import Foundation
import SimuCore

public struct ScenarioConditionsDraft: Equatable, Sendable {
    public let scenarioID: UUID
    public var surfaces: [SurfaceConditionDraft]
    public var windows: [WindowConditionDraft]
    public var ventilation: [VentilationConditionDraft]
    public var representativeDate: String
    public var timeZone: String
    public var outdoorTemperature: PhysicalParameterDraft
    public var outdoorHumidity: PhysicalParameterDraft
    public var indoorHumidity: PhysicalParameterDraft
    public var currency: String
    public var tariffs: [TariffConditionDraft]
    public var quotes: [QuoteConditionDraft]
    private let original: Scenario
    private let geometry: ProjectGeometry
    private var deletedRecords: Set<ConditionRepairLocation> = []

    public init(project: ProjectDocument, scenarioID: UUID) throws {
        guard let scenario = project.scenarios.first(where: { $0.id == scenarioID }) else {
            throw ConditionsDraftError.missingScenario
        }
        self.scenarioID = scenarioID; original = scenario; geometry = project.geometry
        let input = scenario.inputs
        surfaces = project.geometry.rooms.flatMap { room in room.surfaces.map { surface in
            let index = input.envelope.surfaces.firstIndex { $0.surfaceID == surface.id }
            return SurfaceConditionDraft(surface: surface, roomName: room.name,
                                  condition: index.map { input.envelope.surfaces[$0] }, recordIndex: index)
        } }
        windows = project.geometry.rooms.flatMap { room in room.openings.filter { $0.kind == .window }.map { opening in
            let index = input.envelope.windows.firstIndex { $0.openingID == opening.id }
            return WindowConditionDraft(openingID: opening.id, roomName: room.name,
                                 condition: index.map { input.envelope.windows[$0] }, recordIndex: index)
        } }
        ventilation = project.geometry.rooms.map { room in
            let index = input.ventilation.firstIndex { $0.roomID == room.id }
            return VentilationConditionDraft(room: room, condition: index.map { input.ventilation[$0] }, recordIndex: index)
        }
        representativeDate = input.environment.representativeDate ?? ""
        timeZone = input.environment.timeZone ?? ""
        outdoorTemperature = .init(input.environment.outdoorTemperature)
        outdoorHumidity = .init(input.environment.outdoorHumidity)
        indoorHumidity = .init(input.environment.indoorHumidity)
        currency = scenario.evaluation.cost.currency ?? ""
        tariffs = scenario.evaluation.cost.tariffs.enumerated().map { TariffConditionDraft(index: $0.offset, tariff: $0.element) }
        quotes = scenario.evaluation.cost.quotes.map(QuoteConditionDraft.init)
    }

    /// Retains original ordering and all unselected records. Repair deletions are explicit.
    public func applying(to project: ProjectDocument) throws -> ProjectDocument {
        guard let index = project.scenarios.firstIndex(where: { $0.id == scenarioID }) else {
            throw ConditionsDraftError.missingScenario
        }
        var candidate = project
        var input = project.scenarios[index].inputs
        guard project.geometry == geometry, input.envelope == original.inputs.envelope, input.ventilation == original.inputs.ventilation else {
            throw ConditionsDraftError.staleConditions
        }
        input.envelope.surfaces = try original.inputs.envelope.surfaces.enumerated().compactMap { index, record in
            guard !deletedRecords.contains(.surface(index)) else { return nil }
            if let draft = surfaces.first(where: { $0.recordIndex == index }) {
                return draft.isEnabled ? try draft.condition() : nil
            }
            return record
        } + (try surfaces.filter { $0.recordIndex == nil && $0.isEnabled }.map { try $0.condition() })
        input.envelope.windows = try original.inputs.envelope.windows.enumerated().compactMap { index, record in
            guard !deletedRecords.contains(.window(index)) else { return nil }
            if let draft = windows.first(where: { $0.recordIndex == index }) {
                return draft.isEnabled ? try draft.condition() : nil
            }
            return record
        } + (try windows.filter { $0.recordIndex == nil && $0.isEnabled }.map { try $0.condition() })
        input.ventilation = try original.inputs.ventilation.enumerated().compactMap { index, record in
            guard !deletedRecords.contains(.ventilation(index)) else { return nil }
            let deletions = openingDeletions(parent: index)
            if let draft = ventilation.first(where: { $0.recordIndex == index }) {
                return draft.isEnabled ? try draft.condition(deletedOpenings: deletions) : nil
            }
            var preserved = record
            preserved.openings = record.openings.enumerated().compactMap { deletions.contains($0.offset) ? nil : $0.element }
            return preserved
        } + (try ventilation.filter { $0.recordIndex == nil && $0.isEnabled }.map { try $0.condition() })
        input.environment.representativeDate = preservedText(representativeDate, original.inputs.environment.representativeDate)
        input.environment.timeZone = preservedText(timeZone, original.inputs.environment.timeZone)
        // Weather is edited by the document asset importer, never by invented paths.
        input.environment.outdoorTemperature = try preservedParameter(outdoorTemperature, original: original.inputs.environment.outdoorTemperature, range: .init(minimum: -273.15))
        input.environment.outdoorHumidity = try preservedParameter(outdoorHumidity, original: original.inputs.environment.outdoorHumidity, range: .fraction)
        input.environment.indoorHumidity = try preservedParameter(indoorHumidity, original: original.inputs.environment.indoorHumidity, range: .fraction)
        candidate.scenarios[index].inputs = input
        candidate.scenarios[index].evaluation.cost = .init(currency: preservedText(currency, original.evaluation.cost.currency),
            tariffs: try tariffs.map { try $0.tariff() }, quotes: try quotes.map { try $0.quote() })
        return candidate
    }
    public var hasChanges: Bool {
        // Invalid intermediate text is dirty even though it cannot enter the wire model.
        (try? applying(to: .init(id: UUID(), name: "", spaceType: .office, geometry: geometry, scenarios: [original])).scenarios[0]) != original
    }

    /// Records are addressed by their original array position, never by a reference that may repeat.
    public var repairItems: [ConditionRepairItem] {
        var result: [ConditionRepairItem] = []
        let validSurfaces = Set(geometry.rooms.flatMap(\.surfaces).map(\.id))
        let validWindows = Set(geometry.rooms.flatMap(\.openings).filter { $0.kind == .window }.map(\.id))
        let validRooms = Set(geometry.rooms.map(\.id))
        let surfaceCounts = Dictionary(grouping: original.inputs.envelope.surfaces, by: \.surfaceID).mapValues(\.count)
        let windowCounts = Dictionary(grouping: original.inputs.envelope.windows, by: \.openingID).mapValues(\.count)
        let ventilationCounts = Dictionary(grouping: original.inputs.ventilation, by: \.roomID).mapValues(\.count)
        for (index, record) in original.inputs.envelope.surfaces.enumerated() {
            var reasons: [String] = []
            if !validSurfaces.contains(record.surfaceID) { reasons.append("表面引用不存在") }
            if surfaceCounts[record.surfaceID, default: 0] > 1 { reasons.append("同一表面有重复配置") }
            let conflict = Self.boundaryConflict(record.boundary)
            if conflict { reasons.append("热边界模式与温度/热流字段冲突") }
            if !reasons.isEmpty {
                result.append(repairItem(.surface(index), reference: record.surfaceID, title: "表面配置 \(index + 1)",
                                         reasons: reasons, record: record, canSelect: validSurfaces.contains(record.surfaceID), canNormalize: conflict))
            }
        }
        for (index, record) in original.inputs.envelope.windows.enumerated() {
            var reasons: [String] = []
            if !validWindows.contains(record.openingID) { reasons.append("引用不存在，或引用的对象不是窗") }
            if windowCounts[record.openingID, default: 0] > 1 { reasons.append("同一窗有重复配置") }
            if !reasons.isEmpty {
                result.append(repairItem(.window(index), reference: record.openingID, title: "窗配置 \(index + 1)",
                                         reasons: reasons, record: record, canSelect: validWindows.contains(record.openingID)))
            }
        }
        for (index, record) in original.inputs.ventilation.enumerated() {
            var reasons: [String] = []
            if !validRooms.contains(record.roomID) { reasons.append("房间引用不存在") }
            if ventilationCounts[record.roomID, default: 0] > 1 { reasons.append("同一房间有重复通风配置") }
            if !reasons.isEmpty {
                result.append(repairItem(.ventilation(index), reference: record.roomID, title: "通风配置 \(index + 1)",
                                         reasons: reasons, record: record, canSelect: validRooms.contains(record.roomID)))
            }
            let validOpenings = Set(geometry.rooms.filter { $0.id == record.roomID }.flatMap(\.openings).map(\.id))
            let openingCounts = Dictionary(grouping: record.openings, by: \.openingID).mapValues(\.count)
            for (openingIndex, state) in record.openings.enumerated() where !deletedRecords.contains(.ventilation(index)) {
                var openingReasons: [String] = []
                if !validOpenings.contains(state.openingID) { openingReasons.append("开口不属于该房间，或已不存在") }
                if openingCounts[state.openingID, default: 0] > 1 { openingReasons.append("同一开口有重复状态") }
                if !openingReasons.isEmpty {
                    result.append(repairItem(.opening(index, openingIndex), reference: state.openingID,
                        title: "通风 \(index + 1) · 开口状态 \(openingIndex + 1)", reasons: openingReasons, record: state,
                        canSelect: validOpenings.contains(state.openingID)))
                }
            }
        }
        return result
    }

    public mutating func deleteRepairRecord(_ location: ConditionRepairLocation) throws {
        guard repairItems.contains(where: { $0.location == location }) else { throw ConditionsDraftError.missingRecord }
        deletedRecords.insert(location)
        switch location {
        case .surface(let index):
            if let row = surfaces.firstIndex(where: { $0.recordIndex == index }) {
                let reference = surfaces[row].id
                let replacement = original.inputs.envelope.surfaces.indices.first { original.inputs.envelope.surfaces[$0].surfaceID == reference && !deletedRecords.contains(.surface($0)) }
                surfaces[row] = surfaceDraft(reference: reference, recordIndex: replacement)
            }
        case .window(let index):
            if let row = windows.firstIndex(where: { $0.recordIndex == index }) {
                let reference = windows[row].id
                let replacement = original.inputs.envelope.windows.indices.first { original.inputs.envelope.windows[$0].openingID == reference && !deletedRecords.contains(.window($0)) }
                windows[row] = windowDraft(reference: reference, recordIndex: replacement)
            }
        case .ventilation(let index):
            if let row = ventilation.firstIndex(where: { $0.recordIndex == index }) {
                let reference = ventilation[row].id
                let replacement = original.inputs.ventilation.indices.first { original.inputs.ventilation[$0].roomID == reference && !deletedRecords.contains(.ventilation($0)) }
                ventilation[row] = ventilationDraft(reference: reference, recordIndex: replacement)
            }
        case .opening(let parent, let index):
            if let row = ventilation.firstIndex(where: { $0.recordIndex == parent }) {
                ventilation[row].removeSelectedOpeningRecord(index, deleted: openingDeletions(parent: parent))
            }
        }
    }

    public mutating func restoreRepairRecord(_ location: ConditionRepairLocation) {
        guard repairItems.contains(where: { $0.location == location }) else { return }
        deletedRecords.remove(location)
        switch location {
        case .surface(let index):
            let reference = original.inputs.envelope.surfaces[index].surfaceID
            if surfaces.contains(where: { $0.id == reference && $0.recordIndex == nil && $0 == surfaceDraft(reference: reference, recordIndex: nil) }) { try? selectRepairRecord(location) }
        case .window(let index):
            let reference = original.inputs.envelope.windows[index].openingID
            if windows.contains(where: { $0.id == reference && $0.recordIndex == nil && $0 == windowDraft(reference: reference, recordIndex: nil) }) { try? selectRepairRecord(location) }
        case .ventilation(let index):
            let reference = original.inputs.ventilation[index].roomID
            if ventilation.contains(where: { $0.id == reference && $0.recordIndex == nil && $0 == ventilationDraft(reference: reference, recordIndex: nil) }) { try? selectRepairRecord(location) }
        case .opening(let parent, let index):
            if let row = ventilation.firstIndex(where: { $0.recordIndex == parent }),
               ventilation[row].openings.contains(where: { $0.id == original.inputs.ventilation[parent].openings[index].openingID && $0.recordIndex == nil && $0 == OpeningConditionDraft(openingID: $0.id, kind: $0.kind, state: nil) }) {
                ventilation[row].selectOpeningRecord(index)
            }
        }
        // Other original records are retained even while a different record is selected.
    }

    public mutating func selectRepairRecord(_ location: ConditionRepairLocation) throws {
        guard let item = repairItems.first(where: { $0.location == location }), item.canSelect, !item.isDeleted else {
            throw ConditionsDraftError.missingRecord
        }
        switch location {
        case .surface(let index):
            let reference = original.inputs.envelope.surfaces[index].surfaceID
            guard let row = surfaces.firstIndex(where: { $0.id == reference }) else { throw ConditionsDraftError.missingRecord }
            surfaces[row] = surfaceDraft(reference: reference, recordIndex: index)
        case .window(let index):
            let reference = original.inputs.envelope.windows[index].openingID
            guard let row = windows.firstIndex(where: { $0.id == reference }) else { throw ConditionsDraftError.missingRecord }
            windows[row] = windowDraft(reference: reference, recordIndex: index)
        case .ventilation(let index):
            let reference = original.inputs.ventilation[index].roomID
            guard let row = ventilation.firstIndex(where: { $0.id == reference }) else { throw ConditionsDraftError.missingRecord }
            ventilation[row] = ventilationDraft(reference: reference, recordIndex: index)
        case .opening(let parent, let index):
            let reference = original.inputs.ventilation[parent].roomID
            guard let row = ventilation.firstIndex(where: { $0.id == reference }) else { throw ConditionsDraftError.missingRecord }
            if ventilation[row].recordIndex != parent { ventilation[row] = ventilationDraft(reference: reference, recordIndex: parent) }
            ventilation[row].selectOpeningRecord(index)
        }
    }

    public mutating func normalizeBoundary(_ location: ConditionRepairLocation) throws {
        guard case .surface(let index) = location else { throw ConditionsDraftError.missingRecord }
        if !isSelected(location) { try selectRepairRecord(location) }
        guard let row = surfaces.firstIndex(where: { $0.recordIndex == index }) else { throw ConditionsDraftError.missingRecord }
        surfaces[row].normalizeBoundary = true
    }

    public func isSelected(_ location: ConditionRepairLocation) -> Bool {
        switch location {
        case .surface(let index): surfaces.contains { $0.recordIndex == index }
        case .window(let index): windows.contains { $0.recordIndex == index }
        case .ventilation(let index): ventilation.contains { $0.recordIndex == index }
        case .opening(let parent, let index): ventilation.contains { $0.recordIndex == parent && $0.openings.contains { $0.recordIndex == index } }
        }
    }

    public func selectionWouldDiscardEdits(_ location: ConditionRepairLocation) -> Bool {
        guard repairItems.contains(where: { $0.location == location }) else { return false }
        switch location {
        case .surface(let index):
            let reference = original.inputs.envelope.surfaces[index].surfaceID
            guard let row = surfaces.first(where: { $0.id == reference }) else { return false }
            return row != surfaceDraft(reference: reference, recordIndex: row.recordIndex)
        case .window(let index):
            let reference = original.inputs.envelope.windows[index].openingID
            guard let row = windows.first(where: { $0.id == reference }) else { return false }
            return row != windowDraft(reference: reference, recordIndex: row.recordIndex)
        case .ventilation(let index):
            let reference = original.inputs.ventilation[index].roomID
            guard let row = ventilation.first(where: { $0.id == reference }) else { return false }
            return row != ventilationDraft(reference: reference, recordIndex: row.recordIndex)
        case .opening(let parent, let index):
            let reference = original.inputs.ventilation[parent].roomID
            guard let room = ventilation.first(where: { $0.id == reference }) else { return false }
            if room.recordIndex != parent { return room != ventilationDraft(reference: reference, recordIndex: room.recordIndex) }
            return room.openingSelectionWouldDiscardEdits(index)
        }
    }

    public func boundaryNormalizationScheduled(_ location: ConditionRepairLocation) -> Bool {
        guard case .surface(let index) = location else { return false }
        return surfaces.contains { $0.recordIndex == index && $0.normalizeBoundary }
    }

    private func surfaceDraft(reference: UUID, recordIndex: Int?) -> SurfaceConditionDraft {
        let room = geometry.rooms.first { $0.surfaces.contains { $0.id == reference } }!
        return .init(surface: room.surfaces.first { $0.id == reference }!, roomName: room.name,
                     condition: recordIndex.map { original.inputs.envelope.surfaces[$0] }, recordIndex: recordIndex)
    }
    private func windowDraft(reference: UUID, recordIndex: Int?) -> WindowConditionDraft {
        let room = geometry.rooms.first { $0.openings.contains { $0.id == reference } }!
        return .init(openingID: reference, roomName: room.name, condition: recordIndex.map { original.inputs.envelope.windows[$0] }, recordIndex: recordIndex)
    }
    private func ventilationDraft(reference: UUID, recordIndex: Int?) -> VentilationConditionDraft {
        .init(room: geometry.rooms.first { $0.id == reference }!, condition: recordIndex.map { original.inputs.ventilation[$0] }, recordIndex: recordIndex)
    }
    private func openingDeletions(parent: Int) -> Set<Int> {
        Set(deletedRecords.compactMap { if case .opening(let p, let index) = $0, p == parent { return index }; return nil })
    }
    private func repairItem<T: Encodable>(_ location: ConditionRepairLocation, reference: UUID, title: String,
            reasons: [String], record: T, canSelect: Bool, canNormalize: Bool = false) -> ConditionRepairItem {
        .init(location: location, referenceID: reference, title: title, reasons: reasons,
              originalJSON: (try? JSONTreeCoding.encode(record).text()) ?? "无法显示原始值", canSelect: canSelect,
              canNormalizeBoundary: canNormalize, isDeleted: deletedRecords.contains(location), isSelected: isSelected(location))
    }
    private static func boundaryConflict(_ boundary: ThermalBoundary) -> Bool {
        switch boundary.mode {
        case .temperature: boundary.temperature == nil || boundary.heatFlux != nil
        case .heatFlux: boundary.heatFlux == nil || boundary.temperature != nil
        case .fromL1: boundary.temperature != nil || boundary.heatFlux != nil
        }
    }
}

public enum ConditionRepairLocation: Hashable, Sendable {
    case surface(Int), window(Int), ventilation(Int), opening(Int, Int)
}
public struct ConditionRepairItem: Identifiable, Equatable, Sendable {
    public var id: ConditionRepairLocation { location }
    public let location: ConditionRepairLocation
    public let referenceID: UUID
    public let title: String
    public let reasons: [String]
    public let originalJSON: String
    public let canSelect: Bool
    public let canNormalizeBoundary: Bool
    public let isDeleted: Bool
    public let isSelected: Bool
}

private func preservedParameter<Q: QuantityTag>(_ draft: PhysicalParameterDraft, original: PhysicalParameter<Q>?,
                                                range: ParameterValueRange = .unbounded) throws -> PhysicalParameter<Q> {
    if let original, draft == PhysicalParameterDraft(original) { return original }
    return try draft.parameter(as: Q.self, range: range)
}
private func preservedText(_ text: String, _ original: String?) -> String? {
    if text == (original ?? "") { return original }
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
}

public struct SurfaceConditionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let face: SurfaceFace
    public let roomName: String
    public var isEnabled: Bool
    public var exposure: Exposure
    public var mode: BoundaryMode
    public var uValue: PhysicalParameterDraft
    public var temperature: PhysicalParameterDraft
    public var heatFlux: PhysicalParameterDraft
    public let recordIndex: Int?
    public var normalizeBoundary = false
    private let original: SurfaceCondition?
    init(surface: Surface, roomName: String, condition: SurfaceCondition?, recordIndex: Int? = nil) {
        original = condition; self.recordIndex = recordIndex
        id = surface.id; face = surface.face; self.roomName = roomName
        isEnabled = condition != nil
        exposure = condition?.exposure ?? .outdoors
        mode = condition?.boundary.mode ?? .fromL1
        uValue = .init(condition?.uValue ?? .unknown(reason: "围护传热系数待提供"))
        temperature = .init(condition?.boundary.temperature ?? .unknown(reason: "表面温度待提供"))
        heatFlux = .init(condition?.boundary.heatFlux ?? .unknown(reason: "表面热流待提供"))
    }
    func condition() throws -> SurfaceCondition {
        var boundary: ThermalBoundary
        if let original, mode == original.boundary.mode, !normalizeBoundary {
            boundary = original.boundary
            if mode == .temperature, temperature != PhysicalParameterDraft(original.boundary.temperature ?? .unknown(reason: "表面温度待提供")) {
                boundary.temperature = try preservedParameter(temperature, original: original.boundary.temperature, range: .init(minimum: -273.15))
            } else if mode == .heatFlux, heatFlux != PhysicalParameterDraft(original.boundary.heatFlux ?? .unknown(reason: "表面热流待提供")) {
                boundary.heatFlux = try preservedParameter(heatFlux, original: original.boundary.heatFlux)
            }
        } else { switch mode {
        case .fromL1: boundary = .init(mode: .fromL1)
        case .temperature: boundary = .init(mode: .temperature,
            temperature: try temperature.parameter(as: TemperatureTag.self, range: .init(minimum: -273.15)))
        case .heatFlux: boundary = .init(mode: .heatFlux, heatFlux: try heatFlux.parameter(as: HeatFluxTag.self))
        } }
        return .init(surfaceID: id, exposure: exposure,
                     uValue: try preservedParameter(uValue, original: original?.uValue, range: .nonnegative), boundary: boundary)
    }
}
public struct WindowConditionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let roomName: String
    public var isEnabled: Bool
    public var uValue: PhysicalParameterDraft
    public var shgc: PhysicalParameterDraft
    public var shadingFactor: PhysicalParameterDraft
    public let recordIndex: Int?
    private let original: WindowCondition?
    init(openingID: UUID, roomName: String, condition: WindowCondition?, recordIndex: Int? = nil) {
        original = condition; self.recordIndex = recordIndex
        id = openingID; self.roomName = roomName; isEnabled = condition != nil
        uValue = .init(condition?.uValue ?? .unknown(reason: "窗传热系数待提供"))
        shgc = .init(condition?.shgc ?? .unknown(reason: "太阳得热系数待提供"))
        shadingFactor = .init(condition?.shadingFactor ?? .unknown(reason: "遮阳条件待提供"))
    }
    func condition() throws -> WindowCondition {
        .init(openingID: id, uValue: try preservedParameter(uValue, original: original?.uValue, range: .nonnegative),
              shgc: try preservedParameter(shgc, original: original?.shgc, range: .fraction),
              shadingFactor: try preservedParameter(shadingFactor, original: original?.shadingFactor, range: .fraction))
    }
}
public struct VentilationConditionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let roomName: String
    public var isEnabled: Bool
    public var outdoorAir: PhysicalParameterDraft
    public var exhaustAir: PhysicalParameterDraft
    public var infiltration: PhysicalParameterDraft
    public var exfiltration: PhysicalParameterDraft
    public var density: PhysicalParameterDraft
    public var openings: [OpeningConditionDraft]
    public let recordIndex: Int?
    private let original: RoomVentilation?
    init(room: Room, condition: RoomVentilation?, recordIndex: Int? = nil) {
        original = condition; self.recordIndex = recordIndex
        id = room.id; roomName = room.name; isEnabled = condition != nil
        outdoorAir = .init(condition?.outdoorAir ?? .unknown(reason: "室外新风量待提供"))
        exhaustAir = .init(condition?.exhaustAir ?? .unknown(reason: "室外排风量待提供"))
        infiltration = .init(condition?.infiltration ?? .unknown(reason: "渗风量待提供"))
        exfiltration = .init(condition?.exfiltration ?? .unknown(reason: "外泄风量待提供"))
        density = .init(condition?.density ?? .unknown(reason: "交换空气密度待提供"))
        openings = room.openings.map { opening in
            let index = condition?.openings.firstIndex { $0.openingID == opening.id }
            return .init(openingID: opening.id, kind: opening.kind,
                  state: index.map { condition!.openings[$0] }, recordIndex: index)
        }
    }
    func condition(deletedOpenings: Set<Int> = []) throws -> RoomVentilation {
        let states = try (original?.openings ?? []).enumerated().compactMap { index, state -> OpeningState? in
            guard !deletedOpenings.contains(index) else { return nil }
            if let draft = openings.first(where: { $0.recordIndex == index }) { return draft.isConfigured ? try draft.state() : nil }
            return state
        } + (try openings.filter { $0.recordIndex == nil && $0.isConfigured }.map { try $0.state() })
        return .init(roomID: id, outdoorAir: try preservedParameter(outdoorAir, original: original?.outdoorAir, range: .nonnegative),
              exhaustAir: try preservedParameter(exhaustAir, original: original?.exhaustAir, range: .nonnegative),
              infiltration: try preservedParameter(infiltration, original: original?.infiltration, range: .nonnegative),
              exfiltration: try preservedParameter(exfiltration, original: original?.exfiltration, range: .nonnegative),
              density: try preservedParameter(density, original: original?.density, range: .positive), openings: states)
    }
    mutating func selectOpeningRecord(_ index: Int) {
        guard let original, original.openings.indices.contains(index),
              let row = openings.firstIndex(where: { $0.id == original.openings[index].openingID }) else { return }
        openings[row] = .init(openingID: openings[row].id, kind: openings[row].kind, state: original.openings[index], recordIndex: index)
    }
    mutating func removeSelectedOpeningRecord(_ index: Int, deleted: Set<Int>) {
        guard let row = openings.firstIndex(where: { $0.recordIndex == index }), let original else { return }
        let replacement = original.openings.indices.first { original.openings[$0].openingID == openings[row].id && !deleted.contains($0) }
        if let replacement { selectOpeningRecord(replacement) }
        else { openings[row] = .init(openingID: openings[row].id, kind: openings[row].kind, state: nil) }
    }
    func openingSelectionWouldDiscardEdits(_ index: Int) -> Bool {
        guard let original, original.openings.indices.contains(index),
              let row = openings.first(where: { $0.id == original.openings[index].openingID }) else { return false }
        let record = row.recordIndex.map { original.openings[$0] }
        return row != OpeningConditionDraft(openingID: row.id, kind: row.kind, state: record, recordIndex: row.recordIndex)
    }
}
public struct OpeningConditionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: OpeningKind
    public var openFraction: PhysicalParameterDraft
    public var isConfigured: Bool
    public let recordIndex: Int?
    private let original: OpeningState?
    init(openingID: UUID, kind: OpeningKind, state: OpeningState?, recordIndex: Int? = nil) {
        original = state; self.recordIndex = recordIndex; isConfigured = state != nil
        id = openingID; self.kind = kind
        openFraction = .init(state?.openFraction ?? .unknown(reason: "门窗开启比例待提供"))
    }
    func state() throws -> OpeningState {
        .init(openingID: id, openFraction: try preservedParameter(openFraction, original: original?.openFraction, range: .fraction))
    }
}
public struct TariffConditionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var startMinute: String
    public var endMinute: String
    public var rate: PhysicalParameterDraft
    private let original: TariffInterval?
    init(index: Int = 0, tariff: TariffInterval? = nil) {
        original = tariff; id = UUID(); startMinute = String(tariff?.startMinute ?? 0); endMinute = String(tariff?.endMinute ?? 1440)
        rate = .init(tariff?.rate ?? .unknown(reason: "电价来源待提供"))
    }
    func tariff() throws -> TariffInterval {
        if let original, startMinute == String(original.startMinute), endMinute == String(original.endMinute), rate == PhysicalParameterDraft(original.rate) { return original }
        guard let start = Int(startMinute), let end = Int(endMinute), start >= 0, start < end, end <= 1440 else {
            throw ConditionsDraftError.interval
        }
        return .init(startMinute: start, endMinute: end, rate: try rate.parameter(as: EnergyRateTag.self, range: .nonnegative))
    }
}
public struct QuoteConditionDraft: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let quoteID: UUID
    public var amount: PhysicalParameterDraft
    private let original: Quote?
    init(_ quote: Quote? = nil) {
        original = quote; id = UUID(); quoteID = quote?.id ?? UUID(); amount = .init(quote?.amount ?? .unknown(reason: "报价待提供"))
    }
    func quote() throws -> Quote { .init(id: quoteID, amount: try preservedParameter(amount, original: original?.amount, range: .nonnegative)) }
}
public enum ConditionsDraftError: LocalizedError {
    case interval, missingScenario, missingRecord, staleConditions
    public var errorDescription: String? {
        switch self {
        case .interval: "电价时段使用代表日本地时间的分钟数：0 ≤ 起点 < 终点 ≤ 1440。"
        case .missingScenario: "找不到所选方案，请重新选择。"
        case .missingRecord: "该配置记录已不存在、已删除或不能编辑；请重新选择。"
        case .staleConditions: "方案条件在打开表单后已改变；请关闭并重新打开以保留最新输入。"
        }
    }
}
