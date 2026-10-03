import Foundation

/// Filesystem probe only. Does not launch EnergyPlus or Docker.
public enum LocalEngineProbe {
    public static func energyPlusURL(in enginesRoot: URL) -> URL {
        enginesRoot.appendingPathComponent("EnergyPlus/energyplus")
    }

    public static func workerURL(in repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
    }

    public static func isConfigured(repositoryRoot: URL, enginesRoot: URL) -> Bool {
        let energyPlus = energyPlusURL(in: enginesRoot)
        let worker = workerURL(in: repositoryRoot)
        return FileManager.default.isExecutableFile(atPath: energyPlus.path)
            && FileManager.default.fileExists(atPath: worker.path)
    }
}
