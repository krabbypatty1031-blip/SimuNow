import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuReporting

@Test func measurementSummaryRemovesPrivateIdentifiersAndKeepsEvidenceValues() throws {
    let input = try CalibrationFixture.input()
    let bytes = try MeasurementSummaryExporter.export(input.dataset)
    let text = String(decoding: bytes, as: UTF8.self)
    #expect(!text.contains(input.dataset.projectID.uuidString))
    #expect(!text.contains(input.deviceID.uuidString))
    #expect(!text.contains(input.dataset.records[0].instrument))
    #expect(!text.contains(input.dataset.records[0].timestamp))
    let envelope = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let snapshot = try #require(envelope["snapshot"] as? [String: Any])
    let rows = try #require(snapshot["records"] as? [[String: Any]])
    #expect(rows.count == input.dataset.records.count)
    #expect(rows[0]["value"] as? Double == 4)
    #expect(rows.allSatisfy { $0["position"] == nil && $0["timestamp"] == nil })
    #expect((envelope["exportHash"] as? String)?.count == 64)
}

@Test func measurementTimeZoneUnitsQuotedFieldsAndMissingStayExplicit() throws {
    #expect(MeasurementDatasetCodec.timestamp("2026-02-30T15:00:00Z") == nil)
    #expect(MeasurementDatasetCodec.timestamp("2024-02-29T15:00:00.123+08:00") != nil)
    let csv = MeasurementCSVImporter.template
        + "2026-10-03T15:00:00+08:00,1,2,1,temperature,298.15,K,\"meter, one\",valid,,low,closed,closed,validation,,0-50 C,checked\r\n"
        + "2026-10-03T07:00:00Z,,,,electricalPower,1.2,kW,power,valid,,low,closed,closed,unassigned,,,\n"
        + "2026-10-03T15:00:00,1,2,1,airSpeed,1,m/s,meter,valid,,low,closed,closed,calibration,,,\n"
        + "2026-10-03T07:00:00Z,1,2,1,airSpeed,,m/s,meter,missing,no reading,low,closed,closed,calibration,,,\n"
    let dataset = try MeasurementCSVImporter.importCSV(Data(csv.utf8), projectID: UUID())
    #expect(dataset.records.count == 3)
    #expect(dataset.issues.count == 1)
    #expect(dataset.issues[0].row == 4)
    #expect(abs(dataset.records[0].value! - 25) < 1e-10)
    #expect(dataset.records[0].instrument == "meter, one")
    #expect(dataset.records[1].value == 1200)
    #expect(dataset.records[2].value == nil)
    #expect(MeasurementDatasetCodec.timestamp(dataset.records[0].timestamp) == MeasurementDatasetCodec.timestamp(dataset.records[1].timestamp))
    #expect(try MeasurementDatasetCodec.decode(MeasurementDatasetCodec.encode(dataset)) == dataset)
}

@Test func projectionResolutionBenchmarkRecordsConservationAndResourceEvidence() throws {
    var rows: [[String: Any]] = []
    for n in [8, 16, 32] {
        let dx = 1.0 / Double(n)
        var u = Array(repeating: 0.0, count: (n + 1) * n)
        for y in 0..<n { for x in 1..<n { u[y * (n + 1) + x] = sin(.pi * Double(x) / Double(n)) * sin(.pi * (Double(y) + 0.5) / Double(n)) } }
        let result = try PressureProjectionExperiment.run(columns: n, rows: n, cellWidth: dx, timeStep: 0.01, density: 1.2,
            horizontalFaceVelocity: u, verticalFaceVelocity: Array(repeating: 0, count: n * (n + 1)), fluidMask: Array(repeating: true, count: n * n), maximumIterations: 5000)
        #expect(result.converged && result.finalMaximumDivergence <= 1e-6)
        #expect(result.estimatedArrayBytes < 1024 * 1024)
        rows.append(["resolution": n, "elapsedSeconds": result.elapsedSeconds, "iterations": result.iterations,
            "estimatedArrayBytes": result.estimatedArrayBytes, "initialMaximumDivergence": result.initialMaximumDivergence,
            "finalMaximumDivergence": result.finalMaximumDivergence, "source": "synthetic closed-box sine velocity; no field measurements"])
    }
    if let directory = ProcessInfo.processInfo.environment["SIMUNOW_CONSUMER_OUTPUT_DIR"] {
        let root = URL(fileURLWithPath: directory); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted]).write(to: root.appendingPathComponent("n6-grid-benchmark.json"))
    }
}

@Test func measurementMalformedQuotesNonfiniteUnitsAndFutureVersionFail() throws {
    #expect(throws: (any Error).self) { try MeasurementCSVImporter.importCSV(Data("timestamp,\"bad".utf8), projectID: UUID()) }
    let csv = MeasurementCSVImporter.template
        + "2026-10-03T07:00:00Z,1,2,1,airSpeed,NaN,m/s,meter,valid,,low,closed,closed,calibration,,,\n"
        + "2026-10-03T07:00:00Z,1,2,1,airSpeed,5,W,meter,valid,,low,closed,closed,calibration,,,\n"
    let dataset = try MeasurementCSVImporter.importCSV(Data(csv.utf8), projectID: UUID())
    #expect(dataset.records.isEmpty); #expect(dataset.issues.count == 2)
    var fields = try #require(JSONTreeCoding.encode(dataset).fields); fields["datasetVersion"] = .number("2")
    #expect(throws: (any Error).self) { try MeasurementDatasetCodec.decode(JSONValue.object(fields).data()) }
    fields["datasetVersion"] = .number("1"); fields["surprise"] = .bool(true)
    #expect(throws: (any Error).self) { try MeasurementDatasetCodec.decode(JSONValue.object(fields).data()) }
}

enum CalibrationFixture {
    static func input(validationScale: Double = 1, duplicateHoldout: Bool = false) throws -> FiniteJetCalibrationInput {
        let project = UUID(), device = UUID()
        func row(position: Position3D?, quantity: MeasurementQuantity, value: Double, partition: MeasurementPartition, timestamp: String = "2026-10-03T07:00:00Z") -> MeasurementRecord {
            .init(timestamp: timestamp, position: position, quantity: quantity, value: value, instrument: "synthetic-anemometer",
                instrumentRange: "0-10 m/s", instrumentCalibration: "analytical fixture, not field measurement",
                quality: .valid, fanSetting: "fixed-test-setting", doorState: .closed, windowState: .closed, partition: partition, deviceID: device)
        }
        var records = [row(position: nil, quantity: .outletSpeed, value: 4, partition: .calibration)]
        let points: [(Double, Double)] = [(0.5,0), (0.5,0.15), (1,0), (1,0.2), (2,0), (2,0.3)]
        func speed(_ axial: Double, _ radial: Double) -> Double { 4/(1+0.21*axial)*exp(-pow(radial/(0.05+0.1*axial),2)) }
        for (axial,radial) in points { records.append(row(position: .init(x: axial,y: radial,z: 0), quantity: .airSpeed, value: speed(axial,radial), partition: .calibration)) }
        for (axial,radial) in duplicateHoldout ? Array(points.prefix(3)) : [(0.7,0.1), (1.3,0.15), (1.8,0.25)] {
            records.append(row(position: .init(x: axial,y: radial,z: 0), quantity: .airSpeed, value: speed(axial,radial)*validationScale, partition: .validation))
        }
        let dataset = MeasurementDataset(projectID: project, sourceSHA256: String(repeating: "a", count: 64), records: records, issues: [])
        return .init(dataset: dataset, deviceID: device, geometrySHA256: String(repeating: "b", count: 64), origin: .init(x: 0,y: 0,z: 0),
            direction: .init(x: 1,y: 0,z: 0), outletRadiusMeters: 0.05, maximumDistanceMeters: 3, maximumValidationRMSE: 0.1)
    }
}

@Test func calibrationUsesOnlyTrainingAndRejectsLeakedHoldout() throws {
    let fixture = try CalibrationFixture.input()
    let fit = try FiniteJetCalibration.calibrate(fixture)
    let bad = try FiniteJetCalibration.calibrate(CalibrationFixture.input(validationScale: 5))
    #expect(abs(fit.spreadingRate - 0.1) < 1e-10)
    #expect(abs(fit.decayRatePerMeter - 0.21) < 1e-10)
    #expect(fit.spreadingRate == bad.spreadingRate && fit.decayRatePerMeter == bad.decayRatePerMeter)
    #expect(fit.acceptedForScopedResearch)
    #expect(!bad.acceptedForScopedResearch)
    #expect(fit.maximumDistanceMeters == 2)
    let model = try ScopedFiniteJetModel.verified(record: fit, dataset: fixture.dataset)
    #expect(try FiniteJetCalibration.speed(model: model, projectID: fit.projectID, deviceID: fit.deviceID,
        geometrySHA256: fit.geometrySHA256, fanSetting: fit.fanSetting, currentOutletOrigin: fit.origin, currentOutletDirection: fit.direction, position: .init(x: 1, y: 0, z: 0)) > 0)
    var forged = try JSONSerialization.jsonObject(with: JSONTreeCoding.encode(fit).data()) as! [String: Any]
    forged["spreadingRate"] = 0.3
    let altered = try JSONTreeCoding.decode(JetCalibrationRecord.self, from: JSONValue(data: JSONSerialization.data(withJSONObject: forged)))
    #expect(throws: (any Error).self) { try ScopedFiniteJetModel.verified(record: altered, dataset: fixture.dataset) }
    #expect(throws: (any Error).self) { try FiniteJetCalibration.calibrate(CalibrationFixture.input(duplicateHoldout: true)) }
    #expect(throws: (any Error).self) { try FiniteJetCalibration.speed(model: ScopedFiniteJetModel.verified(record: fit, dataset: fixture.dataset), projectID: fit.projectID, deviceID: fit.deviceID,
        geometrySHA256: String(repeating: "c", count: 64), fanSetting: fit.fanSetting, currentOutletOrigin: fit.origin, currentOutletDirection: fit.direction, position: .init(x: 1,y: 0,z: 0)) }
}

@Test func dynamicsMatchesAnalyticalCoolingAndCO2WithTimeStepIndependence() throws {
    let c = RoomDynamicsConfiguration(roomVolumeCubicMeters: 100, heatCapacityJoulesPerKelvin: 100_000,
        envelopeConductanceWattsPerKelvin: 100, outdoorExchangeCubicMetersPerSecond: 0.1,
        airVolumetricHeatCapacityJoulesPerCubicMeterKelvin: 1200, initialTemperatureDegC: 30, initialCO2PPM: 1000)
    let interval = RoomDynamicsInterval(durationSeconds: 1000, outdoorTemperatureDegC: 20, internalSensibleWatts: 100,
        deliveredSensibleCoolingWatts: 100, outdoorCO2PPM: 400, co2SourceCubicMetersPerSecond: 0)
    let coarse = try #require(RoomDynamicsExperiment.run(c, intervals: [interval], outputStepSeconds: 100).last)
    let fine = try #require(RoomDynamicsExperiment.run(c, intervals: [interval], outputStepSeconds: 10).last)
    #expect(abs(coarse.roomMeanTemperatureDegC - (20+10*exp(-2.2))) < 1e-10)
    #expect(abs(coarse.roomMeanCO2PPM - (400+600*exp(-1))) < 1e-10)
    #expect(abs(coarse.roomMeanTemperatureDegC - fine.roomMeanTemperatureDegC) < 1e-10)
    #expect(abs(coarse.roomMeanCO2PPM - fine.roomMeanCO2PPM) < 1e-10)
}

@Test func sealedRoomConservesThermalAndCO2SourcesAndBudgetsOutput() throws {
    let c = RoomDynamicsConfiguration(roomVolumeCubicMeters: 100, heatCapacityJoulesPerKelvin: 100_000,
        envelopeConductanceWattsPerKelvin: 0, outdoorExchangeCubicMetersPerSecond: 0,
        airVolumetricHeatCapacityJoulesPerCubicMeterKelvin: 1200, initialTemperatureDegC: 20, initialCO2PPM: 400)
    let interval = RoomDynamicsInterval(durationSeconds: 1000, outdoorTemperatureDegC: 0, internalSensibleWatts: 100,
        deliveredSensibleCoolingWatts: 0, outdoorCO2PPM: 0, co2SourceCubicMetersPerSecond: 1e-6)
    let end = try #require(RoomDynamicsExperiment.run(c, intervals: [interval], outputStepSeconds: 100).last)
    #expect(abs(end.roomMeanTemperatureDegC - 21) < 1e-10)
    #expect(abs(end.roomMeanCO2PPM - 410) < 1e-10)
    #expect(throws: (any Error).self) { try RoomDynamicsExperiment.run(c, intervals: [interval,interval], outputStepSeconds: 0.1) }
}

@Test func pressureProjectionReducesDivergenceAndRespectsObstacleFaces() throws {
    let nx = 8, ny = 8
    var u = Array(repeating: 0.0, count: (nx+1)*ny), v = Array(repeating: 0.0, count: nx*(ny+1))
    for y in 0..<ny { for x in 1..<nx { u[y*(nx+1)+x] = sin(Double(x))*0.1 } }
    for y in 1..<ny { for x in 0..<nx { v[y*nx+x] = cos(Double(y))*0.1 } }
    var mask = Array(repeating: true, count: nx*ny); mask[3*nx+3] = false
    let result = try PressureProjectionExperiment.run(columns: nx, rows: ny, cellWidth: 0.25, timeStep: 0.1, density: 1.2,
        horizontalFaceVelocity: u, verticalFaceVelocity: v, fluidMask: mask)
    #expect(result.converged)
    #expect(result.finalMaximumDivergence < 1e-6)
    #expect(result.finalMaximumDivergence < result.initialMaximumDivergence)
    #expect(result.horizontalFaceVelocity[3*(nx+1)+3] == 0)
    #expect(result.horizontalFaceVelocity[3*(nx+1)+4] == 0)
    #expect(result.estimatedArrayBytes < 20_000)
}

@Test func adiabaticMaskedThermalGridConservesMeanAndRejectsUnstableStep() throws {
    let nx = 4, ny = 4, u = Array(repeating: 0.0,count: 20), v = Array(repeating: 0.0,count: 20)
    var mask = Array(repeating: true,count: 16); mask[5] = false
    var temperatures = Array(repeating: 20.0,count: 16); temperatures[0] = 30; temperatures[5] = 900
    let result = try ThermalGridExperiment.step(columns: nx, rows: ny, cellWidth: 1, timeStep: 0.1, density: 1.2,
        horizontalFaceVelocity: u, verticalFaceVelocity: v, fluidMask: mask, temperature: temperatures,
        diffusivitySquareMetersPerSecond: 0.1, thermalExpansionPerKelvin: 0, referenceTemperatureDegC: 20)
    #expect(abs(result.fluidMeanTemperatureDegC - (20+10.0/15)) < 1e-10)
    #expect(result.maximumTemperatureDegC < 30)
    #expect(result.minimumTemperatureDegC >= 20)
    #expect(throws: (any Error).self) { try ThermalGridExperiment.step(columns: nx, rows: ny, cellWidth: 1, timeStep: 10, density: 1.2,
        horizontalFaceVelocity: u, verticalFaceVelocity: v, fluidMask: mask, temperature: temperatures,
        diffusivitySquareMetersPerSecond: 0.1, thermalExpansionPerKelvin: 0, referenceTemperatureDegC: 20) }
}

@Test func professionalReviewNeverSubmitsWithoutPerRequestConfirmation() async throws {
    let e = try await ConsumerFixture.evidence(ConsumerFixture.project())
    let c = ProfessionalReviewConfiguration(endpoint: "https://example.invalid/review", expectedEngine: "test", expectedVersion: "1", retentionPolicy: "delete after review")
    await #expect(throws: (any Error).self) { try await ProfessionalReviewClient().submit(.init(configuration: c, request: e.request,
        confirmedInputHash: e.request.identity.inputHash, userConfirmedDataTransfer: false), bearerToken: "test") }
}
