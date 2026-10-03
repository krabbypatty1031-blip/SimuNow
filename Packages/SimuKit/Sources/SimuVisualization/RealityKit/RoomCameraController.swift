import RealityKit
import SimuCore

@available(macOS 15, iOS 18, *)
@MainActor
public enum RoomCameraController {
    public static func update(_ camera: Entity, state: RoomCameraState, bounds: GeometryBounds?) {
        let diagonal = bounds.map(RoomCameraState.diagonal) ?? state.distance
        camera.components.set(PerspectiveCameraComponent(near: 0.005, far: Float(max(100,state.distance+diagonal*4)),
                                                         fieldOfViewInDegrees: Float(state.fieldOfViewDegrees), fieldOfViewOrientation: .vertical))
        let p = CoordinateTransform.toApple(state.position), t = CoordinateTransform.toApple(state.target)
        camera.look(at: [Float(t.x),Float(t.y),Float(t.z)],from: [Float(p.x),Float(p.y),Float(p.z)],upVector: [0,1,0],relativeTo: nil)
    }
}
