import Foundation
import Observation
import SimuCore
import SimuReporting
import SimuSimulation
import SimuVisualization

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
    /// Steady velocity glyphs and streamlines from the same quality-passed run.
    public var lastFlowOverlay: FlowOverlay?
    public var lastBoundary: L2Boundary?
    public var runEvents: [SimulationEvent] = []
    public var runMessage: String?
    /// Why the last furniture placement was refused; nil after a legal drop.
    /// Placement rules are user-facing, so the wording is room language.
    public var furniturePlacementMessage: String?
    /// Last refusal, so a language toggle can re-speak the same reason.
    private var lastFurnitureRejection: FurniturePlacement.Rejection?
    public var isSubmitting = false
    public var engineStatus = UserFacingCopy.english.engineStatusNeedFolder
    public var pendingRepositoryRoot: URL?
    public var pendingEnginesRoot: URL?
    /// Folder basename only. Full paths stay out of the inspector.
    public var engineFolderName: String? {
        pendingEnginesRoot?.lastPathComponent
    }
    /// UI language. Tests construct with English; production goes through
    /// makeAppStore, which loads the saved choice (shipped default: Chinese).
    public var language: AppLanguage = .english {
        didSet {
            guard language != oldValue else { return }
            if persistsLanguageChanges {
                language.persist()
            }
            refreshLocalizedStatus()
        }
    }
    public var copy: UserFacingCopy { UserFacingCopy(language: language) }
    /// Tests leave this false so they do not write UserDefaults.
    public var persistsLanguageChanges = false

    public init(
        simulationClient: any SimulationClient = UnconfiguredSimulationClient(),
        l1Client: (any L1TaskClient)? = nil,
        l2Client: (any L2TaskClient)? = nil,
        language: AppLanguage = .english
    ) {
        self.simulationClient = simulationClient
        self.l1Client = l1Client ?? UnconfiguredL1TaskClient()
        self.l2Client = l2Client ?? UnconfiguredL2TaskClient()
        self.language = language
        let copy = UserFacingCopy(language: language)
        engineStatus = copy.engineStatusNeedFolder
        if l1Client != nil {
            engineStatus = self.l1Client.isConfigured ? copy.engineStatusReadyL1 : copy.engineStatusNeedFolder
        }
    }

    /// Production entry: restore the saved language, defaulting to the
    /// shipped default (Chinese, merge decision 2026-10-04).
    public static func makeAppStore() -> WorkspaceStore {
        let store = WorkspaceStore(language: AppLanguage.load())
        store.persistsLanguageChanges = true
        return store
    }

    /// Re-speak live status after the language changes. Frozen run reasons stay as stored.
    private func refreshLocalizedStatus() {
        #if os(macOS)
        if let engines = pendingEnginesRoot {
            let name = engines.lastPathComponent
            if let repo = pendingRepositoryRoot {
                if l1Client.isConfigured && l2Client.isConfigured {
                    engineStatus = copy.engineSelectedReadyBoth(name)
                } else if l1Client.isConfigured {
                    engineStatus = copy.engineSelectedReadyL1(name)
                } else {
                    engineStatus = engineNotReadyMessage(
                        folderName: name,
                        repositoryRoot: repo,
                        enginesRoot: engines
                    )
                }
            } else {
                engineStatus = copy.engineSelectedNeedCopy(name)
            }
            return
        }
        if pendingRepositoryRoot != nil {
            engineStatus = copy.needEngineFolderAfterCopy
            return
        }
        #endif
        engineStatus = l1Client.isConfigured ? copy.engineStatusReadyL1 : copy.engineStatusNeedFolder
        if let rejection = lastFurnitureRejection {
            furniturePlacementMessage = copy.furniturePlacementRejection(rejection)
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
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applyRoomSize(x: x, y: y, z: z, source: .user)
        project = draft
    }

    public func applyNorthYawDegrees(_ value: Double) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applyNorthYawDegrees(value, source: .user)
        project = draft
    }

    /// Zone setpoint. This is not the supply-air temperature.
    public func applyZoneSetpointC(_ value: Double) {
        guard var draft = project, var hvac = draft.hvac else { return }
        hvac.setpointC = PhysicalQuantity(value: value, unit: "C", source: .user)
        fieldIssues = draft.applyHVAC(hvac)
        project = draft
    }

    /// Supply-air temperature. This is not the zone setpoint.
    public func applySupplyTemperatureC(_ value: Double) {
        guard var draft = project, var hvac = draft.hvac else { return }
        hvac.supplyTemperatureC = PhysicalQuantity(value: value, unit: "C", source: .user)
        fieldIssues = draft.applyHVAC(hvac)
        project = draft
    }

    public func upsertOpening(_ opening: Opening) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
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
        source: ParameterSource,
        heatFluxWm2: PhysicalQuantity? = nil
    ) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        // heatFluxWm2 nil = keep the stored flux (the editor has no flux field);
        // non-nil = explicit write (addOpening's template-level 80 W/m2).
        fieldIssues = draft.applyOpening(
            id: id,
            kind: kind,
            wall: wall,
            s0: s0,
            s1: s1,
            z0: z0,
            z1: z1,
            source: source,
            heatFluxWm2: heatFluxWm2
        )
        project = draft
    }

    public func upsertObstacle(_ box: ObstacleBox) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.upsertObstacle(box)
        project = draft
    }

    /// Placement gate (user request 2026-10-04): a furniture box lands only
    /// inside the room, clear of other furniture, seats, the supply/return
    /// bands and windows — the same rule the drag preview runs live, so the
    /// editor and the drop can never disagree. A refusal sets the message
    /// and leaves the draft untouched.
    public func applyObstacle(id: String, origin: Position3D, size: Position3D, kind: FurnitureKind = .desk) {
        guard let current = project else {
            return
        }
        let box = ObstacleBox(id: id, origin: origin, size: size, kind: kind)
        if let rejection = FurniturePlacement.rejection(for: box, in: current, ignoring: id) {
            lastFurnitureRejection = rejection
            furniturePlacementMessage = copy.furniturePlacementRejection(rejection)
            return
        }
        lastFurnitureRejection = nil
        furniturePlacementMessage = nil
        var draft = current
        fieldIssues = draft.applyObstacle(id: id, origin: origin, size: size, kind: kind)
        project = draft
    }

    public func removeObstacle(id: String) {
        project?.removeObstacle(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func upsertSeat(_ seat: Seat) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.upsertSeat(seat)
        project = draft
    }

    public func applySeat(id: String, position: Position3D, source: ParameterSource) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applySeat(id: id, position: position, source: source)
        project = draft
    }

    public func removeSeat(id: String) {
        guard var draft = project else { return }
        fieldIssues = draft.removeSeat(id: id)
        project = draft
    }

    public func installDefaultSplitAC() {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.installDefaultSplitAC()
        project = draft
    }

    public func removeHVAC() {
        project?.removeHVAC()
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func applySupplyTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
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
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applyReturnTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    // MARK: - Viewport tap placement (2026-10-04)

    /// What the viewport can place with one tap. Mirrors the inspector's
    /// add-buttons; the canvas fallback and VoiceOver keep that path.
    public enum ViewportPlacementChoice: Equatable, Sendable {
        case window, door, supplyTerminal, returnTerminal, seat

        /// Room-language label for the placement toolbar; follows the
        /// active UI language (2026-10-04 bilingual pass).
        public func title(for copy: UserFacingCopy) -> String {
            switch self {
            case .window: copy.placeWindowTitle
            case .door: copy.placeDoorTitle
            case .supplyTerminal: copy.placeSupplyTitle
            case .returnTerminal: copy.placeReturnTitle
            case .seat: copy.placeSeatTitle
            }
        }
    }

    /// Why the last viewport placement was refused; nil after a legal place.
    /// Room language, like `furniturePlacementMessage`.
    public var viewportPlacementMessage: String?

    /// Places one item from a viewport tap. nil = placed; non-nil = a
    /// room-language refusal. A refused tap leaves the draft untouched:
    /// overlapping or out-of-wall patches are never written, so the draft
    /// never gains an overlap from placement.
    @discardableResult
    public func placeFromViewport(
        _ choice: ViewportPlacementChoice,
        on surface: PlacementGeometry.Surface
    ) -> String? {
        viewportPlacementMessage = nil
        guard var draft = project, let geometry = draft.geometry else {
            viewportPlacementMessage = copy.placeNeedRoomSizeFirst
            return viewportPlacementMessage
        }
        let sizeXM = geometry.sizeX.value
        let sizeYM = geometry.sizeY.value
        let sizeZM = geometry.sizeZ.value

        switch choice {
        case .window, .door:
            guard case .wall(let wall, let sM, let zM) = surface else {
                viewportPlacementMessage = copy.placeOpeningsNeedWall
                return viewportPlacementMessage
            }
            let patch: WallPatchScene?
            if choice == .window {
                patch = PlacementGeometry.windowPatch(
                    on: wall, sM: sM, zM: zM, sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM
                )
            } else {
                // A door stands on the floor; the tap height is ignored.
                patch = PlacementGeometry.doorPatch(
                    on: wall, sM: sM, sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM
                )
            }
            guard let patch else {
                viewportPlacementMessage = copy.placeWallTooShort(
                    kind: choice == .window ? copy.openingKindTitle(.window) : copy.openingKindTitle(.door)
                )
                return viewportPlacementMessage
            }
            if let conflict = draft.conflictingWallPatch(
                wall: wall, s0: patch.s0M, s1: patch.s1M, z0: patch.z0M, z1: patch.z1M
            ) {
                viewportPlacementMessage = copy.placeOverlaps(what: conflict.displayName(for: copy))
                return viewportPlacementMessage
            }
            let id = ProjectDraft.nextPrefixedID(
                prefix: choice == .window ? "W" : "D",
                existing: geometry.openings.map(\.id)
            )
            // New windows get the same template-level 80 W/m² the inspector
            // add-button writes, so both entry points reach both engines.
            let flux = choice == .window
                ? PhysicalQuantity(value: 80, unit: "W/m2", source: .assumed)
                : nil
            fieldIssues = draft.applyOpening(
                id: id,
                kind: choice == .window ? .window : .door,
                wall: wall,
                s0: patch.s0M,
                s1: patch.s1M,
                z0: patch.z0M,
                z1: patch.z1M,
                source: .user,
                heatFluxWm2: flux
            )
            project = draft
            return nil

        case .supplyTerminal, .returnTerminal:
            guard case .wall(let wall, let sM, let zM) = surface else {
                viewportPlacementMessage = copy.placeTerminalsNeedWall
                return viewportPlacementMessage
            }
            // Placing a terminal on an HVAC-less draft installs the default
            // split AC first (same machine as the inspector button), then
            // moves the tapped terminal onto the tap.
            if draft.hvac == nil {
                _ = draft.installDefaultSplitAC()
            }
            let patch: WallPatchScene?
            if choice == .supplyTerminal {
                patch = PlacementGeometry.supplyPatch(
                    on: wall, sM: sM, zM: zM, sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM
                )
            } else {
                patch = PlacementGeometry.returnPatch(
                    on: wall, sM: sM, zM: zM, sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM
                )
            }
            guard let patch else {
                viewportPlacementMessage = copy.placeWallTooShortForVent
                return viewportPlacementMessage
            }
            // Moving a terminal excludes its own current position, but the
            // other terminal and every opening still block the tap.
            let excluding: WallPatchOwner = choice == .supplyTerminal ? .supply : .returnTerminal
            if let conflict = draft.conflictingWallPatch(
                wall: wall,
                s0: patch.s0M,
                s1: patch.s1M,
                z0: patch.z0M,
                z1: patch.z1M,
                excluding: excluding
            ) {
                viewportPlacementMessage = copy.placeOverlaps(what: conflict.displayName(for: copy))
                return viewportPlacementMessage
            }
            if choice == .supplyTerminal {
                // applySupplyTerminal recomputes flow from the new area;
                // speed stays the independent input.
                fieldIssues = draft.applySupplyTerminal(
                    wall: wall, s0: patch.s0M, s1: patch.s1M, z0: patch.z0M, z1: patch.z1M, source: .user
                )
            } else {
                fieldIssues = draft.applyReturnTerminal(
                    wall: wall, s0: patch.s0M, s1: patch.s1M, z0: patch.z0M, z1: patch.z1M, source: .user
                )
            }
            project = draft
            return nil

        case .seat:
            guard case .floor(let xM, let yM) = surface else {
                viewportPlacementMessage = copy.placeSeatsNeedFloor
                return viewportPlacementMessage
            }
            let position = PlacementGeometry.seatPosition(
                xM: xM, yM: yM, sizeXM: sizeXM, sizeYM: sizeYM
            )
            // The sample point must sit in the fluid domain: not inside a
            // furniture box, not against a wall.
            guard geometry.containsSeat(Seat(id: "probe", position: position, source: .user)) else {
                viewportPlacementMessage = copy.placeSeatSpotBlocked
                return viewportPlacementMessage
            }
            let existing = draft.occupancy?.seats.map(\.id) ?? []
            let id = ProjectDraft.nextPrefixedID(prefix: "S", existing: existing)
            // applySeat: a new seat is a new person; headcount follows seats.
            fieldIssues = draft.applySeat(id: id, position: position, source: .user)
            project = draft
            return nil
        }
    }

    public func applyOccupantCount(_ value: Double) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applyOccupantCount(value, source: .user)
        project = draft
    }

    public func applyOccupiedHours(start: String, end: String) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applyOccupiedHours(start: start, end: end, source: .user)
        project = draft
    }

    public func applyOutdoorAirM3s(_ value: Double) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applyOutdoorAirM3s(value, source: .user)
        project = draft
    }

    public func applySupplySpeedMs(_ value: Double) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applySupplySpeedMs(value, source: .user)
        project = draft
    }

    public func applySupplyAirflowM3s(_ value: Double) {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
        fieldIssues = draft.applySupplyAirflowM3s(value, source: .user)
        project = draft
    }

    public func recomputeSupplyAirflowFromSpeedAndArea() {
        var draft = project ?? ProjectDraft(name: copy.untitledRoom)
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
            packageError = copy.nothingToSave
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
            runMessage = copy.noRoomYet
            return
        }
        guard canSubmitL1 else {
            runMessage = l1Client.isConfigured ? copy.roomIncompleteOrBusy : copy.engineStatusNeedFolder
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
                runMessage = copy.l1FailedNoZero
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
            runMessage = copy.noRoomYet
            return
        }
        guard canSubmitL2 else {
            runMessage = l2Client.isConfigured ? copy.roomIncompleteOrBusy : copy.cannotViewSeatsNeedFolder
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
            lastFlowOverlay = try await l2Client.loadFlowOverlay(runID: receipt.identity.runID)
            if receipt.state == .failed {
                runMessage = copy.l2FailedNoZero
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

    /// Report built from pinned runs only. Nil when nothing is pinned, so the
    /// page stays an empty state instead of quoting the live draft.
    public var highlightedRunID: UUID?
    /// Injected in tests. Production uses DeepSeek when a key is present.
    public var reportGenerator: (any ReportGenerator)?
    /// Tests turn this off so export never hits the network.
    public var allowEnvironmentGenerator = true
    /// Last export or block note shown on the report page and inspector.
    public var reportMessage: String?

    /// Button copy stays this phrase. A missing API key must not rename it to 「生成报告」.
    public static var evidenceExportLabel: String { UserFacingCopy.english.evidenceExportLabel }
    public static var missingDeepSeekStatus: String { UserFacingCopy.english.missingDeepSeekStatus }
    public static var generateFailedStatus: String { UserFacingCopy.english.generateFailedStatus }
    public static var exportedStatus: String { UserFacingCopy.english.exportedStatus }
    public static var blockedExportStatus: String { UserFacingCopy.english.blockedExportStatus }

    /// DeepSeek writes the readable body from the frozen evidence pack.
    /// Missing key or a failed request does not invent a stand-in PDF.
    public func writeEvidencePDF(to url: URL) async throws {
        guard let evidence = reportEvidence, evidence.isComparisonReportable else {
            reportMessage = copy.blockedExportStatus
            throw EvidencePDFError.notExportable
        }
        guard let generator = resolvedReportGenerator() else {
            reportMessage = copy.missingDeepSeekStatus
            throw EvidencePDFError.generatorUnavailable
        }
        guard let report = await generator.generate(evidence) else {
            reportMessage = copy.generateFailedStatus
            throw EvidencePDFError.generatorUnavailable
        }
        // ADR-024: WebKit layout is async; hop to the MainActor render inside.
        try await EvidencePDFAssembler.write(evidence: evidence, report: report, copy: copy, to: url)
        reportMessage = copy.exportedStatus
    }

    public var reportEvidence: ReportEvidence? {
        guard !candidateRuns.isEmpty else { return nil }
        return ReportEvidence.build(from: candidateRuns, copy: copy)
    }

    /// Quality-failed packs can be read. Export also needs DeepSeek.
    public var canExportEvidencePDF: Bool {
        reportEvidence?.isComparisonReportable == true && isReportGeneratorConfigured
    }

    public var isReportGeneratorConfigured: Bool {
        if reportGenerator != nil { return true }
        guard allowEnvironmentGenerator else { return false }
        return DeepSeekReportClient.configuredFromEnvironment(language: language) != nil
    }

    /// Empty pin list stays an empty state. Failed-only packs explain why export is hidden.
    public var reportStatusLine: String? {
        guard let evidence = reportEvidence else { return nil }
        if !evidence.isComparisonReportable {
            return reportMessage ?? copy.blockedExportStatus
        }
        if !isReportGeneratorConfigured {
            return reportMessage ?? copy.missingDeepSeekStatus
        }
        return reportMessage
    }

    private func resolvedReportGenerator() -> (any ReportGenerator)? {
        if let reportGenerator { return reportGenerator }
        guard allowEnvironmentGenerator else { return nil }
        return DeepSeekReportClient.configuredFromEnvironment(language: language)
    }

    /// Card run IDs jump back to the comparison page, which still shows the frozen record.
    public func focusCitedRun(_ runID: UUID) {
        highlightedRunID = runID
        selection = .scenarios
    }

    // MARK: - Consult assistant (ADR-022)

    /// The whole consult conversation, newest last. Rendered by `ChatPanel`.
    public var chatTurns: [ChatTurn] = []
    /// Injected in tests. Production uses DeepSeek when a key is present.
    public var chatAssistant: (any ChatAssistant)?
    /// Tests turn this off so consult never touches the network.
    public var allowEnvironmentChatAssistant = true
    /// True while a reply is in flight, so the panel shows a thinking note.
    public var isChatThinking = false
    /// The half-typed reply the panel renders during the typewriter reveal.
    /// Non-nil means "an assistant reply is arriving, character by character".
    public var chatStreamingText: String?
    /// Milliseconds between revealed characters. 0 skips the animation
    /// (tests set this so the flow completes in one runloop tick).
    public var chatTypingIntervalMs = 14
    /// Fixed replies so the user is never left without a spoken answer.
    public static var chatMissingKeyText: String { UserFacingCopy.english.chatMissingKeyText }
    public static var chatFailedText: String { UserFacingCopy.english.chatFailedText }
    public static var chatEmptyText: String { UserFacingCopy.english.chatEmptyText }

    public var isChatAssistantConfigured: Bool {
        if chatAssistant != nil { return true }
        guard allowEnvironmentChatAssistant else { return false }
        return DeepSeekChatClient.configuredFromEnvironment(language: language) != nil
    }

    private func resolvedChatAssistant() -> (any ChatAssistant)? {
        if let chatAssistant { return chatAssistant }
        guard allowEnvironmentChatAssistant else { return nil }
        return DeepSeekChatClient.configuredFromEnvironment(language: language)
    }

    /// One consult round: freeze the user's words, snapshot the context,
    /// ask, screen, then reveal the answer character by character the way
    /// a live assistant types. A failed ask still gets a spoken fallback so
    /// the conversation never ends in silence.
    public func sendChat(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatTurns.append(ChatTurn(role: .user, text: trimmed))
        let context = ChatContext(
            draftSummary: ChatContextBuilder.draftSummary(for: project, copy: copy),
            evidence: reportEvidence
        )
        guard let assistant = resolvedChatAssistant() else {
            chatStreamingText = nil
            chatTurns.append(ChatTurn(role: .assistant, text: copy.chatMissingKeyText))
            return
        }
        isChatThinking = true
        chatStreamingText = ""
        let reply = await assistant.respond(to: chatTurns, context: context)
        // Screen locally too: a stubbed or future client must not bypass
        // the same free-text guard the DeepSeek client applies.
        let screened = reply.map { ChatGuard.screen($0, history: chatTurns, context: context, language: language) }
        let final = (screened ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? copy.chatFailedText
        // Typewriter reveal: the reply appears character by character, the
        // way a live assistant types. `clearChat` mid-reveal empties the
        // streaming text; the guard on each tick stops the loop then.
        for character in final {
            guard chatStreamingText != nil else { return }
            chatStreamingText = (chatStreamingText ?? "") + String(character)
            if chatTypingIntervalMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(chatTypingIntervalMs) * 1_000_000)
            }
        }
        // A breath on the finished line before it becomes a spoken turn.
        if chatTypingIntervalMs > 0 {
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        guard chatStreamingText != nil else { return }
        chatStreamingText = nil
        isChatThinking = false
        // History keeps the model's own words only (ADR-022 live hand-test
        // 2026-10-04): the appended caution note must not ride back into the
        // history the next round's model reads, or the model starts copying
        // the note style into its own replies. The note becomes display
        // metadata on the turn instead.
        // The client screens with the panel's language, so the strip must
        // compare the same wording — AppLanguage.default is NOT assumed here.
        let note = ChatGuard.cautionNote(for: copy.language)
        let hasCaution = final.hasSuffix(note)
        let body = hasCaution
            ? String(final.dropLast(note.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : final
        chatTurns.append(
            ChatTurn(role: .assistant, text: body.isEmpty ? final : body, hasCautionNote: hasCaution)
        )
    }

    /// Start over without losing the project. Kept explicit: consult logs
    /// are never written anywhere, so clearing is the whole story. Mid-reveal
    /// this also stops the typewriter (the reveal loop watches for nil).
    public func clearChat() {
        chatTurns = []
        chatStreamingText = nil
        isChatThinking = false
    }

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
            name: name?.isEmpty == false ? name! : copy.defaultSchemeName(candidateRuns.count + 1),
            identity: result.identity,
            state: result.state,
            quality: result.quality,
            metrics: result.metrics,
            slice: lastL2Result == nil ? nil : lastFieldSlice,
            flow: lastL2Result == nil ? nil : lastFlowOverlay,
            seatSamples: lastL2Result?.seatSamples,
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
        return copy.comparisonSavings(UserFacingCopy.displayNumber(saved), currency: currency)
    }

    /// Day cost of the stored L1 watts. Hours come from that run's schedule
    /// when it has one, so a later draft edit does not rewrite the old day.
    public func frozenDayCost(project: ProjectDraft) -> RepresentativeDayCost {
        guard let l1 = lastL1Result else {
            return .omitted(reason: copy.omitDayCostNoEnergyResult)
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
        guard let project else { return .omitted(reason: copy.omitDayCostNoProject) }
        return frozenDayCost(project: project)
    }

    public func removeCandidate(runID: UUID) {
        candidateRuns.removeAll { $0.identity.runID == runID }
    }

    /// Shared physical colour range: joint min/max of quality-passed slices.
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
            if let reason = CandidateRun.basisMismatch(first, other, copy: copy) {
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
    /// The stale marker moved to the view layer (a small "待更新" badge next to
    /// the number) so the long sentence is said once per card, not per number.
    /// The guard stays: `candidateL1Freshness` is the truth the badge reads.
    private func annotatedL1(_ record: CandidateRun, text: String, hasValue: Bool) -> String {
        guard hasValue, text != "未知", text != UserFacingCopy.english.unknown else {
            return (text == "未知" || text == UserFacingCopy.english.unknown) ? copy.unknown : text
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
            message: copy.chooseProgramCopyPanelMessage,
            prompt: copy.chooseProgramCopyPrompt
        ) else {
            engineStatus = copy.cancelledProgramCopy
            return
        }
        pendingRepositoryRoot = url
        if let engines = pendingEnginesRoot {
            applyEnginesOnly(engines)
        } else {
            engineStatus = copy.needEngineFolderAfterCopy
        }
    }

    public func chooseEnginesRoot() {
        guard let url = ProjectLocationPicker.requestDirectoryURL(
            message: copy.chooseEngineFolderPanelMessage,
            prompt: copy.chooseEngineFolderPrompt
        ) else {
            // Cancel used to return with the idle sentence unchanged.
            engineStatus = copy.cancelledFolder
            return
        }
        applyEnginesOnly(url)
    }

    /// Stage worker into the app container, then point L1 at the staged tree plus engines.
    public func applyEnginesOnly(_ enginesRoot: URL, runtimeRoot: URL? = nil) {
        pendingEnginesRoot = enginesRoot
        let name = enginesRoot.lastPathComponent
        guard let source = workerSourceRoot() else {
            engineStatus = copy.engineSelectedNeedCopy(name)
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
            // Staging errors can mention filenames; never echo a home path.
            engineStatus = copy.engineSelectedCopyFailed(name)
        }
    }

    public func applyLocalEngine(repositoryRoot: URL, enginesRoot: URL) {
        pendingRepositoryRoot = repositoryRoot
        pendingEnginesRoot = enginesRoot
        _ = repositoryRoot.startAccessingSecurityScopedResource()
        _ = enginesRoot.startAccessingSecurityScopedResource()
        let runRoot: URL
        if let packageURL {
            runRoot = packageURL.appendingPathComponent("runs", isDirectory: true)
        } else if let support = try? WorkerTreeStaging.applicationSupportRuns() {
            runRoot = support
        } else {
            runRoot = FileManager.default.temporaryDirectory.appendingPathComponent("runs", isDirectory: true)
        }
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
        let name = enginesRoot.lastPathComponent
        if client.isConfigured && l2.isConfigured {
            engineStatus = copy.engineSelectedReadyBoth(name)
        } else if client.isConfigured {
            l2Client = UnconfiguredL2TaskClient()
            engineStatus = copy.engineSelectedReadyL1(name)
        } else {
            l1Client = UnconfiguredL1TaskClient()
            l2Client = UnconfiguredL2TaskClient()
            engineStatus = engineNotReadyMessage(
                folderName: name,
                repositoryRoot: repositoryRoot,
                enginesRoot: enginesRoot
            )
        }
    }

    /// Say what the picked folder is missing. Do not repeat the idle prompt.
    private func engineNotReadyMessage(
        folderName: String,
        repositoryRoot: URL,
        enginesRoot: URL
    ) -> String {
        let energyPlus = LocalEngineProbe.energyPlusURL(in: enginesRoot)
        let worker = LocalEngineProbe.workerURL(in: repositoryRoot)
        if !FileManager.default.fileExists(atPath: energyPlus.path) {
            return copy.engineFolderMissingEnergy(folderName)
        }
        if !LocalEngineProbe.hasExecuteBit(at: energyPlus.path) {
            return copy.engineFolderEnergyNotRunnable(folderName)
        }
        if !FileManager.default.fileExists(atPath: worker.path) {
            return copy.engineSelectedNeedCopy(folderName)
        }
        return copy.engineFolderCannotEstimate(folderName)
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
            return formatMetric(lastL1Result, name: name)
        }
        return formatMetric(lastL2Result, name: name)
    }

    public func dayEnergyText() -> String {
        annotated(liveDayCost.energyText, hasResult: lastL1Result != nil, hasValue: liveDayCost.energyKWh != nil)
    }

    public func dayCostText() -> String {
        annotated(liveDayCost.costText, hasResult: lastL1Result != nil, hasValue: liveDayCost.cost != nil)
    }

    /// Stale L1 numbers stay visible but are not described as the current draft.
    /// The stale marker moved to the view layer (a small "待更新" badge next to
    /// the number) so the long sentence is said once per card, not per number.
    /// The guard stays: `l1Freshness` is the truth the badge reads.
    private func annotated(_ text: String, hasResult: Bool, hasValue: Bool) -> String {
        if !hasResult { return copy.noResult }
        if !hasValue || text == "未知" || text == UserFacingCopy.english.unknown { return copy.unknown }
        return text
    }

    /// Pure number text. The stale marker lives in the view (a "待更新" badge);
    /// `l1Freshness` stays the independent truth the badge reads.
    private func formatMetric(_ result: SimulationResult?, name: String) -> String {
        guard let metric = result?.metric(named: name), let value = metric.value, !metric.omitted else {
            return result == nil ? copy.noResult : copy.unknown
        }
        return UserFacingCopy.displayQuantity(value, unit: metric.unit)
    }

    private func resetRunState() {
        activeRun = nil
        lastL1Result = nil
        lastL2Result = nil
        lastFieldSlice = nil
        lastFlowOverlay = nil
        lastBoundary = nil
        runEvents = []
        runMessage = nil
        isSubmitting = false
    }

    private func presentPackageError(_ error: Error) {
        if let packageError = error as? ProjectPackageError {
            self.packageError = copy.packageErrorText(packageError)
        } else {
            packageError = error.localizedDescription
        }
    }
}

public enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    // Case order is the sidebar order: 布置房间 → 计算结果 → 方案对比 → 导出报告
    // (estimate before comparing estimates; 2026-10-04 swap of runs and scenarios).
    case workspace, runs, scenarios, reports

    public var id: String { rawValue }

    public var title: String { title(UserFacingCopy.english) }

    public func title(_ copy: UserFacingCopy) -> String {
        copy.destinationTitle(rawValue)
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
