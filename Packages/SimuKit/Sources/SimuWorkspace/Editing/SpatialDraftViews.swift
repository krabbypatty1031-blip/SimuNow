import SwiftUI
import SimuCore
import SimuVisualization

struct DirectionPreview: View {
    let yaw: String
    let pitch: String
    var body: some View {
        if let y = Double(yaw), let p = Double(pitch), let direction = try? AirflowDirection.unit(yawDegrees: y, pitchDegrees: p) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).stroke(.secondary)
                    Image(systemName: "arrow.right").font(.title).rotationEffect(.degrees(-y))
                    VStack { Text("+Y"); Spacer(); HStack { Spacer(); Text("+X") } }.font(.caption2).padding(4)
                }.frame(width: 84, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("俯视方向 · 水平角 \(y.formatted())°")
                    Text(p > 0 ? "向上 \(p.formatted())°" : p < 0 ? "向下 \((-p).formatted())°" : "水平送风")
                    DisclosureGroup("方向分量") {
                        Text("(\(direction.x.formatted()), \(direction.y.formatted()), \(direction.z.formatted()))")
                    }
                }.font(.caption)
            }.accessibilityElement(children: .combine)
        } else { Label("方向角无效；请检查水平角与俯仰角。", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
    }
}

struct PositionPreview: View {
    let x: String
    let y: String
    let z: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Path { path in
                    path.move(to: .init(x: 10, y: 45)); path.addLine(to: .init(x: 65, y: 45))
                    path.move(to: .init(x: 10, y: 45)); path.addLine(to: .init(x: 10, y: 5))
                }.stroke(.secondary, lineWidth: 1)
                Text("+Y").position(x: 20, y: 8)
                Text("+X").position(x: 64, y: 35)
                Text("0").position(x: 8, y: 55)
            }.font(.caption2).frame(width: 80, height: 64).accessibilityHidden(true)
            Text("俯视原点在左下。X 向右，Y 向上；Z 表示离地高度。当前：X \(x)、Y \(y)、Z \(z) m。相对位置从所属对象开始计量。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FurnitureDraftPreview: View {
    let project: ProjectDocument
    let draft: FurnitureEditDraft
    let registry: ModelRegistry
    var body: some View {
        if let room = project.geometry.rooms.first(where: { $0.id == draft.roomID }),
           let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry), let bounds = shape.geometryBounds() {
            VStack(alignment: .leading, spacing: 6) {
                Canvas { context, size in
                    guard let projection = PlanProjection(bounds: bounds, screenWidth: size.width, screenHeight: size.height) else { return }
                    let corner = projection.project(.init(x: bounds.origin.x, y: bounds.origin.y + bounds.size.y, z: 0))
                    let roomRect = CGRect(x: corner.x, y: corner.y, width: bounds.size.x * projection.scale, height: bounds.size.y * projection.scale)
                    context.stroke(Path(roomRect), with: .color(.primary), lineWidth: 1.5)
                    for obstacle in project.geometry.obstacles where obstacle.roomID == room.id && obstacle.id != draft.id {
                        if let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry), let b = box.geometryBounds() {
                            let p = projection.project(.init(x: b.origin.x, y: b.origin.y + b.size.y, z: 0))
                            context.fill(Path(CGRect(x: p.x, y: p.y, width: b.size.x * projection.scale, height: b.size.y * projection.scale)), with: .color(Color.secondary.opacity(0.25)))
                        }
                    }
                    if let origin = try? draft.origin.position(), draft.width.isKnown, draft.depth.isKnown,
                       let width = Double(draft.width.valueText), let depth = Double(draft.depth.valueText),
                       width.isFinite, depth.isFinite, width > 0, depth > 0 {
                        let point = projection.project(.init(x: origin.x, y: origin.y + depth, z: origin.z))
                        let rect = CGRect(x: point.x, y: point.y, width: width * projection.scale, height: depth * projection.scale)
                        context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.25)))
                        context.stroke(Path(rect), with: .color(.accentColor), lineWidth: 2)
                    }
                }.frame(height: 160).accessibilityHidden(true)
                Text("家具草稿俯视 · 灰色为已有家具，描边为当前草稿。位置按最小角计量；未知尺寸不绘制。越界和碰撞在应用时检查。").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// An elevation uses the same surface U/V axes as the stored geometry.
struct OpeningElevationView: View {
    let room: Room
    let draft: OpeningDraft
    let registry: ModelRegistry
    var body: some View {
        if let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
           let bounds = shape.geometryBounds(),
           [bounds.size.x, bounds.size.y, bounds.size.z].allSatisfy({ $0.isFinite && $0 > 0 }),
           let face = room.surfaces.first(where: { $0.id == draft.surfaceID })?.face {
            let wallWidth = [.xMin, .xMax].contains(face) ? bounds.size.y : bounds.size.x
            let wallHeight = [.floor, .ceiling].contains(face) ? bounds.size.y : bounds.size.z
            VStack(alignment: .leading, spacing: 8) {
                Text(room.name + " · " + RoomIssuePresentation.wallTitle(face)).font(.subheadline.bold())
                Canvas { context, size in
                    let scale = min((size.width - 32) / bounds.size.x, (size.height - 24) / bounds.size.y)
                    let rect = CGRect(x: 16, y: 8, width: bounds.size.x * scale, height: bounds.size.y * scale)
                    context.stroke(Path(rect), with: .color(.secondary), lineWidth: 1)
                    var selected = Path()
                    switch face {
                    case .xMin: selected.move(to: .init(x: rect.minX, y: rect.minY)); selected.addLine(to: .init(x: rect.minX, y: rect.maxY))
                    case .xMax: selected.move(to: .init(x: rect.maxX, y: rect.minY)); selected.addLine(to: .init(x: rect.maxX, y: rect.maxY))
                    case .yMin: selected.move(to: .init(x: rect.minX, y: rect.maxY)); selected.addLine(to: .init(x: rect.maxX, y: rect.maxY))
                    case .yMax: selected.move(to: .init(x: rect.minX, y: rect.minY)); selected.addLine(to: .init(x: rect.maxX, y: rect.minY))
                    case .floor, .ceiling: selected = Path(rect)
                    }
                    context.stroke(selected, with: .color(.accentColor), lineWidth: 4)
                }.frame(height: 88).accessibilityHidden(true)
                Text("俯视 · 粗线为所选墙面").font(.caption).foregroundStyle(.secondary)
                Canvas { context, size in
                    let scale = min((size.width - 40) / wallWidth, (size.height - 32) / wallHeight)
                    let wall = CGRect(x: 20, y: 12, width: wallWidth * scale, height: wallHeight * scale)
                    context.stroke(Path(wall), with: .color(.primary), lineWidth: 2)
                    if let u = draft.offsetU.isKnown ? Double(draft.offsetU.valueText) : nil,
                       let v = draft.offsetV.isKnown ? Double(draft.offsetV.valueText) : nil,
                       let w = draft.width.isKnown ? Double(draft.width.valueText) : nil,
                       let h = draft.height.isKnown ? Double(draft.height.valueText) : nil,
                       [u, v, w, h].allSatisfy(\.isFinite), w > 0, h > 0 {
                        let rect = CGRect(x: wall.minX + u * scale, y: wall.maxY - (v + h) * scale, width: w * scale, height: h * scale)
                        let invalid = u < 0 || v < 0 || u + w > wallWidth || v + h > wallHeight
                        context.fill(Path(rect), with: .color(invalid ? Color.orange.opacity(0.3) : Color.accentColor.opacity(0.2)))
                        context.stroke(Path(rect), with: .color(invalid ? .orange : .accentColor), lineWidth: 2)
                    }
                    context.draw(Text("\(wallWidth.formatted()) m").font(.caption), at: .init(x: wall.midX, y: wall.maxY + 12))
                }.frame(height: 160)
                Text("横轴 U · 垂直轴 V；窗口底边高度即 V 偏移。未知几何不绘制；未建模门扇开启方向。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else { Text("房间尺寸未知；无法绘制墙面立面。仍可记录门窗草稿。").font(.caption) }
    }
}

extension RoomIssuePresentation {
    static func wallTitle(_ face: SurfaceFace) -> String {
        switch face {
        case .xMin: "左墙（X 最小）"
        case .xMax: "右墙（X 最大）"
        case .yMin: "下墙（Y 最小）"
        case .yMax: "上墙（Y 最大）"
        case .floor: "地板"
        case .ceiling: "天花板"
        }
    }
}
