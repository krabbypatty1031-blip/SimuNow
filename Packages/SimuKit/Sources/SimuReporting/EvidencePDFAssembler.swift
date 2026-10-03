import Foundation
import SimuCore
#if os(macOS)
import AppKit
import CoreText
#endif

public enum EvidencePDFError: Error, Equatable {
    /// iOS has no PDFKit writer in this phase. Callers must not invent a stand-in document.
    case unsupportedPlatform
    /// Quality failed, no feasible seats, or mixed basis. The page may explain; it must not write a recommendation PDF.
    case notExportable
    case writeFailed
}

/// Draws an evidence pack. Narration is optional and is filtered before it is drawn.
public enum EvidencePDFAssembler {
    public static func write(
        evidence: ReportEvidence,
        narration: ReportNarration?,
        to url: URL
    ) throws {
        #if os(macOS)
        let guarded = narration.map { NarrationGuard.filter($0, evidence: evidence) }
        try writePDF(render(evidence: evidence, narration: guarded), to: url)
        #else
        throw EvidencePDFError.unsupportedPlatform
        #endif
    }

    /// Plain-text body. Every figure is formatted from an evidence field.
    static func render(evidence: ReportEvidence, narration: ReportNarration?) -> String {
        var lines: [String] = []
        lines.append("对比说明")
        lines.append("电价说明：\(evidence.tariffReference)")
        let bandLow = evidence.candidates.first?.seatBandLowC ?? SeatFeasibility.airLowC
        let bandHigh = evidence.candidates.first?.seatBandHighC ?? SeatFeasibility.airHighC
        lines.append("座位合适范围：\(format(bandLow))–\(format(bandHigh)) °C（计算用的温度带，不是问卷）")
        lines.append("方案")
        for run in evidence.candidates {
            lines.append(run.name)
            if run.seatPassRatioOmitted || run.seatPassRatio == nil {
                lines.append("合适的座位 不可评价")
            } else if let ratio = run.seatPassRatio {
                lines.append("合适的座位 \(format(ratio))")
            }
            if let energy = run.dayEnergyKWh {
                lines.append("这一天用电 \(format(energy)) kWh")
            } else {
                lines.append("这一天用电 还没有")
            }
            if let cost = run.dayCost, let currency = run.currency {
                lines.append("这一天费用 \(format(cost)) \(currency)")
            } else {
                lines.append("这一天费用 还没有")
            }
            if let z0 = run.supplyZ0M, let z1 = run.supplyZ1M {
                lines.append("出风口离地 \(format(z0))–\(format(z1)) m")
            }
        }
        lines.append("查看依据与限制")
        if evidence.comfortAssumptions.isEmpty {
            lines.append("还没有舒适假设")
        } else {
            for item in evidence.comfortAssumptions {
                let value = item.value.map(format) ?? "还没有"
                let reference = item.reference ?? ""
                lines.append("\(UserFacingCopy.comfortKeyTitle(item.name)) \(value) \(item.unit) \(reference)")
            }
        }
        for card in evidence.cards {
            lines.append(card.kind.label)
            lines.append(card.title)
            lines.append(card.detail)
            if let quote = card.quoteStatus {
                lines.append(quote)
            }
            for assumption in card.assumptions {
                lines.append(assumption)
            }
        }
        if let narration {
            lines.append("说明文字")
            lines.append(narration.headline)
            for (key, prose) in narration.cardProse.sorted(by: { $0.key < $1.key }) {
                lines.append(key)
                lines.append(prose)
            }
            for caveat in narration.caveats {
                lines.append(caveat)
            }
        }
        lines.append("详细编号")
        for run in evidence.candidates {
            lines.append(run.name)
            lines.append(run.runID.uuidString)
            lines.append(run.inputHash)
            lines.append(UserFacingCopy.qualityTitle(run.quality))
        }
        return lines.joined(separator: "\n")
    }

    /// Same two-decimal display as the rest of the UI. Stored run values stay full precision.
    private static func format(_ value: Double) -> String {
        UserFacingCopy.displayNumber(value)
    }

    #if os(macOS)
    private static func writePDF(_ text: String, to url: URL) throws {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw EvidencePDFError.writeFailed
        }
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 9, nil)
        let lines = text.components(separatedBy: "\n")
        let margin: CGFloat = 36
        let lineHeight: CGFloat = 14
        var y = media.height - margin
        context.beginPDFPage(nil)
        for line in lines {
            if y < margin {
                context.endPDFPage()
                context.beginPDFPage(nil)
                y = media.height - margin
            }
            draw(line, at: CGPoint(x: margin, y: y), font: font, context: context)
            y -= lineHeight
        }
        context.endPDFPage()
        context.closePDF()
        do {
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            throw EvidencePDFError.writeFailed
        }
    }

    private static func draw(_ line: String, at point: CGPoint, font: CTFont, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let attributed = NSAttributedString(string: line, attributes: attributes)
        let ctLine = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: point.x, y: point.y)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }
    #endif
}
