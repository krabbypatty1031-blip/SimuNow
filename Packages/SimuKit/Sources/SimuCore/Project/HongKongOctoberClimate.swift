import Foundation

/// October climate defaults for the University of Hong Kong main campus.
///
/// Temperatures and humidity are Hong Kong Observatory 1991–2020 monthly normals
/// (Tables 4 and 5), recorded at Tsim Sha Tsui and applied to the Pok Fu Lam campus.
/// They are not a campus measurement and not an hourly weather file.
/// L0 uses the constant outdoor temperature; it does not open the citation file.
public enum HongKongOctoberClimate {
    public static let citation = "https://www.hko.gov.hk/en/cis/normal/1991_2020/normals.htm"
    public static let outdoorTemperatureC = 25.7
    public static let relativeHumidity = 0.73
    public static let representativeDate = "2026-10-15"
    public static let timeZoneIdentifier = "Asia/Hong_Kong"
    public static let northAngleDegrees = 0.0
    public static let weatherRelativePath = "climate/hku-october-1991-2020.txt"
    /// SHA-256 of `Resources/hku-october-1991-2020.txt`.
    public static let weatherSHA256 = "d30f482d59c20255d6f8d777ec03fefdd63b5884b777ac6f84555c31d0f57033"

    public static let preset = SourceRecord(
        kind: .preset,
        reference: citation,
        note: "香港天文台 1991–2020 年 10 月月平均，用于香港大学本部（薄扶林，约 22.284°N、114.138°E）。测站在尖沙咀，不是校园实测。"
    )

    public static func outdoorTemperature() -> Temperature {
        .known(value: outdoorTemperatureC, source: preset)
    }

    public static func humidity(indoor: Bool) -> Ratio {
        var source = preset
        source.note = indoor
            ? "没有室内实测，暂用香港天文台 1991–2020 年 10 月室外月平均相对湿度 73%。"
            : "香港天文台 1991–2020 年 10 月月平均相对湿度 73%。"
        return .known(value: relativeHumidity, source: source)
    }

    public static func northAngle() -> Angle {
        var source = preset
        source.note = "俯视图远侧（+Y）暂按正北。香港大学本部约 22.284°N、114.138°E；房间实际朝向请按现场修改。"
        return .known(value: northAngleDegrees, source: source)
    }

    public static func exteriorAirTemperature() -> Temperature {
        var source = preset
        source.note = "外墙外的空气温度，采用香港天文台 1991–2020 年 10 月月平均 25.7°C，不是墙面实测温度。"
        return .known(value: outdoorTemperatureC, source: source)
    }

    public static func environment() -> Environment {
        Environment(
            representativeDate: representativeDate,
            timeZone: timeZoneIdentifier,
            weather: WeatherReference(relativePath: weatherRelativePath, sha256: weatherSHA256),
            outdoorTemperature: outdoorTemperature(),
            outdoorHumidity: humidity(indoor: false),
            indoorHumidity: humidity(indoor: true)
        )
    }

    public static func citationData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "hku-october-1991-2020", withExtension: "txt") else {
            throw ProjectPackageError.missingProjectFile(weatherRelativePath)
        }
        return try Data(contentsOf: url)
    }

    /// Writes the citation beside `project.json` when a scenario still uses this preset.
    public static func installCitationIfReferenced(into packageURL: URL, project: ProjectDocument) throws {
        let referenced = project.scenarios.contains {
            $0.inputs.environment.weather?.relativePath == weatherRelativePath
                && $0.inputs.environment.weather?.sha256 == weatherSHA256
        }
        guard referenced else { return }
        let data = try citationData()
        let directory = packageURL.appendingPathComponent("climate", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("hku-october-1991-2020.txt"), options: .atomic)
    }
}
