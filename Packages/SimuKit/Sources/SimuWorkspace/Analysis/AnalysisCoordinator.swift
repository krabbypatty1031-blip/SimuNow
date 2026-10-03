import Foundation
import Observation
import SimuCore
import SimuSimulation

private struct ValidatedAnalysisEvent: Sendable {
    let value: LocalAnalysisEvent
    init(_ value: LocalAnalysisEvent) throws {
        try NativeAnalysisCodec().validateEvent(value)
        self.value = value
    }
}

// Internal injection makes cancellation during artifact preparation independently testable.
protocol AnalysisArtifactBuilding: Sendable {
    func make(request: LocalAnalysisRequest, result: LocalAnalysisResult) async throws -> NativeAnalysisArtifact
}
private struct NativeAnalysisArtifactBuilder: AnalysisArtifactBuilding {
    func make(request: LocalAnalysisRequest, result: LocalAnalysisResult) async throws -> NativeAnalysisArtifact {
        let task = Task.detached {
            try Task.checkCancellation()
            let artifact = try NativeArtifactCodec().make(request: request, result: result)
            try Task.checkCancellation()
            return artifact
        }
        return try await withTaskCancellationHandler(
            operation: { try await task.value }, onCancel: { task.cancel() })
    }
}

public struct AnalysisEventCursor: Sendable {
    public let identity: RunIdentity
    public private(set) var lastSequence = -1
    public private(set) var terminated = false
    public init(identity: RunIdentity) { self.identity = identity }
    public mutating func accepts(_ event: LocalAnalysisEvent) -> Bool {
        guard let validated = try? ValidatedAnalysisEvent(event) else { return false }
        return accepts(validated)
    }
    fileprivate mutating func accepts(_ validated: ValidatedAnalysisEvent) -> Bool {
        let event = validated.value
        guard !terminated, event.runID == identity.runID, event.scenarioID == identity.scenarioID,
            event.sequence > lastSequence, event.sequence < 24,
            event.result.map({ $0.identity == identity }) ?? true
        else { return false }
        lastSequence = event.sequence
        terminated = event.stage.isTerminal
        return true
    }
}
public struct AnalysisSessionRecord: Equatable, Sendable {
    public let identity: RunIdentity
    public let method: AnalysisMethod
    public let checks: AnalysisChecksState
    public let residentBytes: Int
}
/// Per-window transient state. Native document bindings remain persisted authority.
@MainActor
@Observable
public final class AnalysisCoordinator {
    public private(set) var activeIdentity: RunIdentity?
    public private(set) var stage: LocalAnalysisStage?
    public private(set) var results: [UUID: LocalAnalysisResult] = [:]
    public private(set) var records: [UUID: AnalysisSessionRecord] = [:]
    public private(set) var persistence: [UUID: AnalysisPersistenceState] = [:]
    public private(set) var failure: AnalysisMissingReason?
    public let maximumResidentResults: Int
    public let maximumResidentBytes: Int
    public let maximumSessionRecords: Int
    @ObservationIgnored private var residentOrder: [UUID] = []
    @ObservationIgnored private var recordOrder: [UUID] = []
    @ObservationIgnored private let client: any LocalAnalysisSubmitting
    @ObservationIgnored private var subscription: Task<Void, Never>?
    @ObservationIgnored private var cursor: AnalysisEventCursor?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var eventValidation: Task<ValidatedAnalysisEvent, Error>?
    @ObservationIgnored private var artifactPreparation: Task<NativeAnalysisArtifact, Error>?
    @ObservationIgnored private let artifactBuilder: any AnalysisArtifactBuilding
    public convenience init(
        client: any LocalAnalysisSubmitting, maximumResidentResults: Int = 12,
        maximumResidentBytes: Int = 24 * 1024 * 1024, maximumSessionRecords: Int = 256
    ) {
        self.init(client: client, maximumResidentResults: maximumResidentResults,
                  maximumResidentBytes: maximumResidentBytes, maximumSessionRecords: maximumSessionRecords,
                  artifactBuilder: NativeAnalysisArtifactBuilder())
    }
    init(client: any LocalAnalysisSubmitting, maximumResidentResults: Int = 12,
         maximumResidentBytes: Int = 24 * 1024 * 1024, maximumSessionRecords: Int = 256,
         artifactBuilder: any AnalysisArtifactBuilding) {
        self.client = client
        self.artifactBuilder = artifactBuilder
        self.maximumResidentResults = max(1, min(12, maximumResidentResults))
        self.maximumResidentBytes = max(1, min(24 * 1024 * 1024, maximumResidentBytes))
        self.maximumSessionRecords = max(12, min(256, maximumSessionRecords))
    }
    public var residentBytes: Int { results.keys.reduce(0) { $0 + (records[$1]?.residentBytes ?? 0) } }
    private func retain(_ result: LocalAnalysisResult, bytes: Int) {
        let id = result.identity.runID
        recordOrder.removeAll { $0 == id }
        recordOrder.append(id)
        records[id] = .init(
            identity: result.identity, method: result.method, checks: result.checks.state,
            residentBytes: bytes)
        residentOrder.removeAll { $0 == id }
        if bytes <= maximumResidentBytes {
            results[id] = result
            residentOrder.append(id)
        } else {
            results.removeValue(forKey: id)
        }
        while residentOrder.count > maximumResidentResults || residentBytes > maximumResidentBytes {
            let candidate = residentOrder.firstIndex { $0 != activeIdentity?.runID } ?? 0
            let old = residentOrder.remove(at: candidate)
            results.removeValue(forKey: old)
        }
        while recordOrder.count > maximumSessionRecords {
            let old = recordOrder.removeFirst()
            records.removeValue(forKey: old)
            persistence.removeValue(forKey: old)
            results.removeValue(forKey: old)
            residentOrder.removeAll { $0 == old }
        }
        // Saved run files and fixed comparison references are never removed by this resident cache.
    }
    deinit {
        subscription?.cancel()
        eventValidation?.cancel()
        artifactPreparation?.cancel()
    }
    /// Persist callback must merge into the latest document binding and recheck its project identity.
    public func start(
        _ request: LocalAnalysisRequest,
        persist: @escaping @MainActor @Sendable (NativeAnalysisArtifact) throws -> Void
    ) {
        stop()
        activeIdentity = request.identity
        cursor = .init(identity: request.identity)
        stage = nil
        failure = nil
        let client = client
        let token = generation
        subscription = Task { [weak self] in
            do {
                let stream = try await client.submit(request)
                for await event in stream {
                    try Task.checkCancellation()
                    await self?.consume(event, request: request, generation: token, persist: persist)
                }
            } catch is CancellationError { await client.cancel(runID: request.identity.runID) } catch {
                self?.submissionFailed(error, identity: request.identity, generation: token)
            }
        }
    }
    public func stop() {
        generation &+= 1
        eventValidation?.cancel()
        eventValidation = nil
        artifactPreparation?.cancel()
        artifactPreparation = nil
        subscription?.cancel()
        subscription = nil
        if let id = activeIdentity?.runID {
            let client = client
            Task { await client.cancel(runID: id) }
        }
        activeIdentity = nil
        cursor = nil
    }
    // Internal observation of the real subscription allows deterministic teardown
    // checks to await an old consumer after a replacement cancels it.
    var eventSubscription: Task<Void, Never>? { subscription }
    /// A different open document must not inherit resident runs, even when its
    /// project UUID and input bytes happen to match the previous instance.
    public func resetSession() {
        stop()
        stage = nil
        failure = nil
        results.removeAll()
        records.removeAll()
        persistence.removeAll()
        residentOrder.removeAll()
        recordOrder.removeAll()
    }
    public func result(scenarioID: UUID, inputHash: String) -> LocalAnalysisResult? {
        residentOrder.reversed().compactMap { results[$0] }.first {
            $0.identity.scenarioID == scenarioID && $0.identity.inputHash == inputHash
                && $0.checks.state == .passed
        }
    }
    public func restore(_ artifacts: [NativeAnalysisArtifact]) {
        for a in artifacts {
            retain(a.result, bytes: a.resultData.count)
            persistence[a.result.identity.runID] = .saved
        }
    }
    private func submissionFailed(_ error: any Error, identity: RunIdentity, generation token: UInt64) {
        guard generation == token, activeIdentity == identity else { return }
        stage = .failed
        failure = .init(code: "submission_failed", fieldPath: "", reason: String(describing: error))
        subscription = nil
    }
    private func consume(
        _ event: LocalAnalysisEvent, request: LocalAnalysisRequest, generation token: UInt64,
        persist: @escaping @MainActor @Sendable (NativeAnalysisArtifact) throws -> Void
    ) async {
        guard generation == token, activeIdentity == request.identity,
              event.runID == request.identity.runID, event.scenarioID == request.identity.scenarioID,
              let currentCursor = cursor, !currentCursor.terminated,
              event.sequence > currentCursor.lastSequence, event.sequence < 24,
              event.result.map({ $0.identity == request.identity }) ?? true else { return }
        // Validate large completed payloads off MainActor. Recheck the cursor only
        // after returning, since stop/start may replace the entire session meanwhile.
        let validation = Task.detached {
            try Task.checkCancellation()
            let value = try ValidatedAnalysisEvent(event)
            if let result = event.result {
                try ThermalEstimateEvidenceValidation.validate(request: request, result: result)
            }
            try Task.checkCancellation()
            return value
        }
        eventValidation = validation
        let validated: ValidatedAnalysisEvent
        do {
            validated = try await withTaskCancellationHandler(
                operation: { try await validation.value }, onCancel: { validation.cancel() })
            try Task.checkCancellation()
        } catch is CancellationError { return } catch {
            guard generation == token, activeIdentity == request.identity, !Task.isCancelled else { return }
            stage = .failed
            failure = .init(code: "invalid_analysis_event", fieldPath: "", reason: String(describing: error))
            cursor = nil
            eventValidation = nil
            subscription?.cancel()
            subscription = nil
            await client.cancel(runID: request.identity.runID)
            return
        }
        guard generation == token, activeIdentity == request.identity,
              cursor?.accepts(validated) == true else { return }
        eventValidation = nil
        stage = event.stage
        failure = event.failure
        if let result = event.result {
            // Conservative structural estimate bounds payloads before the detached artifact serialization completes.
            let bytes: Int
            if case .airflowPreview(let payload) = result.payload {
                bytes =
                    4096 + payload.paths.reduce(0) { $0 + $1.points.count * 160 } + payload.relations.count
                    * 1024
            } else {
                bytes = 64 * 1024
            }
            retain(result, bytes: bytes)
            persistence[result.identity.runID] = .notSaved
            do {
                // CPU serialization and hash checks run off the UI executor.
                let builder = artifactBuilder
                let task = Task { try await builder.make(request: request, result: result) }
                artifactPreparation = task
                let artifact = try await withTaskCancellationHandler(
                    operation: { try await task.value }, onCancel: { task.cancel() })
                try Task.checkCancellation()
                guard generation == token, activeIdentity == request.identity else { return }
                artifactPreparation = nil
                retain(result, bytes: artifact.resultData.count)
                try persist(artifact)
                persistence[result.identity.runID] = .saved
            } catch is CancellationError {
                // A completed result remains session history; closing or replacing
                // its session cancels packaging and cannot append into the next one.
            } catch {
                guard generation == token, activeIdentity == request.identity else { return }
                artifactPreparation = nil
                persistence[result.identity.runID] = .failed(String(describing: error))
            }
        }
        if event.stage.isTerminal, generation == token, activeIdentity == request.identity { subscription = nil }
    }
}
