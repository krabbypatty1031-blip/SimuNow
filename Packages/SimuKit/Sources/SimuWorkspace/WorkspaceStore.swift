import Foundation
import Observation
import SimuCore
import SimuSimulation

@MainActor
@Observable
public final class WorkspaceStore {
    public var selection: WorkspaceDestination? = .workspace
    public var project: ProjectDraft?
    public var fieldIssues: [FieldIssue] = []
    /// In-memory package location only. Never written into project.json.
    public var packageURL: URL?
    public var packageError: String?
    public var packageWarning: String?
    /// Frozen input snapshot. Editing `project` must not mutate this value.
    public var baseline: ProjectDraft?
    public var baselineScenarioID: UUID?
    public var overridable: [String] = []
    public var lockedAssumptions: [String] = []
    public let simulationClient: any SimulationClient
    public var l1Client: any L1TaskClient
    /// In-app L2 client; unconfigured until the user picks an engine tree.
    public var l2Client: any L2TaskClient
    public var activeRun: RunReceipt?
    /// Last finished L1. L2 submit must not clear this slot.
    public var lastL1Result: SimulationResult?
    /// Last finished L2. L1 submit must not clear this slot.
    public var lastL2Result: SimulationResult?
    /// Latest finished run for older call sites. Prefer the explicit slots.
    /// L2 wins when both exist so a CFD submit does not pretend to be the L1 watts.
    public var lastResult: SimulationResult? { lastL2Result ?? lastL1Result }
    /// Seat-height temperature slice from the latest quality-passed L2 run.
    /// Quality-failed runs produce nil, never a fabricated field.
    public var lastFieldSlice: FieldSlice?
    public var lastBoundary: L2Boundary?
    public var runEvents: [SimulationEvent] = []
    public var runMessage: String?
    public var isSubmitting = false
    public var engineStatus = "未配置本地 EnergyPlus"
    public var pendingRepositoryRoot: URL?
    public var pendingEnginesRoot: URL?

    public init(
        simulationClient: any SimulationClient = UnconfiguredSimulationClient(),
        l1Client: (any L1TaskClient)? = nil,
        l2Client: (any L2TaskClient)? = nil
    ) {
        self.simulationClient = simulationClient
        self.l1Client = l1Client ?? UnconfiguredL1TaskClient()
        self.l2Client = l2Client ?? UnconfiguredL2TaskClient()
        if l1Client != nil {
            engineStatus = self.l1Client.isConfigured ? "已配置代表日 L1" : "未配置本地 EnergyPlus"
        }
    }

    public var canSubmitL1: Bool {
        l1Client.isConfigured && isPhysicalModelComplete && !isSubmitting
    }

    /// L2 needs a complete physical model, a configured engine and no run in flight.
    public var canSubmitL2: Bool {
        l2Client.isConfigured && isPhysicalModelComplete && !isSubmitting
    }

    public func freshness(of result: SimulationResult?) -> ResultFreshness? {
        guard let result, let hash = currentInputHash() else { return nil }
        return result.identity.freshness(relativeTo: hash)
    }

    /// L1 freshness is independent of L2. A stale L1 must not be labelled current.
    public var l1Freshness: ResultFreshness? { freshness(of: lastL1Result) }

    public var l2Freshness: ResultFreshness? { freshness(of: lastL2Result) }

    /// Freshness of the run the pin gate uses: L2 when that slot is filled, otherwise L1.
    public var resultFreshness: ResultFreshness? {
        if lastL2Result != nil { return l2Freshness }
        return l1Freshness
    }

    public func currentInputHash() -> String? {
        guard let project else { return nil }
        return InputSnapshotHash.sha256Hex(encodeSnapshot(project))
    }

    public var isPhysicalModelComplete: Bool {
        project?.hasCompletePhysicalModel == true && fieldIssues.isEmpty
    }

    public func applyRoomSize(x: Double, y: Double, z: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyRoomSize(x: x, y: y, z: z, source: .user)
        project = draft
    }

    public func applyNorthYawDegrees(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyNorthYawDegrees(value, source: .user)
        project = draft
    }

    public func upsertOpening(_ opening: Opening) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.upsertOpening(opening)
        project = draft
    }

    public func removeOpening(id: String) {
        project?.removeOpening(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func applyOpening(
        id: String,
        kind: OpeningKind,
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyOpening(id: id, kind: kind, wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    public func upsertObstacle(_ box: ObstacleBox) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.upsertObstacle(box)
        project = draft
    }

    public func applyObstacle(id: String, origin: Position3D, size: Position3D) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyObstacle(id: id, origin: origin, size: size)
        project = draft
    }

    public func removeObstacle(id: String) {
        project?.removeObstacle(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func upsertSeat(_ seat: Seat) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.upsertSeat(seat)
        project = draft
    }

    public func applySeat(id: String, position: Position3D, source: ParameterSource) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySeat(id: id, position: position, source: source)
        project = draft
    }

    public func removeSeat(id: String) {
        project?.removeSeat(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func installDefaultSplitAC() {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.installDefaultSplitAC()
        project = draft
    }

    public func applySupplyTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySupplyTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    public func applyReturnTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyReturnTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    public func applyOccupantCount(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyOccupantCount(value, source: .user)
        project = draft
    }

    public func applyOccupiedHours(start: String, end: String) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyOccupiedHours(start: start, end: end, source: .user)
        project = draft
    }

    public func applyOutdoorAirM3s(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyOutdoorAirM3s(value, source: .user)
        project = draft
    }

    public func applySupplySpeedMs(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySupplySpeedMs(value, source: .user)
        project = draft
    }

    public func applySupplyAirflowM3s(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySupplyAirflowM3s(value, source: .user)
        project = draft
    }

    public func recomputeSupplyAirflowFromSpeedAndArea() {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.recomputeSupplyAirflowFromSpeedAndArea()
        project = draft
    }

    public func openPackage(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let loaded = try ProjectPackage.load(from: url)
            project = loaded.draft
            fieldIssues = loaded.draft.allFieldIssues()
            packageURL = url.lastPathComponent == ProjectPackage.projectFileName
                ? url.deletingLastPathComponent()
                : url
            packageError = nil
            packageWarning = loaded.warnings.isEmpty ? nil : loaded.warnings.joined(separator: "\n")
            baseline = nil
            baselineScenarioID = nil
            overridable = []
            lockedAssumptions = []
            resetRunState()
        } catch {
            presentPackageError(error)
        }
    }

    public func savePackage(to url: URL) {
        guard let project else {
            packageError = "没有可保存的项目。请先填写房间或打开一个包。"
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try ProjectPackage.save(project, to: url)
            packageURL = url
            packageError = nil
        } catch {
            presentPackageError(error)
        }
    }

    public func savePackage() {
        if let packageURL {
            savePackage(to: packageURL)
        }
    }

    public func loadOfficeTemplate() {
        loadTemplate(named: "office")
    }

    public func loadClassroomTemplate() {
        loadTemplate(named: "classroom")
    }

    private func loadTemplate(named name: String) {
        do {
            apply(try ProjectTemplates.bundled(named: name))
        } catch {
            presentPackageError(error)
        }
    }

    private func apply(_ template: ProjectTemplate) {
        let session = template.instantiate()
        project = session.current
        baseline = session.baseline
        baselineScenarioID = session.baselineScenarioID
        overridable = session.overridable
        lockedAssumptions = session.lockedAssumptions
        fieldIssues = session.current.allFieldIssues()
        packageError = nil
        resetRunState()
    }

    /// Submit an immutable representative-day L1. Does not invent watts if the client fails.
    public func submitL1() async {
        guard let project else {
            runMessage = "没有可提交的项目。"
            return
        }
        guard canSubmitL1 else {
            runMessage = l1Client.isConfigured ? "模型不完整或已有任务在运行。" : "计算引擎尚未配置。请选择工作副本与引擎目录。"
            return
        }
        isSubmitting = true
        runMessage = nil
        let snapshot = encodeSnapshot(project)
        let digest = InputSnapshotHash.sha256Hex(snapshot)
        let request = SimulationRequest(
            identity: RunIdentity(runID: UUID(), scenarioID: project.id, inputHash: digest),
            fidelity: .l1,
            snapshotPath: "input.json",
            snapshotHash: digest,
            scheduleHash: L1Accounting.scheduleHash(of: project)
        )
        activeRun = RunReceipt(identity: request.identity, state: .queued)
        selection = .runs
        do {
            let receipt = try await l1Client.submitL1(request, snapshot: snapshot)
            activeRun = receipt
            runEvents = (try? await l1Client.loadEvents(runID: receipt.identity.runID)) ?? []
            lastL1Result = try await l1Client.loadResult(runID: receipt.identity.runID)
            if let lastL1Result {
                lastBoundary = try? L2BoundaryMapping.map(draft: project, l1: lastL1Result)
            }
            if receipt.state == .failed {
                runMessage = "代表日 L1 失败。冷量未写成 0。"
            }
        } catch {
            runMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    /// Submit an immutable representative-case L2. Quality-failed runs keep
    /// seat metrics omitted and load no slice; nothing is invented.
    public func submitL2() async {
        guard let project else {
            runMessage = "没有可提交的项目。"
            return
        }
        guard canSubmitL2 else {
            runMessage = l2Client.isConfigured ? "模型不完整或已有任务在运行。" : "计算引擎尚未配置。请选择工作副本与含 openfoam.sh 的引擎目录。"
            return
        }
        isSubmitting = true
        runMessage = nil
        let snapshot = encodeSnapshot(project)
        let digest = InputSnapshotHash.sha256Hex(snapshot)
        let request = SimulationRequest(
            identity: RunIdentity(runID: UUID(), scenarioID: project.id, inputHash: digest),
            fidelity: .l2,
            snapshotPath: "input.json",
            snapshotHash: digest
        )
        activeRun = RunReceipt(identity: request.identity, state: .queued)
        selection = .runs
        do {
            let receipt = try await l2Client.submitL2(request, snapshot: snapshot)
            activeRun = receipt
            runEvents = (try? await l2Client.loadEvents(runID: receipt.identity.runID)) ?? []
            lastL2Result = try await l2Client.loadResult(runID: receipt.identity.runID)
            // The slice only exists for a quality-passed field; nil is honest.
            lastFieldSlice = try await l2Client.loadFieldSlice(runID: receipt.identity.runID)
            if receipt.state == .failed {
                runMessage = "代表工况 L2 失败。座位温度未写成 0。"
            }
        } catch {
            runMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    public func cancelActiveRun() async {
        guard let runID = activeRun?.identity.runID else { return }
        // Cancel both channels; the one holding the run terminates it.
        try? await l1Client.cancel(runID: runID)
        try? await l2Client.cancel(runID: runID)
    }

    // MARK: - Candidate comparison (P4-06)

    /// Pinned, frozen scenario results for the comparison page. The record is
    /// a copy; later edits never mutate it.
    public var candidateRuns: [CandidateRun] = []

    /// The run pin freezes: the current L2 when one exists, otherwise the
    /// current finished L1. Pinning never clears the other slot.
    public var pinnableResult: SimulationResult? { lastL2Result ?? lastL1Result }

    /// Pinning requires a finished, current result. A stale result belongs to
    /// an older input and must not be labelled with the current draft.
    public var canPinCandidate: Bool {
        guard let result = pinnableResult else { return false }
        return freshness(of: result) == .current && !isSubmitting
    }

    /// Writes the inspector tariff onto the draft. A nil price stays omitted.
    public func applyElectricityTariff(_ tariff: CostAssumptions) {
        guard var draft = project else { return }
        draft.costAssumptions = tariff
        project = draft
    }

    /// Freeze the latest result as a comparison candidate. The basis (people,
    /// hours, setpoints, supply temperature) is copied from the draft at pin
    /// time; only fresh results may pin, so basis and run cannot drift apart.
    /// Day cost is the L1 power at this moment. No L1 leaves it omitted.
    public func pinCurrentAsCandidate(named name: String? = nil) {
        guard canPinCandidate, let result = pinnableResult, let project else { return }
        let basis = CandidateRun.ComparisonBasis(
            occupantCount: project.occupancy?.occupantCount.value ?? 0,
            occupiedStart: project.occupancy?.schedule?.start
                ?? project.hvac?.schedule?.start ?? "",
            occupiedEnd: project.occupancy?.schedule?.end
                ?? project.hvac?.schedule?.end ?? "",
            setpointC: project.hvac?.setpointC.value ?? 0,
            supplyTemperatureC: project.hvac?.supplyTemperatureC.value ?? 0
        )
        let record = CandidateRun(
            name: name?.isEmpty == false ? name! : "方案 \(candidateRuns.count + 1)",
            identity: result.identity,
            state: result.state,
            quality: result.quality,
            metrics: result.metrics,
            slice: lastL2Result == nil ? nil : lastFieldSlice,
            basis: basis,
            draft: project,
            dayCost: frozenDayCost(project: project),
            l1Identity: lastL1Result?.identity
        )
        candidateRuns.append(record)
    }

    /// Side-by-side difference of two L1 day costs that share currency and tariff.
    /// Hidden when the candidates do not share a basis, or when the delta would
    /// only be a price change. No percent is invented for a mismatched tariff.
    public var comparisonSavingsText: String? {
        guard basisMismatchText == nil else { return nil }
        let priced = candidateRuns.filter { $0.dayCost.cost != nil && $0.dayCost.electricPowerW != nil }
        guard let high = priced.max(by: { ($0.dayCost.cost ?? 0) < ($1.dayCost.cost ?? 0) }),
              let low = priced.min(by: { ($0.dayCost.cost ?? 0) < ($1.dayCost.cost ?? 0) }),
              high.identity.runID != low.identity.runID,
              let currency = high.dayCost.currency,
              high.dayCost.currency == low.dayCost.currency,
              let saved = CostAccounting.savingsHKD(high.dayCost, low.dayCost, basisMismatch: nil),
              saved != 0 else {
            return nil
        }
        return String(format: "代表日电费相差 %.3f %@（两次 L1 电功率之差，不是系数估算）", saved, currency)
    }

    /// Day cost of the stored L1 watts. Hours come from that run's schedule
    /// when it has one, so a later draft edit does not rewrite the old day.
    public func frozenDayCost(project: ProjectDraft) -> RepresentativeDayCost {
        guard let l1 = lastL1Result else {
            return .omitted(reason: "无 L1，代表日电费省略")
        }
        let metric = l1.metric(named: "p_elec_w")
        let watts = metric?.omitted == false ? metric?.value : nil
        let start: String?
        let end: String?
        if let schedule = l1.schedule {
            start = schedule.start
            end = schedule.end
        } else if l1Freshness == .current {
            start = project.occupancy?.schedule?.start ?? project.hvac?.schedule?.start
            end = project.occupancy?.schedule?.end ?? project.hvac?.schedule?.end
        } else {
            start = nil
            end = nil
        }
        return CostAccounting.representativeDay(
            electricPowerW: watts,
            occupiedStart: start,
            occupiedEnd: end,
            tariff: project.costAssumptions
        )
    }

    public var liveDayCost: RepresentativeDayCost {
        guard let project else { return .omitted(reason: "无项目") }
        return frozenDayCost(project: project)
    }

    public func removeCandidate(runID: UUID) {
        candidateRuns.removeAll { $0.identity.runID == runID }
    }

    /// Shared physical colour range across all quality-passed candidate
    /// slices. Candidates never renormalise individually to hide differences.
    /// nil when no candidate has a quality-passed slice with valid stats.
    public var comparisonPaletteRange: (minC: Double, maxC: Double)? {
        let slices = candidateRuns.compactMap(\.slice).filter { $0.quality == "passed" }
        let mins = slices.compactMap(\.stats.minC)
        let maxs = slices.compactMap(\.stats.maxC)
        guard let minC = mins.min(), let maxC = maxs.max() else { return nil }
        return (minC, maxC)
    }

    /// Whether every pinned candidate shares one basis; a false value must
    /// block a side-by-side numeric comparison in the UI.
    public var candidatesShareBasis: Bool {
        basisMismatchText == nil
    }

    /// nil when all candidates share the basis, otherwise the first mismatch
    /// reason. Empty candidate lists trivially share a basis.
    public var basisMismatchText: String? {
        let bases = candidateRuns.map(\.basis)
        guard let first = bases.first else { return nil }
        for other in bases.dropFirst() {
            if let reason = CandidateRun.basisMismatch(first, other) {
                return reason
            }
        }
        return nil
    }

    /// Per-candidate freshness against the live draft: a pinned record whose
    /// input hash matches the current draft is current; anything else is
    /// stale. Freshness is independent of the record's own quality.
    /// This is the pinned run (L2 when that was what pin froze), not the L1 watts.
    public func candidateFreshness(_ record: CandidateRun) -> ResultFreshness {
        guard let hash = currentInputHash() else { return .stale }
        return record.identity.inputHash == hash ? .current : .stale
    }

    /// Freshness of the L1 snapshot frozen on the candidate. Nil when pin had no L1.
    /// A current L2 does not make these watts current.
    public func candidateL1Freshness(_ record: CandidateRun) -> ResultFreshness? {
        guard let identity = record.l1Identity, let hash = currentInputHash() else { return nil }
        return identity.freshness(relativeTo: hash)
    }

    public func candidateL1PowerText(_ record: CandidateRun) -> String {
        annotatedL1(record, text: record.dayCost.powerText, hasValue: record.dayCost.electricPowerW != nil)
    }

    public func candidateL1EnergyText(_ record: CandidateRun) -> String {
        annotatedL1(record, text: record.dayCost.energyText, hasValue: record.dayCost.energyKWh != nil)
    }

    public func candidateL1CostText(_ record: CandidateRun) -> String {
        annotatedL1(record, text: record.dayCost.costText, hasValue: record.dayCost.cost != nil)
    }

    /// Stale L1 watts stay visible on the card but are not described as the current draft.
    private func annotatedL1(_ record: CandidateRun, text: String, hasValue: Bool) -> String {
        guard hasValue, text != "未知" else { return text }
        if candidateL1Freshness(record) == .stale {
            return "\(text)（输入已改，非当前草稿）"
        }
        return text
    }

    #if os(macOS)
    public func restoreEngineBookmarks() {
        if let saved = EngineBookmarkStore.restore() {
            applyLocalEngine(repositoryRoot: saved.repositoryRoot, enginesRoot: saved.enginesRoot)
            return
        }
        if let engines = EngineBookmarkStore.restoreEngines() {
            applyEnginesOnly(engines)
        }
    }

    public func chooseRepositoryRoot() {
        guard let url = ProjectLocationPicker.requestDirectoryURL(
            message: "选择含 Backend/src 的工作副本。App 包内已有 worker 时不必选。",
            prompt: "选择工作副本"
        ) else { return }
        pendingRepositoryRoot = url
        if let engines = pendingEnginesRoot {
            applyEnginesOnly(engines)
        } else {
            engineStatus = "已选工作副本，还需要引擎目录"
        }
    }

    public func chooseEnginesRoot() {
        guard let url = ProjectLocationPicker.requestDirectoryURL(
            message: "选择含 EnergyPlus/energyplus 的引擎目录。只需选一次。",
            prompt: "选择引擎目录"
        ) else { return }
        applyEnginesOnly(url)
    }

    /// Stage worker into the app container, then point L1 at the staged tree plus engines.
    public func applyEnginesOnly(_ enginesRoot: URL, runtimeRoot: URL? = nil) {
        pendingEnginesRoot = enginesRoot
        guard let source = workerSourceRoot() else {
            engineStatus = "已选引擎目录。还需要 App 内 worker 或工作副本。"
            return
        }
        do {
            let runtime = try runtimeRoot ?? WorkerTreeStaging.applicationSupportRuntime()
            try WorkerTreeStaging.stageWorker(from: source, into: runtime)
            _ = enginesRoot.startAccessingSecurityScopedResource()
            // Engines run in place from the user-selected directory via
            // SIMUNOW_ENGINES_ROOT. Copies into the app container get
            // quarantined by macOS and the sandbox cannot exec or remove the
            // mark, so the staged tree carries only Python files.
            applyLocalEngine(repositoryRoot: runtime, enginesRoot: enginesRoot)
            if l1Client.isConfigured {
                EngineBookmarkStore.saveEngines(enginesRoot)
            }
        } catch {
            l1Client = UnconfiguredL1TaskClient()
            l2Client = UnconfiguredL2TaskClient()
            engineStatus = error.localizedDescription
        }
    }

    public func applyLocalEngine(repositoryRoot: URL, enginesRoot: URL) {
        pendingRepositoryRoot = repositoryRoot
        pendingEnginesRoot = enginesRoot
        _ = repositoryRoot.startAccessingSecurityScopedResource()
        _ = enginesRoot.startAccessingSecurityScopedResource()
        let runRoot = (packageURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("runs", isDirectory: true)
        let client = LocalProcessL1Client(
            repositoryRoot: repositoryRoot,
            enginesRoot: enginesRoot,
            runRoot: runRoot
        )
        l1Client = client
        // L2 shares the staged tree; it additionally needs openfoam.sh.
        let l2 = LocalProcessL2Client(
            repositoryRoot: repositoryRoot,
            enginesRoot: enginesRoot,
            runRoot: runRoot
        )
        l2Client = l2
        if client.isConfigured && l2.isConfigured {
            engineStatus = "已配置代表日 L1 与代表工况 L2（不是全年 8760h）"
        } else if client.isConfigured {
            l2Client = UnconfiguredL2TaskClient()
            engineStatus = "已配置 EnergyPlus 代表日 L1，不是 CFD；L2 还需要含 openfoam.sh 的引擎目录"
        } else {
            l1Client = UnconfiguredL1TaskClient()
            l2Client = UnconfiguredL2TaskClient()
            engineStatus = "未配置：运行时须含 worker，引擎目录须含 EnergyPlus/energyplus，且需可用的 python3"
        }
    }

    private func workerSourceRoot() -> URL? {
        if let bundled = WorkerTreeStaging.bundledSource(), WorkerTreeStaging.isWorkerPresent(in: bundled) {
            return bundled
        }
        return pendingRepositoryRoot
    }
    #endif

    /// Physics snapshot. The demo tariff is applied after L1, so it is not
    /// part of the run hash: editing the price must not mark watts stale.
    private func encodeSnapshot(_ draft: ProjectDraft) -> Data {
        var physics = draft
        physics.costAssumptions = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(physics)) ?? Data()
    }

    private static let l1MetricNames: Set<String> = ["q_cool_w", "p_elec_w", "annual_kwh"]

    public func metricText(named name: String) -> String {
        if Self.l1MetricNames.contains(name) {
            return formatMetric(lastL1Result, name: name, markStale: l1Freshness == .stale)
        }
        return formatMetric(lastL2Result, name: name, markStale: false)
    }

    public func dayEnergyText() -> String {
        annotated(liveDayCost.energyText, hasResult: lastL1Result != nil, hasValue: liveDayCost.energyKWh != nil)
    }

    public func dayCostText() -> String {
        annotated(liveDayCost.costText, hasResult: lastL1Result != nil, hasValue: liveDayCost.cost != nil)
    }

    /// Stale L1 numbers stay visible but are not described as the current draft.
    private func annotated(_ text: String, hasResult: Bool, hasValue: Bool) -> String {
        if !hasResult { return "无结果" }
        if !hasValue || text == "未知" { return "未知" }
        if l1Freshness == .stale {
            return "\(text)（输入已改，非当前草稿）"
        }
        return text
    }

    private func formatMetric(_ result: SimulationResult?, name: String, markStale: Bool) -> String {
        guard let metric = result?.metric(named: name), let value = metric.value, !metric.omitted else {
            return result == nil ? "无结果" : "未知"
        }
        let text = "\(value) \(metric.unit)"
        if markStale {
            return "\(text)（输入已改，非当前草稿）"
        }
        return text
    }

    private func resetRunState() {
        activeRun = nil
        lastL1Result = nil
        lastL2Result = nil
        lastFieldSlice = nil
        lastBoundary = nil
        runEvents = []
        runMessage = nil
        isSubmitting = false
    }

    private func presentPackageError(_ error: Error) {
        if let packageError = error as? ProjectPackageError {
            let description = packageError.errorDescription ?? "项目包错误"
            let recovery = packageError.recoverySuggestion ?? ""
            self.packageError = "\(description)。\(recovery)"
        } else {
            packageError = error.localizedDescription
        }
    }
}

public enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case workspace, scenarios, runs, reports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .workspace: "房间工作区"
        case .scenarios: "方案对比"
        case .runs: "计算任务"
        case .reports: "分析报告"
        }
    }

    public var symbol: String {
        switch self {
        case .workspace: "cube.transparent"
        case .scenarios: "square.stack.3d.up"
        case .runs: "waveform.path"
        case .reports: "doc.text"
        }
    }
}
