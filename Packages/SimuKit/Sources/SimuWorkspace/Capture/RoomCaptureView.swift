import SwiftUI
import SimuCore
import SimuVisualization
#if os(iOS) && canImport(RoomPlan)
import RoomPlan
import AVFoundation
import simd
#endif

@MainActor public struct RoomCaptureWorkflowView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    let onApply: @MainActor (RoomCaptureSnapshot, Data) async throws -> Void
    let onManual: @MainActor () -> Void
    @State private var applying = false
    @State private var work: Task<Void, Never>?
    @State private var notice: String?
    public init(onManual: @escaping @MainActor () -> Void, onApply: @escaping @MainActor (RoomCaptureSnapshot, Data) async throws -> Void) {
        self.onManual = onManual; self.onApply = onApply
    }
    #if os(iOS) && canImport(RoomPlan)
    @State private var authorized = false
    @State private var stopping = false
    @State private var result: RoomCaptureSnapshot?
    @State private var original: Data?
    @State private var scanID = UUID()
    #endif
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                #if os(iOS) && canImport(RoomPlan)
                if RoomCaptureSession.isSupported {
                    if let result, let original {
                        Text("房间包围盒：\(result.roomDimensionsMeters.x.formatted()) × \(result.roomDimensionsMeters.y.formatted()) × \(result.roomDimensionsMeters.z.formatted()) m；\(result.furniture.count) 个家具盒体。")
                        Text("转换为当前支持的矩形模板需你确认。门窗、设备、关注点及复杂几何请在编辑器中补充或修正；扫描不会提供热工、功率或性能参数。原扫描 JSON 仅保存在本地项目附件。")
                        Button("确认包围盒转换并创建项目") {
                            applying = true; notice = nil
                            work = Task {
                                defer { applying = false; work = nil }
                                do { try await onApply(result, original); try Task.checkCancellation(); dismiss() }
                                catch { if !Task.isCancelled { notice = error.localizedDescription } }
                            }
                        }.disabled(applying)
                        if applying { ProgressView("后台检查扫描与项目包…") }
                    } else if authorized {
                        NativeRoomCapture(stopRequested: stopping) { snapshot, bytes in result = snapshot; original = bytes } onError: { notice = $0 }
                            .id(scanID)
                        Button(stopping ? "正在处理扫描…" : "结束扫描并检查") { stopping = true }.disabled(stopping)
                    } else {
                        Text("扫描需要摄像头权限，仅在你主动开始时请求。没有权限也可用手动向导。")
                        Button("允许摄像头并开始扫描") {
                            Task { authorized = await AVCaptureDevice.requestAccess(for: .video); if !authorized { notice = "摄像头未获授权。请返回使用手动建模，或在系统设置允许摄像头。" } }
                        }
                    }
                } else { Text("此设备不支持 RoomPlan。请使用手动房间向导；LiDAR 不是完成本地预览的必需条件。") }
                #else
                Text("房间扫描在支持 RoomPlan 的 iPhone/iPad 上提供。此设备可以手动建模或打开手机导出的项目包。")
                #endif
                if let notice { Text(notice).foregroundStyle(.orange) }
                Button("打开手动房间向导", action: onManual).disabled(applying)
                #if os(iOS) && canImport(RoomPlan)
                if notice != nil, authorized {
                    Button("重新扫描") { scanID = UUID(); stopping = false; result = nil; original = nil; notice = nil }
                }
                #endif
            }.padding().navigationTitle("扫描房间")
            .onDisappear { work?.cancel() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消扫描") { dismiss() } } }
        }
    }
}

#if os(iOS) && canImport(RoomPlan)
@MainActor private struct NativeRoomCapture: UIViewRepresentable {
    let stopRequested: Bool
    let onResult: (RoomCaptureSnapshot, Data) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult, onError: onError) }
    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero); view.delegate = context.coordinator
        view.captureSession.run(configuration: .init()); return view
    }
    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if stopRequested, !context.coordinator.stopped { context.coordinator.stopped = true; view.captureSession.stop() }
    }
    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) { view.captureSession.stop() }
    @objc(SimuNowRoomCaptureCoordinator)
    @MainActor final class Coordinator: NSObject, @preconcurrency RoomCaptureViewDelegate {
        var stopped = false
        let onResult: (RoomCaptureSnapshot, Data) -> Void
        let onError: (String) -> Void
        init(onResult: @escaping (RoomCaptureSnapshot, Data) -> Void, onError: @escaping (String) -> Void) { self.onResult = onResult; self.onError = onError }
        // RoomPlan's delegate inherits NSCoding in the current SDK. This live
        // coordinator holds callbacks and must be recreated by SwiftUI.
        required init?(coder: NSCoder) { return nil }
        func encode(with coder: NSCoder) {}
        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
            if let error { onError(error.localizedDescription); return false }; return true
        }
        func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
            if let error { onError(error.localizedDescription); return }
            do {
                let bytes = try JSONEncoder().encode(processedResult)
                guard bytes.count <= 8*1024*1024, !processedResult.walls.isEmpty, processedResult.objects.count <= 128 else { throw ProjectDataError.contract("扫描为空或超过支持预算。") }
                func box(dimensions: SIMD3<Float>, transform: simd_float4x4) -> CapturedGeometryBox {
                    let corners = [-0.5,0.5].flatMap { x in [-0.5,0.5].flatMap { y in [-0.5,0.5].map { z in
                        let p = transform * SIMD4<Float>(Float(x)*dimensions.x, Float(y)*dimensions.y, Float(z)*dimensions.z, 1)
                        return CoordinateTransform.toDomain(Position3D(x: Double(p.x), y: Double(p.y), z: Double(p.z)))
                    } } }
                    let low = Position3D(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!, z: corners.map(\.z).min()!)
                    let high = Position3D(x: corners.map(\.x).max()!, y: corners.map(\.y).max()!, z: corners.map(\.z).max()!)
                    return .init(origin: low, dimensions: .init(x: high.x-low.x, y: high.y-low.y, z: high.z-low.z))
                }
                let walls = processedResult.walls.map { box(dimensions: $0.dimensions, transform: $0.transform) }
                let objects = processedResult.objects.map { box(dimensions: $0.dimensions, transform: $0.transform) }
                let all = walls + objects
                let origin = Position3D(x: all.map(\.origin.x).min()!, y: all.map(\.origin.y).min()!, z: all.map(\.origin.z).min()!)
                let high = Position3D(x: all.map { $0.origin.x+$0.dimensions.x }.max()!, y: all.map { $0.origin.y+$0.dimensions.y }.max()!, z: all.map { $0.origin.z+$0.dimensions.z }.max()!)
                let local = objects.map { CapturedGeometryBox(origin: .init(x: $0.origin.x-origin.x, y: $0.origin.y-origin.y, z: $0.origin.z-origin.z), dimensions: $0.dimensions) }
                onResult(.init(appleOriginInDomain: origin, roomDimensionsMeters: .init(x: high.x-origin.x, y: high.y-origin.y, z: high.z-origin.z),
                    furniture: local, source: .init(kind: .scan, reference: "Apple RoomPlan", note: "用户确认的世界轴包围盒简化；原扫描保留本地，需人工修正几何。")), bytes)
            } catch { onError(error.localizedDescription) }
        }
    }
}
#endif
