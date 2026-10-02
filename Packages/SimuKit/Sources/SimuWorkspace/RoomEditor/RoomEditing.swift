import Foundation
import SimuCore

public enum RoomEditingError: LocalizedError, Equatable {
    case missingRoom, missingOpening, unsupportedShape, nameRequired
    case invalid([ValidationIssue])
    public var errorDescription: String? {
        switch self {
        case .missingRoom: "房间已经不存在，请重新选择。"
        case .missingOpening: "门窗已经不存在，请重新选择。"
        case .unsupportedShape: "此房间类型无法在矩形编辑器中修改；原始数据将保留。"
        case .nameRequired: "请填写项目和房间名称。"
        case .invalid(let issues): issues.map(RoomIssuePresentation.message).joined(separator: "\n")
        }
    }
}

/// Shared geometry edits validate every scenario before committing a single value transaction.
public enum RoomEditing {
    public static func createProject(name: String, spaceType: SpaceType, room: Room,
                                     projectID: UUID = UUID(), scenarioID: UUID = UUID(),
                                     registry: ModelRegistry = .builtIn) throws -> ProjectDocument {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RoomEditingError.nameRequired }
        let reason = "尚未录入；请提供依据或明确假设"
        let windows = room.openings.filter { $0.kind == .window }.map(unknownWindow)
        let ventilation = RoomVentilation(roomID: room.id, outdoorAir: .unknown(reason: reason),
            exhaustAir: .unknown(reason: reason), infiltration: .unknown(reason: reason),
            exfiltration: .unknown(reason: reason), density: .unknown(reason: reason),
            openings: room.openings.map { .init(openingID: $0.id, openFraction: .unknown(reason: reason)) })
        // Exposure and boundary mode have no unknown representation or source metadata in v2.
        // Leave these assignments absent until the user explicitly configures actual boundaries.
        let inputs = ScenarioInputs(usage: .init(), envelope: .init(windows: windows),
            ventilation: [ventilation], environment: .init(outdoorTemperature: .unknown(reason: reason),
            outdoorHumidity: .unknown(reason: reason), indoorHumidity: .unknown(reason: reason)))
        let project = ProjectDocument(id: projectID, name: name, spaceType: spaceType,
            geometry: .init(rooms: [room]), scenarios: [.init(id: scenarioID, name: "基准方案",
            inputs: inputs, evaluation: .init(cost: .init()))])
        try check(project, registry: registry)
        return project
    }

    public static func updateRoom(in project: inout ProjectDocument, roomID: UUID, name: String,
                                  dimensions: Dimensions3D, northAngle: Angle,
                                  registry: ModelRegistry = .builtIn) throws {
        var candidate = project
        let index = try roomIndex(candidate, roomID)
        guard try candidate.geometry.rooms[index].shape.resolved(as: RectangularRoom.self, registry: registry) != nil else { throw RoomEditingError.unsupportedShape }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RoomEditingError.nameRequired }
        candidate.geometry.rooms[index].name = name
        candidate.geometry.rooms[index].shape = try ExtensionRecord(RectangularRoom(dimensions: dimensions))
        candidate.geometry.rooms[index].northAngle = northAngle
        try check(candidate, previous: project, registry: registry)
        project = candidate
    }

    public static func addOpening(in project: inout ProjectDocument, roomID: UUID, opening: Opening,
                                   registry: ModelRegistry = .builtIn) throws {
        var candidate = project
        let index = try roomIndex(candidate, roomID)
        candidate.geometry.rooms[index].openings.append(opening)
        maintainOpeningReferences(in: &candidate, roomID: roomID, opening: opening)
        try check(candidate, previous: project, registry: registry)
        project = candidate
    }

    public static func updateOpening(in project: inout ProjectDocument, roomID: UUID, opening: Opening,
                                      registry: ModelRegistry = .builtIn) throws {
        var candidate = project
        let index = try roomIndex(candidate, roomID)
        guard let openingIndex = candidate.geometry.rooms[index].openings.firstIndex(where: { $0.id == opening.id }) else { throw RoomEditingError.missingOpening }
        candidate.geometry.rooms[index].openings[openingIndex] = opening
        maintainOpeningReferences(in: &candidate, roomID: roomID, opening: opening)
        try check(candidate, previous: project, registry: registry)
        project = candidate
    }

    public static func deleteOpening(in project: inout ProjectDocument, roomID: UUID, openingID: UUID,
                                      registry: ModelRegistry = .builtIn) throws {
        var candidate = project
        let index = try roomIndex(candidate, roomID)
        guard candidate.geometry.rooms[index].openings.contains(where: { $0.id == openingID }) else { throw RoomEditingError.missingOpening }
        candidate.geometry.rooms[index].openings.removeAll { $0.id == openingID }
        for i in candidate.scenarios.indices {
            candidate.scenarios[i].inputs.envelope.windows.removeAll { $0.openingID == openingID }
            for j in candidate.scenarios[i].inputs.ventilation.indices {
                candidate.scenarios[i].inputs.ventilation[j].openings.removeAll { $0.openingID == openingID }
            }
        }
        try check(candidate, previous: project, registry: registry)
        project = candidate
    }

    private static func roomIndex(_ project: ProjectDocument, _ id: UUID) throws -> Int {
        guard let index = project.geometry.rooms.firstIndex(where: { $0.id == id }) else { throw RoomEditingError.missingRoom }
        return index
    }
    private static func check(_ project: ProjectDocument, previous: ProjectDocument? = nil, registry: ModelRegistry) throws {
        let issues = try ProjectValidator().validate(project, registry: registry).issues.filter { $0.blocks.contains(.projectIntegrity) }
        guard let previous else {
            if !issues.isEmpty { throw RoomEditingError.invalid(issues) }
            return
        }
        // Preserve existing imported errors so users can repair them one object at a time.
        // Numeric indices are intentionally omitted: removing another item changes array indices,
        // but an issue's stable entity and field remain the same.
        let previousIssues = try ProjectValidator().validate(previous, registry: registry).issues.filter { $0.blocks.contains(.projectIntegrity) }
        var remaining = Dictionary(grouping: previousIssues, by: { IntegrityIssueSignature($0, project: previous) }).mapValues(\.count)
        let newIssues = issues.filter { issue in
            let signature = IntegrityIssueSignature(issue, project: project)
            if let count = remaining[signature], count > 0 {
                remaining[signature] = count - 1
                return false
            }
            return true
        }
        if !newIssues.isEmpty { throw RoomEditingError.invalid(newIssues) }
    }
    private static func unknownWindow(_ opening: Opening) -> WindowCondition {
        let reason = "新增窗尚未配置；请提供窗参数依据"
        return .init(openingID: opening.id, uValue: .unknown(reason: reason), shgc: .unknown(reason: reason), shadingFactor: .unknown(reason: reason))
    }
    private static func maintainOpeningReferences(in project: inout ProjectDocument, roomID: UUID, opening: Opening) {
        for i in project.scenarios.indices {
            if opening.kind == .door {
                project.scenarios[i].inputs.envelope.windows.removeAll { $0.openingID == opening.id }
            } else if !project.scenarios[i].inputs.envelope.windows.contains(where: { $0.openingID == opening.id }) {
                project.scenarios[i].inputs.envelope.windows.append(unknownWindow(opening))
            }
            for j in project.scenarios[i].inputs.ventilation.indices where project.scenarios[i].inputs.ventilation[j].roomID == roomID {
                if !project.scenarios[i].inputs.ventilation[j].openings.contains(where: { $0.openingID == opening.id }) {
                    project.scenarios[i].inputs.ventilation[j].openings.append(.init(openingID: opening.id,
                        openFraction: .unknown(reason: "新增门窗的开启比例尚未录入")))
                }
            }
        }
    }
}

private struct IntegrityIssueSignature: Hashable {
    let code: String
    let entityID: UUID?
    let scenarioID: UUID?
    let fieldPath: String
    init(_ issue: ValidationIssue, project: ProjectDocument) {
        code = issue.code; entityID = issue.entityID
        let components = issue.path.split(separator: "/")
        // Nested object UUIDs may intentionally match across copied scenarios. Their errors must
        // remain in the owning scenario even if an edit changes which scenario has the problem.
        if components.count >= 2, components[0] == "scenarios", let index = Int(components[1]), project.scenarios.indices.contains(index) {
            scenarioID = project.scenarios[index].id
        } else { scenarioID = nil }
        fieldPath = components.filter { Int($0) == nil }.joined(separator: "/")
    }
}

public struct RoomDraft: Equatable, Sendable {
    public let id: UUID
    public let surfaces: [Surface]
    public var name: String
    public var width: PhysicalParameterDraft
    public var depth: PhysicalParameterDraft
    public var height: PhysicalParameterDraft
    public var northAngle: PhysicalParameterDraft
    public init(name: String = "房间") {
        id = UUID(); surfaces = SurfaceFace.allCases.map { .init(id: UUID(), face: $0) }
        self.name = name; width = .init(); depth = .init(); height = .init()
        northAngle = .init(unknownReason: "尚未测量真北方向")
    }
    public init(room: Room, registry: ModelRegistry = .builtIn) throws {
        guard let rectangle = try room.shape.resolved(as: RectangularRoom.self, registry: registry) else { throw RoomEditingError.unsupportedShape }
        id = room.id; surfaces = room.surfaces; name = room.name
        width = .init(rectangle.dimensions.width); depth = .init(rectangle.dimensions.depth)
        height = .init(rectangle.dimensions.height); northAngle = .init(room.northAngle)
    }
    public func dimensions() throws -> Dimensions3D {
        .init(width: try width.parameter(range: .positive), depth: try depth.parameter(range: .positive), height: try height.parameter(range: .positive))
    }
    public func room(openings: [Opening] = []) throws -> Room {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RoomEditingError.nameRequired }
        return .init(id: id, name: name, shape: try ExtensionRecord(RectangularRoom(dimensions: dimensions())),
            northAngle: try northAngle.parameter(range: .northBearing), surfaces: surfaces, openings: openings)
    }
}

public struct OpeningDraft: Equatable, Sendable {
    public let id: UUID
    public var surfaceID: UUID
    public var kind: OpeningKind
    public var offsetU: PhysicalParameterDraft
    public var offsetV: PhysicalParameterDraft
    public var width: PhysicalParameterDraft
    public var height: PhysicalParameterDraft
    public init(surfaceID: UUID, kind: OpeningKind = .window) {
        id = UUID(); self.surfaceID = surfaceID; self.kind = kind
        offsetU = .init(); offsetV = .init(); width = .init(); height = .init()
    }
    public init(opening: Opening) {
        id = opening.id; surfaceID = opening.surfaceID; kind = opening.kind
        offsetU = .init(opening.offsetU); offsetV = .init(opening.offsetV)
        width = .init(opening.width); height = .init(opening.height)
    }
    public func opening() throws -> Opening {
        .init(id: id, surfaceID: surfaceID, kind: kind, offsetU: try offsetU.parameter(range: .nonnegative),
            offsetV: try offsetV.parameter(range: .nonnegative), width: try width.parameter(range: .positive), height: try height.parameter(range: .positive))
    }
}

public enum RoomIssuePresentation {
    public static func message(_ issue: ValidationIssue) -> String {
        let explanation: String
        switch issue.code {
        case "opening_bounds": explanation = "门窗超出所属表面；请修改 U/V 偏移或尺寸。"
        case "opening_overlap": explanation = "同一表面上的门窗相互重叠。"
        case "obstacle_bounds": explanation = "家具超出房间；缩小房间前请调整家具。"
        case "point_bounds": explanation = "座位、采样点、设备或风口超出房间。"
        case "point_in_solid": explanation = "点位进入实体家具。"
        case "parameter_range": explanation = "数值不在允许的物理范围。"
        case "source_required": explanation = "参数缺少来源依据或假设说明。"
        case "uncertainty_bounds": explanation = "不确定性上下界无效。"
        case "dangling_reference": explanation = "对象引用已失效。"
        case "duplicate_id", "duplicate_assignment": explanation = "对象身份或引用重复。"
        default: explanation = issue.message
        }
        return "\(explanation)\n位置：\(issue.path)\(issue.entityID.map { "；对象 \($0.uuidString)" } ?? "")"
    }
    public static func surfaceName(_ face: SurfaceFace) -> String {
        switch face {
        case .xMin: "X 最小墙（U = +Y，V = +Z）"
        case .xMax: "X 最大墙（U = +Y，V = +Z）"
        case .yMin: "Y 最小墙（U = +X，V = +Z）"
        case .yMax: "Y 最大墙（U = +X，V = +Z）"
        case .floor: "地面（U = +X，V = +Y）"
        case .ceiling: "顶面（U = +X，V = +Y）"
        }
    }
}
