import SwiftUI
import SimuCore
import SimuSimulation
import SimuDesignSystem

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
            Section {
                RoomPageIntro("哪种设置更合适？", detail: "复制一个方案，修改温度，再分别估算。")
                Text("当前比较用电与制冷能力，尚不能判断各座位是否舒适。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("我的方案") {
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
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制一份，单独修改设置")
                    }
                    if let runStoreRow = currentRows.first(where: { $0.scenarioID == scenario.id }) {
                        LatestRunSummary(record: runStoreRow.record,
                                         freshness: runStoreRow.record
                                            .map { $0.freshness(relativeTo: runStore.currentHash(for: scenario.id)) } ?? .stale)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button("试试调高 / 调低 1°C") { addSetpointCandidates() }
                        .disabled(session.currentScenario?.inputs.controls.first?.setpoint.value == nil)
                    Text("新增可用温度范围内的方案，不会改动当前设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("结果怎么理解") {
                ForEach(cards, id: \.title) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardTitle(card)).font(.callout.bold())
                        Text(cardSummary(card, rows: members)).font(.subheadline).foregroundStyle(.secondary)
                        DisclosureGroup("查看依据与限制") {
                            Text(card.body).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("相同条件下的对比 · \(members.count) 个方案") {
                if members.isEmpty {
                    Text("先到「用电估算」计算每个方案。结果需通过检查，修改过设置的方案需重新估算。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(members, id: \.scenarioID) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.scenarioName).font(.headline)
                            LabeledContent("一天预计用电", value: metricText(row, "estimatedElectricEnergy"))
                            LabeledContent("一天预计费用", value: metricText(row, "dailyCost"))
                            LabeledContent("制冷能力", value: adequacyText(row))
                        }
                        .font(.subheadline).padding(.vertical, 4)
                    }
                    DisclosureGroup("详细指标与计算编号") {
                        ScrollView(.horizontal) { comparisonTable(members: members) }
                    }
                }
                if !excluded.isEmpty {
                    Text("天气、人数或时间不同，未一起排序：\(excluded.map(\.scenarioName).joined(separator: "、"))")
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
                Text("费用只对应选定的一天；没有价格信息时不估算费用。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cardTitle(_ card: ComparisonModel.Card) -> String {
        switch card.kind {
        case .operation: "用电怎么选"
        case .capacity: "空调是否够用"
        case .comfort: "座位舒适度"
        }
    }

    private func cardSummary(_ card: ComparisonModel.Card, rows: [ComparisonModel.Row]) -> String {
        switch card.kind {
        case .operation:
            if let id = card.runID, let row = rows.first(where: { $0.record?.identity.runID == id }) {
                return "「\(row.scenarioName)」在可比方案中预计用电较少。"
            }
            return rows.isEmpty ? "先完成方案估算，再查看建议。" : "先核对制冷能力，再比较用电。"
        case .capacity: return card.runID == nil ? "这些方案的预计峰值需求未超过空调制冷能力。" : "有方案制冷能力不足，请先核对空调规格。"
        case .comfort: return "尚未评价；目前无法判断座位冷热和吹风感。"
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
        if metric.isMissing { return "暂无法估算" }
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
                Text("尚未提供电价和报价").font(.caption2).foregroundStyle(.secondary)
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
