import Foundation
import SimuCore
import SimuSimulation

/// Pure comparison logic for scenario decision (P5). L0-only scope: capacity, total energy
/// and cost. Spatial comfort is never claimed here — it needs L2 (hard rule 5).
public enum ComparisonModel {

    // MARK: - Eligibility

    /// A run feeds comparison only when completed, quality-passed and current. Terminal,
    /// quality and freshness are independent axes (hard rule 7; stale is not deleted).
    public static func eligibility(of record: RunRecord?, currentHash: String?) -> Eligibility {
        guard let record else { return .noRun }
        guard record.status == .completed, let result = record.result, result.state == .completed else {
            return .notCompleted(record.status)
        }
        guard result.quality.state == .passed else { return .qualityFailed }
        guard let currentHash, record.identity.freshness(relativeTo: currentHash) == .current else { return .stale }
        return .eligible
    }

    public enum Eligibility: Equatable, Sendable {
        case eligible
        case noRun
        case notCompleted(RunStatus)
        case qualityFailed
        case stale

        public var explanation: String {
            switch self {
            case .eligible: "有效"
            case .noRun: "尚无运行"
            case .notCompleted(let status): "未完成（\(status.title)）"
            case .qualityFailed: "质量失败，禁止用于推荐"
            case .stale: "输入已修改，待重算"
            }
        }
    }

    public struct Row: Equatable, Sendable {
        public let scenarioID: UUID
        public let scenarioName: String
        public let representativeDate: String?
        public let eligibility: Eligibility
        public let record: RunRecord?
        /// Canonical text of {environment, usage}: the shared-basis key for fair comparison.
        public let basisKey: String?
    }

    public static func rows(project: ProjectDocument, records: [RunRecord], currentHashes: [UUID: String]) -> [Row] {
        project.scenarios.map { scenario in
            let record = records.first { $0.identity.scenarioID == scenario.id }
            let hash = currentHashes[scenario.id]
            return Row(scenarioID: scenario.id, scenarioName: scenario.name,
                       representativeDate: scenario.inputs.environment.representativeDate,
                       eligibility: eligibility(of: record, currentHash: hash),
                       record: record, basisKey: basisKey(of: scenario))
        }
    }

    /// Same-weather / same-occupancy basis: environment + usage, canonical serialization.
    public static func basisKey(of scenario: Scenario) -> String? {
        guard let inputs = try? JSONTreeCoding.encode(scenario.inputs),
              let environment = inputs["environment"], let usage = inputs["usage"],
              let combined = try? JSONValue.object(["environment": environment, "usage": usage]).text() else {
            return nil
        }
        return combined
    }

    /// Largest same-basis group among eligible rows; others are flagged 口径不同.
    public static func mainBasisGroup(rows: [Row]) -> (key: String?, members: [Row], excluded: [Row]) {
        let eligible = rows.filter { $0.eligibility == .eligible }
        var counts: [String: Int] = [:]
        for row in eligible { if let key = row.basisKey { counts[key, default: 0] += 1 } }
        guard let key = counts.max(by: { $0.value < $1.value })?.key else {
            return (nil, [], eligible)  // nothing comparable without a shared basis
        }
        let members = eligible.filter { $0.basisKey == key }
        return (key, members, eligible.filter { $0.basisKey != key })
    }

    // MARK: - Candidates (L0-scope only: setpoint)

    /// Duplicate the scenario with setpoint offsets (°C). Entity IDs are preserved (same
    /// objects, different settings); the scenario ID is new. Unknown setpoint generates
    /// nothing; candidates outside 16–30 °C are skipped. Direction/angle candidates are
    /// impossible at L0 and are never generated.
    public static func setpointCandidates(of scenario: Scenario, offsets: [Double] = [-1, 1]) -> [Scenario] {
        guard let setpoint = scenario.inputs.controls.first?.setpoint.value else { return [] }
        return offsets.compactMap { offset in
            let newValue = setpoint + offset
            guard (16...30).contains(newValue) else { return nil }
            var copy = scenario
            copy.id = UUID()
            copy.name = "\(scenario.name) · 设定 \(newValue.formatted())°C"
            for index in copy.inputs.controls.indices {
                if case .known(let value, let source, let uncertainty) = copy.inputs.controls[index].setpoint {
                    copy.inputs.controls[index].setpoint = .known(value: value + offset, source: source, uncertainty: uncertainty)
                }
            }
            return copy
        }
    }

    // MARK: - Recommendation cards

    public struct Card: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable { case operation, capacity, comfort }
        public let kind: Kind
        public let title: String
        public let body: String
        public let runID: UUID?
    }

    /// Cards cite a fixed run ID and method; no card contains spatial comfort numbers.
    public static func cards(rows: [Row]) -> [Card] {
        let (_, members, excluded) = mainBasisGroup(rows: rows)
        guard !members.isEmpty else {
            return [Card(kind: .operation, title: "尚无有效结果可用于建议",
                         body: "需要至少一个已完成、质量通过且未过期的 L0 运行。失败或过期结果不参与推荐。", runID: nil)]
        }
        var cards: [Card] = []

        // 1. Operation adjustment: lowest estimated electric energy among capacity-adequate scenarios.
        let adequate = members.filter { $0.record?.result?.metric(named: "capacityAdequate")?.boolValue == true }
        let withElectric = adequate.compactMap { row -> (Row, Double)? in
            guard let value = row.record?.result?.metric(named: "estimatedElectricEnergy")?.doubleValue else { return nil }
            return (row, value)
        }
        if let (best, value) = withElectric.min(by: { $0.1 < $1.1 }) {
            let date = best.representativeDate.map { "，代表日 \($0)" } ?? ""
            let runID = best.record?.identity.runID
            let short = runID.map { String($0.uuidString.prefix(8)) } ?? "?"
            var body = "在 \(members.count) 个同口径方案中，「\(best.scenarioName)」代表日估算电耗最低：\(format(value)) kWh（L0 平均估算，等效 COP 口径\(date)）。依据 run \(short)，方法 l0_steady_state。"
            if let metric = best.record?.result?.metric(named: "dailyCost"), let cost = metric.doubleValue {
                body += " 对应日费用约 \(format(cost)) \(metric.unit)。"
            }
            if !excluded.isEmpty {
                body += " 另有 \(excluded.count) 个有效方案因口径不同（天气/人数/时段）未参与排序。"
            }
            if withElectric.count < 2 {
                body += " 只有一个方案可比较；复制方案并改设定温度后可比较。"
            }
            cards.append(Card(kind: .operation, title: "运行调整", body: body, runID: runID))
        } else if adequate.isEmpty {
            cards.append(Card(kind: .operation, title: "运行调整",
                              body: "参与对比的方案均容量不足（代表日峰值超过制冷量），先解决容量再比较运行费用。",
                              runID: nil))
        }

        // 2. Capacity / configuration.
        let undersized = members.filter { $0.record?.result?.metric(named: "capacityAdequate")?.boolValue == false }
        if !undersized.isEmpty {
            let details = undersized.map { row -> String in
                let peak = row.record?.result?.metric(named: "coolingLoadPeak")?.doubleValue
                return "「\(row.scenarioName)」峰值负荷 \(peak.map { "\(format($0)) W" } ?? "未知")"
            }.joined(separator: "；")
            cards.append(Card(kind: .capacity, title: "容量配置",
                              body: "\(details)，代表日容量不足（L0 平均估算口径）。建议核实设备制冷量或降低负荷；选型报价需另行询价。",
                              runID: undersized.first?.record?.identity.runID))
        } else {
            cards.append(Card(kind: .capacity, title: "容量配置",
                              body: "参与对比的方案代表日峰值均未超过设备制冷量（L0 平均估算口径）。",
                              runID: nil))
        }

        // 3. Comfort: an honest status, not a conclusion.
        cards.append(Card(kind: .comfort, title: "舒适改善",
                          body: "位置级舒适（PMV/吹风/垂直温差）需要 L2 CFD 结果，当前未评价；本页任何内容都不表示舒适达标或不达标。",
                          runID: nil))
        return cards
    }

    public static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
