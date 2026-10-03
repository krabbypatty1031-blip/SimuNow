import Foundation
import Testing
import SimuCore
import SimuWorkspace

@Test func fieldTitlesNeverEchoRawPaths() {
    let samples = [
        "hvac.setpointC", "hvac.supply", "occupancy.occupantCount",
        "geometry.openings.W1.z0", "occupancy.comfort.mrtC", "occupancy.comfort.clo"
    ]
    for path in samples {
        let title = UserFacingCopy.fieldTitle(path)
        #expect(!title.contains("hvac."))
        #expect(!title.contains("z0"))
        #expect(!title.contains("mrtC"))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(title))
    }
    #expect(UserFacingCopy.fieldTitle("hvac.setpointC") == "Setpoint temperature")
    #expect(UserFacingCopy.fieldTitle("occupancy.comfort.mrtC") == "Surrounding surface temperature")
    #expect(UserFacingCopy.chinese.fieldTitle("hvac.setpointC") == "空调设定温度")
}

@Test func wallsAndOpeningsUseRoomLanguage() {
    #expect(UserFacingCopy.wallTitle(.xMin) == "Left wall")
    #expect(UserFacingCopy.wallTitle(.xMax) == "Right wall")
    #expect(UserFacingCopy.wallTitle(.yMin) == "Near wall")
    #expect(UserFacingCopy.wallTitle(.yMax) == "Far wall")
    #expect(UserFacingCopy.openingTitle(kind: .window, wall: .xMax, indexOnWall: 0, countOnWall: 1) == "Right wall window")
    #expect(UserFacingCopy.openingTitle(kind: .door, wall: .yMin, indexOnWall: 1, countOnWall: 2) == "Near wall door 2")
    #expect(UserFacingCopy.seatTitle(index: 0, near: .nearWindow) == "Window seat 1")
    #expect(UserFacingCopy.terminalTitle(isSupply: true) == "Supply outlet")
    #expect(UserFacingCopy.terminalTitle(isSupply: false) == "Return inlet")
    #expect(UserFacingCopy.chinese.wallTitle(.xMin) == "左墙")
    #expect(UserFacingCopy.chinese.openingTitle(kind: .window, wall: .xMax, indexOnWall: 0, countOnWall: 1) == "右墙的窗")
}

@Test func metricAndStateTitlesHideSolverNames() {
    #expect(UserFacingCopy.metricTitle("q_cool_w") == "Cooling demand")
    #expect(UserFacingCopy.metricTitle("p_elec_w") == "AC electric power")
    #expect(UserFacingCopy.metricTitle("seat_t_c_min") == "Coolest seat")
    #expect(UserFacingCopy.metricTitle("seat_t_c_max") == "Warmest seat")
    #expect(UserFacingCopy.metricTitle("seat_u_mag_max") == "Highest seat air speed")
    #expect(UserFacingCopy.metricTitle("seat_pmv_min") == "Too cool (sensation)")
    #expect(UserFacingCopy.metricTitle("seat_ppd_max") == "Share who may feel uncomfortable")
    #expect(UserFacingCopy.runStateTitle(.solving) == "Estimating")
    #expect(UserFacingCopy.qualityTitle(.passed) == "Passed checks")
    #expect(UserFacingCopy.qualityTitle(.failed) == "Did not pass checks")
    #expect(UserFacingCopy.qualityShortTitle(.passed) == "Passed")
    #expect(UserFacingCopy.qualityShortTitle(.failed) == "Did not pass")
    #expect(UserFacingCopy.qualityShortTitle(.notEvaluated) == "Not checked yet")
    #expect(UserFacingCopy.freshnessTitle(.stale) == "The room changed. Estimate again.")
    #expect(UserFacingCopy.omittedAssumptionTitle("omitted: envelope_u_value") == "Wall insulation is not filled in and will not be treated as 0")
    #expect(UserFacingCopy.chinese.metricTitle("q_cool_w") == "制冷需求")
    #expect(UserFacingCopy.chinese.qualityShortTitle(.passed) == "已通过")
    #expect(UserFacingCopy.chinese.freshnessTitle(.stale) == "房间改过了，请重新估算")
}

@Test func defaultCopyRejectsForbiddenTokens() {
    let titles = [
        UserFacingCopy.metricTitle("q_cool_w"),
        UserFacingCopy.fieldTitle("geometry.openings.W1.s0"),
        UserFacingCopy.freshnessTitle(.stale),
        UserFacingCopy.comfortKeyTitle("clo")
    ]
    for text in titles {
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(text))
    }
}

@Test func officeTemplateSeatNearWindowIsNamedForTheUser() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let geometry = try #require(draft.geometry)
    let seats = try #require(draft.occupancy?.seats)
    let places = seats.map { SeatPlace.classify(seat: $0, geometry: geometry) }
    #expect(places.contains(.nearWindow))
    let named = seats.enumerated().map { index, seat in
        UserFacingCopy.seatTitle(index: index, near: SeatPlace.classify(seat: seat, geometry: geometry))
    }
    for title in named {
        #expect(!title.hasPrefix("S") || title.hasPrefix("Seat") || title.hasPrefix("Window") || title.hasPrefix("Door"))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(title))
    }
}

@Test func displayNumbersKeepTwoFractionDigits() {
    #expect(UserFacingCopy.displayNumber(1033.112) == "1033.11")
    #expect(UserFacingCopy.displayNumber(10.33112) == "10.33")
    #expect(UserFacingCopy.displayNumber(12.397) == "12.40")
    #expect(UserFacingCopy.displayNumber(24) == "24.00")
    #expect(UserFacingCopy.displayNumber(0.75) == "0.75")
    #expect(UserFacingCopy.displayQuantity(26, unit: "°C") == "26.00 °C")
    // Contract units stay "C"; the display layer spells them "°C" so the
    // card never reads a bare "C" next to a temperature.
    #expect(UserFacingCopy.displayQuantity(25.16, unit: "C") == "25.16 °C")
    #expect(UserFacingCopy.displayRange(23.348, 25.207, unit: "°C") == "23.35 – 25.21 °C")
}

@Test func destinationTitlesAreUserGoals() {
    #expect(WorkspaceDestination.workspace.title == "Lay out the room")
    #expect(WorkspaceDestination.runs.title == "Calculation results")
    #expect(WorkspaceDestination.scenarios.title == "Compare schemes")
    #expect(WorkspaceDestination.reports.title == "Export report")
    // The enum case order drives the sidebar order via CaseIterable; anchor the
    // workflow sequence (estimate, then compare estimates) so a reorder cannot
    // slip in silently.
    #expect(WorkspaceDestination.allCases == [.workspace, .runs, .scenarios, .reports])
    for destination in WorkspaceDestination.allCases {
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(destination.title))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(destination.title(UserFacingCopy.chinese)))
    }
    #expect(WorkspaceDestination.workspace.title(UserFacingCopy.chinese) == "布置房间")
    #expect(WorkspaceDestination.runs.title(UserFacingCopy.chinese) == "计算结果")
}

@Test func appLanguageDefaultsToChineseAndPersistsInASuite() {
    // Merge decision 2026-10-04: the app ships Chinese-first; English is a toggle.
    #expect(AppLanguage.default == .chinese)
    #expect(AppLanguage.chinese.locale.identifier == "zh-Hans")
    #expect(AppLanguage.english.locale.identifier == "en")
    let suiteName = "simunow.tests.appLanguage.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }
    #expect(AppLanguage.load(defaults: suite) == .chinese)
    AppLanguage.chinese.persist(defaults: suite)
    #expect(AppLanguage.load(defaults: suite) == .chinese)
    AppLanguage.english.persist(defaults: suite)
    #expect(AppLanguage.load(defaults: suite) == .english)
}

@MainActor
@Test func switchingWorkspaceLanguageUpdatesCopyWithoutWritingDefaults() {
    let store = WorkspaceStore()
    #expect(store.language == .english)
    #expect(store.copy.destinationTitle("runs") == "Calculation results")
    store.language = .chinese
    #expect(store.copy.destinationTitle("runs") == "计算结果")
    #expect(store.engineStatus.contains("计算准备") || store.engineStatus.contains("还不能估算"))
    // Inspector field labels (2026-10-04 live: macOS .inspector kept
    // English "Wall" / "Apply 出风口" after the toggle because child
    // editors read the environment default, not store.copy). The copy
    // the inspector must be given is this one.
    #expect(store.copy.wall == "墙面")
    #expect(store.copy.wallTitle(.xMin) == "左墙")
    #expect(store.copy.source == "来源")
    #expect(store.copy.sourceTitle(.preset) == "模板预设")
    #expect(store.copy.startAlongWall == "沿墙起点")
    #expect(store.copy.endAlongWall == "沿墙终点")
    #expect(store.copy.heightAboveFloor == "离地高度")
    #expect(store.copy.topHeight == "上沿高度")
    #expect(store.copy.terminalTitle(isSupply: true) == "出风口")
    #expect(store.copy.applyNamed("出风口") == "应用出风口")
    store.language = .english
    #expect(store.copy.destinationTitle("runs") == "Calculation results")
    #expect(store.copy.wall == "Wall")
    #expect(store.copy.applyNamed("Supply outlet") == "Apply Supply outlet")
}

/// The SwiftUI environment key defaults to English. macOS `.inspector`
/// (and sheets) do not inherit a custom environment unless the presenting
/// view reapplies it, so a language toggle that only sets the root
/// environment leaves the right-hand editor on this default.
@Test func userFacingCopyEnvironmentDefaultIsEnglish() {
    #expect(UserFacingCopy.environmentDefault.language == .english)
    #expect(UserFacingCopy.environmentDefault.wall == "Wall")
    #expect(UserFacingCopy.environmentDefault.applyNamed("出风口") == "Apply 出风口")
}

@Test func storedAssumptionNotesDisplayInTheUILanguage() throws {
    #expect(
        UserFacingCopy.english.displayStoredNote(UserFacingCopy.storedDemoTariffReference)
            == "Contest demo assumption, not a real tariff"
    )
    #expect(
        UserFacingCopy.chinese.displayStoredNote(UserFacingCopy.storedDemoTariffReference)
            == UserFacingCopy.storedDemoTariffReference
    )
    #expect(
        UserFacingCopy.english.displayStoredNote(UserFacingCopy.storedMRTEqualsSetpoint)
            == "Assumed equal to the zone setpoint, not a radiation solve"
    )
    #expect(
        UserFacingCopy.english.displayStoredNote(UserFacingCopy.storedChildrenUnevaluated)
            == "Children are not evaluated separately"
    )
    let draft = try ProjectTemplates.bundled(named: "office").project
    var listed = draft.listedAssumptions()
    for index in listed.indices {
        listed[index].copy = .english
    }
    let mrt = listed.first { $0.path == "occupancy.comfort.mrtC" }
    #expect(mrt?.reference == UserFacingCopy.storedMRTEqualsSetpoint)
    #expect(mrt?.provenanceText == "Assumed equal to the zone setpoint, not a radiation solve")
    let occupants = listed.first { $0.path == "occupancy.occupantCount" }
    #expect(occupants?.provenanceText == "Template preset")
}
