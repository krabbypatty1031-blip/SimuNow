import Foundation

/// Copy worker scripts into a container-owned tree. Never writes Desktop paths into project.json.
public enum WorkerTreeStaging {
    public static let bundleFolderName = "WorkerTree"

    public static func bundledSource() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(bundleFolderName, isDirectory: true)
    }

    public static func applicationSupportRuntime() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dest = root.appendingPathComponent("SimuNow/runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        return dest
    }

    public static func workerURL(in runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
    }

    public static func isWorkerPresent(in runtimeRoot: URL) -> Bool {
        FileManager.default.fileExists(atPath: workerURL(in: runtimeRoot).path)
    }

    public static func isP1Present(in runtimeRoot: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: runtimeRoot.appendingPathComponent("test/p1/write_idf.py").path
        )
    }

    /// P1 helpers the L2 pipeline imports by module name. The staged tree must
    /// carry all of them or `run-l2` fails on import after staging.
    public static let l2PipelineScripts = [
        "run_room.py",
        "write_openfoam_room.py",
        "quality.py",
        "sample_seats.py",
        "foam_io.py",
        "field_slice.py"
    ]

    /// Copy only the Python worker and P1 helpers. Engines are never staged:
    /// macOS quarantines executables an app writes into its own container and
    /// the sandboxed app can neither exec nor remove the mark (2026-10-03 hand
    /// test), so EnergyPlus, the EPW and the OpenFOAM wrapper run in place
    /// from the user-selected engines directory via SIMUNOW_ENGINES_ROOT.
    /// Staged Python files are data, not executables - the mark is harmless.
    public static func stageWorker(from sourceRoot: URL, into runtimeRoot: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        // Drop any engine tree an older build staged into the container.
        try? fm.removeItem(at: runtimeRoot.appendingPathComponent("test/engines"))
        try replaceDirectory(
            from: sourceRoot.appendingPathComponent("Backend/src/simunow_worker"),
            to: runtimeRoot.appendingPathComponent("Backend/src/simunow_worker")
        )
        let p1Dest = runtimeRoot.appendingPathComponent("test/p1", isDirectory: true)
        try fm.createDirectory(at: p1Dest, withIntermediateDirectories: true)
        for name in ["write_idf.py", "run_l1.py", "room_input.py"] + l2PipelineScripts {
            let src = sourceRoot.appendingPathComponent("test/p1/\(name)")
            guard fm.fileExists(atPath: src.path) else {
                throw StagingError.missingWorkerFile(name)
            }
            let dest = p1Dest.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: src, to: dest)
        }
    }

    private static func replaceDirectory(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw StagingError.missingWorkerFile(source.lastPathComponent)
        }
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: dest)
    }

    public enum StagingError: Error, Equatable, LocalizedError {
        case missingWorkerFile(String)

        public var errorDescription: String? {
            switch self {
            case .missingWorkerFile(let name):
                "运行时缺少 \(name)，无法提交代表日 L1。"
            }
        }
    }
}
