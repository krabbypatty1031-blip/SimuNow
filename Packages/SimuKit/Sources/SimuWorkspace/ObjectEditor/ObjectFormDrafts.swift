import Foundation
import SimuCore
import SimuVisualization

struct FurnitureEditDraft: Equatable {
    let id: UUID
    var roomID: UUID
    var name: String
    var origin: ObjectPositionDraft
    var width: PhysicalParameterDraft
    var depth: PhysicalParameterDraft
    var height: PhysicalParameterDraft
    let originalShape: ExtensionRecord
    let originalBox: BoxObstacle
    init(_ obstacle: Obstacle, box: BoxObstacle) {
        id = obstacle.id; roomID = obstacle.roomID; name = obstacle.name; origin = .init(box.origin)
        originalShape = obstacle.shape; originalBox = box
        width = .init(box.dimensions.width); depth = .init(box.dimensions.depth); height = .init(box.dimensions.height)
    }
    func value() throws -> Obstacle {
        let dimensions = try Dimensions3D(width: width.parameter(as: LengthTag.self, range: .positive), depth: depth.parameter(as: LengthTag.self, range: .positive), height: height.parameter(as: LengthTag.self, range: .positive))
        let box = try BoxObstacle(origin: origin.position(), dimensions: dimensions)
        let shape = box == originalBox ? originalShape : try ExtensionRecord(box)
        return .init(id: id, roomID: roomID, name: name, shape: shape)
    }
}
struct SampleEditDraft: Identifiable, Equatable {
    let id: UUID
    var offset: ObjectPositionDraft
    let originalOffset: ObjectPositionDraft
    let originalPosition: Position3D
    let originalOrigin: Position3D
    init(_ sample: SamplePoint, relativeTo origin: Position3D) {
        id = sample.id; offset = .init(.init(x: sample.position.x - origin.x, y: sample.position.y - origin.y, z: sample.position.z - origin.z))
        originalOffset = offset; originalPosition = sample.position; originalOrigin = origin
    }
    func value(relativeTo origin: Position3D) throws -> SamplePoint {
        if offset == originalOffset { return .init(id: id, position: ObjectEditing.translated(originalPosition, from: originalOrigin, to: origin)) }
        let p = try offset.position(label: "采样点偏移")
        return .init(id: id, position: .init(x: origin.x + p.x, y: origin.y + p.y, z: origin.z + p.z))
    }
}
struct OccupantEditDraft: Equatable {
    let id: UUID
    var enabled: Bool
    var activity: PhysicalParameterDraft
    var clothing: PhysicalParameterDraft
    var heat: ObjectHeatDraft
    var schedule: ObjectScheduleDraft
    init(_ occupant: Occupant?) {
        id = occupant?.id ?? UUID(); enabled = occupant != nil
        activity = .init(occupant?.activity ?? .unknown(reason: "待确认人员活动"))
        clothing = .init(occupant?.clothing ?? .unknown(reason: "待确认衣着"))
        heat = .init(occupant?.heat ?? ObjectEditing.unknownHeat()); schedule = .init(occupant?.schedule ?? .init())
    }
    func value(seatID: UUID) throws -> Occupant? {
        guard enabled else { return nil }
        return try .init(id: id, seatID: seatID, activity: activity.parameter(as: ActivityTag.self, range: .positive), clothing: clothing.parameter(as: ClothingTag.self, range: .nonnegative), heat: heat.heat(), schedule: schedule.schedule())
    }
}
struct SeatEditDraft: Equatable {
    let id: UUID
    var roomID: UUID
    var name: String
    var position: ObjectPositionDraft
    var samples: [SampleEditDraft]
    var occupant: OccupantEditDraft
    init(_ seat: Seat, occupant: Occupant?) {
        id = seat.id; roomID = seat.roomID; name = seat.name; position = .init(seat.position)
        samples = seat.samples.map { .init($0, relativeTo: seat.position) }; self.occupant = .init(occupant)
    }
    func value() throws -> Seat {
        let p = try position.position()
        return try .init(id: id, roomID: roomID, name: name, position: p, samples: samples.map { try $0.value(relativeTo: p) })
    }
}
struct EquipmentEditDraft: Equatable {
    let id: UUID
    var roomID: UUID
    var position: ObjectPositionDraft
    var heat: ObjectHeatDraft
    var schedule: ObjectScheduleDraft
    init(_ item: EquipmentGain) { id = item.id; roomID = item.roomID; position = .init(item.position); heat = .init(item.heat); schedule = .init(item.schedule) }
    func value() throws -> EquipmentGain {
        try .init(id: id, roomID: roomID, position: position.position(), heat: heat.heat(), schedule: schedule.schedule())
    }
}
struct PortEditDraft: Identifiable, Equatable {
    let id: UUID
    var role: PortRole
    var offset: ObjectPositionDraft
    var yaw: String
    var pitch: String
    var area: PhysicalParameterDraft
    var flow: PhysicalParameterDraft
    var speed: PhysicalParameterDraft
    var density: PhysicalParameterDraft
    /// Retain an unchanged imported direction exactly, rather than round-trip it through trigonometry.
    let originalDirection: Direction3D
    let originalYaw: String
    let originalPitch: String
    let originalPosition: Position3D
    let originalOrigin: Position3D
    let originalOffset: ObjectPositionDraft
    var rebuildDirection = false
    init(_ port: AirPort, relativeTo origin: Position3D) {
        id = port.id; role = port.role
        offset = .init(.init(x: port.position.x - origin.x, y: port.position.y - origin.y, z: port.position.z - origin.z))
        originalPosition = port.position; originalOrigin = origin; originalOffset = offset
        let angles = AirflowDirection.angles(port.direction)
        yaw = String(angles.yaw); pitch = String(angles.pitch)
        originalYaw = yaw; originalPitch = pitch; originalDirection = port.direction
        area = .init(port.area); flow = .init(port.volumeFlow); speed = .init(port.speed); density = .init(port.density)
    }
    func value(relativeTo origin: Position3D) throws -> AirPort {
        let p = try offset.position(label: "风口偏移")
        let direction = !rebuildDirection && yaw == originalYaw && pitch == originalPitch ? originalDirection : try AirflowDirection.unit(yawDegrees: objectNumber(yaw, label: "水平角"), pitchDegrees: objectNumber(pitch, label: "俯仰角"))
        let position = offset == originalOffset ? ObjectEditing.translated(originalPosition, from: originalOrigin, to: origin) : .init(x: origin.x + p.x, y: origin.y + p.y, z: origin.z + p.z)
        return try .init(id: id, role: role, position: position, direction: direction,
                        area: area.parameter(as: AreaTag.self, range: .positive), volumeFlow: flow.parameter(as: VolumeFlowTag.self, range: .nonnegative), speed: speed.parameter(as: SpeedTag.self, range: .nonnegative), density: density.parameter(as: DensityTag.self, range: .positive))
    }
    mutating func deriveSpeed() throws {
        let a: Area = try area.parameter(as: AreaTag.self, range: .positive)
        let f: VolumeFlow = try flow.parameter(as: VolumeFlowTag.self, range: .nonnegative)
        guard let av = a.value, let fv = f.value else { throw ProjectDataError.contract("推导风速前，请提供面积和风量。") }
        speed = .init(Speed.known(value: fv / av, source: .init(kind: .assumed, note: "由本风口体积流量 ÷ 有效面积推导；需核实输入依据。")))
    }
}
struct ControlEditDraft: Equatable {
    let id: UUID
    var enabled: Bool
    var setpoint: PhysicalParameterDraft
    var sensor: ObjectPositionDraft
    var schedule: ObjectScheduleDraft
    init(_ control: Control?, initialSensor: Position3D) {
        id = control?.id ?? UUID(); enabled = control != nil
        setpoint = .init(control?.setpoint ?? .unknown(reason: "待提供温控设定"))
        sensor = .init(control?.sensorPosition ?? initialSensor); schedule = .init(control?.schedule ?? .init())
    }
    func value(deviceID: UUID) throws -> Control? {
        guard enabled else { return nil }
        return try .init(id: id, deviceID: deviceID, setpoint: setpoint.parameter(as: TemperatureTag.self, range: .init(minimum: -273.15)), sensorPosition: sensor.position(label: "温控测点"), schedule: schedule.schedule())
    }
}
struct DeviceEditDraft: Equatable {
    let id: UUID
    var roomID: UUID
    var name: String
    var position: ObjectPositionDraft
    var capacity: PhysicalParameterDraft
    var electricalPower: PhysicalParameterDraft
    var cop: PhysicalParameterDraft
    var supplyTemperature: PhysicalParameterDraft
    var ports: [PortEditDraft]
    var control: ControlEditDraft
    let originalDefinition: ExtensionRecord
    let originalSplit: SingleSplit
    init(_ device: HVACDevice, split: SingleSplit, control: Control?, initialSensor: Position3D) {
        id = device.id; roomID = device.roomID; name = device.name; position = .init(device.position)
        originalDefinition = device.definition; originalSplit = split
        capacity = .init(split.coolingCapacity); electricalPower = .init(split.electricalPower); cop = .init(split.cop); supplyTemperature = .init(device.supplyTemperature)
        ports = device.ports.map { .init($0, relativeTo: device.position) }
        self.control = .init(control, initialSensor: initialSensor)
    }
    func value() throws -> HVACDevice {
        let p = try position.position()
        let split = try SingleSplit(coolingCapacity: capacity.parameter(as: ThermalPowerTag.self, range: .nonnegative), electricalPower: electricalPower.parameter(as: ElectricalPowerTag.self, range: .nonnegative), cop: cop.parameter(as: RatioTag.self, range: .positive))
        let definition = split == originalSplit ? originalDefinition : try ExtensionRecord(split)
        return try .init(id: id, roomID: roomID, name: name, position: p, definition: definition, ports: ports.map { try $0.value(relativeTo: p) }, supplyTemperature: supplyTemperature.parameter(as: TemperatureTag.self, range: .init(minimum: -273.15)))
    }
}
