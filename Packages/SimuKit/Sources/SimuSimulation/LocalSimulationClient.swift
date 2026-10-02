#if os(macOS)
import Darwin
import Foundation
import SimuCore

/// Locates the Python worker. Explicit configuration only — never guesses user paths.
/// Resolution order: UserDefaults overrides, then environment variables.
public struct WorkerEnvironment: Equatable, Sendable {
    public static let pythonDefaultsKey = "simunow.worker.python"
    public static let sourceDefaultsKey = "simunow.worker.src"

    /// The locked virtualenv interpreter (e.g. Backend/.venv/bin/python).
    public let pythonExecutableURL: URL
    /// Directory containing the simunow_worker package (Backend/src).
    public let workerSourceURL: URL

    public init(pythonExecutableURL: URL, workerSourceURL: URL) {
        self.pythonExecutableURL = pythonExecutableURL
        self.workerSourceURL = workerSourceURL
    }

    public var isUsable: Bool {
        FileManager.default.isExecutableFile(atPath: pythonExecutableURL.path)
            && FileManager.default.fileExists(atPath: workerSourceURL.appendingPathComponent("simunow_worker/__main__.py").path)
    }

    public static func resolve(defaults: UserDefaults = .standard,
                               environment: [String: String] = ProcessInfo.processInfo.environment) -> WorkerEnvironment? {
        guard let python = defaults.string(forKey: pythonDefaultsKey) ?? environment["SIMUNOW_WORKER_PYTHON"],
              let source = defaults.string(forKey: sourceDefaultsKey) ?? environment["SIMUNOW_WORKER_SRC"] else {
            return nil
        }
        let candidate = WorkerEnvironment(pythonExecutableURL: URL(fileURLWithPath: python),
                                          workerSourceURL: URL(fileURLWithPath: source))
        return candidate.isUsable ? candidate : nil
    }
}

/// Lock-protected live-process table shared by all runs of one client. Every access is
/// under the lock; this is the cancellation thread-safety story.
final class RunProcessTable: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [UUID: pid_t] = [:]

    func register(_ pid: pid_t, for runID: UUID) {
        lock.lock(); pids[runID] = pid; lock.unlock()
    }

    func pid(for runID: UUID) -> pid_t? {
        lock.lock(); defer { lock.unlock() }; return pids[runID]
    }

    func remove(_ runID: UUID) {
        lock.lock(); pids[runID] = nil; lock.unlock()
    }
}

/// Lock-protected per-run stream state: the validating parser, terminal-event flag and
/// double-finish protection shared by the reader thread and the termination path.
final class RunStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: RunEventStreamParser
    private var sawTerminal = false
    private var finished = false

    init(expectedRunID: UUID) {
        parser = RunEventStreamParser(expectedRunID: expectedRunID)
    }

    func push(_ data: Data) throws -> [RunEvent] {
        lock.lock()
        defer { lock.unlock() }
        return try parser.push(data)
    }

    func finishParsing() throws -> [RunEvent] {
        lock.lock()
        defer { lock.unlock() }
        return try parser.finish()
    }

    func markTerminal() {
        lock.lock(); sawTerminal = true; lock.unlock()
    }

    /// Terminal decision after process exit: a stream without a terminal event is a crash
    /// (e.g. exit 3 invalid input emits no events), never a silent success.
    func complete(_ continuation: AsyncThrowingStream<RunEvent, Error>.Continuation, exitStatus: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        if sawTerminal {
            continuation.finish()
        } else {
            let exited = exitStatus & 0x7F == 0
            let code = exited ? (exitStatus >> 8) & 0xFF : -(exitStatus & 0x7F)
            continuation.finish(throwing: RunClientError.workerCrashed(exitCode: code))
        }
    }

    func fail(_ continuation: AsyncThrowingStream<RunEvent, Error>.Continuation, with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.finish(throwing: error)
    }
}

/// macOS executor: spawns the Python worker as its own process-group leader so cancellation
/// can terminate the whole tree (P3 process-tree cancel), streams stdout JSONL through the
/// validating parser, and tees stderr into the run directory as a diagnostic log.
///
/// Sandboxing note: under the App Sandbox the child inherits the sandbox profile; reading the
/// worker outside the container then fails honestly with a spawn/IO error. The packaged
/// runtime bridge (helper/companion) is a P7 deployment decision (see decisions.md).
public struct LocalSimulationClient: RunClient {
    public let environment: WorkerEnvironment
    private let table = RunProcessTable()

    public init(environment: WorkerEnvironment) {
        self.environment = environment
    }

    public var unavailableReason: String? { nil }

    public func events(for job: RunJob) -> AsyncThrowingStream<RunEvent, Error> {
        let environment = self.environment
        let table = self.table
        return AsyncThrowingStream { continuation in
            do {
                try spawn(job, environment: environment, table: table, continuation: continuation)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Cooperative cancellation: write the marker file (idempotent); escalate to the process
    /// group only if the worker does not exit promptly.
    public func cancel(_ job: RunJob) async throws {
        FileManager.default.createFile(atPath: job.cancelFileURL.path, contents: Data())
        guard let pid = table.pid(for: job.identity.runID) else { return }
        let table = self.table
        let runID = job.identity.runID
        Task.detached {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if table.pid(for: runID) != nil, kill(pid, 0) == 0 { killpg(pid, SIGTERM) }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if table.pid(for: runID) != nil, kill(pid, 0) == 0 { killpg(pid, SIGKILL) }
        }
    }

    // MARK: - Process lifecycle

    private func spawn(_ job: RunJob, environment: WorkerEnvironment, table: RunProcessTable,
                       continuation: AsyncThrowingStream<RunEvent, Error>.Continuation) throws {
        guard environment.isUsable else {
            throw RunClientError.unavailable("Python worker 不可用：请按 doctor 修复路径配置（\(WorkerEnvironment.pythonDefaultsKey) / SIMUNOW_WORKER_PYTHON）。")
        }
        guard FileManager.default.fileExists(atPath: job.inputFileURL.path) else {
            throw RunClientError.unavailable("RunInput 缺失：\(job.inputFileURL.lastPathComponent)")
        }
        let runID = job.identity.runID
        let stream = RunStreamState(expectedRunID: runID)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // New session: the child leads its own process group, so killpg can never hit the app.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var environmentPairs = ProcessInfo.processInfo.environment
        environmentPairs["PYTHONPATH"] = environment.workerSourceURL.path
        environmentPairs["PYTHONDONTWRITEBYTECODE"] = "1"
        let arguments = ["-m", "simunow_worker", "run",
                         "--input", job.inputFileURL.path,
                         "--run-dir", job.runDirectoryURL.path,
                         "--cancel-file", job.cancelFileURL.path]
        var argv = ([environment.pythonExecutableURL.path] + arguments).map { strdup($0) } + [nil]
        var envp = environmentPairs.map { strdup("\($0)=\($1)") } + [nil]
        var pid = pid_t()
        let status = posix_spawn(&pid, environment.pythonExecutableURL.path, &actions, &attributes, &argv, &envp)
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attributes)
        argv.forEach { free($0) }
        envp.forEach { free($0) }
        // Parent closes its copies of the write ends so EOF propagates when the child exits.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        guard status == 0 else {
            throw RunClientError.unavailable("worker 进程启动失败（posix_spawn 错误 \(status)）")
        }
        let childPID = pid
        table.register(childPID, for: runID)

        let stderrLog = job.runDirectoryURL.appendingPathComponent("worker-stderr.log")
        FileManager.default.createFile(atPath: stderrLog.path, contents: nil)
        let stderrWriter = try? FileHandle(forWritingTo: stderrLog)
        let stderrReader = stderrPipe.fileHandleForReading
        Thread.detachNewThread {
            while let data = try? stderrReader.read(upToCount: 65536), !data.isEmpty {
                try? stderrWriter?.write(contentsOf: data)
            }
            try? stderrWriter?.close()
        }

        continuation.onTermination = { _ in
            // Consumer disappeared: do not leave an orphaned worker behind.
            if table.pid(for: runID) != nil { killpg(childPID, SIGKILL) }
            table.remove(runID)
        }

        Thread.detachNewThread {
            let reader = stdoutPipe.fileHandleForReading
            do {
                while true {
                    guard let data = try reader.read(upToCount: 65536), !data.isEmpty else { break }
                    let events = try stream.push(data)
                    for event in events {
                        if event.eventType.isTerminal { stream.markTerminal() }
                        continuation.yield(event)
                    }
                }
                let tail = try stream.finishParsing()
                for event in tail {
                    if event.eventType.isTerminal { stream.markTerminal() }
                    continuation.yield(event)
                }
            } catch {
                // Protocol violation or read failure: stop the worker, keep evidence.
                killpg(childPID, SIGKILL)
                var status: Int32 = 0
                waitpid(childPID, &status, 0)
                table.remove(runID)
                stream.fail(continuation, with: error)
                return
            }
            var exitStatus: Int32 = 0
            waitpid(childPID, &exitStatus, 0)
            table.remove(runID)
            stream.complete(continuation, exitStatus: exitStatus)
        }
    }
}
#endif
