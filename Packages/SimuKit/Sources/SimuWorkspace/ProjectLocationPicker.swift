import Foundation
import SimuCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Platform file panels. Core I/O never sees these URLs as model fields.
@MainActor
enum ProjectLocationPicker {
    static func requestSaveURL(
        suggestedName: String = "Project.simunow",
        copy: UserFacingCopy = .english
    ) -> URL? {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.prompt = copy.savePanelPrompt
        panel.message = copy.savePanelMessage
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if url.pathExtension == ProjectPackage.packageExtension {
            return url
        }
        return url.appendingPathExtension(ProjectPackage.packageExtension)
        #else
        return nil
        #endif
    }

    static func requestOpenURL(copy: UserFacingCopy = .english) -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = copy.openPanelPrompt
        panel.message = copy.openPanelMessage
        guard panel.runModal() == .OK else { return nil }
        return panel.url
        #else
        return nil
        #endif
    }

    static func requestEvidencePDFURL(copy: UserFacingCopy = .english) -> URL? {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = copy.evidencePDFFilename
        panel.prompt = copy.export
        panel.message = copy.evidencePDFPanelMessage
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if url.pathExtension.lowercased() == "pdf" {
            return url
        }
        return url.appendingPathExtension("pdf")
        #else
        return nil
        #endif
    }

    static func requestDirectoryURL(message: String, prompt: String) -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        guard panel.runModal() == .OK else { return nil }
        return panel.url
        #else
        return nil
        #endif
    }
}
