import SwiftUI
import SimuCore

/// Property editor dispatched by the current selection. All edits go through ProjectSession.mutate.
public struct InspectorView: View {
    let session: ProjectSession

    public init(session: ProjectSession) { self.session = session }

    public var body: some View {
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
                Text("在俯视图或侧边栏选择对象后编辑参数。")
                    .foregroundStyle(.secondary)
                assumptionsSection
            }
        }
        .formStyle(.grouped)
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
                ParameterRow("北向角", room.northAngle)
            } header: { Text("房间") }
            if let payload = try? session.project.geometry.rooms[index].shape.resolved(as: RectangularRoom.self, registry: session.registry) {
                let shape = shapeBinding(roomIndex: index, fallback: payload)
                Section {
                    ParameterRow("宽（X）", shape.dimensions.width)
                    ParameterRow("深（Y）", shape.dimensions.depth)
                    ParameterRow("高（Z）", shape.dimensions.height)
                } header: { Text("尺寸") }
            }
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

    private func openingForm(_ id: UUID) -> AnyView {
        for (ri, room) in session.project.geometry.rooms.enumerated() {
            guard let oi = room.openings.firstIndex(where: { $0.id == id }) else { continue }
            let opening = bind(\.geometry.rooms[ri].openings[oi])
            return AnyView(Group {
                Section("开口") {
                    Picker("类型", selection: opening.kind) {
                        Text("窗").tag(OpeningKind.window)
                        Text("门").tag(OpeningKind.door)
                    }
                    ParameterRow("U 偏移", opening.offsetU)
                    ParameterRow("V 偏移", opening.offsetV)
                    ParameterRow("宽", opening.width)
                    ParameterRow("高", opening.height)
                }
                Button(role: .destructive, action: { deleteOpening(roomIndex: ri, openingIndex: oi) }) {
                    Label("删除开口", systemImage: "trash")
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
                UnitNumberRow("X", unit: "m", value: doubleBinding(shape, \.origin.x))
                UnitNumberRow("Y", unit: "m", value: doubleBinding(shape, \.origin.y))
            }
            Section("尺寸") {
                ParameterRow("宽（X）", shape.dimensions.width)
                ParameterRow("深（Y）", shape.dimensions.depth)
                ParameterRow("高（Z）", shape.dimensions.height)
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
                ParameterRow("送风温度", device.supplyTemperature)
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
                    ParameterRow("制冷量", definition.coolingCapacity)
                    ParameterRow("电功率", definition.electricalPower)
                    ParameterRow("COP", definition.cop)
                }
            } else {
                Section("设备性能") { Text("未知设备类型，仅保留数据；安装对应支持后可编辑。").foregroundStyle(.secondary) }
            }
            Section("风口") {
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
            Section("风口") {
                ParameterRow("面积", port.area)
                ParameterRow("风量", port.volumeFlow)
                ParameterRow("风速", port.speed)
                ParameterRow("密度", port.density)
                Text("面积 × 风速 = 风量；不一致会在校验中提示。").font(.caption).foregroundStyle(.secondary)
            }
            Section("方向（单位向量）") {
                UnitNumberRow("X", unit: "", value: doubleBinding(port, \.direction.x))
                UnitNumberRow("Y", unit: "", value: doubleBinding(port, \.direction.y))
                UnitNumberRow("Z", unit: "", value: doubleBinding(port, \.direction.z))
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
                UnitNumberRow("X", unit: "m", value: doubleBinding(seat, \.position.x))
                UnitNumberRow("Y", unit: "m", value: doubleBinding(seat, \.position.y))
            }
            Section("采样点（\(sampleCount)）") {
                ForEach(0..<sampleCount, id: \.self) { sampleIndex in
                    HStack {
                        Text("高度 z")
                        TextField("高度", value: seat.samples[sampleIndex].position.z, format: .number)
                            .frame(maxWidth: 80)
                        Text("m").foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive, action: {
                            session.mutate { $0.scenarios[si].inputs.usage.seats[i].samples.remove(at: sampleIndex) }
                        }, label: { Image(systemName: "minus.circle") }).buttonStyle(.borderless)
                    }
                }
                Button("添加采样点") {
                    session.mutate { document in
                        let value = document.scenarios[si].inputs.usage.seats[i]
                        let z = (value.samples.map(\.position.z).max() ?? 0) + 0.5
                        document.scenarios[si].inputs.usage.seats[i].samples.append(
                            SamplePoint(id: UUID(), position: Position3D(x: value.position.x, y: value.position.y, z: z)))
                    }
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
                ParameterRow("衣着", occupant.clothing)
                ParameterRow("显热", occupant.heat.sensible)
                ParameterRow("对流比例", occupant.heat.convectiveFraction)
                ParameterRow("潜热", occupant.heat.latent)
            }
            ScheduleEditor(schedule: occupant.schedule)
        })
    }

    private func equipmentForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let i = session.project.scenarios[si].inputs.usage.equipment.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let equipment = bind(\.scenarios[si].inputs.usage.equipment[i])
        return AnyView(Group {
            Section("设备热源") {
                ParameterRow("显热", equipment.heat.sensible)
                ParameterRow("对流比例", equipment.heat.convectiveFraction)
                ParameterRow("潜热", equipment.heat.latent)
            }
            ScheduleEditor(schedule: equipment.schedule)
            Button(role: .destructive, action: {
                session.mutate { $0.scenarios[si].inputs.usage.equipment.remove(at: i) }
                session.selection = nil
            }, label: { Label("删除设备热源", systemImage: "trash") })
        })
    }

    // MARK: - Controls / environment / cost

    private func controlForm(_ id: UUID) -> AnyView {
        guard let si = scenarioIndex,
              let i = session.project.scenarios[si].inputs.controls.firstIndex(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let control = bind(\.scenarios[si].inputs.controls[i])
        return AnyView(Group {
            Section("控制") {
                ParameterRow("设定温度", control.setpoint)
                Text("设定温度不等于送风温度。").font(.caption).foregroundStyle(.secondary)
            }
            ScheduleEditor(schedule: control.schedule)
        })
    }

    private var environmentForm: AnyView {
        guard let si = scenarioIndex else { return AnyView(EmptyView()) }
        let environment = bind(\.scenarios[si].inputs.environment)
        return AnyView(Group {
            Section("环境") {
                ParameterRow("室外温度", environment.outdoorTemperature)
                ParameterRow("室外湿度", environment.outdoorHumidity)
                ParameterRow("室内湿度", environment.indoorHumidity)
            }
            Section("代表日") {
                TextField("日期 YYYY-MM-DD", text: optionalString(environment.representativeDate))
                TextField("时区（IANA）", text: optionalString(environment.timeZone))
            }
            Section("天气文件") {
                TextField("包内相对路径", text: weatherPath(environment))
                TextField("SHA-256", text: weatherHash(environment))
                Text("天气文件校验在能耗适配阶段执行；当前仅记录引用。").font(.caption).foregroundStyle(.secondary)
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
            TextField("币种（如 CNY）", text: optionalString(cost.currency))
            Text("没有报价或电价时保持为空；缺失不会按零费用计算。").font(.caption).foregroundStyle(.secondary)
        })
    }

    // MARK: - Assumptions

    private var assumptionsSection: some View {
        Section("未知与假设") {
            let items = AssumptionCollector.items(in: session.project)
            if items.isEmpty {
                Text("当前没有未知参数。").foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { Text($0).font(.caption) }
            }
        }
    }
}

/// Representative-day schedule editor: contiguous intervals in minutes, fractions are parameters.
public struct ScheduleEditor: View {
    @Binding var schedule: DailySchedule

    public init(schedule: Binding<DailySchedule>) { self._schedule = schedule }

    public var body: some View {
        Section("时间表（代表日，分钟）") {
            ForEach(0..<schedule.intervals.count, id: \.self) { index in
                HStack {
                    TextField("起", value: $schedule.intervals[index].startMinute, format: .number).frame(maxWidth: 60)
                    Text("–")
                    TextField("止", value: $schedule.intervals[index].endMinute, format: .number).frame(maxWidth: 60)
                    ParameterRow("比例", $schedule.intervals[index].fraction)
                }
            }
            Button("添加时段") {
                let last = schedule.intervals.last?.endMinute ?? 0
                guard last < 1440 else { return }
                schedule.intervals.append(ScheduleInterval(
                    startMinute: last, endMinute: 1440,
                    fraction: .known(value: 0, source: .init(kind: .assumed, note: "Added interval; adjust fraction"))))
            }
            Text("首个物理配置要求时段连续覆盖 0–1440，停用时段比例为 0。").font(.caption).foregroundStyle(.secondary)
        }
    }
}
