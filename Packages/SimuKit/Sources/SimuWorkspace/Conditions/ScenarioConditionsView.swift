import SwiftUI
import SimuCore

public struct ScenarioConditionsView: View {
    private let project: ProjectDocument
    @State private var initialDraft: ScenarioConditionsDraft
    private let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    private let onImportWeather: (@MainActor () -> Void)?
    private let onClearWeather: @MainActor () throws -> Void
    @State private var draft: ScenarioConditionsDraft
    @State private var baseProject: ProjectDocument
    @State private var section = ConditionsSection.envelope
    @State private var error: String?
    @State private var confirmDiscard = false
    @SwiftUI.Environment(\.editorFocus) private var focus
    @State private var pendingRepairSelection: RepairSelectionRequest?
    @SwiftUI.Environment(\.dismiss) private var dismiss

    public init(project: ProjectDocument, draft: ScenarioConditionsDraft,
                onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void,
                onImportWeather: (@MainActor () -> Void)?,
                onClearWeather: @escaping @MainActor () throws -> Void) {
        self.project = project; _initialDraft = State(initialValue: draft); _draft = State(initialValue: draft)
        _baseProject = State(initialValue: project)
        self.onCommit = onCommit; self.onImportWeather = onImportWeather; self.onClearWeather = onClearWeather
    }
    public var body: some View {
        NavigationStack {
            EditorForm {
                Label("本地预览仅需几何与风向；以下专业输入按估算任务补充。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if isStale {
                    EditorSection("项目已变化") {
                        Label("打开表单后项目已更新。此处保留未应用草稿供查看；请关闭并重新打开后编辑，防止覆盖最新输入。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                switch section {
                case .envelope: envelope
                case .ventilation: ventilation
                case .environment: environment
                case .cost: cost
                case .repair: repair
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityLabel("输入错误：\(error)") }
            }

            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.scenarios.first { $0.id == draft.scenarioID }?.name ?? "方案").font(.headline)
                    if section != .repair { Picker("输入类别", selection: $section) {
                        ForEach(ConditionsSection.allCases.filter { $0 != .repair }) { item in Text(item.title).tag(item) }
                    }.pickerStyle(.segmented) }
                    if !draft.repairItems.isEmpty {
                        Button(section == .repair ? "返回围护输入" : "查看并修复 \(draft.repairItems.count) 项异常记录", systemImage: "exclamationmark.triangle") {
                            section = section == .repair ? .envelope : .repair
                        }.controlSize(.small)
                    }
                    Text(sectionSummary).font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(.regularMaterial)
            }
            .onAppear {
                if draft.repairItems.contains(where: { $0.referenceID == focus.entityID }) { section = .repair; return }
                switch focus.field {
                case "室外温度", "室内相对湿度", "室外相对湿度", "代表日", "时区": section = .environment
                case "电价", "报价金额", "开始（HH:mm）", "结束（HH:mm）", "币种代码，例如 CNY / USD（未知时留空）": section = .cost
                case "室外新风", "室外排风", "渗风", "外泄", "交换空气密度", "开启比例": section = .ventilation
                default: break
                }
            }
            .navigationTitle("方案使用条件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if draft != initialDraft { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        do {
                            guard !isStale else { throw ConditionsDraftError.staleConditions }
                            try onCommit(draft.applying(to: baseProject), "修改方案使用条件"); dismiss()
                        }
                        catch { self.error = error.localizedDescription }
                    }.disabled(isStale)
                }
            }
            .confirmationDialog("放弃未应用的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .interactiveDismissDisabled(draft != initialDraft)
            .confirmationDialog("替换此对象尚未应用的字段？", isPresented: Binding(
                get: { pendingRepairSelection != nil }, set: { if !$0 { pendingRepairSelection = nil } }), titleVisibility: .visible) {
                if let request = pendingRepairSelection {
                    Button("选择原始记录", role: .destructive) { performRepairSelection(request); pendingRepairSelection = nil }
                }
                Button("继续编辑", role: .cancel) { pendingRepairSelection = nil }
            } message: { Text("该对象当前的字段草稿会被所选原始记录替换；其他配置记录仍会保留。") }
        }
        .environment(\.editorEntityID, draft.scenarioID)
        .modifier(EditorSheetSize())
    }
    private var envelope: some View {
        Group {
            ForEach($draft.surfaces) { $surface in
                EditorDisclosure(title: "\(surface.roomName) · \(RoomIssuePresentation.wallTitle(surface.face))", entityID: surface.id, initiallyExpanded: true) {
                    Toggle("记录此表面的热工输入", isOn: $surface.isEnabled)
                    if !surface.isEnabled { Text("未记录；不等于绝热。几何预览仍可使用此墙面。").font(.caption).foregroundStyle(.secondary) }
                    if surface.isEnabled {
                        Picker("室外关系（用户选择）", selection: $surface.exposure) {
                            Text("室外暴露").tag(Exposure.outdoors)
                            Text("绝热").tag(Exposure.adiabatic)
                        }
                        PhysicalParameterEditor("传热系数", draft: $surface.uValue, quantity: UValueTag.self, range: .nonnegative)
                        Picker("热边界", selection: $surface.mode) {
                            Text("等待 L1 提供").tag(BoundaryMode.fromL1)
                            Text("表面温度").tag(BoundaryMode.temperature)
                            Text("表面热流").tag(BoundaryMode.heatFlux)
                        }
                        if surface.mode == .temperature {
                            PhysicalParameterEditor("表面温度", draft: $surface.temperature, quantity: TemperatureTag.self, range: .init(minimum: -273.15))
                        } else if surface.mode == .heatFlux {
                            PhysicalParameterEditor("表面热流（有符号）", draft: $surface.heatFlux, quantity: HeatFluxTag.self)
                        } else {
                            Text("此边界尚未由能耗模型求得，将阻断当前计算准备。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach($draft.windows) { $window in
                EditorDisclosure(title: windowTitle(window.id, roomName: window.roomName), entityID: window.id, initiallyExpanded: true) {
                    Toggle("配置此窗", isOn: $window.isEnabled)
                    if window.isEnabled {
                        PhysicalParameterEditor("窗传热系数", draft: $window.uValue, quantity: UValueTag.self, range: .nonnegative)
                        PhysicalParameterEditor("太阳得热系数 SHGC", draft: $window.shgc, quantity: RatioTag.self, range: .fraction)
                        PhysicalParameterEditor("遮阳系数", draft: $window.shadingFactor, quantity: RatioTag.self, range: .fraction)
                    }
                }
            }
        }
    }
    private var ventilation: some View {
        Group {
            Text("室外新风、排风、渗风和外泄与空调室内回风循环分别建模；开启比例本身不自动换算成风量。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($draft.ventilation) { $room in
                EditorDisclosure(title: room.roomName + " · 室外交换", entityID: room.id, initiallyExpanded: true) {
                    Toggle("记录室外交换", isOn: $room.isEnabled)
                    if !room.isEnabled { Text("交换情况未记录；不等于无新风或零交换。").font(.caption).foregroundStyle(.secondary) }
                    if room.isEnabled {
                        PhysicalParameterEditor("室外新风", draft: $room.outdoorAir, quantity: VolumeFlowTag.self, range: .nonnegative)
                        PhysicalParameterEditor("室外排风", draft: $room.exhaustAir, quantity: VolumeFlowTag.self, range: .nonnegative)
                        PhysicalParameterEditor("渗风", draft: $room.infiltration, quantity: VolumeFlowTag.self, range: .nonnegative)
                        PhysicalParameterEditor("外泄", draft: $room.exfiltration, quantity: VolumeFlowTag.self, range: .nonnegative)
                        PhysicalParameterEditor("交换空气密度", draft: $room.density, quantity: DensityTag.self, range: .positive)
                        ForEach($room.openings) { $opening in
                            EditorDisclosure(title: windowTitle(opening.id, roomName: room.roomName), entityID: opening.id, initiallyExpanded: true) {
                            Toggle("记录开启状态", isOn: $opening.isConfigured)
                            if opening.isConfigured {
                                PhysicalParameterEditor("开启比例", draft: $opening.openFraction, quantity: RatioTag.self, range: .fraction)
                            }
                            }
                        }
                    }
                }
            }
        }
    }
    private var environment: some View {
        Group {
            EditorSection("代表工况") {
                RepresentativeDayField(text: $draft.representativeDate)
                Picker("时区", selection: $draft.timeZone) {
                    Text("未知").tag("")
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { zone in Text(zone).tag(zone) }
                    if !draft.timeZone.isEmpty, !TimeZone.knownTimeZoneIdentifiers.contains(draft.timeZone) { Text(draft.timeZone + " · 无效，需修复").tag(draft.timeZone) }
                }.id(EditorFieldAnchor(entityID: draft.scenarioID, field: "时区"))
                Text("时间表使用代表日的本地时间；时区不会由本机位置自动推定。").font(.caption).foregroundStyle(.secondary)
            }
            EditorSection("天气文件") {
                if let weather = project.scenarios.first(where: { $0.id == draft.scenarioID })?.inputs.environment.weather {
                    LabeledContent("包内路径", value: weather.relativePath)
                    Text("SHA-256：\(weather.sha256)").font(.caption).textSelection(.enabled)
                    Button("移除天气引用", role: .destructive) {
                        do {
                            guard !isStale else { throw ConditionsDraftError.staleConditions }
                            try onClearWeather(); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(draft != initialDraft || isStale)
                } else { Text("未提供天气文件") }
                if let onImportWeather {
                Button(draft != initialDraft ? "应用草稿并导入天气" : "导入 EPW 天气文件") {
                    do {
                        guard !isStale else { throw ConditionsDraftError.staleConditions }
                        if draft != initialDraft { try onCommit(draft.applying(to: baseProject), "应用条件并导入天气") }
                        dismiss(); onImportWeather()
                    } catch { self.error = error.localizedDescription }
                }.disabled(isStale)
                } else { Text("此工作区未配置天气文件导入。").font(.caption).foregroundStyle(.secondary) }
                Text("导入前应用草稿；取消或失败也保留这些已应用输入。天气复制到此方案的项目包，规则预览不要求 EPW；气象适用性尚待外部方法验证。").font(.caption).foregroundStyle(.secondary)
            }
            EditorSection("温湿度") {
                PhysicalParameterEditor("室外温度", draft: $draft.outdoorTemperature, quantity: TemperatureTag.self, range: .init(minimum: -273.15))
                PhysicalParameterEditor("室外相对湿度", draft: $draft.outdoorHumidity, quantity: RatioTag.self, range: .fraction, percentage: true)
                PhysicalParameterEditor("室内相对湿度", draft: $draft.indoorHumidity, quantity: RatioTag.self, range: .fraction, percentage: true)
            }
        }
    }
    private var cost: some View {
        Group {
            EditorSection("币种与来源") {
                EditorTextField(title: "币种代码，例如 CNY / USD（未知时留空）", text: $draft.currency)
                Text("费用未知不等于零；没有来源的报价和电价不能形成成本结论。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach($draft.tariffs) { $tariff in
                EditorSection("电价时段") {
                    ClockMinuteField(title: "开始", text: $tariff.startMinute)
                    ClockMinuteField(title: "结束", text: $tariff.endMinute)
                    PhysicalParameterEditor("电价", draft: $tariff.rate, quantity: EnergyRateTag.self, range: .nonnegative)
                    Button("删除此电价时段", role: .destructive) { draft.tariffs.removeAll { $0.id == tariff.id } }
                }.environment(\.editorFieldOrdinal, draft.tariffs.firstIndex { $0.id == tariff.id })
            }
            Button("新增电价时段") { draft.tariffs.append(.init()) }
            ForEach($draft.quotes) { $quote in
                EditorSection("报价 · " + quoteTitle(quote.quoteID)) {
                    PhysicalParameterEditor("报价金额", draft: $quote.amount, quantity: MoneyTag.self, range: .nonnegative)
                    Button("删除此报价", role: .destructive) { draft.quotes.removeAll { $0.id == quote.id } }
                }.environment(\.editorEntityID, quote.quoteID)
            }
            Button("新增报价") { draft.quotes.append(.init()) }
        }
    }

    private var sectionSummary: String {
        switch section {
        case .envelope: "已记录 \(draft.surfaces.filter(\.isEnabled).count)/\(draft.surfaces.count) 个表面、\(draft.windows.filter(\.isEnabled).count)/\(draft.windows.count) 个窗；记录不表示参数已齐备。"
        case .ventilation: "已记录 \(draft.ventilation.filter(\.isEnabled).count)/\(draft.ventilation.count) 个房间；室外交换独立于室内循环。"
        case .environment: "代表日、时区与天气；未知可以保留，规则预览无需天气。"
        case .cost: "\(draft.tariffs.count) 个电价时段 · \(draft.quotes.count) 个报价；费用需要明确币种和来源。"
        case .repair: "\(draft.repairItems.count) 项异常记录；普通编辑不会删除未选记录。"
        }
    }
    private func windowTitle(_ id: UUID, roomName: String) -> String {
        for room in project.geometry.rooms {
            if let opening = room.openings.first(where: { $0.id == id }) {
                let wall = room.surfaces.first(where: { $0.id == opening.surfaceID }).map { RoomIssuePresentation.wallTitle($0.face) } ?? "表面"
                let position = opening.offsetU.value.map { $0.formatted() + " m" } ?? "未知位置"
                return roomName + " · " + wall + " · " + (opening.kind == .window ? "窗" : "门") + "（距墙角 " + position + "）"
            }
        }
        return roomName + " · 失效的窗引用"
    }
    private func quoteTitle(_ id: UUID) -> String {
        guard let value = project.scenarios.first(where: { $0.id == draft.scenarioID })?.evaluation.cost.quotes.first(where: { $0.id == id }) else { return "待记录对象与来源" }
        return value.amount.source?.reference ?? value.amount.source?.note ?? "独立报价（未关联设备）"
    }
    private var isStale: Bool { project != baseProject }

    private var repair: some View {
        Group {
            EditorSection("导入配置修复") {
                Text("普通字段编辑保留所有其他原始配置及来源。重复配置按记录区分；选择记录仅决定编辑哪一条，不会删除其他项。删除和冲突清理只有在应用后才写入项目，可在此前恢复。")
                    .font(.caption).foregroundStyle(.secondary)
                if draft.repairItems.isEmpty { Text("没有未匹配引用、重复配置或热边界字段冲突。") }
            }
            ForEach(draft.repairItems) { item in
                EditorSection(item.title) {
                    Text(item.reasons.joined(separator: "；")).foregroundStyle(.orange)
                    Text("引用：\(item.referenceID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                    DisclosureGroup("原始值与来源") {
                        Text(item.originalJSON).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if item.isDeleted {
                        Label("应用时删除此记录", systemImage: "trash")
                        Button("保留原记录") { draft.restoreRepairRecord(item.location) }
                    } else {
                        if item.canSelect {
                            if item.isSelected { Label("当前编辑记录", systemImage: "checkmark.circle") }
                            else { Button("选择作为编辑记录") { requestRepairSelection(.init(location: item.location, normalize: false)) } }
                        }
                        if item.canNormalizeBoundary && item.canSelect {
                            if draft.boundaryNormalizationScheduled(item.location) {
                                Label("应用时按当前热边界模式清理冲突", systemImage: "checkmark.circle")
                            } else {
                                Button("按当前热边界模式清理冲突") { requestRepairSelection(.init(location: item.location, normalize: true)) }
                            }
                        }
                        Button("删除此原始配置", role: .destructive) {
                            do { try draft.deleteRepairRecord(item.location) } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }

    private func requestRepairSelection(_ request: RepairSelectionRequest) {
        if !draft.isSelected(request.location) && draft.selectionWouldDiscardEdits(request.location) {
            pendingRepairSelection = request
        } else { performRepairSelection(request) }
    }
    private func performRepairSelection(_ request: RepairSelectionRequest) {
        do {
            if request.normalize { try draft.normalizeBoundary(request.location) }
            else { try draft.selectRepairRecord(request.location) }
        } catch { self.error = error.localizedDescription }
    }
    private func faceName(_ face: SurfaceFace) -> String {
        switch face {
        case .xMin: "X 最小侧墙"
        case .xMax: "X 最大侧墙"
        case .yMin: "Y 最小侧墙"
        case .yMax: "Y 最大侧墙"
        case .floor: "地板"
        case .ceiling: "天花板"
        }
    }
}
private enum ConditionsSection: String, CaseIterable, Identifiable {
    case envelope, ventilation, environment, cost, repair
    var id: String { rawValue }
    var title: String {
        switch self {
        case .envelope: "围护"
        case .ventilation: "通风"
        case .environment: "环境"
        case .cost: "费用"
        case .repair: "修复引用与冲突"
        }
    }
}
private struct RepairSelectionRequest {
    let location: ConditionRepairLocation
    let normalize: Bool
}
