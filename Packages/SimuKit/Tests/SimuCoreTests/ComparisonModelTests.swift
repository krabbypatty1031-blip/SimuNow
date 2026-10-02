import Foundation
import Testing
@testable import SimuCore
@testable import SimuSimulation
@testable import SimuWorkspace

@MainActor
struct ComparisonModelTests {
    private func fixtureProject() throws -> ProjectDocument {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try ProjectCodec(registry: .builtIn)
            .decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    }

    private func result(_ electric: Double, adequate: Bool = true, quality: QualityState = .passed) -> RunResult {
        RunResult(
            identity: RunIdentity(scenarioID: UUID(), inputHash: "x"), fidelity: .l0, state: .completed,
            metrics: [
                RunMetric(name: "estimatedElectricEnergy", value: .number("\(electric)"), unit: "kWh",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
                RunMetric(name: "capacityAdequate", value: .bool(adequate), unit: "1",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
                RunMetric(name: "coolingLoadPeak", value: .number("371.2"), unit: "W",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
            ],
            quality: RunQuality(state: quality, checks: []),
            assumptions: ["L0 集总平均模型"], startedAt: "2026-10-03T01:00:00.000Z",
            finishedAt: "2026-10-03T01:00:01.000Z")
    }

    private func record(_ scenarioID: UUID, hash: String, status: RunStatus = .completed,
                        result: RunResult) -> RunRecord {
        RunRecord(identity: RunIdentity(runID: UUID(), scenarioID: scenarioID, inputHash: hash),
                  fidelity: .l0, status: status, events: [],
                  result: result, errorMessage: nil,
                  runDirectory: URL(fileURLWithPath: "/tmp/simunow-test"), startedAt: Date())
    }

    @Test func eligibilityRequiresCompletePassedAndCurrent() throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        let currentHash = "h-current"
        let eligible = ComparisonModel.eligibility(of: record(scenarioID, hash: currentHash, result: result(2.0)),
                                                   currentHash: currentHash)
        #expect(eligible == .eligible)
        #expect(ComparisonModel.eligibility(of: record(scenarioID, hash: "old", result: result(2.0)),
                                            currentHash: currentHash) == .stale)
        #expect(ComparisonModel.eligibility(of: record(scenarioID, hash: currentHash,
                                                       result: result(2.0, quality: .failed)),
                                            currentHash: currentHash) == .qualityFailed)
        #expect(ComparisonModel.eligibility(of: record(scenarioID, hash: currentHash, status: .cancelled,
                                                       result: result(2.0)),
                                            currentHash: currentHash) == .notCompleted(.cancelled))
        #expect(ComparisonModel.eligibility(of: nil, currentHash: currentHash) == .noRun)
    }

    @Test func basisGroupsByEnvironmentAndUsage() throws {
        let project = try fixtureProject()
        var otherWeather = project.scenarios[0]
        otherWeather.id = UUID()
        otherWeather.inputs.environment.outdoorTemperature = .known(value: 30, source: .init(kind: .user))
        var twoScenarios = project
        twoScenarios.scenarios.append(otherWeather)
        let hash = "h"
        let records = [
            record(project.scenarios[0].id, hash: hash, result: result(2.0)),
            record(otherWeather.id, hash: hash, result: result(1.5)),
        ]
        let rows = ComparisonModel.rows(project: twoScenarios, records: records,
                                        currentHashes: [project.scenarios[0].id: hash, otherWeather.id: hash])
        #expect(rows.allSatisfy { $0.eligibility == .eligible })
        let (_, members, excluded) = ComparisonModel.mainBasisGroup(rows: rows)
        // Different weather → different basis: the pair never ranks against each other.
        #expect(members.count == 1)
        #expect(excluded.count == 1)
    }

    @Test func operationCardPicksLowestElectricWithRunReference() throws {
        let project = try fixtureProject()
        var second = project.scenarios[0]
        second.id = UUID()
        second.name = "候选 +1°C"
        var two = project
        two.scenarios.append(second)
        let hash = "h"
        let cheap = record(second.id, hash: hash, result: result(1.8))
        let rows = ComparisonModel.rows(project: two,
                                        records: [record(project.scenarios[0].id, hash: hash, result: result(2.6)), cheap],
                                        currentHashes: [project.scenarios[0].id: hash, second.id: hash])
        let cards = ComparisonModel.cards(rows: rows)
        let operation = try #require(cards.first { $0.kind == .operation })
        #expect(operation.body.contains("候选 +1°C"))
        #expect(operation.body.contains("1.8 kWh"))
        #expect(operation.body.contains(String(cheap.identity.runID.uuidString.prefix(8))))
        #expect(operation.body.contains("L0 平均估算"))
        #expect(operation.runID == cheap.identity.runID)
        // Comfort card is an honest status, never a claim.
        let comfort = try #require(cards.first { $0.kind == .comfort })
        #expect(comfort.body.contains("L2"))
        #expect(!comfort.body.contains("PMV 达标"))
    }

    @Test func capacityCardReportsUndersizedPeak() throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        let rows = ComparisonModel.rows(project: project,
                                        records: [record(scenarioID, hash: "h", result: result(2.0, adequate: false))],
                                        currentHashes: [scenarioID: "h"])
        let capacity = try #require(ComparisonModel.cards(rows: rows).first { $0.kind == .capacity })
        #expect(capacity.body.contains("371.2 W"))
        #expect(capacity.body.contains("容量不足"))
    }

    @Test func noEligibleRunsProducesExplanationNotRecommendation() throws {
        let project = try fixtureProject()
        let rows = ComparisonModel.rows(project: project, records: [], currentHashes: [:])
        let cards = ComparisonModel.cards(rows: rows)
        #expect(cards.count == 1)
        #expect(cards[0].title == "尚无有效结果可用于建议")
        #expect(cards[0].runID == nil)
    }

    @Test func setpointCandidatesKeepIdentityAndSkipUnknown() throws {
        let project = try fixtureProject()
        let scenario = project.scenarios[0]
        let candidates = ComparisonModel.setpointCandidates(of: scenario)
        #expect(candidates.count == 2)
        for candidate in candidates {
            #expect(candidate.id != scenario.id)
            #expect(candidate.inputs.usage.seats.map(\.id) == scenario.inputs.usage.seats.map(\.id))
            #expect(candidate.inputs.hvac.map(\.id) == scenario.inputs.hvac.map(\.id))
        }
        let setpoints = candidates.compactMap { $0.inputs.controls.first?.setpoint.value }.sorted()
        #expect(setpoints == [24, 26])  // fixture setpoint is 25 °C
        var unknownSetpoint = scenario
        unknownSetpoint.inputs.controls[0].setpoint = .unknown(reason: "No thermostat reading")
        #expect(ComparisonModel.setpointCandidates(of: unknownSetpoint).isEmpty)
    }
}
