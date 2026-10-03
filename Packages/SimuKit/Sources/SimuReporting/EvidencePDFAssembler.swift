import Foundation
import SimuCore
#if os(macOS)
import AppKit
import CoreText
#endif

public enum EvidencePDFError: Error, Equatable {
    /// iOS has no PDF writer in this phase. Callers must not invent a stand-in document.
    case unsupportedPlatform
    /// Quality failed, no feasible seats, or mixed basis. The page may explain; it must not write a recommendation PDF.
    case notExportable
    /// DeepSeek is missing, refused, or returned nothing usable.
    case generatorUnavailable
    case writeFailed
}

/// Draws a DeepSeek-written report plus a local evidence appendix.
public enum EvidencePDFAssembler {
    public static func write(
        evidence: ReportEvidence,
        report: GeneratedReport,
        copy: UserFacingCopy = .english,
        to url: URL
    ) throws {
        #if os(macOS)
        let guarded = NarrationGuard.filter(report, evidence: evidence)
        try writePDF(report: guarded, evidence: evidence, copy: copy, to: url)
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
                let reference = item.reference ?? ""
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

    #if os(macOS)
    private static func writePDF(
        report: GeneratedReport,
        evidence: ReportEvidence,
        copy: UserFacingCopy,
        to url: URL
    ) throws {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw EvidencePDFError.writeFailed
        }
        let chinese = copy.language == .chinese
        let titleFont = CTFontCreateWithName((chinese ? "PingFangSC-Medium" : "Helvetica-Bold") as CFString, 18, nil)
        let headingFont = CTFontCreateWithName((chinese ? "PingFangSC-Medium" : "Helvetica-Bold") as CFString, 13, nil)
        let bodyFont = CTFontCreateWithName((chinese ? "PingFangSC-Regular" : "Helvetica") as CFString, 11, nil)
        let captionFont = CTFontCreateWithName((chinese ? "PingFangSC-Regular" : "Helvetica") as CFString, 9, nil)
        let margin: CGFloat = 48
        let width = media.width - margin * 2
        var y = media.height - margin

        func newPage() {
            context.endPDFPage()
            context.beginPDFPage(nil)
            y = media.height - margin
        }

        func ensure(_ height: CGFloat) {
            if y - height < margin {
                newPage()
            }
        }

        func drawWrapped(_ text: String, font: CTFont, lineHeight: CGFloat) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let attributed = NSAttributedString(string: trimmed, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var start = 0
            let count = attributed.length
            while start < count {
                ensure(lineHeight)
                let breakIndex = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                let length = max(breakIndex, 1)
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length))
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: margin, y: y)
                CTLineDraw(line, context)
                context.restoreGState()
                y -= lineHeight
                start += length
            }
            y -= 6
        }

        context.beginPDFPage(nil)
        drawWrapped(report.title, font: titleFont, lineHeight: 24)
        drawWrapped(copy.pdfDeepSeekCaption, font: captionFont, lineHeight: 13)
        drawWrapped(report.summary, font: bodyFont, lineHeight: 16)
        for section in report.sections {
            drawWrapped(section.heading, font: headingFont, lineHeight: 18)
            drawWrapped(section.body, font: bodyFont, lineHeight: 16)
        }
        if !report.caveats.isEmpty {
            drawWrapped(copy.pdfSuggestedActions, font: headingFont, lineHeight: 18)
            for caveat in report.caveats {
                drawWrapped(caveat, font: bodyFont, lineHeight: 16)
            }
        }
        for line in appendix(evidence: evidence, copy: copy).components(separatedBy: "\n") {
            let isHeading = copy.isPDFHeading(line)
            drawWrapped(line, font: isHeading ? headingFont : captionFont, lineHeight: isHeading ? 18 : 13)
        }
        context.endPDFPage()
        context.closePDF()
        do {
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            throw EvidencePDFError.writeFailed
        }
    }
    #endif
}
