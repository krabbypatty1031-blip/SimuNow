import Foundation
import SimuCore

public enum SceneObjectCategory: String, Hashable, Sendable {
    case room, surface, opening, furniture, seat, sample, occupant, equipment, hvac, port, control
}

/// Stable business identity. Display subdivisions never mint model UUIDs.
public struct SceneObjectKey: Hashable, Sendable, Identifiable {
    public let category: SceneObjectCategory
    public let modelID: UUID
    public var id: String { category.rawValue + ":" + modelID.uuidString.lowercased() }
    public init(category: SceneObjectCategory, modelID: UUID) { self.category = category; self.modelID = modelID }
    public var planSelection: RoomPlanSelection? {
        let kind: RoomPlanObjectKind
        switch category {
        case .furniture: kind = .furniture
        case .seat: kind = .seat
        case .sample: kind = .sample
        case .equipment: kind = .equipment
        case .hvac: kind = .hvac
        case .port: kind = .port
        case .control: kind = .control
        case .room, .surface, .opening, .occupant: return nil
        }
        return .init(kind: kind, objectID: modelID)
    }
    public init(_ selection: RoomPlanSelection) {
        self.init(category: SceneObjectCategory(rawValue: selection.kind.rawValue)!, modelID: selection.objectID)
    }
}

public struct SceneNodeKey: Hashable, Sendable, Identifiable {
    public let object: SceneObjectKey
    public let part: String
    public var id: String { object.id + "/" + part }
    public init(object: SceneObjectKey, part: String) { self.object = object; self.part = part }
}

/// Selection is a pure ID adapter, never an Entity reference.
public enum RoomSceneSelectionTarget: Hashable, Sendable {
    case object(RoomPlanSelection)
    case room(UUID)
    case opening(roomID: UUID, openingID: UUID)
}
