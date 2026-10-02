import SwiftUI
import SimuWorkspace

@main
struct SimuNowMacApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: SimuNowDocument.unfinished()) { configuration in
            WorkspaceDocumentView(document: configuration.$document)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
