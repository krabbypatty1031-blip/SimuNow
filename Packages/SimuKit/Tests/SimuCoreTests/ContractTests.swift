import Foundation
import Testing
@testable import SimuCore
import SimuSimulation

@Test func projectDraftPreservesWireConvention() throws {
    let original = ProjectDraft(name: "办公室", spaceType: .office)
    let data = try JSONEncoder().encode(original)
    let restored = try JSONDecoder().decode(ProjectDraft.self, from: data)
    #expect(restored == original)
    #expect(restored.lengthUnit == "m")
    #expect(restored.coordinateSystem == "rightHandedZUp")
}

@Test func oldRunDoesNotMatchEditedInputs() {
    let identity = RunIdentity(scenarioID: UUID(), inputHash: "snapshot-a")
    #expect(identity.freshness(relativeTo: "snapshot-a") == .current)
    #expect(identity.freshness(relativeTo: "snapshot-b") == .stale)
}

@Test func missingEngineCannotProduceSuccessfulResults() async {
    let request = SimulationRequest(identity: RunIdentity(scenarioID: UUID(), inputHash: "input"), fidelity: .l2)
    do {
        _ = try await UnconfiguredSimulationClient().submit(request)
        Issue.record("An unavailable engine must not report a successful calculation.")
    } catch {
        #expect(error is SimulationClientError)
    }
}
