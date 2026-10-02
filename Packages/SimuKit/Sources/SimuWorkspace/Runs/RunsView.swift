import SwiftUI
import SimuCore
import SimuSimulation

/// Runs page: submit L0 runs, watch progress, inspect quality/assumptions, cancel.
/// L0 is a lumped average estimate — the page labels it everywhere and never shows point results.
public struct RunsView: View {
    let session: ProjectSession
    let runStore: RunStore
    @State private var showValidation = false

    public init(session: ProjectSession, runStore: RunStore) {
        self.session = session
        self.runStore = runStore
    }

    private var inputReady: Bool { session.validation.passes(.inputPreparation) }

    public var body: some View {
        Group {
            if let reason = runStore.client.unavailableReason {
                ContentUnavailableView {
                    Label("执行器不可用", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                } actions: {
                    Text("诊断命令：PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            } else {
                runList
            }
        }
        .onAppear { runStore.syncHashes(project: session.project) }
        .sheet(isPresented: $showValidation) {
            NavigationStack {
                ValidationIssueListView(session: session)
                    .navigationTitle("校验")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showValidation = false } } }
            }
            .frame(minWidth: 520, minHeight: 400)
        }
    }

    private var runList: some View {
        List {
            Section {
                HStack {
                    Button("运行 L0 平均估算（当前方案）") {
                        Task { await runStore.submitL0(project: session.project, scenarioID: session.currentScenarioID,
                                                       validator: session.validator, registry: session.registry) }
                    }
                    .disabled(!inputReady)
                    if !inputReady {
                        Button("查看校验问题") { showValidation = true }
                            .font(.caption)
                    }
                    Spacer()
                }
                Text("L0 是集总平均估算：总量与平均值，不是逐点 CFD 结果。修改方案输入后旧结果标记「待重算」，不会被覆盖。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = runStore.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            ForEach(session.project.scenarios, id: \.id) { scenario in
                Section(header: scenarioHeader(scenario)) {
                    let runs = runStore.records(for: scenario.id)
                    if runs.isEmpty {
                        Text("尚无运行记录").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(runs) { record in
                            RunRow(record: record, freshness: record.freshness(relativeTo: runStore.currentHash(for: scenario.id)),
                                   onCancel: { Task { await runStore.cancel(record) } })
                        }
                    }
                }
            }
        }
    }

    private func scenarioHeader(_ scenario: Scenario) -> some View {
        HStack {
            Text(scenario.name)
            if scenario.id == session.currentScenarioID {
                Text("当前").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct RunRow: View {
    let record: RunRecord
    let freshness: ResultFreshness
    let onCancel: () -> Void

    var body: some View {
        DisclosureGroup {
            detail
        } label: {
            HStack(spacing: 8) {
                statusIcon
                Text(String(record.identity.runID.uuidString.prefix(8))).font(.caption.monospaced())
                Text("L0 平均估算").font(.caption2)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 3))
                qualityBadge
                if record.status == .running {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Button("取消", action: onCancel).font(.caption).buttonStyle(.borderless)
                } else {
                    freshnessBadge
                }
                Spacer()
                if let startedAt = record.startedAt {
                    Text(startedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch record.status {
        case .running: Label("进行中", systemImage: "ellipsis.circle").foregroundStyle(.secondary).labelStyle(.iconOnly)
        case .completed: Label("已完成", systemImage: "checkmark.circle").foregroundStyle(.green).labelStyle(.iconOnly)
        case .failed: Label("失败", systemImage: "xmark.circle").foregroundStyle(.red).labelStyle(.iconOnly)
        case .cancelled: Label("已取消", systemImage: "stop.circle").foregroundStyle(.orange).labelStyle(.iconOnly)
        case .interrupted: Label("已中断", systemImage: "questionmark.circle").foregroundStyle(.orange).labelStyle(.iconOnly)
        }
    }

    @ViewBuilder
    private var qualityBadge: some View {
        if let quality = record.result?.quality {
            Text(quality.state == .passed ? "质量通过" : quality.state == .failed ? "质量失败" : "未评估")
                .font(.caption2)
                .foregroundStyle(quality.state == .passed ? .green : quality.state == .failed ? .red : .secondary)
        }
    }

    @ViewBuilder
    private var freshnessBadge: some View {
        switch freshness {
        case .current: Text("最新").font(.caption2).foregroundStyle(.green)
        case .stale: Text("待重算").font(.caption2).foregroundStyle(.orange)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let result = record.result {
                if !result.metrics.isEmpty {
                    MetricTable(metrics: result.metrics)
                }
                if !result.assumptions.isEmpty {
                    Text("假设").font(.caption.bold())
                    ForEach(result.assumptions, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                }
                if let error = result.error {
                    Text("错误（\(error.kind)）：\(error.message)").font(.caption).foregroundStyle(.red)
                }
            }
            if let message = record.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if !record.events.isEmpty {
                Text("事件（最近 \(record.events.count) 条）").font(.caption.bold())
                ForEach(record.events, id: \.sequence) { event in
                    Text("#\(event.sequence) \(event.timestamp) \(event.eventType.rawValue)\(event.stage.map { " · \($0)" } ?? "")")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            Text("运行目录：\(record.runDirectory.path)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

/// Metric rows with units; missing values show their reason, never zero.
public struct MetricTable: View {
    public let metrics: [RunMetric]
    public init(metrics: [RunMetric]) { self.metrics = metrics }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(metrics, id: \.name) { metric in
                HStack {
                    Text(RunsMetricTitles.title(for: metric.name)).font(.caption)
                    Spacer()
                    if metric.isMissing {
                        Text("缺失：\(metric.missingReason ?? "未知原因")").font(.caption).foregroundStyle(.secondary)
                    } else if let flag = metric.boolValue {
                        Text(flag ? "是" : "否").font(.caption)
                    } else if let value = metric.doubleValue {
                        Text("\(value.formatted()) \(metric.unit)").font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }
}
