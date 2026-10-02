import SwiftUI
import SimuCore
import SimuSimulation

/// Scenario comparison page (P5): candidate generation, recommendation cards, same-basis
/// comparison table and cost layering. L0-only: no spatial comfort, no annual extrapolation.
public struct ComparisonView: View {
    let session: ProjectSession
    let runStore: RunStore

    public init(session: ProjectSession, runStore: RunStore) {
        self.session = session
        self.runStore = runStore
    }

    private var rows: [ComparisonModel.Row] {
        ComparisonModel.rows(project: session.project, records: runStore.records, currentHashes: runStore.currentHashes)
    }

    public var body: some View {
        let currentRows = rows
        let cards = ComparisonModel.cards(rows: currentRows)
        let (_, members, excluded) = ComparisonModel.mainBasisGroup(rows: currentRows)
        List {
            Section("方案管理") {
                ForEach(session.project.scenarios, id: \.id) { scenario in
                    HStack {
                        Button { session.currentScenarioID = scenario.id } label: {
                            HStack {
                                Text(scenario.name)
                                if scenario.id == session.currentScenarioID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        Spacer()
                        Button { session.duplicateScenario(scenario.id, name: scenario.name + " 候选") } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制为候选方案（实体身份保留，可独立改参数）")
                    }
                    if let runStoreRow = currentRows.first(where: { $0.scenarioID == scenario.id }) {
                        LatestRunSummary(record: runStoreRow.record,
                                         freshness: runStoreRow.record
                                            .map { $0.freshness(relativeTo: runStore.currentHash(for: scenario.id)) } ?? .stale)
                    }
                }
                HStack {
                    Button("生成 ±1°C 设定温度候选") { addSetpointCandidates() }
                        .disabled(session.currentScenario == nil)
                    Text("风向/角度类候选需要 L2 CFD，当前不可评价").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section("建议卡") {
                ForEach(cards, id: \.title) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title).font(.callout.bold())
                        Text(card.body).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("对比（\(members.count) 个同口径有效方案）") {
                if members.isEmpty {
                    Text("没有可对比的有效结果：运行需完成、质量通过且未过期。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    comparisonTable(members: members)
                }
                if !excluded.isEmpty {
                    Text("口径不同（天气/人数/时段），未参与排序：\(excluded.map(\.scenarioName).joined(separator: "、"))")
                        .font(.caption2).foregroundStyle(.orange)
                }
                let ineligible = currentRows.filter { $0.eligibility != .eligible }
                if !ineligible.isEmpty {
                    ForEach(ineligible, id: \.scenarioID) { row in
                        Text("「\(row.scenarioName)」未参与：\(row.eligibility.explanation)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section("费用") {
                ForEach(session.project.scenarios, id: \.id) { scenario in
                    costBlock(scenario)
                }
                Text("代表日费用不外推全年；报价与电价缺失时显示待报价，不按 0 计。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func addSetpointCandidates() {
        guard let scenario = session.currentScenario else { return }
        let candidates = ComparisonModel.setpointCandidates(of: scenario)
        guard !candidates.isEmpty else { return }
        session.mutate { document in
            document.scenarios.append(contentsOf: candidates)
        }
    }

    private func comparisonTable(members: [ComparisonModel.Row]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("方案").bold()
                Text("峰值负荷").bold()
                Text("日冷量").bold()
                Text("估算电耗").bold()
                Text("日费用").bold()
                Text("容量").bold()
                Text("run").bold()
            }
            .font(.caption)
            ForEach(members, id: \.scenarioID) { row in
                GridRow {
                    Text(row.scenarioName)
                    Text(metricText(row, "coolingLoadPeak"))
                    Text(metricText(row, "dailyCoolingEnergy"))
                    Text(metricText(row, "estimatedElectricEnergy"))
                    Text(metricText(row, "dailyCost"))
                    Text(adequacyText(row))
                    Text(row.record.map { String($0.identity.runID.uuidString.prefix(8)) } ?? "—")
                        .font(.caption2.monospaced())
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricText(_ row: ComparisonModel.Row, _ name: String) -> String {
        guard let metric = row.record?.result?.metric(named: name) else { return "—" }
        if metric.isMissing { return "缺失" }
        if let flag = metric.boolValue { return flag ? "是" : "否" }
        guard let value = metric.doubleValue else { return "—" }
        return "\(ComparisonModel.format(value)) \(metric.unit)"
    }

    private func adequacyText(_ row: ComparisonModel.Row) -> String {
        guard let metric = row.record?.result?.metric(named: "capacityAdequate"), let flag = metric.boolValue else { return "未知" }
        return flag ? "充足" : "不足"
    }

    private func costBlock(_ scenario: Scenario) -> some View {
        let cost = scenario.evaluation.cost
        return VStack(alignment: .leading, spacing: 2) {
            Text(scenario.name).font(.caption.bold())
            if let currency = cost.currency {
                Text("币种 \(currency)").font(.caption2).foregroundStyle(.secondary)
            }
            if cost.tariffs.isEmpty && cost.quotes.isEmpty {
                Text("待报价/待电价").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(cost.tariffs.indices, id: \.self) { index in
                let tariff = cost.tariffs[index]
                Text("电价 \(tariff.startMinute)–\(tariff.endMinute) min：\(tariff.rate.value.map(ComparisonModel.format) ?? "未知") \(cost.currency ?? "币种未填")/kWh")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(cost.quotes, id: \.id) { quote in
                Text("报价：\(quote.amount.value.map(ComparisonModel.format) ?? "待报价") \(cost.currency ?? (quote.amount.value == nil ? "" : "币种未填"))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
