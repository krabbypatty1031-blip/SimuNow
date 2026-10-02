import CoreGraphics
import CoreText
import Foundation

/// Basic text PDF (A4, paginated, selectable text) via CoreGraphics/CoreText.
/// Chosen over ImageRenderer (raster, non-selectable) and third-party libraries
/// (new dependency); see decisions.md. Renders the fixed ReportContent verbatim.
public struct BasicReportExporter: ReportExporter {
    public enum ExportError: Error, Equatable {
        /// No eligible (completed + quality-passed + current) runs: nothing honest to report.
        case noEligibleContent
        case writerUnavailable
    }

    public init() {}

    public func export(_ content: ReportContent, to destination: URL) async throws {
        guard !content.entries.isEmpty else { throw ExportError.noEligibleContent }
        let data = try Self.renderPDF(content)
        try data.write(to: destination, options: .atomic)
    }

    // MARK: - Layout

    private static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 at 72dpi
    private static let margin: CGFloat = 48

    static func renderPDF(_ content: ReportContent) throws -> Data {
        let attributed = buildText(content)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw ExportError.writerUnavailable }
        var mediaBox = pageRect
        let info: CFDictionary = [kCGPDFContextTitle: "SimuNow 方案报告",
                                  kCGPDFContextCreator: "SimuNow"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else {
            throw ExportError.writerUnavailable
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)
        var location = 0
        while location < attributed.length {
            context.beginPDFPage(nil)
            context.saveGState()
            // CoreText draws in a flipped (top-left origin) frame.
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1, y: -1)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0),
                                                 CGPath(rect: contentRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { context.endPDFPage(); break }
            location += visible.length
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - Text building

    private static func font(_ size: CGFloat, _ bold: Bool = false) -> CTFont {
        guard let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) else {
            preconditionFailure("System UI font unavailable")
        }
        return font
    }

    private static func append(_ text: NSMutableAttributedString, _ line: String,
                               size: CGFloat, bold: Bool = false, gapAfter: Bool = false) {
        let string = NSMutableAttributedString(string: line + (gapAfter ? "\n\n" : "\n"))
        string.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: font(size, bold),
                            range: NSRange(location: 0, length: string.length))
        text.append(string)
    }

    static func buildText(_ content: ReportContent) -> NSMutableAttributedString {
        let text = NSMutableAttributedString()
        append(text, "SimuNow 方案报告", size: 20, bold: true)
        append(text, "项目：\(content.projectName)", size: 11)
        append(text, "生成时间：\(content.generatedAt.formatted(date: .numeric, time: .standard))", size: 11, gapAfter: true)

        append(text, "范围与口径", size: 14, bold: true)
        for statement in content.scopeStatements { append(text, "· \(statement)", size: 10) }
        append(text, "", size: 10)

        append(text, "方案对比（仅收录已完成、质量通过且未过期的运行）", size: 14, bold: true)
        for entry in content.entries {
            append(text, "方案：\(entry.scenarioName)", size: 12, bold: true)
            append(text, "run \(entry.runID) · 输入哈希 \(String(entry.inputHash.prefix(12)))… · \(entry.fidelity) · 质量 \(entry.quality)\(entry.representativeDate.map { " · 代表日 \($0)" } ?? "")", size: 9)
            for metric in entry.metrics {
                append(text, "  \(metric.title)：\(metric.value)", size: 10)
            }
            for line in entry.costLines { append(text, "  \(line)", size: 10) }
            if !entry.assumptions.isEmpty {
                append(text, "  假设：", size: 9)
                for assumption in entry.assumptions { append(text, "  · \(assumption)", size: 9) }
            }
            append(text, "", size: 10)
        }

        append(text, "建议卡", size: 14, bold: true)
        for card in content.cards {
            append(text, "\(card.title)：\(card.body)", size: 10)
        }
        append(text, "", size: 10)

        append(text, "未知与假设清单", size: 14, bold: true)
        if content.unknownsAndAssumptions.isEmpty {
            append(text, "（无）", size: 10)
        } else {
            for item in content.unknownsAndAssumptions { append(text, "· \(item)", size: 9) }
        }
        append(text, "", size: 10)

        append(text, "限制与待补测", size: 14, bold: true)
        for item in content.limitations { append(text, "· \(item)", size: 10) }
        return text
    }
}
