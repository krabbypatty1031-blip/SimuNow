import Foundation
import Testing
@testable import SimuCore
@testable import SimuWorkspace

@Test @MainActor func sessionEditsMarkDirtyAndRevalidate() throws {
    let session = ProjectSession(project: ProjectTemplates.office())
    #expect(!session.isDirty)
    #expect(!session.validation.passes(.inputPreparation)) // template honestly lacks weather
    session.mutate { $0.name = "改名" }
    #expect(session.isDirty)
    #expect(session.validation.passes(.projectIntegrity))
}

@Test @MainActor func sessionSaveLoadRoundTripAndRecents() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-session-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("demo.simunow")
    let session = ProjectSession(project: ProjectTemplates.classroom())
    session.mutate { $0.name = "保存测试" }
    try session.save(to: url)
    #expect(!session.isDirty)
    let loaded = try ProjectSession.load(from: url)
    #expect(loaded.project == session.project)
    #expect(loaded.packageURL == url)
    #expect(ProjectSession.recents.first?.path == url.path)
}

@Test @MainActor func duplicateScenarioKeepsEntityIdentityWithNewScenarioID() throws {
    let session = ProjectSession(project: ProjectTemplates.office())
    let original = session.project.scenarios[0]
    session.duplicateScenario(original.id, name: "候选 A")
    #expect(session.project.scenarios.count == 2)
    let copy = session.project.scenarios[1]
    #expect(copy.id != original.id)
    #expect(copy.name == "候选 A")
    #expect(copy.inputs.usage.seats.map(\.id) == original.inputs.usage.seats.map(\.id))
    #expect(copy.inputs.hvac.map(\.id) == original.inputs.hvac.map(\.id))
    // Editing the copy must not touch the original (value semantics).
    let copyID = copy.id
    session.mutate { document in
        if let index = document.scenarios.firstIndex(where: { $0.id == copyID }) {
            document.scenarios[index].inputs.controls[0].setpoint = .known(
                value: 24, source: .init(kind: .user))
        }
    }
    #expect(session.project.scenarios[0].inputs.controls[0].setpoint.value == 26)
    #expect(session.project.scenarios[1].inputs.controls[0].setpoint.value == 24)
}

@Test @MainActor func selectionClearsWhenEntityDisappears() throws {
    let session = ProjectSession(project: ProjectTemplates.office())
    let seat = session.project.scenarios[0].inputs.usage.seats[0]
    session.selection = .seat(seat.id)
    #expect(session.selection == .seat(seat.id))
    session.mutate { document in
        document.scenarios[0].inputs.usage.seats.removeAll { $0.id == seat.id }
        document.scenarios[0].inputs.usage.occupants.removeAll { $0.seatID == seat.id }
    }
    session.selection = .seat(seat.id) // didSet re-validates identity
    #expect(session.selection == nil)
    // Snapshots stay capturable after edits.
    #expect(try session.snapshot(for: session.project.scenarios[0].id).scenarioID == session.project.scenarios[0].id)
}
