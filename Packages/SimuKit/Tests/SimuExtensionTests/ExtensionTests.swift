import Foundation
import Testing
import SimuCore

private struct TestDevice: ModelPayload {
    static let category = "hvac"
    static let kind = "test.hvac.fan"
    static var wireSchema: JSONValue { .object(["type":.string("object"),"properties":.object(["label":.object(["type":.string("string")])]),"required":.array([.string("label")]),"additionalProperties":.bool(false)]) }
    let label: String
    func validate(at path: String) -> [ValidationIssue] {
        label == "blocked" ? [.init(code:"test_label",path:path + "/label",blocks:[.inputPreparation],message:"Name the test device.")] : []
    }
}
private struct ExtraRule: ProjectValidationRule {
    func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue] {
        [.init(code:"extra_rule",path:"/name",message:"Test rule injected independently.")]
    }
}
private func projectFixture() throws -> ProjectDocument {
    var root = URL(fileURLWithPath:#filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try ProjectCodec(registry:.builtIn).decode(Data(contentsOf:root.appendingPathComponent("Fixtures/Contracts/office.json")))
}
@Test func independentDeviceRegistrationCoversProjectPipeline() throws {
    let registry = try ModelRegistry(ModelRegistry.builtIn.registrations + [ModelRegistration(TestDevice.self)])
    var project = try projectFixture()
    project.scenarios[0].inputs.hvac[0].definition = try ExtensionRecord(TestDevice(label:"blocked"))
    let codec = ProjectCodec(registry:registry)
    #expect(try codec.decode(codec.encode(project)) == project)
    let report = try ProjectValidator().validate(project,registry:registry)
    #expect(report.issues.count == 1 && report.issues[0].code == "test_label")
    let snapshot = try ScenarioSnapshotBuilder.capture(project,scenarioID:project.scenarios[0].id)
    #expect(try codec.decodeSnapshot(codec.encodeSnapshot(snapshot)) == snapshot)
    #expect(try project.scenarios[0].inputs.hvac[0].definition.resolved(as:TestDevice.self,registry:registry)?.label == "blocked")
    #expect(try ProjectValidator(rules:[ExtraRule()]).validate(project,registry:registry).issues[0].code == "extra_rule")
    #expect(throws:(any Error).self) { try ModelRegistry([ModelRegistration(TestDevice.self),ModelRegistration(TestDevice.self)]) }
    let invalid = ExtensionRecord(kind:TestDevice.kind,payloadVersion:1,payload:.object(["unexpected":.bool(true)]))
    #expect(throws:(any Error).self) { try registry.resolve(category:"hvac",record:invalid) }
}

private struct RestrictedRoom: GeometryPayload {
    static let category = "room"
    static let kind = "test.geometry.restrictedRoom"
    static var wireSchema: JSONValue { .object(["type":.string("object"),"properties":.object([:]),"additionalProperties":.bool(false)]) }
    func geometryBounds() -> GeometryBounds? { .init(origin:.init(x:0,y:0,z:0),size:.init(x:6,y:4,z:3)) }
    func contains(_ p: Position3D, tolerance: Double) -> Bool { geometryBounds()!.contains(p,tolerance:tolerance) && p.x < 5 }
    func surfaceExtent(_ face: SurfaceFace) -> (Double,Double)? {
        switch face { case .xMin,.xMax: return (4,3); case .yMin,.yMax: return (6,3); case .floor,.ceiling: return (6,4) }
    }
    func intersects(_ other: any GeometryPayload, tolerance: Double) -> Bool {
        guard let bounds = other.geometryBounds() else { return false }
        return geometryBounds()!.intersects(bounds,tolerance:tolerance)
    }
}
@Test func registeredGeometryOwnsContainmentQueries() throws {
    let registry = try ModelRegistry(ModelRegistry.builtIn.registrations + [ModelRegistration(RestrictedRoom.self)])
    var project = try projectFixture()
    project.geometry.rooms[0].shape = try ExtensionRecord(RestrictedRoom())
    project.scenarios[0].inputs.usage.seats[0].samples[0].position = .init(x:5.5,y:2,z:1)
    #expect(try ProjectCodec(registry:registry).decode(ProjectCodec(registry:registry).encode(project)) == project)
    let issues = try GeometryRule().validate(project,registry:registry)
    #expect(issues.contains { $0.code == "point_bounds" && $0.path.hasSuffix("/samples/0/position") })
}
