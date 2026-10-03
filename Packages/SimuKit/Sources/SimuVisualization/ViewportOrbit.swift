import CoreGraphics
import Foundation

/// Viewer-only camera for the room. Drag changes yaw/pitch; pinch changes
/// distance. The comparison page shares `yawRadians` so several candidates
/// stay on the same heading — built-in RealityKit orbit controls would
/// break that contract, so the room root is rotated from these values.
public struct ViewportOrbit: Equatable, Sendable {
    public static let defaultYaw = -0.6
    public static let defaultPitch = Double.pi / 6
    public static let defaultDistance = 1.0
    /// Keep the look slightly above the floor so the room cannot invert.
    public static let minPitch = 0.08
    public static let maxPitch = 1.35
    public static let minDistance = 0.45
    public static let maxDistance = 2.5

    public var yawRadians: Double
    public var pitchRadians: Double
    public var distance: Double

    public init(
        yawRadians: Double = Self.defaultYaw,
        pitchRadians: Double = Self.defaultPitch,
        distance: Double = Self.defaultDistance
    ) {
        self.yawRadians = yawRadians
        self.pitchRadians = Self.clampedPitch(pitchRadians)
        self.distance = Self.clampedDistance(distance)
    }

    /// Horizontal drag yaws; vertical drag pitches. Sensitivity matches the
    /// Canvas wireframe so the two renderers feel like one control.
    public mutating func applyDrag(translation: CGSize, startYaw: Double, startPitch: Double) {
        yawRadians = startYaw + Double(translation.width) * 0.01
        pitchRadians = Self.clampedPitch(startPitch + Double(translation.height) * 0.01)
    }

    /// Pinch greater than 1 zooms in (smaller distance). The start distance
    /// is captured at gesture begin so the scale stays continuous.
    public mutating func applyMagnification(_ magnification: Double, startDistance: Double) {
        distance = Self.clampedDistance(startDistance / max(magnification, 0.01))
    }

    /// Uniform scale that fits the room diagonal into about two display units,
    /// then applies zoom. Metres stay on the model; this is view fit only.
    public func fitScale(sizeXM: Double, sizeYM: Double, sizeZM: Double) -> Float {
        let diagonal = (sizeXM * sizeXM + sizeYM * sizeYM + sizeZM * sizeZM).squareRoot()
        let fit = 2.0 / max(diagonal, 0.1)
        return Float(fit / max(distance, 0.01))
    }

    private static func clampedPitch(_ value: Double) -> Double {
        min(max(value, minPitch), maxPitch)
    }

    private static func clampedDistance(_ value: Double) -> Double {
        min(max(value, minDistance), maxDistance)
    }
}
