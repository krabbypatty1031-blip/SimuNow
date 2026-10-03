import SimuCore
import SwiftUI

private struct PlanMarker: Identifiable {
    let selection: RoomPlanSelection
    let name: String
    let position: Position3D
    var direction: Direction3D? = nil
    var id: String { selection.id }
}

/// Geometry/input positions and immutable checked rule paths; never a physical velocity/temperature field.
public struct RoomPlanView: View {
    @State private var hitCandidates: [PlanChoice] = []
    public let project: ProjectDocument
    public let scenarioID: UUID
    public let selection: RoomPlanSelection?
    public let registry: ModelRegistry
    public let overlay: RoomSceneOverlay
    public let placing: Bool
    public let onSelect: @MainActor (RoomPlanSelection) -> Void
    public let onPlace: @MainActor (Position3D) -> Void
    public init(
        project: ProjectDocument, scenarioID: UUID, selection: RoomPlanSelection?,
        registry: ModelRegistry = .builtIn, placing: Bool = false, overlay: RoomSceneOverlay = .empty,
        onSelect: @escaping @MainActor (RoomPlanSelection) -> Void,
        onPlace: @escaping @MainActor (Position3D) -> Void
    ) {
        self.project = project
        self.scenarioID = scenarioID
        self.selection = selection
        self.registry = registry
        self.placing = placing
        self.overlay = overlay
        self.onSelect = onSelect
        self.onPlace = onPlace
    }
    private var room: Room? { project.geometry.rooms.first }
    private var bounds: GeometryBounds? {
        guard let room, let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry)
        else { return nil }
        return shape.geometryBounds()
    }
    private var markers: [PlanMarker] {
        guard let room, let input = project.scenarios.first(where: { $0.id == scenarioID })?.inputs else {
            return []
        }
        var result: [PlanMarker] = []
        for seat in input.usage.seats where seat.roomID == room.id {
            result.append(
                .init(
                    selection: .init(kind: .seat, objectID: seat.id), name: seat.name, position: seat.position
                ))
            for (i, sample) in seat.samples.enumerated() {
                result.append(
                    .init(
                        selection: .init(kind: .sample, objectID: sample.id),
                        name: "\(seat.name) 采样点 \(i + 1)", position: sample.position))
            }
        }
        for item in input.usage.equipment where item.roomID == room.id {
            result.append(
                .init(
                    selection: .init(kind: .equipment, objectID: item.id), name: "热源 · " + item.id.uuidString.prefix(6),
                    position: item.position))
        }
        for device in input.hvac where device.roomID == room.id {
            result.append(
                .init(
                    selection: .init(kind: .hvac, objectID: device.id), name: device.name,
                    position: device.position))
            for (i, port) in device.ports.enumerated() {
                let role = port.role == .supply ? "送风口" : "回风口"
                result.append(
                    .init(
                        selection: .init(kind: .port, objectID: port.id),
                        name: "\(device.name) \(role) \(i + 1)", position: port.position,
                        direction: port.direction))
            }
            for control in input.controls where control.deviceID == device.id {
                result.append(
                    .init(
                        selection: .init(kind: .control, objectID: control.id), name: "\(device.name) 温控测点",
                        position: control.sensorPosition))
            }
        }
        return result
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                if let bounds,
                    let projection = PlanProjection(
                        bounds: bounds, screenWidth: geometry.size.width, screenHeight: geometry.size.height)
                {
                    Canvas { context, _ in draw(in: &context, projection: projection) }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let point = PlanPoint(x: location.x, y: location.y)
                            guard projection.contains(point) else { return }
                            if placing {
                                onPlace(projection.unproject(point, z: 0))
                                return
                            }
                            let hits = hitTest(point, projection: projection)
                            if hits.count == 1, let hit = hits.first { onSelect(hit.selection) }
                            else if !hits.isEmpty { hitCandidates = hits }
                        }
                        .accessibilityLabel("房间俯视图")
                        .accessibilityValue("坐标为米，横轴 X，纵轴 Y。对象清单可选择和编辑全部对象。")
                        .accessibilityChildren {
                            ForEach(markers) { marker in
                                Button(marker.name) { onSelect(marker.selection) }
                                    .accessibilityValue(
                                        "X \(marker.position.x.formatted()) 米，Y \(marker.position.y.formatted()) 米，Z \(marker.position.z.formatted()) 米"
                                    )
                            }
                            ForEach(project.geometry.obstacles.filter { $0.roomID == room?.id }, id: \.id) {
                                obstacle in
                                Button(obstacle.name) {
                                    onSelect(.init(kind: .furniture, objectID: obstacle.id))
                                }
                            }
                        }
                } else {
                    ContentUnavailableView(
                        "无法显示俯视图", systemImage: "square.dashed",
                        description: Text("请补齐受支持房间的宽度和深度。数值表单仍可查看对象。"))
                }
            }
            .frame(minHeight: 120, maxHeight: .infinity)
            HStack {
                Text("米制 · +X 向右 · +Y 向上 · Z 为高度")
                Spacer()
                Text(placing ? "点击设置所选对象的 X / Y" : "点击选择，或使用对象列表")
            }
            .font(.caption).foregroundStyle(.secondary)
            if let marker = markers.first(where: { $0.selection == selection }) {
                Text(selectedDescription(marker)).font(.caption).foregroundStyle(.primary)
            }
            if !overlay.explanation.isEmpty {
                Text(overlay.explanation).font(.caption).foregroundStyle(.secondary)
            }
            if let issue = overlay.validationMessage { Text(issue).font(.caption).foregroundStyle(.orange) }
        }
        .confirmationDialog("选择此处的对象", isPresented: Binding(get: { !hitCandidates.isEmpty }, set: { if !$0 { hitCandidates = [] } }), titleVisibility: .visible) {
            ForEach(hitCandidates) { item in
                Button(item.name + " · " + item.selection.kind.title) { onSelect(item.selection); hitCandidates = [] }
            }
            Button("取消", role: .cancel) { hitCandidates = [] }
        }
    }
    private func selectedDescription(_ marker: PlanMarker) -> String {
        var text =
            "选中：\(marker.name) · 高度 Z \(marker.position.z.formatted(.number.precision(.fractionLength(2)))) m"
        if let direction = marker.direction {
            text += " · 方向 Z \(direction.z.formatted(.number.precision(.fractionLength(2))))"
        }
        return text
    }
    private func color(_ kind: RoomPlanObjectKind) -> Color {
        switch kind {
        case .furniture: .secondary
        case .seat: .blue
        case .sample: .cyan
        case .equipment: .orange
        case .hvac: .purple
        case .port: .teal
        case .control: .pink
        }
    }
    private func cg(_ point: PlanPoint) -> CGPoint { .init(x: point.x, y: point.y) }
    private func draw(in context: inout GraphicsContext, projection: PlanProjection) {
        guard let room else { return }
        let b = projection.bounds
        let topLeft = projection.project(.init(x: b.origin.x, y: b.origin.y + b.size.y, z: 0))
        let roomRect = CGRect(
            x: topLeft.x, y: topLeft.y, width: b.size.x * projection.scale,
            height: b.size.y * projection.scale)
        context.fill(Path(roomRect), with: .color(Color.primary.opacity(0.025)))
        let step = pow(10, floor(log10(max(b.size.x, b.size.y)))) / 10
        let gridStep = max(0.1, step * (step * projection.scale < 20 ? 5 : 1))
        var grid = Path()
        for x in stride(from: b.origin.x + gridStep, to: b.origin.x + b.size.x, by: gridStep) {
            let point = projection.project(.init(x: x, y: b.origin.y, z: 0))
            grid.move(to: .init(x: point.x, y: roomRect.minY)); grid.addLine(to: .init(x: point.x, y: roomRect.maxY))
        }
        for y in stride(from: b.origin.y + gridStep, to: b.origin.y + b.size.y, by: gridStep) {
            let point = projection.project(.init(x: b.origin.x, y: y, z: 0))
            grid.move(to: .init(x: roomRect.minX, y: point.y)); grid.addLine(to: .init(x: roomRect.maxX, y: point.y))
        }
        context.stroke(grid, with: .color(Color.secondary.opacity(0.18)), lineWidth: 0.5)
        context.stroke(Path(roomRect), with: .color(.primary), lineWidth: 2)
        context.draw(Text("\(b.size.x.formatted()) m").font(.caption), at: .init(x: roomRect.midX, y: roomRect.maxY + 12))
        context.draw(Text("\(b.size.y.formatted()) m").font(.caption), at: .init(x: roomRect.minX + 26, y: roomRect.minY + 12))
        context.draw(Text("网格 \(gridStep.formatted()) m").font(.caption2), at: .init(x: roomRect.minX + 48, y: roomRect.maxY - 12))
        for obstacle in project.geometry.obstacles where obstacle.roomID == room.id {
            guard let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry),
                let ob = box.geometryBounds()
            else { continue }
            let p = projection.project(.init(x: ob.origin.x, y: ob.origin.y + ob.size.y, z: ob.origin.z))
            let rect = CGRect(
                x: p.x, y: p.y, width: ob.size.x * projection.scale, height: ob.size.y * projection.scale)
            let chosen = selection == .init(kind: .furniture, objectID: obstacle.id)
            context.fill(Path(rect), with: .color(Color.secondary.opacity(0.3)))
            context.stroke(
                Path(rect), with: .color(chosen ? .accentColor : .secondary), lineWidth: chosen ? 3 : 1)
            if rect.width > 80 && rect.height > 24 {
                context.draw(Text(obstacle.name).font(.caption2), in: rect.insetBy(dx: 4, dy: 4))
            }
        }
        for opening in room.openings {
            guard let face = room.surfaces.first(where: { $0.id == opening.surfaceID })?.face,
                let u = opening.offsetU.value, let width = opening.width.value
            else { continue }
            let start: Position3D
            let end: Position3D
            switch face {
            case .xMin, .xMax:
                let x = face == .xMin ? b.origin.x : b.origin.x + b.size.x
                start = .init(x: x, y: b.origin.y + u, z: 0)
                end = .init(x: x, y: b.origin.y + u + width, z: 0)
            case .yMin, .yMax:
                let y = face == .yMin ? b.origin.y : b.origin.y + b.size.y
                start = .init(x: b.origin.x + u, y: y, z: 0)
                end = .init(x: b.origin.x + u + width, y: y, z: 0)
            case .floor, .ceiling: continue
            }
            var path = Path()
            path.move(to: cg(projection.project(start)))
            path.addLine(to: cg(projection.project(end)))
            context.stroke(path, with: .color(opening.kind == .window ? .cyan : .orange), lineWidth: opening.kind == .window ? 5 : 3)
            let midpoint = projection.project(.init(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2, z: 0))
            context.draw(Text(opening.kind == .window ? "窗" : "门").font(.caption2.bold()), at: .init(x: midpoint.x + 10, y: midpoint.y - 10))
        }
        if overlay.validationMessage == nil {
            for line in overlay.paths {
                var path = Path()
                if let first = line.points.first { path.move(to: cg(projection.project(first))) }
                for point in line.points.dropFirst() { path.addLine(to: cg(projection.project(point))) }
                context.stroke(path, with: .color(line.blocked ? .orange : .teal), lineWidth: 1.5)
                if line.blocked, let last = line.points.last {
                    let p = cg(projection.project(last))
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                        with: .color(.orange))
                }
            }
        }
        for marker in markers {
            let p = cg(projection.project(marker.position))
            let chosen = marker.selection == selection
            let radius: Double = marker.selection.kind == .sample ? 3 : 5
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            let symbol: Path
            switch marker.selection.kind {
            case .sample:
                symbol = Path { path in path.move(to: .init(x: p.x, y: p.y - 5)); path.addLine(to: .init(x: p.x + 5, y: p.y)); path.addLine(to: .init(x: p.x, y: p.y + 5)); path.addLine(to: .init(x: p.x - 5, y: p.y)); path.closeSubpath() }
            case .equipment, .hvac: symbol = Path(rect)
            default: symbol = Path(ellipseIn: rect)
            }
            context.fill(symbol, with: .color(color(marker.selection.kind)))
            if chosen {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.accentColor), lineWidth: 2)
            }
            // Coincident seat/sample/sensor and device/port points are common.
            // Keep complete names in the accessible list and annotate only the selection.
            if chosen {
                let labelX = min(max(p.x, roomRect.minX + 36), roomRect.maxX - 36)
                context.draw(
                    Text(marker.selection.kind.title).font(.caption2.bold()),
                    at: .init(x: labelX, y: p.y - 22))
            } else if marker.selection.kind == .seat {
                context.draw(
                    Text(markers.filter { $0.selection.kind == .seat }.count > 12 ? String((markers.filter { $0.selection.kind == .seat }.firstIndex { $0.id == marker.id } ?? 0) + 1) : marker.name).font(.caption2), at: .init(x: p.x, y: p.y + 13))
            } else if marker.selection.kind == .equipment {
                let number = marker.name.split(separator: " ").last.map(String.init) ?? ""
                context.draw(Text("热\(number)").font(.caption2), at: .init(x: p.x, y: p.y + 13))
            }
            if let d = marker.direction {
                let dx = d.x * 30
                let dy = -d.y * 30
                let end = CGPoint(x: p.x + dx, y: p.y + dy)
                var arrow = Path()
                arrow.move(to: p)
                arrow.addLine(to: end)
                if hypot(dx, dy) > 1 {
                    let angle = atan2(dy, dx)
                    arrow.move(
                        to: .init(x: end.x - 7 * cos(angle - .pi / 6), y: end.y - 7 * sin(angle - .pi / 6)))
                    arrow.addLine(to: end)
                    arrow.addLine(
                        to: .init(x: end.x - 7 * cos(angle + .pi / 6), y: end.y - 7 * sin(angle + .pi / 6)))
                }
                context.stroke(arrow, with: .color(.teal), lineWidth: 2)
            }
        }
        if let north = room.northAngle.value {
            let radians = north * .pi / 180
            let anchor = CGPoint(x: roomRect.maxX - 20, y: roomRect.minY + 30)
            let end = CGPoint(x: anchor.x + sin(radians) * 18, y: anchor.y - cos(radians) * 18)
            var arrow = Path()
            arrow.move(to: anchor)
            arrow.addLine(to: end)
            context.stroke(arrow, with: .color(.primary), lineWidth: 2)
            context.draw(Text("N").font(.caption.bold()), at: .init(x: end.x, y: end.y - 8))
        }
    }
    private func hitTest(_ point: PlanPoint, projection: PlanProjection) -> [PlanChoice] {
        var result = markers.map { ($0, projection.project($0.position)) }.filter {
            hypot($0.1.x - point.x, $0.1.y - point.y) <= 16
        }.sorted {
            let a = hypot($0.1.x - point.x, $0.1.y - point.y), b = hypot($1.1.x - point.x, $1.1.y - point.y)
            return a == b ? $0.0.id < $1.0.id : a < b
        }.map { PlanChoice(selection: $0.0.selection, name: $0.0.name) }
        let position = projection.unproject(point, z: 0)
        for obstacle in project.geometry.obstacles.reversed() where obstacle.roomID == room?.id {
            guard let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry), let b = box.geometryBounds() else { continue }
            if (b.origin.x...b.origin.x + b.size.x).contains(position.x), (b.origin.y...b.origin.y + b.size.y).contains(position.y) {
                result.append(.init(selection: .init(kind: .furniture, objectID: obstacle.id), name: obstacle.name))
            }
        }
        return result
    }
}
private struct PlanChoice: Identifiable {
    let selection: RoomPlanSelection
    let name: String
    var id: String { selection.id }
}
