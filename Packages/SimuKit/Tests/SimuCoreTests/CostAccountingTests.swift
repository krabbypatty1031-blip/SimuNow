import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

/// ADR-014: representative-day cost uses the demo tariff and occupied hours.
/// Currency is locked to millis; a missing input stays omitted, never 0.
@Test func demoTariffTimesTenOccupiedHoursLocksDayEnergyAndHKD() {
    #expect(CostAssumptions.demo.pricePerKWh == 1.2)
    #expect(CostAssumptions.demo.currency == "HKD")
    #expect(CostAssumptions.demo.source == .assumed)
    #expect(CostAssumptions.demo.reference == "比赛演示假设，非真实电价")
    #expect(CostAccounting.occupiedHours(start: "08:00", end: "18:00") == 10)

    let day = CostAccounting.representativeDay(
        electricPowerW: 1033.112,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: .demo
    )
    #expect(day.energyOmitted == false)
    #expect(day.costOmitted == false)
    #expect(String(format: "%.5f", day.energyKWh ?? -1) == "10.33112")
    #expect(String(format: "%.3f", day.cost ?? -1) == "12.397")
    #expect(day.currency == "HKD")
    #expect(day.electricPowerW == 1033.112)
    #expect(day.occupiedHours == 10)
    #expect(day.retrofitQuote == "待报价")
    #expect(day.cost != 0)
}

@Test func missingTariffOmitsCostDayButKeepsEnergy() {
    let day = CostAccounting.representativeDay(
        electricPowerW: 1033.112,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: nil
    )
    #expect(day.cost == nil)
    #expect(day.costOmitted == true)
    #expect(day.currency == nil)
    #expect(String(format: "%.5f", day.energyKWh ?? -1) == "10.33112")
    #expect(day.energyOmitted == false)
    #expect(day.cost != 0)
}

@Test func missingElectricPowerOmitsEnergyAndCost() {
    let day = CostAccounting.representativeDay(
        electricPowerW: nil,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: .demo
    )
    #expect(day.energyKWh == nil)
    #expect(day.cost == nil)
    #expect(day.energyOmitted == true)
    #expect(day.costOmitted == true)
    #expect(day.energyKWh != 0)
    #expect(day.cost != 0)
    #expect(day.retrofitQuote == "待报价")
}

@Test func missingOccupiedHoursOmitsEnergyAndCost() {
    let day = CostAccounting.representativeDay(
        electricPowerW: 1033.112,
        occupiedStart: nil,
        occupiedEnd: nil,
        tariff: .demo
    )
    #expect(day.energyKWh == nil)
    #expect(day.cost == nil)
    #expect(day.occupiedHours == nil)
    #expect(day.energyKWh != 0)
    #expect(day.cost != 0)
}

/// The accounting object must not carry a valued annual total or payback.
/// Absence is the contract; a filled number would invent a year.
@Test func dayCostJSONHasNoValuedAnnualOrPayback() throws {
    let day = CostAccounting.representativeDay(
        electricPowerW: 1033.112,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: .demo
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any]
    )
    for key in ["annual_kwh", "annualKWh", "payback_years", "paybackYears"] {
        let value = object[key]
        let valued = value != nil && !(value is NSNull)
        #expect(valued == false)
    }
    #expect(day.retrofitQuote == "待报价")
}

/// "更省电" is the difference of two L1-derived day costs. A basis mismatch
/// hides the figure. The delta is not one power times a fudge factor.
@Test func savingsComeFromTwoL1DayCostsAndHideWhenBasisDiffers() {
    let low = CostAccounting.representativeDay(
        electricPowerW: 1000,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: .demo
    )
    let high = CostAccounting.representativeDay(
        electricPowerW: 1500,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: .demo
    )
    let saved = CostAccounting.savingsHKD(high, low, basisMismatch: nil)
    #expect(String(format: "%.3f", saved ?? -1) == "6.000")
    #expect(saved == (high.cost ?? 0) - (low.cost ?? 0))
    #expect(CostAccounting.savingsHKD(high, low, basisMismatch: "口径不同（人数）") == nil)
    #expect(CostAccounting.savingsHKD(high, low, basisMismatch: nil) != 1500 * 0.1)
}

@MainActor
@Test func submitL2KeepsPreviousL1CoolingAndElectricity() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let l2 = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ]
    )
    let l1Client = RecordingL1Client()
    await l1Client.prepare(result: l1)
    let l2Client = RecordingL2Client()
    await l2Client.prepare(result: l2)
    let store = WorkspaceStore(l1Client: l1Client, l2Client: l2Client)
    store.loadOfficeTemplate()
    await store.submitL1()
    await store.submitL2()
    #expect(store.lastL1Result?.metric(named: "q_cool_w")?.value == 6000)
    #expect(store.lastL1Result?.metric(named: "p_elec_w")?.value == 2000)
    #expect(store.lastL2Result?.metric(named: "seat_t_c_min")?.value == 25.08)
    #expect(store.metricText(named: "q_cool_w").contains("6000"))
    #expect(store.metricText(named: "p_elec_w").contains("2000"))
    #expect(store.metricText(named: "seat_t_c_min").contains("25.08"))
    #expect(store.l1Freshness == .current)
}

@MainActor
@Test func staleL1WattsAreNotLabelledAsTheCurrentDraft() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let client = RecordingL1Client()
    await client.prepare(result: l1)
    let store = WorkspaceStore(l1Client: client)
    store.loadOfficeTemplate()
    await store.submitL1()
    store.applyOccupantCount(10)
    #expect(store.l1Freshness == .stale)
    #expect(store.metricText(named: "p_elec_w").contains("2000"))
    #expect(store.metricText(named: "p_elec_w").contains(UserFacingCopy.freshnessTitle(.stale)))
}

@MainActor
@Test func pinFreezesL1DayCostAndOmitsCostWhenL1IsMissing() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    var priced = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 3099.336)
    )
    // Lock the hand-measured office watt, not cooling/COP rounding.
    priced.metrics = [
        ResultMetric(name: "q_cool_w", value: 3099.336, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
        ResultMetric(name: "p_elec_w", value: 1033.112, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
        ResultMetric(name: "annual_kwh", value: nil, unit: "kWh", method: "not_modeled", fidelity: .l1, omitted: true)
    ]
    let l2 = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 24.5, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ]
    )
    let l1Client = RecordingL1Client()
    await l1Client.prepare(result: priced)
    let l2Client = RecordingL2Client()
    await l2Client.prepare(result: l2)
    let store = WorkspaceStore(l1Client: l1Client, l2Client: l2Client)
    store.loadOfficeTemplate()
    store.applyElectricityTariff(CostAssumptions.demo)
    await store.submitL1()
    await store.submitL2()
    #expect(store.canPinCandidate)
    store.pinCurrentAsCandidate(named: "基准")
    let frozen = try #require(store.candidateRuns.first?.dayCost)
    #expect(String(format: "%.5f", frozen.energyKWh ?? -1) == "10.33112")
    #expect(String(format: "%.3f", frozen.cost ?? -1) == "12.397")
    #expect(frozen.currency == "HKD")
    #expect(frozen.electricPowerW == 1033.112)
    #expect(frozen.retrofitQuote == "待报价")
    #expect(store.lastL1Result?.metric(named: "p_elec_w")?.value == 1033.112)

    let l2Only = RecordingL2Client()
    await l2Only.prepare(result: l2)
    let bare = WorkspaceStore(l2Client: l2Only)
    bare.loadOfficeTemplate()
    bare.applyElectricityTariff(CostAssumptions.demo)
    await bare.submitL2()
    bare.pinCurrentAsCandidate(named: "仅 L2")
    let omitted = try #require(bare.candidateRuns.first?.dayCost)
    #expect(omitted.cost == nil)
    #expect(omitted.energyKWh == nil)
    #expect(omitted.cost != 0)
    #expect(omitted.energyKWh != 0)
    #expect(omitted.retrofitQuote == "待报价")
}

@MainActor
@Test func mixedBasisHidesSavingsWhileStillShowingEachDayCost() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let l2 = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 24.5, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ]
    )
    let l1Client = RecordingL1Client()
    await l1Client.prepare(result: l1)
    let l2Client = RecordingL2Client()
    await l2Client.prepare(result: l2)
    let store = WorkspaceStore(l1Client: l1Client, l2Client: l2Client)
    store.loadOfficeTemplate()
    store.applyElectricityTariff(CostAssumptions.demo)
    await store.submitL1()
    await store.submitL2()
    store.pinCurrentAsCandidate(named: "基准")
    store.applyOccupantCount(12)
    var dearer = l1
    dearer.metrics = [
        ResultMetric(name: "q_cool_w", value: 4500, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
        ResultMetric(name: "p_elec_w", value: 1500, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
        ResultMetric(name: "annual_kwh", value: nil, unit: "kWh", method: "not_modeled", fidelity: .l1, omitted: true)
    ]
    await l1Client.prepare(result: dearer)
    await store.submitL1()
    await store.submitL2()
    store.pinCurrentAsCandidate(named: "多人")
    #expect(store.basisMismatchText != nil)
    #expect(store.comparisonSavingsText == nil)
    #expect(store.candidateRuns.count == 2)
    #expect(store.candidateRuns[0].dayCost.cost != store.candidateRuns[1].dayCost.cost)
    #expect(store.candidateRuns.allSatisfy { $0.dayCost.cost != nil })
    #expect(store.candidateRuns.allSatisfy { $0.dayCost.cost != 0 })
}

/// The tariff is a post-process. Changing it must not relabel the L1 watts
/// as a different physics draft, and the day cost follows the new price.
@MainActor
@Test func editingTariffKeepsL1WattsCurrentAndRepricesTheDay() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let client = RecordingL1Client()
    await client.prepare(result: l1)
    let store = WorkspaceStore(l1Client: client)
    store.loadOfficeTemplate()
    await store.submitL1()
    #expect(store.l1Freshness == .current)
    store.applyElectricityTariff(CostAssumptions(
        pricePerKWh: 1.5,
        currency: "HKD",
        source: .user,
        reference: "演示改价"
    ))
    #expect(store.l1Freshness == .current)
    #expect(!store.metricText(named: "p_elec_w").contains("非当前"))
    #expect(store.dayCostText() == "30.00 HKD")
}

/// Lowering the supply and re-running only L2 leaves L1 watts behind.
/// Pin still accepts the current L2, but the frozen L1 cost must not read as the current draft.
@MainActor
@Test func pinAfterSupplyHeightL2RerunMarksStaleL1Watts() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let l2 = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 24.5, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ]
    )
    let l1Client = RecordingL1Client()
    await l1Client.prepare(result: l1)
    let l2Client = RecordingL2Client()
    await l2Client.prepare(result: l2)
    let store = WorkspaceStore(l1Client: l1Client, l2Client: l2Client)
    store.loadOfficeTemplate()
    store.applyElectricityTariff(CostAssumptions.demo)
    await store.submitL1()
    await store.submitL2()
    let supply = try #require(store.project?.hvac?.supply)
    store.applySupplyTerminal(
        wall: supply.wall,
        s0: supply.s0.value,
        s1: supply.s1.value,
        z0: 2.10,
        z1: 2.28,
        source: .user
    )
    #expect(store.fieldIssues.isEmpty)
    #expect(store.l1Freshness == .stale)
    #expect(!store.canPinCandidate)
    await store.submitL2()
    #expect(store.l2Freshness == .current)
    #expect(store.l1Freshness == .stale)
    #expect(store.canPinCandidate)
    store.pinCurrentAsCandidate(named: "降低风口")
    let record = try #require(store.candidateRuns.first)
    #expect(record.dayCost.cost != nil)
    #expect(record.dayCost.cost != 0)
    #expect(record.dayCost.electricPowerW == 2000)
    #expect(record.dayCost.occupiedHours == 10)
    #expect(store.candidateFreshness(record) == .current)
    #expect(record.l1Identity?.inputHash != record.identity.inputHash)
    #expect(store.candidateL1Freshness(record) == .stale)
    let power = store.candidateL1PowerText(record)
    let cost = store.candidateL1CostText(record)
    #expect(power.contains(UserFacingCopy.freshnessTitle(.stale)))
    #expect(!power.contains("当前输入"))
    #expect(cost.contains(UserFacingCopy.freshnessTitle(.stale)))
    #expect(!cost.contains("当前输入"))
}

/// Same L1 watts priced at two tariffs are not a power saving.
/// A currency change is not a saving either, and no percent is invented.
@MainActor
@Test func sameWattsDifferentTariffOmitsSavingsFigure() async throws {
    let sameWatts = CostAccounting.representativeDay(
        electricPowerW: 1000,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: .demo
    )
    let repriced = CostAccounting.representativeDay(
        electricPowerW: 1000,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: CostAssumptions(pricePerKWh: 1.5, currency: "HKD", source: .user, reference: "演示改价")
    )
    let otherCurrency = CostAccounting.representativeDay(
        electricPowerW: 1000,
        occupiedStart: "08:00",
        occupiedEnd: "18:00",
        tariff: CostAssumptions(pricePerKWh: 2.4, currency: "USD", source: .user, reference: "演示换币")
    )
    #expect(sameWatts.cost != repriced.cost)
    #expect(CostAccounting.savingsHKD(repriced, sameWatts, basisMismatch: nil) == nil)
    #expect(CostAccounting.savingsHKD(otherCurrency, sameWatts, basisMismatch: nil) == nil)
    #expect(CostAccounting.savingsHKD(repriced, sameWatts, basisMismatch: "口径不同（人数）") == nil)

    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let l2 = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 24.5, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ]
    )
    let l1Client = RecordingL1Client()
    await l1Client.prepare(result: l1)
    let l2Client = RecordingL2Client()
    await l2Client.prepare(result: l2)
    let store = WorkspaceStore(l1Client: l1Client, l2Client: l2Client)
    store.loadOfficeTemplate()
    store.applyElectricityTariff(CostAssumptions.demo)
    await store.submitL1()
    await store.submitL2()
    store.pinCurrentAsCandidate(named: "基准")
    store.applyElectricityTariff(CostAssumptions(
        pricePerKWh: 1.5,
        currency: "HKD",
        source: .user,
        reference: "演示改价"
    ))
    #expect(store.l1Freshness == .current)
    await store.submitL2()
    store.pinCurrentAsCandidate(named: "改价")
    #expect(store.basisMismatchText == nil)
    #expect(store.candidateRuns.count == 2)
    #expect(store.candidateRuns[0].identity.runID != store.candidateRuns[1].identity.runID)
    #expect(store.candidateRuns[0].dayCost.electricPowerW == store.candidateRuns[1].dayCost.electricPowerW)
    #expect(store.candidateRuns[0].dayCost.cost != store.candidateRuns[1].dayCost.cost)
    #expect(store.comparisonSavingsText == nil)
}
