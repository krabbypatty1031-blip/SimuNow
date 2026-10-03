import Foundation
import Testing
import SimuCore
import SimuVisualization

// P4-05c: the slice palette is a fixed physical mapping, so two candidates
// with the same range show comparable colours; invalid cells stay neutral
// and never borrow a temperature colour.

@Test func slicePaletteMapsColdToWarmHueMonotonically() {
    let palette = SlicePalette(minC: 24.0, maxC: 26.0)
    // Hue runs from blue (2/3) at the minimum to red (0) at the maximum.
    #expect(abs(palette.hue(forC: 24.0) - 2.0 / 3.0) < 1e-9)
    #expect(abs(palette.hue(forC: 26.0)) < 1e-9)
    // Warmer cells are redder: the hue decreases with temperature.
    #expect(palette.hue(forC: 24.5) > palette.hue(forC: 25.0))
    #expect(palette.hue(forC: 25.5) > palette.hue(forC: 26.0))
    // Out-of-range values clamp, they do not extrapolate.
    #expect(palette.hue(forC: 23.0) == palette.hue(forC: 24.0))
    #expect(palette.hue(forC: 27.0) == palette.hue(forC: 26.0))
}

@Test func slicePaletteLegendShowsPhysicalRangeWithUnit() {
    let palette = SlicePalette(minC: 23.9, maxC: 25.9)
    let legend = palette.legendText
    #expect(legend.contains("23.9"))
    #expect(legend.contains("25.9"))
    #expect(legend.contains("°C"))
}

@Test func slicePaletteLegendStatesSeatHeightAndColdWarm() {
    let palette = SlicePalette(minC: 23.9, maxC: 25.9)
    #expect(palette.legendText.contains("23.9"))
    #expect(palette.legendText.contains("坐姿高度"))
    #expect(palette.legendText.contains("蓝凉红热"))
    #expect(!palette.legendText.contains("L2"))
}

@Test func slicePaletteWithDegenerateRangeIsSingleHue() {
    // A flat field is one colour, not a division by zero.
    let palette = SlicePalette(minC: 25.0, maxC: 25.0)
    #expect(palette.hue(forC: 25.0) == palette.hue(forC: 25.0))
    #expect(abs(palette.hue(forC: 25.0) - 2.0 / 3.0) < 1e-9)
}
