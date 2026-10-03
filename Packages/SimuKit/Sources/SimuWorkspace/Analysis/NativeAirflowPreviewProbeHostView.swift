#if DEBUG
    import SwiftUI
    import UniformTypeIdentifiers
    import SimuCore
    import SimuSimulation
    import SimuVisualization

    /// Debug fixture inputs go through the real production client, workspace and native document binding.
    @MainActor
    public struct NativeAirflowPreviewProbeHostView: View {
        @State private var document: SimuNowDocument
        @State private var exporting = false
        @State private var importing = false
        @State private var obstruction = false
        @State private var forcePlan = false
        @State private var error: String?
        private let client = LocalAnalysisClient.production()
        public init() {
            do {
                _document = State(initialValue: try SimuNowDocument(project: N3SyntheticFixture.make()))
            } catch { _document = State(initialValue: SimuNowDocument.unfinished()) }
        }
        public var body: some View {
            VStack(spacing: 4) {
                Text("N3 synthetic F-A / F-B / F-C · 真实 Swift 规则执行，不是预制结果").font(.caption)
                ViewThatFits(in: .horizontal) {
                    HStack { controls }
                    VStack { controls }
                }.padding(.horizontal)
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                WorkspaceDocumentView(
                    document: $document, localAnalysisClient: client,
                    rendererCapability: forcePlan
                        ? .init(supportsNonAR3D: false, explanation: "验证强制二维分支；最低系统仍需实机验收。") : .current)
            }
            .fileExporter(
                isPresented: $exporting, document: document, contentType: .simuNowProject,
                defaultFilename: "N3-synthetic"
            ) { result in
                if case .failure(let error) = result { self.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.simuNowProject]) { result in
                if case .success(let url) = result {
                    Task {
                        do { document = try await ProjectPackageIO().readPackage(from: url) } catch {
                            self.error = error.localizedDescription
                        }
                    }
                } else if case .failure(let error) = result {
                    self.error = error.localizedDescription
                }
            }
            #if os(macOS)
                .frame(minWidth: 1000, minHeight: 740)
            #endif
        }
        @ViewBuilder private var controls: some View {
            Toggle("F-B 0.05m 薄盒", isOn: $obstruction).onChange(of: obstruction) { _, value in
                do {
                    var project = document.project
                    project.geometry.obstacles = try N3SyntheticFixture.obstacles(enabled: value)
                    document = try document.applyingWorkspaceState(
                        .init(
                            project: project, baselineScenarioID: document.metadata.baselineScenarioID,
                            analysisConfiguration: try document.analysisConfigurationStore()))
                } catch { self.error = error.localizedDescription }
            }
            Toggle("验证二维", isOn: $forcePlan)
            Button("导出项目包") { exporting = true }
            Button("重新打开项目包") { importing = true }
        }
    }
    public enum N3SyntheticFixture {
        public static func id(_ n: Int) -> UUID {
            UUID(uuidString: String(format: "00000003-0000-4000-8000-%012d", n))!
        }
        private static func length(_ value: Double) -> Length {
            .known(
                value: value,
                source: .init(
                    kind: .assumed, reference: "synthetic.N3", note: "Synthetic geometry, not measured."))
        }
        public static func obstacles(enabled: Bool) throws -> [Obstacle] {
            enabled
                ? [
                    .init(
                        id: id(70), roomID: id(1), name: "F-B 0.05 m 薄盒",
                        shape: try .init(
                            BoxObstacle(
                                origin: .init(x: 3, y: 1.5, z: 0),
                                dimensions: .init(width: length(0.05), depth: length(1), height: length(2)))))
                ] : []
        }
        public static func make() throws -> ProjectDocument {
            let room = Room(
                id: id(1), name: "Synthetic 6×4×3",
                shape: try .init(
                    RectangularRoom(dimensions: .init(width: length(6), depth: length(4), height: length(3)))),
                northAngle: .unknown(reason: "Synthetic"),
                surfaces: SurfaceFace.allCases.enumerated().map {
                    .init(id: id(2 + $0.offset), face: $0.element)
                })
            var scenarios: [Scenario] = []
            for (i, yaw) in [0.0, 30.0, -30.0].enumerated() {
                let offset = 0
                let split = SingleSplit(
                    coolingCapacity: .unknown(reason: "No thermal basis"),
                    electricalPower: .unknown(reason: "No electrical basis"),
                    cop: .unknown(reason: "No performance basis"))
                let port = AirPort(
                    id: id(21 + offset), role: .supply, position: .init(x: 0.05, y: 2, z: 1.5),
                    direction: try AirflowDirection.unit(yawDegrees: yaw, pitchDegrees: 0),
                    area: .unknown(reason: "No measurement"), volumeFlow: .unknown(reason: "No measurement"),
                    speed: .unknown(reason: "No measurement"), density: .unknown(reason: "No measurement"))
                let device = HVACDevice(
                    id: id(20 + offset), roomID: id(1), name: "Synthetic split", position: port.position,
                    definition: try .init(split), ports: [port],
                    supplyTemperature: .unknown(reason: "No measurement"))
                var scenario = Scenario.unfinished(
                    id: id(10 + i), name: ["F-A 基准 0°", "F-C 候选 +30°", "F-C 候选 −30°"][i])
                scenario.inputs.hvac = [device]
                scenario.inputs.usage.seats = [
                    Position3D(x: 2, y: 2, z: 1.5), .init(x: 4, y: 2, z: 1.5), .init(x: 2, y: 0.5, z: 1.5),
                ].enumerated().map {
                    .init(
                        id: id(30 + $0.offset + offset), roomID: id(1), name: ["A", "B", "C"][$0.offset],
                        position: $0.element,
                        samples: [.init(id: id(40 + $0.offset + offset), position: $0.element)])
                }
                scenarios.append(scenario)
            }
            return .init(
                id: id(1000), name: "N3 synthetic 验证", spaceType: .office, geometry: .init(rooms: [room]),
                scenarios: scenarios)
        }
    }
#endif
