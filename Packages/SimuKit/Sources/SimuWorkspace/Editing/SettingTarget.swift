import Foundation
import SimuCore

/// Where a missing or invalid input can be edited. `anchor` is the validation path.
public struct SettingTarget: Equatable, Sendable {
    public var scenarioID: UUID?
    public var selection: EntitySelection
    public var anchor: String

    public init(scenarioID: UUID? = nil, selection: EntitySelection, anchor: String) {
        self.scenarioID = scenarioID
        self.selection = selection
        self.anchor = anchor
    }
}

public extension ProjectSession {
    /// Map a validator path to the inspector selection that can edit it.
    func settingTarget(for issue: ValidationIssue) -> SettingTarget? {
        let parts = issue.path.split(separator: "/").map(String.init)
        guard let root = parts.first else { return nil }
        switch root {
        case "geometry": return geometryTarget(parts, anchor: issue.path)
        case "scenarios": return scenarioTarget(parts, anchor: issue.path)
        default: return nil
        }
    }

    private func geometryTarget(_ parts: [String], anchor: String) -> SettingTarget? {
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "rooms":
            guard let room = item(project.geometry.rooms, parts, 2) ?? project.geometry.rooms.first else { return nil }
            if parts.count > 3, parts[3] == "openings" {
                let opening = item(room.openings, parts, 4) ?? (parts.count <= 4 ? room.openings.first : nil)
                if let opening {
                    return SettingTarget(selection: .opening(opening.id), anchor: anchor)
                }
            }
            return SettingTarget(selection: .room(room.id), anchor: anchor)
        case "obstacles":
            guard let obstacle = item(project.geometry.obstacles, parts, 2) ?? project.geometry.obstacles.first else { return nil }
            return SettingTarget(selection: .obstacle(obstacle.id), anchor: anchor)
        default:
            guard let room = project.geometry.rooms.first else { return nil }
            return SettingTarget(selection: .room(room.id), anchor: anchor)
        }
    }

    private func scenarioTarget(_ parts: [String], anchor: String) -> SettingTarget? {
        guard let scenario = item(project.scenarios, parts, 1) ?? project.scenarios.first else { return nil }
        let inputs = scenario.inputs
        if parts.count > 2, parts[2] == "evaluation" {
            return SettingTarget(scenarioID: scenario.id, selection: .cost, anchor: anchor)
        }
        guard parts.count > 3, parts[2] == "inputs" else {
            return SettingTarget(scenarioID: scenario.id, selection: .environment, anchor: anchor)
        }
        switch parts[3] {
        case "environment":
            return SettingTarget(scenarioID: scenario.id, selection: .environment, anchor: anchor)
        case "ventilation":
            let roomID = item(inputs.ventilation, parts, 4)?.roomID ?? project.geometry.rooms.first?.id
            guard let roomID else { return nil }
            return SettingTarget(scenarioID: scenario.id, selection: .room(roomID), anchor: anchor)
        case "envelope":
            if parts.count > 4, parts[4] == "windows", let window = item(inputs.envelope.windows, parts, 5) {
                return SettingTarget(scenarioID: scenario.id, selection: .opening(window.openingID), anchor: anchor)
            }
            if parts.count > 4, parts[4] == "surfaces", let surface = item(inputs.envelope.surfaces, parts, 5),
               let room = project.geometry.rooms.first(where: { $0.surfaces.contains { $0.id == surface.surfaceID } }) {
                return SettingTarget(scenarioID: scenario.id, selection: .room(room.id), anchor: anchor)
            }
            guard let room = project.geometry.rooms.first else { return nil }
            return SettingTarget(scenarioID: scenario.id, selection: .room(room.id), anchor: anchor)
        case "hvac":
            guard let device = item(inputs.hvac, parts, 4) ?? inputs.hvac.first else { return nil }
            if parts.count > 5, parts[5] == "ports", let port = item(device.ports, parts, 6) {
                return SettingTarget(scenarioID: scenario.id, selection: .port(deviceID: device.id, portID: port.id), anchor: anchor)
            }
            return SettingTarget(scenarioID: scenario.id, selection: .device(device.id), anchor: anchor)
        case "controls":
            guard let control = item(inputs.controls, parts, 4) ?? inputs.controls.first else { return nil }
            return SettingTarget(scenarioID: scenario.id, selection: .control(control.id), anchor: anchor)
        case "usage":
            guard parts.count > 4 else { return nil }
            switch parts[4] {
            case "seats":
                guard let seat = item(inputs.usage.seats, parts, 5) ?? inputs.usage.seats.first else { return nil }
                return SettingTarget(scenarioID: scenario.id, selection: .seat(seat.id), anchor: anchor)
            case "occupants":
                guard let occupant = item(inputs.usage.occupants, parts, 5) ?? inputs.usage.occupants.first else { return nil }
                return SettingTarget(scenarioID: scenario.id, selection: .occupant(occupant.id), anchor: anchor)
            case "equipment":
                guard let equipment = item(inputs.usage.equipment, parts, 5) ?? inputs.usage.equipment.first else { return nil }
                return SettingTarget(scenarioID: scenario.id, selection: .equipment(equipment.id), anchor: anchor)
            default:
                return nil
            }
        default:
            return SettingTarget(scenarioID: scenario.id, selection: .environment, anchor: anchor)
        }
    }

    private func item<T>(_ items: [T], _ parts: [String], _ index: Int) -> T? {
        guard parts.count > index, let offset = Int(parts[index]), items.indices.contains(offset) else { return nil }
        return items[offset]
    }
}
