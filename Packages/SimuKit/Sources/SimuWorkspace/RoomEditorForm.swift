import SwiftUI
import SimuCore

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
                    Text("模板会填入几何、人员与空调；围护与天气仍标为 omitted，不会当作 0。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("可覆盖项") {
                if store.overridable.isEmpty {
                    Text("从模板创建后，这里列出应改的设定温度、风口与人数。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.overridable, id: \.self) { path in
                        Text(path)
                            .accessibilityLabel("可覆盖 \(path)")
                    }
                }
            }
            Section("锁定假设") {
                if store.lockedAssumptions.isEmpty {
                    Text("模板未建模的围护与天气会标为 omitted，不填 0。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.lockedAssumptions, id: \.self) { note in
                        Text(note)
                            .accessibilityLabel("锁定假设 \(note)")
                    }
                }
            }
            Section("房间尺寸") {
                sizeField("长度", value: $sizeX, pathHint: "geometry.sizeX")
                sizeField("宽度", value: $sizeY, pathHint: "geometry.sizeY")
                sizeField("高度", value: $sizeZ, pathHint: "geometry.sizeZ")
                Button("应用尺寸") {
                    store.applyRoomSize(x: sizeX, y: sizeY, z: sizeZ)
                    refreshFromStore()
                }
                .accessibilityLabel("应用房间尺寸，单位米")
            }
            Section("朝向") {
                Text("0° 表示计算坐标 +Y 为北。修改角度不会旋转已有门窗 s0/s1。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("北向角", value: $northYaw, format: .number)
                    .accessibilityLabel("北向角，度，零表示正 Y 为北")
                Button("应用朝向") {
                    store.applyNorthYawDegrees(northYaw)
                }
            }
            Section("门窗") {
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再添加开口。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.project?.geometry?.openings ?? []) { opening in
                        OpeningEditor(
                            opening: opening,
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
                    .accessibilityLabel("添加窗，沿墙 s0 到 s1，单位米")
                    Button("添加门") {
                        addOpening(kind: .door)
                    }
                    .accessibilityLabel("添加门，沿墙 s0 到 s1，单位米")
                }
            }
            Section("家具") {
                if store.project?.geometry == nil {
                    Text("先填写房间尺寸后再添加家具。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.project?.geometry?.obstacles ?? []) { box in
                        ObstacleEditor(
                            box: box,
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
                    .accessibilityLabel("添加家具盒体，原点与尺寸单位米")
                }
            }
            Section("代表日人员") {
                Text("人数是热源计数，不是座位数。时段是代表日时钟窗，不是全年。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("人数", value: $occupantCount, format: .number)
                    .accessibilityLabel("代表日人数")
                Button("应用人数") {
                    store.applyOccupantCount(occupantCount)
                }
                .accessibilityLabel("应用代表日人数")
                TextField("开始 HH:MM", text: $occupiedStart)
                    .accessibilityLabel("占用开始时间")
                TextField("结束 HH:MM", text: $occupiedEnd)
                    .accessibilityLabel("占用结束时间")
                Button("应用占用时段") {
                    store.applyOccupiedHours(start: occupiedStart, end: occupiedEnd)
                }
                .accessibilityLabel("应用代表日占用时段")
            }
            Section("计算引擎") {
                Text(store.engineStatus)
                    .font(.footnote)
                    .accessibilityLabel(store.engineStatus)
                #if os(macOS)
                Text("worker 从 App 复制到容器。只需选择引擎目录（含 EnergyPlus 与 openfoam.sh），不要把路径写进项目。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("选择引擎目录") {
                    store.chooseEnginesRoot()
                }
                .accessibilityLabel("选择 EnergyPlus 与 openfoam.sh 引擎目录")
                Button("选择工作副本（备用）") {
                    store.chooseRepositoryRoot()
                }
                .accessibilityLabel("选择含 worker 的工作副本，仅当 App 资源缺失时")
                #else
                Text("iOS 本阶段不运行本地 EnergyPlus 或 OpenFOAM。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
                Button("提交代表日 L1") {
                    Task { await store.submitL1() }
                }
                .disabled(!store.canSubmitL1)
                .accessibilityLabel("提交代表日 L1")
                #if os(macOS)
                Button("提交代表工况 L2") {
                    Task { await store.submitL2() }
                }
                .disabled(!store.canSubmitL2)
                .accessibilityLabel("提交代表工况 L2，稳态气流场，不是全年 8760 小时")
                #endif
                Button("取消任务") {
                    Task { await store.cancelActiveRun() }
                }
                .disabled(store.activeRun == nil || !store.isSubmitting)
                .accessibilityLabel("取消当前任务")
                if let message = store.runMessage {
                    Text(message)
                        .font(.footnote)
                        .accessibilityLabel(message)
                }
            }
            Section("座位") {
                ForEach(store.project?.occupancy?.seats ?? []) { seat in
                    SeatEditor(
                        seat: seat,
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
                .accessibilityLabel("添加座位采样点，坐标单位米")
            }
            Section("空调") {
                Button("安装默认分体空调") {
                    store.installDefaultSplitAC()
                }
                .accessibilityLabel("安装默认分体空调，设定与送风温度分开")
                if let hvac = store.project?.hvac {
                    Text("设定 \(hvac.setpointC.value) °C，送风 \(hvac.supplyTemperatureC.value) °C。口 ID 不随编辑改变。")
                        .font(.footnote)
                    TerminalEditor(
                        title: "送风口",
                        terminal: hvac.supply,
                        issue: store.fieldIssues.first(where: { $0.path == "hvac.supply" }),
                        onApply: { wall, s0, s1, z0, z1, source in
                            store.applySupplyTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
                        }
                    )
                    TerminalEditor(
                        title: "回风口",
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
                }
                ForEach(store.fieldIssues.filter { $0.path.hasPrefix("hvac") }) { issue in
                    Text(issue.message)
                        .font(.footnote)
                        .accessibilityLabel(issue.message)
                }
            }
            Section("假设与来源") {
                if listed.isEmpty {
                    Text("尚无假设。未知出处不会显示为 0。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(listed) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.path)
                            Text(item.provenanceText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let uncertainty = item.uncertainty, let unit = item.unit {
                                Text("不确定度 \(uncertainty) \(unit)")
                                    .font(.footnote)
                                    .accessibilityLabel("不确定度 \(uncertainty) \(unit)")
                            }
                        }
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

    private var statusText: String {
        if store.project == nil {
            return "尚未载入"
        }
        if store.isPhysicalModelComplete {
            #if os(macOS)
            if store.l2Client.isConfigured {
                return "物理分区齐全，可提交代表日 L1 与代表工况 L2"
            }
            #endif
            return store.l1Client.isConfigured ? "物理分区齐全，可提交代表日 L1" : "物理分区齐全（引擎未配置）"
        }
        return "模型不完整"
    }

    private var listed: [ListedAssumption] {
        store.project?.listedAssumptions() ?? []
    }

    @ViewBuilder
    private func sizeField(_ title: String, value: Binding<Double>, pathHint: String) -> some View {
        VStack(alignment: .leading) {
            TextField("\(title) m", value: value, format: .number)
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
        issue: FieldIssue?,
        onApply: @escaping (OpeningKind, WallFace, Double, Double, Double, Double, ParameterSource) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.opening = opening
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
            Text("\(opening.kind.editorLabel) \(opening.id)")
            Picker("类型", selection: $kind) {
                ForEach(OpeningKind.allCases, id: \.self) { item in
                    Text(item.editorLabel).tag(item)
                }
            }
            .accessibilityLabel("开口类型")
            WallPicker(wall: $wall)
            SourcePicker(source: $source)
            NumericField("s0", value: $s0, unit: "m")
            NumericField("s1", value: $s1, unit: "m")
            NumericField("z0", value: $z0, unit: "m")
            NumericField("z1", value: $z1, unit: "m")
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel("开口错误 \(issue.message)")
            }
            Button("应用开口") {
                onApply(kind, wall, s0, s1, z0, z1, source)
            }
            .accessibilityLabel("应用开口 \(opening.id)，单位米")
            Button("删除开口", role: .destructive, action: onDelete)
                .accessibilityLabel("删除开口 \(opening.id)")
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
        issue: FieldIssue?,
        onApply: @escaping (Position3D, Position3D) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.box = box
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
            Text("家具 \(box.id)")
            NumericField("原点 x", value: $originX, unit: "m")
            NumericField("原点 y", value: $originY, unit: "m")
            NumericField("原点 z", value: $originZ, unit: "m")
            NumericField("尺寸 x", value: $sizeX, unit: "m")
            NumericField("尺寸 y", value: $sizeY, unit: "m")
            NumericField("尺寸 z", value: $sizeZ, unit: "m")
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
            .accessibilityLabel("应用家具 \(box.id)，单位米")
            Button("删除家具", role: .destructive, action: onDelete)
                .accessibilityLabel("删除家具 \(box.id)")
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
    let issue: FieldIssue?
    let onApply: (Position3D, ParameterSource) -> Void
    let onDelete: () -> Void

    @State private var x: Double
    @State private var y: Double
    @State private var z: Double
    @State private var source: ParameterSource

    init(
        seat: Seat,
        issue: FieldIssue?,
        onApply: @escaping (Position3D, ParameterSource) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.seat = seat
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
            Text("座位 \(seat.id)")
            NumericField("x", value: $x, unit: "m")
            NumericField("y", value: $y, unit: "m")
            NumericField("z", value: $z, unit: "m")
            SourcePicker(source: $source)
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
            Button("应用座位") {
                onApply(Position3D(x: x, y: y, z: z), source)
            }
            .accessibilityLabel("应用座位 \(seat.id)，单位米")
            Button("删除座位", role: .destructive, action: onDelete)
                .accessibilityLabel("删除座位 \(seat.id)")
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
            Text("\(title) \(terminal.id)")
            WallPicker(wall: $wall)
            SourcePicker(source: $source)
            NumericField("s0", value: $s0, unit: "m")
            NumericField("s1", value: $s1, unit: "m")
            NumericField("z0", value: $z0, unit: "m")
            NumericField("z1", value: $z1, unit: "m")
            if let issue {
                Text(issue.message)
                    .font(.footnote)
                    .accessibilityLabel(issue.message)
            }
            Button("应用\(title)") {
                onApply(wall, s0, s1, z0, z1, source)
            }
            .accessibilityLabel("应用\(title) \(terminal.id)，沿墙 s0 到 s1，单位米")
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
            LabeledContent("送风面积", value: String(format: "%.4f m²", hvac.supply.patchAreaM2))
                .accessibilityLabel("送风面积 \(hvac.supply.patchAreaM2) 平方米")
            NumericField("送风速度", value: $speed, unit: "m/s")
            Button("应用送风速度") {
                onApplySpeed(speed)
            }
            .accessibilityLabel("应用送风速度，单位米每秒，并按面积重算风量")
            NumericField("送风量", value: $airflow, unit: "m3/s")
            Button("应用送风量") {
                onApplyAirflow(airflow)
            }
            .accessibilityLabel("应用送风量，单位立方米每秒")
            Button("按速度×面积重算风量", action: onRecompute)
                .accessibilityLabel("按速度乘面积重算送风量")
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
        TextField("\(title) \(unit)", value: $value, format: .number)
            .accessibilityLabel("\(title)，\(unit)")
    }
}

private struct WallPicker: View {
    @Binding var wall: WallFace

    var body: some View {
        Picker("墙面", selection: $wall) {
            ForEach(WallFace.allCases, id: \.self) { face in
                Text(face.rawValue).tag(face)
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
                Text(item.editorLabel).tag(item)
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

private extension ParameterSource {
    var editorLabel: String {
        switch self {
        case .scan: "扫描"
        case .measured: "实测"
        case .manufacturer: "厂家"
        case .user: "用户输入"
        case .preset: "预设"
        case .assumed: "假设"
        }
    }
}
