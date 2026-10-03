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
    /// Viewport tap placement (2026-10-04): the armed choice, or nil. The
    /// toolbar only exists on the RealityKit path (macOS 15 / iOS 18);
    /// the canvas fallback and VoiceOver keep the inspector add-buttons.
    @State private var placementChoice: WorkspaceStore.ViewportPlacementChoice?
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
        var copy: UserFacingCopy

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
                        PendingBadge(copy: copy)
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
        var copy: UserFacingCopy

        var body: some View {
            Text(copy.pendingUpdateBadge)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel(copy.pendingUpdateAccessibility)
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
                PendingBadge(copy: store.copy)
            }
        }
    }

    /// One natural sentence per card instead of the old question-shaped row
    /// (是否按当前房间 / 房间改过了，请重新估算 repeated per number).
    @ViewBuilder
    private func freshnessLine(_ freshness: ResultFreshness?) -> some View {
        switch freshness {
        case .stale:
            Text(store.copy.staleNumbersLine)
                .font(.footnote)
                .foregroundStyle(.orange)
        case .current:
            Text(store.copy.numbersMatchRoom)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case nil:
            Text(store.copy.freshnessTitle(nil))
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
                        Label(destination.title(store.copy), systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                #if os(macOS)
                RoomEditorForm(store: store, page: $inspectorPage, column: .sidebar)
                #else
                LanguagePickerSection(store: store)
                #endif
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            detail
                .navigationTitle(store.selection?.title(store.copy) ?? "SimuNow")
                // Attach to the detail column so macOS actually shows items in the title bar.
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(store.copy.open) {
                            openPackage()
                        }
                        .accessibilityLabel(store.copy.openPackage)
                        Button(store.copy.save) {
                            savePackage()
                        }
                        .disabled(store.project == nil)
                        .accessibilityLabel(store.copy.savePackage)
                        Menu(store.copy.templates) {
                            Button(store.copy.office) {
                                store.loadOfficeTemplate()
                            }
                            .accessibilityLabel(store.copy.createFromOfficeTemplate)
                            Button(store.copy.classroom) {
                                store.loadClassroomTemplate()
                            }
                            .accessibilityLabel(store.copy.createFromClassroomTemplate)
                        }
                        .accessibilityLabel(store.copy.createFromTemplate)
                        // Consult assistant (ADR-022): free-text questions about
                        // how to use the app and what the numbers mean.
                        Button {
                            isChatPresented = true
                        } label: {
                            Label(store.copy.consult, systemImage: "bubble")
                        }
                        .accessibilityLabel(store.copy.consultAccessibility)
                    }
                }
        }
        .environment(\.userFacingCopy, store.copy)
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
                seatSamples: store.lastL2Result?.seatSamples,
                isPlacing: placementChoice != nil,
                onTapSurface: handleViewportTap
            )
            .overlay(alignment: .top) {
                placementToolbar
            }
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
                        seatSamples: store.lastL2Result?.seatSamples,
                        isPlacing: placementChoice != nil,
                        onTapSurface: handleViewportTap
                    )
                    .overlay(alignment: .top) {
                        placementToolbar
                    }
                }
                NavigationLink(store.copy.editRoom) {
                    RoomEditorForm(store: store)
                }
                .padding()
                .accessibilityLabel(store.copy.editRoom)
            }
        }
        #endif
    }

    /// Placement toolbar. macOS 15 / iOS 18 only — the canvas fallback has no
    /// hit-test, so the inspector add-buttons stay that path's only entry.
    /// Re-selecting the armed choice disarms; a refused tap keeps the mode
    /// and shows the reason so the user can try a different spot.
    @ViewBuilder
    private var placementToolbar: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(store.copy.tapToPlaceBar)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)  // the buttons carry the words
                    ForEach(placementChoices, id: \.self) { choice in
                        // Selected/unselected split into branches: one ternary
                        // over two buttonStyle types does not type-check.
                        let choiceTitle = choice.title(for: store.copy)
                        if choice == placementChoice {
                            Button(choiceTitle) {
                                placementChoice = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(store.copy.placementChoiceSelectedAccessibility(choiceTitle))
                            .accessibilityAddTraits(.isSelected)
                        } else {
                            Button(choiceTitle) {
                                placementChoice = choice
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(store.copy.placementChoiceArmAccessibility(choiceTitle))
                        }
                    }
                    if placementChoice != nil {
                        Button(store.copy.cancelPlacement) {
                            placementChoice = nil
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(store.copy.cancelPlacementAccessibility)
                    }
                }
                if placementChoice != nil {
                    Text(store.copy.tapToPlaceHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notice = store.viewportPlacementMessage {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(8)
        }
    }

    private let placementChoices: [WorkspaceStore.ViewportPlacementChoice] = [
        .window, .door, .supplyTerminal, .returnTerminal, .seat,
    ]

    /// One tap, one placement: a successful place disarms the mode; a
    /// refused one keeps it armed so the next tap can try another spot.
    private func handleViewportTap(_ surface: PlacementGeometry.Surface) {
        guard let choice = placementChoice else { return }
        if store.placeFromViewport(choice, on: surface) == nil {
            placementChoice = nil
        }
    }

    @ViewBuilder
    private var runsDetail: some View {
        if store.activeRun == nil && store.lastL1Result == nil && store.lastL2Result == nil {
            VStack(spacing: 16) {
                EmptyStateView(
                    store.copy.destinationTitle("runs"),
                    symbol: "waveform.path",
                    message: store.copy.emptyRunsMessage
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
                    LabeledContent(store.copy.progress, value: store.activeRun.map { store.copy.runStateTitle($0.state) } ?? store.copy.completed)
                    // Short value: the label already says quality check, so the
                    // row no longer reads the long "Passed checks" phrase twice.
                    LabeledContent(store.copy.qualityCheck, value: store.copy.qualityShortTitle((store.lastL2Result ?? store.lastL1Result)?.quality ?? .notEvaluated))
                    // One natural sentence per card; stale numbers carry the
                    // "待更新" badge instead of repeating the long sentence.
                    freshnessLine(store.resultFreshness)
                    if store.isSubmitting {
                        Text(store.copy.estimating)
                            .font(.footnote)
                    }
                    if let message = store.runMessage {
                        Text(message)
                            .font(.footnote)
                    }
                    // Detail page: Form rows read from the leading edge.
                    runActionButtons(alignment: .leading)
                    if store.candidateRuns.isEmpty {
                        Text(store.copy.roomChangedNeedRepin)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.copy.schemesOnComparisonPage(store.candidateRuns.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    // L1 numbers: trailing-closure values carry the badge when
                    // the L1 result predates the current draft.
                    LabeledContent(store.copy.dayEnergy) {
                        staleMarkedValue(store.dayEnergyText(), stale: store.l1Freshness == .stale)
                    }
                    LabeledContent(store.copy.dayCost) {
                        staleMarkedValue(store.dayCostText(), stale: store.l1Freshness == .stale)
                    }
                    LabeledContent(store.copy.metricTitle("seat_t_c_min"), value: store.metricText(named: "seat_t_c_min"))
                    LabeledContent(store.copy.metricTitle("seat_t_c_max"), value: store.metricText(named: "seat_t_c_max"))
                    ForEach(SeatFeasibility.comparisonRows(metrics: store.lastL2Result?.metrics ?? [], copy: store.copy), id: \.label) { row in
                        LabeledContent(row.label, value: row.value)
                    }
                }
                // Gated by showsDetailDisclosures (user request 2026-10-03):
                // the two detail sections are hidden from the default card.
                if Self.showsDetailDisclosures {
                    DisclosureGroup(store.copy.evidenceAndLimits) {
                        LabeledContent(store.copy.metricTitle("q_cool_w")) {
                            staleMarkedValue(store.metricText(named: "q_cool_w"), stale: store.l1Freshness == .stale)
                        }
                        LabeledContent(store.copy.metricTitle("p_elec_w")) {
                            staleMarkedValue(store.metricText(named: "p_elec_w"), stale: store.l1Freshness == .stale)
                        }
                        LabeledContent(store.copy.retrofitQuote, value: store.copy.awaitingQuote)
                        // Worst-seat full evidence: the default line above only
                        // carries one sentence, so gates and the low-speed
                        // reading note are disclosed here.
                        if let worstEvidence = SeatFeasibility.worstSeatEvidenceText(metrics: store.lastL2Result?.metrics ?? [], copy: store.copy) {
                            Text(worstEvidence)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(store.copy.evidenceLimitsBody)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup(store.copy.calculationProcess) {
                        LabeledContent(store.copy.supplyTemperature, value: temperatureText(store.lastBoundary?.supplyTemperatureC, unit: "°C"))
                        LabeledContent(store.copy.setpointTemperature, value: temperatureText(store.lastBoundary?.setpointC, unit: "°C"))
                        LabeledContent(store.copy.outdoorAir, value: flowText(store.lastBoundary?.outdoorAirM3s))
                        LabeledContent(store.copy.recirculatedAir, value: flowText(store.lastBoundary?.recirculatedAirM3s))
                        if let slice = store.lastFieldSlice {
                            LabeledContent(store.copy.seatHeight, value: UserFacingCopy.displayQuantity(slice.zM, unit: "m"))
                            LabeledContent(store.copy.temperatureRange, value: sliceRangeText(slice))
                        } else {
                            Text(store.copy.noPassedTemperatureMap)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let flow = store.lastFlowOverlay, let maxMag = flow.stats.maxMag {
                            LabeledContent(store.copy.airflowRange, value: flowRangeText(flow, maxMag: maxMag))
                            Text(store.copy.flowOverlayCaption)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(store.copy.modelingDisclosure)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if store.lastFieldSlice != nil {
                            Text(store.copy.noFlowOverlayYet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if store.runEvents.isEmpty {
                            Text(store.copy.noProgressYet)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(store.runEvents.enumerated()), id: \.offset) { _, event in
                                let monitor = store.copy.monitorTitle(event.payload?.monitor)
                                Text("\(store.copy.eventTitle(event.eventType.rawValue)) \(monitor)")
                                    .accessibilityLabel(store.copy.progressAccessibility(store.copy.eventTitle(event.eventType.rawValue)))
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
            Button(store.copy.estimateDayEnergy) {
                Task { await store.submitL1() }
            }
            .disabled(!store.canSubmitL1)
            .accessibilityLabel(store.copy.estimateDayEnergy)
            #if os(macOS)
            Button(store.copy.viewSeatTemperatures) {
                Task { await store.submitL2() }
            }
            .disabled(!store.canSubmitL2)
            .accessibilityLabel(store.copy.viewSeatTemperatures)
            #endif
            Button(store.copy.addToComparison) {
                store.pinCurrentAsCandidate()
            }
            .disabled(!store.canPinCandidate)
            .accessibilityLabel(store.copy.addToComparisonAccessibility)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        Button(store.copy.cancel) {
            Task { await store.cancelActiveRun() }
        }
        .disabled(store.activeRun == nil || !store.isSubmitting)
        .accessibilityLabel(store.copy.cancelEstimate)
    }

    /// P4-06 comparison page: pinned candidates share one camera (yaw), one
    /// physical colour range and the same basis; mixed bases are flagged
    /// instead of being shown as a valid comparison.
    @ViewBuilder
    private var scenariosDetail: some View {
        if store.candidateRuns.isEmpty {
            EmptyStateView(
                store.copy.destinationTitle("scenarios"),
                symbol: "square.stack.3d.up",
                message: store.copy.emptyComparisonMessage
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
                        Label(store.copy.sameBasisOK, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let savings = store.comparisonSavingsText {
                            Text(savings)
                                .font(.footnote)
                                .accessibilityLabel(savings)
                        }
                    }
                    if let range = store.comparisonPaletteRange {
                        Text(store.copy.sharedPaletteCaption(UserFacingCopy.displayRange(range.minC, range.maxC, unit: "°C")))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.copy.noSharedPalette)
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
                    Text(store.copy.citedByConclusion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    store.removeCandidate(runID: record.identity.runID)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(store.copy.removeSchemeAccessibility(record.name))
            }
            // Readability pass 2026-10-03: dashboard cells (grey label above,
            // body-weight value below) instead of two LabeledContent squeezed
            // into one HStack where labels and values ran together.
            HStack(spacing: 16) {
                MetricCell(label: store.copy.qualityCheck, value: store.copy.qualityShortTitle(record.quality), copy: store.copy)
                MetricCell(
                    label: store.copy.matchesThisRoom,
                    value: store.candidateFreshness(record) == .stale ? store.copy.needsNewEstimate : store.copy.matchesCurrentRoomShort,
                    copy: store.copy
                )
            }
            HStack(spacing: 16) {
                // L1 numbers: the room may have changed after the L1 estimate,
                // so a stale L1 watt keeps the "needs update" badge, not a repeated sentence.
                MetricCell(
                    label: store.copy.dayEnergy,
                    value: store.candidateL1EnergyText(record),
                    stale: store.candidateL1Freshness(record) == .stale,
                    copy: store.copy
                )
                MetricCell(
                    label: store.copy.dayCost,
                    value: store.candidateL1CostText(record),
                    stale: store.candidateL1Freshness(record) == .stale,
                    copy: store.copy
                )
            }
            HStack(spacing: 16) {
                MetricCell(label: store.copy.metricTitle("seat_t_c_min"), value: candidateMetric(record, "seat_t_c_min"), copy: store.copy)
                MetricCell(label: store.copy.metricTitle("seat_t_c_max"), value: candidateMetric(record, "seat_t_c_max"), copy: store.copy)
            }
            // Full-width cells: the worst-seat sentence wraps naturally instead
            // of being clipped into a side-by-side LabeledContent column.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SeatFeasibility.comparisonRows(metrics: record.metrics, copy: store.copy), id: \.label) { row in
                    MetricCell(label: row.label, value: row.value, copy: store.copy)
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
                DisclosureGroup(store.copy.evidenceAndLimits) {
                    LabeledContent(store.copy.metricTitle("p_elec_w"), value: store.candidateL1PowerText(record))
                    LabeledContent(store.copy.metricTitle("seat_u_mag_max"), value: candidateMetric(record, "seat_u_mag_max"))
                    LabeledContent(store.copy.metricTitle("seat_ppd_max"), value: candidateMetric(record, "seat_ppd_max"))
                    if store.candidateL1Freshness(record) == .stale {
                        Text(store.copy.freshnessTitle(.stale))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let coverageNote = record.metrics.first(where: { $0.name == "seat_pass_ratio" })?.reason {
                        Text(coverageNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let worstEvidence = SeatFeasibility.worstSeatEvidenceText(metrics: record.metrics, copy: store.copy) {
                        Text(worstEvidence)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let infeasible = record.metrics.first(where: { $0.name == "infeasibleReason" }),
                       !infeasible.omitted,
                       let text = infeasible.reason {
                        Text(store.copy.gateTitle(text))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(store.copy.calculationID, value: String(record.identity.runID.uuidString.prefix(8)))
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.copy.comparisonSchemeAccessibility(record.name))
    }

    private func candidateMetric(_ record: CandidateRun, _ name: String) -> String {
        guard let metric = record.metrics.first(where: { $0.name == name }) else {
            return store.copy.noSuchMetric
        }
        if metric.omitted || metric.value == nil {
            return store.copy.unknown
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
            return store.copy.unknown
        }
        return UserFacingCopy.displayRange(minC, maxC, unit: "°C")
    }

    private func flowRangeText(_ flow: FlowOverlay, maxMag: Double) -> String {
        UserFacingCopy.displayRange(flow.stats.minMag ?? 0, maxMag, unit: "m/s")
    }

    private func temperatureText(_ value: Double?, unit: String) -> String {
        guard let value else { return store.copy.none }
        return UserFacingCopy.displayQuantity(value, unit: unit)
    }

    private func flowText(_ value: Double?) -> String {
        guard let value else { return store.copy.none }
        return UserFacingCopy.displayQuantity(value, unit: "m³/s")
    }

    /// Pinned evidence only. No candidates keeps the empty state, and the export
    /// control stays hidden until there is a quality-passed recommendation to cite.
    @ViewBuilder
    private var reportDetail: some View {
        if let evidence = store.reportEvidence {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.copy.displayTariffReference(evidence.tariffReference))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            store.copy.tariffReferenceAccessibility(
                                store.copy.displayTariffReference(evidence.tariffReference)
                            )
                        )
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
                        Button(store.copy.evidenceExportLabel) {
                            Task { await exportEvidencePDF() }
                        }
                        .accessibilityLabel(store.copy.evidenceExportLabel)
                    }
                    #else
                    if store.canExportEvidencePDF {
                        Text(store.copy.pdfMacOnly)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
                .padding()
            }
        } else {
            EmptyStateView(store.copy.destinationTitle("reports"), symbol: "doc.text", message: store.copy.emptyReportMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// ADR-021: the code-computed pair diff on the report page. Input
    /// sentences tell the user what they changed; grouped deltas keep the
    /// energy / comfort / flow dimensions the report has always used.
    private func pairDiffSection(_ diff: CandidatePairDiff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.copy.pairDiffWhatYouDid)
                .font(.caption)
                .foregroundStyle(.secondary)
            if diff.inputChanges.isEmpty {
                Text(store.copy.pairDiffInputsSame)
                    .font(.body)
                    .accessibilityLabel(store.copy.pairDiffInputsSame)
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
                Text(store.copy.pairDiffResultDeltas)
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
        .accessibilityLabel(store.copy.pairDiffSectionAccessibility)
    }

    /// e.g. 座位最凉 24.21 → 24.43 °C（差 +0.22）。Numbers are evidence fields,
    /// formatted exactly as stored so nothing is recomputed here.
    private func pairDeltaText(_ delta: CandidatePairDiff.ResultDelta) -> String {
        let first = delta.first.map(UserFacingCopy.displayNumber) ?? "—"
        let second = delta.second.map(UserFacingCopy.displayNumber) ?? "—"
        return store.copy.pairDeltaLine(
            label: delta.label,
            first: first,
            second: second,
            unit: delta.unit,
            delta: delta.delta
        )
    }

    private func exportEvidencePDF() async {
        guard let url = ProjectLocationPicker.requestEvidencePDFURL(copy: store.copy) else { return }
        do {
            try await store.writeEvidencePDF(to: url)
        } catch EvidencePDFError.notExportable {
            store.reportMessage = store.copy.blockedExportStatus
        } catch EvidencePDFError.generatorUnavailable {
            if store.reportMessage == nil {
                store.reportMessage = store.copy.missingDeepSeekStatus
            }
        } catch EvidencePDFError.unsupportedPlatform {
            store.packageError = store.copy.pdfMacOnlyError
        } catch {
            store.packageError = store.copy.pdfExportFailed
        }
    }

    /// Visible start actions; the title-bar 模板 menu is easy to miss on macOS split views.
    private var emptyProjectPane: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                store.copy.destinationTitle("workspace"),
                symbol: "cube.transparent",
                message: store.copy.emptyRoomMessage
            )
            HStack(spacing: 12) {
                Button(store.copy.officeTemplate) {
                    store.loadOfficeTemplate()
                }
                .accessibilityLabel(store.copy.createFromOfficeTemplate)
                Button(store.copy.classroomTemplate) {
                    store.loadClassroomTemplate()
                }
                .accessibilityLabel(store.copy.createFromClassroomTemplate)
                Button(store.copy.openPackage) {
                    openPackage()
                }
                .accessibilityLabel(store.copy.openPackage)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPackage() {
        #if os(macOS)
        if let url = ProjectLocationPicker.requestOpenURL(copy: store.copy) {
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
        if let url = ProjectLocationPicker.requestSaveURL(copy: store.copy) {
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
