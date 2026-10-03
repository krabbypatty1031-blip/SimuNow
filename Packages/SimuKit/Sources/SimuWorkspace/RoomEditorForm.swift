import SwiftUI
import SimuCore
import SimuDesignSystem

/// Which room item is open. The list stays in the sidebar; the editor uses the other column.
enum InspectorPage: Hashable {
    case list
    case room
    case opening(String)
    case obstacle(String)
    /// Top-down drag-to-place plan (user request 2026-10-04).
    case furniturePlan
    case occupancy
    case seat(String)
    case temperatures
    case supply
    case returnTerminal
    case airflow
    case engines
}

/// Inspector fields show at most two decimals. The bound Double keeps full precision.
private enum InspectorNumberFormat {
    static let twoPlaces = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)
    static let integer = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)
}

/// Where this form draws. Sidebar and detail share one `InspectorPage` on the Mac.
enum RoomInspectorColumn {
    /// Rows inside the leading sidebar list. Selecting a row does not replace the list.
    case sidebar
    /// Editor for the selected row, shown in the trailing inspector.
    case detail
    /// iPhone: the list and the editor share one column.
    case stack
}

/// Shared Mac inspector / iOS detail editor. Does not submit simulation jobs.
public struct RoomEditorForm: View {
    @Bindable var store: WorkspaceStore
    private var page: Binding<InspectorPage>?
    private var column: RoomInspectorColumn
    @State private var ownedPage = InspectorPage.list
    /// One parent disclosure over the room-editing sections (user request
    /// 2026-10-04): 房间 / 门窗 / 家具 / 使用 / 空调 collapse together so the
    /// sidebar can be tidied with a single tap. 计算准备 stays outside — it
    /// is a global navigation row, not room content.
    @State private var isRoomSettingsExpanded = true
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
    @State private var setpointC: Double = 26
    @State private var supplyTemperatureC: Double = 16
    public init(store: WorkspaceStore) {
        self.store = store
        self.page = nil
        self.column = .stack
    }

    init(store: WorkspaceStore, page: Binding<InspectorPage>, column: RoomInspectorColumn) {
        self.store = store
        self.page = page
        self.column = column
    }

    private var currentPage: InspectorPage {
        page?.wrappedValue ?? ownedPage
    }

    public var body: some View {
        switch column {
        case .sidebar:
            listColumn
                .onChange(of: store.project?.id) { _, _ in
                    show(.list)
                }
        case .detail:
            detailForm
        case .stack:
            Form {
                if currentPage == .list {
                    listColumn
                } else {
                    editorColumn
                }
            }
            .formStyle(.grouped)
            .onChange(of: store.project?.id, initial: true) { _, _ in
                show(.list)
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
    }

    private var detailForm: some View {
        Form {
            editorColumn
        }
        .id(currentPage)
        .formStyle(.grouped)
        .onAppear {
            refreshFromStore()
        }
        .onChange(of: currentPage) { _, _ in
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
    private var listColumn: some View {
        if let warning = store.packageWarning {
            Section {
                Text(warning)
                    .font(.footnote)
                    .accessibilityLabel(warning)
            }
            // PR#4 moved the engines/run-message block into the inspector's
            // 计算准备 page (enginesEditor); the sidebar list stays a list.
        }
        if let error = store.packageError {
            Section {
                Text(error)
                    .font(.footnote)
                    .accessibilityLabel("项目包错误 \(error)")
            }
        }
        Section {
            InspectorRow(title: "计算准备", isSelected: currentPage == .engines) { toggle(.engines) }
                .accessibilityLabel("计算准备、电价和假设")
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
        } else {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("项目状态 \(statusText)")
            // 父折叠栏（用户要求 2026-10-04）：房间/门窗/家具/使用/空调
            // 五节统一收进一个开关，一点收起或展开，替代原来平铺五个分区。
            DisclosureGroup("房间设置", isExpanded: $isRoomSettingsExpanded) {
                Section("房间") {
                InspectorRow(title: roomLine, isSelected: currentPage == .room) { toggle(.room) }
                    .accessibilityLabel("编辑房间尺寸 \(roomLine)")
            }
            Section("门窗") {
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再添加门窗。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.project?.geometry?.openings ?? []) { opening in
                        InspectorRow(title: openingSummary(opening), isSelected: currentPage == .opening(opening.id)) {
                            toggle(.opening(opening.id))
                        }
                    }
                    // 横排且左对齐（用户要求 2026-10-04）：两个按钮从左边
                    // 紧挨着排，收缩到文字宽度，不再各占半行撑满整行。
                    HStack(spacing: 12) {
                        Button("添加窗") { addOpening(kind: .window) }
                            .fixedSize()
                            .accessibilityLabel("添加窗，沿墙位置单位米")
                        Button("添加门") { addOpening(kind: .door) }
                            .fixedSize()
                            .accessibilityLabel("添加门，沿墙位置单位米")
                    }
                }
            }
            Section("家具") {
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再添加家具。")
                        .foregroundStyle(.secondary)
                } else if store.project?.geometry?.obstacles.isEmpty == true {
                    Text("还没有家具。可以在俯视图里拖入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array((store.project?.geometry?.obstacles ?? []).enumerated()), id: \.element.id) { index, box in
                    InspectorRow(title: furnitureSummary(box, index: index), isSelected: currentPage == .obstacle(box.id)) {
                        toggle(.obstacle(box.id))
                    }
                }
                InspectorRow(title: "俯视图拖拽布置家具", isSelected: currentPage == .furniturePlan) {
                    toggle(.furniturePlan)
                }
                .accessibilityLabel("俯视图拖拽布置家具，类型先选再拖入")
                // 类型按钮（用户要求 2026-10-04）：家具按类型添加，各自带
                // 默认尺寸落到房间一角附近，之后可拖拽或数值微调。
                // FlowLayout（2026-10-04 修复）：检查器窄列容不下四个按钮的
                // 一整行，HStack 不折行会把右端裁掉；流式布局保持横排、
                // 放不下才折到下一行，宽检查器与 iPhone 整行仍是一行。
                FlowLayout(spacing: 12) {
                    ForEach(FurnitureKind.allCases, id: \.self) { kind in
                        Button("添加\(kind.title)") { addObstacle(kind: kind) }
                            .fixedSize()
                            .accessibilityLabel("添加\(kind.title)，默认尺寸单位米")
                    }
                }
                .disabled(store.project?.geometry == nil)
            }
            Section("使用") {
                InspectorRow(title: occupancyLine, isSelected: currentPage == .occupancy) { toggle(.occupancy) }
                    .accessibilityLabel("编辑人数和使用时间 \(occupancyLine)")
                ForEach(store.project?.occupancy?.seats ?? []) { seat in
                    InspectorRow(title: seatSummary(seat), isSelected: currentPage == .seat(seat.id)) {
                        toggle(.seat(seat.id))
                    }
                }
                Button("添加座位") { addSeat() }
                    .accessibilityLabel("添加座位检查点，坐标单位米")
            }
            Section("空调") {
                if store.project?.hvac == nil {
                    Button("安装默认分体空调") {
                        store.installDefaultSplitAC()
                    }
                    .accessibilityLabel("安装默认分体空调，设定与出风温度分开")
                } else if let hvac = store.project?.hvac {
                    InspectorRow(title: temperatureLine, isSelected: currentPage == .temperatures) { toggle(.temperatures) }
                        .accessibilityLabel("编辑设定温度和出风温度")
                    InspectorRow(title: terminalSummary(hvac.supply, isSupply: true), isSelected: currentPage == .supply) {
                        toggle(.supply)
                    }
                    InspectorRow(title: terminalSummary(hvac.returnTerminal, isSupply: false), isSelected: currentPage == .returnTerminal) {
                        toggle(.returnTerminal)
                    }
                    InspectorRow(title: "风量与新风", isSelected: currentPage == .airflow) { toggle(.airflow) }
                    }
                }
            }
            // Closes the 房间设置 parent disclosure.
        }
    }

    @ViewBuilder
    private var editorColumn: some View {
        if column == .stack {
            Section {
                Button {
                    show(.list)
                } label: {
                    Label("返回", systemImage: "chevron.backward")
                }
                .accessibilityLabel("返回房间清单")
            }
        }
        switch currentPage {
        case .list:
            EmptyView()
        case .room:
            Section("房间") { roomEditor }
        case .opening(let id):
            if let opening = store.project?.geometry?.openings.first(where: { $0.id == id }) {
                Section(openingDisplayTitle(opening)) {
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
                        onDelete: {
                            store.removeOpening(id: opening.id)
                            show(.list)
                        }
                    )
                }
            } else {
                missingItem
            }
        case .obstacle(let id):
            if let box = store.project?.geometry?.obstacles.first(where: { $0.id == id }) {
                Section(furnitureTitle(for: box)) {
                    ObstacleEditor(
                        box: box,
                        displayTitle: furnitureTitle(for: box),
                        issue: store.fieldIssues.first(where: { $0.path == "geometry.obstacles.\(box.id)" }),
                        onApply: { kind, origin, size in
                            store.applyObstacle(id: box.id, origin: origin, size: size, kind: kind)
                        },
                        onDelete: {
                            store.removeObstacle(id: box.id)
                            show(.list)
                        }
                    )
                    if let message = store.furniturePlacementMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("放置被拒绝 \(message)")
                    }
                    Text("外形是示意。家具以整格阻挡进入气流计算，与外形细节无关。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                missingItem
            }
        case .furniturePlan:
            Section("俯视图拖拽布置") {
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再布置家具。")
                        .foregroundStyle(.secondary)
                } else {
                    FurniturePlanView(store: store)
                }
                Text("松手时只放在房间内、不压其他家具、座位、送回风带和窗户的位置；不合法的位置会被拒绝并说明原因。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .occupancy:
            Section("人数与时间") { occupancyEditor }
        case .seat(let id):
            if let seat = store.project?.occupancy?.seats.first(where: { $0.id == id }) {
                Section(seatDisplayTitle(seat)) {
                    SeatEditor(
                        seat: seat,
                        displayTitle: seatDisplayTitle(seat),
                        issue: store.fieldIssues.first(where: { $0.path == "occupancy.seats.\(seat.id)" }),
                        onApply: { position, source in
                            store.applySeat(id: seat.id, position: position, source: source)
                        },
                        onDelete: {
                            store.removeSeat(id: seat.id)
                            show(.list)
                        }
                    )
                    Text("删座位会同时少一个人。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                missingItem
            }
        case .temperatures:
            Section("温度") { temperatureEditor }
        case .supply:
            if let hvac = store.project?.hvac {
                Section(UserFacingCopy.terminalTitle(isSupply: true)) {
                    TerminalEditor(
                        title: UserFacingCopy.terminalTitle(isSupply: true),
                        terminal: hvac.supply,
                        issue: store.fieldIssues.first(where: { $0.path == "hvac.supply" }),
                        onApply: { wall, s0, s1, z0, z1, source in
                            store.applySupplyTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
                        }
                    )
                    Text("出风口画成壁挂室内机。外形是示意，不是实测尺寸。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                missingItem
            }
        case .returnTerminal:
            if let hvac = store.project?.hvac {
                Section(UserFacingCopy.terminalTitle(isSupply: false)) {
                    TerminalEditor(
                        title: UserFacingCopy.terminalTitle(isSupply: false),
                        terminal: hvac.returnTerminal,
                        issue: store.fieldIssues.first(where: { $0.path == "hvac.returnTerminal" }),
                        onApply: { wall, s0, s1, z0, z1, source in
                            store.applyReturnTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
                        }
                    )
                    Text("回风口画成格栅。外形是示意，不是实测尺寸。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                missingItem
            }
        case .airflow:
            if let hvac = store.project?.hvac {
                Section("风量与新风") {
                    SupplyFlowEditor(
                        hvac: hvac,
                        airflowIssue: store.fieldIssues.first(where: { $0.path == "hvac.supplyAirflowM3s" }),
                        onApplyOutdoorAir: { store.applyOutdoorAirM3s($0) },
                        onApplySpeed: { store.applySupplySpeedMs($0) },
                        onApplyAirflow: { store.applySupplyAirflowM3s($0) },
                        onRecompute: { store.recomputeSupplyAirflowFromSpeedAndArea() }
                    )
                }
            } else {
                missingItem
            }
        case .engines:
            Section("计算准备") { enginesEditor }
            Section("电价") { tariffEditor }
            Section("查看假设") { assumptionsEditor }
        }
    }

    private var missingItem: some View {
        Section {
            Text("这一项已经不在房间里。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var roomEditor: some View {
        sizeField("长度", value: $sizeX, pathHint: "geometry.sizeX")
        sizeField("宽度", value: $sizeY, pathHint: "geometry.sizeY")
        sizeField("高度", value: $sizeZ, pathHint: "geometry.sizeZ")
        ApplyButton(
            title: "应用尺寸",
            isDirty: roomSizeIsDirty,
            accessibilityLabel: "应用房间尺寸，单位米"
        ) {
            store.applyRoomSize(x: sizeX, y: sizeY, z: sizeZ)
            refreshFromStore()
        }
        NumericField("哪面墙朝北", value: $northYaw, unit: "°")
        Text("0° 表示近侧墙的对面是北。改朝向不会挪动已经放好的门窗。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        ApplyButton(
            title: "应用朝向",
            isDirty: northYawIsDirty,
            accessibilityLabel: "应用朝向，单位度"
        ) {
            store.applyNorthYawDegrees(northYaw)
        }
    }

    @ViewBuilder
    private var occupancyEditor: some View {
        LabeledContent("人数") {
            TextField("人数", value: $occupantCount, format: InspectorNumberFormat.integer)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
        }
        .accessibilityLabel("人数")
        ApplyButton(
            title: "应用人数",
            isDirty: occupantCountIsDirty,
            accessibilityLabel: "应用人数"
        ) {
            store.applyOccupantCount(occupantCount)
        }
        Text("人数和座位数保持一致。改人数会增删座位。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        LabeledContent("开始") {
            TextField("开始", text: $occupiedStart)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
        }
        .accessibilityLabel("使用开始时间")
        LabeledContent("结束") {
            TextField("结束", text: $occupiedEnd)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
        }
        .accessibilityLabel("使用结束时间")
        ApplyButton(
            title: "应用使用时间",
            isDirty: occupiedHoursAreDirty,
            accessibilityLabel: "应用使用时间"
        ) {
            store.applyOccupiedHours(start: occupiedStart, end: occupiedEnd)
        }
        Text("时段是选定的一天，不是全年。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var temperatureEditor: some View {
        if store.project?.hvac == nil {
            Text("还没有安装空调。")
                .foregroundStyle(.secondary)
        } else {
            NumericField("设定温度", value: $setpointC, unit: "°C")
            NumericField("出风温度", value: $supplyTemperatureC, unit: "°C")
            Text("设定温度是房间目标，出风温度是空调吹出来的空气，两者分开。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ApplyButton(
                title: "应用温度",
                isDirty: temperaturesAreDirty,
                accessibilityLabel: "应用设定温度和出风温度，单位摄氏度"
            ) {
                if setpointC != store.project?.hvac?.setpointC.value {
                    store.applyZoneSetpointC(setpointC)
                }
                if supplyTemperatureC != store.project?.hvac?.supplyTemperatureC.value {
                    store.applySupplyTemperatureC(supplyTemperatureC)
                }
            }
            Button("移除空调", role: .destructive) {
                store.removeHVAC()
                show(.list)
            }
            .accessibilityLabel("移除分体空调，三维视口不再画室内机")
            ForEach(store.fieldIssues.filter { $0.path.hasPrefix("hvac") && $0.path != "hvac.supply" && $0.path != "hvac.returnTerminal" && $0.path != "hvac.supplyAirflowM3s" }) { issue in
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
        }
    }

    @ViewBuilder
    private var enginesEditor: some View {
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
        }
        .accessibilityLabel(store.engineFolderName == nil ? "选择计算文件夹" : "重新选择计算文件夹")
        Button("选择程序副本（备用）") {
            store.chooseRepositoryRoot()
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
        // Kept from dev (export-report copy): the engines page also carries the
        // report-export hint; PR#4's move had not seen that commit yet.
        Text(store.reportStatusLine ?? "加入通过检查的方案后，到「导出报告」导出对比说明。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityLabel(store.reportStatusLine ?? "对比说明导出提示")
    }

    @ViewBuilder
    private var tariffEditor: some View {
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
        ApplyButton(
            title: "应用电价",
            isDirty: tariffIsDirty,
            accessibilityLabel: "应用演示电价"
        ) {
            let trimmedPrice = tariffPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let reference = tariffReference.trimmingCharacters(in: .whitespacesAndNewlines)
            store.applyElectricityTariff(CostAssumptions(
                pricePerKWh: trimmedPrice.isEmpty ? nil : Double(trimmedPrice),
                currency: tariffCurrency.trimmingCharacters(in: .whitespacesAndNewlines),
                source: tariffSource,
                reference: reference.isEmpty ? nil : reference
            ))
        }
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

    @ViewBuilder
    private var assumptionsEditor: some View {
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

    private func show(_ next: InspectorPage) {
        if let page {
            page.wrappedValue = next
        } else {
            ownedPage = next
            refreshFromStore()
        }
    }

    /// Selecting the open row again closes the trailing editor.
    private func toggle(_ next: InspectorPage) {
        show(currentPage == next ? .list : next)
    }

    private var roomLine: String {
        guard let geometry = store.project?.geometry else { return "尚未填写尺寸" }
        return "\(UserFacingCopy.displayNumber(geometry.sizeX.value)) × \(UserFacingCopy.displayNumber(geometry.sizeY.value)) × \(UserFacingCopy.displayNumber(geometry.sizeZ.value)) m"
    }

    private var occupancyLine: String {
        let count = Int(store.project?.occupancy?.occupantCount.value ?? 0)
        let start = store.project?.occupancy?.schedule?.start ?? "08:00"
        let end = store.project?.occupancy?.schedule?.end ?? "18:00"
        return "\(count) 人 · \(start)–\(end)"
    }

    private var temperatureLine: String {
        let setpoint = UserFacingCopy.displayNumber(store.project?.hvac?.setpointC.value ?? setpointC)
        let supply = UserFacingCopy.displayNumber(store.project?.hvac?.supplyTemperatureC.value ?? supplyTemperatureC)
        return "设定 \(setpoint) °C · 出风 \(supply) °C"
    }

    private func openingSummary(_ opening: Opening) -> String {
        let title = openingDisplayTitle(opening)
        let span = "\(UserFacingCopy.displayNumber(opening.s0.value))–\(UserFacingCopy.displayNumber(opening.s1.value)) m"
        return "\(title) · \(span)"
    }

    /// Kind-based name (桌子 1 …), numbered within its own kind so the
    /// label names what the user placed.
    private func furnitureTitle(for box: ObstacleBox) -> String {
        guard let obstacles = store.project?.geometry?.obstacles else {
            return box.kind.title
        }
        let index = obstacles.prefix(while: { $0.id != box.id }).filter { $0.kind == box.kind }.count
        return UserFacingCopy.furnitureTitle(kind: box.kind, index: index)
    }

    private func furnitureSummary(_ box: ObstacleBox, index: Int) -> String {
        "\(furnitureTitle(for: box)) · 左右 \(UserFacingCopy.displayNumber(box.origin.x)) · 前后 \(UserFacingCopy.displayNumber(box.origin.y)) m"
    }

    private func seatSummary(_ seat: Seat) -> String {
        let title = seatDisplayTitle(seat)
        return "\(title) · 左右 \(UserFacingCopy.displayNumber(seat.position.x)) · 前后 \(UserFacingCopy.displayNumber(seat.position.y)) m"
    }

    private func terminalSummary(_ terminal: AirTerminal, isSupply: Bool) -> String {
        let title = UserFacingCopy.terminalTitle(isSupply: isSupply)
        let wall = UserFacingCopy.wallTitle(terminal.wall)
        let span = "\(UserFacingCopy.displayNumber(terminal.s0.value))–\(UserFacingCopy.displayNumber(terminal.s1.value)) m"
        return "\(title) · \(wall) \(span)"
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
        VStack(alignment: .leading, spacing: 2) {
            NumericField(title, value: value, unit: "m")
            if let issue = store.fieldIssues.first(where: { $0.path == pathHint }) {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
        }
    }

    private var roomSizeIsDirty: Bool {
        let geometry = store.project?.geometry
        return inspectorValuesDiffer(sizeX, geometry?.sizeX.value ?? 0)
            || inspectorValuesDiffer(sizeY, geometry?.sizeY.value ?? 0)
            || inspectorValuesDiffer(sizeZ, geometry?.sizeZ.value ?? 0)
    }

    private var northYawIsDirty: Bool {
        inspectorValuesDiffer(northYaw, store.project?.geometry?.northYawDegrees.value ?? 0)
    }

    private var occupantCountIsDirty: Bool {
        inspectorValuesDiffer(occupantCount, store.project?.occupancy?.occupantCount.value ?? 0)
    }

    private var occupiedHoursAreDirty: Bool {
        let schedule = store.project?.occupancy?.schedule
        return occupiedStart != (schedule?.start ?? "08:00")
            || occupiedEnd != (schedule?.end ?? "18:00")
    }

    private var temperaturesAreDirty: Bool {
        guard let hvac = store.project?.hvac else { return false }
        return inspectorValuesDiffer(setpointC, hvac.setpointC.value)
            || inspectorValuesDiffer(supplyTemperatureC, hvac.supplyTemperatureC.value)
    }

    private var tariffIsDirty: Bool {
        let stored = store.project?.costAssumptions
        let trimmedPrice = tariffPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let priceDirty: Bool
        if trimmedPrice.isEmpty {
            priceDirty = stored?.pricePerKWh != nil
        } else if let drafted = Double(trimmedPrice) {
            priceDirty = stored?.pricePerKWh.map { inspectorValuesDiffer(drafted, $0) } ?? true
        } else {
            priceDirty = true
        }
        let currencyDirty = tariffCurrency.trimmingCharacters(in: .whitespacesAndNewlines)
            != (stored?.currency ?? "HKD")
        let sourceDirty = tariffSource != (stored?.source ?? .assumed)
        let referenceDirty = tariffReference.trimmingCharacters(in: .whitespacesAndNewlines)
            != (stored?.reference ?? "")
        return priceDirty || currencyDirty || sourceDirty || referenceDirty
    }

    private func refreshFromStore() {
        sizeX = store.project?.geometry?.sizeX.value ?? 0
        sizeY = store.project?.geometry?.sizeY.value ?? 0
        sizeZ = store.project?.geometry?.sizeZ.value ?? 0
        northYaw = store.project?.geometry?.northYawDegrees.value ?? 0
        occupantCount = store.project?.occupancy?.occupantCount.value ?? 0
        occupiedStart = store.project?.occupancy?.schedule?.start ?? "08:00"
        occupiedEnd = store.project?.occupancy?.schedule?.end ?? "18:00"
        setpointC = store.project?.hvac?.setpointC.value ?? 26
        supplyTemperatureC = store.project?.hvac?.supplyTemperatureC.value ?? 16
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
        let id = ProjectDraft.nextPrefixedID(prefix: prefix, existing: existing)
        // New windows get the template-level 80 W/m² (office/classroom preset)
        // so adding a window reaches BOTH engines: L1 area drives the bill,
        // the declared flux drives the L2 field. Marked assumed, not measured.
        let defaultWindowFlux = kind == .window
            ? PhysicalQuantity(value: 80, unit: "W/m2", source: .assumed)
            : nil
        store.applyOpening(
            id: id,
            kind: kind,
            wall: .xMax,
            s0: 0.5,
            s1: kind == .window ? 2.0 : 1.4,
            z0: kind == .window ? 0.9 : 0,
            z1: kind == .window ? 2.2 : 2.1,
            source: .user,
            heatFluxWm2: defaultWindowFlux
        )
        show(.opening(id))
    }

    private func addObstacle(kind: FurnitureKind) {
        let existing = store.project?.geometry?.obstacles.map(\.id) ?? []
        let id = ProjectDraft.nextPrefixedID(prefix: "F", existing: existing)
        let size = kind.defaultSize
        store.applyObstacle(
            id: id,
            origin: Position3D(x: 1, y: 1, z: 0),
            size: size,
            kind: kind
        )
        // A refused default corner (message set) stays on the list page so
        // the reason is visible; the drag plan or numeric editor can place
        // the piece legally.
        show(store.furniturePlacementMessage == nil ? .obstacle(id) : .furniturePlan)
    }

    private func addSeat() {
        let existing = store.project?.occupancy?.seats.map(\.id) ?? []
        let id = ProjectDraft.nextPrefixedID(prefix: "S", existing: existing)
        store.applySeat(
            id: id,
            position: Position3D(x: 1.5, y: 1.5, z: 1.1),
            source: .user
        )
        show(.seat(id))
    }
}

/// Draft numbers and stored quantities can differ by binary noise after formatting.
private func inspectorValuesDiffer(_ draft: Double, _ stored: Double) -> Bool {
    abs(draft - stored) > 0.000_001
}

/// Apply control. A leading dot means the fields above it are edited and not written yet.
private struct ApplyButton: View {
    let title: String
    var isDirty: Bool
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(isDirty ? "• \(title)" : title, action: action)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isDirty ? "有修改还没应用" : "")
    }
}

private struct InspectorRow: View {
    let title: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor : nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("在右侧显示这一项")
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
            ApplyButton(
                title: "应用开口",
                isDirty: isDirty,
                accessibilityLabel: "应用\(displayTitle)，单位米",
                action: apply
            )
            Button("删除开口", role: .destructive, action: onDelete)
                .accessibilityLabel("删除\(displayTitle)")
        }
        .padding(.vertical, 4)
        .onSubmit(apply)
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

    private var isDirty: Bool {
        kind != opening.kind
            || wall != opening.wall
            || source != opening.s0.source
            || inspectorValuesDiffer(s0, opening.s0.value)
            || inspectorValuesDiffer(s1, opening.s1.value)
            || inspectorValuesDiffer(z0, opening.z0.value)
            || inspectorValuesDiffer(z1, opening.z1.value)
    }

    private func apply() {
        onApply(kind, wall, s0, s1, z0, z1, source)
    }
}

private struct ObstacleEditor: View {
    let box: ObstacleBox
    let displayTitle: String
    let issue: FieldIssue?
    let onApply: (FurnitureKind, Position3D, Position3D) -> Void
    let onDelete: () -> Void

    @State private var kind: FurnitureKind
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
        onApply: @escaping (FurnitureKind, Position3D, Position3D) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.box = box
        self.displayTitle = displayTitle
        self.issue = issue
        self.onApply = onApply
        self.onDelete = onDelete
        _kind = State(initialValue: box.kind)
        _originX = State(initialValue: box.origin.x)
        _originY = State(initialValue: box.origin.y)
        _originZ = State(initialValue: box.origin.z)
        _sizeX = State(initialValue: box.size.x)
        _sizeY = State(initialValue: box.size.y)
        _sizeZ = State(initialValue: box.size.z)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("类型", selection: $kind) {
                ForEach(FurnitureKind.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .accessibilityLabel("家具类型")
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
            ApplyButton(
                title: "应用家具",
                isDirty: isDirty,
                accessibilityLabel: "应用\(displayTitle)，单位米",
                action: apply
            )
            Button("删除家具", role: .destructive, action: onDelete)
                .accessibilityLabel("删除\(displayTitle)")
        }
        .padding(.vertical, 4)
        .onSubmit(apply)
        .onChange(of: box) { _, updated in
            kind = updated.kind
            originX = updated.origin.x
            originY = updated.origin.y
            originZ = updated.origin.z
            sizeX = updated.size.x
            sizeY = updated.size.y
            sizeZ = updated.size.z
        }
    }

    private var isDirty: Bool {
        kind != box.kind
            || inspectorValuesDiffer(originX, box.origin.x)
            || inspectorValuesDiffer(originY, box.origin.y)
            || inspectorValuesDiffer(originZ, box.origin.z)
            || inspectorValuesDiffer(sizeX, box.size.x)
            || inspectorValuesDiffer(sizeY, box.size.y)
            || inspectorValuesDiffer(sizeZ, box.size.z)
    }

    private func apply() {
        onApply(
            kind,
            Position3D(x: originX, y: originY, z: originZ),
            Position3D(x: sizeX, y: sizeY, z: sizeZ)
        )
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
            NumericField("左右", value: $x, unit: "m")
            NumericField("前后", value: $y, unit: "m")
            NumericField("坐姿高度", value: $z, unit: "m")
            SourcePicker(source: $source)
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
            ApplyButton(
                title: "应用座位",
                isDirty: isDirty,
                accessibilityLabel: "应用\(displayTitle)，单位米",
                action: apply
            )
            Button("删除座位", role: .destructive, action: onDelete)
                .accessibilityLabel("删除\(displayTitle)")
        }
        .padding(.vertical, 4)
        .onSubmit(apply)
        .onChange(of: seat) { _, updated in
            x = updated.position.x
            y = updated.position.y
            z = updated.position.z
            source = updated.source
        }
    }

    private var isDirty: Bool {
        source != seat.source
            || inspectorValuesDiffer(x, seat.position.x)
            || inspectorValuesDiffer(y, seat.position.y)
            || inspectorValuesDiffer(z, seat.position.z)
    }

    private func apply() {
        onApply(Position3D(x: x, y: y, z: z), source)
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
            ApplyButton(
                title: "应用\(title)",
                isDirty: isDirty,
                accessibilityLabel: "应用\(title)，沿墙位置单位米",
                action: apply
            )
        }
        .padding(.vertical, 4)
        .onSubmit(apply)
        .onChange(of: terminal) { _, updated in
            wall = updated.wall
            s0 = updated.s0.value
            s1 = updated.s1.value
            z0 = updated.z0.value
            z1 = updated.z1.value
            source = updated.s0.source
        }
    }

    private var isDirty: Bool {
        wall != terminal.wall
            || source != terminal.s0.source
            || inspectorValuesDiffer(s0, terminal.s0.value)
            || inspectorValuesDiffer(s1, terminal.s1.value)
            || inspectorValuesDiffer(z0, terminal.z0.value)
            || inspectorValuesDiffer(z1, terminal.z1.value)
    }

    private func apply() {
        onApply(wall, s0, s1, z0, z1, source)
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
            ApplyButton(
                title: "应用出风速度",
                isDirty: inspectorValuesDiffer(speed, hvac.supplySpeedMs.value),
                accessibilityLabel: "应用出风速度，单位米每秒，并按面积重算风量"
            ) {
                onApplySpeed(speed)
            }
            NumericField("出风量", value: $airflow, unit: "m3/s")
            ApplyButton(
                title: "应用出风量",
                isDirty: inspectorValuesDiffer(airflow, hvac.supplyAirflowM3s.value),
                accessibilityLabel: "应用出风量，单位立方米每秒"
            ) {
                onApplyAirflow(airflow)
            }
            Button("按速度×面积重算风量", action: onRecompute)
                .accessibilityLabel("按速度乘面积重算出风量")
            if let airflowIssue {
                Text(airflowIssue.message)
                    .font(.footnote)
                    .accessibilityLabel(airflowIssue.message)
            }
            NumericField("室外新风", value: $outdoorAir, unit: "m3/s")
            ApplyButton(
                title: "应用室外新风",
                isDirty: inspectorValuesDiffer(outdoorAir, hvac.outdoorAirM3s.value),
                accessibilityLabel: "应用室外新风，与回风口分开，单位立方米每秒"
            ) {
                onApplyOutdoorAir(outdoorAir)
            }
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
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: $value, format: InspectorNumberFormat.twoPlaces)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text(unit)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .accessibilityElement(children: .combine)
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
