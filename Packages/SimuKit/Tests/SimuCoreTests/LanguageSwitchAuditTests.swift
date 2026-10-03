import Foundation
import Testing
import SimuCore
import SimuWorkspace

/// Full bilingual audit (2026-10-04): every `t(en, zh)` pair in the copy
/// tables must have both sides, they must differ, and the UI surfaces that
/// previously stayed Chinese after a language toggle must follow `store.copy`.

@Test func everyCopyTablePairHasBothLanguagesAndTheyDiffer() throws {
    let sources = copyTableURLs()
    #expect(!sources.isEmpty)
    var pairs: [(en: String, zh: String)] = []
    for url in sources {
        pairs.append(contentsOf: extractCopyPairs(from: try String(contentsOf: url, encoding: .utf8)))
    }
    // Floor: a silent drop of a whole file would shrink this; 2026-10-04 count
    // is 280+ including interpolated titles.
    #expect(pairs.count >= 280, "copy table shrank to \(pairs.count) pairs")
    var identical: [String] = []
    var missingCJK: [String] = []
    var empty: [String] = []
    for pair in pairs {
        if pair.en.isEmpty || pair.zh.isEmpty {
            empty.append("en=\(pair.en) zh=\(pair.zh)")
        }
        if pair.en == pair.zh {
            identical.append(pair.en)
        }
        if !containsHanLetter(pair.zh) {
            let formatOnly = pair.zh == "、" || pair.zh.contains("\\(") || pair.zh.contains("（")
            if !formatOnly {
                missingCJK.append(pair.zh)
            }
        }
    }
    #expect(empty.isEmpty, "empty side: \(empty)")
    #expect(identical.isEmpty, "en==zh (not a translation): \(identical)")
    #expect(missingCJK.isEmpty, "zh missing Han: \(missingCJK)")
}

@Test func inspectorAndPlanSurfacesFlipWithLanguage() {
    let en = UserFacingCopy.english
    let zh = UserFacingCopy.chinese
    let pairs: [(String, String, String)] = [
        ("wall", en.wall, zh.wall),
        ("wallTitle.xMin", en.wallTitle(.xMin), zh.wallTitle(.xMin)),
        ("source", en.source, zh.source),
        ("sourceTitle.preset", en.sourceTitle(.preset), zh.sourceTitle(.preset)),
        ("startAlongWall", en.startAlongWall, zh.startAlongWall),
        ("endAlongWall", en.endAlongWall, zh.endAlongWall),
        ("heightAboveFloor", en.heightAboveFloor, zh.heightAboveFloor),
        ("topHeight", en.topHeight, zh.topHeight),
        ("applyNamed.supply", en.applyNamed("Supply outlet"), zh.applyNamed("出风口")),
        ("dragFurnitureInPlanRow", en.dragFurnitureInPlanRow, zh.dragFurnitureInPlanRow),
        ("planNoRoomYet", en.planNoRoomYet, zh.planNoRoomYet),
        ("planLegalDropNote", en.planLegalDropNote, zh.planLegalDropNote),
        ("fillRoomBeforeFurniture", en.fillRoomBeforeFurniture, zh.fillRoomBeforeFurniture),
        ("terminal.supply", en.terminalTitle(isSupply: true), zh.terminalTitle(isSupply: true)),
        ("desk", en.furnitureKindTitle(.desk), zh.furnitureKindTitle(.desk)),
        ("destination.workspace", en.destinationTitle("workspace"), zh.destinationTitle("workspace")),
        ("destination.runs", en.destinationTitle("runs"), zh.destinationTitle("runs")),
        ("open", en.open, zh.open),
        ("save", en.save, zh.save),
        ("consult", en.consult, zh.consult),
        ("estimateDayEnergy", en.estimateDayEnergy, zh.estimateDayEnergy),
    ]
    for (name, english, chinese) in pairs {
        #expect(!english.isEmpty, Comment(rawValue: name))
        #expect(!chinese.isEmpty, Comment(rawValue: name))
        #expect(english != chinese, Comment(rawValue: name))
        #expect(containsHanLetter(chinese), Comment(rawValue: name))
        #expect(!containsHanLetter(english), Comment(rawValue: "\(name) English leaked Han: \(english)"))
    }
}

@Test func furnitureRejectionAndKindTitlesFlipWithLanguage() {
    let en = UserFacingCopy.english
    let zh = UserFacingCopy.chinese
    for rejection in FurniturePlacement.Rejection.allCases {
        let english = en.furniturePlacementRejection(rejection)
        let chinese = zh.furniturePlacementRejection(rejection)
        #expect(english != chinese)
        #expect(chinese == rejection.rawValue)
        #expect(english.range(of: #"\p{Han}"#, options: .regularExpression) == nil)
    }
    for kind in FurnitureKind.allCases {
        #expect(en.furnitureKindTitle(kind) != zh.furnitureKindTitle(kind))
        #expect(zh.furnitureKindTitle(kind) == kind.title)
    }
}

@MainActor
@Test func switchingLanguageRespeaksFurnitureRefusal() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.upsertObstacle(
        ObstacleBox(id: "F1", origin: Position3D(x: 1, y: 1, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75), kind: .desk)
    )
    let store = WorkspaceStore()
    store.project = draft
    store.language = .chinese
    // Drop a second desk on the first: overlap, draft unchanged.
    store.applyObstacle(id: "F2", origin: Position3D(x: 1.1, y: 1.1, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75), kind: .desk)
    #expect(store.furniturePlacementMessage == UserFacingCopy.chinese.furniturePlacementRejection(.overlapsFurniture))
    store.language = .english
    #expect(store.furniturePlacementMessage == UserFacingCopy.english.furniturePlacementRejection(.overlapsFurniture))
}

@Test func workspaceUIFilesHaveNoHardcodedChineseCopy() throws {
    // Comments may mention Chinese; only string literals are banned.
    let uiFiles = [
        "SimuWorkspace/RoomEditorForm.swift",
        "SimuWorkspace/WorkspaceView.swift",
        "SimuWorkspace/FurniturePlanView.swift",
        "SimuWorkspace/ChatPanel.swift",
        "SimuWorkspace/LanguagePickerSection.swift",
    ]
    let root = sourcesRoot()
    let literal = try Regex(#""([^"\\]|\\.)*""#)
    for relative in uiFiles {
        let text = try String(contentsOf: root.appending(path: relative), encoding: .utf8)
        let withoutComments = stripComments(text)
        for match in withoutComments.matches(of: literal) {
            let token = String(withoutComments[match.range])
            if containsHanLetter(token) {
                Issue.record("hardcoded Chinese in \(relative): \(token)")
            }
        }
    }
}

// MARK: - Helpers

private func copyTableURLs() -> [URL] {
    let root = sourcesRoot().appending(path: "SimuCore")
    return [
        root.appending(path: "UserFacingCopy.swift"),
        root.appending(path: "UserFacingCopy+Chrome.swift"),
    ]
}

private func sourcesRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SimuCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SimuKit
        .appending(path: "Sources")
}

private func extractCopyPairs(from source: String) -> [(en: String, zh: String)] {
    // t("english", zh: "中文") and the multiline form with newlines/indent.
    let pattern = #"t\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*zh:\s*"((?:[^"\\]|\\.)*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = source as NSString
    return regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).compactMap { match in
        guard match.numberOfRanges == 3,
              let en = ns.substring(with: match.range(at: 1)).removingEscapeSequences as String?,
              let zh = ns.substring(with: match.range(at: 2)).removingEscapeSequences as String?
        else { return nil }
        return (en, zh)
    }
}

private extension String {
    var removingEscapeSequences: String {
        replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private func containsHanLetter(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }
}

private func stripComments(_ source: String) -> String {
    var result = ""
    var i = source.startIndex
    var inLine = false
    var inBlock = false
    var inString = false
    while i < source.endIndex {
        let next = source.index(after: i)
        if inLine {
            if source[i] == "\n" {
                inLine = false
                result.append("\n")
            }
            i = next
            continue
        }
        if inBlock {
            if source[i] == "*", next < source.endIndex, source[next] == "/" {
                inBlock = false
                i = source.index(after: next)
            } else {
                i = next
            }
            continue
        }
        if inString {
            result.append(source[i])
            if source[i] == "\\" && next < source.endIndex {
                result.append(source[next])
                i = source.index(after: next)
                continue
            }
            if source[i] == "\"" { inString = false }
            i = next
            continue
        }
        if source[i] == "\"" {
            inString = true
            result.append("\"")
            i = next
            continue
        }
        if source[i] == "/", next < source.endIndex, source[next] == "/" {
            inLine = true
            i = source.index(after: next)
            continue
        }
        if source[i] == "/", next < source.endIndex, source[next] == "*" {
            inBlock = true
            i = source.index(after: next)
            continue
        }
        result.append(source[i])
        i = next
    }
    return result
}
