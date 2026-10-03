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
        lines.append("证据报告")
        lines.append("电价说明：\(evidence.tariffReference)")
        lines.append("座位带是模型门 \(format(evidence.candidates.first?.seatBandLowC ?? SeatFeasibility.airLowC))–\(format(evidence.candidates.first?.seatBandHighC ?? SeatFeasibility.airHighC)) °C。")
        lines.append("证据表")
        lines.append("名称")
        lines.append("run ID")
        lines.append("inputHash")
        lines.append("quality")
        lines.append("座位带 °C")
        lines.append("达标比例（模型）")
        lines.append("代表日 kWh")
        lines.append("代表日费用")
        for run in evidence.candidates {
            lines.append(run.name)
            lines.append(run.runID.uuidString)
            lines.append(run.inputHash)
            lines.append(run.quality.rawValue)
            lines.append("\(format(run.seatBandLowC))–\(format(run.seatBandHighC))")
            if run.seatPassRatioOmitted || run.seatPassRatio == nil {
                lines.append("达标比例（模型） 不可评价")
            } else if let ratio = run.seatPassRatio {
                lines.append(format(ratio))
            }
            if let energy = run.dayEnergyKWh {
                lines.append("\(format(energy)) kWh")
            } else {
                lines.append("代表日电量 省略")
            }
            if let cost = run.dayCost, let currency = run.currency {
                lines.append("\(format(cost)) \(currency)")
            } else {
                lines.append("代表日费用 省略")
            }
            if let z0 = run.supplyZ0M, let z1 = run.supplyZ1M {
                lines.append("送风口高度 \(format(z0))–\(format(z1)) m")
            }
        }
        lines.append("舒适假设")
        if evidence.comfortAssumptions.isEmpty {
            lines.append("无舒适假设")
        } else {
            for item in evidence.comfortAssumptions {
                let value = item.value.map(format) ?? "省略"
                let reference = item.reference ?? ""
                lines.append("\(item.name) \(value) \(item.unit) \(reference)")
            }
        }
        lines.append("建议")
        for card in evidence.cards {
            lines.append(card.kind.rawValue)
            lines.append(card.title)
            lines.append(card.detail)
            if let quote = card.quoteStatus {
                lines.append(quote)
            }
            for id in card.citedRunIDs {
                lines.append(id.uuidString)
            }
            for assumption in card.assumptions {
                lines.append(assumption)
            }
        }
        if let narration {
            lines.append("叙述")
            lines.append(narration.headline)
            for (key, prose) in narration.cardProse.sorted(by: { $0.key < $1.key }) {
                lines.append(key)
                lines.append(prose)
            }
            for caveat in narration.caveats {
                lines.append(caveat)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `%g` matches the guard and the PDF test for values such as 0.75 and 23.
    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
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
