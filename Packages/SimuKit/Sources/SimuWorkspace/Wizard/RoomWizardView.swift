import SwiftUI
import SimuCore
import SimuDesignSystem

/// Multi-step room creation wizard. Produces an honest ProjectDocument:
/// geometry and envelope come from the form; climate uses the Hong Kong October preset;
/// HVAC and ventilation stay empty until the user fills them.
public struct RoomWizardDraft: Sendable {
    public init() {}

    public var name = "新项目"
    public var spaceType: SpaceType = .office
    public var widthText = "5.0"
    public var depthText = "4.0"
    public var heightText = "2.8"
    public var northKnown = false
    public var northText = "0"
    public var exteriorFaces: Set<SurfaceFace> = [.yMax]
    public var wallUText = "1.8"
    public var windowUText = "3.0"
    public var shgcText = "0.6"
    public var openings: [OpeningDraft] = []

    public struct OpeningDraft: Identifiable, Sendable {
        public let id = UUID()
        public var face: SurfaceFace = .yMax
        public var kind: OpeningKind = .window
        public var offsetUText = "1.0"
        public var offsetVText = "0.9"
        public var widthText = "1.5"
        public var heightText = "1.2"
    }

    public static let userSource = SourceRecord(kind: .user)
    public static let wizardNote = "Provided in room creation wizard"

    static func m(_ v: Double) -> Length { .known(value: v, source: userSource) }

    public var dimensionsValid: Bool {
        [widthText, depthText, heightText].compactMap(Double.init).allSatisfy { $0 > 0 }
            && [widthText, depthText, heightText].allSatisfy { Double($0) != nil }
    }

    public func openingError(_ opening: OpeningDraft) -> String? {
        guard let u = Double(opening.offsetUText), let v = Double(opening.offsetVText),
              let w = Double(opening.widthText), let h = Double(opening.heightText),
              let width = Double(widthText), let depth = Double(depthText), let height = Double(heightText) else {
            return "数值不完整"
        }
        guard w > 0, h > 0, u >= 0, v >= 0 else { return "尺寸必须为正" }
        let extent: (Double, Double) = switch opening.face {
        case .xMin, .xMax: (depth, height)
        case .yMin, .yMax: (width, height)
        case .floor, .ceiling: (width, depth)
        }
        if u + w > extent.0 + 1e-9 || v + h > extent.1 + 1e-9 { return "开口超出表面范围" }
        return nil
    }

    public func build() -> ProjectDocument {
        let roomID = UUID()
        let faces: [SurfaceFace] = [.xMin, .xMax, .yMin, .yMax, .floor, .ceiling]
        let surfaces = faces.map { Surface(id: UUID(), face: $0) }
        let openings: [Opening] = self.openings.compactMap { draft in
            guard openingError(draft) == nil, let surface = surfaces.first(where: { $0.face == draft.face }) else { return nil }
            return Opening(id: UUID(), surfaceID: surface.id, kind: draft.kind,
                           offsetU: Self.m(Double(draft.offsetUText)!), offsetV: Self.m(Double(draft.offsetVText)!),
                           width: Self.m(Double(draft.widthText)!), height: Self.m(Double(draft.heightText)!))
        }
        let width = Self.m(Double(widthText)!), depth = Self.m(Double(depthText)!), height = Self.m(Double(heightText)!)
        let shape = RectangularRoom(dimensions: Dimensions3D(width: width, depth: depth, height: height))
        let north: SimuCore.Angle = northKnown
            ? .known(value: Double(northText) ?? 0, source: Self.userSource)
            : HongKongOctoberClimate.northAngle()
        let room = Room(id: roomID, name: name, shape: try! ExtensionRecord(shape),
                        northAngle: north, surfaces: surfaces, openings: openings)
        let wallU: UValue = .known(value: Double(wallUText) ?? 1.8, source: Self.userSource)
        let windowU: UValue = .known(value: Double(windowUText) ?? 3.0, source: Self.userSource)
        let shgc: Ratio = .known(value: Double(shgcText) ?? 0.6, source: Self.userSource)
        let envelope = Envelope(
            surfaces: surfaces.map { surface in
                if exteriorFaces.contains(surface.face) {
                    return SurfaceCondition(surfaceID: surface.id, exposure: .outdoors, uValue: wallU,
                                            boundary: ThermalBoundary(mode: .temperature, temperature: HongKongOctoberClimate.exteriorAirTemperature()))
                }
                return SurfaceCondition(surfaceID: surface.id, exposure: .adiabatic, uValue: wallU,
                                        boundary: ThermalBoundary(mode: .heatFlux, heatFlux: .known(value: 0, source: .init(kind: .assumed, note: "Adiabatic interior partition (wizard assumption)"))))
            },
            windows: openings.filter { $0.kind == .window }.map {
                WindowCondition(openingID: $0.id, uValue: windowU, shgc: shgc,
                                shadingFactor: .known(value: 1.0, source: .init(kind: .assumed, note: "No shading device (wizard default)")))
            })
        let ventilation = RoomVentilation(roomID: roomID,
                                        outdoorAir: .unknown(reason: "待补充新风量"),
                                        exhaustAir: .unknown(reason: "待补充排风量"),
                                        infiltration: .known(value: 0, source: .init(kind: .assumed, note: "No infiltration (wizard default)")),
                                        exfiltration: .known(value: 0, source: .init(kind: .assumed, note: "No exfiltration (wizard default)")),
                                        density: .known(value: 1.2, source: .init(kind: .preset, reference: "Indoor air density near 20–26 °C (preset; verify)")),
                                        openings: openings.map { OpeningState(openingID: $0.id, openFraction: .known(value: 0, source: .init(kind: .assumed, note: "Closed (wizard default)"))) })
        let environment = HongKongOctoberClimate.environment()
        let scenario = Scenario(id: UUID(), name: "基准方案",
                                inputs: ScenarioInputs(usage: Usage(), hvac: [], controls: [],
                                                       envelope: envelope, ventilation: [ventilation], environment: environment),
                                evaluation: EvaluationInputs(cost: CostInputs()))
        return ProjectDocument(id: UUID(), name: name, spaceType: spaceType,
                               geometry: ProjectGeometry(rooms: [room], obstacles: []), scenarios: [scenario])
    }
}

public struct RoomWizardView: View {
    let onFinish: (ProjectDocument) -> Void
    @State private var draft = RoomWizardDraft()
    @State private var step = 0
    @SwiftUI.Environment(\.dismiss) private var dismiss: DismissAction

    public init(onFinish: @escaping (ProjectDocument) -> Void) { self.onFinish = onFinish }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    RoomPageIntro(stepTitle, detail: stepDetail)
                    ProgressView(value: Double(step + 1), total: 5)
                        .accessibilityLabel("建房进度，第 \(step + 1) 步，共 5 步")
                }
                switch step {
                case 0: basicsStep
                case 1: dimensionsStep
                case 2: openingsStep
                case 3: envelopeStep
                default: summaryStep
                }
            }
            .formStyle(.grouped)
            .navigationTitle("创建房间 · \(step + 1)/5")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if step > 0 { Button("上一步") { step -= 1 } }
                    if step < 4 {
                        Button("下一步") { step += 1 }.disabled(!canAdvance)
                    } else {
                        Button("进入房间") { onFinish(draft.build()) ; dismiss() }
                    }
                }
            }
        }
        .modifier(RoomTheme())
        .frame(idealWidth: 520, minHeight: 420)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 500)
        #endif
    }

    private var stepTitle: String {
        ["这是什么房间？", "房间有多大？", "门窗在哪里？", "哪些墙面接触室外？", "确认房间信息"][step]
    }

    private var stepDetail: String {
        ["起个名字，方便之后找到它。", "填入实际测量的尺寸，单位是米。", "可以先跳过；门窗位置从所在墙的起点量起。", "勾选接触室外的墙面，保温参数可在下面查看。", "先建好房间，再设置空调、座位和使用时间。"][step]
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return draft.dimensionsValid
        case 2: return draft.openings.allSatisfy { draft.openingError($0) == nil }
        default: return true
        }
    }

    private var basicsStep: some View {
        Section("项目") {
            TextField("名称", text: $draft.name)
            Picker("空间类型", selection: $draft.spaceType) {
                ForEach(SpaceType.allCases, id: \.self) { type in
                    Text(InputPresentation.spaceTitle(type)).tag(type)
                }
            }
        }
    }

    private var dimensionsStep: some View {
        Group {
            Section("房间尺寸（米）") {
                dimensionField("左右宽度", $draft.widthText)
                dimensionField("前后进深", $draft.depthText)
                dimensionField("天花板高度", $draft.heightText)
                if !draft.dimensionsValid { Text("尺寸必须为正的数值").foregroundStyle(.orange).font(.caption) }
            }
            Section("朝向") {
                Toggle("我知道房间朝向", isOn: $draft.northKnown)
                if draft.northKnown {
                    dimensionField("北向角（度）", $draft.northText)
                    DisclosureGroup("角度怎么量？") {
                        Text("以俯视图的远侧方向（+Y）为起点，顺时针转到真北。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("未填写时，俯视图远侧按正北。这是香港大学本部的默认朝向，房间不同请之后修改。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var openingsStep: some View {
        Group {
            Section("门与窗") {
                RoomPlanMark(showWalls: true)
                ForEach($draft.openings) { $opening in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Picker("类型", selection: $opening.kind) {
                                Text("窗").tag(OpeningKind.window)
                                Text("门").tag(OpeningKind.door)
                            }
                            .labelsHidden()
                            Picker("所在墙面", selection: $opening.face) {
                                ForEach(SurfaceFace.allCases, id: \.self) { Text(faceTitle($0)).tag($0) }
                            }
                            .labelsHidden()
                            Button(role: .destructive, action: { draft.openings.removeAll { $0.id == opening.id } }, label: {
                                Image(systemName: "trash")
                            })
                            .buttonStyle(.borderless)
                        }
                        VStack(spacing: 8) {
                            dimensionField("沿墙位置（米）", $opening.offsetUText)
                            dimensionField("离地高度（米）", $opening.offsetVText)
                            dimensionField("宽", $opening.widthText)
                            dimensionField("高", $opening.heightText)
                        }
                        DisclosureGroup("位置从哪里量？") {
                            Text("左右墙从近侧量起，近侧和远侧墙从左侧量起。地板和天花板沿左右、前后方向量起；所有位置与尺寸均为米。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = draft.openingError(opening) {
                            Text(error).foregroundStyle(.orange).font(.caption)
                        }
                    }
                }
                Button("添加门窗") { draft.openings.append(RoomWizardDraft.OpeningDraft()) }
            }
        }
    }

    private var envelopeStep: some View {
        Group {
            Section("接触室外的墙面") {
                RoomPlanMark(showWalls: true)
                ForEach(SurfaceFace.allCases, id: \.self) { face in
                    Toggle(faceTitle(face), isOn: exteriorBinding(face))
                }
                Text("未勾选的表面暂按不传热处理。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("保温与玻璃参数 · 专业设置") {
                    dimensionField("墙体传热系数 U", $draft.wallUText)
                    dimensionField("窗户传热系数 U", $draft.windowUText)
                    dimensionField("玻璃太阳得热系数 SHGC", $draft.shgcText)
                    Text("U 的单位为 W/(m²·K)，越小越隔热；SHGC 是 0–1 的比例。当前显示的初始值还需核实，保存后记为自己填写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("外墙外的空气温度已按香港 10 月月平均 25.7°C 填入，可在房间设置里修改。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summaryStep: some View {
        Section("确认") {
            LabeledContent("名称", value: draft.name)
            LabeledContent("尺寸", value: "\(draft.widthText) × \(draft.depthText) × \(draft.heightText) m")
            LabeledContent("门窗", value: "\(draft.openings.count) 个")
            LabeledContent("接触室外", value: SurfaceFace.allCases.filter { draft.exteriorFaces.contains($0) }.map(faceTitle).joined(separator: "、"))
            Text("气候、日期和时区已按香港大学 10 月默认填好。还需填写空调和通风；未填的会保留为待补充。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dimensionField(_ label: String, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(label, text: text)
                .labelsHidden()
                .accessibilityLabel(label)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func faceTitle(_ face: SurfaceFace) -> String {
        switch face {
        case .xMin: "左墙"; case .xMax: "右墙"
        case .yMin: "近侧墙"; case .yMax: "远侧墙"
        case .floor: "地板"; case .ceiling: "天花板"
        }
    }

    private func exteriorBinding(_ face: SurfaceFace) -> Binding<Bool> {
        Binding(get: { draft.exteriorFaces.contains(face) }, set: { isOn in
            if isOn { draft.exteriorFaces.insert(face) } else { draft.exteriorFaces.remove(face) }
        })
    }
}
