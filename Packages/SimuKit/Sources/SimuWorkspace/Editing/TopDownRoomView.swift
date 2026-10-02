import SwiftUI
import SimuCore

/// Top-down plan view: room rectangle with obstacles, seats, devices and ports.
/// Tap selects; drag repositions (snap 0.05 m, clamped to the room); contract validation reports the rest.
public struct TopDownRoomView: View {
    let session: ProjectSession
    @State private var dragStart: Position3D?

    public init(session: ProjectSession) { self.session = session }

    private var room: Room? { session.project.geometry.rooms.first }
    private var roomSize: (w: Double, d: Double)? {
        guard let room,
              let payload = try? room.shape.resolved(as: RectangularRoom.self, registry: session.registry),
              let w = payload.dimensions.width.value, let d = payload.dimensions.depth.value else { return nil }
        return (w, d)
    }

    public var body: some View {
        GeometryReader { proxy in
            if let room, let size = roomSize {
                let scale = min((proxy.size.width - 60) / size.w, (proxy.size.height - 60) / size.d)
                let origin = CGPoint(x: (proxy.size.width - size.w * scale) / 2,
                                     y: (proxy.size.height - size.d * scale) / 2)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(context: context, scale: scale, origin: origin, room: room, size: size)
                    }
                    .gesture(dragGesture(scale: scale, origin: origin))
                    .onTapGesture { point in select(at: point, scale: scale, origin: origin) }
                }
            } else {
                ContentUnavailableView("无法显示房间", systemImage: "cube.transparent",
                                       description: Text("房间几何未完成或不支持。"))
            }
        }
    }

    // MARK: - Drawing

    private func point(_ p: Position3D, scale: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + (roomSize?.d ?? 0) * scale - p.y * scale)
    }

    private func draw(context: GraphicsContext, scale: CGFloat, origin: CGPoint, room: Room, size: (w: Double, d: Double)) {
        let rect = CGRect(origin: origin, size: CGSize(width: size.w * scale, height: size.d * scale))
        context.stroke(Path(rect), with: .color(.primary), lineWidth: 2)

        for obstacle in session.project.geometry.obstacles {
            guard let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: session.registry),
                  let w = box.dimensions.width.value, let d = box.dimensions.depth.value else { continue }
            let a = point(box.origin, scale: scale, origin: origin)
            let r = CGRect(x: a.x, y: a.y - d * scale, width: w * scale, height: d * scale)
            context.fill(Path(r), with: .color(.gray.opacity(0.35)))
            if session.selection == .obstacle(obstacle.id) {
                context.stroke(Path(r), with: .color(.accentColor), lineWidth: 2)
            }
        }
        guard let scenario = session.currentScenario else { return }
        for seat in scenario.inputs.usage.seats {
            let c = point(seat.position, scale: scale, origin: origin)
            let r = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: r), with: .color(.green.opacity(0.8)))
            if session.selection == .seat(seat.id) {
                context.stroke(Path(ellipseIn: r.insetBy(dx: -3, dy: -3)), with: .color(.accentColor), lineWidth: 2)
            }
            context.draw(Text(seat.name).font(.system(size: 9)), at: CGPoint(x: c.x, y: c.y - 12))
        }
        for device in scenario.inputs.hvac {
            let c = point(device.position, scale: scale, origin: origin)
            let r = CGRect(x: c.x - 10, y: c.y - 6, width: 20, height: 12)
            context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(.blue.opacity(0.7)))
            if session.selection == .device(device.id) {
                context.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 3), with: .color(.accentColor), lineWidth: 2)
            }
            for port in device.ports {
                let pc = point(port.position, scale: scale, origin: origin)
                let tip = CGPoint(x: pc.x + port.direction.x * 14, y: pc.y - port.direction.y * 14)
                var arrow = Path()
                arrow.move(to: pc); arrow.addLine(to: tip)
                context.stroke(arrow, with: .color(port.role == .supply ? .orange : .purple), lineWidth: 2)
            }
        }
    }

    // MARK: - Hit testing & gestures

    private func hitTest(_ viewPoint: CGPoint, scale: CGFloat, origin: CGPoint) -> EntitySelection? {
        guard let scenario = session.currentScenario else { return nil }
        func distance(_ p: Position3D) -> Double {
            let c = point(p, scale: scale, origin: origin)
            return hypot(Double(c.x - viewPoint.x), Double(c.y - viewPoint.y))
        }
        var best: (EntitySelection, Double)?
        func consider(_ selection: EntitySelection, _ position: Position3D) {
            let d = distance(position)
            guard d < 24 else { return }
            if best == nil || d < best!.1 { best = (selection, d) }
        }
        for seat in scenario.inputs.usage.seats { consider(.seat(seat.id), seat.position) }
        for device in scenario.inputs.hvac { consider(.device(device.id), device.position) }
        for obstacle in session.project.geometry.obstacles {
            if let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: session.registry) {
                consider(.obstacle(obstacle.id), Position3D(x: box.origin.x + (box.dimensions.width.value ?? 0) / 2,
                                                            y: box.origin.y + (box.dimensions.depth.value ?? 0) / 2, z: 0))
            }
        }
        return best?.0
    }

    private func select(at viewPoint: CGPoint, scale: CGFloat, origin: CGPoint) {
        session.selection = hitTest(viewPoint, scale: scale, origin: origin)
    }

    private func dragGesture(scale: CGFloat, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStart == nil {
                    if let selection = hitTest(value.startLocation, scale: scale, origin: origin) {
                        session.selection = selection
                        dragStart = currentPosition(of: selection)
                    }
                }
                guard let selection = session.selection, let start = dragStart else { return }
                let dx = Double(value.translation.width) / scale
                let dy = -Double(value.translation.height) / scale
                move(selection, to: snap(start.x + dx), snap(start.y + dy))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func snap(_ v: Double) -> Double { (v / 0.05).rounded() * 0.05 }

    private func currentPosition(of selection: EntitySelection) -> Position3D? {
        guard let scenario = session.currentScenario else { return nil }
        switch selection {
        case .seat(let id): return scenario.inputs.usage.seats.first { $0.id == id }?.position
        case .device(let id): return scenario.inputs.hvac.first { $0.id == id }?.position
        case .obstacle(let id):
            guard let obstacle = session.project.geometry.obstacles.first(where: { $0.id == id }),
                  let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: session.registry) else { return nil }
            return box.origin
        default: return nil
        }
    }

    private func move(_ selection: EntitySelection, to x: Double, _ y: Double) {
        guard let size = roomSize else { return }
        session.mutate { document in
            guard let sIndex = document.scenarios.firstIndex(where: { $0.id == session.currentScenarioID }) else { return }
            switch selection {
            case .seat(let id):
                guard let i = document.scenarios[sIndex].inputs.usage.seats.firstIndex(where: { $0.id == id }) else { return }
                let px = min(max(x, 0), size.w), py = min(max(y, 0), size.d)
                let seat = document.scenarios[sIndex].inputs.usage.seats[i]
                let dx = px - seat.position.x, dy = py - seat.position.y
                document.scenarios[sIndex].inputs.usage.seats[i].position = Position3D(x: px, y: py, z: seat.position.z)
                for j in seat.samples.indices {
                    let s = seat.samples[j].position
                    document.scenarios[sIndex].inputs.usage.seats[i].samples[j].position = Position3D(x: s.x + dx, y: s.y + dy, z: s.z)
                }
            case .device(let id):
                guard let i = document.scenarios[sIndex].inputs.hvac.firstIndex(where: { $0.id == id }) else { return }
                let px = min(max(x, 0), size.w), py = min(max(y, 0), size.d)
                let device = document.scenarios[sIndex].inputs.hvac[i]
                let dx = px - device.position.x, dy = py - device.position.y
                document.scenarios[sIndex].inputs.hvac[i].position = Position3D(x: px, y: py, z: device.position.z)
                for k in device.ports.indices {
                    let p = device.ports[k].position
                    document.scenarios[sIndex].inputs.hvac[i].ports[k].position = Position3D(x: p.x + dx, y: p.y + dy, z: p.z)
                }
            case .obstacle(let id):
                guard let oi = document.geometry.obstacles.firstIndex(where: { $0.id == id }),
                      let box = try? document.geometry.obstacles[oi].shape.resolved(as: BoxObstacle.self, registry: session.registry),
                      let w = box.dimensions.width.value, let d = box.dimensions.depth.value else { return }
                let px = min(max(x, 0), size.w - w), py = min(max(y, 0), size.d - d)
                let moved = BoxObstacle(origin: Position3D(x: px, y: py, z: box.origin.z), dimensions: box.dimensions)
                if let record = try? ExtensionRecord(moved) {
                    document.geometry.obstacles[oi].shape = record
                }
            default: break
            }
        }
    }
}
