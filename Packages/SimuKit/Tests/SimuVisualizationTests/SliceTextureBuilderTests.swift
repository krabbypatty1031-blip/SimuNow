import Foundation
import Testing
import SimuCore
import SimuVisualization

// Colour exists only for a quality-passed field. The texture is the same
// physical palette as the 2D legend: blue at minC, red at maxC, invalid
// cells stay neutral grey.

@Test func sliceTextureBuilderMapsAxisOrderYXOntoPixels() throws {
    let field = FieldSlice(
        zM: 1.1,
        originM: FieldSlice.SliceOrigin(x: 0.1, y: 0.1),
        spacingM: FieldSlice.SliceOrigin(x: 0.25, y: 0.25),
        shape: FieldSlice.SliceShape(nx: 2, ny: 2),
        values: [
            [20.0, 30.0],
            [25.0, 22.0],
        ],
        valid: [
            [true, true],
            [false, true],
        ],
        stats: FieldSlice.SliceStats(validCount: 3, minC: 20.0, maxC: 30.0),
        inputHash: "texture-test"
    )
    let palette = SlicePalette(minC: 20.0, maxC: 30.0)
    let bytes = try #require(SliceTextureBuilder.rgbaBytes(field: field, palette: palette))
    #expect(bytes.count == 2 * 2 * 4)

    // Plane V=0 is min display Z = max computation Y, so the first image
    // row is values[ny-1]: invalid grey then a mid-cold cell.
    let topLeft = Array(bytes[0..<4])
    #expect(abs(Int(topLeft[0]) - Int(topLeft[1])) < 8)
    #expect(abs(Int(topLeft[1]) - Int(topLeft[2])) < 8)

    // Bottom-left pixel is values[0][0] = 20 C: cold, so blue dominates red.
    let bottomLeft = Array(bytes[2 * 4..<3 * 4])
    #expect(bottomLeft[2] > bottomLeft[0])

    // Bottom-right pixel is values[0][1] = 30 C: warm, so red dominates blue.
    let bottomRight = Array(bytes[3 * 4..<4 * 4])
    #expect(bottomRight[0] > bottomRight[2])
}

@Test func sliceTextureBuilderOmitsFailedQuality() {
    let field = FieldSlice(
        zM: 1.1,
        originM: FieldSlice.SliceOrigin(x: 0, y: 0),
        spacingM: FieldSlice.SliceOrigin(x: 1, y: 1),
        shape: FieldSlice.SliceShape(nx: 1, ny: 1),
        values: [[24.0]],
        valid: [[true]],
        stats: FieldSlice.SliceStats(validCount: 1, minC: 24.0, maxC: 24.0),
        inputHash: "failed",
        quality: "failed"
    )
    #expect(SliceTextureBuilder.rgbaBytes(field: field, palette: SlicePalette(minC: 24, maxC: 24)) == nil)
    #expect(SliceTextureBuilder.cgImage(field: field, palette: SlicePalette(minC: 24, maxC: 24)) == nil)
}

@Test func slicePaletteResolvedUsesSharedRangeAndDropsFailedFields() throws {
    let passed = FieldSlice(
        zM: 1.1,
        originM: FieldSlice.SliceOrigin(x: 0, y: 0),
        spacingM: FieldSlice.SliceOrigin(x: 1, y: 1),
        shape: FieldSlice.SliceShape(nx: 1, ny: 1),
        values: [[24.4]],
        valid: [[true]],
        stats: FieldSlice.SliceStats(validCount: 1, minC: 24.4, maxC: 24.8),
        inputHash: "ok"
    )
    let own = try #require(SlicePalette.resolved(field: passed, shared: nil))
    #expect(own.minC == 24.4)
    #expect(own.maxC == 24.8)

    let shared = SlicePalette(minC: 23.0, maxC: 25.2)
    let compared = try #require(SlicePalette.resolved(field: passed, shared: shared))
    #expect(compared.minC == 23.0)
    #expect(compared.maxC == 25.2)

    let failed = FieldSlice(
        zM: 1.1,
        originM: FieldSlice.SliceOrigin(x: 0, y: 0),
        spacingM: FieldSlice.SliceOrigin(x: 1, y: 1),
        shape: FieldSlice.SliceShape(nx: 1, ny: 1),
        values: [[24.4]],
        valid: [[true]],
        stats: FieldSlice.SliceStats(validCount: 1, minC: 24.4, maxC: 24.8),
        inputHash: "fail",
        quality: "failed"
    )
    #expect(SlicePalette.resolved(field: failed, shared: nil) == nil)
}
