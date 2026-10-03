import SwiftUI
import SimuCore

/// Fixed physical palette for temperature slices. A shared comparison
/// range wins; otherwise the field uses its own passed min/max.
public struct SlicePalette: Equatable, Sendable {
    /// Coldest valid cell in the field, degrees Celsius.
    public var minC: Double
    /// Warmest valid cell in the field, degrees Celsius.
    public var maxC: Double

    public init(minC: Double, maxC: Double) {
        self.minC = minC
        self.maxC = maxC
    }

    /// Shared comparison range wins; otherwise the field's own passed
    /// statistics. A failed or missing field never produces a palette, so
    /// no colour is drawn from an invalid slice.
    public static func resolved(field: FieldSlice?, shared: SlicePalette?) -> SlicePalette? {
        guard let field, field.quality == "passed" else {
            return nil
        }
        if let shared {
            return shared
        }
        guard let minC = field.stats.minC, let maxC = field.stats.maxC else {
            return nil
        }
        return SlicePalette(minC: minC, maxC: maxC)
    }

    /// Hue in [0, 2/3]: blue (2/3) at `minC` through cyan/green/yellow to
    /// red (0) at `maxC`. Values clamp to the field range - they never
    /// extrapolate. A degenerate (flat) range is a single cold hue.
    public func hue(forC value: Double) -> Double {
        let span = maxC - minC
        let t: Double
        if span <= 0 {
            t = 0
        } else {
            t = min(max((value - minC) / span, 0), 1)
        }
        // Cold at t=0, warm at t=1.
        return (2.0 / 3.0) * (1.0 - t)
    }

    /// Display colour for a valid cell.
    public func color(forC value: Double) -> Color {
        Color(hue: hue(forC: value), saturation: 0.85, brightness: 0.95)
    }

    /// Neutral colour for invalid cells (wall/furniture interiors): they are
    /// outside the field and never borrow a temperature colour.
    public static let invalidColor = Color.gray.opacity(0.4)

    /// Legend text states the physical range with the unit; the range is
    /// evidence, not decoration.
    public var legendText: String {
        "坐姿高度 \(UserFacingCopy.displayRange(minC, maxC, unit: "°C")) · 蓝凉红热"
    }
}
