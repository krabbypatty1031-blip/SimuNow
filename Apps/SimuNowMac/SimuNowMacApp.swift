import SwiftUI
import SimuWorkspace

@main
struct SimuNowMacApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: WorkspaceStore.makeAppStore())
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
