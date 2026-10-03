import Foundation

/// Filesystem probe only. Does not launch EnergyPlus or Docker.
public enum LocalEngineProbe {
    public static func energyPlusURL(in enginesRoot: URL) -> URL {
        enginesRoot.appendingPathComponent("EnergyPlus/energyplus")
    }

    public static func workerURL(in repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
    }

    /// POSIX execute bits via stat, never access(X_OK). App Sandbox denies
    /// access(X_OK) for staged container paths and user-selected engine
    /// directories alike, so `isExecutableFile` returned false inside the
    /// sandbox while `test -x` passed in a shell (2026-10-03 in-app hand
    /// test). stat needs only read access, which the sandbox grants, and it
    /// follows symlinks, so the staged `energyplus -> energyplus-25.2.0`
    /// layout probes the target's bits. Whether the engine actually runs
    /// stays the task's own evidence, never this probe's claim.
    public static func hasExecuteBit(at path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return false
        }
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0
        return (permissions & 0o111) != 0
    }

    public static func isConfigured(repositoryRoot: URL, enginesRoot: URL) -> Bool {
        let energyPlus = energyPlusURL(in: enginesRoot)
        let worker = workerURL(in: repositoryRoot)
        // Execute bits, not X_OK: same sandbox-safe rule as hasExecuteBit.
        return hasExecuteBit(at: energyPlus.path)
            && FileManager.default.fileExists(atPath: worker.path)
    }
}
