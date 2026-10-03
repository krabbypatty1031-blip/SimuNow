import Foundation
import Testing
import SimuCore

@Test func missingWeatherOmitsCoolingAndElectricityInsteadOfZero() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let identity = RunIdentity(scenarioID: UUID(), inputHash: "snap")
    let result = try L1Accounting.evaluate(
        identity: identity,
        draft: draft,
        context: L1DayContext(weatherPath: nil, weatherHash: nil, coolingLoadW: nil)
    )
    let cool = try #require(result.metric(named: "q_cool_w"))
    let elec = try #require(result.metric(named: "p_elec_w"))
    let annual = try #require(result.metric(named: "annual_kwh"))
    #expect(cool.omitted)
    #expect(cool.value == nil)
    #expect(elec.omitted)
    #expect(elec.value == nil)
    #expect(annual.omitted)
    #expect(annual.value != 0)
    #expect(result.weatherPath == nil)
}

@Test func electricityIsCoolingDividedByCOPAndNotTheRatedCapacity() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let identity = RunIdentity(scenarioID: UUID(), inputHash: "snap")
    let result = try L1Accounting.evaluate(
        identity: identity,
        draft: draft,
        context: L1DayContext(
            weatherPath: "weather/CHN_Hong.Kong.SAR.450070_CityUHK.epw",
            weatherHash: "epw-hash",
            coolingLoadW: 6334.87
        )
    )
    let cool = try #require(result.metric(named: "q_cool_w"))
    let elec = try #require(result.metric(named: "p_elec_w"))
    #expect(cool.value == 6334.87)
    #expect(cool.unit == "W")
    #expect(elec.unit == "W")
    #expect(elec.method == "equivalent_ideal_loads")
    #expect(cool.fidelity == .l1)
    #expect(abs((elec.value ?? 0) - 6334.87 / 3.0) < 1e-6)
    #expect(elec.value != cool.value)
    #expect(result.weatherHash == "epw-hash")
    #expect(result.period?.kind == "representative_day")
    #expect(result.period?.start == "07-15")
    #expect(result.period?.end == "07-15")
}

@Test func l1ResultKeepsSetpointSeparateFromSupplyTemperature() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.hvac?.setpointC.value == 26)
    #expect(draft.hvac?.supplyTemperatureC.value == 16)
    let result = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
        draft: draft,
        context: L1DayContext(
            weatherPath: "weather/HK.epw",
            weatherHash: "h",
            coolingLoadW: 900
        )
    )
    #expect(result.supplyTemperatureC == 16)
    #expect(result.setpointC == 26)
    #expect(result.supplyTemperatureC != result.setpointC)
}

@Test func officeScheduleEntersL1WithHashAndIsNotTheWeatherFile() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let occupancy = try #require(draft.occupancy?.schedule)
    let hvac = try #require(draft.hvac?.schedule)
    #expect(occupancy.start == "08:00")
    #expect(occupancy.end == "18:00")
    #expect(hvac.kind == "occupied_hours")
    let digest = try #require(L1Accounting.scheduleHash(of: draft))
    let result = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
        draft: draft,
        context: L1DayContext(
            weatherPath: "weather/HK.epw",
            weatherHash: "epw-hash",
            coolingLoadW: 900,
            scheduleHash: digest
        )
    )
    #expect(result.schedule?.kind == "occupied_hours")
    #expect(result.schedule?.start == "08:00")
    #expect(result.schedule?.end == "18:00")
    #expect(result.hvacSchedule?.start == "08:00")
    #expect(result.scheduleHash == digest)
    #expect(result.scheduleHash != result.weatherHash)
}

@Test func missingScheduleOmitsHoursInsteadOfInventingADay() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    draft.occupancy?.schedule = nil
    draft.hvac?.schedule = nil
    let result = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 1)
    )
    #expect(result.schedule == nil)
    #expect(result.hvacSchedule == nil)
    #expect(result.scheduleHash == nil)
}

@Test func l1RejectsScheduleHashThatDoesNotMatchDraft() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    #expect(throws: TaskProtocolError.hashMismatch) {
        try L1Accounting.evaluate(
            identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
            draft: draft,
            context: L1DayContext(
                weatherPath: "weather/HK.epw",
                weatherHash: "h",
                coolingLoadW: 1,
                scheduleHash: "not-the-schedule"
            )
        )
    }
}

@Test func l1RejectsAbsoluteWeatherPath() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    #expect(throws: TaskProtocolError.unsafeSnapshotPath) {
        try L1Accounting.evaluate(
            identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
            draft: draft,
            context: L1DayContext(
                weatherPath: "/Users/krabbypatty/weather.epw",
                weatherHash: "h",
                coolingLoadW: 1
            )
        )
    }
}
