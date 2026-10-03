import SwiftUI
import SimuCore

/// Inspector fields show at most two decimals. The bound Double keeps full precision.
private enum InspectorNumberFormat {
    static let twoPlaces = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)
    static let integer = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)
}

/// Shared Mac inspector / iOS detail editor. Does not submit simulation jobs.
public struct RoomEditorForm: View {
    @Bindable var store: WorkspaceStore
    @State private var sizeX: Double = 0
    @State private var sizeY: Double = 0
    @State private var sizeZ: Double = 0
    @State private var northYaw: Double = 0
    @State private var occupantCount: Double = 0
    @State private var occupiedStart = "08:00"
    @State private var occupiedEnd = "18:00"
    @State private var tariffPriceText = "1.2"
    @State private var tariffCurrency = "HKD"
    @State private var tariffSource: ParameterSource = .assumed
    @State private var tariffReference = "比赛演示假设，非真实电价"
    /// Keep 计算准备 open after a folder pick so the result is not off-screen.
    @State private var prepExpanded = true

    public init(store: WorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("项目") {
                LabeledContent("状态", value: statusText)
                    .accessibilityLabel("项目状态 \(statusText)")
                LabeledContent("项目包", value: store.packageURL?.lastPathComponent ?? "未保存")
                    .accessibilityLabel("项目包 \(store.packageURL?.lastPathComponent ?? "未保存")")
                if let warning = store.packageWarning {
                    Text(warning)
                        .font(.footnote)
                        .accessibilityLabel(warning)
                }
                if let error = store.packageError {
                    Text(error)
                        .font(.footnote)
                        .accessibilityLabel("项目包错误 \(error)")
                }
                LabeledContent("计算", value: store.engineStatus)
                    .accessibilityLabel("计算 \(store.engineStatus)")
                if let name = store.engineFolderName {
                    LabeledContent("计算文件夹", value: name)
                        .accessibilityLabel("计算文件夹 \(name)")
                }
            }
            if store.project == nil {
                Section("开始") {
                    Button("从办公室模板创建") {
                        store.loadOfficeTemplate()
                    }
                    .accessibilityLabel("从办公室模板创建项目")
                    Button("从教室模板创建") {
                        store.loadClassroomTemplate()
                    }
                    .accessibilityLabel("从教室模板创建项目")
                    Text("模板会填入房间、人员和空调。墙保温和天气还没填时不会按 0 计算。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            enginePrepSection
            Section("房间") {
                sizeField("长度", value: $sizeX, pathHint: "geometry.sizeX")
                sizeField("宽度", value: $sizeY, pathHint: "geometry.sizeY")
                sizeField("高度", value: $sizeZ, pathHint: "geometry.sizeZ")
                Button("应用尺寸") {
                    store.applyRoomSize(x: sizeX, y: sizeY, z: sizeZ)
                    refreshFromStore()
                }
                .accessibilityLabel("应用房间尺寸，单位米")
                Text("0° 表示近侧墙的对面是北。改朝向不会自动转动已经放好的门窗。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("哪面墙朝北（度）", value: $northYaw, format: InspectorNumberFormat.twoPlaces)
                    .accessibilityLabel("哪面墙朝北，单位度")
                Button("应用朝向") {
                    store.applyNorthYawDegrees(northYaw)
                }
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再添加门窗。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.project?.geometry?.openings ?? []) { opening in
                        OpeningEditor(
                            opening: opening,
                            displayTitle: openingDisplayTitle(opening),
                            issue: store.fieldIssues.first(where: { $0.path == "geometry.openings.\(opening.id)" }),
                            onApply: { kind, wall, s0, s1, z0, z1, source in
                                store.applyOpening(
                                    id: opening.id,
                                    kind: kind,
                                    wall: wall,
                                    s0: s0,
                                    s1: s1,
                                    z0: z0,
                                    z1: z1,
                                    source: source
                                )
                            },
                            onDelete: { store.removeOpening(id: opening.id) }
                        )
                    }
                    Button("添加窗") {
                        addOpening(kind: .window)
                    }
                    .accessibilityLabel("添加窗，沿墙位置单位米")
                    Button("添加门") {
                        addOpening(kind: .door)
                    }
                    .accessibilityLabel("添加门，沿墙位置单位米")
                }
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再添加家具。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array((store.project?.geometry?.obstacles ?? []).enumerated()), id: \.element.id) { index, box in
                        ObstacleEditor(
                            box: box,
                            displayTitle: UserFacingCopy.furnitureTitle(index: index),
                            issue: store.fieldIssues.first(where: { $0.path == "geometry.obstacles.\(box.id)" }),
                            onApply: { origin, size in
                                store.applyObstacle(id: box.id, origin: origin, size: size)
                            },
                            onDelete: { store.removeObstacle(id: box.id) }
                        )
                    }
                    Button("添加家具") {
                        addObstacle()
                    }
                    .accessibilityLabel("添加家具，位置与尺寸单位米")
                    Text("增删窗、门、家具后，三维视口会立刻更新。家具外形是示意桌，目前不进气流网格。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("使用") {
                Text("人数和座位必须相同。加座位会加一个人，改人数会增删座位。时段是选定的一天，不是全年。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("人数", value: $occupantCount, format: InspectorNumberFormat.integer)
                    .accessibilityLabel("人数")
                Button("应用人数") {
                    store.applyOccupantCount(occupantCount)
                }
                .accessibilityLabel("应用人数")
                TextField("开始 HH:MM", text: $occupiedStart)
                    .accessibilityLabel("使用开始时间")
                TextField("结束 HH:MM", text: $occupiedEnd)
                    .accessibilityLabel("使用结束时间")
                Button("应用使用时间") {
                    store.applyOccupiedHours(start: occupiedStart, end: occupiedEnd)
                }
                .accessibilityLabel("应用使用时间")
                Text("每个座位是一个人，也是舒适检查点。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(store.project?.occupancy?.seats ?? []) { seat in
                    SeatEditor(
                        seat: seat,
                        displayTitle: seatDisplayTitle(seat),
                        issue: store.fieldIssues.first(where: { $0.path == "occupancy.seats.\(seat.id)" }),
                        onApply: { position, source in
                            store.applySeat(id: seat.id, position: position, source: source)
                        },
                        onDelete: { store.removeSeat(id: seat.id) }
                    )
                }
                Button("添加座位") {
                    addSeat()
                }
                .accessibilityLabel("添加座位检查点，坐标单位米")
                Text("每个座位在三维里画成椅子和坐着的人。删座位会同时少一个人。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("空调") {
                Button("安装默认分体空调") {
                    store.installDefaultSplitAC()
                }
                .accessibilityLabel("安装默认分体空调，设定与出风温度分开")
                if let hvac = store.project?.hvac {
                    Text("设定 \(UserFacingCopy.displayNumber(hvac.setpointC.value)) °C，出风 \(UserFacingCopy.displayNumber(hvac.supplyTemperatureC.value)) °C。")
                        .font(.footnote)
                    TerminalEditor(
                        title: UserFacingCopy.terminalTitle(isSupply: true),
                        terminal: hvac.supply,
                        issue: store.fieldIssues.first(where: { $0.path == "hvac.supply" }),
                        onApply: { wall, s0, s1, z0, z1, source in
                            store.applySupplyTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
                        }
                    )
                    TerminalEditor(
                        title: UserFacingCopy.terminalTitle(isSupply: false),
                        terminal: hvac.returnTerminal,
                        issue: store.fieldIssues.first(where: { $0.path == "hvac.returnTerminal" }),
                        onApply: { wall, s0, s1, z0, z1, source in
                            store.applyReturnTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
                        }
                    )
                    SupplyFlowEditor(
                        hvac: hvac,
                        airflowIssue: store.fieldIssues.first(where: { $0.path == "hvac.supplyAirflowM3s" }),
                        onApplyOutdoorAir: { store.applyOutdoorAirM3s($0) },
                        onApplySpeed: { store.applySupplySpeedMs($0) },
                        onApplyAirflow: { store.applySupplyAirflowM3s($0) },
                        onRecompute: { store.recomputeSupplyAirflowFromSpeedAndArea() }
                    )
                    Button("移除空调", role: .destructive) {
                        store.removeHVAC()
                    }
                    .accessibilityLabel("移除分体空调，三维视口不再画室内机")
                    Text("出风口画成壁挂室内机，回风口画成格栅。外形是示意，不是实测尺寸。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.fieldIssues.filter { $0.path.hasPrefix("hvac") }) { issue in
                    Text(issue.message)
                        .font(.footnote)
                        .accessibilityLabel(issue.message)
                }
            }
            DisclosureGroup("电价") {
                Text("只算选定的一天，不是全年。改造待报价。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("电价（每千瓦时）", text: $tariffPriceText)
                    .accessibilityLabel("演示电价，每千瓦时")
                TextField("币种", text: $tariffCurrency)
                    .accessibilityLabel("电价币种")
                SourcePicker(source: $tariffSource)
                TextField("出处", text: $tariffReference)
                    .accessibilityLabel("电价出处")
                Button("应用电价") {
                    let trimmedPrice = tariffPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reference = tariffReference.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.applyElectricityTariff(CostAssumptions(
                        pricePerKWh: trimmedPrice.isEmpty ? nil : Double(trimmedPrice),
                        currency: tariffCurrency.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: tariffSource,
                        reference: reference.isEmpty ? nil : reference
                    ))
                }
                .accessibilityLabel("应用演示电价")
                if let tariff = store.project?.costAssumptions {
                    Text("出处 \(UserFacingCopy.sourceTitle(tariff.source))：\(tariff.reference ?? "无出处")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("电价出处 \(UserFacingCopy.sourceTitle(tariff.source)) \(tariff.reference ?? "无出处")")
                }
                Text("缺电价、缺用电功率或缺使用时间时费用省略，不填 0。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("查看假设") {
                if store.lockedAssumptions.isEmpty && listed.isEmpty && store.overridable.isEmpty {
                    Text("还没有需要说明的假设。未知出处不会显示为 0。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.lockedAssumptions, id: \.self) { note in
                        Text(UserFacingCopy.omittedAssumptionTitle(note))
                            .accessibilityLabel(UserFacingCopy.omittedAssumptionTitle(note))
                    }
                    ForEach(listed) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(UserFacingCopy.fieldTitle(item.path))
                            Text(item.provenanceText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let uncertainty = item.uncertainty, let unit = item.unit {
                                Text("不确定度 \(UserFacingCopy.displayQuantity(uncertainty, unit: unit))")
                                    .font(.footnote)
                                    .accessibilityLabel("不确定度 \(UserFacingCopy.displayQuantity(uncertainty, unit: unit))")
                            }
                        }
                    }
                    ForEach(store.overridable, id: \.self) { path in
                        Text(UserFacingCopy.fieldTitle(path))
                            .accessibilityLabel(UserFacingCopy.fieldTitle(path))
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Inspector is already on screen before a template loads, so onAppear alone leaves 0 / 0 / 0.
        .onChange(of: store.project?.id, initial: true) { _, _ in
            refreshFromStore()
        }
        .onChange(of: store.project?.geometry?.sizeX.value) { _, _ in
            refreshFromStore()
        }
        .onChange(of: store.project?.geometry?.sizeY.value) { _, _ in
            refreshFromStore()
        }
        .onChange(of: store.project?.geometry?.sizeZ.value) { _, _ in
            refreshFromStore()
        }
        .onChange(of: store.project?.geometry?.northYawDegrees.value) { _, _ in
            refreshFromStore()
        }
        .onChange(of: store.project?.occupancy?.occupantCount.value) { _, _ in
            refreshFromStore()
        }
        .onChange(of: store.project?.occupancy?.schedule?.start) { _, _ in
            refreshFromStore()
        }
    }

    @ViewBuilder
    private var enginePrepSection: some View {
        DisclosureGroup("计算准备", isExpanded: $prepExpanded) {
            Text(store.engineStatus)
                .font(.footnote)
                .accessibilityLabel(store.engineStatus)
            if let name = store.engineFolderName {
                Text("当前文件夹：\(name)")
                    .font(.footnote)
                    .accessibilityLabel("当前文件夹 \(name)")
            }
            #if os(macOS)
            Text("计算程序会复制到本机工作区。只需选择计算文件夹，不要把路径写进项目。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(store.engineFolderName == nil ? "选择计算文件夹" : "重新选择计算文件夹") {
                store.chooseEnginesRoot()
                prepExpanded = true
            }
            .accessibilityLabel(store.engineFolderName == nil ? "选择计算文件夹" : "重新选择计算文件夹")
            Button("选择程序副本（备用）") {
                store.chooseRepositoryRoot()
                prepExpanded = true
            }
            .accessibilityLabel("选择程序副本，仅当应用资源缺失时")
            #else
            Text("这台设备上还不能在本地估算。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif
            if let message = store.runMessage {
                Text(message)
                    .font(.footnote)
                    .accessibilityLabel(message)
            }
            Text(store.reportStatusLine ?? "加入通过检查的方案后，到「带走结论」导出对比说明。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(store.reportStatusLine ?? "对比说明导出提示")
        }
        .onChange(of: store.engineStatus) { _, _ in
            prepExpanded = true
        }
    }

    private var statusText: String {
        if store.project == nil {
            return "尚未载入"
        }
        if store.isPhysicalModelComplete {
            #if os(macOS)
            if store.l2Client.isConfigured {
                return "房间已齐，可以估算用电并查看座位冷热"
            }
            #endif
            return store.l1Client.isConfigured ? "房间已齐，可以估算这一天用电" : "房间已齐，还需要在计算准备里选择计算文件夹"
        }
        return "房间还不完整"
    }

    private var listed: [ListedAssumption] {
        store.project?.listedAssumptions() ?? []
    }

    private func openingDisplayTitle(_ opening: Opening) -> String {
        UserFacingCopy.openingTitle(for: opening, in: store.project?.geometry?.openings ?? [])
    }

    private func seatDisplayTitle(_ seat: Seat) -> String {
        UserFacingCopy.seatTitle(
            seat: seat,
            seats: store.project?.occupancy?.seats ?? [],
            geometry: store.project?.geometry
        )
    }

    @ViewBuilder
    private func sizeField(_ title: String, value: Binding<Double>, pathHint: String) -> some View {
        VStack(alignment: .leading) {
            TextField("\(title) m", value: value, format: InspectorNumberFormat.twoPlaces)
                .accessibilityLabel("\(title)，米")
            if let issue = store.fieldIssues.first(where: { $0.path == pathHint }) {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
        }
    }

    private func refreshFromStore() {
        sizeX = store.project?.geometry?.sizeX.value ?? 0
        sizeY = store.project?.geometry?.sizeY.value ?? 0
        sizeZ = store.project?.geometry?.sizeZ.value ?? 0
        northYaw = store.project?.geometry?.northYawDegrees.value ?? 0
        occupantCount = store.project?.occupancy?.occupantCount.value ?? 0
        occupiedStart = store.project?.occupancy?.schedule?.start ?? "08:00"
        occupiedEnd = store.project?.occupancy?.schedule?.end ?? "18:00"
        if let tariff = store.project?.costAssumptions {
            tariffPriceText = tariff.pricePerKWh.map(UserFacingCopy.displayNumber) ?? ""
            tariffCurrency = tariff.currency
            tariffSource = tariff.source
            tariffReference = tariff.reference ?? ""
        } else {
            tariffPriceText = ""
            tariffCurrency = "HKD"
            tariffSource = .assumed
            tariffReference = ""
        }
    }

    private func addOpening(kind: OpeningKind) {
        let prefix = kind == .window ? "W" : "D"
        let existing = store.project?.geometry?.openings.map(\.id) ?? []
        store.applyOpening(
            id: ProjectDraft.nextPrefixedID(prefix: prefix, existing: existing),
            kind: kind,
            wall: .xMax,
            s0: 0.5,
            s1: kind == .window ? 2.0 : 1.4,
            z0: kind == .window ? 0.9 : 0,
            z1: kind == .window ? 2.2 : 2.1,
            source: .user
        )
    }

    private func addObstacle() {
        let existing = store.project?.geometry?.obstacles.map(\.id) ?? []
        store.applyObstacle(
            id: ProjectDraft.nextPrefixedID(prefix: "F", existing: existing),
            origin: Position3D(x: 1, y: 1, z: 0),
            size: Position3D(x: 1.2, y: 0.7, z: 0.75)
        )
    }

    private func addSeat() {
        let existing = store.project?.occupancy?.seats.map(\.id) ?? []
        store.applySeat(
            id: ProjectDraft.nextPrefixedID(prefix: "S", existing: existing),
            position: Position3D(x: 1.5, y: 1.5, z: 1.1),
            source: .user
        )
    }
}

private struct OpeningEditor: View {
    let opening: Opening
    let displayTitle: String
    let issue: FieldIssue?
    let onApply: (OpeningKind, WallFace, Double, Double, Double, Double, ParameterSource) -> Void
    let onDelete: () -> Void

    @State private var kind: OpeningKind
    @State private var wall: WallFace
    @State private var s0: Double
    @State private var s1: Double
    @State private var z0: Double
    @State private var z1: Double
    @State private var source: ParameterSource

    init(
        opening: Opening,
        displayTitle: String,
        issue: FieldIssue?,
        onApply: @escaping (OpeningKind, WallFace, Double, Double, Double, Double, ParameterSource) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.opening = opening
        self.displayTitle = displayTitle
        self.issue = issue
        self.onApply = onApply
        self.onDelete = onDelete
        _kind = State(initialValue: opening.kind)
        _wall = State(initialValue: opening.wall)
        _s0 = State(initialValue: opening.s0.value)
        _s1 = State(initialValue: opening.s1.value)
        _z0 = State(initialValue: opening.z0.value)
        _z1 = State(initialValue: opening.z1.value)
        _source = State(initialValue: opening.s0.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
            Picker("类型", selection: $kind) {
                ForEach(OpeningKind.allCases, id: \.self) { item in
                    Text(item.editorLabel).tag(item)
                }
            }
            .accessibilityLabel("开口类型")
            WallPicker(wall: $wall)
            SourcePicker(source: $source)
            NumericField("沿墙起点", value: $s0, unit: "m")
            NumericField("沿墙终点", value: $s1, unit: "m")
            NumericField("离地高度", value: $z0, unit: "m")
            NumericField("上沿高度", value: $z1, unit: "m")
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel("开口错误 \(issue.message)")
            }
            Button("应用开口") {
                onApply(kind, wall, s0, s1, z0, z1, source)
            }
            .accessibilityLabel("应用\(displayTitle)，单位米")
            Button("删除开口", role: .destructive, action: onDelete)
                .accessibilityLabel("删除\(displayTitle)")
        }
        .padding(.vertical, 4)
        .onChange(of: opening) { _, updated in
            kind = updated.kind
            wall = updated.wall
            s0 = updated.s0.value
            s1 = updated.s1.value
            z0 = updated.z0.value
            z1 = updated.z1.value
            source = updated.s0.source
        }
    }
}

private struct ObstacleEditor: View {
    let box: ObstacleBox
    let displayTitle: String
    let issue: FieldIssue?
    let onApply: (Position3D, Position3D) -> Void
    let onDelete: () -> Void

    @State private var originX: Double
    @State private var originY: Double
    @State private var originZ: Double
    @State private var sizeX: Double
    @State private var sizeY: Double
    @State private var sizeZ: Double

    init(
        box: ObstacleBox,
        displayTitle: String,
        issue: FieldIssue?,
        onApply: @escaping (Position3D, Position3D) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.box = box
        self.displayTitle = displayTitle
        self.issue = issue
        self.onApply = onApply
        self.onDelete = onDelete
        _originX = State(initialValue: box.origin.x)
        _originY = State(initialValue: box.origin.y)
        _originZ = State(initialValue: box.origin.z)
        _sizeX = State(initialValue: box.size.x)
        _sizeY = State(initialValue: box.size.y)
        _sizeZ = State(initialValue: box.size.z)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
            NumericField("左右", value: $originX, unit: "m")
            NumericField("前后", value: $originY, unit: "m")
            NumericField("离地", value: $originZ, unit: "m")
            NumericField("长度", value: $sizeX, unit: "m")
            NumericField("宽度", value: $sizeY, unit: "m")
            NumericField("高度", value: $sizeZ, unit: "m")
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
            Button("应用家具") {
                onApply(
                    Position3D(x: originX, y: originY, z: originZ),
                    Position3D(x: sizeX, y: sizeY, z: sizeZ)
                )
            }
            .accessibilityLabel("应用\(displayTitle)，单位米")
            Button("删除家具", role: .destructive, action: onDelete)
                .accessibilityLabel("删除\(displayTitle)")
        }
        .padding(.vertical, 4)
        .onChange(of: box) { _, updated in
            originX = updated.origin.x
            originY = updated.origin.y
            originZ = updated.origin.z
            sizeX = updated.size.x
            sizeY = updated.size.y
            sizeZ = updated.size.z
        }
    }
}

private struct SeatEditor: View {
    let seat: Seat
    let displayTitle: String
    let issue: FieldIssue?
    let onApply: (Position3D, ParameterSource) -> Void
    let onDelete: () -> Void

    @State private var x: Double
    @State private var y: Double
    @State private var z: Double
    @State private var source: ParameterSource

    init(
        seat: Seat,
        displayTitle: String,
        issue: FieldIssue?,
        onApply: @escaping (Position3D, ParameterSource) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.seat = seat
        self.displayTitle = displayTitle
        self.issue = issue
        self.onApply = onApply
        self.onDelete = onDelete
        _x = State(initialValue: seat.position.x)
        _y = State(initialValue: seat.position.y)
        _z = State(initialValue: seat.position.z)
        _source = State(initialValue: seat.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
            NumericField("左右", value: $x, unit: "m")
            NumericField("前后", value: $y, unit: "m")
            NumericField("坐姿高度", value: $z, unit: "m")
            SourcePicker(source: $source)
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
            Button("应用座位") {
                onApply(Position3D(x: x, y: y, z: z), source)
            }
            .accessibilityLabel("应用\(displayTitle)，单位米")
            Button("删除座位", role: .destructive, action: onDelete)
                .accessibilityLabel("删除\(displayTitle)")
        }
        .padding(.vertical, 4)
        .onChange(of: seat) { _, updated in
            x = updated.position.x
            y = updated.position.y
            z = updated.position.z
            source = updated.source
        }
    }
}

private struct TerminalEditor: View {
    let title: String
    let terminal: AirTerminal
    let issue: FieldIssue?
    let onApply: (WallFace, Double, Double, Double, Double, ParameterSource) -> Void

    @State private var wall: WallFace
    @State private var s0: Double
    @State private var s1: Double
    @State private var z0: Double
    @State private var z1: Double
    @State private var source: ParameterSource

    init(
        title: String,
        terminal: AirTerminal,
        issue: FieldIssue?,
        onApply: @escaping (WallFace, Double, Double, Double, Double, ParameterSource) -> Void
    ) {
        self.title = title
        self.terminal = terminal
        self.issue = issue
        self.onApply = onApply
        _wall = State(initialValue: terminal.wall)
        _s0 = State(initialValue: terminal.s0.value)
        _s1 = State(initialValue: terminal.s1.value)
        _z0 = State(initialValue: terminal.z0.value)
        _z1 = State(initialValue: terminal.z1.value)
        _source = State(initialValue: terminal.s0.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            WallPicker(wall: $wall)
            SourcePicker(source: $source)
            NumericField("沿墙起点", value: $s0, unit: "m")
            NumericField("沿墙终点", value: $s1, unit: "m")
            NumericField("离地高度", value: $z0, unit: "m")
            NumericField("上沿高度", value: $z1, unit: "m")
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
            Button("应用\(title)") {
                onApply(wall, s0, s1, z0, z1, source)
            }
            .accessibilityLabel("应用\(title)，沿墙位置单位米")
        }
        .padding(.vertical, 4)
        .onChange(of: terminal) { _, updated in
            wall = updated.wall
            s0 = updated.s0.value
            s1 = updated.s1.value
            z0 = updated.z0.value
            z1 = updated.z1.value
            source = updated.s0.source
        }
    }
}

private struct SupplyFlowEditor: View {
    let hvac: HVACModel
    let airflowIssue: FieldIssue?
    let onApplyOutdoorAir: (Double) -> Void
    let onApplySpeed: (Double) -> Void
    let onApplyAirflow: (Double) -> Void
    let onRecompute: () -> Void

    @State private var outdoorAir: Double
    @State private var speed: Double
    @State private var airflow: Double

    init(
        hvac: HVACModel,
        airflowIssue: FieldIssue?,
        onApplyOutdoorAir: @escaping (Double) -> Void,
        onApplySpeed: @escaping (Double) -> Void,
        onApplyAirflow: @escaping (Double) -> Void,
        onRecompute: @escaping () -> Void
    ) {
        self.hvac = hvac
        self.airflowIssue = airflowIssue
        self.onApplyOutdoorAir = onApplyOutdoorAir
        self.onApplySpeed = onApplySpeed
        self.onApplyAirflow = onApplyAirflow
        self.onRecompute = onRecompute
        _outdoorAir = State(initialValue: hvac.outdoorAirM3s.value)
        _speed = State(initialValue: hvac.supplySpeedMs.value)
        _airflow = State(initialValue: hvac.supplyAirflowM3s.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("出风口面积", value: UserFacingCopy.displayQuantity(hvac.supply.patchAreaM2, unit: "m²"))
                .accessibilityLabel("出风口面积 \(UserFacingCopy.displayNumber(hvac.supply.patchAreaM2)) 平方米")
            NumericField("出风速度", value: $speed, unit: "m/s")
            Button("应用出风速度") {
                onApplySpeed(speed)
            }
            .accessibilityLabel("应用出风速度，单位米每秒，并按面积重算风量")
            NumericField("出风量", value: $airflow, unit: "m3/s")
            Button("应用出风量") {
                onApplyAirflow(airflow)
            }
            .accessibilityLabel("应用出风量，单位立方米每秒")
            Button("按速度×面积重算风量", action: onRecompute)
                .accessibilityLabel("按速度乘面积重算出风量")
            if let airflowIssue {
                Text(airflowIssue.message)
                    .font(.footnote)
                    .accessibilityLabel(airflowIssue.message)
            }
            NumericField("室外新风", value: $outdoorAir, unit: "m3/s")
            Button("应用室外新风") {
                onApplyOutdoorAir(outdoorAir)
            }
            .accessibilityLabel("应用室外新风，与回风口分开，单位立方米每秒")
        }
        .padding(.vertical, 4)
        .onChange(of: hvac) { _, updated in
            outdoorAir = updated.outdoorAirM3s.value
            speed = updated.supplySpeedMs.value
            airflow = updated.supplyAirflowM3s.value
        }
    }
}

private struct NumericField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, unit: String) {
        self.title = title
        self._value = value
        self.unit = unit
    }

    var body: some View {
        TextField("\(title) \(unit)", value: $value, format: InspectorNumberFormat.twoPlaces)
            .accessibilityLabel("\(title)，\(unit)")
    }
}

private struct WallPicker: View {
    @Binding var wall: WallFace

    var body: some View {
        Picker("墙面", selection: $wall) {
            ForEach(WallFace.allCases, id: \.self) { face in
                Text(UserFacingCopy.wallTitle(face)).tag(face)
            }
        }
        .accessibilityLabel("墙面")
    }
}

private struct SourcePicker: View {
    @Binding var source: ParameterSource

    var body: some View {
        Picker("来源", selection: $source) {
            ForEach(ParameterSource.allCases, id: \.self) { item in
                Text(UserFacingCopy.sourceTitle(item)).tag(item)
            }
        }
        .accessibilityLabel("参数来源")
    }
}

private extension OpeningKind {
    var editorLabel: String {
        switch self {
        case .window: "窗"
        case .door: "门"
        }
    }
}
