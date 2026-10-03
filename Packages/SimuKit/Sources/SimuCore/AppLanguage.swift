import Foundation

/// In-app UI language. English is the default; Chinese is the other shipped locale.
/// Switching does not require relaunch. The choice is stored in UserDefaults.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable, Equatable {
    case english = "en"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    /// Name of this language in that language, so the picker is readable before the UI switches.
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }

    public static let `default`: AppLanguage = .english

    public static let storageKey = "simunow.appLanguage"

    public static func load(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let raw = defaults.string(forKey: storageKey),
              let language = AppLanguage(rawValue: raw) else {
            return .default
        }
        return language
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}
