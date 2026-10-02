import Foundation

/// Code-built starter templates. Every physical value is marked preset/assumed with a reference or note;
/// environment and weather stay explicitly unknown so no climate is invented.
public enum ProjectTemplates {
    public static let presetReference = "Template preset; replace with project-specific source before engineering use."
    public static let occupancyReference = "ASHRAE Fundamentals representative seated-adult values (preset; verify on site)."

    public static func office() -> ProjectDocument {
        var b = Builder(spaceType: .office, name: "办公室模板", width: 5, depth: 4, height: 2.8)
        b.exteriorWall = .yMax
        b.addWindow(surface: .yMax, offsetU: 1.5, offsetV: 1.0, width: 2.0, height: 1.2)
        b.addDoor(surface: .xMin, offsetU: 0.4, offsetV: 0.0, width: 0.9, height: 2.1)
        b.setpoint(26)
        b.addDevice(x: 2.5, y: 3.85, z: 2.4, coolingW: 3500, electricW: 1100, cop: 3.2, flow: 0.15)
        b.ventilation(perPersonFlow: 0.010, people: 4)
        b.occupancySchedule(startMinute: 540, endMinute: 1080) // 09:00–18:00
        let seats: [(Double, Double)] = [(1.4, 1.2), (3.6, 1.2), (1.4, 2.8), (3.6, 2.8)]
        for (index, seat) in seats.enumerated() {
            b.addDesk(x: seat.0 - 0.6, y: seat.1 + 0.45)
            b.addSeat(name: "工位 \(index + 1)", x: seat.0, y: seat.1, occupant: true, met: 1.2, clo: 0.5)
            b.addComputer(x: seat.0 + 0.3, y: seat.1 + 0.75, watts: 150)
        }
        return b.finish()
    }

    public static func classroom() -> ProjectDocument {
        var b = Builder(spaceType: .classroom, name: "教室模板", width: 8, depth: 6, height: 3.2)
        b.exteriorWall = .yMax
        b.addWindow(surface: .yMax, offsetU: 1.2, offsetV: 1.1, width: 2.2, height: 1.4)
        b.addWindow(surface: .yMax, offsetU: 4.6, offsetV: 1.1, width: 2.2, height: 1.4)
        b.addDoor(surface: .xMin, offsetU: 0.3, offsetV: 0.0, width: 1.0, height: 2.2)
        b.setpoint(26)
        b.addDevice(x: 4.0, y: 5.82, z: 2.6, coolingW: 7200, electricW: 2200, cop: 3.3, flow: 0.3)
        b.ventilation(perPersonFlow: 0.010, people: 12)
        b.occupancySchedule(startMinute: 480, endMinute: 1020) // 08:00–17:00
        for row in 0..<3 {
            for column in 0..<4 {
                b.addSeat(name: "座位 \(row * 4 + column + 1)",
                          x: 1.6 + Double(column) * 1.6, y: 1.5 + Double(row) * 1.5,
                          occupant: true, met: 1.2, clo: 0.5)
            }
        }
        return b.finish()
    }
}

private struct Builder {
    let spaceType: SpaceType
    let name: String
    let width: Double, depth: Double, height: Double
    var counter = 0
    var exteriorWall: SurfaceFace = .yMax
    var openings: [Opening] = []
    var windows: [WindowCondition] = []
    var obstacles: [Obstacle] = []
    var devices: [HVACDevice] = []
    var controls: [Control] = []
    var seats: [Seat] = []
    var occupants: [Occupant] = []
    var equipment: [EquipmentGain] = []
    var ventilationFlow: VolumeFlow = .unknown(reason: "Not supplied")
    var occupancySchedule: DailySchedule = DailySchedule(intervals: [
        ScheduleInterval(startMinute: 0, endMinute: 1440, fraction: .known(value: 0, source: .init(kind: .assumed, note: "Unoccupied placeholder")))
    ])
    var controlSetpoint: Temperature = .unknown(reason: "Not supplied")

    mutating func id() -> UUID {
        counter += 1
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", counter))!
    }

    func m(_ v: Double, preset: Bool = true, note: String? = nil) -> Length {
        .known(value: v, source: preset ? .init(kind: .preset, reference: ProjectTemplates.presetReference) : .init(kind: .assumed, note: note ?? "Template assumption"))
    }
    func w(_ v: Double, reference: String = ProjectTemplates.presetReference) -> ThermalPower { .known(value: v, source: .init(kind: .preset, reference: reference)) }
    func we(_ v: Double) -> ElectricalPower { .known(value: v, source: .init(kind: .preset, reference: ProjectTemplates.presetReference)) }
    func ratio(_ v: Double, reference: String = ProjectTemplates.presetReference) -> Ratio { .known(value: v, source: .init(kind: .preset, reference: reference)) }
    func assumedRatio(_ v: Double, _ note: String) -> Ratio { .known(value: v, source: .init(kind: .assumed, note: note)) }
    func uv(_ v: Double) -> UValue { .known(value: v, source: .init(kind: .preset, reference: ProjectTemplates.presetReference)) }
    func area(_ v: Double) -> Area { .known(value: v, source: .init(kind: .preset, reference: ProjectTemplates.presetReference)) }
    func flow(_ v: Double) -> VolumeFlow { .known(value: v, source: .init(kind: .preset, reference: ProjectTemplates.presetReference)) }
    func assumedFlow(_ v: Double, _ note: String) -> VolumeFlow { .known(value: v, source: .init(kind: .assumed, note: note)) }
    func density() -> Density { .known(value: 1.2, source: .init(kind: .preset, reference: "Indoor air density near 20–26 °C (preset; verify)")) }

    mutating func addWindow(surface: SurfaceFace, offsetU: Double, offsetV: Double, width: Double, height: Double) {
        let openingID = id()
        openings.append(Opening(id: openingID, surfaceID: surfaceID(for: surface), kind: .window,
                                offsetU: m(offsetU), offsetV: m(offsetV), width: m(width), height: m(height)))
        windows.append(WindowCondition(openingID: openingID, uValue: uv(3.0), shgc: ratio(0.6),
                                       shadingFactor: assumedRatio(1.0, "No shading device in template")))
    }

    mutating func addDoor(surface: SurfaceFace, offsetU: Double, offsetV: Double, width: Double, height: Double) {
        openings.append(Opening(id: id(), surfaceID: surfaceID(for: surface), kind: .door,
                                offsetU: m(offsetU), offsetV: m(offsetV), width: m(width), height: m(height)))
    }

    mutating func addDesk(x: Double, y: Double) {
        let payload = BoxObstacle(origin: Position3D(x: x, y: y, z: 0),
                                  dimensions: Dimensions3D(width: m(1.2), depth: m(0.6), height: m(0.75)))
        obstacles.append(Obstacle(id: id(), roomID: roomID, name: "桌 \(obstacles.count + 1)",
                                  shape: try! ExtensionRecord(payload)))
    }

    mutating func addDevice(x: Double, y: Double, z: Double, coolingW: Double, electricW: Double, cop: Double, flow supplyFlow: Double) {
        let deviceID = id()
        let portArea = 0.05
        let speed = supplyFlow / portArea
        let supply = AirPort(id: id(), role: .supply, position: Position3D(x: x, y: y, z: z),
                             direction: Direction3D(x: 0, y: -1, z: 0), area: area(portArea),
                             volumeFlow: flow(supplyFlow), speed: .known(value: speed, source: .init(kind: .assumed, note: "Derived as flow/area in template")),
                             density: density())
        let ret = AirPort(id: id(), role: .return, position: Position3D(x: x, y: y, z: z + 0.25),
                          direction: Direction3D(x: 0, y: 1, z: 0), area: area(portArea),
                          volumeFlow: flow(supplyFlow), speed: .known(value: speed, source: .init(kind: .assumed, note: "Derived as flow/area in template")),
                          density: density())
        let definition = SingleSplit(coolingCapacity: w(coolingW), electricalPower: we(electricW), cop: ratio(cop))
        devices.append(HVACDevice(id: deviceID, roomID: roomID, name: "分体空调",
                                  position: Position3D(x: x, y: y, z: z),
                                  definition: try! ExtensionRecord(definition),
                                  ports: [supply, ret],
                                  supplyTemperature: .known(value: 13, source: .init(kind: .assumed, note: "Typical cooling supply temperature; confirm with device data"))))
        controls.append(Control(id: id(), deviceID: deviceID,
                                setpoint: controlSetpoint,
                                sensorPosition: Position3D(x: width / 2, y: depth / 2, z: 1.1),
                                schedule: DailySchedule(intervals: [ScheduleInterval(startMinute: 0, endMinute: 1440, fraction: assumedRatio(1.0, "Controller active all day in template"))])))
    }

    mutating func setpoint(_ v: Double) {
        controlSetpoint = .known(value: v, source: .init(kind: .preset, reference: "Typical summer cooling setpoint (preset; project may choose)"))
    }

    mutating func ventilation(perPersonFlow: Double, people: Int) {
        let total = perPersonFlow * Double(people)
        ventilationFlow = flow(total)
        ventilationPeople = people
    }
    var ventilationPeople = 0

    mutating func occupancySchedule(startMinute: Int, endMinute: Int) {
        occupancySchedule = DailySchedule(intervals: [
            ScheduleInterval(startMinute: 0, endMinute: startMinute, fraction: assumedRatio(0, "Unoccupied")),
            ScheduleInterval(startMinute: startMinute, endMinute: endMinute, fraction: ratio(1.0)),
            ScheduleInterval(startMinute: endMinute, endMinute: 1440, fraction: assumedRatio(0, "Unoccupied"))
        ])
    }

    mutating func addSeat(name: String, x: Double, y: Double, occupant: Bool, met: Double, clo: Double) {
        let seatID = id()
        let samples = [0.1, 0.6, 1.1].map { SamplePoint(id: id(), position: Position3D(x: x, y: y, z: $0)) }
        seats.append(Seat(id: seatID, roomID: roomID, name: name, position: Position3D(x: x, y: y, z: 0), samples: samples))
        if occupant {
            occupants.append(Occupant(id: id(), seatID: seatID,
                                      activity: .known(value: met, source: .init(kind: .preset, reference: ProjectTemplates.occupancyReference)),
                                      clothing: .known(value: clo, source: .init(kind: .preset, reference: ProjectTemplates.occupancyReference)),
                                      heat: HeatGain(sensible: w(75, reference: ProjectTemplates.occupancyReference),
                                                     convectiveFraction: ratio(0.6, reference: ProjectTemplates.occupancyReference),
                                                     latent: w(55, reference: ProjectTemplates.occupancyReference)),
                                      schedule: occupancySchedule))
        }
    }

    mutating func addComputer(x: Double, y: Double, watts: Double) {
        equipment.append(EquipmentGain(id: id(), roomID: roomID, position: Position3D(x: x, y: y, z: 0.76),
                                       heat: HeatGain(sensible: w(watts), convectiveFraction: ratio(0.7),
                                                      latent: .known(value: 0, source: .init(kind: .assumed, note: "Office electronics have no latent gain"))),
                                       schedule: occupancySchedule))
    }

    var roomID: UUID = UUID(uuidString: "00000000-0000-4000-8000-0000000000F1")!
    var surfaceIDs: [SurfaceFace: UUID] = [:]

    mutating func surfaceID(for face: SurfaceFace) -> UUID {
        if let existing = surfaceIDs[face] { return existing }
        let new = id()
        surfaceIDs[face] = new
        return new
    }

    mutating func finish() -> ProjectDocument {
        let faces: [SurfaceFace] = [.xMin, .xMax, .yMin, .yMax, .floor, .ceiling]
        let surfaces = faces.map { Surface(id: surfaceID(for: $0), face: $0) }
        let shape = RectangularRoom(dimensions: Dimensions3D(width: m(width), depth: m(depth), height: m(height)))
        let room = Room(id: roomID, name: name, shape: try! ExtensionRecord(shape),
                        northAngle: .unknown(reason: "Confirm orientation on site"),
                        surfaces: surfaces, openings: openings)
        let envelope = Envelope(surfaces: surfaces.map { surface in
            if surface.face == exteriorWall {
                return SurfaceCondition(surfaceID: surface.id, exposure: .outdoors, uValue: uv(1.8),
                                        boundary: ThermalBoundary(mode: .temperature, temperature: .unknown(reason: "Boundary condition pending L1 or weather adapter")))
            }
            return SurfaceCondition(surfaceID: surface.id, exposure: .adiabatic, uValue: uv(1.5),
                                    boundary: ThermalBoundary(mode: .heatFlux, heatFlux: .known(value: 0, source: .init(kind: .assumed, note: "Adiabatic interior partition (template assumption)"))))
        }, windows: windows)
        let ventilation = RoomVentilation(roomID: roomID,
                                          outdoorAir: ventilationFlow, exhaustAir: ventilationFlow,
                                          infiltration: assumedFlow(0, "No infiltration in template"),
                                          exfiltration: assumedFlow(0, "No exfiltration in template"),
                                          density: density(),
                                          openings: openings.map { OpeningState(openingID: $0.id, openFraction: assumedRatio(0, "Openings closed in template")) })
        let environment = Environment(outdoorTemperature: .unknown(reason: "Weather adapter not connected"),
                                      outdoorHumidity: .unknown(reason: "Weather adapter not connected"),
                                      indoorHumidity: .unknown(reason: "No measurement or model source yet"))
        let inputs = ScenarioInputs(usage: Usage(seats: seats, occupants: occupants, equipment: equipment),
                                    hvac: devices, controls: controls, envelope: envelope,
                                    ventilation: [ventilation], environment: environment)
        let scenario = Scenario(id: id(), name: "基准方案", inputs: inputs, evaluation: EvaluationInputs(cost: CostInputs()))
        return ProjectDocument(id: id(), name: name, spaceType: spaceType,
                               geometry: ProjectGeometry(rooms: [room], obstacles: obstacles), scenarios: [scenario])
    }
}
