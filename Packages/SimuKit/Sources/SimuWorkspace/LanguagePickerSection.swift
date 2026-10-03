import SwiftUI
import SimuCore

/// Language control for the bottom of the sidebar. Options keep their native names.
struct LanguagePickerSection: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        Section {
            Picker(selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            } label: {
                Label(store.copy.languageMenuTitle, systemImage: "globe")
            }
            #if os(macOS)
            .pickerStyle(.menu)
            #endif
        }
        .accessibilityLabel(store.copy.languageAccessibilityLabel)
    }
}
