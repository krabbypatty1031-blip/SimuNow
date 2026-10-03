import SwiftUI
import UniformTypeIdentifiers
import SimuCore
import SimuDesignSystem
import SimuReporting
import SimuVisualization

public struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    @State private var isOpeningPackage = false
    @State private var isSavingPackage = false
    /// Selected room row. The sidebar keeps the list; the inspector shows only this item.
    @State private var inspectorPage = InspectorPage.list
    /// Shared camera yaw for the comparison page: one lens for all candidates.
    @State private var comparisonYaw: Double = -0.6
    /// Consult assistant sheet. One flag for both platforms.
    @State private var isChatPresented = false
    /// Temporarily hidden (user request 2026-10-03): both detail disclosures
    /// cluttered the result cards. One switch gates every occurrence
    /// (results card, candidate card, recommendation card) so they come back
    /// together. The evidence functions stay; only the sections are hidden.
    private static let showsDetailDisclosures = false

    // MARK: Card data cells (readability pass 2026-10-03)
    // The old rows stacked two LabeledContent side by side in one HStack at
    // footnote size: labels and values ran together like a paragraph. These
    // cells put a small grey label above a body-weight value so two of them
    // side by side read as a dashboard, not a paragraph.

    /// Card data cell: small grey label on top, body-weight value below.
    /// Numbers use monospaced digits so values align across cells.
    private struct MetricCell: View {
        let label: String
        let value: String
        /// Marks a number whose room changed after the estimate (L1 watts).
        var stale = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(value)
                        .font(.body)
                        .monospacedDigit()
                    if stale {
                        PendingBadge()
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// Small pill marking one number whose room changed after the estimate.
    /// The long sentence is said once per card; the badge marks each stale
    /// number. Stale numbers stay marked — never presented as the current draft.
    private struct PendingBadge: View {
        var body: some View {
            Text("待更新")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("房间已改，这个数字待重新估算")
        }
    }

    /// Form rows cannot nest a badge inside `LabeledContent("…", value:)`,
    /// so value-form rows use this trailing-closure value instead.
    @ViewBuilder
    private func staleMarkedValue(_ text: String, stale: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .monospacedDigit()
            if stale {
                PendingBadge()
            }
        }
    }

    /// One natural sentence per card instead of the old question-shaped row
    /// (是否按当前房间 / 房间改过了，请重新估算 repeated per number).
    @ViewBuilder
    private func freshnessLine(_ freshness: ResultFreshness?) -> some View {
        switch freshness {
        case .stale:
            Text("房间改过了，上面的数字待重新估算")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .current:
            Text("数字按当前房间")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case nil:
            Text(UserFacingCopy.freshnessTitle(nil))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    public init(store: WorkspaceStore) {
        self._store = State(initialValue: store)
    }

    public var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.selection) {
                Section {
                    ForEach(WorkspaceDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                #if os(macOS)
                RoomEditorForm(store: store, page: $inspectorPage, column: .sidebar)
                #endif
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
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
                        // Consult assistant (ADR-022): free-text questions about
                        // how to use the app and what the numbers mean.
                        Button {
                            isChatPresented = true
                        } label: {
                            Label("咨询", systemImage: "bubble")
                        }
                        .accessibilityLabel("咨询：问怎么用或数字含义")
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
        .sheet(isPresented: $isChatPresented) {
            ChatPanel(store: store)
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
        .inspector(isPresented: Binding(
            get: { inspectorPage != .list },
            set: { isPresented in
                if !isPresented {
                    inspectorPage = .list
                }
            }
        )) {
            RoomEditorForm(store: store, page: $inspectorPage, column: .detail)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 420)
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
            reportDetail
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
            SimulationViewport(
                draft: store.project,
                field: store.lastFieldSlice,
                flow: store.lastFlowOverlay,
                sharedPalette: nil,
                seatSamples: store.lastL2Result?.seatSamples
            )
        }
        #else
        NavigationStack {
            VStack(spacing: 0) {
                if store.project == nil {
                    emptyProjectPane
                } else {
                    SimulationViewport(
                        draft: store.project,
                        field: store.lastFieldSlice,
                        flow: store.lastFlowOverlay,
                        sharedPalette: nil,
                        seatSamples: store.lastL2Result?.seatSamples
                    )
                }
                NavigationLink("编辑房间") {
                    RoomEditorForm(store: store)
                }
                .padding()
                .accessibilityLabel("编辑房间")
            }
        }
        #endif
    }

    @ViewBuilder
    private var runsDetail: some View {
        if store.activeRun == nil && store.lastL1Result == nil && store.lastL2Result == nil {
            VStack(spacing: 16) {
                EmptyStateView(
                    "计算结果",
                    symbol: "waveform.path",
                    message: "布置好房间后，在这里估算这一天用电，并查看座位冷热。"
                )
                VStack(spacing: 8) {
                    // Initial interface: the welcome panel keeps the actions
                    // centered; the detail page switches them to leading.
                    runActionButtons(alignment: .center)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    LabeledContent("进度", value: store.activeRun.map { UserFacingCopy.runStateTitle($0.state) } ?? "已完成")
                    // Short value: the label already says "质量检查", so the
                    // row no longer reads "检查: 已通过检查" (label/value echo).
                    LabeledContent("质量检查", value: UserFacingCopy.qualityShortTitle((store.lastL2Result ?? store.lastL1Result)?.quality ?? .notEvaluated))
                    // One natural sentence per card; stale numbers carry the
                    // "待更新" badge instead of repeating the long sentence.
                    freshnessLine(store.resultFreshness)
                    if store.isSubmitting {
                        Text("正在估算…")
                            .font(.footnote)
                    }
                    if let message = store.runMessage {
                        Text(message)
                            .font(.footnote)
                    }
                    // Detail page: Form rows read from the leading edge.
                    runActionButtons(alignment: .leading)
                    if store.candidateRuns.isEmpty {
                        Text("房间改过之后需要重新估算，才能加入对比。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("已有 \(store.candidateRuns.count) 个方案在对比页。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    // L1 numbers: trailing-closure values carry the badge when
                    // the L1 result predates the current draft.
                    LabeledContent("这一天预计用电") {
                        staleMarkedValue(store.dayEnergyText(), stale: store.l1Freshness == .stale)
                    }
                    LabeledContent("这一天预计费用") {
                        staleMarkedValue(store.dayCostText(), stale: store.l1Freshness == .stale)
                    }
                    LabeledContent(UserFacingCopy.metricTitle("seat_t_c_min"), value: store.metricText(named: "seat_t_c_min"))
                    LabeledContent(UserFacingCopy.metricTitle("seat_t_c_max"), value: store.metricText(named: "seat_t_c_max"))
                    ForEach(SeatFeasibility.comparisonRows(metrics: store.lastL2Result?.metrics ?? []), id: \.label) { row in
                        LabeledContent(row.label, value: row.value)
                    }
                }
                // Gated by showsDetailDisclosures (user request 2026-10-03):
                // the two detail sections are hidden from the default card.
                if Self.showsDetailDisclosures {
                    DisclosureGroup("查看依据与限制") {
                        LabeledContent(UserFacingCopy.metricTitle("q_cool_w")) {
                            staleMarkedValue(store.metricText(named: "q_cool_w"), stale: store.l1Freshness == .stale)
                        }
                        LabeledContent(UserFacingCopy.metricTitle("p_elec_w")) {
                            staleMarkedValue(store.metricText(named: "p_elec_w"), stale: store.l1Freshness == .stale)
                        }
                        LabeledContent("改造报价", value: "待报价")
                        // Worst-seat full evidence: the default line above only
                        // carries one sentence, so gates and the low-speed
                        // reading note are disclosed here.
                        if let worstEvidence = SeatFeasibility.worstSeatEvidenceText(metrics: store.lastL2Result?.metrics ?? []) {
                            Text(worstEvidence)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("制冷需求不是用电功率。这一天费用 = 用电功率 ÷ 1000 × 占用小时 × 电价，不是全年电费。改造待报价，不出回收期。座位是检查点不是发热源。这是稳态，不是开机降温时间。合适的座位不是问卷满意率。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("计算过程") {
                        LabeledContent("出风温度", value: temperatureText(store.lastBoundary?.supplyTemperatureC, unit: "°C"))
                        LabeledContent("设定温度", value: temperatureText(store.lastBoundary?.setpointC, unit: "°C"))
                        LabeledContent("室外新风", value: flowText(store.lastBoundary?.outdoorAirM3s))
                        LabeledContent("循环风", value: flowText(store.lastBoundary?.recirculatedAirM3s))
                        if let slice = store.lastFieldSlice {
                            LabeledContent("坐姿高度", value: UserFacingCopy.displayQuantity(slice.zM, unit: "m"))
                            LabeledContent("温度范围", value: sliceRangeText(slice))
                        } else {
                            Text("还没有通过检查的温度图。未通过的数据不当有效结果。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let flow = store.lastFlowOverlay, let maxMag = flow.stats.maxMag {
                            LabeledContent("气流范围", value: flowRangeText(flow, maxMag: maxMag))
                            Text("箭头和流线来自通过检查的稳态速度场。圆点沿流线循环是示意流向，箭头已放大，不是真实位移，也不是开机降温。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            // The solver's simplifications, disclosed next to the flow they produced:
                            // windows are per-rectangle (P4-07), supply/return stay full-wall bands.
                            Text("窗按实际墙面与宽度进入计算（每扇单独进网格）；送回风仍按整墙高度带进入计算，速度按风量缩放，「送风」「回风」标注指该带，墙上空调外形只标位置。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if store.lastFieldSlice != nil {
                            Text("这次结果还没有气流图。重新估算后才会画箭头和流线。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if store.runEvents.isEmpty {
                            Text("还没有进度。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(store.runEvents.enumerated()), id: \.offset) { _, event in
                                let monitor = UserFacingCopy.monitorTitle(event.payload?.monitor)
                                Text("\(UserFacingCopy.eventTitle(event.eventType.rawValue)) \(monitor)")
                                    .accessibilityLabel("进度 \(UserFacingCopy.eventTitle(event.eventType.rawValue))")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// The three primary actions. `alignment` matches the host surface:
    /// centered in the empty-state welcome (initial interface), leading in
    /// the detail-page Form rows (user request 2026-10-03). 取消 is a
    /// recovery action and keeps its own line below.
    @ViewBuilder
    private func runActionButtons(alignment: Alignment) -> some View {
        HStack {
            Button("估算这一天用电") {
                Task { await store.submitL1() }
            }
            .disabled(!store.canSubmitL1)
            .accessibilityLabel("估算这一天用电")
            #if os(macOS)
            Button("查看座位冷热分布") {
                Task { await store.submitL2() }
            }
            .disabled(!store.canSubmitL2)
            .accessibilityLabel("查看座位冷热分布")
            #endif
            Button("加入对比") {
                store.pinCurrentAsCandidate()
            }
            .disabled(!store.canPinCandidate)
            .accessibilityLabel("把当前结果加入对比")
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        Button("取消") {
            Task { await store.cancelActiveRun() }
        }
        .disabled(store.activeRun == nil || !store.isSubmitting)
        .accessibilityLabel("取消当前估算")
    }

    /// P4-06 comparison page: pinned candidates share one camera (yaw), one
    /// physical colour range and the same basis; mixed bases are flagged
    /// instead of being shown as a valid comparison.
    @ViewBuilder
    private var scenariosDetail: some View {
        if store.candidateRuns.isEmpty {
            EmptyStateView(
                "方案对比",
                symbol: "square.stack.3d.up",
                message: "先完成估算，再把结果加入对比。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let mismatch = store.basisMismatchText {
                        Label(mismatch, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(mismatch)
                    } else {
                        Label("人数、使用时间和设定温度相同，可以并排比较。", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let savings = store.comparisonSavingsText {
                            Text(savings)
                                .font(.footnote)
                                .accessibilityLabel(savings)
                        }
                    }
                    if let range = store.comparisonPaletteRange {
                        Text("共用色标 \(UserFacingCopy.displayRange(range.minC, range.maxC, unit: "°C"))（同一把尺，不各自拉伸）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("还没有通过检查的温度图，暂无共用色标。")
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
                if store.highlightedRunID == record.identity.runID
                    || store.highlightedRunID == record.l1Identity?.runID {
                    Text("结论引用此方案")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    store.removeCandidate(runID: record.identity.runID)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("移除方案 \(record.name)")
            }
            // Readability pass 2026-10-03: dashboard cells (grey label above,
            // body-weight value below) instead of two LabeledContent squeezed
            // into one HStack where labels and values ran together.
            HStack(spacing: 16) {
                MetricCell(label: "质量检查", value: UserFacingCopy.qualityShortTitle(record.quality))
                MetricCell(
                    label: "数字是否按当前房间",
                    value: store.candidateFreshness(record) == .stale ? "待重新估算" : "按当前房间"
                )
            }
            HStack(spacing: 16) {
                // L1 numbers: the room may have changed after the L1 estimate,
                // so a stale L1 watt keeps the "待更新" badge, not a repeated sentence.
                MetricCell(
                    label: "这一天预计用电",
                    value: store.candidateL1EnergyText(record),
                    stale: store.candidateL1Freshness(record) == .stale
                )
                MetricCell(
                    label: "这一天预计费用",
                    value: store.candidateL1CostText(record),
                    stale: store.candidateL1Freshness(record) == .stale
                )
            }
            HStack(spacing: 16) {
                MetricCell(label: UserFacingCopy.metricTitle("seat_t_c_min"), value: candidateMetric(record, "seat_t_c_min"))
                MetricCell(label: UserFacingCopy.metricTitle("seat_t_c_max"), value: candidateMetric(record, "seat_t_c_max"))
            }
            // Full-width cells: the worst-seat sentence wraps naturally instead
            // of being clipped into a side-by-side LabeledContent column.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SeatFeasibility.comparisonRows(metrics: record.metrics), id: \.label) { row in
                    MetricCell(label: row.label, value: row.value)
                }
            }
            SimulationViewport(
                draft: record.draft,
                field: record.slice,
                flow: record.flow,
                sharedPalette: sharedComparisonPalette,
                yaw: sharedYaw,
                seatSamples: record.seatSamples
            )
            .frame(height: 220)
            // Gated by showsDetailDisclosures (user request 2026-10-03):
            // hidden together with the results-card detail sections.
            if Self.showsDetailDisclosures {
                DisclosureGroup("查看依据与限制") {
                    LabeledContent(UserFacingCopy.metricTitle("p_elec_w"), value: store.candidateL1PowerText(record))
                    LabeledContent(UserFacingCopy.metricTitle("seat_u_mag_max"), value: candidateMetric(record, "seat_u_mag_max"))
                    LabeledContent(UserFacingCopy.metricTitle("seat_ppd_max"), value: candidateMetric(record, "seat_ppd_max"))
                    if store.candidateL1Freshness(record) == .stale {
                        Text(UserFacingCopy.freshnessTitle(.stale))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let coverageNote = record.metrics.first(where: { $0.name == "seat_pass_ratio" })?.reason {
                        Text(coverageNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Worst-seat full evidence behind the one-sentence default
                    // line above (gates, numbers, low-speed reading note).
                    if let worstEvidence = SeatFeasibility.worstSeatEvidenceText(metrics: record.metrics) {
                        Text(worstEvidence)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let infeasible = record.metrics.first(where: { $0.name == "infeasibleReason" }),
                       !infeasible.omitted,
                       let text = infeasible.reason {
                        Text(UserFacingCopy.gateTitle(text))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("计算编号", value: String(record.identity.runID.uuidString.prefix(8)))
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("对比方案 \(record.name)")
    }

    private func candidateMetric(_ record: CandidateRun, _ name: String) -> String {
        guard let metric = record.metrics.first(where: { $0.name == name }) else {
            return "无此指标"
        }
        if metric.omitted || metric.value == nil {
            return "未知"
        }
        return UserFacingCopy.displayQuantity(metric.value!, unit: metric.unit)
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
        return UserFacingCopy.displayRange(minC, maxC, unit: "°C")
    }

    private func flowRangeText(_ flow: FlowOverlay, maxMag: Double) -> String {
        UserFacingCopy.displayRange(flow.stats.minMag ?? 0, maxMag, unit: "m/s")
    }

    private func temperatureText(_ value: Double?, unit: String) -> String {
        guard let value else { return "无" }
        return UserFacingCopy.displayQuantity(value, unit: unit)
    }

    private func flowText(_ value: Double?) -> String {
        guard let value else { return "无" }
        return UserFacingCopy.displayQuantity(value, unit: "m³/s")
    }

    /// Pinned evidence only. No candidates keeps the empty state, and the export
    /// control stays hidden until there is a quality-passed recommendation to cite.
    @ViewBuilder
    private var reportDetail: some View {
        if let evidence = store.reportEvidence {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(evidence.tariffReference)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("电价说明 \(evidence.tariffReference)")
                    // ADR-021: the AI narrates the comparison in the PDF; the
                    // page shows the code-computed diff so the numbers stay
                    // readable even without a configured DeepSeek key.
                    if let diff = evidence.pairDiff {
                        pairDiffSection(diff)
                    }
                    if let status = store.reportStatusLine {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(status)
                    }
                    #if os(macOS)
                    if store.canExportEvidencePDF {
                        Button(WorkspaceStore.evidenceExportLabel) {
                            Task { await exportEvidencePDF() }
                        }
                        .accessibilityLabel(WorkspaceStore.evidenceExportLabel)
                    }
                    #else
                    if store.canExportEvidencePDF {
                        Text("对比说明在 Mac 上导出。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
                .padding()
            }
        } else {
            EmptyStateView("导出报告", symbol: "doc.text", message: "加入通过检查的方案后，这里给出结论。没有方案时不能导出。")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// ADR-021: the code-computed pair diff on the report page. Input
    /// sentences tell the user what they changed; grouped deltas keep the
    /// energy / comfort / flow dimensions the report has always used.
    private func pairDiffSection(_ diff: CandidatePairDiff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("你做了什么")
                .font(.caption)
                .foregroundStyle(.secondary)
            if diff.inputChanges.isEmpty {
                Text("两个方案输入相同。")
                    .font(.body)
                    .accessibilityLabel("两个方案输入相同")
            } else {
                ForEach(diff.inputChanges, id: \.field) { change in
                    Text(change.sentence)
                        .font(.body)
                        .accessibilityLabel(change.sentence)
                }
            }
            if let reason = diff.basisMismatchReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(reason)
            }
            if !diff.resultDeltas.isEmpty {
                Text("结果差值（方案一 → 方案二）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(diff.resultDeltas, id: \.field) { delta in
                    Text(pairDeltaText(delta))
                        .font(.body)
                        .accessibilityLabel(pairDeltaText(delta))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("方案对比差值")
    }

    /// e.g. 座位最凉 24.21 → 24.43 °C（差 +0.22）。Numbers are evidence fields,
    /// formatted exactly as stored so nothing is recomputed here.
    private func pairDeltaText(_ delta: CandidatePairDiff.ResultDelta) -> String {
        let first = delta.first.map(UserFacingCopy.displayNumber) ?? "—"
        let second = delta.second.map(UserFacingCopy.displayNumber) ?? "—"
        let unit = delta.unit.isEmpty ? "" : " \(delta.unit)"
        guard let value = delta.delta else {
            return "\(delta.label) \(first) → \(second)\(unit)"
        }
        let sign = value >= 0 ? "+" : ""
        // Bracket delta mirrors the row body's "value unit" spacing.
        return "\(delta.label) \(first) → \(second)\(unit)（差 \(sign)\(UserFacingCopy.displayNumber(value))\(unit)）"
    }

    private func exportEvidencePDF() async {
        guard let url = ProjectLocationPicker.requestEvidencePDFURL() else { return }
        do {
            try await store.writeEvidencePDF(to: url)
        } catch EvidencePDFError.notExportable {
            store.reportMessage = WorkspaceStore.blockedExportStatus
        } catch EvidencePDFError.generatorUnavailable {
            if store.reportMessage == nil {
                store.reportMessage = WorkspaceStore.missingDeepSeekStatus
            }
        } catch EvidencePDFError.unsupportedPlatform {
            store.packageError = "对比说明仅在 Mac 上导出"
        } catch {
            store.packageError = "对比说明导出失败"
        }
    }

    /// Visible start actions; the title-bar 模板 menu is easy to miss on macOS split views.
    private var emptyProjectPane: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                "布置房间",
                symbol: "cube.transparent",
                message: "从一个办公室或教室模板开始，或打开已有房间。"
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
