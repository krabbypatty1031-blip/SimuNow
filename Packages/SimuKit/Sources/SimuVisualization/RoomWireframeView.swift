import SwiftUI
import SimuCore

/// Wireframe of the real draft geometry: room box, windows, supply/return
/// terminals and seat markers. A quality-passed field slice paints the
/// seat-height plane with its own legend; no field means no colour - an
/// illustrative rainbow is never drawn.
public struct RoomWireframeView: View {
    private let scene: RoomScene
    private let field: FieldSlice?
    private let flow: FlowOverlay?
    /// Shared comparison palette (P4-06): candidates render against one
    /// physical range instead of renormalising individually. nil keeps the
    /// slice's own range, which is the single-run behaviour.
    private let sharedPalette: SlicePalette?
    /// External yaw so the comparison page can keep one camera for several
    /// candidates. nil keeps a private, self-contained camera.
    private let externalYaw: Binding<Double>?
    /// Quality-passed L2 seat samples. When a sample matches a seat id the
    /// seat label carries its air temperature; missing samples show the
    /// plain seat name, never a fabricated number.
    private let seatSamples: [SeatSample]?
    @State private var internalYaw: Double = -0.6
    @State private var dragStartYaw: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.userFacingCopy) private var copy

    public init(
        scene: RoomScene,
        field: FieldSlice? = nil,
        flow: FlowOverlay? = nil,
        sharedPalette: SlicePalette? = nil,
        yaw: Binding<Double>? = nil,
        seatSamples: [SeatSample]? = nil
    ) {
        self.scene = scene
        self.field = field
        self.flow = flow
        self.sharedPalette = sharedPalette
        self.externalYaw = yaw
        self.seatSamples = seatSamples
    }

    /// The live camera binding: external when provided, private otherwise.
    private var yaw: Binding<Double> {
        externalYaw ?? $internalYaw
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animatesFlow)) { timeline in
                Canvas { context, canvasSize in
                    draw(
                        in: &context,
                        canvasSize: canvasSize,
                        phase: RoomDisplayLayout.flowParticlePhase(at: timeline.date)
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(alignment: .bottom) {
                    if palette != nil || flow != nil {
                        ViewportLegend(palette: palette, flow: flow)
                            .padding(.bottom, 12)
                    }
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
        .accessibilityHint(Text(copy.rotateRoomHint))
        .accessibilityIdentifier("roomWireframe")
    }

    private var palette: SlicePalette? {
        SlicePalette.resolved(field: field, shared: sharedPalette)
    }

    private var accessibilityText: String {
        var text = scene.accessibilitySummary(copy: copy)
        if let field, let minC = field.stats.minC, let maxC = field.stats.maxC {
            text += copy.sliceAccessibility(
                min: UserFacingCopy.displayNumber(minC),
                max: UserFacingCopy.displayNumber(maxC)
            )
        }
        if let flow, let maxMag = flow.stats.maxMag {
            text += copy.flowAccessibility(max: UserFacingCopy.displayNumber(maxMag))
        }
        let seatTemps = scene.seats.compactMap { seat -> String? in
            guard let sample = seatSample(for: seat) else { return nil }
            return copy.seatTemperatureLabel(name: seat.displayName, value: UserFacingCopy.displayNumber(sample.tC))
        }
        if !seatTemps.isEmpty {
            text += copy.seatTemperaturesAccessibility(seatTemps.joined(separator: copy.listSeparator))
        }
        return text
    }

    private var animatesFlow: Bool {
        !reduceMotion && flow?.quality == "passed" && !(flow?.lines.isEmpty ?? true)
    }

    /// All geometry is projected first, then fitted with one uniform scale so
    /// the room keeps its proportions; padding leaves room for the legend.
    private func draw(in context: inout GraphicsContext, canvasSize: CGSize, phase: Double) {
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
        if let field, palette != nil {
            allPoints.append(contentsOf: slicePoints(field, projection: projection))
        }
        if let flow {
            allPoints.append(contentsOf: flowPoints(flow, projection: projection))
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

        if let flow {
            drawFlow(flow, projection: projection, fit: fit, phase: phase, in: &context)
        }

        // Seat markers: sample points, drawn on top so they stay visible.
        // An L2 sample for this seat id appends its air temperature.
        for seat in scene.seats {
            let center = Self.apply(projection.screenPoint(seat.position), transform: fit)
            let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(.primary))
            context.draw(
                Text(RoomDisplayLayout.seatLabelText(seat: seat, sample: seatSample(for: seat)))
                    .font(.caption2),
                at: CGPoint(x: center.x + 10, y: center.y)
            )
        }
    }

    /// The quality-passed sample for one seat, matched by id; nil keeps the
    /// plain seat name so no temperature is invented.
    private func seatSample(for seat: SeatScene) -> SeatSample? {
        seatSamples?.first(where: { $0.id == seat.id })
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

    private func flowPoints(_ flow: FlowOverlay, projection: IsometricProjection) -> [CGPoint] {
        var points: [CGPoint] = flow.glyphs.map { projection.screenPoint($0.position) }
        for line in flow.lines {
            points.append(contentsOf: line.points.map { projection.screenPoint($0.position) })
        }
        return points
    }

    private func drawFlow(
        _ flow: FlowOverlay,
        projection: IsometricProjection,
        fit: (scale: CGFloat, offset: CGSize),
        phase: Double,
        in context: inout GraphicsContext
    ) {
        let maxMag = flow.stats.maxMag ?? flow.glyphs.map(\.mag).max() ?? 0.01
        // 「送风」/「回风」 name where the mesh actually injects and
        // extracts air: the full-span band at the terminal height.
        if let supply = scene.supply {
            drawTerminalLabel(supply, text: copy.supplyLabel, color: .blue, projection: projection, fit: fit, in: &context)
        }
        if let returnAir = scene.returnAir {
            drawTerminalLabel(returnAir, text: copy.returnLabel, color: .orange, projection: projection, fit: fit, in: &context)
        }
        for line in flow.lines {
            guard line.points.count >= 2 else { continue }
            var path = Path()
            path.move(to: Self.apply(projection.screenPoint(line.points[0].position), transform: fit))
            for point in line.points.dropFirst() {
                path.addLine(to: Self.apply(projection.screenPoint(point.position), transform: fit))
            }
            context.stroke(path, with: .color(.cyan.opacity(0.85)), lineWidth: 1.6)
            let points = line.points.map(\.position)
            for bead in 0..<RoomDisplayLayout.flowParticleBeadCount {
                guard let sample = RoomDisplayLayout.polylineSample(
                    points: points,
                    phase: RoomDisplayLayout.flowBeadPhase(
                        clock: phase,
                        index: bead,
                        count: RoomDisplayLayout.flowParticleBeadCount
                    )
                ) else { continue }
                let center = Self.apply(projection.screenPoint(sample), transform: fit)
                let rect = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: rect), with: .color(.cyan))
            }
        }
        for glyph in flow.glyphs {
            let start = Self.apply(projection.screenPoint(glyph.position), transform: fit)
            let displayMetres = Double(RoomDisplayLayout.glyphDisplayLength(mag: glyph.mag, maxMag: maxMag))
            let tip = Position3D(
                x: glyph.x + glyph.ux / max(glyph.mag, 1e-6) * displayMetres,
                y: glyph.y + glyph.uy / max(glyph.mag, 1e-6) * displayMetres,
                z: glyph.z + glyph.uz / max(glyph.mag, 1e-6) * displayMetres
            )
            let end = Self.apply(projection.screenPoint(tip), transform: fit)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.cyan), lineWidth: 1.8)
        }
    }

    private func drawTerminalLabel(
        _ patch: WallPatchScene,
        text: String,
        color: Color,
        projection: IsometricProjection,
        fit: (scale: CGFloat, offset: CGSize),
        in context: inout GraphicsContext
    ) {
        // Same device-side anchor as the 3D glyphs: beside and above the box.
        let anchor = RoomDisplayLayout.terminalLabelAnchor(patch, scene: scene)
        let point = Self.apply(projection.screenPoint(anchor), transform: fit)
        let label = Text(text).font(.title3.weight(.bold)).foregroundStyle(color)
        // Offset dark copy first: a cheap shadow so the label reads over the heatmap.
        context.draw(label.foregroundStyle(.black.opacity(0.75)), at: CGPoint(x: point.x + 1, y: point.y + 1))
        context.draw(label, at: point)
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
