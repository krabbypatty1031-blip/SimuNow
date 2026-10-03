import Foundation
import Testing
@testable import SimuCore

// 用户要求 2026-10-04：家具按类型拖入，只能放在房间内且不与其他物品重叠的
// 位置。这里钉住 FurniturePlacement 的每条拒绝分支与旧项目包的解码兼容：
// 放置规则是 UI 与引擎 intake 的同一裁判，规则漂移会直接破坏
// L2 的送回风带和窗户 patch。

/// 6×6×2.8 房间 + 默认分体空调（送/回风口都在 xMin 墙）的测试底稿。
private func placementDraft() -> ProjectDraft {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    return draft
}

@Test func obstacleJSONWithoutKindDecodesAsDesk() throws {
    // 旧项目包没有 kind 字段：按原来的桌子盒解码，文件不能失效。
    let json = """
    {"id":"F1","origin":{"x":1,"y":2,"z":0},"size":{"x":1.2,"y":0.6,"z":0.75}}
    """
    let box = try JSONDecoder().decode(ObstacleBox.self, from: Data(json.utf8))
    #expect(box.id == "F1")
    #expect(box.kind == .desk)
}

@Test func legalPlacementHasNoRejection() {
    let draft = placementDraft()
    let box = ObstacleBox(id: "F1", origin: Position3D(x: 1, y: 1, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75))
    #expect(FurniturePlacement.rejection(for: box, in: draft) == nil)
}

@Test func boxOutsideRoomIsRefused() {
    let draft = placementDraft()
    let box = ObstacleBox(id: "F1", origin: Position3D(x: 5.5, y: 1, z: 0), size: Position3D(x: 1.0, y: 0.7, z: 0.75))
    #expect(FurniturePlacement.rejection(for: box, in: draft) == .outsideRoom)
}

@Test func overlappingFurnitureIsRefusedButItsOwnEditIsNot() throws {
    var draft = placementDraft()
    let existing = ObstacleBox(id: "F1", origin: Position3D(x: 1, y: 1, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75))
    _ = draft.upsertObstacle(existing)
    let overlapping = ObstacleBox(id: "F2", origin: Position3D(x: 1.5, y: 1.2, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75))
    #expect(FurniturePlacement.rejection(for: overlapping, in: draft) == .overlapsFurniture)
    // 原位微调 F1 自己：不与自己碰撞。
    let moved = ObstacleBox(id: "F1", origin: Position3D(x: 1.1, y: 1.05, z: 0), size: existing.size)
    #expect(FurniturePlacement.rejection(for: moved, in: draft, ignoring: "F1") == nil)
}

@Test func boxCoveringASeatIsRefused() throws {
    var draft = placementDraft()
    _ = draft.applySeat(id: "S1", position: Position3D(x: 2.0, y: 2.0, z: 1.1), source: .user)
    let box = ObstacleBox(id: "F1", origin: Position3D(x: 1.6, y: 1.6, z: 0), size: Position3D(x: 1.0, y: 1.0, z: 1.8))
    #expect(FurniturePlacement.rejection(for: box, in: draft) == .coversSeat)
}

@Test func boxInFrontOfTerminalBandIsRefused() {
    let draft = placementDraft()
    // 送/回风口都在 xMin 墙：解算带占满整面墙的对应高度。箱子伸进
    // 墙内侧 0.4 m 净空且高度盖住带，会删掉 inlet/outlet 的 cell。
    let box = ObstacleBox(id: "F1", origin: Position3D(x: 0.2, y: 2.8, z: 0), size: Position3D(x: 0.3, y: 1.0, z: 2.8))
    #expect(FurniturePlacement.rejection(for: box, in: draft) == .blocksTerminal)
    // 同样高度但离墙足够远的箱子不挡风口。
    let clear = ObstacleBox(id: "F2", origin: Position3D(x: 0.5, y: 2.8, z: 0), size: Position3D(x: 0.3, y: 1.0, z: 2.8))
    #expect(FurniturePlacement.rejection(for: clear, in: draft) == nil)
}

@Test func boxInFrontOfWindowIsRefused() throws {
    var draft = placementDraft()
    _ = draft.applyOpening(
        id: "W1",
        kind: .window,
        wall: .xMax,
        s0: 2.5,
        s1: 3.5,
        z0: 0.9,
        z1: 2.2,
        source: .user
    )
    let box = ObstacleBox(id: "F1", origin: Position3D(x: 5.6, y: 2.6, z: 0), size: Position3D(x: 0.4, y: 0.8, z: 1.8))
    #expect(FurniturePlacement.rejection(for: box, in: draft) == .blocksWindow)
    // 离开窗户贴墙投影体积的箱子合法。
    let clear = ObstacleBox(id: "F2", origin: Position3D(x: 5.0, y: 2.6, z: 0), size: Position3D(x: 0.4, y: 0.8, z: 1.8))
    #expect(FurniturePlacement.rejection(for: clear, in: draft) == nil)
}

@Test func furnitureKindsCarryTitlesAndPositiveFootprints() {
    for kind in FurnitureKind.allCases {
        #expect(!kind.title.isEmpty)
        #expect(kind.defaultSize.x > 0)
        #expect(kind.defaultSize.y > 0)
        #expect(kind.defaultSize.z > 0)
    }
    #expect(FurnitureKind.desk.title == "桌子")
    #expect(FurnitureKind.chair.title == "椅子")
    #expect(FurnitureKind.cabinet.title == "柜子")
    #expect(FurnitureKind.screen.title == "屏风")
}
