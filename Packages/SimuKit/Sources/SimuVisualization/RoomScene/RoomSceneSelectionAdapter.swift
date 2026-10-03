import Foundation
import SimuCore

public enum RoomSceneSelectionAdapter {
    /// Revalidates against the current model, including nested/parent identities.
    public static func target(for key: SceneObjectKey, project: ProjectDocument, scenarioID: UUID) -> RoomSceneSelectionTarget? {
        switch key.category {
        case .room:
            return project.geometry.rooms.filter { $0.id == key.modelID }.count == 1 ? .room(key.modelID) : nil
        case .surface:
            let rooms = project.geometry.rooms.filter { $0.surfaces.contains { $0.id == key.modelID } }
            guard rooms.count == 1, let room = rooms.first, room.surfaces.filter({ $0.id == key.modelID }).count == 1 else { return nil }
            return .room(room.id)
        case .opening:
            let rooms = project.geometry.rooms.filter { $0.openings.contains { $0.id == key.modelID } }
            guard rooms.count == 1, let room = rooms.first, room.openings.filter({ $0.id == key.modelID }).count == 1 else { return nil }
            return .opening(roomID: room.id,openingID: key.modelID)
        case .furniture:
            guard project.geometry.obstacles.filter({ $0.id == key.modelID }).count == 1 else { return nil }
        case .seat, .sample, .occupant, .equipment, .hvac, .port, .control:
            guard project.scenarios.filter({ $0.id == scenarioID }).count == 1, let input = project.scenarios.first(where: { $0.id == scenarioID })?.inputs else { return nil }
            switch key.category {
            case .seat: guard input.usage.seats.filter({ $0.id == key.modelID }).count == 1 else { return nil }
            case .sample: guard input.usage.seats.flatMap(\.samples).filter({ $0.id == key.modelID }).count == 1 else { return nil }
            case .equipment: guard input.usage.equipment.filter({ $0.id == key.modelID }).count == 1 else { return nil }
            case .hvac: guard input.hvac.filter({ $0.id == key.modelID }).count == 1 else { return nil }
            case .port: guard input.hvac.flatMap(\.ports).filter({ $0.id == key.modelID }).count == 1 else { return nil }
            case .control: guard input.controls.filter({ $0.id == key.modelID }).count == 1 else { return nil }
            case .occupant:
                let occupants = input.usage.occupants.filter { $0.id == key.modelID }
                guard occupants.count == 1, let occupant = occupants.first, input.usage.seats.filter({ $0.id == occupant.seatID }).count == 1 else { return nil }
                return .object(.init(kind: .seat,objectID: occupant.seatID))
            default: return nil
            }
        }
        return key.planSelection.map(RoomSceneSelectionTarget.object)
    }
}
