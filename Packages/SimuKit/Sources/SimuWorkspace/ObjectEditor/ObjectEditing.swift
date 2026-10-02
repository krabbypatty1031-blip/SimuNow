import Foundation
import SimuCore
import SimuVisualization

public enum ObjectEditingError: Error, LocalizedError, Sendable {
    case missingObject
    case unsupportedShape
    case incompleteRoom
    case staleDraft
    case invalid([ValidationIssue])
    public var errorDescription: String? {
        switch self {
        case .missingObject: "找不到所选对象；请重新选择。"
        case .unsupportedShape: "此类型只能查看，不能用当前编辑器修改。"
        case .incompleteRoom: "请先补齐房间尺寸，再放置对象。"
        case .staleDraft: "项目在编辑期间已改变，当前草稿不能应用。请关闭此表单，再从最新项目重新打开编辑。"
        case .invalid(let issues): issues.map { "\($0.code)：\($0.path)" }.joined(separator: "\n")
        }
    }
}

/// Commands are atomic: validation uses a copy, and a failed edit leaves the input untouched.
/// Shared furniture is checked against the points of every scenario.
public enum ObjectEditing {
    /// Editors freeze their starting value; later undo or document updates cannot replay an old form.
    public static func requireCurrentProject(base: ProjectDocument, current: ProjectDocument) throws {
        guard base == current else { throw ObjectEditingError.staleDraft }
    }
    private static func scenarioIndex(_ project: ProjectDocument, _ id: UUID) throws -> Int {
        guard let index = project.scenarios.firstIndex(where: { $0.id == id }) else { throw ProjectDataError.missingScenario(id) }
        return index
    }
    private static func requireRoom(_ project: ProjectDocument, roomID: UUID, registry: ModelRegistry) throws {
        guard let room = project.geometry.rooms.first(where: { $0.id == roomID }),
              let shape = try registry.resolve(category: "room", record: room.shape) as? any GeometryPayload,
              let bounds = shape.geometryBounds(), bounds.size.x > 0, bounds.size.y > 0, bounds.size.z > 0 else {
            throw ObjectEditingError.incompleteRoom
        }
    }
    public static func transaction(_ project: inout ProjectDocument, registry: ModelRegistry = .builtIn,
                                   edit: (inout ProjectDocument) throws -> Void) throws {
        let validator = ProjectValidator()
        let existing = try validator.validate(project, registry: registry).issues.filter { $0.blocks.contains(.projectIntegrity) }
        var remaining = Dictionary(existing.map { (issueSignature($0, in: project), 1) }, uniquingKeysWith: +)
        var candidate = project
        try edit(&candidate)
        let report = try validator.validate(candidate, registry: registry)
        let introduced = report.issues.filter { issue in
            guard issue.blocks.contains(.projectIntegrity) else { return false }
            let signature = issueSignature(issue, in: candidate), count = remaining[signature, default: 0]
            if count > 0 { remaining[signature] = count - 1; return false }
            return true
        }
        guard introduced.isEmpty else { throw ObjectEditingError.invalid(introduced) }
        project = candidate
    }
    private static func issueSignature(_ issue: ValidationIssue, in project: ProjectDocument) -> String {
        let parts = issue.path.split(separator: "/")
        let path = parts.filter { Int($0) == nil }.joined(separator: "/")
        var scope = "shared"
        if parts.count >= 2, parts[0] == "scenarios", let index = Int(parts[1]), project.scenarios.indices.contains(index) {
            scope = project.scenarios[index].id.uuidString
        }
        return scope + "|" + issue.code + "|" + (issue.entityID?.uuidString ?? "") + "|" + path
    }
    public static func upsertFurniture(_ value: Obstacle, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try requireRoom(project, roomID: value.roomID, registry: registry)
        guard try value.shape.resolved(as: BoxObstacle.self, registry: registry) != nil else { throw ObjectEditingError.unsupportedShape }
        if let old = project.geometry.obstacles.first(where: { $0.id == value.id }),
           try old.shape.resolved(as: BoxObstacle.self, registry: registry) == nil { throw ObjectEditingError.unsupportedShape }
        try transaction(&project, registry: registry) { candidate in
            if let i = candidate.geometry.obstacles.firstIndex(where: { $0.id == value.id }) { candidate.geometry.obstacles[i] = value }
            else { candidate.geometry.obstacles.append(value) }
        }
    }
    public static func upsertSeat(_ value: Seat, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try requireRoom(project, roomID: value.roomID, registry: registry)
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            if let i = candidate.scenarios[s].inputs.usage.seats.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.usage.seats[i] = value }
            else { candidate.scenarios[s].inputs.usage.seats.append(value) }
        }
    }
    public static func upsertSeat(_ value: Seat, occupant: Occupant?, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try requireRoom(project, roomID: value.roomID, registry: registry)
        if let occupant, occupant.seatID != value.id { throw ObjectEditingError.missingObject }
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            if let i = candidate.scenarios[s].inputs.usage.seats.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.usage.seats[i] = value }
            else { candidate.scenarios[s].inputs.usage.seats.append(value) }
            if let occupant {
                if let i = candidate.scenarios[s].inputs.usage.occupants.firstIndex(where: { $0.seatID == value.id }) { candidate.scenarios[s].inputs.usage.occupants[i] = occupant }
                else { candidate.scenarios[s].inputs.usage.occupants.append(occupant) }
            } else { candidate.scenarios[s].inputs.usage.occupants.removeAll { $0.seatID == value.id } }
        }
    }
    public static func upsertOccupant(_ value: Occupant, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            if let i = candidate.scenarios[s].inputs.usage.occupants.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.usage.occupants[i] = value }
            else { candidate.scenarios[s].inputs.usage.occupants.append(value) }
        }
    }
    public static func upsertEquipment(_ value: EquipmentGain, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try requireRoom(project, roomID: value.roomID, registry: registry)
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            if let i = candidate.scenarios[s].inputs.usage.equipment.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.usage.equipment[i] = value }
            else { candidate.scenarios[s].inputs.usage.equipment.append(value) }
        }
    }
    public static func upsertDevice(_ value: HVACDevice, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try requireRoom(project, roomID: value.roomID, registry: registry)
        guard try value.definition.resolved(as: SingleSplit.self, registry: registry) != nil else { throw ObjectEditingError.unsupportedShape }
        let s = try scenarioIndex(project, scenarioID)
        if let old = project.scenarios[s].inputs.hvac.first(where: { $0.id == value.id }),
           try old.definition.resolved(as: SingleSplit.self, registry: registry) == nil { throw ObjectEditingError.unsupportedShape }
        try transaction(&project, registry: registry) { candidate in
            if let i = candidate.scenarios[s].inputs.hvac.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.hvac[i] = value }
            else { candidate.scenarios[s].inputs.hvac.append(value) }
        }
    }
    public static func upsertDevice(_ value: HVACDevice, control: Control?, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try requireRoom(project, roomID: value.roomID, registry: registry)
        guard try value.definition.resolved(as: SingleSplit.self, registry: registry) != nil else { throw ObjectEditingError.unsupportedShape }
        let s = try scenarioIndex(project, scenarioID)
        if let old = project.scenarios[s].inputs.hvac.first(where: { $0.id == value.id }),
           try old.definition.resolved(as: SingleSplit.self, registry: registry) == nil { throw ObjectEditingError.unsupportedShape }
        if let control, control.deviceID != value.id { throw ObjectEditingError.missingObject }
        try transaction(&project, registry: registry) { candidate in
            if let i = candidate.scenarios[s].inputs.hvac.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.hvac[i] = value }
            else { candidate.scenarios[s].inputs.hvac.append(value) }
            if let control {
                if let i = candidate.scenarios[s].inputs.controls.firstIndex(where: { $0.deviceID == value.id }) { candidate.scenarios[s].inputs.controls[i] = control }
                else { candidate.scenarios[s].inputs.controls.append(control) }
            } else { candidate.scenarios[s].inputs.controls.removeAll { $0.deviceID == value.id } }
        }
    }
    public static func upsertControl(_ value: Control, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            if let i = candidate.scenarios[s].inputs.controls.firstIndex(where: { $0.id == value.id }) { candidate.scenarios[s].inputs.controls[i] = value }
            else { candidate.scenarios[s].inputs.controls.append(value) }
        }
    }
    /// Seats and their samples move together. A thermostat's sensor does not move with its device.
    public static func move(_ selection: RoomPlanSelection, to position: Position3D, scenarioID: UUID,
                            project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            switch selection.kind {
            case .furniture:
                guard let i = candidate.geometry.obstacles.firstIndex(where: { $0.id == selection.objectID }) else { throw ObjectEditingError.missingObject }
                let old = candidate.geometry.obstacles[i]
                try requireRoom(candidate, roomID: old.roomID, registry: registry)
                guard var box = try old.shape.resolved(as: BoxObstacle.self, registry: registry) else { throw ObjectEditingError.unsupportedShape }
                if box.origin != position { box.origin = position; candidate.geometry.obstacles[i].shape = try ExtensionRecord(box) }
            case .seat:
                guard let i = candidate.scenarios[s].inputs.usage.seats.firstIndex(where: { $0.id == selection.objectID }) else { throw ObjectEditingError.missingObject }
                let seat = candidate.scenarios[s].inputs.usage.seats[i]
                try requireRoom(candidate, roomID: seat.roomID, registry: registry)
                candidate.scenarios[s].inputs.usage.seats[i].position = position
                candidate.scenarios[s].inputs.usage.seats[i].samples = seat.samples.map {
                    .init(id: $0.id, position: translated($0.position, from: seat.position, to: position))
                }
            case .sample:
                guard let i = candidate.scenarios[s].inputs.usage.seats.firstIndex(where: { $0.samples.contains { $0.id == selection.objectID } }),
                      let j = candidate.scenarios[s].inputs.usage.seats[i].samples.firstIndex(where: { $0.id == selection.objectID }) else { throw ObjectEditingError.missingObject }
                try requireRoom(candidate, roomID: candidate.scenarios[s].inputs.usage.seats[i].roomID, registry: registry)
                candidate.scenarios[s].inputs.usage.seats[i].samples[j].position = position
            case .equipment:
                guard let i = candidate.scenarios[s].inputs.usage.equipment.firstIndex(where: { $0.id == selection.objectID }) else { throw ObjectEditingError.missingObject }
                try requireRoom(candidate, roomID: candidate.scenarios[s].inputs.usage.equipment[i].roomID, registry: registry)
                candidate.scenarios[s].inputs.usage.equipment[i].position = position
            case .hvac:
                guard let i = candidate.scenarios[s].inputs.hvac.firstIndex(where: { $0.id == selection.objectID }) else { throw ObjectEditingError.missingObject }
                let device = candidate.scenarios[s].inputs.hvac[i]
                try requireRoom(candidate, roomID: device.roomID, registry: registry)
                guard try device.definition.resolved(as: SingleSplit.self, registry: registry) != nil else { throw ObjectEditingError.unsupportedShape }
                candidate.scenarios[s].inputs.hvac[i].position = position
                candidate.scenarios[s].inputs.hvac[i].ports = device.ports.map {
                    var port = $0; port.position = translated(port.position, from: device.position, to: position); return port
                }
            case .port:
                guard let i = candidate.scenarios[s].inputs.hvac.firstIndex(where: { $0.ports.contains { $0.id == selection.objectID } }),
                      let j = candidate.scenarios[s].inputs.hvac[i].ports.firstIndex(where: { $0.id == selection.objectID }) else { throw ObjectEditingError.missingObject }
                try requireRoom(candidate, roomID: candidate.scenarios[s].inputs.hvac[i].roomID, registry: registry)
                guard try candidate.scenarios[s].inputs.hvac[i].definition.resolved(as: SingleSplit.self, registry: registry) != nil else { throw ObjectEditingError.unsupportedShape }
                candidate.scenarios[s].inputs.hvac[i].ports[j].position = position
            case .control:
                guard let i = candidate.scenarios[s].inputs.controls.firstIndex(where: { $0.id == selection.objectID }),
                      let device = candidate.scenarios[s].inputs.hvac.first(where: { $0.id == candidate.scenarios[s].inputs.controls[i].deviceID }) else { throw ObjectEditingError.missingObject }
                try requireRoom(candidate, roomID: device.roomID, registry: registry)
                candidate.scenarios[s].inputs.controls[i].sensorPosition = position
            }
        }
    }
    public static func delete(_ selection: RoomPlanSelection, scenarioID: UUID, project: inout ProjectDocument, registry: ModelRegistry = .builtIn) throws {
        try transaction(&project, registry: registry) { candidate in
            let s = try scenarioIndex(candidate, scenarioID)
            guard contains(selection, in: candidate, scenarioID: scenarioID) else { throw ObjectEditingError.missingObject }
            switch selection.kind {
            case .furniture: candidate.geometry.obstacles.removeAll { $0.id == selection.objectID }
            case .seat:
                candidate.scenarios[s].inputs.usage.seats.removeAll { $0.id == selection.objectID }
                candidate.scenarios[s].inputs.usage.occupants.removeAll { $0.seatID == selection.objectID }
            case .sample:
                for i in candidate.scenarios[s].inputs.usage.seats.indices { candidate.scenarios[s].inputs.usage.seats[i].samples.removeAll { $0.id == selection.objectID } }
            case .equipment: candidate.scenarios[s].inputs.usage.equipment.removeAll { $0.id == selection.objectID }
            case .hvac:
                candidate.scenarios[s].inputs.hvac.removeAll { $0.id == selection.objectID }
                candidate.scenarios[s].inputs.controls.removeAll { $0.deviceID == selection.objectID }
            case .port:
                for i in candidate.scenarios[s].inputs.hvac.indices { candidate.scenarios[s].inputs.hvac[i].ports.removeAll { $0.id == selection.objectID } }
            case .control: candidate.scenarios[s].inputs.controls.removeAll { $0.id == selection.objectID }
            }
        }
    }
    public static func contains(_ selection: RoomPlanSelection, in project: ProjectDocument, scenarioID: UUID) -> Bool {
        guard let input = project.scenarios.first(where: { $0.id == scenarioID })?.inputs else { return false }
        switch selection.kind {
        case .furniture: return project.geometry.obstacles.contains { $0.id == selection.objectID }
        case .seat: return input.usage.seats.contains { $0.id == selection.objectID }
        case .sample: return input.usage.seats.flatMap(\.samples).contains { $0.id == selection.objectID }
        case .equipment: return input.usage.equipment.contains { $0.id == selection.objectID }
        case .hvac: return input.hvac.contains { $0.id == selection.objectID }
        case .port: return input.hvac.flatMap(\.ports).contains { $0.id == selection.objectID }
        case .control: return input.controls.contains { $0.id == selection.objectID }
        }
    }
    public static func position(of selection: RoomPlanSelection, in project: ProjectDocument, scenarioID: UUID, registry: ModelRegistry = .builtIn) -> Position3D? {
        guard let input = project.scenarios.first(where: { $0.id == scenarioID })?.inputs else { return nil }
        switch selection.kind {
        case .furniture:
            guard let obstacle = project.geometry.obstacles.first(where: { $0.id == selection.objectID }),
                  let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry) else { return nil }
            return box.origin
        case .seat: return input.usage.seats.first { $0.id == selection.objectID }?.position
        case .sample: return input.usage.seats.flatMap(\.samples).first { $0.id == selection.objectID }?.position
        case .equipment: return input.usage.equipment.first { $0.id == selection.objectID }?.position
        case .hvac: return input.hvac.first { $0.id == selection.objectID }?.position
        case .port: return input.hvac.flatMap(\.ports).first { $0.id == selection.objectID }?.position
        case .control: return input.controls.first { $0.id == selection.objectID }?.sensorPosition
        }
    }
    public static func translated(_ point: Position3D, from old: Position3D, to new: Position3D) -> Position3D {
        if old == new { return point }
        return .init(x: point.x + (new.x - old.x), y: point.y + (new.y - old.y), z: point.z + (new.z - old.z))
    }
    public static func unknownHeat() -> HeatGain {
        .init(sensible: .unknown(reason: "未提供热源依据"), convectiveFraction: .unknown(reason: "未提供对流比例依据"), latent: .unknown(reason: "未提供潜热依据"))
    }
}
