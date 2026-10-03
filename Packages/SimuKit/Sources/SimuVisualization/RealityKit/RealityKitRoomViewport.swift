import RealityKit
import SimuCore
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// Non-AR production viewport. Availability is contained here; older systems use RoomPlanView.
@MainActor
public struct RealityKitRoomViewport: View {
    private let descriptor: SceneDescriptor
    private let selection: SceneObjectKey?
    private let overlay: RoomSceneOverlay
    private let inputEnabled: Bool
    private let onSelect: @MainActor (SceneObjectKey?) -> Void
    public init(
        descriptor: SceneDescriptor, selection: SceneObjectKey?, overlay: RoomSceneOverlay = .empty,
        inputEnabled: Bool = true,
        onSelect: @escaping @MainActor (SceneObjectKey?) -> Void
    ) {
        self.descriptor = descriptor
        self.selection = selection
        self.overlay = overlay
        self.inputEnabled = inputEnabled
        self.onSelect = onSelect
    }
    public var body: some View {
        if #available(macOS 15, iOS 18, *) {
            NativeRoomViewport(
                descriptor: descriptor, selection: selection, overlay: overlay, inputEnabled: inputEnabled,
                onSelect: onSelect)
        } else {
            Text(RendererCapabilities.current.explanation).foregroundStyle(.secondary)
        }
    }
}
@available(macOS 15, iOS 18, *)
@MainActor
private struct NativeRoomViewport: View {
    let descriptor: SceneDescriptor
    let selection: SceneObjectKey?
    let overlay: RoomSceneOverlay
    let inputEnabled: Bool
    let onSelect: @MainActor (SceneObjectKey?) -> Void
    @State private var controller: RoomSceneController
    @State private var preparedOverlay = RoomSceneOverlay.empty
    @State private var overlayPreparationFailure: String?
    @State private var dragStart: RoomCameraState?
    @State private var magnifyStart: RoomCameraState?
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.scenePhase) private var scenePhase
    init(
        descriptor: SceneDescriptor, selection: SceneObjectKey?, overlay: RoomSceneOverlay,
        inputEnabled: Bool, onSelect: @escaping @MainActor (SceneObjectKey?) -> Void
    ) {
        self.descriptor = descriptor
        self.selection = selection
        self.overlay = overlay
        self.inputEnabled = inputEnabled
        self.onSelect = onSelect
        _controller = State(initialValue: RoomSceneController(bounds: descriptor.bounds))
    }
    var body: some View {
        // Reading these values binds camera/visibility changes to RealityView's update closure.
        let camera = controller.camera
        let visibility = controller.visibility
        let active = controller.isActive
        let renderOverlay =
            preparedOverlay.paths.map(\.id) == overlay.paths.map(\.id)
                && zip(preparedOverlay.paths, overlay.paths).allSatisfy({
                    $0.points == $1.points && $0.blocked == $1.blocked
                }) ? preparedOverlay : .empty
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { viewport in
                let width = Double(viewport.size.width)
                let height = Double(viewport.size.height)
                ZStack {
                    RealityView { content in
                        content.camera = .virtual
                        content.add(controller.worldRoot)
                        controller.reconcile(
                            descriptor: descriptor, overlay: renderOverlay, selection: selection,
                            dark: colorScheme == .dark)
                    } update: { _ in
                        _ = camera
                        _ = visibility
                        _ = active
                        controller.reconcile(
                            descriptor: descriptor, overlay: renderOverlay, selection: selection,
                            dark: colorScheme == .dark)
                    }
                    .realityViewCameraControls(.none)
                    // Public SwiftUI input layer. Does not rely on AR entity targeting.
                    Color.clear.contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { event in
                                guard inputEnabled, magnifyStart == nil,
                                    hypot(event.translation.width, event.translation.height) >= 4
                                else { return }
                                if dragStart == nil { dragStart = controller.camera }
                                guard var next = dragStart else { return }
                                next.orbit(
                                    horizontalDegrees: -Double(event.translation.width) * 0.3,
                                    verticalDegrees: Double(event.translation.height) * 0.3)
                                controller.setCamera(next)
                            }.onEnded { event in
                                let isClick =
                                    hypot(event.translation.width, event.translation.height) < 4
                                    && dragStart == nil && magnifyStart == nil
                                if inputEnabled && isClick {
                                    onSelect(
                                        controller.pick(
                                            x: Double(event.location.x), y: Double(event.location.y),
                                            width: width, height: height))
                                }
                                dragStart = nil
                            }
                        )
                        .simultaneousGesture(
                            MagnifyGesture().onChanged { event in
                                if magnifyStart == nil {
                                    magnifyStart = controller.camera
                                    dragStart = nil
                                }
                                guard var next = magnifyStart, let bounds = descriptor.bounds else { return }
                                next.zoom(factor: 1 / Double(event.magnification), roomBounds: bounds)
                                controller.setCamera(next)
                            }.onEnded { _ in magnifyStart = nil }
                        )
                        .accessibilityHidden(true)
                }
                #if os(macOS)
                    .background(
                        RoomScrollCapture(isActive: active && scenePhase == .active) { delta in
                            controller.zoom(factor: exp(-min(100, max(-100, delta)) * 0.015))
                        })
                #endif
                .onAppear {
                    controller.resume()
                    controller.updateViewport(width: width, height: height)
                }
                .onChange(of: viewport.size) { _, size in
                    controller.updateViewport(width: Double(size.width), height: Double(size.height))
                }
            }
            .frame(minHeight: 260, idealHeight: 340)
            .background(
                colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            LazyVGrid(columns: [.init(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                cameraButton("左转", "arrow.counterclockwise") { controller.orbit(horizontalDegrees: -15) }
                cameraButton("右转", "arrow.clockwise") { controller.orbit(horizontalDegrees: 15) }
                cameraButton("放大", "plus.magnifyingglass") { controller.zoom(factor: 0.8) }
                cameraButton("缩小", "minus.magnifyingglass") { controller.zoom(factor: 1.25) }
                cameraButton("俯视", "square.3.layers.3d.top.filled") { controller.top() }
                cameraButton("等轴重置", "arrow.uturn.backward") { controller.reset() }
                cameraButton("聚焦选中", "scope") { controller.focus(selection) }.disabled(
                    descriptor.object(selection)?.focusBounds == nil)
            }.buttonStyle(.bordered).controlSize(.small)
            ViewThatFits(in: .horizontal) {
                HStack { visibilityControls }
                VStack(alignment: .leading) { visibilityControls }
            }
            Text("米制 Z-up · 拖动旋转，滚轮或捏合缩放，点选查看；对象清单提供无手势操作。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !overlay.explanation.isEmpty {
                Text(overlay.explanation).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let issue = overlayPreparationFailure ?? controller.overlayRenderingIssue
                ?? overlay.validationMessage
            {
                Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .task(id: overlay) {
            let source = overlay
            let task = Task.detached(priority: .userInitiated) { try source.preparedFor3D() }
            do {
                let value = try await withTaskCancellationHandler(
                    operation: { try await task.value }, onCancel: { task.cancel() })
                if !Task.isCancelled {
                    preparedOverlay = value
                    overlayPreparationFailure = nil
                }
            } catch is CancellationError {} catch {
                if !Task.isCancelled {
                    preparedOverlay = .empty
                    overlayPreparationFailure = String(describing: error)
                }
            }
        }
        .onDisappear {
            dragStart = nil
            magnifyStart = nil
            controller.suspend()
        }
        .onChange(of: scenePhase) { _, phase in controller.setForeground(phase == .active) }
        #if os(iOS)
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            ) { _ in controller.clearReusableCaches() }
        #endif
    }
    private func cameraButton(_ title: String, _ symbol: String, action: @escaping @MainActor () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity).fixedSize(
                horizontal: false, vertical: true)
        }
        .accessibilityHint("仅改变显示相机，不修改项目输入。")
    }
    @ViewBuilder private var visibilityControls: some View {
        Toggle(
            "显示天花板",
            isOn: Binding(get: { controller.visibility.showCeiling }, set: { controller.showCeiling($0) }))
        Toggle(
            "隐藏面向视点的侧墙",
            isOn: Binding(
                get: { controller.visibility.hideFacingWalls }, set: { controller.hideFacingWalls($0) }))
    }
}
