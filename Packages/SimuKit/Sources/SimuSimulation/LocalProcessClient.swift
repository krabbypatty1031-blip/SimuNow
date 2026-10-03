#if os(macOS)
import Foundation
import SimuCore

/// macOS-only stub runner. Does not download engines or fabricate EnergyPlus watts.
public actor LocalProcessClient: SimulationClient {
    private let repositoryRoot: URL
    private let runRoot: URL
    private let pythonExecutable: URL
    private let extraEnvironment: [String: String]
    private var running: [UUID: Process] = [:]
    private var cancelled: Set<UUID> = []
    private var succeededByHash: [String: RunReceipt] = [:]

    public init(
        repositoryRoot: URL,
        runRoot: URL,
        pythonExecutable: URL? = nil,
        extraEnvironment: [String: String] = [:]
    ) {
        self.repositoryRoot = repositoryRoot
        self.runRoot = runRoot
        self.pythonExecutable = pythonExecutable ?? Self.resolvePythonExecutable()
        self.extraEnvironment = extraEnvironment
    }

    /// Probe fixed binaries only. Sandbox often blocks `zsh -lc`, and 3.9 is legal after future annotations.
    public static func resolvePythonExecutable() -> URL {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if canStartInterpreter(at: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    private static func canStartInterpreter(at path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "from __future__ import annotations"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func submit(_ request: SimulationRequest) async throws -> RunReceipt {
        // Snapshot bytes are required so the hash can be checked. P3-03 wires the package file.
        throw SimulationClientError.engineNotConfigured
    }

    public func submit(
        _ request: SimulationRequest,
        snapshot: Data,
        extraArguments: [String] = [],
        timeoutSeconds: TimeInterval? = nil,
        workerCommand: String = "run-l1"
    ) async throws -> RunReceipt {
        try request.validate(snapshot: snapshot)
        if let cached = succeededByHash[request.identity.inputHash] {
            return cached
        }
        let runDir = runRoot.appendingPathComponent(request.identity.runID.uuidString, isDirectory: true)
        let logs = runDir.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: runDir.appendingPathComponent("request.json"))
        try snapshot.write(to: runDir.appendingPathComponent("input.json"))

        let process = Process()
        process.executableURL = pythonExecutable
        process.currentDirectoryURL = repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = repositoryRoot.appendingPathComponent("Backend/src").path
        extraEnvironment.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        process.arguments = [
            "-m", "simunow_worker", workerCommand,
            "--request", runDir.appendingPathComponent("request.json").path,
            "--snapshot", runDir.appendingPathComponent("input.json").path,
            "--run-dir", runDir.path
        ] + extraArguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        running[request.identity.runID] = process
        try process.run()
        let timedOut = await waitForExit(process, timeoutSeconds: timeoutSeconds)
        running[request.identity.runID] = nil

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        var stderrText = redactHome(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        if timedOut {
            stderrText += (stderrText.isEmpty || stderrText.hasSuffix("\n") ? "" : "\n")
            stderrText += "timeout: stub worker exceeded limit\n"
        }
        try stdoutData.write(to: runDir.appendingPathComponent("events.jsonl"))
        try stderrText.write(to: logs.appendingPathComponent("stderr.log"), atomically: true, encoding: .utf8)

        var stream = TaskEventStream(expectedRunID: request.identity.runID)
        if let text = String(data: stdoutData, encoding: .utf8) {
            _ = try? stream.ingest(text.hasSuffix("\n") ? text : text + "\n")
            try? stream.finish()
        }

        if cancelled.contains(request.identity.runID) {
            cancelled.remove(request.identity.runID)
            return RunReceipt(identity: request.identity, state: .cancelled, quality: .notEvaluated)
        }
        if timedOut || process.terminationStatus != 0 {
            return RunReceipt(identity: request.identity, state: .failed, quality: .notEvaluated)
        }
        if stream.events.contains(where: { $0.eventType == .completed }) {
            let receipt = RunReceipt(identity: request.identity, state: .succeeded, quality: .notEvaluated)
            succeededByHash[request.identity.inputHash] = receipt
            return receipt
        }
        return RunReceipt(identity: request.identity, state: .failed, quality: .notEvaluated)
    }

    /// Resume once on process exit or after terminate-on-timeout. Does not invent a receipt.
    private func waitForExit(_ process: Process, timeoutSeconds: TimeInterval?) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = OnceResume()
            process.terminationHandler = { _ in once.resume(continuation, timedOut: false) }
            if let timeoutSeconds {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                    if process.isRunning {
                        process.terminate()
                        once.resume(continuation, timedOut: true)
                    }
                }
            }
            if !process.isRunning {
                once.resume(continuation, timedOut: false)
            }
        }
    }

    public func cancel(runID: UUID) async throws {
        cancelled.insert(runID)
        if let process = running[runID], process.isRunning {
            process.terminate()
        }
    }

    public func loadResult(runID: UUID) throws -> SimulationResult? {
        let url = runRoot.appendingPathComponent(runID.uuidString, isDirectory: true)
            .appendingPathComponent("result.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SimulationResult.self, from: Data(contentsOf: url))
    }

    public func loadEvents(runID: UUID) throws -> [SimulationEvent] {
        let url = runRoot.appendingPathComponent(runID.uuidString, isDirectory: true)
            .appendingPathComponent("events.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var stream = TaskEventStream(expectedRunID: runID)
        _ = try? stream.ingest(text.hasSuffix("\n") ? text : text + "\n")
        try? stream.finish()
        return stream.events
    }

    private func redactHome(_ text: String) -> String {
        var redacted = text.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "$HOME"
        )
        // Defense in depth if a library expands another user path.
        if let range = redacted.range(of: "/Users/", options: .caseInsensitive) {
            redacted.replaceSubrange(range, with: "$USERS/")
        }
        return redacted
    }
}

/// Lock-protected one-shot so timeout and terminationHandler cannot double-resume.
private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, timedOut: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: timedOut)
    }
}
#endif
