import Foundation
import Testing
@testable import SimuCore
@testable import SimuReporting
@testable import SimuSimulation
@testable import SimuWorkspace

struct ReportTests {
    private func fixtureProject() throws -> ProjectDocument {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try ProjectCodec(registry: .builtIn)
            .decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    }

    private func completedRecord(scenarioID: UUID, hash: String) -> RunRecord {
        let result = RunResult(
            identity: RunIdentity(runID: UUID(uuidString: "3392F7E1-1234-4000-8000-0000000000AB")!,
                                  scenarioID: scenarioID, inputHash: hash),
            fidelity: .l0, state: .completed,
            metrics: [
                RunMetric(name: "averageRoomTemperature", value: .number("25.0"), unit: "degC",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
                RunMetric(name: "estimatedElectricEnergy", value: .number("2.97"), unit: "kWh",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
                RunMetric(name: "capacityAdequate", value: .bool(true), unit: "1",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
                RunMetric(name: "dailyCost", value: nil, unit: "currency", missingReason: "缺少币种或电价；不编造费用",
                          aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
            ],
            quality: RunQuality(state: .passed, checks: []),
            assumptions: ["L0 集总平均模型：单房间稳态热平衡，无逐点分布（不能替代 CFD）。"],
            startedAt: "2026-10-03T01:00:00.000Z", finishedAt: "2026-10-03T01:00:01.000Z")
        return RunRecord(identity: result.identity, fidelity: .l0, status: .completed, events: [],
                         result: result, errorMessage: nil,
                         runDirectory: URL(fileURLWithPath: "/tmp/simunow-test"), startedAt: Date())
    }

    @Test func contentIncludesRunIdentityAndHonestMissing() throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        let hash = "h1"
        let record = completedRecord(scenarioID: scenarioID, hash: hash)
        let rows = ComparisonModel.rows(project: project, records: [record], currentHashes: [scenarioID: hash])
        let cards = ComparisonModel.cards(rows: rows)
        let content = try #require(ReportBuilder.content(project: project, rows: rows, cards: cards))
        #expect(content.entries.count == 1)
        let entry = content.entries[0]
        #expect(entry.runID == "3392F7E1-1234-4000-8000-0000000000AB")
        #expect(entry.inputHash == "h1")
        #expect(entry.fidelity.contains("L0"))
        let cost = try #require(entry.metrics.first { $0.title == "日费用" })
        #expect(cost.value.contains("缺失"))
        #expect(!cost.value.contains("0.0"))
        #expect(content.scopeStatements.contains { $0.contains("不是逐点 CFD") })
        #expect(content.limitations.contains { $0.contains("L2") })
        #expect(!content.unknownsAndAssumptions.isEmpty)  // fixture carries assumed sources
    }

    @Test func staleOrFailedRunsAreExcludedFromReport() throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        // Stale: current hash moved on after the run.
        let stale = completedRecord(scenarioID: scenarioID, hash: "old-hash")
        let rows = ComparisonModel.rows(project: project, records: [stale], currentHashes: [scenarioID: "new-hash"])
        #expect(ReportBuilder.content(project: project, rows: rows, cards: []) == nil)
    }

    @Test func exportBlockedWithoutEligibleContent() async throws {
        let project = try fixtureProject()
        // No runs at all → no content snapshot.
        #expect(ReportBuilder.content(project: project, rows: [], cards: []) == nil)
        // Exporting an empty report throws instead of producing a hollow document.
        let content = ReportContent(projectName: project.name, generatedAt: Date(),
                                    scopeStatements: ReportBuilder.scopeStatements, entries: [],
                                    cards: [], unknownsAndAssumptions: [], limitations: ReportBuilder.limitations)
        do {
            _ = try await BasicReportExporter().export(content, to: URL(fileURLWithPath: "/tmp/simunow-should-not-exist.pdf"))
            Issue.record("An empty report must not be exportable.")
        } catch {
            #expect(error as? BasicReportExporter.ExportError == .noEligibleContent)
        }
    }

    @Test func pdfExportProducesValidDocument() async throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        let hash = "h1"
        let record = completedRecord(scenarioID: scenarioID, hash: hash)
        let rows = ComparisonModel.rows(project: project, records: [record], currentHashes: [scenarioID: hash])
        let content = try #require(ReportBuilder.content(project: project, rows: rows,
                                                         cards: ComparisonModel.cards(rows: rows)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-report-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await BasicReportExporter().export(content, to: url)
        let data = try Data(contentsOf: url)
        #expect(data.count > 1000)
        #expect(data.prefix(5) == Data("%PDF-".utf8))
        #expect(data.suffix(32).contains(Data("EOF".utf8)))
        // Pagination sanity: at least one page object.
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/Type /Page") || text.contains("/Type/Page"))
    }
}
