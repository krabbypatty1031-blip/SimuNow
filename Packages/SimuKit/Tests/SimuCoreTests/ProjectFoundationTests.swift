import Foundation
import Testing
import SimuCore
import SimuVisualization
import SimuWorkspace

private func fixture(_ name: String = "office") throws -> Data {
    var root = URL(fileURLWithPath:#filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try Data(contentsOf:root.appendingPathComponent("Fixtures/Contracts/\(name).json"))
}
private let codec = ProjectCodec(registry:.builtIn)

@Test func completeProjectAndSnapshotRoundTrips() throws {
    for name in ["office","classroom"] {
        let project = try codec.decode(fixture(name))
        #expect(try codec.decode(codec.encode(project)) == project)
        #expect(try ProjectValidator().validate(project,registry:.builtIn).issues.isEmpty)
        let snapshot = try ScenarioSnapshotBuilder.capture(project,scenarioID:project.scenarios[0].id)
        #expect(try codec.decodeSnapshot(codec.encodeSnapshot(snapshot)) == snapshot)
        var edited = project
        edited.geometry.rooms.removeAll()
        edited.scenarios[0].inputs.hvac[0].supplyTemperature = .known(value:99,source:.init(kind:.user))
        #expect(snapshot.geometry.rooms.count == 1)
        #expect(snapshot.inputs.hvac[0].supplyTemperature.value == 16)
        #expect(throws:(any Error).self) { try ScenarioSnapshotBuilder.capture(project,scenarioID:UUID()) }
    }
}
@Test func legacyMigrationInventsNoPhysicalDefaults() throws {
    let draft = ProjectDraft(name:"Legacy")
    let input = try JSONEncoder().encode(draft)
    let result = try ProjectMigrator.migrate(input)
    #expect(result.project.id == draft.id)
    #expect(result.project.geometry.rooms.isEmpty && result.project.scenarios.isEmpty)
    #expect(!result.notes.isEmpty)
    let report = try ProjectValidator().validate(result.project,registry:.builtIn)
    #expect(report.passes(.projectIntegrity)); #expect(!report.passes(.inputPreparation))
    #expect(try JSONDecoder().decode(ProjectDraft.self,from:input) == draft)
}
@Test func unsupportedPayloadIsLosslessAndBlocksPreparation() throws {
    var project = try codec.decode(fixture())
    let payload = try JSONValue(data:Data("{\"big\":1234567890123456789012345678901234567890,\"precise\":1.23456789012345678901234567890123456789,\"nested\":[null,true]}".utf8))
    project.scenarios[0].inputs.hvac[0].definition = .init(kind:"future.hvac",payloadVersion:999,payload:payload)
    let decoded = try codec.decode(codec.encode(project))
    #expect(decoded.scenarios[0].inputs.hvac[0].definition.payload == payload)
    let report = try ProjectValidator().validate(decoded,registry:.builtIn)
    #expect(report.passes(.projectIntegrity)); #expect(!report.passes(.inputPreparation))
    #expect(report.issues.contains { $0.code == "unsupported_type" })
}
@Test func parserRejectsAmbiguousAndNonJSONInputs() {
    for text in ["{\"x\":1,\"x\":2}","{\"x\":NaN}","{\"x\":Infinity}","[1,]","\"bad\\q\"","{} trailing"] {
        #expect(throws:(any Error).self) { try JSONValue(data:Data(text.utf8)) }
    }
}
@Test func physicalQuantitiesAreDistinctAndHeatIsNotDuplicated() throws {
    let project = try codec.decode(fixture())
    let supply: Temperature = project.scenarios[0].inputs.hvac[0].supplyTemperature
    let setpoint: Temperature = project.scenarios[0].inputs.controls[0].setpoint
    let split = try project.scenarios[0].inputs.hvac[0].definition.resolved(as:SingleSplit.self,registry:.builtIn)!
    let capacity: ThermalPower = split.coolingCapacity
    let electric: ElectricalPower = split.electricalPower
    #expect(supply.value == 16 && setpoint.value == 25)
    #expect(capacity.value == 3000 && electric.value == 1000)
    let gain = project.scenarios[0].inputs.usage.occupants[0].heat
    #expect(gain.sensible.value! * gain.convectiveFraction.value! == 48)
    #expect(gain.sensible.value! * (1-gain.convectiveFraction.value!) == 32)
}
@Test func coordinatesPreserveHandednessAndGravity() {
    let point = Position3D(x:2,y:3,z:4), direction = Direction3D(x:1,y:0,z:0), gravity = Displacement3D(x:0,y:0,z:-9.81)
    #expect(CoordinateTransform.toDomain(CoordinateTransform.toApple(point)) == point)
    #expect(CoordinateTransform.toDomain(CoordinateTransform.toApple(direction)) == direction)
    #expect(CoordinateTransform.toApple(gravity) == Displacement3D(x:0,y:-9.81,z:0))
    #expect(CoordinateTransform.toDomain(CoordinateTransform.toApple(gravity)) == gravity)
    // Domain X cross Y = Z; mapped Apple X cross -Z = Y.
    #expect(CoordinateTransform.toApple(Position3D(x:0,y:1,z:0)) == Position3D(x:0,y:0,z:-1))
}
@Test @MainActor func workspaceAcceptsInjectedModelServices() throws {
    let store = WorkspaceStore(modelRegistry:.builtIn,projectValidator:ProjectValidator())
    store.project = try codec.decode(fixture())
    #expect(store.project?.schemaVersion == 2)
    #expect(store.modelRegistry.registrations.count == 3)
}
@Test func adapterRequirementsCheckDayCoverage() throws {
    var project = try codec.decode(fixture())
    let path = "/scenarios/0/inputs/controls/0/schedule/intervals"
    let rule = InputRequirements(requiredPaths:["/scenarios/0/inputs/environment/weather"],fullDaySchedulePaths:[path])
    #expect(try rule.validate(project,registry:.builtIn).isEmpty)
    project.scenarios[0].inputs.controls[0].schedule.intervals[0].startMinute = 100
    #expect(try rule.validate(project,registry:.builtIn).first?.code == "schedule_coverage")
}
@Test func pythonAndSwiftExchange() throws {
    guard let path = ProcessInfo.processInfo.environment["SIMUNOW_CONTRACT_DIR"] else { return }
    let directory = URL(fileURLWithPath:path)
    let files = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
    for file in files where file.lastPathComponent.hasSuffix(".python.json") {
        let project = try codec.decode(Data(contentsOf:file))
        let snapshotFile = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent.replacingOccurrences(of:".python.",with:".python-snapshot."))
        let snapshot = try ScenarioSnapshotBuilder.capture(project,scenarioID:project.scenarios[0].id)
        #expect(try codec.decodeSnapshot(Data(contentsOf:snapshotFile)) == snapshot)
        try codec.encode(project).write(to:directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of:".python.",with:".swift.")))
        try codec.encodeSnapshot(snapshot).write(to:directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of:".python.",with:".swift-snapshot.")))
    }
    for file in files where file.lastPathComponent.hasSuffix(".invalid.json") {
        #expect(throws:(any Error).self, Comment(rawValue:file.lastPathComponent)) { try codec.decode(Data(contentsOf:file)) }
    }
    for file in files where file.lastPathComponent.hasSuffix(".case.json") {
        let project = try codec.decode(Data(contentsOf:file))
        let report = try ProjectValidator().validate(project,registry:.builtIn)
        let rows = report.issues.map { issue in JSONValue.array([.string(issue.code),.string(issue.path),.array(issue.blocks.map { .string($0.rawValue) })]) }
        let expected = try JSONValue(data:Data(contentsOf:directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of:".case.",with:".expected."))))
        #expect(try rows.map { try $0.text() }.sorted() == expected.items!.map { try $0.text() }.sorted(), Comment(rawValue:file.lastPathComponent))
        try codec.encode(project).write(to:directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of:".case.",with:".swift-case.")))
    }
    #if os(macOS)
    guard let python = ProcessInfo.processInfo.environment["SIMUNOW_PYTHON"] else { throw ProjectDataError.contract("Locked Python required for bidirectional exchange") }
    var root = URL(fileURLWithPath:#filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath:python)
    process.arguments = [root.appendingPathComponent("Backend/tests/contract_exchange.py").path,"return",path]
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    for name in ["office","classroom"] {
        let sent = try codec.decode(Data(contentsOf:directory.appendingPathComponent(name + ".swift.json")))
        #expect(try codec.decode(Data(contentsOf:directory.appendingPathComponent(name + ".python-return.json"))) == sent)
        #expect(try codec.decodeSnapshot(Data(contentsOf:directory.appendingPathComponent(name + ".python-return-snapshot.json"))) == ScenarioSnapshotBuilder.capture(sent,scenarioID:sent.scenarios[0].id))
    }
    #endif

}

@Test func semanticIssuesIdentifyStableEntities() throws {
    var project = try codec.decode(fixture())
    let seatID = project.scenarios[0].inputs.usage.seats[0].id
    project.scenarios[0].inputs.usage.seats[0].samples.removeAll()
    let issue = try ProjectValidator().validate(project,registry:.builtIn).issues.first { $0.code == "sample_required" }
    #expect(issue?.entityID == seatID)
}
@Test func wireSchemaDoesNotIgnoreTypedAdditionalProperties() {
    let schema = JSONValue.object(["type":.string("object"),"additionalProperties":.object(["type":.string("string")])])
    #expect(throws:(any Error).self) { try WireSchema.validate(.object(["extra":.bool(true)]),schema:schema) }
    let unsupported = JSONValue.object(["type":.array([.string("string"),.string("number")])])
    #expect(throws:(any Error).self) { try WireSchema.validate(.bool(true),schema:unsupported) }
}
