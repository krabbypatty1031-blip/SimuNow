import Foundation
import SimuCore

/// What the user selected in the editor. Identity stays a stable UUID; selection is never persisted into the project file.
public enum EntitySelection: Hashable, Sendable {
    case room(UUID)
    case opening(UUID)
    case obstacle(UUID)
    case device(UUID)
    case port(deviceID: UUID, portID: UUID)
    case seat(UUID)
    case occupant(UUID)
    case equipment(UUID)
    case control(UUID)
    case environment
    case cost
}

public struct RecentProject: Codable, Equatable, Sendable {
    public var name: String
    public var path: String
    public var openedAt: Date
    public init(name: String, path: String, openedAt: Date = Date()) {
        self.name = name; self.path = path; self.openedAt = openedAt
    }
}

/// Editing/session state for one open project. Pure state + imperative operations; views stay thin.
@MainActor
@Observable
public final class ProjectSession {
    public private(set) var project: ProjectDocument
    public private(set) var packageURL: URL?
    public private(set) var isDirty = false
    public var selection: EntitySelection? {
        didSet {
            if let selection, !exists(selection) { self.selection = nil }
            else if oldValue != selection { focusedSetting = nil }
        }
    }
    /// Validation path to reveal after a “go fill this in” jump. Cleared when the selection changes.
    public var focusedSetting: String?
    public var currentScenarioID: UUID {
        didSet { if !project.scenarios.contains(where: { $0.id == currentScenarioID }) {
            currentScenarioID = project.scenarios.first?.id ?? currentScenarioID
        } }
    }
    public private(set) var validation: ValidationReport
    public let registry: ModelRegistry
    public let validator: ProjectValidator
    /// Notified after every committed edit (dirty + revalidation). RunStore uses it to
    /// refresh input hashes so edited scenarios mark old results stale immediately.
    public var onMutate: ((ProjectDocument) -> Void)?
    private let packageCodec: ProjectPackageCodec

    public init(project: ProjectDocument, packageURL: URL? = nil,
                registry: ModelRegistry = .builtIn, validator: ProjectValidator = ProjectValidator()) {
        self.project = project
        self.packageURL = packageURL
        self.registry = registry
        self.validator = validator
        self.packageCodec = ProjectPackageCodec(registry: registry)
        self.currentScenarioID = project.scenarios.first?.id ?? UUID()
        self.validation = (try? validator.validate(project, registry: registry)) ?? ValidationReport(issues: [])
    }

    public var currentScenario: Scenario? {
        project.scenarios.first { $0.id == currentScenarioID }
    }

    /// Every edit goes through here: value replacement, dirty marking, revalidation.
    public func mutate(_ edit: (inout ProjectDocument) -> Void) {
        edit(&project)
        isDirty = true
        revalidate()
        onMutate?(project)
    }

    public func revalidate() {
        validation = (try? validator.validate(project, registry: registry)) ?? ValidationReport(issues: [])
    }

    public func exists(_ selection: EntitySelection) -> Bool {
        switch selection {
        case .room(let id): return project.geometry.rooms.contains { $0.id == id }
        case .opening(let id): return project.geometry.rooms.contains { $0.openings.contains { $0.id == id } }
        case .obstacle(let id): return project.geometry.obstacles.contains { $0.id == id }
        case .device(let id): return currentScenario?.inputs.hvac.contains { $0.id == id } ?? false
        case .port(let deviceID, let portID):
            return currentScenario?.inputs.hvac.first { $0.id == deviceID }?.ports.contains { $0.id == portID } ?? false
        case .seat(let id): return currentScenario?.inputs.usage.seats.contains { $0.id == id } ?? false
        case .occupant(let id): return currentScenario?.inputs.usage.occupants.contains { $0.id == id } ?? false
        case .equipment(let id): return currentScenario?.inputs.usage.equipment.contains { $0.id == id } ?? false
        case .control(let id): return currentScenario?.inputs.controls.contains { $0.id == id } ?? false
        case .environment, .cost: return currentScenario != nil
        }
    }

    // MARK: - Persistence

    public func save(to url: URL? = nil) throws {
        let target = url ?? packageURL
        guard let target else { throw ProjectPackageError.notAPackage("no destination") }
        try packageCodec.write(project, to: target)
        try HongKongOctoberClimate.installCitationIfReferenced(into: target, project: project)
        packageURL = target
        isDirty = false
        Self.recordRecent(name: project.name, path: target.path)
    }

    public static func load(from url: URL, registry: ModelRegistry = .builtIn) throws -> ProjectSession {
        let project = try ProjectPackageCodec(registry: registry).load(from: url)
        recordRecent(name: project.name, path: url.path)
        return ProjectSession(project: project, packageURL: url, registry: registry)
    }

    // MARK: - Scenarios

    /// Duplicate a scenario as a candidate: new scenario ID, same entity IDs (same objects, different settings).
    public func duplicateScenario(_ id: UUID, name: String) {
        guard let source = project.scenarios.first(where: { $0.id == id }) else { return }
        mutate { document in
            var copy = source
            copy.id = UUID()
            copy.name = name
            document.scenarios.append(copy)
        }
        currentScenarioID = project.scenarios.last?.id ?? currentScenarioID
    }

    public func snapshot(for scenarioID: UUID) throws -> ScenarioInputSnapshot {
        try ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID)
    }

    // MARK: - Recents (paths only; sandboxed reopen may require the user to re-select the file)

    private static let recentsKey = "simunow.recentProjects"
    public static var recents: [RecentProject] {
        (UserDefaults.standard.array(forKey: recentsKey) as? [Data])?.compactMap {
            try? JSONDecoder().decode(RecentProject.self, from: $0)
        } ?? []
    }
    public static func recordRecent(name: String, path: String) {
        var items = recents.filter { $0.path != path }
        items.insert(RecentProject(name: name, path: path), at: 0)
        items = Array(items.prefix(10))
        UserDefaults.standard.set(items.map { try? JSONEncoder().encode($0) }, forKey: recentsKey)
    }
}

public extension ProjectSession {
    /// Map a validator entity ID back to an editable selection (geometry first, then current scenario).
    func selection(forEntityID id: UUID) -> EntitySelection? {
        if project.geometry.rooms.contains(where: { $0.id == id }) { return .room(id) }
        if project.geometry.rooms.contains(where: { $0.openings.contains { $0.id == id } }) { return .opening(id) }
        if project.geometry.obstacles.contains(where: { $0.id == id }) { return .obstacle(id) }
        guard let scenario = currentScenario else { return nil }
        if scenario.inputs.hvac.contains(where: { $0.id == id }) { return .device(id) }
        for device in scenario.inputs.hvac where device.ports.contains(where: { $0.id == id }) {
            return .port(deviceID: device.id, portID: id)
        }
        if scenario.inputs.usage.seats.contains(where: { $0.id == id }) { return .seat(id) }
        if scenario.inputs.usage.occupants.contains(where: { $0.id == id }) { return .occupant(id) }
        if scenario.inputs.usage.equipment.contains(where: { $0.id == id }) { return .equipment(id) }
        if scenario.inputs.controls.contains(where: { $0.id == id }) { return .control(id) }
        return nil
    }
}

public extension ProjectSession {
    private static var placeholderNote: String { "Initial placeholder; replace with actual device data" }

    @discardableResult
    func addSeat(withOccupant: Bool = true) -> EntitySelection? {
        guard let room = project.geometry.rooms.first,
              let payload = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
              let w = payload.dimensions.width.value, let d = payload.dimensions.depth.value else { return nil }
        let seatID = UUID()
        let center = Position3D(x: w / 2, y: d / 2, z: 0)
        let samples = [0.1, 0.6, 1.1].map { SamplePoint(id: UUID(), position: Position3D(x: center.x, y: center.y, z: $0)) }
        mutate { document in
            guard let i = document.scenarios.firstIndex(where: { $0.id == currentScenarioID }) else { return }
            document.scenarios[i].inputs.usage.seats.append(
                Seat(id: seatID, roomID: room.id, name: "座位 \(document.scenarios[i].inputs.usage.seats.count + 1)",
                     position: center, samples: samples))
            if withOccupant {
                let note = ProjectSession.placeholderNote
                document.scenarios[i].inputs.usage.occupants.append(Occupant(
                    id: UUID(), seatID: seatID,
                    activity: .known(value: 1.2, source: .init(kind: .assumed, note: note)),
                    clothing: .known(value: 0.5, source: .init(kind: .assumed, note: note)),
                    heat: HeatGain(sensible: .known(value: 75, source: .init(kind: .assumed, note: note)),
                                   convectiveFraction: .known(value: 0.6, source: .init(kind: .assumed, note: note)),
                                   latent: .known(value: 55, source: .init(kind: .assumed, note: note))),
                    schedule: DailySchedule(intervals: [ScheduleInterval(startMinute: 0, endMinute: 1440,
                        fraction: .known(value: 1, source: .init(kind: .assumed, note: note)))])))
            }
        }
        return .seat(seatID)
    }

    @discardableResult
    func addObstacle() -> EntitySelection? {
        guard let room = project.geometry.rooms.first,
              let payload = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
              let w = payload.dimensions.width.value, let d = payload.dimensions.depth.value else { return nil }
        let id = UUID()
        let note = ProjectSession.placeholderNote
        let box = BoxObstacle(origin: Position3D(x: w / 2 - 0.6, y: d / 2 - 0.3, z: 0),
                              dimensions: Dimensions3D(
                                width: .known(value: 1.2, source: .init(kind: .assumed, note: note)),
                                depth: .known(value: 0.6, source: .init(kind: .assumed, note: note)),
                                height: .known(value: 0.75, source: .init(kind: .assumed, note: note))))
        guard let record = try? ExtensionRecord(box) else { return nil }
        mutate { document in
            document.geometry.obstacles.append(Obstacle(id: id, roomID: room.id,
                name: "家具 \(document.geometry.obstacles.count + 1)", shape: record))
        }
        return .obstacle(id)
    }

    /// Adds a single-split device with supply/return ports and a control. Performance values are
    /// explicit assumptions; supply temperature is unknown until the user fills it.
    @discardableResult
    func addDefaultDevice() -> EntitySelection? {
        guard let room = project.geometry.rooms.first,
              let payload = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
              let w = payload.dimensions.width.value, let d = payload.dimensions.depth.value,
              let h = payload.dimensions.height.value else { return nil }
        let note = ProjectSession.placeholderNote
        let deviceID = UUID()
        let position = Position3D(x: w / 2, y: d - 0.15, z: h * 0.85)
        func port(_ role: PortRole, _ direction: Direction3D, _ z: Double) -> AirPort {
            AirPort(id: UUID(), role: role, position: Position3D(x: position.x, y: position.y, z: z),
                    direction: direction,
                    area: .known(value: 0.05, source: .init(kind: .assumed, note: note)),
                    volumeFlow: .known(value: 0.15, source: .init(kind: .assumed, note: note)),
                    speed: .known(value: 3.0, source: .init(kind: .assumed, note: note)),
                    density: .known(value: 1.2, source: .init(kind: .assumed, note: note)))
        }
        let definition = SingleSplit(
            coolingCapacity: .known(value: 3500, source: .init(kind: .assumed, note: note)),
            electricalPower: .known(value: 1100, source: .init(kind: .assumed, note: note)),
            cop: .known(value: 3.2, source: .init(kind: .assumed, note: note)))
        guard let record = try? ExtensionRecord(definition) else { return nil }
        mutate { document in
            guard let i = document.scenarios.firstIndex(where: { $0.id == currentScenarioID }) else { return }
            document.scenarios[i].inputs.hvac.append(HVACDevice(
                id: deviceID, roomID: room.id, name: "空调", position: position, definition: record,
                ports: [port(.supply, Direction3D(x: 0, y: -1, z: 0), position.z),
                        port(.return, Direction3D(x: 0, y: 1, z: 0), position.z + 0.25)],
                supplyTemperature: .unknown(reason: "待按设备数据填写")))
            document.scenarios[i].inputs.controls.append(Control(
                id: UUID(), deviceID: deviceID,
                setpoint: .unknown(reason: "待填写设定温度"),
                sensorPosition: Position3D(x: w / 2, y: d / 2, z: 1.1),
                schedule: DailySchedule(intervals: [ScheduleInterval(startMinute: 0, endMinute: 1440,
                    fraction: .known(value: 1, source: .init(kind: .assumed, note: note)))])))
        }
        return .device(deviceID)
    }
}
