#if DEBUG
import SwiftUI
import SimuCore
import SimuVisualization

/// Independent debug-only synthetic scene. No test executor or fabricated analysis result.
@MainActor
public struct NativeRoomSceneProbeHostView: View {
    @State private var store: WorkspaceStore
    @State private var obstruction = false
    @State private var openings = true
    @State private var forcePlan = false
    @State private var darkDisplay = false
    @State private var maximumText = false
    @State private var error: String?
    public init() {
        let store = WorkspaceStore()
        do { store.load(try N2ProbeFixture.make(obstruction: false,openings: true)) }
        catch { store.presentedError = error.localizedDescription }
        _store = State(initialValue: store)
    }
    public var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                ScrollView {
                VStack(spacing: 8) {
                Text("N2 非 AR 房间验证 · synthetic F-A / F-B").font(.headline).fixedSize(horizontal: false,vertical: true)
                Text("6×4×3 m；模型输入可编辑。没有气流计算，符号不是设备实体尺寸。").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [.init(.adaptive(minimum: 160))]) {
                    Toggle("F-B 薄盒遮挡",isOn: $obstruction)
                    Toggle("展示门窗样例",isOn: $openings)
                    Toggle("验证二维分支",isOn: $forcePlan)
                    Toggle("深色显示",isOn: $darkDisplay)
                    Toggle("最大字号",isOn: $maximumText)
                    Button("撤销输入编辑") { store.undo() }.disabled(!store.canUndo)
                    Button("重做输入编辑") { store.redo() }.disabled(!store.canRedo)
                }.padding(.horizontal)
                }
                }.frame(maxHeight: 180)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let project = store.project {
                    RoomObjectsView(project: project,scenarioID: N2ProbeFixture.id(10),rendererCapability: forcePlan ? .init(supportsNonAR3D: false,explanation: "验证强制二维分支；并非最低系统运行证据。") : .current) { candidate, action in
                        try store.replaceProject(candidate,actionName: action)
                    }
                }
            }
            .navigationTitle("N2 房间验证")
            .onChange(of: obstruction) { _, _ in applyFixture() }
            .onChange(of: openings) { _, _ in applyFixture() }
        }
        .preferredColorScheme(darkDisplay ? .dark : .light)
        .dynamicTypeSize(maximumText ? .accessibility5 : .large)
        #if os(macOS)
        .frame(minWidth: 600,idealWidth: 1000,minHeight: 650,idealHeight: 850)
        #endif
    }
    private func applyFixture() {
        do { try store.replaceProject(N2ProbeFixture.make(obstruction: obstruction,openings: openings),actionName: "切换 synthetic 验证夹具"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
private enum N2ProbeFixture {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d",n))! }
    static func length(_ v: Double) -> Length { .known(value: v,source: .init(kind: .assumed,reference: "synthetic.N2.probe",note: "Debug scene geometry, not a measured room.")) }
    static func make(obstruction: Bool, openings: Bool) throws -> ProjectDocument {
        let roomID = id(1), surfaces = SurfaceFace.allCases.enumerated().map { Surface(id: id(2+$0.offset),face: $0.element) }
        var cuts: [Opening] = []
        if openings {
            cuts = [.init(id: id(80),surfaceID: surfaces.first { $0.face == .xMin }!.id,kind: .door,offsetU: length(0.4),offsetV: length(0),width: length(0.8),height: length(2.1)),
                    .init(id: id(81),surfaceID: surfaces.first { $0.face == .yMin }!.id,kind: .window,offsetU: length(1.2),offsetV: length(1),width: length(1.4),height: length(1.1))]
        }
        let room = Room(id: roomID,name: "Synthetic 房间",shape: try .init(RectangularRoom(dimensions: .init(width: length(6),depth: length(4),height: length(3)))),northAngle: .unknown(reason: "Synthetic orientation not supplied"),surfaces: surfaces,openings: cuts)
        let split = SingleSplit(coolingCapacity: .unknown(reason: "验证夹具无制冷依据"),electricalPower: .unknown(reason: "验证夹具无电功率"),cop: .unknown(reason: "验证夹具无 COP"))
        let port = AirPort(id: id(21),role: .supply,position: .init(x: 0.05,y: 2,z: 1.5),direction: .init(x: 1,y: 0,z: 0),area: .unknown(reason: "验证夹具"),volumeFlow: .unknown(reason: "验证夹具"),speed: .unknown(reason: "验证夹具"),density: .unknown(reason: "验证夹具"))
        let device = HVACDevice(id: id(20),roomID: roomID,name: "Synthetic 空调",position: .init(x: 0.05,y: 2,z: 1.5),definition: try .init(split),ports: [port],supplyTemperature: .unknown(reason: "验证夹具无送风温度"))
        let positions = [Position3D(x: 2,y: 2,z: 1.5),Position3D(x: 4,y: 2,z: 1.5),Position3D(x: 2,y: 0.5,z: 1.5)]
        let seats = positions.enumerated().map { Seat(id: id(30+$0.offset),roomID: roomID,name: ["A 关注点","B 关注点","C 关注点"][$0.offset],position: $0.element,samples: [.init(id: id(40+$0.offset),position: .init(x: $0.element.x,y: $0.element.y,z: $0.element.z+0.1))]) }
        var scenario = Scenario.unfinished(id: id(10),name: "Synthetic 基准"); scenario.inputs.usage.seats = seats; scenario.inputs.hvac = [device]
        var boxes: [Obstacle] = []
        if obstruction { boxes = [.init(id: id(70),roomID: roomID,name: "F-B 0.05 m 薄盒",shape: try .init(BoxObstacle(origin: .init(x: 3,y: 1.5,z: 0),dimensions: .init(width: length(0.05),depth: length(1),height: length(2)))))] }
        return .init(id: id(100),name: "Synthetic N2",spaceType: .office,geometry: .init(rooms: [room],obstacles: boxes),scenarios: [scenario])
    }
}
#endif
