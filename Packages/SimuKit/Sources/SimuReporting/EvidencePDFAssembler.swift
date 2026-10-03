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
        to url: URL
    ) throws {
        #if os(macOS)
        let guarded = NarrationGuard.filter(report, evidence: evidence)
        try writePDF(report: guarded, evidence: evidence, to: url)
        #else
        throw EvidencePDFError.unsupportedPlatform
        #endif
    }

    /// Local appendix. Every figure is formatted from an evidence field.
    static func appendix(evidence: ReportEvidence) -> String {
        var lines: [String] = []
        lines.append("计算依据")
        if let price = evidence.candidates.compactMap(\.pricePerKWh).first {
            let currency = evidence.candidates.compactMap(\.currency).first ?? ""
            lines.append("电价 \(format(price)) \(currency)/kWh")
        }
        let bandLow = evidence.candidates.first?.seatBandLowC ?? SeatFeasibility.airLowC
        let bandHigh = evidence.candidates.first?.seatBandHighC ?? SeatFeasibility.airHighC
        lines.append("座位合适范围：\(format(bandLow))–\(format(bandHigh)) °C")
        lines.append("方案")
        for run in evidence.candidates {
            lines.append(run.name)
            if let count = run.windowCount, count > 0, let area = run.windowAreaM2 {
                lines.append("窗户 \(count) 扇，面积 \(format(area)) m²")
            } else if let count = run.windowCount, count > 0 {
                lines.append("窗户 \(count) 扇")
            }
            if let mean = run.indoorMeanC {
                lines.append("室内平均温度 \(format(mean)) °C")
            }
            if let minC = run.indoorMinC, let maxC = run.indoorMaxC {
                lines.append("室内温度 \(format(minC))–\(format(maxC)) °C")
            }
            if let minU = run.flowMinMps, let maxU = run.flowMaxMps {
                lines.append("气流 \(format(minU))–\(format(maxU)) m/s")
            } else if let speed = run.seatSpeedMaxMps {
                lines.append("座位最大风速 \(format(speed)) m/s")
            }
            if let cooling = run.coolingW {
                lines.append("制冷量 \(format(cooling)) W")
            }
            if let electric = run.electricPowerW {
                lines.append("电功率 \(format(electric)) W")
            }
            if run.seatPassRatioOmitted || run.seatPassRatio == nil {
                lines.append("合适的座位 不可评价")
            } else if let ratio = run.seatPassRatio {
                lines.append("合适的座位 \(format(ratio))")
            }
            if let energy = run.dayEnergyKWh {
                lines.append("代表日用电 \(format(energy)) kWh")
            }
            if let annual = run.annualEnergyKWh {
                lines.append("全年用电 \(format(annual)) kWh")
            }
            if let cost = run.dayCost, let currency = run.currency {
                lines.append("代表日电费 \(format(cost)) \(currency)")
            }
            if let annual = run.annualCost, let currency = run.currency {
                lines.append("全年电费 \(format(annual)) \(currency)")
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
        lines.append("两个方案的差异")
        if let diff = evidence.pairDiff {
            if diff.inputChanges.isEmpty {
                lines.append("两个方案输入相同")
            } else {
                for change in diff.inputChanges {
                    lines.append(change.sentence)
                }
            }
            if let reason = diff.basisMismatchReason {
                lines.append(reason)
            }
            for delta in diff.resultDeltas {
                // e.g. 座位最凉 24.21 → 24.43 °C（差 +0.22）
                let first = delta.first.map { format($0) } ?? "—"
                let second = delta.second.map { format($0) } ?? "—"
                if let deltaValue = delta.delta {
                    let sign = deltaValue >= 0 ? "+" : ""
                    lines.append("\(delta.label) \(first) → \(second) \(delta.unit)（差 \(sign)\(format(deltaValue))）")
                } else {
                    lines.append("\(delta.label) \(first) → \(second) \(delta.unit)")
                }
            }
        } else {
            lines.append("只有一个方案，没有差值")
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
    private static func writePDF(
        report: GeneratedReport,
        evidence: ReportEvidence,
        to url: URL
    ) throws {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw EvidencePDFError.writeFailed
        }
        let titleFont = CTFontCreateWithName("PingFangSC-Medium" as CFString, 18, nil)
        let headingFont = CTFontCreateWithName("PingFangSC-Medium" as CFString, 13, nil)
        let bodyFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, 11, nil)
        let captionFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, 9, nil)
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
        drawWrapped(
            "以下正文由 DeepSeek 根据计算结果整理。",
            font: captionFont,
            lineHeight: 13
        )
        drawWrapped(report.summary, font: bodyFont, lineHeight: 16)
        for section in report.sections {
            drawWrapped(section.heading, font: headingFont, lineHeight: 18)
            drawWrapped(section.body, font: bodyFont, lineHeight: 16)
        }
        if !report.caveats.isEmpty {
            drawWrapped("行动建议", font: headingFont, lineHeight: 18)
            for caveat in report.caveats {
                drawWrapped(caveat, font: bodyFont, lineHeight: 16)
            }
        }
        for line in appendix(evidence: evidence).components(separatedBy: "\n") {
            let isHeading = line == "计算依据" || line == "方案" || line == "查看依据与限制" || line == "详细编号"
                || line == "两个方案的差异" || line == "行动建议"
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
