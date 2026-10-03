import SwiftUI
import SimuWorkspace
import SimuSimulation

@main
struct SimuNowMacApp: App {
    // Shared across DocumentGroup windows; each window keeps its own coordinator.
    @State private var analysisClient = LocalAnalysisClient.production()
    var body: some Scene {
        #if SIMUNOW_THERMAL_PROBE && DEBUG
        WindowGroup("N4 Swift Thermal Estimate") { NativeThermalEstimateProbeHostView(localAnalysisClient: analysisClient) }
        #elseif SIMUNOW_AIRFLOW_PROBE && DEBUG
        WindowGroup("N3 Swift Airflow Preview") { NativeAirflowPreviewProbeHostView() }
        #elseif SIMUNOW_ROOM_PROBE && DEBUG
        WindowGroup("N2 Room Scene Probe") { NativeRoomSceneProbeHostView() }
        #elseif SIMUNOW_NATIVE_PROBE
        WindowGroup("N1 RealityKit Probe") { NativeAnalysisProbeHostView() }
        #else
        DocumentGroup(newDocument: SimuNowDocument.unfinished()) { configuration in
            WorkspaceDocumentView(document: configuration.$document, localAnalysisClient: analysisClient)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
        #if DEBUG
        .commands {
            CommandMenu("Developer") {
                NativeProbeCommand()
                NativeRoomProbeCommand()
            }
        }
        #endif
        #endif
        #if DEBUG && !SIMUNOW_NATIVE_PROBE && !SIMUNOW_ROOM_PROBE && !SIMUNOW_AIRFLOW_PROBE && !SIMUNOW_THERMAL_PROBE
        WindowGroup("N1 RealityKit Probe", id: "native-probe") { NativeAnalysisProbeHostView() }
        WindowGroup("N2 Room Scene Probe", id: "room-scene-probe") { NativeRoomSceneProbeHostView() }
        #endif
    }
}
#if DEBUG
private struct NativeRoomProbeCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Open N2 Room Scene Probe") { openWindow(id: "room-scene-probe") } }
}
private struct NativeProbeCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Open N1 RealityKit Probe") { openWindow(id: "native-probe") } }
}
#endif
