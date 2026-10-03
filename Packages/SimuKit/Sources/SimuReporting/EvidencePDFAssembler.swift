import Foundation
import SimuCore
#if canImport(WebKit)
import WebKit
#endif

public enum EvidencePDFError: Error, Equatable {
    /// Kept for callers written before WebKit export. WebKit renders on both
    /// platforms now, so this is no longer thrown; the case stays source-compatible.
    case unsupportedPlatform
    /// Quality failed, no feasible seats, or mixed basis. The page may explain; it must not write a recommendation PDF.
    case notExportable
    /// DeepSeek is missing, refused, or returned nothing usable.
    case generatorUnavailable
    case writeFailed
}

/// Renders a DeepSeek-written report plus a local evidence appendix.
/// ADR-024: layout moved from hand-drawn CoreText to HTML/CSS laid out by
/// WebKit, so both platforms export the same styled PDF. Evidence numbers,
/// appendix lines, and NarrationGuard filtering are unchanged.
public enum EvidencePDFAssembler {
    public static func write(
        evidence: ReportEvidence,
        report: GeneratedReport,
        copy: UserFacingCopy = .english,
        to url: URL
    ) async throws {
        #if canImport(WebKit)
        // Same freeze as before: the PDF renders only guarded text.
        let guarded = NarrationGuard.filter(report, evidence: evidence, language: copy.language)
        let document = htmlDocument(evidence: evidence, report: guarded, copy: copy)
        let data = try await renderPDFData(html: document)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw EvidencePDFError.writeFailed
        }
        #else
        throw EvidencePDFError.unsupportedPlatform
        #endif
    }

    /// Local appendix. Every figure is formatted from an evidence field.
    static func appendix(evidence: ReportEvidence, copy: UserFacingCopy = .english) -> String {
        var lines: [String] = []
        lines.append(copy.pdfCalculationBasis)
        if let price = evidence.candidates.compactMap(\.pricePerKWh).first {
            let currency = evidence.candidates.compactMap(\.currency).first ?? ""
            lines.append(copy.pdfTariff(format(price), currency: currency))
        }
        let bandLow = evidence.candidates.first?.seatBandLowC ?? SeatFeasibility.airLowC
        let bandHigh = evidence.candidates.first?.seatBandHighC ?? SeatFeasibility.airHighC
        lines.append(copy.pdfSeatBand(low: format(bandLow), high: format(bandHigh)))
        lines.append(copy.pdfSchemes)
        for run in evidence.candidates {
            lines.append(run.name)
            if let count = run.windowCount, count > 0, let area = run.windowAreaM2 {
                lines.append(copy.pdfWindows(count: count, area: format(area)))
            } else if let count = run.windowCount, count > 0 {
                lines.append(copy.pdfWindows(count: count, area: nil))
            }
            if let mean = run.indoorMeanC {
                lines.append(copy.pdfIndoorMean(format(mean)))
            }
            if let minC = run.indoorMinC, let maxC = run.indoorMaxC {
                lines.append(copy.pdfIndoorRange(min: format(minC), max: format(maxC)))
            }
            if let minU = run.flowMinMps, let maxU = run.flowMaxMps {
                lines.append(copy.pdfAirflow(min: format(minU), max: format(maxU)))
            } else if let speed = run.seatSpeedMaxMps {
                lines.append(copy.pdfSeatMaxSpeed(format(speed)))
            }
            if let cooling = run.coolingW {
                lines.append(copy.pdfCooling(format(cooling)))
            }
            if let electric = run.electricPowerW {
                lines.append(copy.pdfElectric(format(electric)))
            }
            if run.seatPassRatioOmitted || run.seatPassRatio == nil {
                lines.append(copy.pdfSeatsUnevaluable)
            } else if let ratio = run.seatPassRatio {
                lines.append(copy.pdfSeatsRatio(format(ratio)))
            }
            if let energy = run.dayEnergyKWh {
                lines.append(copy.pdfDayEnergy(format(energy)))
            }
            if let annual = run.annualEnergyKWh {
                lines.append(copy.pdfYearEnergy(format(annual)))
            }
            if let cost = run.dayCost, let currency = run.currency {
                lines.append(copy.pdfDayCost(format(cost), currency: currency))
            }
            if let annual = run.annualCost, let currency = run.currency {
                lines.append(copy.pdfYearCost(format(annual), currency: currency))
            }
            if let z0 = run.supplyZ0M, let z1 = run.supplyZ1M {
                lines.append(copy.pdfSupplyHeight(z0: format(z0), z1: format(z1)))
            }
        }
        lines.append(copy.pdfEvidenceAndLimits)
        if evidence.comfortAssumptions.isEmpty {
            lines.append(copy.pdfNoComfortAssumptions)
        } else {
            for item in evidence.comfortAssumptions {
                let value = item.value.map(format) ?? copy.notYet
                let reference = item.reference.map { copy.displayStoredNote($0) } ?? ""
                lines.append("\(copy.comfortKeyTitle(item.name)) \(value) \(item.unit) \(reference)")
            }
        }
        lines.append(copy.pdfPairDiffHeading)
        if let diff = evidence.pairDiff {
            if diff.inputChanges.isEmpty {
                lines.append(copy.pairDiffInputsSameShort)
            } else {
                for change in diff.inputChanges {
                    lines.append(change.sentence)
                }
            }
            if let reason = diff.basisMismatchReason {
                lines.append(reason)
            }
            for delta in diff.resultDeltas {
                let first = delta.first.map { format($0) } ?? "—"
                let second = delta.second.map { format($0) } ?? "—"
                lines.append(
                    copy.pairDeltaLine(
                        label: delta.label,
                        first: first,
                        second: second,
                        unit: delta.unit,
                        delta: delta.delta
                    )
                )
            }
        } else {
            lines.append(copy.pairDiffSingleScheme)
        }
        lines.append(copy.pdfDetailedIDs)
        for run in evidence.candidates {
            lines.append(run.name)
            lines.append(run.runID.uuidString)
            lines.append(run.inputHash)
            lines.append(copy.qualityTitle(run.quality))
        }
        return lines.joined(separator: "\n")
    }

    /// Same two-decimal display as the rest of the UI. Stored run values stay full precision.
    private static func format(_ value: Double) -> String {
        UserFacingCopy.displayNumber(value)
    }

    // MARK: - HTML

    /// DeepSeek text is arbitrary model output. It must never be interpolated
    /// into the HTML template unescaped.
    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// One styled page: title, model caption, guarded body sections, suggested
    /// actions, then the small-print evidence appendix. Letter size, metric
    /// two-decimal figures, no invented numbers.
    static func htmlDocument(evidence: ReportEvidence, report: GeneratedReport, copy: UserFacingCopy) -> String {
        let lang = copy.language == .chinese ? "zh-Hans" : "en"
        let title = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = """
        <!DOCTYPE html>
        <html lang="\(lang)">
        <head>
        <meta charset="utf-8">
        <style>
        @page { margin: 40pt 48pt; }
        body {
          font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
          font-size: 10.5pt; line-height: 1.55; color: #1d1d1f;
          -webkit-print-color-adjust: exact;
        }
        h1 { font-size: 17pt; font-weight: 600; margin: 0 0 4pt; }
        .caption { color: #6e6e73; font-size: 8.5pt; margin: 0 0 12pt; }
        .summary { margin: 0 0 14pt; }
        h2 {
          font-size: 12pt; font-weight: 600; margin: 16pt 0 6pt;
          padding-left: 6pt; border-left: 2.5pt solid #0a84ff;
          break-after: avoid;
        }
        p { margin: 0 0 8pt; }
        ul.actions { margin: 0 0 8pt; padding-left: 14pt; }
        ul.actions li { margin: 0 0 4pt; }
        .appendix { border-top: 0.5pt solid #d2d2d7; margin-top: 18pt; padding-top: 10pt; }
        .appendix h3 { font-size: 11pt; font-weight: 600; margin: 12pt 0 5pt; break-after: avoid; }
        .appendix p { font-size: 8.5pt; color: #3a3a3c; margin: 0 0 3.5pt; line-height: 1.45; }
        .appendix p.scheme { font-weight: 600; color: #1d1d1f; margin-top: 6pt; }
        </style>
        </head>
        <body>
        <h1>\(escapeHTML(title.isEmpty ? copy.pdfFallbackTitle : title))</h1>
        <p class="caption">\(escapeHTML(copy.pdfDeepSeekCaption))</p>
        <p class="summary">\(escapeHTML(report.summary))</p>
        """

        for section in report.sections {
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty {
                body += "<h2>\(escapeHTML(heading))</h2>\n"
            }
            let text = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                body += "<p>\(escapeHTML(text))</p>\n"
            }
        }

        if !report.caveats.isEmpty {
            body += "<h2>\(escapeHTML(copy.pdfSuggestedActions))</h2>\n<ul class=\"actions\">\n"
            for caveat in report.caveats where !caveat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body += "<li>\(escapeHTML(caveat))</li>\n"
            }
            body += "</ul>\n"
        }

        body += appendixHTML(evidence: evidence, copy: copy)
        body += "</body>\n</html>\n"
        return body
    }

    /// The appendix keeps its line content from `appendix(evidence:copy:)` (tests
    /// pin those lines); here each line is classed into heading / scheme / detail.
    private static func appendixHTML(evidence: ReportEvidence, copy: UserFacingCopy) -> String {
        let schemeNames = Set(evidence.candidates.map(\.name))
        var html = "<div class=\"appendix\">\n"
        for line in appendix(evidence: evidence, copy: copy).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if copy.isPDFHeading(trimmed) {
                html += "<h3>\(escapeHTML(trimmed))</h3>\n"
            } else if schemeNames.contains(trimmed) {
                html += "<p class=\"scheme\">\(escapeHTML(trimmed))</p>\n"
            } else {
                html += "<p>\(escapeHTML(trimmed))</p>\n"
            }
        }
        html += "</div>\n"
        return html
    }

    // MARK: - WebKit render

    #if canImport(WebKit)
    /// Lays out the page offscreen and snapshots it as one Letter-size PDF.
    /// WKWebView is MainActor-isolated; callers hop here from any async context.
    @MainActor
    private static func renderPDFData(html: String) async throws -> Data {
        // Zero-frame WKWebView lays HTML out in a zero-width viewport and the
        // text stacks one glyph per line. Pin the page frame to Letter size.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let webView = WKWebView(frame: pageRect)
        webView.loadHTMLString(html, baseURL: nil)
        // Poll the load flag; a plain test host or a background export has no
        // runloop-driven UI waiting for a navigation delegate.
        var waitedMilliseconds = 0
        while webView.isLoading && waitedMilliseconds < 10_000 {
            try await Task.sleep(for: .milliseconds(50))
            waitedMilliseconds += 50
        }
        if webView.isLoading {
            // A hung load must not hang the export. No partial document.
            throw EvidencePDFError.writeFailed
        }
        // A non-null rect captures only that single region. CGRect.null keeps
        // the whole scrollable content and paginates it into a multi-page PDF.
        let configuration = WKPDFConfiguration()
        configuration.rect = .null
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                webView.createPDF(configuration: configuration) { result in
                    switch result {
                    case .success(let data): continuation.resume(returning: data)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            throw EvidencePDFError.writeFailed
        }
    }
    #endif
}
