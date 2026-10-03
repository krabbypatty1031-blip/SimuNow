import SwiftUI
import SimuCore
import SimuSimulation
import SimuDesignSystem

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
                VStack(alignment: .leading, spacing: 16) {
                    ContentUnavailableView {
                        Label("这台设备还不能估算", systemImage: "desktopcomputer")
                    } description: {
                        #if os(macOS)
                        Text("本地计算工具尚未连接，请由项目维护者完成配置。房间信息仍可编辑和保存。")
                        #else
                        Text("请在 Mac 上运行估算。手机和平板上可以布置房间、查看已有结果。")
                        #endif
                    }
                    DisclosureGroup("计算工具配置详情") {
                        Text(reason).font(.caption).textSelection(.enabled)
                        Text("诊断命令：PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: 560)
            } else {
                runList
            }
        }
        .onAppear { runStore.syncHashes(project: session.project) }
        .sheet(isPresented: $showValidation) {
            NavigationStack {
                ValidationIssueListView(session: session)
                    .navigationTitle("待填信息")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showValidation = false } } }
            }
            .frame(idealWidth: 520, minHeight: 400)
        }
    }

    private var runList: some View {
        List {
            Section {
                RoomPageIntro("看看这一天会用多少电", detail: "当前方案：\(session.currentScenario?.name ?? "尚未选择")")
                HStack {
                    Button("估算当前方案") {
                        Task { await runStore.submitL0(project: session.project, scenarioID: session.currentScenarioID,
                                                       validator: session.validator, registry: session.registry) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!inputReady)
                    if !inputReady {
                        Button("查看待填信息") { showValidation = true }
                            .font(.caption)
                    }
                    Spacer()
                }
                Text("快速估算整个房间的平均情况，不提供各座位温度或气流。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = runStore.lastError {
                    Text("这次估算未能开始。").font(.caption).foregroundStyle(.orange)
                    DisclosureGroup("查看原因") { Text(error).font(.caption).textSelection(.enabled) }
                }
            }
            ForEach(session.project.scenarios, id: \.id) { scenario in
                Section(header: scenarioHeader(scenario)) {
                    let runs = runStore.records(for: scenario.id)
                    if runs.isEmpty {
                        Text("尚未估算。选好方案后，点击「估算当前方案」。").font(.caption).foregroundStyle(.secondary)
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
                Text(record.status.title).font(.subheadline)
                Text("房间平均估算").font(.caption2)
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
            Text(quality.state == .passed ? "检查通过" : quality.state == .failed ? "检查未通过" : "尚未检查")
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
                    DisclosureGroup("估算用了哪些假设") {
                        ForEach(result.assumptions, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
                if let error = result.error {
                    Text("错误（\(error.kind)）：\(error.message)").font(.caption).foregroundStyle(.red)
                }
            }
            if let message = record.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            DisclosureGroup("计算编号与技术记录") {
                Text("L0 · \(record.identity.runID.uuidString)").font(.caption2.monospaced()).textSelection(.enabled)
                if !record.events.isEmpty {
                    ForEach(record.events, id: \.sequence) { event in
                        Text("#\(event.sequence) \(event.timestamp) \(event.eventType.rawValue)\(event.stage.map { " · \($0)" } ?? "")")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Text("运行目录：\(record.runDirectory.path)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .font(.caption)
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
                    Text(InputPresentation.metricTitle(metric.name)).font(.caption)
                    Spacer()
                    if metric.isMissing {
                        Text("暂无法估算").font(.caption).foregroundStyle(.secondary)
                    } else if let flag = metric.boolValue {
                        Text(flag ? "是" : "否").font(.caption)
                    } else if let value = metric.doubleValue {
                        Text("\(value.formatted()) \(metric.unit)").font(.caption.monospacedDigit())
                    }
                }
                if metric.isMissing {
                    DisclosureGroup("为什么没有这个结果") {
                        Text(metric.missingReason ?? "计算没有提供这个数值。").font(.caption2).foregroundStyle(.secondary)
                    }.font(.caption2)
                }
            }
        }
    }
}
