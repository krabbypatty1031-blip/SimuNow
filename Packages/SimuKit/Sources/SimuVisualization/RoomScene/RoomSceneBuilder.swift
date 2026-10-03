import Foundation
import SimuCore

public enum RoomSceneBuilder {
    /// Bounded display work; project input is never modified or "repaired" by this adapter.
    public static func build(project: ProjectDocument, scenarioID: UUID, registry: ModelRegistry = .builtIn) -> SceneDescriptor {
        var b = Builder(projectID: project.id, scenarioID: scenarioID)
        guard project.lengthUnit == "m", project.coordinateSystem == "rightHandedZUp" else {
            b.issue(nil, "coordinate_system", "项目坐标或单位不受支持，无法安全绘制。")
            return b.finish()
        }
        let room = project.geometry.rooms.first
        for (index,item) in project.geometry.rooms.enumerated() {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
            let key = SceneObjectKey(category: .room, modelID: item.id)
            let detail = index == 0 ? "米制模型；显示厚度 0.02 m，不是墙体物理参数。" : "未显示：多房间当前没有共同放置坐标；仅显示第一个房间。"
            _ = b.object(key, title: item.name, detail: detail, target: .room(item.id))
            if index > 0 { b.issue(key, "multiple_rooms", detail) }
        }
        guard let room else { b.issue(nil, "missing_room", "尚无房间。请先创建矩形房间。"); return b.finish() }
        let roomKey = SceneObjectKey(category: .room, modelID: room.id)
        guard let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
              let bounds = shape.geometryBounds(), safe(bounds) else {
            b.issue(roomKey, "unsupported_room", "房间类型不受支持，或尺寸未知/无效；原数据保留，未猜测几何。")
            return b.finish()
        }
        b.roomID = room.id; b.bounds = bounds
        b.updateFocus(roomKey, bounds: bounds)
        var seenFaces: Set<SurfaceFace> = []
        var surfaceIDs: [UUID: Surface] = [:]
        for surface in room.surfaces {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
            let key = SceneObjectKey(category: .surface, modelID: surface.id)
            guard b.object(key, title: faceTitle(surface.face), detail: "房间内表面；显示墙厚向外，不改变分析边界。", target: .room(room.id)) else { continue }
            guard seenFaces.insert(surface.face).inserted else { b.issue(key, "duplicate_face", "该房间表面重复，未绘制重复墙片。"); continue }
            surfaceIDs[surface.id] = surface
            var openingRects: [SurfaceRectangle] = []
            for opening in room.openings where opening.surfaceID == surface.id {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
                let openingKey = SceneObjectKey(category: .opening, modelID: opening.id)
                let title = (opening.kind == .door ? "门" : "窗") + " · " + faceTitle(surface.face)
                guard b.object(openingKey, title: title, detail: "轮廓表示几何开口；不推断开启比例或通风。", target: .opening(roomID: room.id, openingID: opening.id)) else { continue }
                guard let rect = OpeningGeometry.rectangle(opening, face: surface.face, bounds: bounds) else {
                    b.issue(openingKey, "invalid_opening", "门窗宽高/偏移未知、无效或越界；没有猜测开口。")
                    continue
                }
                openingRects.append(rect)
                let quad = OpeningGeometry.quad(surface.face, rectangle: rect, bounds: bounds)
                b.updateFocus(openingKey, bounds: enclosing(quad, minimumSize: 0.02))
                for i in 0..<4 {
                    let from = quad[i], to = quad[(i+1)%4]
                    b.node(.init(key: .init(object: openingKey, part: "outline-\(i)"),
                                 geometry: .segment(vector: .init(x: to.x-from.x, y: to.y-from.y, z: to.z-from.z), radius: 0.015),
                                 position: from, material: opening.kind == .door ? .door : .window, face: surface.face))
                }
            }
            guard let cells = try? OpeningGeometry.wallCells(face: surface.face, bounds: bounds, openings: openingRects) else {
                b.issue(key, "surface_budget", "此表面开口分格超过显示上限，未绘制墙片。请在对象列表检查。")
                continue
            }
            b.updateFocus(key, bounds: enclosing(OpeningGeometry.quad(surface.face, rectangle: .init(u: 0, v: 0, width: OpeningGeometry.extent(surface.face, bounds: bounds).u, height: OpeningGeometry.extent(surface.face, bounds: bounds).v), bounds: bounds), minimumSize: 0.02))
            for (index,cell) in cells.enumerated() {
                let box = OpeningGeometry.wallBox(face: surface.face, rectangle: cell, bounds: bounds)
                b.node(.init(key: .init(object: key, part: "wall-\(index)"), geometry: .box(size: box.size), position: box.center,
                             material: surface.face == .floor ? .floor : .wall, face: surface.face))
            }
        }
        for face in SurfaceFace.allCases where !seenFaces.contains(face) { b.issue(roomKey, "missing_\(face.rawValue)", "缺少\(faceTitle(face))记录，未生成没有模型身份的墙。") }
        for opening in room.openings where surfaceIDs[opening.surfaceID] == nil {
            let key = SceneObjectKey(category: .opening, modelID: opening.id)
            _ = b.object(key, title: "门窗", detail: "所属表面缺失或重复，未显示。", target: .opening(roomID: room.id, openingID: opening.id))
            b.issue(key, "opening_surface", "门窗引用的有效表面不存在，未显示。")
        }
        for obstacle in project.geometry.obstacles {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
            let key = SceneObjectKey(category: .furniture, modelID: obstacle.id)
            guard b.object(key, title: obstacle.name, detail: "家具几何；受支持的盒体按原模型尺寸显示。", target: .object(.init(kind: .furniture, objectID: obstacle.id))) else { continue }
            guard obstacle.roomID == room.id, let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry),
                  let boxBounds = box.geometryBounds(), safe(boxBounds), inside(boxBounds, room: bounds) else {
                b.issue(key, "unsupported_obstacle", "家具类型/尺寸/位置不受支持、无效或不属于当前房间；原数据保留，未生成替代盒体。")
                continue
            }
            b.updateFocus(key, bounds: boxBounds)
            b.node(.init(key: .init(object: key, part: "box"), geometry: .box(size: boxBounds.size), position: center(boxBounds), material: .furniture))
        }
        if project.scenarios.filter({ $0.id == scenarioID }).count == 1, let input = project.scenarios.first(where: { $0.id == scenarioID })?.inputs {
            for seat in input.usage.seats {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
                let key = SceneObjectKey(category: .seat, modelID: seat.id)
                guard b.symbol(key, title: seat.name, detail: "座位位置示意，符号大小不是椅子尺寸。", point: seat.position, roomID: seat.roomID, material: .seat, radius: 0.12, target: .object(.init(kind: .seat, objectID: seat.id))) else { continue }
                for (index,sample) in seat.samples.enumerated() {
                    _ = b.symbol(.init(category: .sample, modelID: sample.id), title: seat.name + " / 采样点 \(index+1)", detail: "模型采样坐标；球大小仅用于选择。", point: sample.position, roomID: seat.roomID, material: .sample, radius: 0.055, target: .object(.init(kind: .sample, objectID: sample.id)))
                }
            }
            for occupant in input.usage.occupants {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
                let key = SceneObjectKey(category: .occupant, modelID: occupant.id)
                guard let seat = input.usage.seats.first(where: { $0.id == occupant.seatID }) else {
                    _ = b.object(key, title: "人员记录", detail: "关联座位不存在；通过待修复人员表单修复。", target: nil)
                    b.issue(key, "occupant_seat", "人员记录没有有效座位，未猜测人员位置。")
                    continue
                }
                // The display offset keeps the linked record selectable; it is not another input point.
                _ = b.symbol(key, title: seat.name + " / 人员", detail: "关联人员示意，显示于座位上方 0.18 m；非人体几何或采样点。", point: .init(x: seat.position.x, y: seat.position.y, z: seat.position.z+0.18), roomID: seat.roomID, material: .occupant, radius: 0.08, target: .object(.init(kind: .seat, objectID: seat.id)))
            }
            for item in input.usage.equipment {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
                _ = b.symbol(.init(category: .equipment, modelID: item.id), title: "热源 · " + item.id.uuidString.prefix(6), detail: "热源点位示意，与家具实体分开。", point: item.position, roomID: item.roomID, material: .equipment, radius: 0.085, target: .object(.init(kind: .equipment, objectID: item.id)))
            }
            for device in input.hvac {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
                let key = SceneObjectKey(category: .hvac, modelID: device.id)
                guard (try? device.definition.resolved(as: SingleSplit.self, registry: registry)) != nil else {
                    _ = b.object(key, title: device.name, detail: "设备类型不受支持，原数据保留。", target: nil)
                    b.issue(key, "unsupported_hvac", "未知空调未生成机身或风口替代物。")
                    continue
                }
                guard b.symbol(key, title: device.name, detail: "室内机点位示意；当前模型没有机身尺寸或机身碰撞体。", point: device.position, roomID: device.roomID, material: .hvac, radius: 0.14, target: .object(.init(kind: .hvac, objectID: device.id))) else { continue }
                for (index,port) in device.ports.enumerated() {
                    let pkey = SceneObjectKey(category: .port, modelID: port.id)
                    guard b.symbol(pkey, title: device.name + " / " + (port.role == .supply ? "送风口" : "回风口") + " \(index+1)", detail: "风口点位与方向示意；箭头长度不代表速度。", point: port.position, roomID: device.roomID, material: port.role == .supply ? .supply : .returnPort, radius: 0.06, target: .object(.init(kind: .port, objectID: port.id))) else { continue }
                    let d = port.direction, norm = sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
                    guard [d.x,d.y,d.z,norm].allSatisfy(\.isFinite), abs(norm-1) <= 1e-6 else { b.issue(pkey, "direction_unit", "方向不是有效单位向量，未绘制或自动修正方向箭头。"); continue }
                    b.node(.init(key: .init(object: pkey, part: "direction"), geometry: .arrow(direction: d, length: 0.5, radius: 0.014), position: port.position, material: port.role == .supply ? .supply : .returnPort))
                }
            }
            for control in input.controls {
            if Task.isCancelled { b.issue(nil, "display_cancelled", "场景准备已取消。"); return b.finish() }
                guard let device = input.hvac.first(where: { $0.id == control.deviceID }) else {
                    let key = SceneObjectKey(category: .control, modelID: control.id)
                    _ = b.object(key, title: "温控测点", detail: "关联空调不存在；通过待修复控制表单修复。", target: nil)
                    b.issue(key, "control_device", "温控引用的空调不存在，未绘制。")
                    continue
                }
                _ = b.symbol(.init(category: .control, modelID: control.id), title: device.name + " / 温控测点", detail: "实际模型点位；球大小为显示选择符号。", point: control.sensorPosition, roomID: device.roomID, material: .control, radius: 0.065, target: .object(.init(kind: .control, objectID: control.id)))
            }
        } else { b.issue(nil, "scenario_missing", "当前方案身份不存在或重复，仅显示共享几何。") }
        if let angle = room.northAngle.value, angle.isFinite {
            let a = angle * .pi / 180
            b.node(.init(key: .init(object: roomKey, part: "north-reference"), geometry: .arrow(direction: .init(x: -sin(a), y: cos(a), z: 0), length: 0.5, radius: 0.012), position: .init(x: bounds.origin.x+bounds.size.x/2, y: bounds.origin.y+bounds.size.y/2, z: bounds.origin.z+0.04), material: .north, selectable: false))
        }
        return b.finish()
    }
    public static func center(_ bounds: GeometryBounds) -> Position3D { .init(x: bounds.origin.x+bounds.size.x/2, y: bounds.origin.y+bounds.size.y/2, z: bounds.origin.z+bounds.size.z/2) }
    private static func safe(_ bounds: GeometryBounds) -> Bool { safe(bounds.origin) && [bounds.size.x,bounds.size.y,bounds.size.z].allSatisfy { $0.isFinite && $0 >= 0.000001 && $0 <= 1_000_000 } }
    private static func safe(_ point: Position3D) -> Bool { [point.x,point.y,point.z].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } }
    private static func inside(_ box: GeometryBounds, room: GeometryBounds) -> Bool { room.contains(box.origin) && room.contains(.init(x: box.origin.x+box.size.x, y: box.origin.y+box.size.y, z: box.origin.z+box.size.z)) }
    private static func enclosing(_ points: [Position3D], minimumSize: Double) -> GeometryBounds {
        let xs = points.map(\.x), ys = points.map(\.y), zs = points.map(\.z)
        let lo = Position3D(x: xs.min() ?? 0, y: ys.min() ?? 0, z: zs.min() ?? 0)
        return .init(origin: lo, size: .init(x: max(minimumSize,(xs.max() ?? 0)-lo.x), y: max(minimumSize,(ys.max() ?? 0)-lo.y), z: max(minimumSize,(zs.max() ?? 0)-lo.z)))
    }
    public static func faceTitle(_ face: SurfaceFace) -> String {
        switch face { case .xMin: "X 最小侧墙"; case .xMax: "X 最大侧墙"; case .yMin: "Y 最小侧墙"; case .yMax: "Y 最大侧墙"; case .floor: "地面"; case .ceiling: "天花板" }
    }
    private struct Builder {
        let projectID: UUID
        let scenarioID: UUID
        var roomID: UUID?
        var bounds: GeometryBounds?
        var nodes: [RoomSceneNode] = []
        var objects: [RoomSceneObject] = []
        var issues: [RoomSceneIssue] = []
        var keys: Set<SceneObjectKey> = []
        var nodeKeys: Set<SceneNodeKey> = []
        var modelIDs: Set<UUID> = []
        var issueKeys: Set<String> = []
        mutating func issue(_ key: SceneObjectKey?, _ code: String, _ message: String) {
            let value = RoomSceneIssue(key: key, code: code, message: message)
            if issueKeys.insert(value.id).inserted {
                issues.append(value)
                if let key, let index = objects.firstIndex(where: { $0.key == key }) {
                    let item = objects[index]
                    objects[index] = .init(key: item.key, title: item.title, detail: item.detail + " " + message, target: item.target, focusBounds: item.focusBounds)
                }
            }
        }
        mutating func object(_ key: SceneObjectKey, title: String, detail: String, target: RoomSceneSelectionTarget?) -> Bool {
            guard keys.insert(key).inserted, modelIDs.insert(key.modelID).inserted else { issue(key, "duplicate_id", "模型身份重复，未绘制重复对象。请先修复项目。"); return false }
            guard objects.count < 8192 else { issue(nil, "object_budget", "对象超过 8192 个显示上限；未显示的输入仍保留。"); return false }
            objects.append(.init(key: key, title: title, detail: detail, target: target)); return true
        }
        mutating func updateFocus(_ key: SceneObjectKey, bounds: GeometryBounds) {
            guard let index = objects.firstIndex(where: { $0.key == key }) else { return }
            let item = objects[index]
            objects[index] = .init(key: key, title: item.title, detail: item.detail, target: item.target, focusBounds: bounds)
        }
        mutating func node(_ node: RoomSceneNode) {
            guard nodeKeys.insert(node.key).inserted else { issue(node.key.object, "duplicate_node", "显示节点重复，已排除重复项。"); return }
            guard nodes.count < 8192 else { issue(nil, "node_budget", "显示节点超过 8192 个上限，部分对象未显示。"); return }
            nodes.append(node)
        }
        mutating func symbol(_ key: SceneObjectKey, title: String, detail: String, point: Position3D, roomID: UUID, material: RoomSceneMaterial, radius: Double, target: RoomSceneSelectionTarget?) -> Bool {
            guard object(key, title: title, detail: detail, target: target) else { return false }
            guard roomID == self.roomID, let bounds, RoomSceneBuilder.safe(point), bounds.contains(point) else {
                issue(key, "invalid_position", "点位无效、越界或不属于显示房间；未猜测位置。")
                return false
            }
            updateFocus(key, bounds: .init(origin: .init(x: point.x-radius, y: point.y-radius, z: point.z-radius), size: .init(x: radius*2, y: radius*2, z: radius*2)))
            node(.init(key: .init(object: key, part: "symbol"), geometry: .sphere(radius: radius), position: point, material: material)); return true
        }
        func finish() -> SceneDescriptor { .init(projectID: projectID, scenarioID: scenarioID, roomID: roomID, bounds: bounds, nodes: nodes, objects: objects, issues: issues) }
    }
}
