import SwiftUI
import SimuWorkspace
import SimuSimulation

@main
struct SimuNowiOSApp: App {
    // Shared across DocumentGroup windows; each window keeps its own coordinator.
    @State private var analysisClient = LocalAnalysisClient.production()
    var body: some Scene {
        #if SIMUNOW_AIRFLOW_PROBE && DEBUG
        WindowGroup("N3 Swift Airflow Preview") { NativeAirflowPreviewProbeHostView() }
        #elseif SIMUNOW_ROOM_PROBE && DEBUG
        WindowGroup("N2 Room Scene Probe") { NativeRoomSceneProbeHostView() }
        #elseif SIMUNOW_NATIVE_PROBE
        WindowGroup("N1 RealityKit Probe") { NativeAnalysisProbeHostView() }
        #else
        DocumentGroup(newDocument: SimuNowDocument.unfinished()) { configuration in
            WorkspaceDocumentView(document: configuration.$document, localAnalysisClient: analysisClient)
        }
        #endif
    }
}
