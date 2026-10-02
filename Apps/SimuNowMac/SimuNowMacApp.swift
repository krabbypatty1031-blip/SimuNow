import SwiftUI
import SimuWorkspace

@main
struct SimuNowMacApp: App {
    var body: some Scene {
        #if SIMUNOW_NATIVE_PROBE
        WindowGroup("N1 RealityKit Probe") { NativeAnalysisProbeHostView() }
        #else
        DocumentGroup(newDocument: SimuNowDocument.unfinished()) { configuration in
            WorkspaceDocumentView(document: configuration.$document)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
        #if DEBUG
        .commands {
            CommandMenu("Developer") {
                NativeProbeCommand()
            }
        }
        #endif
        #endif
        #if DEBUG && !SIMUNOW_NATIVE_PROBE
        WindowGroup("N1 RealityKit Probe", id: "native-probe") { NativeAnalysisProbeHostView() }
        #endif
    }
}
#if DEBUG
private struct NativeProbeCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Open N1 RealityKit Probe") { openWindow(id: "native-probe") } }
}
#endif
