import SwiftUI
import UniformTypeIdentifiers
import SimuCore
import SimuDesignSystem
import SimuVisualization

public struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    @State private var isOpeningPackage = false
    @State private var isSavingPackage = false
    /// Shared camera yaw for the comparison page: one lens for all candidates.
    @State private var comparisonYaw: Double = -0.6

    public init(store: WorkspaceStore) {
        self._store = State(initialValue: store)
    }

    public var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(WorkspaceDestination.allCases, selection: $store.selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
                .navigationTitle(store.selection?.title ?? "SimuNow")
                // Attach to the detail column so macOS actually shows items in the title bar.
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("打开") {
                            openPackage()
                        }
                        .accessibilityLabel("打开项目包")
                        Button("保存") {
                            savePackage()
                        }
                        .disabled(store.project == nil)
                        .accessibilityLabel("保存项目包")
                        Menu("模板") {
                            Button("办公室") {
                                store.loadOfficeTemplate()
                            }
                            .accessibilityLabel("从办公室模板创建项目")
                            Button("教室") {
                                store.loadClassroomTemplate()
                            }
                            .accessibilityLabel("从教室模板创建项目")
                        }
                        .accessibilityLabel("从模板创建项目")
                    }
                }
        }
        .fileImporter(
            isPresented: $isOpeningPackage,
            allowedContentTypes: [.folder, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImportedURL(result)
        }
        .fileImporter(
            isPresented: $isSavingPackage,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleSaveFolder(result)
        }
        #if os(macOS)
        .onAppear {
            store.restoreEngineBookmarks()
        }
        .inspector(isPresented: .constant(true)) {
            RoomEditorForm(store: store)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection ?? .workspace {
        case .workspace:
            workspaceDetail
        case .scenarios:
            scenariosDetail
        case .runs:
            runsDetail
        case .reports:
            EmptyStateView("暂无报告", symbol: "doc.text", message: "通过质量检查的结果可用于生成建议报告。")
        }
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        // The viewport draws the project's real geometry or its empty state;
        // run availability stays a separate concern from the drawing.
        #if os(macOS)
        if store.project == nil {
            emptyProjectPane
        } else {
            // The slice only exists for a quality-passed L2 run; nil draws no fake color.
            SimulationViewport(draft: store.project, field: store.lastFieldSlice)
        }
        #else
        NavigationStack {
            VStack(spacing: 0) {
                if store.project == nil {
                    emptyProjectPane
                } else {
                    SimulationViewport(draft: store.project, field: store.lastFieldSlice)
                }
                NavigationLink("编辑房间参数") {
                    RoomEditorForm(store: store)
                }
                .padding()
                .accessibilityLabel("编辑房间参数")
            }
        }
        #endif
    }

    @ViewBuilder
    private var runsDetail: some View {
        if store.activeRun == nil && store.lastL1Result == nil && store.lastL2Result == nil {
            EmptyStateView(
                "暂无计算任务",
                symbol: "waveform.path",
                message: "配置引擎并提交代表日 L1 或代表工况 L2 后，这里显示进度、指标与质量状态。L2 是稳态气流场，不是全年 8760 小时。"
            )
        } else {
            Form {
                Section("任务") {
                    LabeledContent("状态", value: store.activeRun?.state.rawValue ?? "无")
                    LabeledContent("质量", value: (store.lastL2Result ?? store.lastL1Result)?.quality.rawValue ?? "未评价")
                    LabeledContent("新鲜度", value: freshnessText)
                    if store.isSubmitting {
                        Text("正在求解…")
                            .font(.footnote)
                    }
                    if let message = store.runMessage {
                        Text(message)
                            .font(.footnote)
                    }
                    Button("固定为对比候选") {
                        store.pinCurrentAsCandidate()
                    }
                    .disabled(!store.canPinCandidate)
                    .accessibilityLabel("把当前结果固定为对比候选，冻结几何与口径快照")
                    if store.candidateRuns.isEmpty {
                        Text("固定后可在方案对比页并排查看。stale 结果不能固定。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("已固定 \(store.candidateRuns.count) 个候选，见方案对比页。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("代表日指标") {
                    LabeledContent("L1 新鲜度", value: l1FreshnessText)
                    if store.l1Freshness == .stale {
                        Text("下列瓦数属于上次 L1，不是当前草稿。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("制冷量", value: store.metricText(named: "q_cool_w"))
                    LabeledContent("电功率", value: store.metricText(named: "p_elec_w"))
                    LabeledContent("代表日电量", value: store.dayEnergyText())
                    LabeledContent("代表日电费", value: store.dayCostText())
                    LabeledContent("全年电量", value: store.metricText(named: "annual_kwh"))
                    LabeledContent("改造报价", value: "待报价")
                    Text("制冷量不是电功率。代表日电费 = 电功率 ÷ 1000 × 占用小时 × 电价，不是全年电费。改造费待报价，不出回收期。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("L2 座位指标（稳态气流场）") {
                    LabeledContent("座位最低温", value: store.metricText(named: "seat_t_c_min"))
                    LabeledContent("座位最高温", value: store.metricText(named: "seat_t_c_max"))
                    LabeledContent("座位最大风速", value: store.metricText(named: "seat_u_mag_max"))
                    LabeledContent("座位 PMV 最低", value: store.metricText(named: "seat_pmv_min"))
                    LabeledContent("座位 PPD 最高", value: store.metricText(named: "seat_ppd_max"))
                    if let reason = store.lastL2Result?.metric(named: "seat_pmv_min")?.reason {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("座位 PMV 不可评价原因")
                    }
                    Text("座位是采样点不是热源；PMV 是模型判据不是实测满意率；稳态场不表示降温时间。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let slice = store.lastFieldSlice {
                    Section("温度切片") {
                        LabeledContent("高度", value: String(format: "%.2f m", slice.zM))
                        LabeledContent("范围", value: sliceRangeText(slice))
                        LabeledContent("有效格点", value: "\(slice.stats.validCount)")
                        Text("切片只随质量通过的场出现；格值取最近求解单元，显示密度不进座位数字。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("温度切片") {
                        Text("无质量通过的场，暂无切片。未通过的数据不当有效结果。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("L2 边界（未跑 OpenFOAM）") {
                    LabeledContent("送风温度", value: temperatureText(store.lastBoundary?.supplyTemperatureC, unit: "°C"))
                    LabeledContent("设定温度", value: temperatureText(store.lastBoundary?.setpointC, unit: "°C"))
                    LabeledContent("回风口", value: store.lastBoundary?.returnTerminal.id ?? "无")
                    LabeledContent("新风", value: flowText(store.lastBoundary?.outdoorAirM3s))
                    LabeledContent("循环风", value: flowText(store.lastBoundary?.recirculatedAirM3s))
                    Text("送风温度不是设定温度。回风与新风分开。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("进度事件") {
                    if store.runEvents.isEmpty {
                        Text("尚无 JSONL 事件。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.runEvents.enumerated()), id: \.offset) { _, event in
                            Text("\(event.sequence) \(event.eventType.rawValue) \(event.payload?.message ?? event.payload?.monitor ?? "")")
                                .accessibilityLabel("事件 \(event.sequence) \(event.eventType.rawValue)")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var freshnessText: String {
        switch store.resultFreshness {
        case .current: "当前输入"
        case .stale: "输入已改，待重算"
        case nil: "无结果"
        }
    }

    private var l1FreshnessText: String {
        switch store.l1Freshness {
        case .current: "当前输入"
        case .stale: "输入已改，非当前草稿"
        case nil: "无结果"
        }
    }

    /// P4-06 comparison page: pinned candidates share one camera (yaw), one
    /// physical colour range and the same basis; mixed bases are flagged
    /// instead of being shown as a valid comparison.
    @ViewBuilder
    private var scenariosDetail: some View {
        if store.candidateRuns.isEmpty {
            EmptyStateView(
                "暂无对比候选",
                symbol: "square.stack.3d.up",
                message: "提交代表工况 L2 后，在任务页把结果固定为候选；基准加两个候选同口径并排。"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let mismatch = store.basisMismatchText {
                        Label(mismatch, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(mismatch)
                    } else {
                        Label("口径一致：人数、占用时段、设定与送风温度相同，只有几何不同。", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let savings = store.comparisonSavingsText {
                            Text(savings)
                                .font(.footnote)
                                .accessibilityLabel(savings)
                        }
                    }
                    if let range = store.comparisonPaletteRange {
                        Text(String(format: "共用色标 %.1f – %.1f °C（跨候选联合范围，不各自归一化）", range.minC, range.maxC))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("无质量通过的切片，暂无共用色标。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // One camera for every candidate: a shared yaw binding.
                    ForEach(store.candidateRuns) { record in
                        candidateCard(record, sharedYaw: $comparisonYaw)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func candidateCard(_ record: CandidateRun, sharedYaw: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.name)
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    store.removeCandidate(runID: record.identity.runID)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("移除候选 \(record.name)")
            }
            Text("run \(record.identity.runID.uuidString.prefix(8)) · 输入哈希 \(record.identity.inputHash.prefix(8))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Freshness and quality are independent states, shown side by side.
            HStack(spacing: 12) {
                LabeledContent("状态", value: record.state.rawValue)
                LabeledContent("质量", value: record.quality.rawValue)
                LabeledContent("新鲜度", value: store.candidateFreshness(record) == .current ? "当前输入" : "输入已改")
            }
            .font(.footnote)
            HStack(spacing: 12) {
                LabeledContent("L1 电功率", value: store.candidateL1PowerText(record))
                LabeledContent("代表日电量", value: store.candidateL1EnergyText(record))
                LabeledContent("代表日电费", value: store.candidateL1CostText(record))
            }
            .font(.footnote)
            if store.candidateL1Freshness(record) == .stale {
                Text("L1 电功率与代表日电费属于固定时的 L1，输入已改，非当前草稿。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                LabeledContent("座位最低温", value: candidateMetric(record, "seat_t_c_min"))
                LabeledContent("座位最高温", value: candidateMetric(record, "seat_t_c_max"))
                LabeledContent("最大风速", value: candidateMetric(record, "seat_u_mag_max"))
                LabeledContent("PPD 最高", value: candidateMetric(record, "seat_ppd_max"))
            }
            .font(.footnote)
            // Model-gate coverage. Omitted fields read 不可评价, never 0%.
            HStack(spacing: 12) {
                ForEach(SeatFeasibility.comparisonRows(metrics: record.metrics), id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }
            .font(.footnote)
            if let coverageNote = record.metrics.first(where: { $0.name == "seat_pass_ratio" })?.reason {
                Text(coverageNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let infeasible = record.metrics.first(where: { $0.name == "infeasibleReason" }),
               !infeasible.omitted,
               let text = infeasible.reason {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let reason = record.metrics.first(where: { $0.name == "seat_pmv_min" })?.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Frozen geometry snapshot, not the live draft. One shared camera
            // (yaw) and one shared physical palette across all candidates.
            SimulationViewport(
                draft: record.draft,
                field: record.slice,
                sharedPalette: sharedComparisonPalette,
                yaw: sharedYaw
            )
            .frame(height: 220)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("对比候选 \(record.name)")
    }

    private func candidateMetric(_ record: CandidateRun, _ name: String) -> String {
        guard let metric = record.metrics.first(where: { $0.name == name }) else {
            return "无此指标"
        }
        if metric.omitted || metric.value == nil {
            return "未知"
        }
        return "\(metric.value!) \(metric.unit)"
    }

    /// One physical colour range shared by every candidate viewport.
    private var sharedComparisonPalette: SlicePalette? {
        guard let range = store.comparisonPaletteRange else { return nil }
        return SlicePalette(minC: range.minC, maxC: range.maxC)
    }

    /// Same physical range text as the viewport legend; nil stats stay unknown.
    private func sliceRangeText(_ slice: FieldSlice) -> String {
        guard let minC = slice.stats.minC, let maxC = slice.stats.maxC else {
            return "未知"
        }
        return String(format: "%.1f – %.1f °C", minC, maxC)
    }

    private func temperatureText(_ value: Double?, unit: String) -> String {
        guard let value else { return "无" }
        return "\(value) \(unit)"
    }

    private func flowText(_ value: Double?) -> String {
        guard let value else { return "无" }
        return "\(value) m³/s"
    }

    /// Visible start actions; the title-bar 模板 menu is easy to miss on macOS split views.
    private var emptyProjectPane: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                "房间工作区",
                symbol: "cube.transparent",
                message: "还没有项目。从办公室或教室模板开始，或打开已有的 .simunow 包。未配置引擎时不能提交代表日 L1。"
            )
            HStack(spacing: 12) {
                Button("办公室模板") {
                    store.loadOfficeTemplate()
                }
                .accessibilityLabel("从办公室模板创建项目")
                Button("教室模板") {
                    store.loadClassroomTemplate()
                }
                .accessibilityLabel("从教室模板创建项目")
                Button("打开项目包") {
                    openPackage()
                }
                .accessibilityLabel("打开项目包")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPackage() {
        #if os(macOS)
        if let url = ProjectLocationPicker.requestOpenURL() {
            store.openPackage(at: url)
        }
        #else
        isOpeningPackage = true
        #endif
    }

    private func savePackage() {
        if store.packageURL != nil {
            store.savePackage()
            return
        }
        #if os(macOS)
        if let url = ProjectLocationPicker.requestSaveURL() {
            store.savePackage(to: url)
        }
        #else
        isSavingPackage = true
        #endif
    }

    private func handleImportedURL(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            store.openPackage(at: url)
        case .failure(let error):
            store.packageError = error.localizedDescription
        }
    }

    private func handleSaveFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            let name = store.project?.name ?? "Project"
            let url = folder.appendingPathComponent("\(name).\(ProjectPackage.packageExtension)", isDirectory: true)
            store.savePackage(to: url)
        case .failure(let error):
            store.packageError = error.localizedDescription
        }
    }
}
