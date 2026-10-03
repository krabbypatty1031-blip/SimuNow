import Foundation
import SimuCore

/// Optional prose layered on top of an evidence pack. Tables do not read these strings for numbers.
public struct ReportNarration: Codable, Equatable, Sendable {
    public var headline: String
    public var cardProse: [String: String]
    public var caveats: [String]

    public init(headline: String, cardProse: [String: String], caveats: [String]) {
        self.headline = headline
        self.cardProse = cardProse
        self.caveats = caveats
    }
}

/// Turns an evidence pack into narration. A nil result means export the tables alone.
public protocol ReportNarrator: Sendable {
    func narrate(_ evidence: ReportEvidence) async -> ReportNarration?
}

/// Drops any paragraph whose numbers are not already in the evidence pack.
/// Run-ID prefixes are not treated as invented measurements.
public enum NarrationGuard: Sendable {
    public static let rejection = "叙述未采用（含证据外数字）"

    public static func filter(_ narration: ReportNarration, evidence: ReportEvidence) -> ReportNarration {
        ReportNarration(
            headline: sanitize(narration.headline, evidence: evidence),
            cardProse: narration.cardProse.mapValues { sanitize($0, evidence: evidence) },
            caveats: narration.caveats.map { sanitize($0, evidence: evidence) }
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

    /// JSON numbers only. Digits inside run-ID strings are not measurements.
    private static func numericValues(in evidence: ReportEvidence) -> Set<Decimal> {
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
        return allowed
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
        var identities = evidence.candidates.map(\.runID) + evidence.candidates.compactMap(\.l1RunID)
        identities.append(contentsOf: evidence.cards.flatMap(\.citedRunIDs))
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
