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

@Test func versionOneDraftIsNotASolvableRoom() throws {
    // P0 identity-only JSON must keep decoding, and must not be treated as solver input.
    let json = """
    {
      "schemaVersion": 1,
      "id": "11111111-1111-1111-1111-111111111111",
      "name": "办公室",
      "spaceType": "office",
      "lengthUnit": "m",
      "coordinateSystem": "rightHandedZUp"
    }
    """
    let draft = try JSONDecoder().decode(ProjectDraft.self, from: Data(json.utf8))
    #expect(draft.schemaVersion == 1)
    #expect(draft.hasCompletePhysicalModel == false)
    #expect(draft.geometry == nil)
    #expect(draft.occupancy == nil)
    #expect(draft.hvac == nil)
}

@Test func versionTwoOfficeRoundTripKeepsSetpointSeparateFromSupply() throws {
    let original = makeOfficeDraft()
    let data = try JSONEncoder().encode(original)
    let restored = try JSONDecoder().decode(ProjectDraft.self, from: data)
    #expect(restored == original)
    #expect(restored.schemaVersion == 2)
    #expect(restored.hasCompletePhysicalModel)
    #expect(restored.lengthUnit == "m")
    #expect(restored.coordinateSystem == "rightHandedZUp")
    #expect(restored.hvac?.setpointC.value == 26)
    #expect(restored.hvac?.supplyTemperatureC.value == 16)
    #expect(restored.hvac?.setpointC.value != restored.hvac?.supplyTemperatureC.value)
    #expect(restored.occupancy?.seats.map(\.id) == ["S1", "S2", "S3", "S4"])
}

@Test func windowAndSupplyPatchesUseWallSpanNotFullWall() throws {
    let draft = makeOfficeDraft()
    let window = try #require(draft.geometry?.openings.first)
    let wallLength = try #require(draft.geometry?.span(along: window.wall))
    #expect(window.s1.value - window.s0.value == 1.5)
    #expect(abs(window.patchAreaM2 - 1.95) < 1e-9)
    #expect(window.s1.value - window.s0.value < wallLength)
    #expect(draft.geometry?.contains(window) == true)

    let supply = try #require(draft.hvac?.supply)
    #expect(abs(supply.patchAreaM2 - 0.09) < 1e-9)
    #expect(draft.hvac?.supplyAirflowMatchesSpeed() == true)
}

@Test func mismatchedSupplyAirflowFailsSpeedAreaCheck() throws {
    var hvac = makeOfficeDraft().hvac!
    hvac.supplyAirflowM3s.value = 9
    #expect(hvac.supplyAirflowMatchesSpeed() == false)
}

@Test func physicalQuantityOmitsEmptyProvenanceFromJSON() throws {
    let quantity = PhysicalQuantity(
        value: 26,
        unit: "C",
        source: .user,
        reference: "   ",
        uncertainty: nil
    )
    #expect(quantity.reference == nil)
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(quantity)) as? [String: Any]
    #expect(object?["reference"] == nil)
    #expect(object?["uncertainty"] == nil)
}

@Test func physicalQuantityRoundTripsReferenceAndUncertainty() throws {
    let original = PhysicalQuantity(
        value: 70,
        unit: "W",
        source: .assumed,
        reference: "ISO 8996 office sensible heat",
        uncertainty: 10
    )
    let restored = try JSONDecoder().decode(
        PhysicalQuantity.self,
        from: JSONEncoder().encode(original)
    )
    #expect(restored == original)
    #expect(restored.reference == "ISO 8996 office sensible heat")
    #expect(restored.uncertainty == 10)
}

private func metres(_ value: Double, source: ParameterSource = .preset) -> PhysicalQuantity {
    PhysicalQuantity(value: value, unit: "m", source: source)
}

private func makeOfficeDraft() -> ProjectDraft {
    let window = Opening(
        id: "W1",
        kind: .window,
        wall: .xMax,
        s0: metres(2.25),
        s1: metres(3.75),
        z0: metres(0.9),
        z1: metres(2.2),
        heatFluxWm2: PhysicalQuantity(value: 80, unit: "W/m2", source: .preset)
    )
    let geometry = RoomGeometry(
        sizeX: metres(6),
        sizeY: metres(6),
        sizeZ: metres(2.8),
        openings: [window],
        obstacles: [],
        assumptions: ["omitted: furniture_boxes"]
    )
    let occupancy = OccupancyModel(
        occupantCount: PhysicalQuantity(value: 8, unit: "1", source: .preset),
        occupantSensibleW: PhysicalQuantity(value: 70, unit: "W", source: .preset),
        lightingW: PhysicalQuantity(value: 180, unit: "W", source: .preset),
        equipmentW: PhysicalQuantity(value: 400, unit: "W", source: .preset),
        seats: [
            Seat(id: "S1", position: Position3D(x: 1.5, y: 1.5, z: 1.1), source: .preset),
            Seat(id: "S2", position: Position3D(x: 1.5, y: 4.5, z: 1.1), source: .preset),
            Seat(id: "S3", position: Position3D(x: 4.5, y: 1.5, z: 1.1), source: .preset),
            Seat(id: "S4", position: Position3D(x: 4.5, y: 4.5, z: 1.1), source: .preset)
        ]
    )
    let hvac = HVACModel(
        setpointC: PhysicalQuantity(value: 26, unit: "C", source: .user),
        supplyTemperatureC: PhysicalQuantity(value: 16, unit: "C", source: .preset),
        supplySpeedMs: PhysicalQuantity(value: 1.2, unit: "m/s", source: .preset),
        supplyAirflowM3s: PhysicalQuantity(value: 0.108, unit: "m3/s", source: .preset),
        supply: AirTerminal(
            id: "SUP1",
            wall: .xMin,
            s0: metres(2.75),
            s1: metres(3.25),
            z0: metres(2.48),
            z1: metres(2.66)
        ),
        returnTerminal: AirTerminal(
            id: "RET1",
            wall: .xMin,
            s0: metres(2.70),
            s1: metres(3.30),
            z0: metres(1.85),
            z1: metres(2.05)
        ),
        outdoorAirM3s: PhysicalQuantity(value: 0.02, unit: "m3/s", source: .assumed),
        cop: PhysicalQuantity(value: 3, unit: "1", source: .assumed)
    )
    return ProjectDraft(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "办公室",
        spaceType: .office,
        geometry: geometry,
        occupancy: occupancy,
        hvac: hvac
    )
}

@Test func oldRunDoesNotMatchEditedInputs() {
    let identity = RunIdentity(scenarioID: UUID(), inputHash: "snapshot-a")
    #expect(identity.freshness(relativeTo: "snapshot-a") == .current)
    #expect(identity.freshness(relativeTo: "snapshot-b") == .stale)
}

@Test func missingEngineCannotProduceSuccessfulResults() async {
    let request = SimulationRequest(
        identity: RunIdentity(scenarioID: UUID(), inputHash: "input"),
        fidelity: .l2,
        snapshotPath: "runs/input.json",
        snapshotHash: "input"
    )
    do {
        _ = try await UnconfiguredSimulationClient().submit(request)
        Issue.record("An unavailable engine must not report a successful calculation.")
    } catch {
        #expect(error is SimulationClientError)
    }
}
