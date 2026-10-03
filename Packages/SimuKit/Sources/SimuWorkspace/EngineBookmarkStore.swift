import Foundation

#if os(macOS)
/// Persists the user-selected engines folder. Worker lives in the app container, not project.json.
enum EngineBookmarkStore {
    private static let enginesKey = "simunow.enginesRoot.bookmark"
    private static let repositoryKey = "simunow.repositoryRoot.bookmark"

    static func saveEngines(_ enginesRoot: URL) {
        if let data = try? enginesRoot.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: enginesKey)
        }
    }

    static func restoreEngines() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: enginesKey) else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    static func save(repositoryRoot: URL, enginesRoot: URL) {
        saveEngines(enginesRoot)
        if let data = try? repositoryRoot.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: repositoryKey)
        }
    }

    static func restore() -> (repositoryRoot: URL, enginesRoot: URL)? {
        guard let engines = restoreEngines() else { return nil }
        guard let repoData = UserDefaults.standard.data(forKey: repositoryKey) else {
            return nil
        }
        var stale = false
        guard let repositoryRoot = try? URL(
            resolvingBookmarkData: repoData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        return (repositoryRoot, engines)
    }
}
#endif
