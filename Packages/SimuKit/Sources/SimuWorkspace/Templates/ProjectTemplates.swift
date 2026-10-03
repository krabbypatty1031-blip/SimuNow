import Foundation
import SimuCore

/// These are editable examples of a layout, not measured rooms or physical benchmarks.
public enum ProjectTemplateKind: String, CaseIterable, Identifiable, Sendable {
    case office, classroom, home

    public var id: String { "simunow.template.\(rawValue)" }
    public var title: String {
        switch self { case .office: "小办公室"; case .classroom: "单间教室"; case .home: "家庭房间" }
    }
    public var version: Int { 1 }
    public var descriptor: ProjectTemplateDescriptor {
        .init(id: id, version: version, title: title,
              sourceReference: "\(id).v\(version)",
              assumptionNotes: [
                "房间、门窗、桌体、座位及风口位置是内部可编辑布局示例，未经现场测量。",
                "采样高度 1.1 m 和座位高度 0.6 m 是布局假设，可在编辑器中修改。",
                "全天时间表的活动时段是示例假设；人数由启用的人员记录和时间表决定。",
                "设备性能、热源、设定温度、送风状态、围护性能、通风和湿度均需补充。",
                "没有天气文件、电价或设备报价；创建模板不代表可以计算。",
                self == .classroom ? "人员 met/clo 保持未知；儿童舒适适用性需要另行确认。" : "人员 met/clo 保持未知，应按实际人群补充。"
              ])
    }
}

public struct ProjectTemplateDescriptor: Equatable, Sendable {
    public let id: String
    public let version: Int
    public let title: String
    public let sourceReference: String
    public let assumptionNotes: [String]
}

/// Geometry is expressed in metres, and times in local minutes from midnight.
public struct ProjectTemplateOptions: Equatable, Sendable {
    public var projectName: String
    public var width: Double
    public var depth: Double
    public var height: Double
    public var seatCount: Int
    public var rows: Int
    public var columns: Int
    public var columnSpacing: Double
    public var rowSpacing: Double
    public var deskWidth: Double
    public var deskDepth: Double
    public var deskHeight: Double
    public var activeStartMinute: Int
    public var activeEndMinute: Int
    public var includeFurniture: Bool
    public var includeOccupants: Bool
    public var includeEquipment: Bool
    public var includeHVAC: Bool
    public var includeDoor: Bool
    public var includeWindow: Bool
    public var includeLectern: Bool

    public init(projectName: String, width: Double, depth: Double, height: Double, seatCount: Int,
                rows: Int, columns: Int, columnSpacing: Double, rowSpacing: Double,
                deskWidth: Double, deskDepth: Double, deskHeight: Double,
                activeStartMinute: Int, activeEndMinute: Int, includeFurniture: Bool = true,
                includeOccupants: Bool = true, includeEquipment: Bool = false, includeHVAC: Bool = true,
                includeDoor: Bool = true, includeWindow: Bool = true, includeLectern: Bool = false) {
        self.projectName = projectName
        self.width = width; self.depth = depth; self.height = height
        self.seatCount = seatCount; self.rows = rows; self.columns = columns
        self.columnSpacing = columnSpacing; self.rowSpacing = rowSpacing
        self.deskWidth = deskWidth; self.deskDepth = deskDepth; self.deskHeight = deskHeight
        self.activeStartMinute = activeStartMinute; self.activeEndMinute = activeEndMinute
        self.includeFurniture = includeFurniture; self.includeOccupants = includeOccupants
        self.includeEquipment = includeEquipment; self.includeHVAC = includeHVAC
        self.includeDoor = includeDoor; self.includeWindow = includeWindow; self.includeLectern = includeLectern
    }

    public static func defaults(for kind: ProjectTemplateKind) -> Self {
        if kind == .home {
            return .init(projectName: "家庭房间项目", width: 5, depth: 4, height: 2.8,
                         seatCount: 2, rows: 1, columns: 2, columnSpacing: 1.8, rowSpacing: 1.5,
                         deskWidth: 1.2, deskDepth: 0.6, deskHeight: 0.6,
                         activeStartMinute: 1080, activeEndMinute: 1440,
                         includeFurniture: true, includeOccupants: false, includeEquipment: false)
        }
        if kind == .office {
            return .init(projectName: "办公室项目", width: 6, depth: 5, height: 3,
                         seatCount: 4, rows: 2, columns: 2, columnSpacing: 2.2, rowSpacing: 1.8,
                         deskWidth: 1.4, deskDepth: 0.65, deskHeight: 0.75,
                         activeStartMinute: 540, activeEndMinute: 1080,
                         includeFurniture: true, includeOccupants: true, includeEquipment: true,
                         includeHVAC: true, includeDoor: true, includeWindow: true)
        }
        return .init(projectName: "教室项目", width: 10, depth: 8, height: 3.2,
                     seatCount: 24, rows: 4, columns: 6, columnSpacing: 1.4, rowSpacing: 1.6,
                     deskWidth: 0.8, deskDepth: 0.5, deskHeight: 0.75,
                     activeStartMinute: 480, activeEndMinute: 1020,
                     includeFurniture: true, includeOccupants: true, includeEquipment: false,
                     includeHVAC: true, includeDoor: true, includeWindow: true, includeLectern: true)
    }
}

public struct ProjectTemplateInstantiation: Equatable, Sendable {
    public let project: ProjectDocument
    public let templateID: String
    public let templateVersion: Int
    public let baselineScenarioID: UUID
}

public enum ProjectTemplateError: LocalizedError, Equatable, Sendable {
    case invalidOption(String)
    case layoutDoesNotFit(String)
    case invalidProject([ValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .invalidOption(let message), .layoutDoesNotFit(let message): message
        case .invalidProject(let issues): "模板输入存在冲突：\(issues.first?.message ?? "请调整布局")"
        }
    }
}

public enum ProjectTemplateFactory {
    /// Each call creates independent IDs. Nested references are constructed from those IDs.
    public static func make(kind: ProjectTemplateKind, options: ProjectTemplateOptions) throws -> ProjectTemplateInstantiation {
        try validate(options)
        let defaults = ProjectTemplateOptions.defaults(for: kind)
        let reference = kind.descriptor.sourceReference
        func source(_ field: String, overridden: Bool = false) -> SourceRecord {
            .init(kind: overridden ? .user : .assumed, reference: reference,
                  note: overridden ? "用户覆盖 \(field)；原始布局示例：\(reference)。" : "\(reference) 内部可编辑布局假设：\(field)，并非实测。")
        }
        func length(_ value: Double, _ field: String, _ defaultValue: Double? = nil) -> Length {
            .known(value: value, source: source(field, overridden: defaultValue.map { value != $0 } ?? false))
        }
        let dimensions = Dimensions3D(width: length(options.width, "房间宽度", defaults.width),
                                      depth: length(options.depth, "房间进深", defaults.depth),
                                      height: length(options.height, "房间高度", defaults.height))
        let roomID = UUID()
        let surfaces = SurfaceFace.allCases.map { Surface(id: UUID(), face: $0) }
        var openings: [Opening] = []
        if options.includeDoor {
            guard options.depth >= 1.4, options.height >= 2.1 else {
                throw ProjectTemplateError.layoutDoesNotFit("示例门为 0.9 × 2.1 m，X 墙的进深需至少 1.4 m、高度至少 2.1 m；请调整房间或取消示例门。")
            }
            openings.append(.init(id: UUID(), surfaceID: surfaces.first { $0.face == .xMin }!.id,
                                  kind: .door, offsetU: length(0.25, "门 U 偏移"), offsetV: length(0, "门 V 偏移"),
                                  width: length(0.9, "示例门宽"), height: length(2.1, "示例门高")))
        }
        if options.includeWindow {
            guard options.width >= 1.9, options.height >= 2.3 else {
                throw ProjectTemplateError.layoutDoesNotFit("示例窗为 1.4 × 1.2 m，宽度需至少 1.9 m、高度至少 2.3 m；请调整房间或取消示例窗。")
            }
            openings.append(.init(id: UUID(), surfaceID: surfaces.first { $0.face == .yMax }!.id,
                                  kind: .window, offsetU: length((options.width - 1.4) / 2, "居中示例窗 U 偏移"),
                                  offsetV: length(1.1, "示例窗 V 偏移"), width: length(1.4, "示例窗宽"), height: length(1.2, "示例窗高")))
        }
        let room = Room(id: roomID, name: kind.title, shape: try ExtensionRecord(RectangularRoom(dimensions: dimensions)),
                        northAngle: .unknown(reason: "未测量房间朝向"), surfaces: surfaces, openings: openings)
        let margin = 0.7
        let deskOffset = 0.35
        let usedColumns = min(options.columns, options.seatCount)
        let usedRows = (options.seatCount - 1) / options.columns + 1
        let layoutWidth = Double(usedColumns - 1) * options.columnSpacing + options.deskWidth
        let layoutDepth = Double(usedRows - 1) * options.rowSpacing + deskOffset + options.deskDepth
        guard layoutWidth + 2 * margin <= options.width,
              layoutDepth + 2 * margin <= options.depth,
              options.height > max(1.1, options.deskHeight + 0.1) + GeometryRule.tolerance else {
            throw ProjectTemplateError.layoutDoesNotFit("布局需至少 \(layoutWidth + 2 * margin) × \(layoutDepth + 2 * margin) m，且高度须容纳 1.1 m 采样点和桌上热源。请增大房间、减少座位或调整间距；不会自动截断或缩放。")
        }
        if options.includeLectern {
            guard options.width >= 2.1, layoutDepth + margin + 1.1 <= options.depth else {
                throw ProjectTemplateError.layoutDoesNotFit("示例讲台为 1.5 × 0.6 × 0.8 m；座位区后需留出 1.1 m，房间宽至少 2.1 m。请增大房间或取消讲台。")
            }
        }
        guard options.columnSpacing >= options.deskWidth + 0.1,
              options.rowSpacing > options.deskDepth + deskOffset + 0.1 else {
            throw ProjectTemplateError.layoutDoesNotFit("列间距须比桌宽大至少 0.1 m；排间距须比桌深加 0.45 m 更大，以保持桌体和采样点分离。")
        }
        let schedule = DailySchedule(intervals: [
            .init(startMinute: 0, endMinute: options.activeStartMinute,
                  fraction: .known(value: 0, source: source("停用时段"))),
            .init(startMinute: options.activeStartMinute, endMinute: options.activeEndMinute,
                  fraction: .known(value: 1, source: source("使用时段", overridden: options.activeStartMinute != defaults.activeStartMinute || options.activeEndMinute != defaults.activeEndMinute))),
            .init(startMinute: options.activeEndMinute, endMinute: 1440,
                  fraction: .known(value: 0, source: source("停用时段")))
        ].filter { $0.startMinute < $0.endMinute })
        func unknownGain() -> HeatGain {
            .init(sensible: .unknown(reason: "未提供显热依据"), convectiveFraction: .unknown(reason: "未提供对流占比依据"),
                  latent: .unknown(reason: "未提供潜热依据"))
        }
        var seats: [Seat] = [], occupants: [Occupant] = [], equipment: [EquipmentGain] = [], obstacles: [Obstacle] = []
        for index in 0..<options.seatCount {
            let x = margin + options.deskWidth / 2 + Double(index % options.columns) * options.columnSpacing
            let y = margin + Double(index / options.columns) * options.rowSpacing
            let seatID = UUID()
            seats.append(.init(id: seatID, roomID: roomID, name: "\(kind == .office ? "工位" : kind == .home ? "关注位置" : "座位") \(index + 1)",
                               position: .init(x: x, y: y, z: 0.6), samples: [
                                .init(id: UUID(), position: .init(x: x, y: y, z: 1.1))
                               ]))
            if options.includeFurniture {
                obstacles.append(.init(id: UUID(), roomID: roomID, name: "\(kind == .home ? "家具盒体" : "桌体") \(index + 1)", shape: try ExtensionRecord(BoxObstacle(
                    origin: .init(x: x - options.deskWidth / 2, y: y + deskOffset, z: 0),
                    dimensions: .init(width: length(options.deskWidth, "桌宽", defaults.deskWidth),
                                      depth: length(options.deskDepth, "桌深", defaults.deskDepth),
                                      height: length(options.deskHeight, "桌高", defaults.deskHeight))))))
            }
            if options.includeOccupants {
                occupants.append(.init(id: UUID(), seatID: seatID, activity: .unknown(reason: "按实际人群与活动补充 met；模板不保证舒适模型适用性"),
                                       clothing: .unknown(reason: "按实际衣着补充 clo"), heat: unknownGain(), schedule: schedule))
            }
            if options.includeEquipment {
                equipment.append(.init(id: UUID(), roomID: roomID,
                                       position: .init(x: x, y: y + deskOffset + options.deskDepth / 2, z: options.deskHeight + 0.1),
                                       heat: unknownGain(), schedule: schedule))
            }
        }
        if options.includeLectern {
            obstacles.append(.init(id: UUID(), roomID: roomID, name: "讲台", shape: try ExtensionRecord(BoxObstacle(
                origin: .init(x: (options.width - 1.5) / 2, y: options.depth - 0.95, z: 0),
                dimensions: .init(width: length(1.5, "示例讲台宽"), depth: length(0.6, "示例讲台深"), height: length(0.8, "示例讲台高"))))))
        }
        var scenario = Scenario.unfinished(name: "基准方案")
        scenario.inputs.usage = .init(seats: seats, occupants: occupants, equipment: equipment)
        scenario.inputs.envelope.windows = openings.filter { $0.kind == .window }.map {
            .init(openingID: $0.id, uValue: .unknown(reason: "未提供窗传热依据"), shgc: .unknown(reason: "未提供太阳得热依据"),
                  shadingFactor: .unknown(reason: "未提供遮阳依据"))
        }
        // Surface exposure cannot be unknown in v2, so leave assignments incomplete rather than invent it.
        scenario.inputs.ventilation = [.init(roomID: roomID, outdoorAir: .unknown(reason: "未提供室外新风量"),
                                            exhaustAir: .unknown(reason: "未提供室外排风量"), infiltration: .unknown(reason: "未提供渗透量"),
                                            exfiltration: .unknown(reason: "未提供渗出量"), density: .unknown(reason: "未提供空气密度依据"),
                                            openings: openings.map { .init(openingID: $0.id, openFraction: .unknown(reason: "未提供门窗开启状态")) })]
        if options.includeHVAC {
            let deviceID = UUID()
            let position = Position3D(x: options.width / 2, y: options.depth - 0.1, z: options.height - 0.3)
            func port(_ role: PortRole, z: Double, direction: Direction3D) -> AirPort {
                .init(id: UUID(), role: role, position: .init(x: position.x, y: position.y, z: z), direction: direction,
                      area: .unknown(reason: "未提供风口面积"), volumeFlow: .unknown(reason: "未提供风量"),
                      speed: .unknown(reason: "未提供风速"), density: .unknown(reason: "未提供空气密度依据"))
            }
            scenario.inputs.hvac = [.init(id: deviceID, roomID: roomID, name: "分体空调（参数待补充）", position: position,
                                         definition: try ExtensionRecord(SingleSplit(coolingCapacity: .unknown(reason: "未提供制冷量依据"),
                                                                                    electricalPower: .unknown(reason: "未提供电功率依据"), cop: .unknown(reason: "未提供 COP 依据"))),
                                         ports: [port(.supply, z: position.z - 0.05, direction: .init(x: 0, y: -1, z: 0)),
                                                 port(.return, z: position.z + 0.05, direction: .init(x: 0, y: 1, z: 0))],
                                         supplyTemperature: .unknown(reason: "未提供运行送风温度"))]
            scenario.inputs.controls = [.init(id: UUID(), deviceID: deviceID, setpoint: .unknown(reason: "未提供设定温度"),
                                             sensorPosition: seats[0].samples[0].position, schedule: schedule)]
        }
        let project = ProjectDocument(id: UUID(), name: options.projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                                      spaceType: kind == .office ? .office : kind == .home ? .home : .classroom,
                                      geometry: .init(rooms: [room], obstacles: obstacles), scenarios: [scenario])
        let report = try ProjectValidator().validate(project, registry: .builtIn)
        guard report.passes(.projectIntegrity) else {
            throw ProjectTemplateError.invalidProject(report.issues.filter { $0.blocks.contains(.projectIntegrity) })
        }
        return .init(project: project, templateID: kind.id, templateVersion: kind.version, baselineScenarioID: scenario.id)
    }

    private static func validate(_ options: ProjectTemplateOptions) throws {
        guard !options.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectTemplateError.invalidOption("请输入项目名称。")
        }
        let lengths = [options.width, options.depth, options.height, options.columnSpacing, options.rowSpacing,
                       options.deskWidth, options.deskDepth, options.deskHeight]
        guard lengths.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw ProjectTemplateError.invalidOption("尺寸与间距必须是大于零的有限数，单位为 m。")
        }
        // Explicit bounded creation avoids accidental unbounded work from imported UI option values.
        guard (1...500).contains(options.seatCount), (1...500).contains(options.rows), (1...500).contains(options.columns),
              options.seatCount <= options.rows * options.columns else {
            throw ProjectTemplateError.invalidOption("座位、行数和列数须在 1…500，座位数不能超过行数 × 列数。")
        }
        guard 0 <= options.activeStartMinute, options.activeStartMinute < options.activeEndMinute,
              options.activeEndMinute <= 1440 else {
            throw ProjectTemplateError.invalidOption("使用时段须满足 0 ≤ 开始 < 结束 ≤ 1440 分钟。")
        }
    }
}
