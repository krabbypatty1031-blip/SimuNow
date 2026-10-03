import SwiftUI
import SimuWorkspace

@main
struct SimuNowiOSApp: App {
    var body: some Scene {
        #if SIMUNOW_ROOM_PROBE && DEBUG
        WindowGroup("N2 Room Scene Probe") { NativeRoomSceneProbeHostView() }
        #elseif SIMUNOW_NATIVE_PROBE
        WindowGroup("N1 RealityKit Probe") { NativeAnalysisProbeHostView() }
        #else
        DocumentGroup(newDocument: SimuNowDocument.unfinished()) { configuration in
            WorkspaceDocumentView(document: configuration.$document)
        }
        #endif
    }
}
