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

@Test func fieldSliceDecodesPinnedSliceWithContractClaims() throws {
    let data = try Data(contentsOf: fixturesDirectory().appendingPathComponent("field-slice-l2.json"))
    let slice = try JSONDecoder().decode(FieldSlice.self, from: data)
    // Wire claims stay pinned: unit, frame, axis order, sample method.
    #expect(slice.unit == "C")
    #expect(slice.coordinateSystem == "rightHandedZUp")
    #expect(slice.axisOrder == ["y", "x"])
    #expect(slice.sampleMethod == "nearest_cell")
    #expect(slice.quality == "passed")
    // The pinned office slice is a 24 x 24 grid at seat height.
    #expect(slice.shape.nx == 24)
    #expect(slice.shape.ny == 24)
    #expect(abs(slice.zM - 1.1) < 1e-9)
    #expect(slice.values.count == 24)
    #expect(slice.valid.count == 24)
    #expect(slice.values.allSatisfy { $0.count == 24 })
    // Stats count only valid cells; the pinned field has no invalid cells.
    let validCount = slice.valid.flatMap { $0 }.filter { $0 }.count
    #expect(slice.stats.validCount == validCount)
    #expect(slice.stats.minC != nil)
    #expect(slice.stats.maxC != nil)
    if let minC = slice.stats.minC, let maxC = slice.stats.maxC {
        #expect(minC < maxC)
        // Supply is 16 C, setpoint 26 C: the slice must live between them.
        #expect(minC > 16)
        #expect(maxC < 30)
    }
    let mean = try #require(slice.meanValidC)
    #expect(mean >= slice.stats.minC ?? mean)
    #expect(mean <= slice.stats.maxC ?? mean)
}

@Test func fieldSliceRejectsChangedWireClaims() throws {
    let url = fixturesDirectory().appendingPathComponent("field-slice-l2.json")
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let base = try #require(payload)

    func redecode(_ mutated: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: mutated)
        _ = try JSONDecoder().decode(FieldSlice.self, from: data)
    }

    // A different unit, axis order or sample method is a different contract.
    var unitMutant = base
    unitMutant["unit"] = "K"
    #expect(throws: DecodingError.self) { try redecode(unitMutant) }

    var axisMutant = base
    axisMutant["axisOrder"] = ["x", "y"]
    #expect(throws: DecodingError.self) { try redecode(axisMutant) }

    var methodMutant = base
    methodMutant["sampleMethod"] = "interpolated"
    #expect(throws: DecodingError.self) { try redecode(methodMutant) }

    var frameMutant = base
    frameMutant["coordinateSystem"] = "leftHandedYUp"
    #expect(throws: DecodingError.self) { try redecode(frameMutant) }

    var qualityMutant = base
    qualityMutant["quality"] = "failed"
    #expect(throws: DecodingError.self) { try redecode(qualityMutant) }
}

@Test func fieldSliceRejectsShapeMismatch() throws {
    let url = fixturesDirectory().appendingPathComponent("field-slice-l2.json")
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let base = try #require(payload)
    // Values claiming a shape they do not have must not decode.
    var mutant = base
    mutant["values"] = [[25.0]]
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            FieldSlice.self,
            from: try JSONSerialization.data(withJSONObject: mutant)
        )
    }
}
