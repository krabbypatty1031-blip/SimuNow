import Foundation
import CryptoKit
import SimuCore
#if canImport(CoreText)
import CoreText
import CoreGraphics
#endif

public enum LocalReportFormat: String, CaseIterable, Sendable { case plainText, evidenceSummary, pdf }
public struct LocalReportExport: Sendable {
    public let data: Data
    public let exportHash: String
    public let fileExtension: String
}
public enum LocalReportExporter {
    private struct Envelope: Encodable {
        let owner = "com.simunow.redacted-report"
        let exportVersion = 1
        let hashFormat = "sha256.sorted-json.iso8601.v1"
        let exportHash: String
        let snapshot: LocalReportSnapshot
    }
    public static func export(_ snapshot: LocalReportSnapshot, format: LocalReportFormat) throws -> LocalReportExport {
        guard snapshot.reportVersion == 1, !snapshot.runs.isEmpty, snapshot.runs.count <= 12,
              snapshot.runs.allSatisfy({ $0.checks == .passed }) else { throw ProjectDataError.contract("报告证据不可导出。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
        let canonical = try encoder.encode(snapshot)
        guard canonical.count <= 256 * 1024 else { throw ProjectDataError.contract("匿名报告超过 256 KiB 上限。") }
        let hash = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        let envelopeData = try encoder.encode(Envelope(exportHash: hash, snapshot: snapshot))
        try WireSchema.validate(JSONValue(data: envelopeData), schema: NativeAnalysisCodec.schema(.redactedReport))
        let data: Data; let ext: String
        switch format {
        case .evidenceSummary: data = envelopeData; ext = "json"
        case .plainText: data = Data(text(snapshot, exportHash: hash).utf8); ext = "txt"
        case .pdf:
            #if canImport(CoreText)
            data = try pdf(text(snapshot, exportHash: hash)); ext = "pdf"
            #else
            throw ProjectDataError.contract("此平台不支持 PDF 绘图。")
            #endif
        }
        return .init(data: data, exportHash: hash, fileExtension: ext)
    }
    public static func text(_ snapshot: LocalReportSnapshot, exportHash: String) -> String {
        var lines = ["SimuNow · 匿名分析建议", "报告 v\(snapshot.reportVersion) · \(snapshot.reportID)", "创建时间：\(snapshot.createdAt.ISO8601Format())", ""]
        for run in snapshot.runs {
            lines += ["\(run.scenarioAlias) · \(ReportRedactor.methodName(run.reference.method.kind)) v\(run.reference.method.methodVersion)",
                      run.historical ? "对应历史输入；不能作为当前有效建议。" : "导出时与当前方法输入一致。", "方法检查通过；不代表物理验证。"]
            lines += run.lines + run.assumptions + run.missingReasons
            lines += ["Run：\(run.reference.runID)", "方案 ID：\(run.reference.scenarioID)", "原 inputHash：\(run.reference.inputHash)", ""]
        }
        if let comparison = snapshot.comparison {
            lines += ["固定比较：\(comparison.comparisonID)", "原比较口径哈希：\(comparison.comparisonContextHash)"]
            lines += comparison.incomparableReasons.map(\.reason)
            for metric in comparison.metrics ?? [] {
                lines.append("\(metric.metric)：基准 \(metric.baseline.map(String.init(describing:)) ?? "未知")，候选 \(metric.candidate.map(String.init(describing:)) ?? "未知") \(metric.unit)")
            }
        }
        lines += [""] + snapshot.limitations + ["删减字段：\(snapshot.redactedFields.joined(separator: "、"))", "匿名 exportHash：\(exportHash)"]
        return lines.joined(separator: "\n")
    }
    #if canImport(CoreText)
    private static func pdf(_ text: String) throws -> Data {
        let storage = NSMutableData()
        guard let consumer = CGDataConsumer(data: storage as CFMutableData) else { throw ProjectDataError.contract("无法创建 PDF 数据。") }
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw ProjectDataError.contract("无法创建 PDF 页面。") }
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 11, nil)
        let content = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let setter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        var offset = 0; var pageNumber = 0
        while offset < content.length {
            try Task.checkCancellation(); pageNumber += 1
            guard pageNumber <= 64 else { throw ProjectDataError.contract("报告超过 64 页。") }
            context.beginPDFPage(nil)
            let path = CGPath(rect: CGRect(x: 42, y: 55, width: 511, height: 745), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw ProjectDataError.contract("PDF 排版未能继续分页。") }
            CTFrameDraw(frame, context)
            let footer = NSAttributedString(string: "SimuNow · 匿名证据摘要 · \(pageNumber)", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 42, y: 28); CTLineDraw(CTLineCreateWithAttributedString(footer as CFAttributedString), context)
            context.endPDFPage(); offset += visible.length
        }
        context.closePDF(); return storage as Data
    }
    #endif
}
