import SwiftUI
import SimuWorkspace

@main
struct SimuNowiOSApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: WorkspaceStore.makeAppStore())
        }
    }
}
