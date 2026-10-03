import Foundation
import Testing
import SimuCore

/// Four in-band seats. S4 is farthest from the 24.5 °C band center.
private let inBand: [FeasibilitySeat] = [
    FeasibilitySeat(id: "S1", tC: 24.5, uMag: 0.05, pmv: 0.0),
    FeasibilitySeat(id: "S2", tC: 24.0, uMag: 0.10, pmv: 0.1),
    FeasibilitySeat(id: "S3", tC: 25.2, uMag: 0.15, pmv: -0.2),
    FeasibilitySeat(id: "S4", tC: 23.1, uMag: 0.20, pmv: 0.3),
]

private func metric(_ metrics: [ResultMetric], _ name: String) -> ResultMetric? {
    metrics.first { $0.name == name }
}

@Test func inBandSeatsWithPmvCoverEverySeatAndNameTheFarthest() {
    let metrics = SeatFeasibility.metrics(seats: inBand, qualityPassed: true)
    let ratio = metric(metrics, "seat_pass_ratio")
    #expect(ratio?.omitted == false)
    #expect(ratio?.value == 1)
    #expect(ratio?.fidelity == .l2)
    #expect(metric(metrics, "seat_pass_count")?.value == 4)
    #expect(metric(metrics, "seat_eval_count")?.value == 4)
    #expect(metric(metrics, "worst_seat_id")?.reason == "S4")
    #expect(metric(metrics, "worst_seat_id")?.omitted == false)
}

@Test func oneHotSeatFailsTheTemperatureGate() {
    var seats = inBand
    seats[3] = FeasibilitySeat(id: "S4", tC: 27.0, uMag: 0.05, pmv: 0.2)
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(metric(metrics, "seat_pass_ratio")?.value == 0.75)
    #expect(metric(metrics, "seat_pass_count")?.value == 3)
    #expect(metric(metrics, "seat_eval_count")?.value == 4)
    #expect(metric(metrics, "worst_seat_id")?.reason == "S4")
    #expect(metric(metrics, "worst_seat_reason")?.reason?.contains("温度门") == true)
    // The worst seat's own numbers let the default line name a direction.
    #expect(metric(metrics, "worst_seat_t_c")?.value == 27.0)
    #expect(metric(metrics, "worst_seat_u_mag")?.value == 0.05)
    #expect(SeatFeasibility.worstSeatText(metrics: metrics) == "座位 4 偏热，约 27.00 °C")
}

@Test func omittedSeatLeavesTheDenominator() {
    // 40 °C would win "farthest from 24.5" if a bug counted it.
    var seats = Array(inBand.prefix(3))
    seats.append(FeasibilitySeat(id: "S9", tC: 40.0, uMag: 0.9, omitted: true))
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(metric(metrics, "seat_eval_count")?.value == 3)
    #expect(metric(metrics, "seat_pass_count")?.value == 3)
    #expect(metric(metrics, "seat_pass_ratio")?.value == 1)
    #expect(metric(metrics, "worst_seat_id")?.reason != "S9")
    let reason = metric(metrics, "seat_pass_ratio")?.reason ?? ""
    #expect(reason.contains("S9"))
    #expect(reason.contains("不计入分母"))
}

@Test func failedQualityOmitsTheRatioInsteadOfZero() {
    let metrics = SeatFeasibility.metrics(seats: inBand, qualityPassed: false)
    let ratio = metric(metrics, "seat_pass_ratio")
    #expect(ratio?.omitted == true)
    #expect(ratio?.value == nil)
    #expect(ratio?.value != 0)
    #expect(ratio?.reason?.isEmpty == false)
    let text = SeatFeasibility.coverageText(metrics: metrics)
    #expect(text == "不可评价")
    #expect(text != "0%")
    #expect(!text.contains("0%"))
}

@Test func noSeatSamplesOmitsTheRatio() {
    let metrics = SeatFeasibility.metrics(seats: nil, qualityPassed: true)
    #expect(metric(metrics, "seat_pass_ratio")?.omitted == true)
    #expect(metric(metrics, "seat_pass_ratio")?.value == nil)
    #expect(SeatFeasibility.coverageText(metrics: metrics) == "不可评价")
}

@Test func everyEvaluatedSeatFailingIsZeroWithGatesAndNoRecommendation() {
    let seats = [
        FeasibilitySeat(id: "S1", tC: 28.0, uMag: 0.10, pmv: 0.0),
        FeasibilitySeat(id: "S2", tC: 24.5, uMag: 0.40, pmv: 0.0),
        FeasibilitySeat(id: "S3", tC: 24.5, uMag: 0.10, pmv: 0.9),
    ]
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(metric(metrics, "seat_pass_ratio")?.omitted == false)
    #expect(metric(metrics, "seat_pass_ratio")?.value == 0)
    #expect(metric(metrics, "seat_eval_count")?.value == 3)
    let reason = metric(metrics, "infeasibleReason")?.reason ?? ""
    #expect(metric(metrics, "infeasibleReason")?.omitted == false)
    #expect(reason.contains("温度门"))
    #expect(reason.contains("风速门"))
    #expect(reason.contains("PMV门"))
    let blob = metrics.map { ($0.reason ?? "") + $0.name }.joined(separator: " ")
    #expect(!blob.contains("推荐方案"))
    #expect(!blob.contains("满意率"))
    #expect(SeatFeasibility.coverageText(metrics: metrics) == "3 个中 0 个合适")
}

@Test func comparisonLabelsAreModelCoverageNotSatisfactionRate() {
    let rows = SeatFeasibility.comparisonRows(metrics: SeatFeasibility.metrics(seats: inBand, qualityPassed: true))
    #expect(rows.contains { $0.label == SeatFeasibility.coverageLabel })
    for row in rows {
        #expect(!row.label.contains("满意率"))
        #expect(!row.value.contains("满意率"))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(row.label))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(row.value))
        // The default line never carries the metrology note or a gate name.
        #expect(!row.value.contains("低速绝对误差"))
        #expect(!row.value.contains("温度门"))
        #expect(!row.value.contains("PMV门"))
    }
    #expect(rows[0].value == "4 个中 4 个合适")
    let worst = rows.first { $0.label == SeatFeasibility.worstSeatLabel }
    #expect(worst?.value.contains("座位 4") == true)
    #expect(worst?.value.contains("S4") != true)
    // All seats passed: the line must say the seat is still suitable.
    #expect(worst?.value == "座位 4 相对最偏离目标温度，约 23.10 °C，但仍合适")
}

@Test func bandEdgesPassAndSpeedBreaksATemperatureTie() {
    let seats = [
        FeasibilitySeat(id: "S1", tC: 23.0, uMag: 0.10, pmv: 0.0),
        FeasibilitySeat(id: "S2", tC: 26.0, uMag: 0.25, pmv: 0.0),
    ]
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(metric(metrics, "seat_pass_ratio")?.value == 1)
    #expect(metric(metrics, "worst_seat_id")?.reason == "S2")
}

@Test func temperatureAndPmvBothFailShowOnlyTemperatureByDefault() {
    // Two gates failing must not read as the same complaint twice:
    // the default line names temperature; the PMV evidence goes to the
    // disclosure via worstSeatEvidenceText.
    var seats = inBand
    seats[3] = FeasibilitySeat(id: "S4", tC: 27.0, uMag: 0.05, pmv: 0.9)
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    let text = SeatFeasibility.worstSeatText(metrics: metrics)
    #expect(text == "座位 4 偏热，约 27.00 °C")
    #expect(!text.contains("整体"))
    let evidence = SeatFeasibility.worstSeatEvidenceText(metrics: metrics) ?? ""
    #expect(evidence.contains("空气温度超出"))
    #expect(evidence.contains("整体冷热感觉超出合适范围"))
}

@Test func speedGateAloneShowsAWindSentenceWithTheNumber() {
    var seats = inBand
    // 23.0 °C passes (inclusive edge); only the speed gate fails.
    seats[3] = FeasibilitySeat(id: "S4", tC: 23.0, uMag: 0.40, pmv: 0.1)
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(SeatFeasibility.worstSeatText(metrics: metrics) == "座位 4 风偏大，约 0.40 m/s")
    let evidence = SeatFeasibility.worstSeatEvidenceText(metrics: metrics) ?? ""
    #expect(evidence.contains("风速超过 0.25 m/s"))
}

@Test func pmvGateAloneShowsTheOverallSensationDirection() {
    var seats = inBand
    // Air temperature and speed pass; only the overall sensation fails.
    seats[3] = FeasibilitySeat(id: "S4", tC: 23.1, uMag: 0.20, pmv: 0.8)
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(SeatFeasibility.worstSeatText(metrics: metrics) == "座位 4 整体偏热")
    // A cold PMV reads the other way.
    seats[3].pmv = -0.8
    let coldMetrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    #expect(SeatFeasibility.worstSeatText(metrics: coldMetrics) == "座位 4 整体偏凉")
}

@Test func lowSpeedMetrologyNoteStaysOutOfTheDefaultLine() {
    var seats = inBand
    seats[3] = FeasibilitySeat(id: "S4", tC: 27.0, uMag: 0.02, pmv: 0.2, lowSpeedAbsoluteError: true)
    let metrics = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
    let text = SeatFeasibility.worstSeatText(metrics: metrics)
    #expect(text == "座位 4 偏热，约 27.00 °C")
    #expect(!text.contains("低速绝对误差"))
    // The reading note is disclosed, not dropped.
    let evidence = SeatFeasibility.worstSeatEvidenceText(metrics: metrics) ?? ""
    #expect(evidence.contains("误差按绝对值看"))
}

@Test func legacyRowsWithoutWorstNumbersKeepAReadableSentence() {
    // Runs persisted before the number rows existed must still name a seat.
    let legacy = SeatFeasibility.metrics(seats: inBand, qualityPassed: true)
        .filter { !["worst_seat_t_c", "worst_seat_u_mag", "worst_seat_pmv"].contains($0.name) }
    #expect(SeatFeasibility.worstSeatText(metrics: legacy) == "座位 4 相对最偏离目标温度，但仍合适")
    // A failing gate without its number keeps the direction-free fallback.
    var seats = inBand
    seats[3] = FeasibilitySeat(id: "S4", tC: 27.0, uMag: 0.05, pmv: 0.2)
    let legacyHot = SeatFeasibility.metrics(seats: seats, qualityPassed: true)
        .filter { !["worst_seat_t_c", "worst_seat_u_mag", "worst_seat_pmv"].contains($0.name) }
    #expect(SeatFeasibility.worstSeatText(metrics: legacyHot) == "座位 4：偏热或偏冷")
}

@Test func omittedFieldHasNoWorstSeatEvidence() {
    let metrics = SeatFeasibility.metrics(seats: inBand, qualityPassed: false)
    #expect(SeatFeasibility.worstSeatText(metrics: metrics) == "不可评价")
    #expect(SeatFeasibility.worstSeatEvidenceText(metrics: metrics) == nil)
}
