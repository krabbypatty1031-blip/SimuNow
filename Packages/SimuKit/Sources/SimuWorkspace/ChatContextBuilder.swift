import Foundation
import SimuCore

/// Builds the plain-language draft summary the consult assistant sees.
/// Every figure here comes straight off the live draft, so the assistant
/// quotes the user's own numbers, never a recomputed or invented one.
enum ChatContextBuilder {
    /// Nil when no project is loaded. Chinese short lines, no jargon:
    /// this block is pasted into the system message as-is.
    static func draftSummary(for draft: ProjectDraft?) -> String? {
        guard let draft else { return nil }
        var lines: [String] = []
        if let geometry = draft.geometry {
            lines.append(
                "房间 \(UserFacingCopy.displayNumber(geometry.sizeX.value)) × \(UserFacingCopy.displayNumber(geometry.sizeY.value)) × \(UserFacingCopy.displayNumber(geometry.sizeZ.value)) m"
            )
        }
        if let occupancy = draft.occupancy {
            let people = UserFacingCopy.displayNumber(occupancy.occupantCount.value)
            if let schedule = occupancy.schedule {
                lines.append("\(people) 人，\(schedule.start)–\(schedule.end) 使用")
            } else {
                lines.append("\(people) 人")
            }
        }
        if let hvac = draft.hvac {
            var hvacLine: [String] = []
            hvacLine.append("设定温度 \(UserFacingCopy.displayNumber(hvac.setpointC.value)) °C")
            // PhysicalQuantity.value is a plain Double (never Optional), so
            // these two lines show unconditionally; no `if let` unwrap here.
            hvacLine.append("出风温度 \(UserFacingCopy.displayNumber(hvac.supplyTemperatureC.value)) °C")
            hvacLine.append("能效比 \(UserFacingCopy.displayNumber(hvac.cop.value))")
            lines.append(hvacLine.joined(separator: "，"))
        }
        if let geometry = draft.geometry {
            let windows = geometry.openings.filter { $0.kind == .window }
            let area = windows.reduce(0.0) { $0 + $1.patchAreaM2 }
            lines.append("窗 \(windows.count) 扇共 \(UserFacingCopy.displayNumber(area)) m²")
        }
        if let costs = draft.costAssumptions, let price = costs.pricePerKWh {
            lines.append("电价 \(UserFacingCopy.displayNumber(price)) \(costs.currency)/kWh")
        }
        guard !lines.isEmpty else { return nil }
        return "当前草稿：" + lines.joined(separator: "；") + "。"
    }
}
