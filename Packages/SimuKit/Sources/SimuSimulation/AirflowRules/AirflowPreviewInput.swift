import Foundation
import SimuCore

public struct PreviewObstacle: Equatable, Sendable {
    public let id: UUID
    public let bounds: GeometryBounds
    public init(id: UUID, bounds: GeometryBounds) {
        self.id = id
        self.bounds = bounds
    }
}
public struct AirflowPreviewInput: Sendable {
    public let roomID: UUID
    public let sourcePortID: UUID
    public let room: GeometryBounds
    public let field: RuleDirectionField
    public let obstacles: [PreviewObstacle]
    public let collisionIndex: PreviewCollisionIndex
    public let seats: [Seat]
    public let isWallSource: Bool
    public let notes: [String]
    public init(request: LocalAnalysisRequest, registry: ModelRegistry = .builtIn) throws {
        guard request.method == .init(kind: .airflowPreview),
            case .airflowPreview(let configuration) = request.resolvedInput.configuration.payload
        else { throw AirflowPreviewError.invalidInput("Wrong method") }
        let snapshot = request.resolvedInput.snapshot
        guard snapshot.geometry.rooms.count == 1, let room = snapshot.geometry.rooms.first,
            let model = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
            let bounds = model.geometryBounds(),
            [bounds.size.x, bounds.size.y, bounds.size.z].allSatisfy({ $0.isFinite && $0 > 0 }),
            snapshot.inputs.hvac.count == 1, let device = snapshot.inputs.hvac.first,
            device.roomID == room.id,
            (try? device.definition.resolved(as: SingleSplit.self, registry: registry)) != nil,
            device.ports.filter({ $0.role == .supply }).count == 1,
            let supply = device.ports.first(where: { $0.role == .supply })
        else {
            throw AirflowPreviewError.invalidInput(
                "One rectangular room, one split and one explicit supply required")
        }
        guard
            request.resolvedInput.adoptedAssumptions.contains(where: {
                $0.id == configuration.profileID && $0.version == configuration.profileVersion
                    && $0.source.kind == .assumed
            })
        else { throw AirflowPreviewError.invalidInput("Display assumption not adopted") }
        let profile = try PreviewProfile(configuration: configuration, room: bounds)
        let field = try RuleDirectionField(
            origin: supply.position, direction: supply.direction, profile: profile)
        let point = PreviewVector(supply.position)
        let lower = PreviewVector(bounds.origin)
        let upper = lower + PreviewVector(bounds.size)
        let direction = PreviewVector(field.axis)
        guard bounds.contains(supply.position, tolerance: 0) else {
            throw AirflowPreviewError.invalidInput("Supply outside room")
        }
        var wall = false
        for axis in 0..<3 {
            if abs(point[axis] - lower[axis]) <= 1e-6 {
                wall = true
                guard direction[axis] > 1e-9 else {
                    throw AirflowPreviewError.invalidInput("Wall source must point strictly inward")
                }
            }
            if abs(point[axis] - upper[axis]) <= 1e-6 {
                wall = true
                guard direction[axis] < -1e-9 else {
                    throw AirflowPreviewError.invalidInput("Wall source must point strictly inward")
                }
            }
        }
        guard snapshot.geometry.obstacles.count <= request.limits.maximumObstacles,
            snapshot.inputs.usage.seats.reduce(0, { $0 + max(1, $1.samples.count) })
                <= request.limits.maximumTargets,
            configuration.pathCount <= request.limits.maximumPaths,
            configuration.maximumSegments <= request.limits.maximumSegments
        else { throw AirflowPreviewError.invalidInput("Resource budget exceeded") }
        var boxes: [PreviewObstacle] = []
        for obstacle in snapshot.geometry.obstacles {
            try Task.checkCancellation()
            guard obstacle.roomID == room.id,
                let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry),
                let b = box.geometryBounds(),
                [b.size.x, b.size.y, b.size.z].allSatisfy({ $0.isFinite && $0 > 0 }),
                PreviewVector(b.origin).finite,
                bounds.contains(b.origin, tolerance: 0),
                bounds.contains((PreviewVector(b.origin) + PreviewVector(b.size)).position, tolerance: 0)
            else { throw AirflowPreviewError.invalidInput("Unsupported or invalid obstacle \(obstacle.id)") }
            guard !b.contains(supply.position, tolerance: 0) else {
                throw AirflowPreviewError.invalidInput("Source on or in obstacle")
            }
            boxes.append(.init(id: obstacle.id, bounds: b))
        }
        guard Set(boxes.map(\.id)).count == boxes.count else {
            throw AirflowPreviewError.invalidInput("Duplicate obstacle identity")
        }
        roomID = room.id
        sourcePortID = supply.id
        self.room = bounds
        self.field = field
        isWallSource = wall
        collisionIndex = .init(obstacles: boxes)
        obstacles = boxes.sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        seats = snapshot.inputs.usage.seats
        let warnings = [
            "规则几何预览；展示扩散假设未校准。路径不表示现实风速、温度或舒适。",
            "预览域封闭；任何开启门窗的跨开口气流、绕流、浮力与贴壁效应均未模拟。",
            "任何回风口仅显示输入位置；本规则不生成回风循环，也不将其作为路径吸引点。",
        ]
        notes = warnings
    }
    public func isFluid(_ point: Position3D) -> Bool {
        room.contains(point, tolerance: 0) && !obstacles.contains { $0.bounds.contains(point, tolerance: 0) }
    }
}
