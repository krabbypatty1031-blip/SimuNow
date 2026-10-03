import CoreGraphics
import Foundation
import SimuCore

/// Builds the seat-height temperature texture from a quality-passed field.
/// Colour is the same physical mapping as `SlicePalette`; a failed field
/// produces no image, so a rainbow is never presented as CFD.
public enum SliceTextureBuilder: Sendable {
    /// RGBA8 bytes, row-major. First row is `values[ny-1]` so plane V=0
    /// (min display Z = max computation Y) samples the high-Y edge.
    public static func rgbaBytes(field: FieldSlice, palette: SlicePalette) -> [UInt8]? {
        guard field.quality == "passed", field.shape.nx > 0, field.shape.ny > 0 else {
            return nil
        }
        let nx = field.shape.nx
        let ny = field.shape.ny
        var bytes = [UInt8](repeating: 0, count: nx * ny * 4)
        for row in 0..<ny {
            let sourceRow = ny - 1 - row
            for column in 0..<nx {
                let offset = (row * nx + column) * 4
                let isValid = sourceRow < field.valid.count
                    && column < field.valid[sourceRow].count
                    && field.valid[sourceRow][column]
                if isValid, sourceRow < field.values.count, column < field.values[sourceRow].count {
                    let rgb = hsv(h: palette.hue(forC: field.values[sourceRow][column]), saturation: 0.85, value: 0.95)
                    bytes[offset] = rgb.0
                    bytes[offset + 1] = rgb.1
                    bytes[offset + 2] = rgb.2
                    bytes[offset + 3] = 255
                } else {
                    // Premultiplied grey so wall/furniture interiors stay
                    // neutral and never borrow a temperature colour.
                    let alpha: UInt8 = 102
                    let grey: UInt8 = UInt8((128 * Int(alpha)) / 255)
                    bytes[offset] = grey
                    bytes[offset + 1] = grey
                    bytes[offset + 2] = grey
                    bytes[offset + 3] = alpha
                }
            }
        }
        return bytes
    }

    public static func cgImage(field: FieldSlice, palette: SlicePalette) -> CGImage? {
        guard let bytes = rgbaBytes(field: field, palette: palette) else {
            return nil
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: field.shape.nx,
            height: field.shape.ny,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: field.shape.nx * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Same HSV as `SlicePalette.color(forC:)` so the 3D plane and the
    /// SwiftUI legend stay on one physical range.
    private static func hsv(h: Double, saturation: Double, value: Double) -> (UInt8, UInt8, UInt8) {
        let sector = Int((h * 6).rounded(.down))
        let fraction = h * 6 - Double(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - fraction * saturation)
        let t = value * (1 - (1 - fraction) * saturation)
        let rgb: (Double, Double, Double)
        switch sector % 6 {
        case 0: rgb = (value, t, p)
        case 1: rgb = (q, value, p)
        case 2: rgb = (p, value, t)
        case 3: rgb = (p, q, value)
        case 4: rgb = (t, p, value)
        default: rgb = (value, p, q)
        }
        return (channel(rgb.0), channel(rgb.1), channel(rgb.2))
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}
