import SwiftUI
import SimuCore
import SimuSimulation

/// Inline latest-result summary for a scenario row (P3 result panel). Always carries the
/// fidelity label; stale results say so instead of looking current.
public struct LatestRunSummary: View {
    let record: RunRecord?
    let freshness: ResultFreshness

    public init(record: RunRecord?, freshness: ResultFreshness) {
        self.record = record
        self.freshness = freshness
    }

    public var body: some View {
        switch (record, record?.result) {
        case (nil, _):
            Text("尚无计算结果").font(.caption2).foregroundStyle(.secondary)
        case (let record?, let result?) where record.status == .completed:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("L0 平均估算").font(.caption2)
                        .padding(.horizontal, 3).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 3))
                    if result.quality.state == .failed {
                        Text("质量失败").font(.caption2).foregroundStyle(.red)
                    }
                    if freshness == .stale {
                        Text("待重算").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Text(summaryLine(result)).font(.caption2).foregroundStyle(.secondary)
            }
        case (let record?, _):
            Text("最近运行：\(record.status.title)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func summaryLine(_ result: RunResult) -> String {
        var parts: [String] = []
        if let value = result.metric(named: "averageRoomTemperature")?.doubleValue {
            parts.append("平均室温 \(value.formatted())°C")
        }
        if let value = result.metric(named: "dailyCoolingEnergy")?.doubleValue {
            parts.append("日冷量 \(value.formatted()) kWh")
        }
        if let value = result.metric(named: "estimatedElectricEnergy")?.doubleValue {
            parts.append("电耗 \(value.formatted()) kWh")
        }
        if let metric = result.metric(named: "dailyCost"), let value = metric.doubleValue {
            parts.append("费用 \(value.formatted()) \(metric.unit)")
        }
        return parts.isEmpty ? "无可用指标（缺失项见运行详情）" : parts.joined(separator: " · ")
    }
}
