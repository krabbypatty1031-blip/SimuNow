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
    public var lastResult: SimulationResult?
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

    public var resultFreshness: ResultFreshness? {
        guard let lastResult, let hash = currentInputHash() else { return nil }
        return lastResult.identity.freshness(relativeTo: hash)
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
            lastResult = try await l1Client.loadResult(runID: receipt.identity.runID)
            if let lastResult {
                lastBoundary = try? L2BoundaryMapping.map(draft: project, l1: lastResult)
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
            lastResult = try await l2Client.loadResult(runID: receipt.identity.runID)
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

    /// Pinning requires a finished, current result. A stale result belongs to
    /// an older input and must not be labelled with the current draft.
    public var canPinCandidate: Bool {
        lastResult != nil && resultFreshness == .current && !isSubmitting
    }

    /// Freeze the latest result as a comparison candidate. The basis (people,
    /// hours, setpoints, supply temperature) is copied from the draft at pin
    /// time; only fresh results may pin, so basis and run cannot drift apart.
    public func pinCurrentAsCandidate(named name: String? = nil) {
        guard canPinCandidate, let result = lastResult, let project else { return }
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
            slice: lastFieldSlice,
            basis: basis,
            draft: project
        )
        candidateRuns.append(record)
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
    public func candidateFreshness(_ record: CandidateRun) -> ResultFreshness {
        guard let hash = currentInputHash() else { return .stale }
        return record.identity.inputHash == hash ? .current : .stale
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
            try WorkerTreeStaging.stageEngines(from: enginesRoot, into: runtime)
            applyLocalEngine(
                repositoryRoot: runtime,
                enginesRoot: WorkerTreeStaging.enginesURL(in: runtime)
            )
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

    private func encodeSnapshot(_ draft: ProjectDraft) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(draft)) ?? Data()
    }

    public func metricText(named name: String) -> String {
        guard let metric = lastResult?.metric(named: name), let value = metric.value, !metric.omitted else {
            return lastResult == nil ? "无结果" : "未知"
        }
        return "\(value) \(metric.unit)"
    }

    private func resetRunState() {
        activeRun = nil
        lastResult = nil
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
