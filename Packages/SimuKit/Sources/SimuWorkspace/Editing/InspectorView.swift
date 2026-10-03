import SwiftUI
import SimuCore
import SimuDesignSystem

/// Property editor dispatched by the current selection. All edits go through ProjectSession.mutate.
public struct InspectorView: View {
    let session: ProjectSession
    @State private var northExpanded = false
    @State private var weatherExpanded = false

    public init(session: ProjectSession) { self.session = session }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                if let selection = session.selection, session.exists(selection) {
                    switch selection {
                    case .room(let id): roomForm(id)
                    case .opening(let id): openingForm(id)
                    case .obstacle(let id): obstacleForm(id)
                    case .device(let id): deviceForm(id)
                    case .port(let deviceID, let portID): portForm(deviceID: deviceID, portID: portID)
                    case .seat(let id): seatForm(id)
                    case .occupant(let id): occupantForm(id)
                    case .equipment(let id): equipmentForm(id)
                    case .control(let id): controlForm(id)
                    case .environment: environmentForm
                    case .cost: costForm
                    }
                } else {
                    Section {
                        RoomPageIntro("想改哪里？", detail: "点选图中的空调、座位或家具，就能查看设置。")
                        Text("左侧可以选择尺寸与墙面、门窗、人和空调的设定温度；天气与电价也在左侧。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    assumptionsSection
                }
            }
            .formStyle(.grouped)
            .onChange(of: session.focusedSetting) { reveal(session.focusedSetting, with: proxy) }
            .onAppear { reveal(session.focusedSetting, with: proxy) }
        }
    }

    private func reveal(_ anchor: String?, with proxy: ScrollViewProxy) {
        guard let anchor else { return }
        if anchor.contains("northAngle") { northExpanded = true }
        if anchor.contains("/weather") { weatherExpanded = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation { proxy.scrollTo(anchor, anchor: .center) }
        }
    }

    // MARK: - Binding helpers

    private func bind<V>(_ path: WritableKeyPath<ProjectDocument, V>) -> Binding<V> {
        Binding(get: { session.project[keyPath: path] },
                set: { newValue in session.mutate { $0[keyPath: path] = newValue } })
    }

    private var scenarioIndex: Int? {
        session.project.scenarios.firstIndex { $0.id == session.currentScenarioID }
    }

    private func doubleBinding<T>(_ base: Binding<T>, _ path: WritableKeyPath<T, Double>) -> Binding<Double> {
        Binding(get: { base.wrappedValue[keyPath: path] }, set: { base.wrappedValue[keyPath: path] = $0 })
    }

    // MARK: - Room & openings & obstacles

    private func roomForm(_ id: UUID) -> AnyView {
        guard let index = session.project.geometry.rooms.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let room: Binding<Room> = bind(\.geometry.rooms[index])
        return AnyView(Group {
            Section {
                TextField("名称", text: room.name)
                DisclosureGroup(isExpanded: $northExpanded) {
                    ParameterRow("北向角", room.northAngle)
                        .settingAnchor("/geometry/rooms/\(index)/northAngle", focused: session.focusedSetting)
                    Text("从俯视图远侧方向（+Y）顺时针转到真北的角度。").font(.caption).foregroundStyle(.secondary)
                } label: {
                    Text("房间朝向 · 计算前填写")
                }
            } header: { Text("房间") }
            if let payload = try? session.project.geometry.rooms[index].shape.resolved(as: RectangularRoom.self, registry: session.registry) {
                let shape = shapeBinding(roomIndex: index, fallback: payload)
                let shapePath = "/geometry/rooms/\(index)/shape/payload/dimensions"
                Section {
                    ParameterRow("左右宽度", shape.dimensions.width)
                        .settingAnchor(shapePath + "/width", focused: session.focusedSetting)
                    ParameterRow("前后进深", shape.dimensions.depth)
                        .settingAnchor(shapePath + "/depth", focused: session.focusedSetting)
                    ParameterRow("高度", shape.dimensions.height)
                        .settingAnchor(shapePath + "/height", focused: session.focusedSetting)
                } header: { Text("尺寸") }
            }
            envelopeFields(roomID: id)
            ventilationFields(roomID: id)
        })
    }

    private func shapeBinding(roomIndex index: Int, fallback: RectangularRoom) -> Binding<RectangularRoom> {
        Binding(get: {
            (try? session.project.geometry.rooms[index].shape.resolved(as: RectangularRoom.self, registry: session.registry)) ?? fallback
        }, set: { newValue in
            session.mutate { document in
                if let record = try? ExtensionRecord(newValue) {
                    document.geometry.rooms[index].shape = record
                }
            }
        })
    }

    @ViewBuilder
    private func envelopeFields(roomID: UUID) -> some View {
        if let si = scenarioIndex,
           let room = session.project.geometry.rooms.first(where: { $0.id == roomID }) {
            Section("墙面温度与保温") {
                ForEach(Array(session.project.scenarios[si].inputs.envelope.surfaces.enumerated()), id: \.element.surfaceID) { index, condition in
                    let face = room.surfaces.first { $0.id == condition.surfaceID }?.face
                    let title = face.map(InputPresentation.faceTitle) ?? "墙面"
                    let base = "/scenarios/\(si)/inputs/envelope/surfaces/\(index)"
                    Text(title).font(.callout)
                    ParameterRow("传热系数", surfaceUValue(si, index))
                        .settingAnchor(base + "/uValue", focused: session.focusedSetting)
                    switch condition.boundary.mode {
                    case .temperature:
                        ParameterRow("墙面边界温度", surfaceTemperature(si, index))
                            .settingAnchor(base + "/boundary/temperature", focused: session.focusedSetting)
                    case .heatFlux:
                        ParameterRow("墙面热流", surfaceHeatFlux(si, index))
                            .settingAnchor(base + "/boundary/heatFlux", focused: session.focusedSetting)
                    case .fromL1:
                        Text("\(title)的边界要等能耗计算结果，现在不能在这里填写。")
                            .font(.caption).foregroundStyle(.secondary)
                            .settingAnchor(base + "/boundary", focused: session.focusedSetting)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ventilationFields(roomID: UUID) -> some View {
        if let si = scenarioIndex,
           let index = session.project.scenarios[si].inputs.ventilation.firstIndex(where: { $0.roomID == roomID }) {
            let base = "/scenarios/\(si)/inputs/ventilation/\(index)"
            Section("通风") {
                ParameterRow("新风量", ventilationFlow(si, index, \.outdoorAir))
                    .settingAnchor(base + "/outdoorAir", focused: session.focusedSetting)
                ParameterRow("排风量", ventilationFlow(si, index, \.exhaustAir))
                    .settingAnchor(base + "/exhaustAir", focused: session.focusedSetting)
                ParameterRow("渗入风量", ventilationFlow(si, index, \.infiltration))
                    .settingAnchor(base + "/infiltration", focused: session.focusedSetting)
                ParameterRow("渗出风量", ventilationFlow(si, index, \.exfiltration))
                    .settingAnchor(base + "/exfiltration", focused: session.focusedSetting)
            }
        }
    }

    @ViewBuilder
    private func windowFields(openingID: UUID) -> some View {
        if let si = scenarioIndex,
           let index = session.project.scenarios[si].inputs.envelope.windows.firstIndex(where: { $0.openingID == openingID }) {
            let base = "/scenarios/\(si)/inputs/envelope/windows/\(index)"
            Section("窗户热工") {
                ParameterRow("传热系数", windowValue(si, index, \.uValue))
                    .settingAnchor(base + "/uValue", focused: session.focusedSetting)
                ParameterRow("太阳得热系数", windowValue(si, index, \.shgc))
                    .settingAnchor(base + "/shgc", focused: session.focusedSetting)
                ParameterRow("遮阳系数", windowValue(si, index, \.shadingFactor))
                    .settingAnchor(base + "/shadingFactor", focused: session.focusedSetting)
            }
        }
    }

    @ViewBuilder
    private func openingStateFields(openingID: UUID) -> some View {
        if let si = scenarioIndex {
            ForEach(Array(session.project.scenarios[si].inputs.ventilation.enumerated()), id: \.offset) { ventIndex, ventilation in
                if let stateIndex = ventilation.openings.firstIndex(where: { $0.openingID == openingID }) {
                    ParameterRow("打开比例", openingFraction(si, ventIndex, stateIndex))
                        .settingAnchor("/scenarios/\(si)/inputs/ventilation/\(ventIndex)/openings/\(stateIndex)/openFraction",
                                       focused: session.focusedSetting)
                }
            }
        }
    }

    private func surfaceUValue(_ si: Int, _ index: Int) -> Binding<UValue> {
        Binding(get: { session.project.scenarios[si].inputs.envelope.surfaces[index].uValue },
                set: { newValue in session.mutate { $0.scenarios[si].inputs.envelope.surfaces[index].uValue = newValue } })
    }

    private func surfaceTemperature(_ si: Int, _ index: Int) -> Binding<Temperature> {
        Binding(get: {
            session.project.scenarios[si].inputs.envelope.surfaces[index].boundary.temperature ?? .unknown(reason: "待填写")
        }, set: { newValue in
            session.mutate { $0.scenarios[si].inputs.envelope.surfaces[index].boundary.temperature = newValue }
        })
    }

    private func surfaceHeatFlux(_ si: Int, _ index: Int) -> Binding<HeatFlux> {
        Binding(get: {
            session.project.scenarios[si].inputs.envelope.surfaces[index].boundary.heatFlux ?? .unknown(reason: "待填写")
        }, set: { newValue in
            session.mutate { $0.scenarios[si].inputs.envelope.surfaces[index].boundary.heatFlux = newValue }
        })
    }

    private func ventilationFlow(_ si: Int, _ index: Int, _ key: WritableKeyPath<RoomVentilation, VolumeFlow>) -> Binding<VolumeFlow> {
        Binding(get: { session.project.scenarios[si].inputs.ventilation[index][keyPath: key] },
                set: { newValue in session.mutate { $0.scenarios[si].inputs.ventilation[index][keyPath: key] = newValue } })
    }

    private func windowValue<Q: QuantityTag>(_ si: Int, _ index: Int, _ key: WritableKeyPath<WindowCondition, PhysicalParameter<Q>>) -> Binding<PhysicalParameter<Q>> {
        Binding(get: { session.project.scenarios[si].inputs.envelope.windows[index][keyPath: key] },
                set: { newValue in session.mutate { $0.scenarios[si].inputs.envelope.windows[index][keyPath: key] = newValue } })
    }

    private func openingFraction(_ si: Int, _ ventIndex: Int, _ stateIndex: Int) -> Binding<Ratio> {
        Binding(get: { session.project.scenarios[si].inputs.ventilation[ventIndex].openings[stateIndex].openFraction },
                set: { newValue in
            session.mutate { $0.scenarios[si].inputs.ventilation[ventIndex].openings[stateIndex].openFraction = newValue }
        })
    }

    private func openingForm(_ id: UUID) -> AnyView {
        for (ri, room) in session.project.geometry.rooms.enumerated() {
            guard let oi = room.openings.firstIndex(where: { $0.id == id }) else { continue }
            let opening = bind(\.geometry.rooms[ri].openings[oi])
            return AnyView(Group {
                Section("门窗") {
                    Picker("类型", selection: opening.kind) {
                        Text("窗").tag(OpeningKind.window)
                        Text("门").tag(OpeningKind.door)
                    }
                    let openingPath = "/geometry/rooms/\(ri)/openings/\(oi)"
                    ParameterRow("沿墙位置", opening.offsetU).settingAnchor(openingPath + "/offsetU", focused: session.focusedSetting)
                    ParameterRow("离地高度", opening.offsetV).settingAnchor(openingPath + "/offsetV", focused: session.focusedSetting)
                    ParameterRow("宽", opening.width).settingAnchor(openingPath + "/width", focused: session.focusedSetting)
                    ParameterRow("高", opening.height).settingAnchor(openingPath + "/height", focused: session.focusedSetting)
                }
                windowFields(openingID: id)
                openingStateFields(openingID: id)
                Button(role: .destructive, action: { deleteOpening(roomIndex: ri, openingIndex: oi) }) {
                    Label("删除这扇门或窗", systemImage: "trash")
                }
            })
        }
        return AnyView(EmptyView())
    }

    private func deleteOpening(roomIndex ri: Int, openingIndex oi: Int) {
        let openingID = session.project.geometry.rooms[ri].openings[oi].id
        session.mutate { document in
            document.geometry.rooms[ri].openings.remove(at: oi)
            for s in document.scenarios.indices {
                document.scenarios[s].inputs.envelope.windows.removeAll { $0.openingID == openingID }
                for v in document.scenarios[s].inputs.ventilation.indices {
                    document.scenarios[s].inputs.ventilation[v].openings.removeAll { $0.openingID == openingID }
                }
            }
        }
        session.selection = nil
    }

    private func obstacleForm(_ id: UUID) -> AnyView {
        guard let oi = session.project.geometry.obstacles.firstIndex(where: { $0.id == id }),
              let box = try? session.project.geometry.obstacles[oi].shape.resolved(as: BoxObstacle.self, registry: session.registry) else {
            return AnyView(Text("不支持的几何类型，仅保留数据。").foregroundStyle(.secondary))
        }
        let shape = Binding<BoxObstacle>(get: {
            (try? session.project.geometry.obstacles[oi].shape.resolved(as: BoxObstacle.self, registry: session.registry)) ?? box
        }, set: { newValue in
            session.mutate { document in
                if let record = try? ExtensionRecord(newValue) {
                    document.geometry.obstacles[oi].shape = record
                }
            }
        })
        let obstacle = bind(\.geometry.obstacles[oi])
        return AnyView(Group {
            Section("家具") {
                TextField("名称", text: obstacle.name)
                UnitNumberRow("距左墙", unit: "m", value: doubleBinding(shape, \.origin.x))
                UnitNumberRow("距近侧墙", unit: "m", value: doubleBinding(shape, \.origin.y))
            }
            Section("尺寸") {
                ParameterRow("左右宽度", shape.dimensions.width)
                ParameterRow("前后进深", shape.dimensions.depth)
                ParameterRow("高度", shape.dimensions.height)
            }
            Button(role: .destructive, action: {
                session.mutate { $0.geometry.obstacles.remove(at: oi) }
                session.selection = nil
            }, label: { Label("删除家具", systemImage: "trash") })
        })
    }

    // MARK: - HVAC

    private func deviceForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let di = session.project.scenarios[si].inputs.hvac.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let device = bind(\.scenarios[si].inputs.hvac[di])
        return AnyView(Group {
            Section("空调") {
                TextField("名称", text: device.name)
                ParameterRow("出风温度", device.supplyTemperature)
                    .settingAnchor("/scenarios/\(si)/inputs/hvac/\(di)/supplyTemperature", focused: session.focusedSetting)
                Text("这是吹出来的空气温度，不是遥控器的设定温度。").font(.caption).foregroundStyle(.secondary)
            }
            if let split = try? session.project.scenarios[si].inputs.hvac[di].definition.resolved(as: SingleSplit.self, registry: session.registry) {
                let definition = Binding<SingleSplit>(get: {
                    (try? session.project.scenarios[si].inputs.hvac[di].definition.resolved(as: SingleSplit.self, registry: session.registry)) ?? split
                }, set: { newValue in
                    session.mutate { document in
                        if let record = try? ExtensionRecord(newValue) {
                            document.scenarios[si].inputs.hvac[di].definition = record
                        }
                    }
                })
                Section("设备性能") {
                    let base = "/scenarios/\(si)/inputs/hvac/\(di)/definition/payload"
                    ParameterRow("制冷能力", definition.coolingCapacity)
                        .settingAnchor(base + "/coolingCapacity", focused: session.focusedSetting)
                    ParameterRow("额定用电功率", definition.electricalPower)
                        .settingAnchor(base + "/electricalPower", focused: session.focusedSetting)
                    ParameterRow("能效比 COP", definition.cop)
                        .settingAnchor(base + "/cop", focused: session.focusedSetting)
                    Text("这些数值可从空调铭牌或说明书查到；制冷能力和用电功率不同。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("设备性能") { Text("未知设备类型，仅保留数据；安装对应支持后可编辑。").foregroundStyle(.secondary) }
            }
            Section("出风与回风 · 详细设置") {
                ForEach(session.project.scenarios[si].inputs.hvac[di].ports, id: \.id) { port in
                    Button("\(port.role == .supply ? "送风" : "回风")口") {
                        session.selection = .port(deviceID: id, portID: port.id)
                    }
                }
            }
        })
    }

    private func portForm(deviceID: UUID, portID: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let di = session.project.scenarios[si].inputs.hvac.firstIndex(where: { $0.id == deviceID }),
              let pi = session.project.scenarios[si].inputs.hvac[di].ports.firstIndex(where: { $0.id == portID }) else { return AnyView(EmptyView()) }
        let port = bind(\.scenarios[si].inputs.hvac[di].ports[pi])
        return AnyView(Group {
            Section("风量设置") {
                ParameterRow("面积", port.area)
                ParameterRow("风量", port.volumeFlow)
                ParameterRow("风速", port.speed)
                DisclosureGroup("空气参数") { ParameterRow("空气密度", port.density) }
                Text("面积 × 风速 = 风量；不一致会在校验中提示。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("出风方向 · 专业设置") {
                    UnitNumberRow("左右方向 X", unit: "", value: doubleBinding(port, \.direction.x))
                    UnitNumberRow("前后方向 Y", unit: "", value: doubleBinding(port, \.direction.y))
                    UnitNumberRow("上下方向 Z", unit: "", value: doubleBinding(port, \.direction.z))
                    Text("这里使用单位向量，三个分量的平方和需为 1。").font(.caption).foregroundStyle(.secondary)
                }
            }
        })
    }

    // MARK: - Usage

    private func seatForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let i = session.project.scenarios[si].inputs.usage.seats.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let seat = bind(\.scenarios[si].inputs.usage.seats[i])
        let sampleCount = session.project.scenarios[si].inputs.usage.seats[i].samples.count
        return AnyView(Group {
            Section("座位") {
                TextField("名称", text: seat.name)
                UnitNumberRow("距左墙", unit: "m", value: doubleBinding(seat, \.position.x))
                UnitNumberRow("距近侧墙", unit: "m", value: doubleBinding(seat, \.position.y))
            }
            Section {
                DisclosureGroup("座位检查高度 · \(sampleCount) 个点") {
                ForEach(0..<sampleCount, id: \.self) { sampleIndex in
                    HStack {
                        Text("离地高度")
                        TextField("高度", value: seat.samples[sampleIndex].position.z, format: .number)
                            .labelsHidden()
                            .accessibilityLabel("检查点离地高度，单位米")
                            .frame(maxWidth: 80)
                        Text("m").foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive, action: {
                            session.mutate { $0.scenarios[si].inputs.usage.seats[i].samples.remove(at: sampleIndex) }
                        }, label: { Image(systemName: "minus.circle") }).buttonStyle(.borderless)
                    }
                }
                Button("添加检查高度") {
                    session.mutate { document in
                        let value = document.scenarios[si].inputs.usage.seats[i]
                        let z = (value.samples.map(\.position.z).max() ?? 0) + 0.5
                        document.scenarios[si].inputs.usage.seats[i].samples.append(
                            SamplePoint(id: UUID(), position: Position3D(x: value.position.x, y: value.position.y, z: z)))
                    }
                }
                Text("用于之后检查脚踝、身体和头部位置；当前估算不提供逐点舒适结果。")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(role: .destructive, action: { deleteSeat(seatIndex: i) }, label: { Label("删除座位", systemImage: "trash") })
        })
    }

    private func deleteSeat(seatIndex i: Int) {
        guard let si = scenarioIndex else { return }
        let seatID = session.project.scenarios[si].inputs.usage.seats[i].id
        session.mutate { document in
            document.scenarios[si].inputs.usage.seats.remove(at: i)
            document.scenarios[si].inputs.usage.occupants.removeAll { $0.seatID == seatID }
        }
        session.selection = nil
    }

    private func occupantForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let i = session.project.scenarios[si].inputs.usage.occupants.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let occupant = bind(\.scenarios[si].inputs.usage.occupants[i])
        return AnyView(Group {
            Section("人员") {
                ParameterRow("活动强度", occupant.activity)
                ParameterRow("衣着厚度", occupant.clothing)
                DisclosureGroup("身体散热 · 专业设置") {
                    ParameterRow("散热量", occupant.heat.sensible)
                    ParameterRow("传给空气的比例", occupant.heat.convectiveFraction)
                    ParameterRow("水汽带来的热量", occupant.heat.latent)
                }
            }
            ScheduleEditor(schedule: occupant.schedule)
        })
    }

    private func equipmentForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let i = session.project.scenarios[si].inputs.usage.equipment.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let equipment = bind(\.scenarios[si].inputs.usage.equipment[i])
        return AnyView(Group {
            Section("电器散热") {
                ParameterRow("散热量", equipment.heat.sensible)
                DisclosureGroup("散热方式 · 专业设置") {
                    ParameterRow("传给空气的比例", equipment.heat.convectiveFraction)
                    ParameterRow("水汽带来的热量", equipment.heat.latent)
                }
            }
            ScheduleEditor(schedule: equipment.schedule)
            Button(role: .destructive, action: {
                session.mutate { $0.scenarios[si].inputs.usage.equipment.remove(at: i) }
                session.selection = nil
            }, label: { Label("删除电器", systemImage: "trash") })
        })
    }

    // MARK: - Controls / environment / cost

    private func controlForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let i = session.project.scenarios[si].inputs.controls.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let control = bind(\.scenarios[si].inputs.controls[i])
        return AnyView(Group {
            Section("遥控器温度") {
                ParameterRow("设定温度", control.setpoint)
                    .settingAnchor("/scenarios/\(si)/inputs/controls/\(i)/setpoint", focused: session.focusedSetting)
                Text("这里填写遥控器上的温度。").font(.caption).foregroundStyle(.secondary)
            }
            ScheduleEditor(schedule: control.schedule)
        })
    }

    private var environmentForm: AnyView {
        guard let si = scenarioIndex else { return AnyView(EmptyView()) }
        let environment = bind(\.scenarios[si].inputs.environment)
        return AnyView(Group {
            Section("环境") {
                let base = "/scenarios/\(si)/inputs/environment"
                ParameterRow("室外温度", environment.outdoorTemperature)
                    .settingAnchor(base + "/outdoorTemperature", focused: session.focusedSetting)
                ParameterRow("室外湿度", environment.outdoorHumidity)
                    .settingAnchor(base + "/outdoorHumidity", focused: session.focusedSetting)
                ParameterRow("室内湿度", environment.indoorHumidity)
                    .settingAnchor(base + "/indoorHumidity", focused: session.focusedSetting)
            }
            Section("选一天来估算") {
                let base = "/scenarios/\(si)/inputs/environment"
                TextField("日期 YYYY-MM-DD", text: optionalString(environment.representativeDate))
                    .settingAnchor(base + "/representativeDate", focused: session.focusedSetting)
                TextField("时区，如 Asia/Hong_Kong", text: optionalString(environment.timeZone))
                    .settingAnchor(base + "/timeZone", focused: session.focusedSetting)
            }
            Section {
                let base = "/scenarios/\(si)/inputs/environment"
                DisclosureGroup(isExpanded: $weatherExpanded) {
                    TextField("项目内的文件位置", text: weatherPath(environment))
                        .settingAnchor(base + "/weather/relativePath", focused: session.focusedSetting)
                    TextField("文件校验码 SHA-256", text: weatherHash(environment))
                        .settingAnchor(base + "/weather/sha256", focused: session.focusedSetting)
                    Text("当前只记录文件引用；需由熟悉项目文件的人配置。").font(.caption).foregroundStyle(.secondary)
                } label: {
                    Text("天气文件 · 计算前配置")
                }
                .settingAnchor(base + "/weather", focused: session.focusedSetting)
            }
        })
    }

    private func optionalString(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func weatherPath(_ environment: Binding<SimuCore.Environment>) -> Binding<String> {
        Binding(get: { environment.wrappedValue.weather?.relativePath ?? "" }, set: { newValue in
            let hash = environment.wrappedValue.weather?.sha256 ?? ""
            environment.wrappedValue.weather = newValue.isEmpty ? nil : WeatherReference(relativePath: newValue, sha256: hash)
        })
    }

    private func weatherHash(_ environment: Binding<SimuCore.Environment>) -> Binding<String> {
        Binding(get: { environment.wrappedValue.weather?.sha256 ?? "" }, set: { newValue in
            guard let path = environment.wrappedValue.weather?.relativePath else { return }
            environment.wrappedValue.weather = WeatherReference(relativePath: path, sha256: newValue)
        })
    }

    private var costForm: AnyView {
        guard let si = scenarioIndex else { return AnyView(EmptyView()) }
        let cost = bind(\.scenarios[si].evaluation.cost)
        return AnyView(Section("费用") {
            TextField("币种，如 HKD", text: optionalString(cost.currency))
                .settingAnchor("/scenarios/\(si)/evaluation/cost/currency", focused: session.focusedSetting)
            Text("电价和报价由项目文件提供；这里只设置币种。未提供价格时无法估算费用。").font(.caption).foregroundStyle(.secondary)
        })
    }

    // MARK: - Assumptions

    private var assumptionsSection: some View {
        Section("参数说明") {
            let items = AssumptionCollector.items(in: session.project)
            if items.isEmpty {
                Text("没有待补充或假设参数。").foregroundStyle(.secondary)
            } else {
                DisclosureGroup("查看来源与假设 · \(items.count) 项") {
                    ForEach(items, id: \.self) { item in
                        let path = String(item.split(separator: "：", maxSplits: 1).first ?? "")
                        DisclosureGroup(InputPresentation.fieldTitle(path)) {
                            Text(item).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                Text("模板只是起点，实际数值请核实。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func settingAnchor(_ anchor: String, focused: String?) -> some View {
        if focused == anchor {
            self.id(anchor).listRowBackground(Color.accentColor.opacity(0.16))
        } else {
            self.id(anchor)
        }
    }
}

/// Representative-day schedule editor: contiguous intervals in minutes, fractions are parameters.
public struct ScheduleEditor: View {
    @Binding var schedule: DailySchedule

    public init(schedule: Binding<DailySchedule>) { self._schedule = schedule }

    public var body: some View {
        Section("每天什么时候使用") {
            ForEach(0..<schedule.intervals.count, id: \.self) { index in
                DisclosureGroup("\(clock(schedule.intervals[index].startMinute)) – \(clock(schedule.intervals[index].endMinute)) · \(usageTitle(schedule.intervals[index].fraction.value))") {
                    LabeledContent("开始（从午夜起的分钟数）") {
                        TextField("开始", value: $schedule.intervals[index].startMinute, format: .number)
                            .labelsHidden().accessibilityLabel("开始，从午夜起的分钟数").frame(maxWidth: 70)
                    }
                    LabeledContent("结束（从午夜起的分钟数）") {
                        TextField("结束", value: $schedule.intervals[index].endMinute, format: .number)
                            .labelsHidden().accessibilityLabel("结束，从午夜起的分钟数").frame(maxWidth: 70)
                    }
                    ParameterRow("使用比例（0–1）", $schedule.intervals[index].fraction)
                    Text("0 表示停用，1 表示全部使用；480 分钟是 08:00。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("添加时段") {
                let last = schedule.intervals.last?.endMinute ?? 0
                guard last < 1440 else { return }
                schedule.intervals.append(ScheduleInterval(
                    startMinute: last, endMinute: 1440,
                    fraction: .known(value: 0, source: .init(kind: .assumed, note: "Added interval; adjust fraction"))))
            }
            Text("各时段需覆盖全天；不用的时段将比例设为 0。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func usageTitle(_ fraction: Double?) -> String {
        guard let fraction else { return "使用比例待填" }
        if fraction == 0 { return "停用" }
        if fraction == 1 { return "全部使用" }
        return "使用 \((fraction * 100).formatted())%"
    }
}
