import Foundation
import SimuCore
import SimuVisualization

/// Writes a dragged item back into the project. Seats take their samples, devices take their ports,
/// and furniture keeps its size. The result stays inside the room.
@MainActor
enum RoomMotion {
    static func selection(for item: RoomPreviewItem) -> EntitySelection {
        switch item {
        case .seat(let id): .seat(id)
        case .obstacle(let id): .obstacle(id)
        case .device(let id): .device(id)
        case .equipment(let id): .equipment(id)
        }
    }

    static func apply(_ item: RoomPreviewItem, to requested: Position3D, session: ProjectSession) {
        guard let roomSize = roomSize(session) else { return }
        guard let current = anchor(item, session: session) else { return }
        let span = span(for: item, session: session)
        let point = RoomPreviewDrag.clamp(requested, roomSize: roomSize, span: span)
        guard point != current else { return }
        let delta = Position3D(x: point.x - current.x, y: point.y - current.y, z: point.z - current.z)
        session.mutate { document in
            guard let sIndex = document.scenarios.firstIndex(where: { $0.id == session.currentScenarioID }) else { return }
            switch item {
            case .seat(let id):
                guard let i = document.scenarios[sIndex].inputs.usage.seats.firstIndex(where: { $0.id == id }) else { return }
                let seat = document.scenarios[sIndex].inputs.usage.seats[i]
                document.scenarios[sIndex].inputs.usage.seats[i].position = shifted(seat.position, by: delta)
                for j in seat.samples.indices {
                    document.scenarios[sIndex].inputs.usage.seats[i].samples[j].position = shifted(seat.samples[j].position, by: delta)
                }
            case .device(let id):
                guard let i = document.scenarios[sIndex].inputs.hvac.firstIndex(where: { $0.id == id }) else { return }
                let device = document.scenarios[sIndex].inputs.hvac[i]
                document.scenarios[sIndex].inputs.hvac[i].position = shifted(device.position, by: delta)
                for k in device.ports.indices {
                    document.scenarios[sIndex].inputs.hvac[i].ports[k].position = shifted(device.ports[k].position, by: delta)
                }
            case .obstacle(let id):
                guard let oi = document.geometry.obstacles.firstIndex(where: { $0.id == id }),
                      let box = try? document.geometry.obstacles[oi].shape.resolved(as: BoxObstacle.self, registry: session.registry) else { return }
                let moved = BoxObstacle(origin: shifted(box.origin, by: delta), dimensions: box.dimensions)
                if let record = try? ExtensionRecord(moved) {
                    document.geometry.obstacles[oi].shape = record
                }
            case .equipment(let id):
                guard let i = document.scenarios[sIndex].inputs.usage.equipment.firstIndex(where: { $0.id == id }) else { return }
                let item = document.scenarios[sIndex].inputs.usage.equipment[i]
                document.scenarios[sIndex].inputs.usage.equipment[i].position = shifted(item.position, by: delta)
            }
        }
    }

    private static func roomSize(_ session: ProjectSession) -> Position3D? {
        guard let room = session.project.geometry.rooms.first,
              let payload = try? room.shape.resolved(as: RectangularRoom.self, registry: session.registry),
              let w = payload.dimensions.width.value,
              let d = payload.dimensions.depth.value,
              let h = payload.dimensions.height.value else { return nil }
        return Position3D(x: w, y: d, z: h)
    }

    private static func anchor(_ item: RoomPreviewItem, session: ProjectSession) -> Position3D? {
        switch item {
        case .seat(let id):
            return session.currentScenario?.inputs.usage.seats.first { $0.id == id }?.position
        case .device(let id):
            return session.currentScenario?.inputs.hvac.first { $0.id == id }?.position
        case .equipment(let id):
            return session.currentScenario?.inputs.usage.equipment.first { $0.id == id }?.position
        case .obstacle(let id):
            guard let obstacle = session.project.geometry.obstacles.first(where: { $0.id == id }),
                  let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: session.registry) else { return nil }
            return box.origin
        }
    }

    private static func span(for item: RoomPreviewItem, session: ProjectSession) -> RoomPreviewSpan {
        switch item {
        case .seat(let id):
            guard let seat = session.currentScenario?.inputs.usage.seats.first(where: { $0.id == id }) else { return .point }
            return RoomPreviewSpan(offsets: seat.samples.map { relative($0.position, to: seat.position) })
        case .device(let id):
            guard let device = session.currentScenario?.inputs.hvac.first(where: { $0.id == id }) else { return .point }
            return RoomPreviewSpan(offsets: device.ports.map { relative($0.position, to: device.position) })
        case .obstacle(let id):
            guard let obstacle = session.project.geometry.obstacles.first(where: { $0.id == id }),
                  let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: session.registry),
                  let w = box.dimensions.width.value, let d = box.dimensions.depth.value, let h = box.dimensions.height.value else { return .point }
            return RoomPreviewSpan(offsets: [Position3D(x: w, y: d, z: h)])
        case .equipment:
            return .point
        }
    }

    private static func relative(_ point: Position3D, to origin: Position3D) -> Position3D {
        Position3D(x: point.x - origin.x, y: point.y - origin.y, z: point.z - origin.z)
    }

    private static func shifted(_ point: Position3D, by delta: Position3D) -> Position3D {
        Position3D(x: point.x + delta.x, y: point.y + delta.y, z: point.z + delta.z)
    }
}
