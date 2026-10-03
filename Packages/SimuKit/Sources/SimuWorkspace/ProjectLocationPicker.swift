import Foundation
import SimuCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Platform file panels. Core I/O never sees these URLs as model fields.
@MainActor
enum ProjectLocationPicker {
    static func requestSaveURL(suggestedName: String = "Project.simunow") -> URL? {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.prompt = "保存"
        panel.message = "保存为 .simunow 目录包，内含 project.json"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if url.pathExtension == ProjectPackage.packageExtension {
            return url
        }
        return url.appendingPathExtension(ProjectPackage.packageExtension)
        #else
        return nil
        #endif
    }

    static func requestOpenURL() -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "打开"
        panel.message = "打开 .simunow 包或其中的 project.json"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
        #else
        return nil
        #endif
    }

    static func requestEvidencePDFURL() -> URL? {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "对比说明.pdf"
        panel.prompt = "导出"
        panel.message = "由 DeepSeek 根据已加入对比的方案写说明。数字来自计算结果，不会按当前房间重算。"
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
