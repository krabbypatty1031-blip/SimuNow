import Foundation
import SimuCore

/// Pure layout math for the read-only 3D room preview. Converts domain model geometry
/// (metres, right-handed Z-up) into Apple display coordinates via CoordinateTransform.
/// Contains no field data: the preview shows geometry only, never simulated results.
public struct RoomPreviewLayout: Equatable, Sendable {

    public enum BoxKind: Equatable, Sendable {
        case floor, wall, door, window, obstacle, device, seat, sample
    }

    public struct Box: Equatable, Sendable {
        public let kind: BoxKind
        public let center: Position3D  // Apple Y-up metres
        public let size: Position3D    // positive extents, Apple coords
        /// Unit direction in Apple coords. Devices use the supply direction; other kinds ignore it.
        public let facing: Direction3D

        public init(kind: BoxKind, center: Position3D, size: Position3D, facing: Direction3D = Direction3D(x: 0, y: 0, z: 1)) {
            self.kind = kind
            self.center = center
            self.size = size
            self.facing = facing
        }
    }

    /// Schematic people and monitors. Positions come from occupants and equipment;
    /// the mesh size is a display convention and is not a measured body or device.
    public enum FigureKind: Equatable, Sendable {
        case person, monitor
    }

    public struct Figure: Equatable, Sendable {
        public let kind: FigureKind
        public let position: Position3D // Apple Y-up metres
    }

    public struct Arrow: Equatable, Sendable {
        public let base: Position3D        // port position, Apple coords
        public let direction: Direction3D  // unit vector, Apple coords
        public let role: PortRole
        public let length: Double
    }

    public let roomCenter: Position3D  // Apple coords
    public let roomSize: Position3D    // domain (width, depth, height)
    public let boxes: [Box]
    public let arrows: [Arrow]
    public let figures: [Figure]

    /// Stable identity for view rebuilds (edits are infrequent; orbit gestures must not rebuild).
    public var fingerprint: String {
        var parts = ["room(\(roomSize.x),\(roomSize.y),\(roomSize.z))"]
        for box in boxes {
            parts.append("\(box.kind):\(box.center.x),\(box.center.y),\(box.center.z):\(box.size.x),\(box.size.y),\(box.size.z):\(box.facing.x),\(box.facing.y),\(box.facing.z)")
        }
        for arrow in arrows {
            parts.append("\(arrow.role):\(arrow.base.x),\(arrow.base.y),\(arrow.base.z):\(arrow.direction.x),\(arrow.direction.y),\(arrow.direction.z)")
        }
        for figure in figures {
            parts.append("\(figure.kind):\(figure.position.x),\(figure.position.y),\(figure.position.z)")
        }
        return parts.joined(separator: "|")
    }

    /// Orbit camera offset around a center: horizontal ring in the Apple XZ plane,
    /// elevation above it. `radius` is caller-chosen (see `suggestedDistance`).
    public static func cameraOffset(azimuth: Double, elevation: Double, radius: Double) -> Position3D {
        Position3D(x: radius * cos(elevation) * sin(azimuth),
                   y: radius * sin(elevation),
                   z: radius * cos(elevation) * cos(azimuth))
    }

    public static func suggestedDistance(roomSize: Position3D) -> Double {
        max(roomSize.x, roomSize.y, roomSize.z) * 2.2 + 0.5
    }

    public static let wallThickness = 0.02
    public static let arrowLength = 0.4

    /// Build from the domain model. Returns nil when the room shape is not a known
    /// rectangular room with known dimensions (the preview shows nothing rather than guessing).
    public static func build(room: Room, obstacles: [Obstacle], seats: [Seat], devices: [HVACDevice],
                             registry: ModelRegistry, occupants: [Occupant] = [],
                             equipment: [EquipmentGain] = []) -> RoomPreviewLayout? {
        guard let payload = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
              let w = payload.dimensions.width.value,
              let d = payload.dimensions.depth.value,
              let h = payload.dimensions.height.value else { return nil }
        var boxes: [Box] = []
        var arrows: [Arrow] = []
        var figures: [Figure] = []
        let t = wallThickness

        // Floor + ceiling-thin base and four walls (translucent at draw time).
        boxes.append(Box(kind: .floor, center: apple(x: w / 2, y: d / 2, z: 0), size: appleSize(w, t, d)))
        boxes.append(Box(kind: .wall, center: apple(x: 0, y: d / 2, z: h / 2), size: appleSize(t, h, d)))
        boxes.append(Box(kind: .wall, center: apple(x: w, y: d / 2, z: h / 2), size: appleSize(t, h, d)))
        boxes.append(Box(kind: .wall, center: apple(x: w / 2, y: 0, z: h / 2), size: appleSize(w, h, t)))
        boxes.append(Box(kind: .wall, center: apple(x: w / 2, y: d, z: h / 2), size: appleSize(w, h, t)))

        // Openings as thin panels on their surface (door/window), from local U/V coordinates.
        for opening in room.openings {
            guard let u = opening.offsetU.value, let v = opening.offsetV.value,
                  let ow = opening.width.value, let oh = opening.height.value,
                  let surface = room.surfaces.first(where: { $0.id == opening.surfaceID }) else { continue }
            let kind: BoxKind = opening.kind == .window ? .window : .door
            switch surface.face {
            case .xMin, .xMax:
                let x = surface.face == .xMin ? 0.0 : w
                boxes.append(Box(kind: kind, center: apple(x: x, y: u + ow / 2, z: v + oh / 2), size: appleSize(t, oh, ow)))
            case .yMin, .yMax:
                let y = surface.face == .yMin ? 0.0 : d
                boxes.append(Box(kind: kind, center: apple(x: u + ow / 2, y: y, z: v + oh / 2), size: appleSize(ow, oh, t)))
            case .floor, .ceiling:
                let z = surface.face == .floor ? 0.0 : h
                boxes.append(Box(kind: kind, center: apple(x: u + ow / 2, y: v + oh / 2, z: z), size: appleSize(ow, t, oh)))
            }
        }

        for obstacle in obstacles {
            guard let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry),
                  let bw = box.dimensions.width.value, let bd = box.dimensions.depth.value, let bh = box.dimensions.height.value else { continue }
            boxes.append(Box(kind: .obstacle,
                             center: apple(x: box.origin.x + bw / 2, y: box.origin.y + bd / 2, z: box.origin.z + bh / 2),
                             size: appleSize(bw, bh, bd)))
        }

        for seat in seats {
            boxes.append(Box(kind: .seat, center: apple(seat.position), size: appleSize(0.14, 0.14, 0.14)))
            for sample in seat.samples {
                boxes.append(Box(kind: .sample, center: apple(sample.position), size: appleSize(0.05, 0.05, 0.05)))
            }
        }

        for device in devices {
            // The device marker size is a display convention (the model stores position, not dimensions).
            let supply = device.ports.first { $0.role == .supply }?.direction ?? Direction3D(x: 0, y: -1, z: 0)
            boxes.append(Box(kind: .device, center: apple(device.position), size: appleSize(0.32, 0.22, 0.22),
                             facing: CoordinateTransform.toApple(supply)))
            for port in device.ports {
                arrows.append(Arrow(base: apple(port.position), direction: CoordinateTransform.toApple(port.direction),
                                    role: port.role, length: arrowLength))
            }
        }

        let occupied = Set(occupants.map(\.seatID))
        for seat in seats where occupied.contains(seat.id) {
            figures.append(Figure(kind: .person, position: apple(seat.position)))
        }
        for item in equipment {
            figures.append(Figure(kind: .monitor, position: apple(item.position)))
        }

        return RoomPreviewLayout(roomCenter: apple(x: w / 2, y: d / 2, z: h / 2),
                                 roomSize: Position3D(x: w, y: d, z: h),
                                 boxes: boxes, arrows: arrows, figures: figures)
    }

    // MARK: - Coordinate helpers (domain → Apple Y-up)

    private static func apple(_ p: Position3D) -> Position3D { CoordinateTransform.toApple(p) }
    private static func apple(x: Double, y: Double, z: Double) -> Position3D {
        CoordinateTransform.toApple(Position3D(x: x, y: y, z: z))
    }

    /// Domain sizes (w along X, d along Y, h along Z) → Apple extents (x, y, z) as positives.
    private static func appleSize(_ w: Double, _ h: Double, _ d: Double) -> Position3D {
        Position3D(x: w, y: h, z: d)
    }
}
