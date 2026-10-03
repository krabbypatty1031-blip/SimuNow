import Foundation

/// One calendar day on the pinned typical-year EPW. Not a live forecast
/// and not a leap-day (the CityUHK file has no 29 February).
public struct WeatherDay: Codable, Equatable, Sendable {
    public var month: Int
    public var day: Int
    public var source: ParameterSource
    public var reference: String?

    /// Historical office pin: EnergyPlus RunPeriod 15 July.
    public static let cityUHKTypical = WeatherDay(
        month: 7,
        day: 15,
        source: .assumed,
        reference: "Hong Kong CityUHK typical meteorological year, not a live forecast"
    )

    public init(
        month: Int,
        day: Int,
        source: ParameterSource = .assumed,
        reference: String? = WeatherDay.cityUHKTypical.reference
    ) {
        self.month = month
        self.day = day
        self.source = source
        self.reference = reference
    }

    public var mmdd: String {
        String(format: "%02d-%02d", month, day)
    }

    public var isValidTypicalYearDay: Bool {
        Self.isValid(month: month, day: day)
    }

    /// Typical-year months have 28 days in February. 29 Feb is refused.
    public static func isValid(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        let lengths = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day >= 1 && day <= lengths[month]
    }
}

extension ProjectDraft {
    /// Missing weather on an old package is still 15 July, not "no weather".
    public var resolvedWeather: WeatherDay {
        weather ?? .cityUHKTypical
    }
}
