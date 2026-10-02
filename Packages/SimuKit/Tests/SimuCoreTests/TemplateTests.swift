import Foundation
import Testing
@testable import SimuCore

@Test func templatesPassIntegrityAndStayHonestAboutEnvironment() throws {
    for project in [ProjectTemplates.office(), ProjectTemplates.classroom()] {
        let registry = ModelRegistry.builtIn
        // Structural wire boundary accepts the template.
        let codec = ProjectCodec(registry: registry)
        #expect(try codec.decode(codec.encode(project)) == project)
        let report = try ProjectValidator().validate(project, registry: registry)
        // Templates are complete, consistent projects.
        #expect(report.passes(.projectIntegrity), "Integrity issues: \(report.issues)")
        // But they do not pretend to be runnable: weather/orientation/boundary stay unknown.
        #expect(!report.passes(.inputPreparation))
        #expect(report.issues.contains { $0.code == "required_input" && $0.path.hasSuffix("/environment/weather") })
        #expect(report.issues.contains { $0.path.contains("/northAngle") })
        // Snapshot capture works and is stable.
        let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: project.scenarios[0].id)
        #expect(try codec.decodeSnapshot(codec.encodeSnapshot(snapshot)) == snapshot)
        // No physical value lacks a source; unknowns carry reasons.
        let node = try JSONTreeCoding.encode(project)
        var unknowns = 0, knowns = 0, badUnknowns: [String] = [], badKnowns: [String] = []
        treeWalk(node) { path, n in
            if n["state"]?.string == "unknown" { unknowns += 1; if (n["reason"]?.string ?? "").isEmpty { badUnknowns.append(path) } }
            if n["state"]?.string == "known" { knowns += 1; if n["source"]?["kind"]?.string == nil { badKnowns.append(path) } }
        }
        #expect(badUnknowns.isEmpty, "Unknown without reason: \(badUnknowns)")
        #expect(badKnowns.isEmpty, "Known without source: \(badKnowns)")
        #expect(unknowns > 0 && knowns > 0)
    }
}

@Test func templateMassBalanceAndFlowConsistencyHold() throws {
    for project in [ProjectTemplates.office(), ProjectTemplates.classroom()] {
        let report = try ProjectValidator().validate(project, registry: .builtIn)
        let codes = report.issues.map(\.code)
        #expect(!codes.contains("recirculation_balance"))
        #expect(!codes.contains("flow_area_speed"))
        #expect(!codes.contains("direction_unit"))
        #expect(!codes.contains("schedule_coverage"))
        #expect(!codes.contains("point_in_solid"))
        #expect(!codes.contains("point_bounds"))
    }
}
