import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuVisualization
import SimuWorkspace
import RealityKit

/// Synthetic F-A/F-B values, with fixed UUIDs; not measured airflow or physical benchmarks.
private func n2ID(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d",n))! }
private func n2Length(_ v: Double) -> Length { .known(value: v,source: .init(kind: .assumed,reference: "synthetic.N2",note: "Test geometry only.")) }
private func n2Fixture(obstacle: Bool = false, openings: Bool = false) throws -> ProjectDocument {
    let roomID = n2ID(1)
    let surfaces = SurfaceFace.allCases.enumerated().map { Surface(id: n2ID(2+$0.offset),face: $0.element) }
    var values: [Opening] = []
    if openings {
        values = [.init(id: n2ID(80),surfaceID: surfaces.first { $0.face == .xMin }!.id,kind: .door,offsetU: n2Length(1),offsetV: n2Length(0),width: n2Length(0.8),height: n2Length(2.1)),
                  .init(id: n2ID(81),surfaceID: surfaces.first { $0.face == .yMax }!.id,kind: .window,offsetU: n2Length(1.1),offsetV: n2Length(1.2),width: n2Length(1.2),height: n2Length(1))]
    }
    let room = Room(id: roomID,name: "Synthetic 6×4×3",shape: try .init(RectangularRoom(dimensions: .init(width: n2Length(6),depth: n2Length(4),height: n2Length(3)))),northAngle: .unknown(reason: "Synthetic orientation not supplied"),surfaces: surfaces,openings: values)
    let positions = [Position3D(x: 2,y: 2,z: 1.5),Position3D(x: 4,y: 2,z: 1.5),Position3D(x: 2,y: 0.5,z: 1.5)]
    let seats = positions.enumerated().map { Seat(id: n2ID(30+$0.offset),roomID: roomID,name: ["A","B","C"][$0.offset],position: $0.element,samples: [.init(id: n2ID(40+$0.offset),position: .init(x: $0.element.x,y: $0.element.y,z: $0.element.z+0.1))]) }
    let split = SingleSplit(coolingCapacity: .unknown(reason: "Test has no capacity"),electricalPower: .unknown(reason: "Test has no power"),cop: .unknown(reason: "Test has no COP"))
    let port = AirPort(id: n2ID(21),role: .supply,position: .init(x: 0.05,y: 2,z: 1.5),direction: .init(x: 1,y: 0,z: 0),area: .unknown(reason: "Test"),volumeFlow: .unknown(reason: "Test"),speed: .unknown(reason: "Test"),density: .unknown(reason: "Test"))
    let device = HVACDevice(id: n2ID(20),roomID: roomID,name: "Synthetic split",position: .init(x: 0.05,y: 2,z: 1.5),definition: try .init(split),ports: [port],supplyTemperature: .unknown(reason: "Test"))
    var scenario = Scenario.unfinished(id: n2ID(10),name: "Synthetic baseline"); scenario.inputs.usage.seats = seats; scenario.inputs.hvac = [device]
    var obstacles: [Obstacle] = []
    if obstacle { obstacles = [.init(id: n2ID(70),roomID: roomID,name: "Synthetic thin box",shape: try .init(BoxObstacle(origin: .init(x: 3,y: 1.5,z: 0),dimensions: .init(width: n2Length(0.05),depth: n2Length(1),height: n2Length(2)))))] }
    return .init(id: n2ID(100),name: "Synthetic N2",spaceType: .office,geometry: .init(rooms: [room],obstacles: obstacles),scenarios: [scenario])
}
private func n2Near(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool { abs(a-b) <= tolerance }
private func n2Dot(_ a: Direction3D, _ b: Direction3D) -> Double { a.x*b.x+a.y*b.y+a.z*b.z }
private func n2Cross(_ a: Direction3D, _ b: Direction3D) -> Direction3D { .init(x: a.y*b.z-a.z*b.y,y: a.z*b.x-a.x*b.z,z: a.x*b.y-a.y*b.x) }

@Test func roomSceneCoordinatesKeepHandednessAndPositiveDimensions() throws {
    for (domain,apple) in [(Direction3D(x: 1,y: 0,z: 0),Direction3D(x: 1,y: 0,z: 0)),(.init(x: 0,y: 1,z: 0),.init(x: 0,y: 0,z: -1)),(.init(x: 0,y: 0,z: 1),.init(x: 0,y: 1,z: 0))] {
        #expect(CoordinateTransform.toApple(domain) == apple)
        #expect(CoordinateTransform.toDomain(apple) == domain)
    }
    #expect(CoordinateTransform.appleDimensions(.init(x: 6,y: 4,z: 3)) == .init(x: 6,y: 3,z: 4))
    let point = Position3D(x: 1.25,y: -3.5,z: 0.75)
    #expect(CoordinateTransform.toDomain(CoordinateTransform.toApple(point)) == point)
}
@Test func roomSceneBoxesUseCentersAndNeverRepeatNorthRotation() throws {
    var project = try n2Fixture(obstacle: true)
    project.geometry.obstacles[0].shape = try .init(BoxObstacle(origin: .init(x: 1,y: 2,z: 0.5),dimensions: .init(width: n2Length(2),depth: n2Length(1),height: n2Length(1))))
    let first = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    let box = try #require(first.nodes.first { $0.key.object.modelID == n2ID(70) })
    #expect(box.position == .init(x: 2,y: 2.5,z: 1))
    #expect(box.geometry == .box(size: .init(x: 2,y: 1,z: 1)))
    project.geometry.rooms[0].northAngle = .known(value: 90,source: .init(kind: .assumed,reference: "synthetic.N2"))
    let second = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    #expect(second.nodes.filter { $0.key.part != "north-reference" } == first.nodes)
    #expect(second.bounds == .init(origin: .init(x: 0,y: 0,z: 0),size: .init(x: 6,y: 4,z: 3)))
}
@Test func roomSceneOpeningMapsAllSixFacesAndPreservesOutwardWinding() throws {
    let bounds = GeometryBounds(origin: .init(x: 0,y: 0,z: 0),size: .init(x: 6,y: 4,z: 3))
    let expected: [SurfaceFace: Position3D] = [.xMin: .init(x: 0,y: 1.2,z: 0.7),.xMax: .init(x: 6,y: 1.2,z: 0.7),.yMin: .init(x: 1.2,y: 0,z: 0.7),.yMax: .init(x: 1.2,y: 4,z: 0.7),.floor: .init(x: 1.2,y: 0.7,z: 0),.ceiling: .init(x: 1.2,y: 0.7,z: 3)]
    for face in SurfaceFace.allCases {
        #expect(OpeningGeometry.point(face,u: 1.2,v: 0.7,bounds: bounds) == expected[face])
        let quad = OpeningGeometry.quad(face,rectangle: .init(u: 0.3,v: 0.4,width: 0.7,height: 0.8),bounds: bounds)
        let a = Direction3D(x: quad[1].x-quad[0].x,y: quad[1].y-quad[0].y,z: quad[1].z-quad[0].z)
        let b = Direction3D(x: quad[2].x-quad[1].x,y: quad[2].y-quad[1].y,z: quad[2].z-quad[1].z)
        #expect(n2Dot(n2Cross(a,b),OpeningGeometry.normal(face)) > 0)
        #expect(n2Dot(n2Cross(CoordinateTransform.toApple(a),CoordinateTransform.toApple(b)),CoordinateTransform.toApple(OpeningGeometry.normal(face))) > 0)
    }
}
@Test func roomSceneOpeningsSubtractRealWallCellsAndKeepThicknessOutside() throws {
    let bounds = GeometryBounds(origin: .init(x: 0,y: 0,z: 0),size: .init(x: 6,y: 4,z: 3))
    let openings = [SurfaceRectangle(u: 0.5,v: 0,width: 0.9,height: 2),.init(u: 3,v: 1,width: 1.2,height: 0.8)]
    let cells = try OpeningGeometry.wallCells(face: .yMax,bounds: bounds,openings: openings)
    #expect(n2Near(cells.reduce(0) { $0+$1.width*$1.height },18-1.8-0.96))
    for cell in cells {
        #expect(!openings.contains { $0.contains(u: cell.u+cell.width/2,v: cell.v+cell.height/2) })
        let box = OpeningGeometry.wallBox(face: .yMax,rectangle: cell,bounds: bounds)
        #expect(n2Near(box.center.y-box.size.y/2,4)); #expect(box.size.y == 0.02)
    }
    for face in SurfaceFace.allCases {
        let e = OpeningGeometry.extent(face,bounds: bounds)
        let box = OpeningGeometry.wallBox(face: face,rectangle: .init(u: 0,v: 0,width: e.u,height: e.v),bounds: bounds)
        let p = OpeningGeometry.point(face,u: e.u/2,v: e.v/2,bounds: bounds), n = OpeningGeometry.normal(face)
        #expect(n2Near((box.center.x-p.x)*n.x+(box.center.y-p.y)*n.y+(box.center.z-p.z)*n.z,0.01))
    }
    #expect(throws: OpeningGeometryError.tooManyCells) { try OpeningGeometry.wallCells(face: .yMax,bounds: bounds,openings: openings,maximumCells: 1) }
}
@Test func roomSceneUnknownAndInvalidGeometryHasReasonsAndNoReplacement() throws {
    var project = try n2Fixture(obstacle: true,openings: true)
    project.geometry.obstacles[0].shape = .init(kind: "future.obstacle",payloadVersion: 99,payload: try .init(data: Data("{\"huge\":123456789012345678901234567890}".utf8)))
    project.geometry.rooms[0].openings[0].width = .unknown(reason: "Not measured")
    let descriptor = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    #expect(descriptor.issues.contains { $0.key?.modelID == n2ID(70) && $0.code == "unsupported_obstacle" })
    #expect(!descriptor.nodes.contains { $0.key.object.modelID == n2ID(70) })
    #expect(descriptor.objects.contains { $0.key.modelID == n2ID(70) })
    #expect(!descriptor.nodes.contains { $0.key.object.modelID == n2ID(80) })
    #expect(descriptor.issues.contains { $0.code == "invalid_opening" })
    let wall = descriptor.nodes.filter { $0.face == .xMin && $0.material == .wall }
    #expect(wall.count == 1)
    project.geometry.obstacles[0].shape = try .init(BoxObstacle(origin: .init(x: 1_000_001,y: 0,z: 0),dimensions: .init(width: n2Length(1),depth: n2Length(1),height: n2Length(1))))
    #expect(!RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)).nodes.contains { $0.key.object.modelID == n2ID(70) })
}
@Test func roomSceneDuplicateIdentitiesAndUnsupportedRoomCannotMintNodes() throws {
    var project = try n2Fixture(obstacle: true)
    project.geometry.obstacles.append(project.geometry.obstacles[0])
    project.scenarios[0].inputs.usage.seats[0].id = n2ID(70)
    let descriptor = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    #expect(descriptor.issues.contains { $0.code == "duplicate_id" })
    #expect(descriptor.nodes.filter { $0.key.object.modelID == n2ID(70) }.count == 1)
    #expect(Set(descriptor.nodes.map(\.key)).count == descriptor.nodes.count)
    project.geometry.rooms[0].shape = .init(kind: "future.room",payloadVersion: 99,payload: .object([:]))
    let unknown = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    #expect(unknown.bounds == nil && unknown.nodes.isEmpty)
    #expect(unknown.issues.contains { $0.code == "unsupported_room" })
}
@Test func roomSceneSymbolsPreserveModelIDsAndExplainTheirSizes() throws {
    let project = try n2Fixture()
    let descriptor = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    let device = try #require(descriptor.object(.init(category: .hvac,modelID: n2ID(20))))
    #expect(device.detail.contains("没有机身尺寸"))
    #expect(device.target == .object(.init(kind: .hvac,objectID: n2ID(20))))
    #expect(descriptor.nodes.filter { $0.key.object == device.key }.allSatisfy { if case .sphere = $0.geometry { true } else { false } })
    let port = try #require(descriptor.nodes.first { $0.key.object.modelID == n2ID(21) && $0.key.part == "direction" })
    #expect(port.position == .init(x: 0.05,y: 2,z: 1.5))
    #expect(port.geometry == .arrow(direction: .init(x: 1,y: 0,z: 0),length: 0.5,radius: 0.014))
}
@Test func roomSceneDiffMovesOnlyTheChangedObjectAndKeepsRevisionStable() throws {
    var project = try n2Fixture(obstacle: true)
    let before = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    #expect(RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)).revision == before.revision)
    var box = try #require(try project.geometry.obstacles[0].shape.resolved(as: BoxObstacle.self,registry: .builtIn)); box.origin.x += 0.2
    project.geometry.obstacles[0].shape = try .init(box)
    let after = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)), diff = SceneDiff(old: before,new: after)
    #expect(diff.added.isEmpty && diff.removed.isEmpty && diff.geometry.isEmpty && diff.material.isEmpty)
    #expect(diff.transform == [.init(object: .init(category: .furniture,modelID: n2ID(70)),part: "box")])
    #expect(after.revision != before.revision)
    #expect(SceneDiff(old: after,new: after).isEmpty)
}
@Test func roomSceneCameraFitsPortraitAndLandscapeWithoutMirroring() throws {
    let bounds = GeometryBounds(origin: .init(x: 0,y: 0,z: 0),size: .init(x: 6,y: 4,z: 3))
    for aspect in [0.3,1,3] {
        let camera = RoomCameraState.fitting(bounds: bounds,aspectRatio: aspect)
        let centerRay = try #require(camera.ray(x: aspect*500,y: 500,viewportWidth: aspect*1000,viewportHeight: 1000))
        #expect(n2Near(n2Dot(centerRay.direction,camera.forward),1))
        #expect(n2Near(n2Dot(camera.right,camera.up),0))
        for x in [0.0,6] { for y in [0.0,4] { for z in [0.0,3] {
            let delta = Direction3D(x: x-camera.position.x,y: y-camera.position.y,z: z-camera.position.z)
            let depth = n2Dot(delta,camera.forward), vertical = tan(camera.fieldOfViewDegrees * .pi/360)
            #expect(abs(n2Dot(delta,camera.right)/(depth*vertical*aspect)) <= 1/1.1)
            #expect(abs(n2Dot(delta,camera.up)/(depth*vertical)) <= 1/1.1)
        } } }
        let left = try #require(camera.ray(x: 0,y: 500,viewportWidth: aspect*1000,viewportHeight: 1000))
        #expect(n2Dot(left.direction,camera.right) < 0)
    }
}
@Test func roomSceneCameraPresetsFocusAndRepeatedZoomStayFinite() throws {
    let bounds = GeometryBounds(origin: .init(x: 0,y: 0,z: 0),size: .init(x: 6,y: 4,z: 3)), d = sqrt(61.0)
    var camera = RoomCameraState.fitting(bounds: bounds,aspectRatio: 0.5)
    camera.top(bounds: bounds,aspectRatio: 0.5)
    #expect(camera.pitchDegrees == 89 && camera.up.z > 0)
    camera.orbit(horizontalDegrees: 720,verticalDegrees: 1000); #expect(camera.pitchDegrees == 89)
    for _ in 0..<1000 { camera.zoom(factor: 1.5,roomBounds: bounds) }; #expect(n2Near(camera.distance,d*5))
    for _ in 0..<1000 { camera.zoom(factor: 0.5,roomBounds: bounds) }; #expect(n2Near(camera.distance,d*0.25))
    camera.focus(.init(origin: .init(x: 1,y: 2,z: 0.5),size: .init(x: 2,y: 1,z: 1)),roomBounds: bounds,aspectRatio: 0.5)
    #expect(camera.target == .init(x: 2,y: 2.5,z: 1))
    #expect([camera.position.x,camera.position.y,camera.position.z].allSatisfy { $0.isFinite })
    let old = camera; camera.zoom(factor: .infinity,roomBounds: bounds); #expect(camera == old)
    camera.reset(bounds: bounds,aspectRatio: 0.5); #expect(camera == .fitting(bounds: bounds,aspectRatio: 0.5))
}
@Test func roomScenePickingSelectsNearestVisibleGeometryAndRespectsOpenings() throws {
    var project = try n2Fixture(openings: true)
    project.scenarios[0].inputs.usage = .init(); project.scenarios[0].inputs.hvac = []
    let descriptor = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    let bounds = try #require(descriptor.bounds), camera = RoomCameraState.fitting(bounds: bounds,aspectRatio: 1)
    let ray = RoomPickingRay(origin: .init(x: -2,y: 1.4,z: 1),direction: .init(x: 1,y: 0,z: 0))
    let hit = try #require(RoomSceneHitTester.hit(ray: ray,descriptor: descriptor,camera: camera,visibility: .init(showCeiling: true,hideFacingWalls: false)))
    #expect(hit.key.modelID == project.geometry.rooms[0].surfaces.first { $0.face == .xMax }?.id)
    let directWallRay = RoomPickingRay(origin: .init(x: -2,y: 3,z: 1),direction: .init(x: 1,y: 0,z: 0))
    #expect(RoomSceneHitTester.hit(ray: directWallRay,descriptor: descriptor,camera: camera,visibility: .init(hideFacingWalls: false))?.key.modelID == project.geometry.rooms[0].surfaces.first { $0.face == .xMin }?.id)
    let visibility = RoomSceneVisibility()
    #expect(!visibility.isVisible(try #require(descriptor.nodes.first { $0.face == .ceiling }),camera: camera))
    #expect(!visibility.isVisible(try #require(descriptor.nodes.first { $0.face == .xMax }),camera: camera))
}
@Test func roomSceneSelectionAdapterRevalidatesParentsDeletesAndScenarioScope() throws {
    var project = try n2Fixture()
    let sample = SceneObjectKey(category: .sample,modelID: n2ID(40)), port = SceneObjectKey(category: .port,modelID: n2ID(21))
    #expect(RoomSceneSelectionAdapter.target(for: sample,project: project,scenarioID: n2ID(10)) == .object(.init(kind: .sample,objectID: n2ID(40))))
    #expect(RoomSceneSelectionAdapter.target(for: port,project: project,scenarioID: n2ID(10)) == .object(.init(kind: .port,objectID: n2ID(21))))
    #expect(RoomSceneSelectionAdapter.target(for: port,project: project,scenarioID: n2ID(999)) == nil)
    project.scenarios[0].inputs.hvac.removeAll()
    #expect(RoomSceneSelectionAdapter.target(for: port,project: project,scenarioID: n2ID(10)) == nil)
    project.scenarios[0].inputs.usage.seats[0].samples.removeAll()
    #expect(RoomSceneSelectionAdapter.target(for: sample,project: project,scenarioID: n2ID(10)) == nil)
    project.scenarios.append(project.scenarios[0])
    #expect(RoomSceneSelectionAdapter.target(for: .init(category: .seat,modelID: n2ID(31)),project: project,scenarioID: n2ID(10)) == nil)
    #expect(RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)).nodes.allSatisfy { [.room,.surface,.opening,.furniture].contains($0.key.object.category) })
}
@Test @MainActor func roomSceneDisplayChangesDoNotTouchInputHashesOrUndo() throws {
    let project = try n2Fixture()
    let store = WorkspaceStore(); store.load(project)
    let configuration = AnalysisConfiguration(payload: .airflowPreview(.init()),acceptedAssumptions: [.genericCone])
    let resolver = AnalysisInputResolver(), method = AnalysisMethod(kind: .airflowPreview)
    let before = try resolver.request(project: project,scenarioID: n2ID(10),method: method,configuration: configuration,runID: n2ID(500))
    if #available(macOS 15, iOS 18, *) {
        let controller = RoomSceneController(bounds: RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)).bounds)
        controller.reconcile(descriptor: RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)),selection: nil,dark: false)
        controller.orbit(horizontalDegrees: 15); controller.zoom(factor: 0.8); controller.top(); controller.focus(.init(category: .seat,modelID: n2ID(30)))
        controller.showCeiling(true); controller.hideFacingWalls(false); controller.reset(); controller.suspend()
    }
    let after = try resolver.request(project: store.project!,scenarioID: n2ID(10),method: method,configuration: configuration,runID: n2ID(501))
    #expect(before.identity.inputHash == after.identity.inputHash && before.snapshotHash == after.snapshotHash)
    #expect(store.project == project && !store.canUndo)
}
@Test @MainActor func roomSceneControllerRetainsEntitiesAndCameraForSingleObjectDiff() throws {
    guard #available(macOS 15, iOS 18, *) else { return }
    var project = try n2Fixture(obstacle: true)
    let descriptor = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    let controller = RoomSceneController(bounds: descriptor.bounds)
    controller.reconcile(descriptor: descriptor,selection: nil,dark: false)
    let key = SceneNodeKey(object: .init(category: .furniture,modelID: n2ID(70)),part: "box")
    let entity = try #require(controller.worldRoot.findEntity(named: key.id))
    controller.orbit(horizontalDegrees: 20); let camera = controller.camera
    var box = try #require(try project.geometry.obstacles[0].shape.resolved(as: BoxObstacle.self,registry: .builtIn)); box.origin.x += 0.2; project.geometry.obstacles[0].shape = try .init(box)
    controller.reconcile(descriptor: RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)),selection: key.object,dark: true)
    #expect(controller.worldRoot.findEntity(named: key.id) === entity)
    #expect(controller.camera == camera)
    let apple = CoordinateTransform.toApple(Position3D(x: 3.225,y: 2,z: 1))
    #expect(n2Near(Double(entity.position.x),apple.x,tolerance: 1e-6))
    #expect(controller.statistics.meshCount <= 4 && controller.statistics.materialCount <= 60)
    controller.suspend(); #expect(controller.statistics.nodeCount == 0 && controller.statistics.meshCount == 0)
}
@Test @MainActor func roomSceneControllerTwentyLifecyclesAndWindowsAreIndependent() throws {
    guard #available(macOS 15, iOS 18, *) else { return }
    let descriptor = RoomSceneBuilder.build(project: try n2Fixture(),scenarioID: n2ID(10))
    let one = RoomSceneController(bounds: descriptor.bounds), two = RoomSceneController(bounds: descriptor.bounds)
    for _ in 0..<20 {
        one.resume(); one.reconcile(descriptor: descriptor,selection: nil,dark: false)
        #expect(one.statistics.nodeCount == descriptor.nodes.count && one.statistics.activeSubscriptions == 0)
        one.setForeground(false); one.setForeground(true); one.suspend()
        #expect(one.worldRoot.children.isEmpty && one.statistics.entityCount == 1 && one.statistics.materialCount == 0)
    }
    one.resume(); one.reconcile(descriptor: descriptor,selection: nil,dark: false)
    two.reconcile(descriptor: descriptor,selection: nil,dark: false)
    let before = two.camera; one.orbit(horizontalDegrees: 30); one.top()
    #expect(two.camera == before && two.worldRoot !== one.worldRoot)
    one.suspend(); two.suspend()
}
@Test func roomSceneOverlayRejectsInvalidPathsAndExposesNoAnalysisInference() throws {
    let p = Position3D(x: 1,y: 2,z: 3)
    #expect(RoomSceneOverlay(paths: [.init(id: "run/path0",points: [p,.init(x: 2,y: 2,z: 3)])],explanation: "Rule geometry only").validationMessage == nil)
    #expect(RoomSceneOverlay(paths: [.init(id: "bad",points: [p,.init(x: .nan,y: 0,z: 0)])],explanation: "").validationMessage != nil)
    #expect(RoomSceneOverlay(paths: [.init(id: "duplicate",points: [p,p]),.init(id: "duplicate",points: [p,p])],explanation: "").validationMessage != nil)
    #expect(RoomSceneOverlay(paths: [.init(id: "too-many",points: Array(repeating: p,count: 130))],explanation: "").validationMessage != nil)
}
@Test @MainActor func roomSceneCameraLeavesNativePackageAndOpaqueAttachmentsUnchanged() async throws {
    let project = try n2Fixture(openings: true)
    let document = try SimuNowDocument(project: project,metadata: .init(baselineScenarioID: n2ID(10)),preservedEntries: ["future": .directory(["opaque.json": .file(Data("{\"big\":123456789012345678901234567890}".utf8)),"binary.bin": .file(Data([0,255,42]))])])
    let before = try document.makeFileWrapper()
    if #available(macOS 15, iOS 18, *) {
        let descriptor = RoomSceneBuilder.build(project: project,scenarioID: n2ID(10)), controller = RoomSceneController(bounds: nil)
        controller.reconcile(descriptor: descriptor,selection: .init(category: .opening,modelID: n2ID(80)),dark: false)
        controller.top(); controller.hideFacingWalls(false); controller.showCeiling(true); controller.suspend()
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SimuNow-N2-package-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
    let url = root.appendingPathComponent("Synthetic.simunow"), io = ProjectPackageIO()
    try await io.writePackage(document,to: url)
    let reopened = try await io.readPackage(from: url), after = try reopened.makeFileWrapper()
    #expect(before.fileWrappers?["project.json"]?.regularFileContents == after.fileWrappers?["project.json"]?.regularFileContents)
    #expect(before.fileWrappers?["metadata.json"]?.regularFileContents == after.fileWrappers?["metadata.json"]?.regularFileContents)
    #expect(document.preservedEntries == reopened.preservedEntries)
}

@Test func roomSceneOldBuildCannotSelectNewInputsWithSharedNestedIDs() throws {
    var project = try n2Fixture()
    let frozen = RoomSceneBuildInput(project: project, scenarioID: n2ID(10))
    #expect(frozen.permitsSelection(currentProject: project, scenarioID: n2ID(10)))
    var candidate = project.scenarios[0]; candidate.id = n2ID(11); candidate.name = "Synthetic candidate"
    candidate.inputs.hvac[0].ports[0].direction = .init(x: 0,y: 1,z: 0)
    project.scenarios.append(candidate)
    #expect(!frozen.permitsSelection(currentProject: project, scenarioID: n2ID(11)))
    #expect(!frozen.permitsSelection(currentProject: project, scenarioID: n2ID(10)))
    let fresh = RoomSceneBuildInput(project: project, scenarioID: n2ID(11))
    #expect(fresh.permitsSelection(currentProject: project, scenarioID: n2ID(11)))
    project.scenarios[1].inputs.hvac[0].ports[0].position.x += 0.1
    #expect(!fresh.permitsSelection(currentProject: project, scenarioID: n2ID(11)))
}

@Test func roomSceneCancelledBackgroundBuildStopsBeforeCreatingNodes() async throws {
    let project = try n2Fixture()
    let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        return RoomSceneBuilder.build(project: project,scenarioID: n2ID(10))
    }
    task.cancel()
    let descriptor = await task.value
    #expect(descriptor.nodes.isEmpty && descriptor.objects.isEmpty)
    #expect(descriptor.issues.contains { $0.code == "display_cancelled" })
}
