import Foundation
import Testing
@testable import SimuCore

@Test func canonicalHashTextMatchesSharedRules() throws {
    let ordered = try JSONValue(data: Data("{\"b\":1,\"a\":2,\"ä\":3}".utf8))
    #expect(try InputHash.canonicalText(ordered) == "{\"a\":2,\"b\":1,\"ä\":3}")

    let escaped = try JSONValue(data: Data("{\"s\":\"a\\\"b\\\\c\\nd\"}".utf8))
    #expect(try InputHash.canonicalText(escaped) == "{\"s\":\"a\\\"b\\\\c\\nd\"}")

    let numbers = try JSONValue(data: Data("[1.50,1e2,-0]".utf8))
    #expect(try InputHash.canonicalText(numbers) == "[1.50,1e2,-0]")

    let scalars = try JSONValue(data: Data("[true,false,null]".utf8))
    #expect(try InputHash.canonicalText(scalars) == "[true,false,null]")

    let control = try JSONValue(data: Data("{\"s\":\"\\u0001\"}".utf8))
    #expect(try InputHash.canonicalText(control) == "{\"s\":\"\\u0001\"}")

    let hash = InputHash.sha256Hex("{\"a\":1}")
    #expect(hash.count == 64)
}

@Test func snapshotHashChangesWithInputs() throws {
    let project = ProjectTemplates.office()
    let scenarioID = project.scenarios[0].id
    let original = try InputHash.snapshotHash(ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID))
    var edited = project
    edited.scenarios[0].inputs.controls[0].setpoint = .known(value: 24, source: .init(kind: .user))
    let changed = try InputHash.snapshotHash(ScenarioSnapshotBuilder.capture(edited, scenarioID: scenarioID))
    #expect(original != changed)
    // Same inputs again → same hash (deterministic identity for caching).
    #expect(try InputHash.snapshotHash(ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID)) == original)
}
