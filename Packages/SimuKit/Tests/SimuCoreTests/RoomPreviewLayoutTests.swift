import Foundation
import Testing
@testable import SimuCore
@testable import SimuVisualization

struct RoomPreviewLayoutTests {
    private func template() -> ProjectDocument { ProjectTemplates.office() }

    @Test func layoutBuildsRoomWallsOpeningsAndEntities() throws {
        let project = template()
        let room = try #require(project.geometry.rooms.first)
        let layout = try #require(RoomPreviewLayout.build(
            room: room, obstacles: project.geometry.obstacles,
            seats: project.scenarios[0].inputs.usage.seats,
            devices: project.scenarios[0].inputs.hvac, registry: .builtIn))
        // 5×4×2.8 m room (domain) → center in Apple coords (x, z, -y mapped).
        #expect(layout.roomSize == Position3D(x: 5, y: 4, z: 2.8))
        #expect(layout.roomCenter == Position3D(x: 2.5, y: 1.4, z: -2))
        let kinds = layout.boxes.map(\.kind)
        #expect(kinds.filter { $0 == .floor }.count == 1)
        #expect(kinds.filter { $0 == .wall }.count == 4)
        #expect(kinds.filter { $0 == .window }.count == 1)
        #expect(kinds.filter { $0 == .door }.count == 1)
        #expect(kinds.filter { $0 == .obstacle }.count == 4)      // four desks
        #expect(kinds.filter { $0 == .seat }.count == 4)
        #expect(kinds.filter { $0 == .sample }.count == 12)       // 3 samples per seat
        #expect(layout.arrows.count == 2)                          // supply + return
        #expect(Set(layout.arrows.map(\.role)) == [.supply, .return])

        // Floor: domain center (2.5, 2, 0) → Apple (2.5, 0, -2); extents (5, 0.02, 4).
        let floor = try #require(layout.boxes.first { $0.kind == .floor })
        #expect(floor.center == Position3D(x: 2.5, y: 0, z: -2))
        #expect(floor.size == Position3D(x: 5, y: 0.02, z: 4))

        // Window on yMax (domain y=4): offsetU 1.5, offsetV 1.0, 2.0×1.2 → Apple center (2.5, 1.6, -4).
        let window = try #require(layout.boxes.first { $0.kind == .window })
        #expect(window.center == Position3D(x: 2.5, y: 1.6, z: -4))
        #expect(window.size == Position3D(x: 2, y: 1.2, z: 0.02))

        // Supply port points −Y in domain → Apple +Z.
        let supply = try #require(layout.arrows.first { $0.role == .supply })
        #expect(supply.direction == Direction3D(x: 0, y: 0, z: 1))
        #expect(supply.length > 0)
    }

    @Test func layoutRejectsUnknownDimensions() {
        var room = Room(id: UUID(), name: "r",
                        shape: try! ExtensionRecord(RectangularRoom(dimensions: .init(
                            width: .unknown(reason: "no data"),
                            depth: .known(value: 4, source: .init(kind: .user)),
                            height: .known(value: 3, source: .init(kind: .user))))),
                        northAngle: .unknown(reason: "x"), surfaces: [], openings: [])
        room.id = UUID()
        #expect(RoomPreviewLayout.build(room: room, obstacles: [], seats: [], devices: [], registry: .builtIn) == nil)
    }

    @Test func cameraOffsetMathAndFingerprintStability() {
        // Elevation 0 → offset lies in the horizontal ring at the given radius.
        let flat = RoomPreviewLayout.cameraOffset(azimuth: 0, elevation: 0, radius: 3)
        #expect(flat == Position3D(x: 0, y: 0, z: 3))
        let up = RoomPreviewLayout.cameraOffset(azimuth: 0, elevation: .pi / 2, radius: 3)
        #expect(abs(up.y - 3) < 1e-9)
        #expect(RoomPreviewLayout.suggestedDistance(roomSize: Position3D(x: 5, y: 4, z: 2.8)) == 5 * 2.2 + 0.5)

        let project = template()
        let room = project.geometry.rooms[0]
        let args = (room: room, obstacles: project.geometry.obstacles,
                    seats: project.scenarios[0].inputs.usage.seats,
                    devices: project.scenarios[0].inputs.hvac)
        let first = RoomPreviewLayout.build(room: args.room, obstacles: args.obstacles, seats: args.seats,
                                            devices: args.devices, registry: .builtIn)
        let second = RoomPreviewLayout.build(room: args.room, obstacles: args.obstacles, seats: args.seats,
                                             devices: args.devices, registry: .builtIn)
        #expect(first?.fingerprint == second?.fingerprint)
        var moved = project
        moved.geometry.obstacles.removeFirst()
        let changed = RoomPreviewLayout.build(room: moved.geometry.rooms[0], obstacles: moved.geometry.obstacles,
                                              seats: args.seats, devices: args.devices, registry: .builtIn)
        #expect(changed?.fingerprint != first?.fingerprint)
    }

    @Test func officePreviewAddsSchematicPeopleMonitorsAndSupplyFacing() throws {
        let project = template()
        let scenario = project.scenarios[0]
        let layout = try #require(RoomPreviewLayout.build(
            room: project.geometry.rooms[0],
            obstacles: project.geometry.obstacles,
            seats: scenario.inputs.usage.seats,
            devices: scenario.inputs.hvac,
            registry: .builtIn,
            occupants: scenario.inputs.usage.occupants,
            equipment: scenario.inputs.usage.equipment))
        #expect(layout.figures.filter { $0.kind == .person }.count == 4)
        #expect(layout.figures.filter { $0.kind == .monitor }.count == 4)
        let person = try #require(layout.figures.first { $0.kind == .person })
        #expect(person.position == Position3D(x: 1.4, y: 0, z: -1.2))
        let monitor = try #require(layout.figures.first { $0.kind == .monitor })
        #expect(monitor.position.y == 0.76)
        let device = try #require(layout.boxes.first { $0.kind == .device })
        #expect(device.facing == Direction3D(x: 0, y: 0, z: 1))
        let classroom = ProjectTemplates.classroom()
        let classLayout = try #require(RoomPreviewLayout.build(
            room: classroom.geometry.rooms[0],
            obstacles: classroom.geometry.obstacles,
            seats: classroom.scenarios[0].inputs.usage.seats,
            devices: classroom.scenarios[0].inputs.hvac,
            registry: .builtIn,
            occupants: classroom.scenarios[0].inputs.usage.occupants,
            equipment: classroom.scenarios[0].inputs.usage.equipment))
        #expect(classLayout.figures.filter { $0.kind == .person }.count == 12)
        #expect(classLayout.figures.filter { $0.kind == .monitor }.isEmpty)
    }
}
