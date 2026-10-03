import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuReporting

enum ConsumerFixture {
    static func project() throws -> ProjectDocument {
        let source = SourceRecord(kind: .user, reference: "/Users/private/room-photo.jpg", note: "Alice private home")
        func length(_ value: Double) -> Length { .known(value: value, source: source) }
        let room = Room(id: UUID(), name: "Private room", shape: try .init(RectangularRoom(dimensions:
            .init(width: length(6), depth: length(4), height: length(3)))), northAngle: .unknown(reason: "Private"),
            surfaces: SurfaceFace.allCases.map { .init(id: UUID(), face: $0) })
        let port = AirPort(id: UUID(), role: .supply, position: .init(x: 0.05, y: 2, z: 1.5), direction: .init(x: 1, y: 0, z: 0),
            area: .unknown(reason: "Unused"), volumeFlow: .unknown(reason: "Unused"), speed: .unknown(reason: "Unused"), density: .unknown(reason: "Unused"))
        let device = HVACDevice(id: UUID(), roomID: room.id, name: "Private device", position: port.position,
            definition: try .init(SingleSplit(coolingCapacity: .unknown(reason: "Unused"), electricalPower: .unknown(reason: "Unused"), cop: .unknown(reason: "Unused"))),
            ports: [port], supplyTemperature: .unknown(reason: "Unused"))
        var scenario = Scenario.unfinished(name: "Private baseline")
        scenario.inputs.hvac = [device]
        scenario.inputs.usage.seats = [.init(id: UUID(), roomID: room.id, name: "Alice", position: .init(x: 2, y: 2, z: 1.5), samples: [.init(id: UUID(), position: .init(x: 2, y: 2, z: 1.5))])]
        var second = scenario; second.id = UUID(); second.name = "Private candidate"
        second.inputs.hvac[0].ports[0].direction = .init(x: cos(.pi/6), y: sin(.pi/6), z: 0)
        var third = scenario; third.id = UUID(); third.name = "Private candidate 2"
        third.inputs.hvac[0].ports[0].direction = .init(x: cos(.pi/6), y: -sin(.pi/6), z: 0)
        return .init(id: UUID(), name: "Alice home", spaceType: .home, geometry: .init(rooms: [room]), scenarios: [scenario, second, third])
    }
    static func evidence(_ project: ProjectDocument, index: Int = 0) async throws -> FixedEstimateEvidence {
        let config = AnalysisConfiguration(payload: .airflowPreview(.init(pathCount: 16)), acceptedAssumptions: [.genericCone])
        let request = try AnalysisInputResolver().request(project: project, scenarioID: project.scenarios[index].id,
            method: .init(kind: .airflowPreview), configuration: config)
        let execution = try await AirflowPreviewExecutor().execute(request) { _ in }
        let result = LocalAnalysisResult(identity: request.identity, method: request.method, checks: execution.checks,
            assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: execution.payload)
        return .init(request: request, result: result, currentInputHash: request.identity.inputHash)
    }
}

@Test func suggestionsCarryPerSampleEvidenceAndRejectStale() async throws {
    let e = try await ConsumerFixture.evidence(ConsumerFixture.project())
    let cards = try PreviewRecommendationRules.suggestions(request: e.request, result: e.result, currentInputHash: e.result.identity.inputHash)
    #expect(cards.count == 1)
    #expect(cards[0].identity == e.result.identity)
    #expect(cards[0].sampleID != nil)
    #expect(cards[0].relation == .intersectsAssumedPath)
    #expect(cards[0].message.contains("当前假设路径"))
    #expect(throws: (any Error).self) { try PreviewRecommendationRules.suggestions(request: e.request, result: e.result, currentInputHash: String(repeating: "0", count: 64)) }
}

@Test func fixedThreeWayComparisonRejectsTamperingAndPreservesReferences() async throws {
    let project = try ConsumerFixture.project()
    let evidence = try await [ConsumerFixture.evidence(project, index: 0), ConsumerFixture.evidence(project, index: 1), ConsumerFixture.evidence(project, index: 2)]
    let snapshot = try ComparisonRecordCodec.snapshotFor(evidence, decisions: ["direction"])
    #expect(snapshot.runs.count == 3)
    #expect(snapshot.incomparableReasons.isEmpty)
    let codec = NativeAnalysisCodec()
    let record = try ComparisonRecordCodec.make(snapshot: snapshot, requests: evidence.map(\.request), results: evidence.map(\.result),
        inputFiles: Dictionary(uniqueKeysWithValues: try evidence.map { ($0.request.identity.runID, try codec.encodeRequest($0.request)) }),
        resultFiles: Dictionary(uniqueKeysWithValues: try evidence.map { ($0.result.identity.runID, try codec.encodeResult($0.result)) }))
    let encoded = try ComparisonRecordCodec.encode(record)
    #expect(try ComparisonRecordCodec.decode(encoded) == record)
    var body = try #require(JSONValue(data: encoded).fields)
    body["bodyHash"] = .string(String(repeating: "f", count: 64))
    #expect(throws: (any Error).self) { try ComparisonRecordCodec.decode(JSONValue.object(body).data()) }
    body["recordVersion"] = .number("2")
    #expect(throws: (any Error).self) { try ComparisonRecordCodec.decode(JSONValue.object(body).data()) }
}

@Test func redactedTextAndJSONUseFrozenValuesAndSeparateExportHash() async throws {
    let project = try ConsumerFixture.project(), e = try await ConsumerFixture.evidence(project)
    let cards = try PreviewRecommendationRules.suggestions(request: e.request, result: e.result, currentInputHash: e.result.identity.inputHash)
    let report = try LocalReportBuilder.build([.init(request: e.request, result: e.result, currentInputHash: e.currentInputHash, suggestions: cards)])
    let text = try LocalReportExporter.export(report, format: .plainText)
    let json = try LocalReportExporter.export(report, format: .evidenceSummary)
    #expect(text.exportHash == json.exportHash)
    #expect(text.exportHash != e.request.identity.inputHash)
    let content = String(decoding: text.data, as: UTF8.self) + String(decoding: json.data, as: UTF8.self)
    for secret in ["Alice", "Private room", "Private device", "/Users/", "room-photo.jpg"] { #expect(!content.contains(secret)) }
    #expect(content.contains(e.request.identity.runID.uuidString))
    #expect(content.contains("redactedFields"))
    var edited = project; edited.scenarios[0].name = "Later edit"
    #expect(try LocalReportExporter.export(report, format: .plainText).data == text.data)
    let historical = try LocalReportBuilder.build([.init(request: e.request, result: e.result, currentInputHash: nil)])
    #expect(historical.runs[0].historical)
    #expect(!report.runs[0].historical)
}

@Test func contractExportForIndependentPythonValidation() async throws {
    guard let directory = ProcessInfo.processInfo.environment["SIMUNOW_CONSUMER_OUTPUT_DIR"] else { return }
    let root = URL(fileURLWithPath: directory); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let project = try ConsumerFixture.project()
    let evidence = try await [ConsumerFixture.evidence(project, index: 0), ConsumerFixture.evidence(project, index: 1)]
    let snapshot = try ComparisonRecordCodec.snapshotFor(evidence, decisions: ["direction"])
    let codec = NativeAnalysisCodec()
    let record = try ComparisonRecordCodec.make(snapshot: snapshot, requests: evidence.map(\.request), results: evidence.map(\.result),
        inputFiles: Dictionary(uniqueKeysWithValues: try evidence.map { ($0.request.identity.runID, try codec.encodeRequest($0.request)) }),
        resultFiles: Dictionary(uniqueKeysWithValues: try evidence.map { ($0.result.identity.runID, try codec.encodeResult($0.result)) }))
    try ComparisonRecordCodec.encode(record).write(to: root.appendingPathComponent("comparison-record.json"))
    let dataset = try MeasurementCSVImporter.importCSV(Data((MeasurementCSVImporter.template + "2026-10-03T15:00:00+08:00,1,2,1,temperature,298.15,K,thermometer,valid,,low,closed,closed,validation,,0-50 C,checked\n").utf8), projectID: project.id)
    try MeasurementDatasetCodec.encode(dataset).write(to: root.appendingPathComponent("measurement-dataset.json"))
    let calibrationInput = try CalibrationFixture.input()
    let calibrated = try FiniteJetCalibration.calibrate(calibrationInput)
    try MeasurementDatasetCodec.encode(calibrationInput.dataset).write(to: root.appendingPathComponent("jet-calibration-dataset.json"))
    try JSONTreeCoding.encode(calibrated).data().write(to: root.appendingPathComponent("jet-calibration.json"))
    let report = try LocalReportBuilder.build(evidence.map { .init(request: $0.request, result: $0.result, currentInputHash: $0.currentInputHash) }, comparison: snapshot)
    try LocalReportExporter.export(report, format: .evidenceSummary).data.write(to: root.appendingPathComponent("redacted-report.json"))
    try MeasurementSummaryExporter.export(dataset).write(to: root.appendingPathComponent("redacted-measurements.json"))
    let review = ProfessionalReviewConfiguration(endpoint: "https://review.example.invalid/v1/review", expectedEngine: "fixture-only", expectedVersion: "1", retentionPolicy: "not a deployed endpoint")
    try JSONTreeCoding.encode(review).data().write(to: root.appendingPathComponent("professional-review-configuration.json"))
    let receipt = ProfessionalReviewReceipt(runID: evidence[0].result.identity.runID, inputHash: evidence[0].result.identity.inputHash,
        engine: "fixture-only", engineVersion: "1", qualityPassed: true, benchmarkReference: "synthetic contract fixture",
        resultReference: "https://review.example.invalid/fixture")
    try JSONTreeCoding.encode(receipt).data().write(to: root.appendingPathComponent("professional-review-receipt.json"))
}
