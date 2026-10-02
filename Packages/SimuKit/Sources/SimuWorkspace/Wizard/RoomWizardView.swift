import SwiftUI
import SimuCore

/// Multi-step room creation wizard. Produces an honest ProjectDocument:
/// geometry + envelope filled from user input; HVAC/usage empty; environment explicitly unknown.
public struct RoomWizardDraft: Sendable {
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
            : .unknown(reason: "Confirm orientation on site")
        let room = Room(id: roomID, name: name, shape: try! ExtensionRecord(shape),
                        northAngle: north, surfaces: surfaces, openings: openings)
        let wallU: UValue = .known(value: Double(wallUText) ?? 1.8, source: Self.userSource)
        let windowU: UValue = .known(value: Double(windowUText) ?? 3.0, source: Self.userSource)
        let shgc: Ratio = .known(value: Double(shgcText) ?? 0.6, source: Self.userSource)
        let envelope = Envelope(
            surfaces: surfaces.map { surface in
                if exteriorFaces.contains(surface.face) {
                    return SurfaceCondition(surfaceID: surface.id, exposure: .outdoors, uValue: wallU,
                                            boundary: ThermalBoundary(mode: .temperature, temperature: .unknown(reason: "Boundary condition pending L1 or weather adapter")))
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
        let environment = Environment(outdoorTemperature: .unknown(reason: "Weather adapter not connected"),
                                      outdoorHumidity: .unknown(reason: "Weather adapter not connected"),
                                      indoorHumidity: .unknown(reason: "No measurement or model source yet"))
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
                switch step {
                case 0: basicsStep
                case 1: dimensionsStep
                case 2: openingsStep
                case 3: envelopeStep
                default: summaryStep
                }
            }
            .navigationTitle("创建房间 (\(step + 1)/5)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if step < 4 {
                        Button("下一步") { step += 1 }.disabled(!canAdvance)
                    } else {
                        Button("创建") { onFinish(draft.build()) ; dismiss() }
                    }
                }
                if step > 0 {
                    ToolbarItem(placement: .secondaryAction) { Button("上一步") { step -= 1 } }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
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
                ForEach(SpaceType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
    }

    private var dimensionsStep: some View {
        Group {
            Section("房间尺寸（米）") {
                dimensionField("宽（X）", $draft.widthText)
                dimensionField("深（Y）", $draft.depthText)
                dimensionField("高（Z）", $draft.heightText)
                if !draft.dimensionsValid { Text("尺寸必须为正的数值").foregroundStyle(.orange).font(.caption) }
            }
            Section("朝向") {
                Toggle("已知北向角", isOn: $draft.northKnown)
                if draft.northKnown {
                    dimensionField("从 +Y 顺时针到真北（度）", $draft.northText)
                } else {
                    Text("朝向将标记为未知，可在属性面板补充。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var openingsStep: some View {
        Group {
            Section("门窗（按所在表面与局部坐标）") {
                ForEach($draft.openings) { $opening in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Picker("类型", selection: $opening.kind) {
                                Text("窗").tag(OpeningKind.window)
                                Text("门").tag(OpeningKind.door)
                            }
                            .labelsHidden()
                            Picker("表面", selection: $opening.face) {
                                ForEach(SurfaceFace.allCases, id: \.self) { Text(faceTitle($0)).tag($0) }
                            }
                            .labelsHidden()
                            Button(role: .destructive, action: { draft.openings.removeAll { $0.id == opening.id } }, label: {
                                Image(systemName: "trash")
                            })
                            .buttonStyle(.borderless)
                        }
                        HStack {
                            dimensionField("U 偏移", $opening.offsetUText)
                            dimensionField("V 偏移", $opening.offsetVText)
                            dimensionField("宽", $opening.widthText)
                            dimensionField("高", $opening.heightText)
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
            Section("外表面（其余按绝热内表面处理）") {
                ForEach(SurfaceFace.allCases, id: \.self) { face in
                    Toggle(faceTitle(face), isOn: exteriorBinding(face))
                }
            }
            Section("构造参数（W/(m²·K) 等）") {
                dimensionField("墙体 U 值", $draft.wallUText)
                dimensionField("窗 U 值", $draft.windowUText)
                dimensionField("窗 SHGC", $draft.shgcText)
                Text("以上标记为「用户」来源；外表面边界条件保持未知，待能耗或天气适配提供。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summaryStep: some View {
        Section("确认") {
            LabeledContent("名称", value: draft.name)
            LabeledContent("尺寸", value: "\(draft.widthText) × \(draft.depthText) × \(draft.heightText) m")
            LabeledContent("门窗", value: "\(draft.openings.count) 个")
            LabeledContent("外表面", value: draft.exteriorFaces.map(faceTitle).joined(separator: "、"))
            Text("创建后请在属性面板补充空调、座位、新风与环境参数；未知项会明确列出，不会自动填值。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dimensionField(_ label: String, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func faceTitle(_ face: SurfaceFace) -> String {
        switch face {
        case .xMin: "西墙 (xMin)"; case .xMax: "东墙 (xMax)"
        case .yMin: "南墙 (yMin)"; case .yMax: "北墙 (yMax)"
        case .floor: "地板"; case .ceiling: "天花板"
        }
    }

    private func exteriorBinding(_ face: SurfaceFace) -> Binding<Bool> {
        Binding(get: { draft.exteriorFaces.contains(face) }, set: { isOn in
            if isOn { draft.exteriorFaces.insert(face) } else { draft.exteriorFaces.remove(face) }
        })
    }
}
