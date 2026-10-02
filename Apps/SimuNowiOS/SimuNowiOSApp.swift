import SwiftUI
import SimuWorkspace

@main
struct SimuNowiOSApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: SimuNowDocument.unfinished()) { configuration in
            WorkspaceDocumentView(document: configuration.$document)
        }
    }
}
