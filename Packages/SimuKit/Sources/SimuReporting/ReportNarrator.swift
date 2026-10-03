import Foundation
import SimuCore

/// One heading plus a paragraph. Headings are labels; bodies are guarded for numbers.
public struct ReportSection: Codable, Equatable, Sendable {
    public var heading: String
    public var body: String

    public init(heading: String, body: String) {
        self.heading = heading
        self.body = body
    }
}

/// User-facing report written by a language model from a frozen evidence pack.
/// Tables and the identity appendix do not read these strings for numbers.
public struct GeneratedReport: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String
    public var sections: [ReportSection]
    public var caveats: [String]

    public init(
        title: String,
        summary: String,
        sections: [ReportSection] = [],
        caveats: [String] = []
    ) {
        self.title = title
        self.summary = summary
        self.sections = sections
        self.caveats = caveats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        sections = try container.decodeIfPresent([ReportSection].self, forKey: .sections) ?? []
        caveats = try container.decodeIfPresent([String].self, forKey: .caveats) ?? []
    }
}

/// Turns an evidence pack into a readable report. A nil result means do not write a PDF.
public protocol ReportGenerator: Sendable {
    func generate(_ evidence: ReportEvidence) async -> GeneratedReport?
}

/// Drops any paragraph whose numbers are not already in the evidence pack.
/// Run-ID prefixes are not treated as invented measurements.
public enum NarrationGuard: Sendable {
    public static let rejection = "叙述未采用（含证据外数字）"

    public static func filter(_ report: GeneratedReport, evidence: ReportEvidence) -> GeneratedReport {
        GeneratedReport(
            title: sanitize(report.title, evidence: evidence),
            summary: sanitize(report.summary, evidence: evidence),
            sections: report.sections.map { section in
                ReportSection(
                    heading: sanitize(section.heading, evidence: evidence),
                    body: sanitize(section.body, evidence: evidence)
                )
            },
            caveats: report.caveats.map { sanitize($0, evidence: evidence) }
        )
    }

    /// Keep the paragraph only when every extracted number is listed, or sits inside a run-ID prefix.
    static func sanitize(_ paragraph: String, evidence: ReportEvidence) -> String {
        let allowed = numericValues(in: evidence)
        let masked = maskRunIDPrefixes(paragraph, evidence: evidence)
        guard let expression = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else {
            return rejection
        }
        let range = NSRange(masked.startIndex..<masked.endIndex, in: masked)
        let tokens = expression.matches(in: masked, range: range).compactMap { match -> String? in
            guard let slice = Range(match.range, in: masked) else { return nil }
            return String(masked[slice])
        }
        for token in tokens {
            guard let value = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")),
                  allowed.contains(value) else {
                return rejection
            }
        }
        return paragraph
    }

    /// JSON numbers, plus the two-decimal display form the rest of the UI uses.
    /// Internal so `ChatGuard` (same module) reuses the exact same notion of
    /// "a number the evidence already carries".
    static func numericValues(in evidence: ReportEvidence) -> Set<Decimal> {
        guard let data = try? JSONEncoder().encode(evidence),
            let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let base = Set(decimals(in: json))
        var allowed = base
        // A listed ratio may be written as a percent. 0.75 allows 75; an unlisted 37% does not.
        for value in base where value >= 0 && value <= 1 {
            allowed.insert(value * 100)
        }
        for value in base {
            allowed.insert(value * 1000)
            if value != 0 {
                allowed.insert(value / 1000)
            }
        }
        var displayed: Set<Decimal> = []
        for value in allowed {
            let rounded = UserFacingCopy.displayNumber((value as NSDecimalNumber).doubleValue)
            if let decimal = Decimal(string: rounded, locale: Locale(identifier: "en_US_POSIX")) {
                displayed.insert(decimal)
            }
        }
        // Pair-diff sentences are code-generated from the pinned drafts; the
        // clock strings inside (08:00-18:00) carry numbers that no JSON field
        // holds, so they count as listed evidence, not invented figures.
        if let pairDiff = evidence.pairDiff {
            for change in pairDiff.inputChanges {
                for token in numberTokens(in: change.sentence) {
                    allowed.insert(token)
                }
            }
        }
        return allowed.union(displayed)
    }

    /// Digits inside a sentence, as Decimals. Only used on code-generated text.
    static func numberTokens(in sentence: String) -> [Decimal] {
        guard let expression = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else {
            return []
        }
        let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return expression.matches(in: sentence, range: range).compactMap { match -> Decimal? in
            guard let slice = Range(match.range, in: sentence) else { return nil }
            return Decimal(string: String(sentence[slice]), locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    private static func decimals(in json: Any) -> [Decimal] {
        switch json {
        case let object as [String: Any]:
            return object.values.flatMap(decimals(in:))
        case let list as [Any]:
            return list.flatMap(decimals(in:))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return []
            }
            guard let value = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) else {
                return []
            }
            return [value]
        default:
            return []
        }
    }

    /// Blank out dashed and compact run-ID prefixes (4+ characters) before the number scan.
    private static func maskRunIDPrefixes(_ paragraph: String, evidence: ReportEvidence) -> String {
        var masked = paragraph
        // Candidate L2 run IDs plus their cited L1 IDs. The old card
        // citation list is gone with the classifier (ADR-021).
        let identities = evidence.candidates.map(\.runID) + evidence.candidates.compactMap(\.l1RunID)
        var tokens: [String] = []
        for id in Set(identities) {
            let dashed = id.uuidString
            let compact = dashed.replacingOccurrences(of: "-", with: "")
            tokens.append(dashed)
            tokens.append(dashed.lowercased())
            tokens.append(compact)
            tokens.append(compact.lowercased())
        }
        for token in tokens {
            var length = token.count
            while length >= 4 {
                let prefix = String(token.prefix(length))
                if let range = masked.range(of: prefix) {
                    masked.replaceSubrange(range, with: String(repeating: " ", count: prefix.count))
                } else {
                    length -= 1
                }
            }
        }
        return masked
    }
}
