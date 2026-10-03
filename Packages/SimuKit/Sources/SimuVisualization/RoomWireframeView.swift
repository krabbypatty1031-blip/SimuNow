import SwiftUI
import SimuCore

/// Wireframe of the real draft geometry: room box, windows, supply/return
/// terminals and seat markers. A quality-passed field slice paints the
/// seat-height plane with its own legend; no field means no colour - an
/// illustrative rainbow is never drawn.
public struct RoomWireframeView: View {
    private let scene: RoomScene
    private let field: FieldSlice?
    /// Shared comparison palette (P4-06): candidates render against one
    /// physical range instead of renormalising individually. nil keeps the
    /// slice's own range, which is the single-run behaviour.
    private let sharedPalette: SlicePalette?
    /// External yaw so the comparison page can keep one camera for several
    /// candidates. nil keeps a private, self-contained camera.
    private let externalYaw: Binding<Double>?
    @State private var internalYaw: Double = -0.6
    @State private var dragStartYaw: Double?

    public init(scene: RoomScene, field: FieldSlice? = nil, sharedPalette: SlicePalette? = nil, yaw: Binding<Double>? = nil) {
        self.scene = scene
        self.field = field
        self.sharedPalette = sharedPalette
        self.externalYaw = yaw
    }

    /// The live camera binding: external when provided, private otherwise.
    private var yaw: Binding<Double> {
        externalYaw ?? $internalYaw
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, canvasSize in
                draw(in: &context, canvasSize: canvasSize)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .bottom) {
                if let field, let palette {
                    legend(for: palette)
                        .padding(.bottom, 12)
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Horizontal drag spins the room; no gesture changes data.
                    let base = dragStartYaw ?? yaw.wrappedValue
                    dragStartYaw = base
                    yaw.wrappedValue = base + value.translation.width * 0.01
                }
                .onEnded { _ in dragStartYaw = nil }
        )
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(Text("水平拖动旋转房间视图"))
        .accessibilityIdentifier("roomWireframe")
    }

    private var palette: SlicePalette? {
        // A shared palette wins so candidates compare on one physical range;
        // otherwise the slice's own quality-passed range is used.
        if let sharedPalette {
            return sharedPalette
        }
        // Colour exists only for a quality-passed field with valid stats.
        guard let field, field.quality == "passed",
              let minC = field.stats.minC, let maxC = field.stats.maxC else {
            return nil
        }
        return SlicePalette(minC: minC, maxC: maxC)
    }

    private var accessibilityText: String {
        var text = scene.accessibilitySummary
        if let field, let minC = field.stats.minC, let maxC = field.stats.maxC {
            text += String(
                format: "，坐姿高度温度切片 %.1f 到 %.1f 摄氏度（质量通过）",
                minC,
                maxC
            )
        }
        return text
    }

    /// Legend shows the physical range with the unit; the range is evidence.
    private func legend(for palette: SlicePalette) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.color(forC: palette.minC),
                            palette.color(forC: palette.minC + (palette.maxC - palette.minC) * 0.5),
                            palette.color(forC: palette.maxC),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 120, height: 10)
            Text(palette.legendText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text("温度色标 \(palette.legendText)"))
    }

    /// All geometry is projected first, then fitted with one uniform scale so
    /// the room keeps its proportions; padding leaves room for the legend.
    private func draw(in context: inout GraphicsContext, canvasSize: CGSize) {
        let projection = IsometricProjection(yawRadians: yaw.wrappedValue)
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
        if let field, let palette {
            allPoints.append(contentsOf: slicePoints(field, projection: projection))
        }
        guard let fit = Self.fitTransform(points: allPoints, in: canvasSize) else {
            return
        }

        // The field slice paints first (seat-height plane); invalid cells get
        // the neutral colour and never a temperature one.
        if let field, let palette {
            drawSlice(field, palette: palette, projection: projection, fit: fit, in: &context)
        }

        // Wall patches next so the wireframe stays readable on top.
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

    /// Every slice cell centre, projected (used for fitting the view).
    private func slicePoints(_ field: FieldSlice, projection: IsometricProjection) -> [CGPoint] {
        var points: [CGPoint] = []
        let nx = field.shape.nx
        let ny = field.shape.ny
        let ox = field.originM.x
        let oy = field.originM.y
        let sx = field.spacingM.x
        let sy = field.spacingM.y
        for j in 0..<ny {
            for i in 0..<nx {
                // Cell-centred grid: values[j][i] lives at (ox + i*sx, oy + j*sy).
                let x = ox + Double(i) * sx
                let y = oy + Double(j) * sy
                points.append(projection.screenPoint(Position3D(x: x, y: y, z: field.zM)))
            }
        }
        return points
    }

    private func drawSlice(
        _ field: FieldSlice,
        palette: SlicePalette,
        projection: IsometricProjection,
        fit: (scale: CGFloat, offset: CGSize),
        in context: inout GraphicsContext
    ) {
        let nx = field.shape.nx
        let ny = field.shape.ny
        let ox = field.originM.x
        let oy = field.originM.y
        let sx = field.spacingM.x
        let sy = field.spacingM.y
        for j in 0..<ny {
            for i in 0..<nx {
                // Cell rectangle: [x - sx/2, x + sx/2] x [y - sy/2, y + sy/2]
                // at the slice height, in the computation frame.
                let x = ox + Double(i) * sx
                let y = oy + Double(j) * sy
                let corners = [
                    Position3D(x: x - sx / 2, y: y - sy / 2, z: field.zM),
                    Position3D(x: x + sx / 2, y: y - sy / 2, z: field.zM),
                    Position3D(x: x + sx / 2, y: y + sy / 2, z: field.zM),
                    Position3D(x: x - sx / 2, y: y + sy / 2, z: field.zM),
                ].map(projection.screenPoint)
                let path = Self.closedPath(corners, transform: fit)
                let isFieldCell = j < field.valid.count && i < (field.valid[j].count)
                    ? field.valid[j][i]
                    : false
                if isFieldCell, j < field.values.count, i < field.values[j].count {
                    context.fill(path, with: .color(palette.color(forC: field.values[j][i])))
                } else {
                    // Wall/furniture interiors: neutral, excluded from stats.
                    context.fill(path, with: .color(SlicePalette.invalidColor))
                }
            }
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
