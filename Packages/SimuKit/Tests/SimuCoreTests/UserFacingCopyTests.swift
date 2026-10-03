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
    #expect(UserFacingCopy.fieldTitle("hvac.setpointC") == "空调设定温度")
    #expect(UserFacingCopy.fieldTitle("occupancy.comfort.mrtC") == "周围表面温度")
}

@Test func wallsAndOpeningsUseRoomLanguage() {
    #expect(UserFacingCopy.wallTitle(.xMin) == "左墙")
    #expect(UserFacingCopy.wallTitle(.xMax) == "右墙")
    #expect(UserFacingCopy.wallTitle(.yMin) == "近侧墙")
    #expect(UserFacingCopy.wallTitle(.yMax) == "远侧墙")
    #expect(UserFacingCopy.openingTitle(kind: .window, wall: .xMax, indexOnWall: 0, countOnWall: 1) == "右墙的窗")
    #expect(UserFacingCopy.openingTitle(kind: .door, wall: .yMin, indexOnWall: 1, countOnWall: 2) == "近侧墙的门 2")
    #expect(UserFacingCopy.seatTitle(index: 0, near: .nearWindow) == "靠窗座位 1")
    #expect(UserFacingCopy.terminalTitle(isSupply: true) == "出风口")
    #expect(UserFacingCopy.terminalTitle(isSupply: false) == "回风口")
}

@Test func metricAndStateTitlesHideSolverNames() {
    #expect(UserFacingCopy.metricTitle("q_cool_w") == "制冷需求")
    #expect(UserFacingCopy.metricTitle("p_elec_w") == "空调用电功率")
    #expect(UserFacingCopy.metricTitle("seat_t_c_min") == "座位最凉")
    #expect(UserFacingCopy.metricTitle("seat_t_c_max") == "座位最热")
    #expect(UserFacingCopy.metricTitle("seat_u_mag_max") == "座位最大风速")
    #expect(UserFacingCopy.metricTitle("seat_pmv_min") == "冷热是否合适（偏低）")
    #expect(UserFacingCopy.metricTitle("seat_ppd_max") == "可能觉得不舒服的比例")
    #expect(UserFacingCopy.runStateTitle(.solving) == "正在估算")
    #expect(UserFacingCopy.qualityTitle(.passed) == "已通过检查")
    #expect(UserFacingCopy.qualityTitle(.failed) == "未通过检查")
    #expect(UserFacingCopy.freshnessTitle(.stale) == "房间改过了，请重新估算")
    #expect(UserFacingCopy.omittedAssumptionTitle("omitted: envelope_u_value") == "墙的保温尚未填写，不会按 0 计算")
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
        #expect(!title.hasPrefix("S"))
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
    #expect(UserFacingCopy.displayRange(23.348, 25.207, unit: "°C") == "23.35 – 25.21 °C")
}

@Test func destinationTitlesAreUserGoals() {
    #expect(WorkspaceDestination.workspace.title == "布置房间")
    #expect(WorkspaceDestination.runs.title == "用电与舒适")
    #expect(WorkspaceDestination.scenarios.title == "方案对比")
    #expect(WorkspaceDestination.reports.title == "导出报告")
    for destination in WorkspaceDestination.allCases {
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(destination.title))
    }
}
