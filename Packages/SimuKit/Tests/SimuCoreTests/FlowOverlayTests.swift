import Foundation
import Testing
import SimuCore

private func fixturesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/task")
}

@Test func flowOverlayDecodesFixtureWithContractClaims() throws {
    let data = try Data(contentsOf: fixturesDirectory().appendingPathComponent("field-flow-l2.json"))
    let flow = try JSONDecoder().decode(FlowOverlay.self, from: data)
    #expect(flow.unit == "m/s")
    #expect(flow.coordinateSystem == "rightHandedZUp")
    #expect(flow.sampleMethod == "nearest_cell")
    #expect(flow.streamlineMethod == "rk2_nearest_cell")
    #expect(flow.quality == "passed")
    #expect(abs(flow.zM - 1.1) < 1e-9)
    #expect(flow.glyphs.count == 2)
    #expect(flow.lines.count == 1)
    #expect(flow.stats.glyphCount == 2)
    #expect(flow.stats.maxMag == 0.20)
}

@Test func flowOverlayRejectsChangedWireClaims() throws {
    let url = fixturesDirectory().appendingPathComponent("field-flow-l2.json")
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let base = try #require(payload)

    func redecode(_ mutated: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: mutated)
        _ = try JSONDecoder().decode(FlowOverlay.self, from: data)
    }

    var unitMutant = base
    unitMutant["unit"] = "cm/s"
    #expect(throws: DecodingError.self) { try redecode(unitMutant) }

    var methodMutant = base
    methodMutant["streamlineMethod"] = "sketched"
    #expect(throws: DecodingError.self) { try redecode(methodMutant) }

    var qualityMutant = base
    qualityMutant["quality"] = "failed"
    #expect(throws: DecodingError.self) { try redecode(qualityMutant) }
}

@Test func flowOverlayRejectsCountMismatch() throws {
    let url = fixturesDirectory().appendingPathComponent("field-flow-l2.json")
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    var mutant = try #require(payload)
    mutant["glyphs"] = []
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            FlowOverlay.self,
            from: try JSONSerialization.data(withJSONObject: mutant)
        )
    }
}
