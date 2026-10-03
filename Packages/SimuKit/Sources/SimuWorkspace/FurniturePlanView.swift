import SwiftUI
import SimuCore
import SimuVisualization

/// Top-down drag-to-place editor for furniture (user request 2026-10-04).
///
/// Why a top-down plan instead of 3D dragging: RealityView exposes no public
/// screen→world raycast, so a 3D drop cannot be made honest without a custom
/// camera rewrite. A plan view is exact — screen metres ARE room metres — and
/// the same `FurniturePlacement.rejection` the store applies runs live on
/// every drag frame, so a box the solver would choke on can never land.
/// The numeric obstacle editor stays as the accessible alternative.
struct FurniturePlanView: View {
    @Bindable var store: WorkspaceStore
    /// What a drop on empty floor becomes. The segmented picker above the
    /// plan sets it; dragging an existing box keeps that box's kind.
    @State private var pendingKind: FurnitureKind = .desk
    /// Live drag state: moving an existing box (with grab offset so it does
    /// not jump to the finger) or placing a fresh one at the finger.
    @State private var drag: PlanDrag?
    /// Live ghost while dragging: the candidate box and whether it may land.
    @State private var ghost: GhostBox?

    /// Origin snap grid in metres, so drops land on reproducible numbers and
    /// the L2 blocked-cell set stays deterministic for a given placement.
    private let snapM = 0.05
    private let planPadding: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("家具类型", selection: $pendingKind) {
                ForEach(FurnitureKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("要在空白处拖入的家具类型")

            planCanvas
                .frame(minHeight: 300)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint("在空白处拖入\(pendingKind.title)，或按住已有家具拖动换位置，松手时合法才生效")

            Text(store.furniturePlacementMessage ?? hint)
                .font(.footnote)
                .foregroundStyle(store.furniturePlacementMessage == nil ? Color.secondary : Color.red)
                .accessibilityLabel(store.furniturePlacementMessage ?? hint)
        }
    }

    // MARK: - Plan canvas

    private var planCanvas: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in onChanged(value, in: proxy.size) }
                    .onEnded { value in onEnded(value, in: proxy.size) }
            )
        }
    }

    /// Screen metres: x runs right, y runs down (the near wall at the bottom).
    /// Same mapping both ways, so a hit test and a draw can never disagree.
    private func transform(scene: RoomScene, in size: CGSize) -> (scale: CGFloat, origin: CGPoint)? {
        guard scene.sizeXM > 0, scene.sizeYM > 0, size.width > planPadding * 2, size.height > planPadding * 2 else {
            return nil
        }
        let usable = CGSize(width: size.width - planPadding * 2, height: size.height - planPadding * 2)
        let scale = min(usable.width / scene.sizeXM, usable.height / scene.sizeYM)
        let origin = CGPoint(
            x: planPadding + (usable.width - scene.sizeXM * scale) / 2,
            y: planPadding + (usable.height - scene.sizeYM * scale) / 2
        )
        return (scale, origin)
    }

    private func toScreen(_ x: Double, _ y: Double, _ t: (scale: CGFloat, origin: CGPoint)) -> CGPoint {
        CGPoint(x: t.origin.x + x * t.scale, y: t.origin.y + y * t.scale)
    }

    /// Screen point → floor metres; nil outside the canvas.
    private func toMetres(_ point: CGPoint, scene: RoomScene, _ t: (scale: CGFloat, origin: CGPoint)) -> Position3D? {
        let x = (Double(point.x) - Double(t.origin.x)) / Double(t.scale)
        let y = (Double(point.y) - Double(t.origin.y)) / Double(t.scale)
        return Position3D(x: x, y: y, z: 0)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let scene = store.project.flatMap(RoomScene.init(draft:)),
            let t = transform(scene: scene, in: size) else {
            return
        }
        drawRoom(scene: scene, t: t, in: &context)
        drawGrid(scene: scene, t: t, in: &context)
        drawSolvedBands(scene: scene, t: t, in: &context)
        drawOpenings(scene: scene, t: t, in: &context)
        drawSeats(scene: scene, t: t, in: &context)
        drawFurniture(scene: scene, t: t, in: &context)
        if let ghost {
            drawBox(ghost.box, t: t, label: nil, color: ghost.isLegal ? Color.green : Color.red, in: &context)
        }
    }

    // MARK: - Drawing parts

    private func drawRoom(scene: RoomScene, t: (scale: CGFloat, origin: CGPoint), in context: inout GraphicsContext) {
        var path = Path()
        path.addRect(CGRect(origin: toScreen(0, 0, t), size: CGSize(width: scene.sizeXM * t.scale, height: scene.sizeYM * t.scale)))
        context.fill(path, with: .color(.primary.opacity(0.04)))
        context.stroke(path, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
    }

    private func drawGrid(scene: RoomScene, t: (scale: CGFloat, origin: CGPoint), in context: inout GraphicsContext) {
        var metre: Double = 1
        while metre < max(scene.sizeXM, scene.sizeYM) {
            if metre < scene.sizeXM {
                var path = Path()
                let p0 = toScreen(metre, 0, t)
                let p1 = toScreen(metre, scene.sizeYM, t)
                path.move(to: p0)
                path.addLine(to: p1)
                context.stroke(path, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)
            }
            if metre < scene.sizeYM {
                var path = Path()
                let p0 = toScreen(0, metre, t)
                let p1 = toScreen(scene.sizeXM, metre, t)
                path.move(to: p0)
                path.addLine(to: p1)
                context.stroke(path, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)
            }
            metre += 1
        }
    }

    /// The solved supply/return bands: the case writer stretches each terminal
    /// to the FULL wall span at its height, so the plan marks that whole band
    /// as keep-clear — the drag preview refuses a drop that would remove
    /// inlet/outlet cells and break the mass gate.
    private func drawSolvedBands(scene: RoomScene, t: (scale: CGFloat, origin: CGPoint), in context: inout GraphicsContext) {
        let bandWidth: CGFloat = 5
        func bandPath(wall: WallFace, span: Double) -> Path {
            var path = Path()
            switch wall {
            case .xMin:
                let p0 = toScreen(0, 0, t)
                path.move(to: p0)
                path.addLine(to: toScreen(0, span, t))
            case .xMax:
                let p0 = toScreen(scene.sizeXM, 0, t)
                path.move(to: p0)
                path.addLine(to: toScreen(scene.sizeXM, span, t))
            case .yMin:
                let p0 = toScreen(0, 0, t)
                path.move(to: p0)
                path.addLine(to: toScreen(span, 0, t))
            case .yMax:
                let p0 = toScreen(0, scene.sizeYM, t)
                path.move(to: p0)
                path.addLine(to: toScreen(span, scene.sizeYM, t))
            }
            return path
        }
        if let supply = scene.supply {
            let span: Double
            switch supply.wall {
            case .xMin, .xMax: span = scene.sizeYM
            case .yMin, .yMax: span = scene.sizeXM
            }
            context.stroke(
                bandPath(wall: supply.wall, span: span),
                with: .color(.blue.opacity(0.7)),
                style: StrokeStyle(lineWidth: bandWidth, dash: [6, 4])
            )
        }
        if let returnAir = scene.returnAir {
            let span: Double
            switch returnAir.wall {
            case .xMin, .xMax: span = scene.sizeYM
            case .yMin, .yMax: span = scene.sizeXM
            }
            context.stroke(
                bandPath(wall: returnAir.wall, span: span),
                with: .color(.orange.opacity(0.7)),
                style: StrokeStyle(lineWidth: bandWidth, dash: [6, 4])
            )
        }
    }

    /// Windows keep their own rectangle on the case mesh (per-window patches),
    /// so the plan marks the exact s-range, not a full-wall band.
    private func drawOpenings(scene: RoomScene, t: (scale: CGFloat, origin: CGPoint), in context: inout GraphicsContext) {
        let width: CGFloat = 4
        for window in scene.windows {
            var path = Path()
            let (p0, p1) = wallSegment(window, scene: scene, t: t)
            path.move(to: p0)
            path.addLine(to: p1)
            context.stroke(path, with: .color(.blue), lineWidth: width)
        }
        for door in scene.doors {
            var path = Path()
            let (p0, p1) = wallSegment(door, scene: scene, t: t)
            path.move(to: p0)
            path.addLine(to: p1)
            context.stroke(path, with: .color(.secondary.opacity(0.8)), lineWidth: width)
        }
    }

    /// A wall patch as a plan segment on its wall, s along the wall.
    private func wallSegment(
        _ patch: WallPatchScene,
        scene: RoomScene,
        t: (scale: CGFloat, origin: CGPoint)
    ) -> (CGPoint, CGPoint) {
        switch patch.wall {
        case .xMin:
            return (toScreen(0, patch.s0M, t), toScreen(0, patch.s1M, t))
        case .xMax:
            return (toScreen(scene.sizeXM, patch.s0M, t), toScreen(scene.sizeXM, patch.s1M, t))
        case .yMin:
            return (toScreen(patch.s0M, 0, t), toScreen(patch.s1M, 0, t))
        case .yMax:
            return (toScreen(patch.s0M, scene.sizeYM, t), toScreen(patch.s1M, scene.sizeYM, t))
        }
    }

    private func drawSeats(scene: RoomScene, t: (scale: CGFloat, origin: CGPoint), in context: inout GraphicsContext) {
        for seat in scene.seats {
            let center = toScreen(seat.position.x, seat.position.y, t)
            let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.7)))
        }
    }

    private func drawFurniture(scene: RoomScene, t: (scale: CGFloat, origin: CGPoint), in context: inout GraphicsContext) {
        for box in scene.furniture {
            drawBox(box, t: t, label: box.displayName, color: planColor(box.kind), in: &context)
        }
    }

    private func drawBox(
        _ box: FurnitureScene,
        t: (scale: CGFloat, origin: CGPoint),
        label: String?,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let origin = toScreen(box.origin.x, box.origin.y + box.size.y, t)
        let rect = CGRect(
            origin: origin,
            size: CGSize(width: box.size.x * t.scale, height: box.size.y * t.scale)
        )
        var path = Path()
        path.addRect(rect)
        context.fill(path, with: .color(color.opacity(0.4)))
        context.stroke(path, with: .color(color), lineWidth: 1.5)
        if let label {
            context.draw(
                Text(label).font(.caption2),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
        }
    }

    private func planColor(_ kind: FurnitureKind) -> Color {
        switch kind {
        case .desk: .brown
        case .chair: .blue
        case .cabinet: .orange
        case .screen: .gray
        }
    }

    // MARK: - Drag logic

    private func onChanged(_ value: DragGesture.Value, in size: CGSize) {
        guard let scene = store.project.flatMap(RoomScene.init(draft:)),
            let t = transform(scene: scene, in: size) else {
            return
        }
        // First move decides the mode: a finger on an existing box moves it;
        // anywhere else starts a fresh box of the picked kind.
        if drag == nil {
            if let point = toMetres(value.startLocation, scene: scene, t),
                let hit = hitTest(point, scene: scene) {
                let offset = Position3D(
                    x: point.x - hit.origin.x,
                    y: point.y - hit.origin.y,
                    z: 0
                )
                drag = .movingExisting(hit.id, offset)
            } else {
                drag = .placingNew
            }
        }
        guard let point = toMetres(value.location, scene: scene, t) else {
            return
        }
        let candidate: ObstacleBox
        switch drag {
        case .movingExisting(let id, let offset):
            guard let existing = store.project?.geometry?.obstacles.first(where: { $0.id == id }) else {
                drag = nil
                ghost = nil
                return
            }
            let originX = snap(point.x - offset.x)
            let originY = snap(point.y - offset.y)
            candidate = ObstacleBox(
                id: id,
                origin: Position3D(x: originX, y: originY, z: existing.origin.z),
                size: existing.size,
                kind: existing.kind
            )
        case .placingNew, .none:
            let size = pendingKind.defaultSize
            let originX = snap(point.x - size.x / 2)
            let originY = snap(point.y - size.y / 2)
            candidate = ObstacleBox(
                id: ProjectDraft.nextPrefixedID(
                    prefix: "F",
                    existing: store.project?.geometry?.obstacles.map(\.id) ?? []
                ),
                origin: Position3D(x: originX, y: originY, z: 0),
                size: size,
                kind: pendingKind
            )
        }
        // Live legality on every frame: the ghost is green only when the
        // same rule the store will apply on release says the box may land.
        let ignoring: String?
        if case .movingExisting(let id, _) = drag {
            ignoring = id
        } else {
            ignoring = nil
        }
        let rejection = store.project.map {
            FurniturePlacement.rejection(for: candidate, in: $0, ignoring: ignoring)
        }
        ghost = GhostBox(
            box: FurnitureScene(
                id: candidate.id,
                origin: candidate.origin,
                size: candidate.size,
                kind: candidate.kind,
                displayName: ""
            ),
            isLegal: rejection == nil
        )
    }

    private func onEnded(_ value: DragGesture.Value, in size: CGSize) {
        defer {
            drag = nil
            ghost = nil
        }
        guard let ghost else {
            return
        }
        store.applyObstacle(
            id: ghost.box.id,
            origin: ghost.box.origin,
            size: ghost.box.size,
            kind: ghost.box.kind
        )
    }

    /// Existing furniture under a plan point, topmost wins.
    private func hitTest(_ point: Position3D, scene: RoomScene) -> FurnitureScene? {
        for box in scene.furniture.reversed() {
            let x0 = box.origin.x
            let x1 = box.origin.x + box.size.x
            let y0 = box.origin.y
            let y1 = box.origin.y + box.size.y
            if point.x >= x0, point.x <= x1, point.y >= y0, point.y <= y1 {
                return box
            }
        }
        return nil
    }

    private func snap(_ value: Double) -> Double {
        (value / snapM).rounded() * snapM
    }

    // MARK: - Copy

    private var hint: String {
        "在空白处按下并拖动，松手时放入\(pendingKind.title)；按住已有家具可拖动换位置。虚线蓝带是送风墙，橙带是回风墙，家具不能挡住它们或窗户。"
    }

    private var accessibilityText: String {
        guard let scene = store.project.flatMap(RoomScene.init(draft:)) else {
            return "还没有房间尺寸，不能布置家具"
        }
        var text = "俯视图，房间 \(UserFacingCopy.displayNumber(scene.sizeXM)) × \(UserFacingCopy.displayNumber(scene.sizeYM)) 米"
        if !scene.furniture.isEmpty {
            text += "，已放 \(scene.furniture.map(\.displayName).joined(separator: "、"))"
        } else {
            text += "，还没有家具"
        }
        text += "。用数值编辑器可精确放置。"
        return text
    }
}

/// One in-flight drag.
private enum PlanDrag {
    case movingExisting(String, Position3D)
    case placingNew
}

/// The live candidate while dragging: green means it may land.
private struct GhostBox {
    var box: FurnitureScene
    var isLegal: Bool
}
