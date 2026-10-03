import SwiftUI
import SimuCore

/// Wireframe of the real draft geometry: room box, windows, supply/return
/// terminals and seat markers. No field colour is painted here - a slice
/// needs a quality-passed field (P4-05c) and never an illustrative rainbow.
public struct RoomWireframeView: View {
    private let scene: RoomScene
    @State private var yaw: Double = -0.6
    @State private var dragStartYaw: Double?

    public init(scene: RoomScene) {
        self.scene = scene
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, canvasSize in
                draw(in: &context, canvasSize: canvasSize)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Horizontal drag spins the room; no gesture changes data.
                    let base = dragStartYaw ?? yaw
                    dragStartYaw = base
                    yaw = base + value.translation.width * 0.01
                }
                .onEnded { _ in dragStartYaw = nil }
        )
        .accessibilityLabel(Text(scene.accessibilitySummary))
        .accessibilityHint(Text("水平拖动旋转房间视图"))
        .accessibilityIdentifier("roomWireframe")
    }

    /// All geometry is projected first, then fitted with one uniform scale so
    /// the room keeps its proportions; padding leaves room for the legend.
    private func draw(in context: inout GraphicsContext, canvasSize: CGSize) {
        let projection = IsometricProjection(yawRadians: yaw)
        let roomPoints = projection.roomCorners(scene)
        var allPoints = roomPoints
        if let supply = scene.supply {
            allPoints.append(contentsOf: projection.patchCorners(supply, in: scene))
        }
        if let returnAir = scene.returnAir {
            allPoints.append(contentsOf: projection.patchCorners(returnAir, in: scene))
        }
        for window in scene.windows {
            allPoints.append(contentsOf: projection.patchCorners(window, in: scene))
        }
        for seat in scene.seats {
            allPoints.append(projection.screenPoint(seat.position))
        }
        guard let fit = Self.fitTransform(points: allPoints, in: canvasSize) else {
            return
        }

        // Wall patches first so the wireframe stays readable on top.
        for window in scene.windows {
            let path = Self.closedPath(projection.patchCorners(window, in: scene), transform: fit)
            context.fill(path, with: .color(.blue.opacity(0.12)))
            context.stroke(path, with: .color(.blue), lineWidth: 1.5)
        }
        if let supply = scene.supply {
            let path = Self.closedPath(projection.patchCorners(supply, in: scene), transform: fit)
            context.fill(path, with: .color(.blue.opacity(0.18)))
            context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
        }
        if let returnAir = scene.returnAir {
            let path = Self.closedPath(projection.patchCorners(returnAir, in: scene), transform: fit)
            context.fill(path, with: .color(.orange.opacity(0.18)))
            context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
        }

        // Room box wireframe.
        let edges = RoomScene.roomEdgeIndices
        for (a, b) in edges {
            var path = Path()
            path.move(to: Self.apply(roomPoints[a], transform: fit))
            path.addLine(to: Self.apply(roomPoints[b], transform: fit))
            context.stroke(path, with: .color(.primary.opacity(0.75)), lineWidth: 1.5)
        }

        // Seat markers: sample points, drawn on top so they stay visible.
        for seat in scene.seats {
            let center = Self.apply(projection.screenPoint(seat.position), transform: fit)
            let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(.primary))
        }
    }

    /// Uniform scale + offset that centers the projected bounding box with
    /// padding; returns nil when there is nothing to fit.
    private static func fitTransform(points: [CGPoint], in size: CGSize) -> (scale: CGFloat, offset: CGSize)? {
        guard !points.isEmpty, size.width > 0, size.height > 0 else {
            return nil
        }
        let padding: CGFloat = 48
        let usable = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)
        guard usable.width > 0, usable.height > 0 else {
            return nil
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = max(xs.max()! - xs.min()!, 1e-6)
        let height = max(ys.max()! - ys.min()!, 1e-6)
        let scale = min(usable.width / width, usable.height / height)
        let offsetX = padding + (usable.width - width * scale) / 2 - xs.min()! * scale
        let offsetY = padding + (usable.height - height * scale) / 2 - ys.min()! * scale
        return (scale, CGSize(width: offsetX, height: offsetY))
    }

    private static func apply(_ point: CGPoint, transform: (scale: CGFloat, offset: CGSize)) -> CGPoint {
        CGPoint(x: point.x * transform.scale + transform.offset.width,
                y: point.y * transform.scale + transform.offset.height)
    }

    private static func closedPath(_ points: [CGPoint], transform: (scale: CGFloat, offset: CGSize)) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }
        path.move(to: apply(first, transform: transform))
        for point in points.dropFirst() {
            path.addLine(to: apply(point, transform: transform))
        }
        path.closeSubpath()
        return path
    }
}
