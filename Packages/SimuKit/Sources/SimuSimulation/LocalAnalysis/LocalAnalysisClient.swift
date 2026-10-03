import Foundation
import SimuCore

public protocol LocalAnalysisSubmitting: Sendable {
    func submit(_ request: LocalAnalysisRequest) async throws -> AsyncStream<LocalAnalysisEvent>
    func cancel(runID: UUID) async
}
public struct LocalAnalysisExecution: Sendable {
    public let payload: LocalAnalysisPayload
    public let checks: AnalysisChecks
    public let missingReasons: [AnalysisMissingReason]
    public init(
        payload: LocalAnalysisPayload, checks: AnalysisChecks, missingReasons: [AnalysisMissingReason] = []
    ) {
        self.payload = payload
        self.checks = checks
        self.missingReasons = missingReasons
    }
}
public protocol LocalAnalysisExecutor: Sendable {
    var method: AnalysisMethod { get }
    func execute(_ request: LocalAnalysisRequest, progress: @escaping @Sendable (Double) async -> Void)
        async throws -> LocalAnalysisExecution
}
public enum LocalAnalysisClientError: Error, Equatable, Sendable {
    case unsupportedMethod, duplicateRunID, queueFull, invalidLimits, shutdown, sessionRunLimit
}
public struct LocalAnalysisClientStatistics: Equatable, Sendable {
    public let running: Int
    public let queued: Int
    public let cacheCount: Int
    public let cacheBytes: Int
}
/// Shared actor performs bookkeeping only. All input hashing and algorithm CPU work is detached.
public actor LocalAnalysisClient: LocalAnalysisSubmitting {
    private struct Job: Sendable {
        let request: LocalAnalysisRequest
        let executor: any LocalAnalysisExecutor
        let continuation: AsyncStream<LocalAnalysisEvent>.Continuation
        var task: Task<Void, Never>?
        var sequence = 0
        var progressCount = 0
        var cancelled = false
    }
    private struct CacheEntry: Sendable {
        let execution: LocalAnalysisExecution
        let sourceRunID: UUID
        let byteCount: Int
        var useOrder: UInt64
    }
    private let registry: ModelRegistry
    private let executors: [String: any LocalAnalysisExecutor]
    private let maximumRunning: Int
    private let maximumQueued: Int
    private let maximumCacheEntries: Int
    private let maximumCacheBytes: Int
    private var jobs: [UUID: Job] = [:]
    private var queue: [UUID] = []
    private var running: Set<UUID> = []
    private var cache: [String: CacheEntry] = [:]
    private var cacheBytes = 0
    private var useOrder: UInt64 = 0
    private var acceptedIDs: Set<UUID> = []
    private var isShutdown = false
    /// Empty executors is a real unavailable state. Test executors never enter production injection.
    public init(
        executors: [any LocalAnalysisExecutor] = [], registry: ModelRegistry = .builtIn,
        maximumRunning: Int = 2, maximumQueued: Int = 8, maximumCacheEntries: Int = 12,
        maximumCacheBytes: Int = 32 * 1024 * 1024
    ) throws {
        guard maximumRunning > 0, maximumRunning <= 2, maximumQueued >= 0, maximumQueued <= 8,
            maximumCacheEntries >= 0, maximumCacheEntries <= 12, maximumCacheBytes >= 0,
            maximumCacheBytes <= 32 * 1024 * 1024
        else { throw LocalAnalysisClientError.invalidLimits }
        var map: [String: any LocalAnalysisExecutor] = [:]
        for e in executors {
            let key = Self.methodKey(e.method)
            guard map[key] == nil else { throw ProjectDataError.duplicateRegistration(key) }
            map[key] = e
        }
        self.registry = registry
        self.executors = map
        self.maximumRunning = maximumRunning
        self.maximumQueued = maximumQueued
        self.maximumCacheEntries = maximumCacheEntries
        self.maximumCacheBytes = maximumCacheBytes
    }
    public static let unavailable: LocalAnalysisClient = {
        do { return try LocalAnalysisClient() } catch {
            preconditionFailure("Invalid built-in analysis client limits: \(error)")
        }
    }()
    deinit {
        for job in jobs.values {
            job.task?.cancel()
            job.continuation.yield(
                .init(
                    runID: job.request.identity.runID, scenarioID: job.request.identity.scenarioID,
                    sequence: job.sequence, stage: .cancelled))
            job.continuation.finish()
        }
    }
    public func submit(_ request: LocalAnalysisRequest) async throws -> AsyncStream<LocalAnalysisEvent> {
        guard !isShutdown else { throw LocalAnalysisClientError.shutdown }
        let id = request.identity.runID
        guard jobs[id] == nil, !acceptedIDs.contains(id) else {
            throw LocalAnalysisClientError.duplicateRunID
        }
        guard let executor = executors[Self.methodKey(request.method)] else {
            throw LocalAnalysisClientError.unsupportedMethod
        }
        guard running.count < maximumRunning || queue.count < maximumQueued else {
            throw LocalAnalysisClientError.queueFull
        }
        guard acceptedIDs.count < 65_536 else { throw LocalAnalysisClientError.sessionRunLimit }
        acceptedIDs.insert(id)
        let stream = AsyncStream<LocalAnalysisEvent>.makeStream()
        stream.continuation.onTermination = { [weak self] _ in Task { await self?.cancel(runID: id) } }
        jobs[id] = Job(request: request, executor: executor, continuation: stream.continuation)
        emit(id, stage: .accepted)
        if running.count < maximumRunning { start(id) } else { queue.append(id) }
        return stream.stream
    }
    public func cancel(runID: UUID) async {
        guard var job = jobs[runID] else { return }
        if job.task == nil {
            queue.removeAll { $0 == runID }
            finish(runID, stage: .cancelled)
        } else {
            job.cancelled = true
            job.task?.cancel()
            jobs[runID] = job
        }
    }
    public func shutdown() async {
        isShutdown = true
        for id in Array(jobs.keys) { await cancel(runID: id) }
        // Release queued streams immediately; cooperative running tasks release when cancellation is observed.
    }
    public func statistics() -> LocalAnalysisClientStatistics {
        .init(running: running.count, queued: queue.count, cacheCount: cache.count, cacheBytes: cacheBytes)
    }
    private static func methodKey(_ method: AnalysisMethod) -> String {
        method.kind.rawValue + "/\(method.methodVersion)"
    }
    private func cacheKey(_ request: LocalAnalysisRequest) -> String {
        "\(request.resolvedInput.snapshot.projectID.uuidString.lowercased())/\(request.identity.scenarioID.uuidString.lowercased())/\(Self.methodKey(request.method))/\(request.computationHash)"
    }
    private func start(_ id: UUID) {
        guard var job = jobs[id] else { return }
        running.insert(id)
        emit(id, stage: .validating)
        // emit mutates sequence; preserve the new sequence in the job installed below.
        job = jobs[id]!
        let request = job.request
        let executor = job.executor
        let registry = registry
        job.task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Task.checkCancellation()
                try AnalysisInputResolver(registry: registry).validate(request)
                try Task.checkCancellation()
                if let cached = await self?.cached(request) {
                    await self?.emit(id, stage: .running)
                    await self?.complete(
                        id, execution: cached.execution, elapsed: 0,
                        provenance: .init(cacheHit: true, sourceRunID: cached.sourceRunID), shouldCache: false
                    )
                    return
                }
                await self?.emit(id, stage: .running)
                let clock = ContinuousClock()
                let began = clock.now
                let execution = try await executor.execute(request) { [weak self] fraction in
                    await self?.reportProgress(id, fraction: fraction)
                }
                try Task.checkCancellation()
                let duration = began.duration(to: clock.now).components
                let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                await self?.complete(
                    id, execution: execution, elapsed: elapsed, provenance: .init(), shouldCache: true)
            } catch is CancellationError { await self?.finish(id, stage: .cancelled) } catch {
                await self?.finish(
                    id, stage: .failed,
                    failure: .init(
                        code: "local_analysis_failed", fieldPath: "", reason: String(describing: error)))
            }
        }
        jobs[id] = job
    }
    private func reportProgress(_ id: UUID, fraction: Double) {
        guard var job = jobs[id], !job.cancelled, fraction.isFinite, (0...1).contains(fraction),
            job.progressCount < 16
        else { return }
        job.progressCount += 1
        jobs[id] = job
        emit(id, stage: .progress, progress: fraction)
    }
    private func emit(
        _ id: UUID, stage: LocalAnalysisStage, progress: Double? = nil,
        result: LocalAnalysisResult? = nil, failure: AnalysisMissingReason? = nil
    ) {
        guard var job = jobs[id] else { return }
        let event = LocalAnalysisEvent(
            runID: id, scenarioID: job.request.identity.scenarioID,
            sequence: job.sequence, stage: stage, progress: progress, result: result, failure: failure)
        job.sequence += 1
        jobs[id] = job
        job.continuation.yield(event)
    }
    private func complete(
        _ id: UUID, execution: LocalAnalysisExecution, elapsed: Double,
        provenance: AnalysisCacheProvenance, shouldCache: Bool
    ) async {
        guard let job = jobs[id] else { return }
        if job.cancelled {
            finish(id, stage: .cancelled)
            return
        }
        emit(id, stage: .checking)
        let result = LocalAnalysisResult(
            identity: job.request.identity, method: job.request.method, checks: execution.checks,
            assumptions: job.request.resolvedInput.adoptedAssumptions,
            missingReasons: execution.missingReasons,
            elapsedSeconds: elapsed, payload: execution.payload, provenance: provenance)
        do {
            if case .airflowPreview(let payload) = result.payload {
                guard payload.paths.count <= job.request.limits.maximumPaths,
                    payload.relations.count <= job.request.limits.maximumTargets,
                    payload.paths.allSatisfy({ $0.points.count <= job.request.limits.maximumSegments + 1 })
                else { throw ProjectDataError.contract("Executor result exceeded request resource limits") }
            }
            let registry = registry
            let request = job.request
            let encoding = Task.detached {
                try Task.checkCancellation()
                try ThermalEstimateEvidenceValidation.validate(request: request, result: result)
                return try NativeAnalysisCodec(registry: registry).encodeResult(result).count
            }
            let byteCount = try await withTaskCancellationHandler(
                operation: { try await encoding.value }, onCancel: { encoding.cancel() })
            guard let current = jobs[id] else { return }
            if current.cancelled {
                finish(id, stage: .cancelled)
                return
            }
            if shouldCache, execution.checks.state == .passed {
                insertCache(current.request, execution: execution, byteCount: byteCount)
            }
            finish(id, stage: .completed, result: result)
        } catch is CancellationError { finish(id, stage: .cancelled) } catch {
            finish(
                id, stage: .failed,
                failure: .init(
                    code: "invalid_executor_result", fieldPath: "", reason: String(describing: error)))
        }
    }
    private func finish(
        _ id: UUID, stage: LocalAnalysisStage, result: LocalAnalysisResult? = nil,
        failure: AnalysisMissingReason? = nil
    ) {
        guard let original = jobs[id] else { return }
        let cancelled = original.cancelled || stage == .cancelled
        emit(
            id, stage: cancelled ? .cancelled : stage, result: cancelled ? nil : result,
            failure: cancelled ? nil : failure)
        jobs.removeValue(forKey: id)?.continuation.finish()
        running.remove(id)
        queue.removeAll { $0 == id }
        if !isShutdown, running.count < maximumRunning, let next = queue.first {
            queue.removeFirst()
            start(next)
        }
    }
    private func cached(_ request: LocalAnalysisRequest) -> CacheEntry? {
        let key = cacheKey(request)
        guard var entry = cache[key] else { return nil }
        useOrder &+= 1
        entry.useOrder = useOrder
        cache[key] = entry
        return entry
    }
    private func insertCache(
        _ request: LocalAnalysisRequest, execution: LocalAnalysisExecution, byteCount: Int
    ) {
        guard maximumCacheEntries > 0, byteCount <= maximumCacheBytes else { return }
        let key = cacheKey(request)
        if let previous = cache.removeValue(forKey: key) { cacheBytes -= previous.byteCount }
        useOrder &+= 1
        cache[key] = .init(
            execution: execution, sourceRunID: request.identity.runID, byteCount: byteCount,
            useOrder: useOrder)
        cacheBytes += byteCount
        while cache.count > maximumCacheEntries || cacheBytes > maximumCacheBytes {
            guard let old = cache.min(by: { $0.value.useOrder < $1.value.useOrder }) else { break }
            cacheBytes -= old.value.byteCount
            cache.removeValue(forKey: old.key)
        }
    }
}
