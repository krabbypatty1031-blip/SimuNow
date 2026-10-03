import Foundation
import Testing
@testable import SimuCore

/// ADR-013: office templates ship adult-office comfort defaults so L2 can
/// evaluate PMV. Values stay assumed, never a radiation or humidity field.
@Test func officeTemplateShipsAdultOfficeComfortDefaults() throws {
    let office = try ProjectTemplates.office(from: templatesDirectory())
    let comfort = try #require(office.project.occupancy?.comfort)
    #expect(comfort.clo.value == 0.5)
    #expect(comfort.clo.unit == "clo")
    #expect(comfort.clo.source == .assumed)
    #expect(comfort.met.value == 1.2)
    #expect(comfort.met.unit == "met")
    #expect(comfort.met.source == .assumed)
    #expect(comfort.rhPct.value == 50)
    #expect(comfort.rhPct.unit == "%")
    #expect(comfort.rhPct.source == .assumed)
    #expect(comfort.mrtC.value == 26)
    #expect(comfort.mrtC.unit == "C")
    #expect(comfort.mrtC.source == .assumed)
    #expect(comfort.mrtC.reference?.contains("辐射") == true)
}

/// Classrooms reuse the adult-office defaults but must disclose that
/// children are not separately evaluated.
@Test func classroomComfortDefaultsDiscloseChildrenUnevaluated() throws {
    let classroom = try ProjectTemplates.classroom(from: templatesDirectory())
    let comfort = try #require(classroom.project.occupancy?.comfort)
    #expect(comfort.clo.value == 0.5)
    #expect(comfort.met.value == 1.2)
    #expect(classroom.lockedAssumptions.contains("儿童人群未单独评价"))
    #expect(classroom.project.listedAssumptions().contains { $0.note == "儿童人群未单独评价" })
}

/// A v2 draft that predates occupancy.comfort must still decode. Missing
/// keys stay missing; they are not filled with 0.
@Test func versionTwoDraftWithoutComfortStillDecodes() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/project-v2-office.json")
    let draft = try JSONDecoder().decode(ProjectDraft.self, from: Data(contentsOf: url))
    #expect(draft.hasCompletePhysicalModel)
    #expect(draft.occupancy?.comfort == nil)
}

private func templatesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/templates")
}
