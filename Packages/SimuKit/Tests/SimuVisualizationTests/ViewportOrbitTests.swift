import Foundation
import Testing
import SimuVisualization

// Viewer-only orbit: drag spins the room, pinch zooms, pitch stays above
// the floor. Shared comparison yaw is the same angle this struct stores.

@Test func viewportOrbitDragIncreasesYawToTheRight() {
    var orbit = ViewportOrbit()
    let startYaw = orbit.yawRadians
    orbit.applyDrag(translation: CGSize(width: 40, height: 0), startYaw: startYaw, startPitch: orbit.pitchRadians)
    #expect(orbit.yawRadians > startYaw)
}

@Test func viewportOrbitDragPitchClampsAboveTheFloor() {
    var orbit = ViewportOrbit()
    // A large downward drag must not flip the room under the floor.
    orbit.applyDrag(translation: CGSize(width: 0, height: 4000), startYaw: orbit.yawRadians, startPitch: orbit.pitchRadians)
    #expect(orbit.pitchRadians >= ViewportOrbit.minPitch)
    #expect(orbit.pitchRadians <= ViewportOrbit.maxPitch)

    orbit.applyDrag(translation: CGSize(width: 0, height: -4000), startYaw: orbit.yawRadians, startPitch: orbit.pitchRadians)
    #expect(orbit.pitchRadians >= ViewportOrbit.minPitch)
    #expect(orbit.pitchRadians <= ViewportOrbit.maxPitch)
}

@Test func viewportOrbitMagnificationClampsDistance() {
    var orbit = ViewportOrbit()
    orbit.applyMagnification(0.1, startDistance: ViewportOrbit.defaultDistance)
    #expect(orbit.distance >= ViewportOrbit.minDistance)
    orbit.applyMagnification(20, startDistance: ViewportOrbit.defaultDistance)
    #expect(orbit.distance <= ViewportOrbit.maxDistance)
}

@Test func viewportOrbitFitScaleShrinksALargeRoom() {
    let orbit = ViewportOrbit()
    // A 6×6×2.8 office must fit inside a ~2-unit view, not stay 1:1 metres.
    let scale = orbit.fitScale(sizeXM: 6, sizeYM: 6, sizeZM: 2.8)
    #expect(scale > 0)
    #expect(scale < 1)
}
