#if os(macOS)
import Foundation
import SimuCore

/// macOS-only stub runner. Does not download engines or fabricate EnergyPlus watts.
public actor LocalProcessClient: SimulationClient {
    private let repositoryRoot: URL
    private let runRoot: URL
    // nil = no interpreter could actually start on this machine; submit then
    // refuses instead of running a doomed xcrun shim with no evidence.
    private let pythonExecutable: URL?
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

    /// True when an interpreter actually started. Clients fold this into
    /// isConfigured so a machine with no startable python3 reports
    /// unconfigured up front, never a submit that is doomed from the start.
    /// Reads only the immutable interpreter URL, so it is nonisolated.
    nonisolated public var isUsable: Bool { pythonExecutable != nil }

    /// Probe fixed binaries only. Sandbox often blocks `zsh -lc`, and 3.9 is legal after future annotations.
    ///
    /// The `/usr/bin/python3` stub routes through xcrun, which refuses to run
    /// inside an App Sandbox ("xcrun: error: cannot be used within an App
    /// Sandbox", 2026-10-03 in-app hand test), so the real interpreters that
    /// ship with CLT and Xcode are probed first. X_OK probes are denied in
    /// the sandbox for user-domain paths (ADR-011 addendum), so candidate
    /// filtering reads POSIX execute bits via stat; `canStartInterpreter`
    /// stays the only authority on whether an interpreter truly starts.
    /// All candidates failing returns nil - the honest unconfigured answer.
    public static func resolvePythonExecutable(candidates: [String]? = nil) -> URL? {
        let paths = candidates ?? [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3",
            "/usr/bin/python3"
        ]
        for path in paths where LocalEngineProbe.hasExecuteBit(at: path) {
            if canStartInterpreter(at: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // No candidate actually started. Never fall back to the xcrun stub:
        // it fails inside the sandbox and would turn every submit into an
        // evidence-free failure.
        return nil
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
        // No interpreter ever started on this machine; refuse instead of
        // running the doomed xcrun stub with no evidence.
        guard let pythonExecutable else {
            throw SimulationClientError.engineNotConfigured
        }
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
