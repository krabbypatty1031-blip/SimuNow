import Foundation
import Observation
import RealityKit
import SimuCore

public struct RoomSceneStatistics: Equatable, Sendable {
    public let nodeCount: Int
    public let entityCount: Int
    public let overlayPathCount: Int
    public let meshCount: Int
    public let materialCount: Int
    /// RealityKit SceneEvents/ticker subscriptions; none are created by this static renderer.
    /// The AppKit wheel monitor belongs to the viewport NSView and is removed on dismantle.
    public let activeSubscriptions: Int
    public let isActive: Bool
}
@available(macOS 15, iOS 18, *)
@MainActor
@Observable
public final class RoomSceneController {
    public private(set) var camera: RoomCameraState
    public private(set) var visibility = RoomSceneVisibility()
    public private(set) var isActive = true
    @ObservationIgnored public let worldRoot = Entity()
    @ObservationIgnored private let roomRoot = Entity()
    @ObservationIgnored private let objectsRoot = Entity()
    @ObservationIgnored private let overlayRoot = Entity()
    @ObservationIgnored private let cameraEntity = Entity()
    @ObservationIgnored private var entities: [SceneNodeKey: Entity] = [:]
    @ObservationIgnored private var overlayEntities: [String: Entity] = [:]
    @ObservationIgnored private var descriptor: SceneDescriptor?
    @ObservationIgnored private var overlay = RoomSceneOverlay.empty
    @ObservationIgnored private var selectedKey: SceneObjectKey?
    @ObservationIgnored private var dark = false
    @ObservationIgnored private var lastProjectID: UUID?
    @ObservationIgnored private var hasUserCamera = false
    @ObservationIgnored private var aspectRatio = 1.0
    @ObservationIgnored private let factory = RoomEntityFactory()
    public init(bounds: GeometryBounds?) {
        camera = bounds.map { .fitting(bounds: $0,aspectRatio: 1) } ?? .init(target: .init(x: 0,y: 0,z: 0),distance: 5)
        worldRoot.name = "room-scene-world"; roomRoot.name = "room-scene-room"; objectsRoot.name = "room-scene-objects"
        overlayRoot.name = "room-scene-overlay"; cameraEntity.name = "room-scene-camera"
    }
    public var statistics: RoomSceneStatistics { .init(nodeCount: entities.count,entityCount: entityCount(worldRoot),overlayPathCount: overlayEntities.count,meshCount: factory.meshCount,materialCount: factory.palette.count,activeSubscriptions: 0,isActive: isActive) }
    private func entityCount(_ root: Entity) -> Int { 1 + root.children.reduce(0) { $0 + entityCount($1) } }
    /// Idempotent reconcile; camera-only/selection-only updates don't rebuild geometry.
    public func reconcile(descriptor next: SceneDescriptor, overlay nextOverlay: RoomSceneOverlay = .empty, selection: SceneObjectKey?, dark: Bool) {
        guard isActive else { return }
        if roomRoot.parent == nil {
            worldRoot.addChild(roomRoot); worldRoot.addChild(objectsRoot); worldRoot.addChild(overlayRoot); worldRoot.addChild(cameraEntity)
            let light = Entity(); light.name = "room-scene-light"; light.components.set(DirectionalLightComponent(intensity: 2000))
            light.look(at: [0,0,0],from: [5,8,4],relativeTo: nil); worldRoot.addChild(light)
        }
        if lastProjectID == nil || lastProjectID != next.projectID {
            hasUserCamera = false
            if let bounds = next.bounds { camera.reset(bounds: bounds,aspectRatio: aspectRatio) }
        }
        lastProjectID = next.projectID
        let diff = SceneDiff(old: descriptor,new: next)
        let byKey = Dictionary(next.nodes.map { ($0.key,$0) },uniquingKeysWith: { first,_ in first })
        for key in diff.removed { entities.removeValue(forKey: key)?.removeFromParent() }
        for key in diff.added {
            guard let node = byKey[key] else { continue }
            let entity = factory.entity(node,dark: dark,selected: node.key.object == selection)
            (node.face == nil ? objectsRoot : roomRoot).addChild(entity); entities[key] = entity
        }
        for key in diff.geometry { if let node = byKey[key], let entity = entities[key] { factory.updateGeometry(entity,node: node,dark: dark,selected: key.object == selection) } }
        for key in diff.transform {
            guard let node = byKey[key], let entity = entities[key] else { continue }
            let p = CoordinateTransform.toApple(node.position); entity.position = [Float(p.x),Float(p.y),Float(p.z)]
        }
        for key in diff.selection { if let node = byKey[key], let entity = entities[key] { factory.updateInput(entity,selectable: node.selectable) } }
        let changedSelection = selectedKey != selection
        let paletteChanged = self.dark != dark
        let materialChanges = Set(diff.material)
        for node in next.nodes where paletteChanged || materialChanges.contains(node.key) || (changedSelection && (node.key.object == selection || node.key.object == selectedKey)) {
            if let entity = entities[node.key] { factory.updateMaterial(entity,role: node.material,dark: dark,selected: node.key.object == selection) }
        }
        for node in next.nodes { entities[node.key]?.isEnabled = visibility.isVisible(node,camera: camera) }
        selectedKey = selection; self.dark = dark; descriptor = next
        reconcileOverlay(nextOverlay,dark: dark,forceMaterial: paletteChanged)
        RoomCameraController.update(cameraEntity,state: camera,bounds: next.bounds)
    }
    private func reconcileOverlay(_ next: RoomSceneOverlay, dark: Bool, forceMaterial: Bool) {
        let paths = next.validationMessage == nil ? next.paths : []
        let previous = Dictionary(overlay.paths.map { ($0.id,$0) },uniquingKeysWith: { first,_ in first })
        let ids = Set(paths.map(\.id))
        for id in Array(overlayEntities.keys) where !ids.contains(id) { overlayEntities.removeValue(forKey: id)?.removeFromParent() }
        for path in paths where previous[path.id] != path || forceMaterial || overlayEntities[path.id] == nil {
            overlayEntities.removeValue(forKey: path.id)?.removeFromParent()
            let entity = factory.overlayPath(path,dark: dark); overlayRoot.addChild(entity); overlayEntities[path.id] = entity
        }
        overlay = next.validationMessage == nil ? next : .empty
    }
    public func updateViewport(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        let nextAspect = width/height
        guard abs(nextAspect-aspectRatio) > 1e-6 else { return }
        aspectRatio = nextAspect
        if !hasUserCamera, let bounds = descriptor?.bounds { camera.reset(bounds: bounds,aspectRatio: aspectRatio) }
    }
    public func setCamera(_ value: RoomCameraState) { hasUserCamera = true; camera = value }
    public func orbit(horizontalDegrees: Double, verticalDegrees: Double = 0) { hasUserCamera = true; camera.orbit(horizontalDegrees: horizontalDegrees,verticalDegrees: verticalDegrees) }
    public func zoom(factor: Double) { guard let bounds = descriptor?.bounds else { return }; hasUserCamera = true; camera.zoom(factor: factor,roomBounds: bounds) }
    public func reset() { guard let bounds = descriptor?.bounds else { return }; hasUserCamera = false; camera.reset(bounds: bounds,aspectRatio: aspectRatio) }
    public func top() { guard let bounds = descriptor?.bounds else { return }; hasUserCamera = true; camera.top(bounds: bounds,aspectRatio: aspectRatio) }
    public func focus(_ key: SceneObjectKey?) {
        guard let roomBounds = descriptor?.bounds, let bounds = descriptor?.object(key)?.focusBounds else { return }
        hasUserCamera = true; camera.focus(bounds,roomBounds: roomBounds,aspectRatio: aspectRatio)
    }
    public func showCeiling(_ value: Bool) { visibility.showCeiling = value }
    public func hideFacingWalls(_ value: Bool) { visibility.hideFacingWalls = value }
    public func pick(x: Double, y: Double, width: Double, height: Double) -> SceneObjectKey? {
        guard let descriptor, let ray = camera.ray(x: x,y: y,viewportWidth: width,viewportHeight: height) else { return nil }
        return RoomSceneHitTester.hit(ray: ray,descriptor: descriptor,camera: camera,visibility: visibility)?.key
    }
    public func resume() { isActive = true; worldRoot.isEnabled = true }
    public func setForeground(_ value: Bool) { worldRoot.isEnabled = value && isActive }
    public func suspend() {
        isActive = false
        for child in Array(worldRoot.children) { child.removeFromParent() }
        for root in [roomRoot,objectsRoot,overlayRoot] { for child in Array(root.children) { child.removeFromParent() } }
        entities.removeAll(); overlayEntities.removeAll(); descriptor = nil; overlay = .empty; selectedKey = nil
        factory.clearCaches()
    }
    public func clearReusableCaches() { factory.clearCaches() }
}
