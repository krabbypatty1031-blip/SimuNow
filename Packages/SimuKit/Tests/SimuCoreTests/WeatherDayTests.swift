import Foundation
import Testing
import SimuCore

@Test func typicalYearRejectsLeapDayAndZeroMonth() {
    #expect(WeatherDay.isValid(month: 7, day: 15))
    #expect(WeatherDay.isValid(month: 2, day: 28))
    #expect(!WeatherDay.isValid(month: 2, day: 29))
    #expect(!WeatherDay.isValid(month: 0, day: 1))
    #expect(!WeatherDay.isValid(month: 13, day: 1))
    #expect(!WeatherDay.isValid(month: 4, day: 31))
}

@Test func missingWeatherOnOldDraftResolvesToJuly15() {
    let draft = ProjectDraft(name: "旧稿")
    #expect(draft.weather == nil)
    #expect(draft.resolvedWeather.mmdd == "07-15")
}

@Test func weatherDayRoundTripsWithoutInventingACity() throws {
    let day = WeatherDay(month: 1, day: 15, source: .user)
    let decoded = try JSONDecoder().decode(WeatherDay.self, from: try JSONEncoder().encode(day))
    #expect(decoded.month == 1)
    #expect(decoded.day == 15)
    #expect(decoded.source == .user)
    #expect(decoded.mmdd == "01-15")
}

@Test func applyWeatherDayWritesTypicalYearAndRejectsLeapDay() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.resolvedWeather.mmdd == "07-15")
    #expect(draft.applyWeatherDay(month: 1, day: 15, source: .user).isEmpty)
    #expect(draft.weather?.mmdd == "01-15")
    #expect(draft.weather?.source == .user)
    let rejected = draft.applyWeatherDay(month: 2, day: 29, source: .user)
    #expect(rejected.contains { $0.path == "weather" })
    #expect(draft.weather?.mmdd == "01-15")
}
