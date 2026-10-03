import SwiftUI
import CoreTransferable
import SimuReporting
import UniformTypeIdentifiers
import SimuCore
import SimuSimulation

private struct AnonymousMeasurements: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName { _ in "SimuNow-匿名测量.json" }
    }
}

@MainActor public struct MeasurementWorkspaceView: View {
    let store: WorkspaceStore
    let entries: [String: ProjectPackageEntry]
    let revision: UUID
    @State private var datasets: [MeasurementDataset] = []
    @State private var datasetPage = 0
    @State private var datasetFileCount = 0
    @State private var current: MeasurementDataset?
    @State private var importing = false
    @State private var manual = false
    @State private var error: String?
    @State private var busy = false
    @State private var work: Task<Void, Never>?
    @State private var token = UUID()
    @State private var calibration: JetCalibrationRecord?
    @State private var savedCalibrations: [JetCalibrationRecord] = []
    @State private var calibrationSaved = false
    @State private var historicalCalibration = false
    @State private var deviceID: UUID?
    @State private var portID: UUID?
    @State private var anonymous: Data?
    @State private var radius = ""
    @State private var distance = ""
    @State private var errorLimit = ""
    public init(store: WorkspaceStore, entries: [String: ProjectPackageEntry], revision: UUID) {
        self.store = store; self.entries = entries; self.revision = revision
    }
    public var body: some View {
        Form {
            Section("记录现场测量") {
                Text("测量用于评价模型。记录位置、含时区时间、仪表质量、风档、门窗和设备；校准组与独立验证组须提前分开。主观感受不能录为风速。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("导入测量 CSV") { importing = true }.disabled(busy || store.project == nil)
                Button("手动记录一条测量") { manual = true }.disabled(busy || store.project == nil)
                ShareLink(item: MeasurementCSVImporter.template) { Label("分享 CSV 字段模板", systemImage: "doc.text") }
                DisclosureGroup("字段与单位说明") {
                    Text("quantity：airSpeed/outletSpeed/outletFlow/temperature/electricalPower/relativeHumidity/co2。单位：m/s、m3/s、degC、W、%、ppm；也接受 km/h、L/s、m3/h、K、degF、kW。")
                    Text("quality：valid/suspect/missing/rejected；非 valid 需 quality_reason。partition：calibration/validation/unassigned。door_state/window_state：open/closed/unknown。")
                    Text("位置为米制右手 Z-up。timestamp 例如 2026-10-03T15:00:00+08:00，不能省略时区。设备可填 device_id UUID；射流校准还需 instrument_range 和 instrument_calibration。")
                }.font(.caption)
                if busy { ProgressView("后台检查测量与证据…") }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            Section("本地数据集") {
                ForEach(datasets) { dataset in
                    Button("\(dataset.records.count) 条测量 · \(dataset.issues.count) 个问题 · \(dataset.id.uuidString.prefix(8))") { select(dataset) }
                }
                HStack {
                    Button("上一页数据集") { datasetPage -= 1 }.disabled(datasetPage == 0 || busy)
                    Button("下一页数据集") { datasetPage += 1 }.disabled((datasetPage + 1) * 12 >= datasetFileCount || busy)
                }
                if datasets.isEmpty { Text("尚无已保存的测量；导入不会改写房间或空调输入。") }
            }
            if let current {
                Section("所选测量 · \(current.records.count) 条") {
                    Button("生成匿名测量分享预览") { anonymize(current) }.disabled(busy)
                    if let anonymous {
                        DisclosureGroup("查看将分享的匿名 JSON") { Text(String(decoding: anonymous, as: UTF8.self)).font(.caption).textSelection(.enabled) }
                        ShareLink(item: AnonymousMeasurements(data: anonymous), preview: SharePreview("SimuNow 匿名测量")) { Label("分享匿名测量", systemImage: "square.and.arrow.up") }
                        Text("已移除位置、时间、姓名、设备和仪表标识；原始数据仍仅在项目内。").font(.caption)
                    }
                    Text("来源 CSV SHA-256：\(current.sourceSHA256)").font(.caption).textSelection(.enabled)
                    ForEach(current.records.prefix(200)) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.quantity.title)：\(row.value.map { $0.formatted() } ?? "缺失") \(row.unit)")
                            Text("\(row.timestamp) · \(qualityTitle(row.quality)) · \(partitionTitle(row.partition))").font(.caption)
                            Text("仪表：\(row.instrument) · 风档：\(row.fanSetting)").font(.caption)
                            if let reason = row.qualityReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if current.records.count > 200 { Text("界面显示前 200 条；完整数据保留在项目包中。") }
                    ForEach(Array(current.issues.prefix(100).enumerated()), id: \.offset) { _, issue in
                        Text("第 \(issue.row) 行：\(issue.message)").font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("有限射流校准 · 研究") {
                    Text("只接受同设备、同风档、关闭门窗的仪表风速；至少 6 条校准与 3 条独立验证。出口速度必须来自 calibration 组的实测记录。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("被测设备（必须明确选择）", selection: $deviceID) {
                        Text("请选择设备").tag(Optional<UUID>.none)
                        ForEach(store.currentScenario?.inputs.hvac ?? [], id: \.id) { device in Text(device.name).tag(Optional(device.id)) }
                    }
                    Picker("对应安装的送风口", selection: $portID) {
                        Text("请选择送风口").tag(Optional<UUID>.none)
                        ForEach(store.currentScenario?.inputs.hvac.first(where: { $0.id == deviceID })?.ports.filter { $0.role == .supply } ?? [], id: \.id) { port in
                            Text("送风口 \(port.id.uuidString.prefix(6))").tag(Optional(port.id))
                        }
                    }
                    TextField("实测出口等效半径 · m", text: $radius)
                    TextField("声明最大距离 · m", text: $distance)
                    TextField("独立验证 RMSE 上限 · m/s", text: $errorLimit)
                    Button("拟合并检查独立留出数据") { calibrate(current) }.disabled(busy)
                    if let calibration {
                        Text(calibrationSaved ? "固定校准已保存到项目" : "当前校准尚未保存，仅在会话中").font(.caption)
                        if historicalCalibration { Text("历史安装条件的校准记录；修改几何、设备或运行条件后必须重新拟合，不能直接作为当前模型。").font(.caption).foregroundStyle(.orange) }
                        Text(calibration.acceptedForScopedResearch ? "通过声明误差门槛，仅可用于绑定范围研究" : "未通过门槛，保留失败证据；继续使用规则预览")
                        Text("验证 RMSE：原参数 \(calibration.uncalibratedValidationMetrics.rootMeanSquaredErrorMetersPerSecond.formatted()) → 拟合后 \(calibration.validationMetrics.rootMeanSquaredErrorMetersPerSecond.formatted()) m/s")
                        Text("校准 \(calibration.calibrationMetrics.sampleCount) 条 · 留出 \(calibration.validationMetrics.sampleCount) 条；\(calibration.method)").font(.caption)
                        ForEach(calibration.limitations, id: \.self) { Text($0).font(.caption) }
                    }
                }
            }
            Section("扩展范围") {
                Text("动态 RC/CO₂ 与二维网格是有界研究接口，未注册为当前规则预览。没有独立真实数据与平台预算证据时不升级结果等级。专业外部复核需单独配置 HTTPS 节点、认证、版本和每次传输确认；首版离线功能不依赖节点。")
            }
        }.formStyle(.grouped)
        .task(id: "\(revision)/\(datasetPage)/\(current?.id.uuidString ?? "none")") {
            guard let projectID = store.project?.id else { return }
            let instance = store.documentInstanceID, files = entries, offset = datasetPage * 12, requestedDatasetID = current?.id
            let worker = Task.detached {
                let datasetIDs = MeasurementArtifact.index(entries: files)
                let datasets = try datasetIDs.dropFirst(offset).prefix(12).compactMap { id -> MeasurementDataset? in
                    try Task.checkCancellation(); return try? MeasurementArtifact.load(id: id, entries: files, projectID: projectID).dataset
                }
                let calibrations = try CalibrationArtifact.index(entries: files, datasetID: requestedDatasetID ?? datasets.first?.id).prefix(12).compactMap { id -> JetCalibrationRecord? in
                    try Task.checkCancellation(); return try? CalibrationArtifact.load(id: id, entries: files, projectID: projectID).record
                }
                return (datasets, calibrations, datasetIDs.count)
            }
            let values = try? await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, (try? store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: revision)) != nil else { return }
            datasets = values?.0 ?? []; savedCalibrations = values?.1 ?? []; datasetFileCount = values?.2 ?? 0
            if current == nil, let first = datasets.first { select(first) }
            else if calibration == nil, let current { select(current) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result { case .success(let url): importCSV(url); case .failure(let failure): error = failure.localizedDescription }
        }
        .sheet(isPresented: $manual) {
            if let projectID = store.project?.id { ManualMeasurementEditor(projectID: projectID, deviceID: store.currentScenario?.inputs.hvac.first?.id) { save($0) } }
        }
        .onChange(of: store.revision) { _, _ in historicalCalibration = true }
        .onChange(of: store.selectedScenarioID) { _, _ in deviceID = nil; portID = nil; historicalCalibration = true }
        .onChange(of: deviceID) { _, _ in portID = nil; historicalCalibration = true }
        .onChange(of: portID) { _, _ in historicalCalibration = true }
        .onDisappear { work?.cancel(); token = UUID(); busy = false }
    }
    private func select(_ dataset: MeasurementDataset) {
        if current?.id != dataset.id { anonymous = nil }
        current = dataset
        calibration = savedCalibrations.first { $0.datasetID == dataset.id }
        calibrationSaved = calibration != nil; historicalCalibration = true
    }
    private func anonymize(_ dataset: MeasurementDataset) {
        let instance = store.documentInstanceID
        start {
            let worker = Task.detached { try MeasurementSummaryExporter.export(dataset) }
            let data = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            try store.validateNativeDocumentContext(instanceID: instance)
            guard current?.id == dataset.id else { return }
            anonymous = data
        }
    }
    private func qualityTitle(_ q: MeasurementQuality) -> String {
        switch q { case .valid: "有效测量"; case .suspect: "待核对"; case .missing: "缺失"; case .rejected: "拒绝参与计算" }
    }
    private func partitionTitle(_ p: MeasurementPartition) -> String {
        switch p { case .calibration: "校准组"; case .validation: "独立验证组"; case .unassigned: "未分组" }
    }
    private func importCSV(_ url: URL) {
        guard let projectID = store.project?.id else { return }
        let instance = store.documentInstanceID
        start {
            let bytes = try await MeasurementFileIO().readCSV(url)
            let worker = Task.detached { try MeasurementArtifact.make(MeasurementCSVImporter.importCSV(bytes, projectID: projectID)) }
            let artifact = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try store.validateNativeDocumentContext(instanceID: instance)
            try accept(artifact)
        }
    }
    private func save(_ dataset: MeasurementDataset) {
        let instance = store.documentInstanceID
        start {
            let worker = Task.detached { try MeasurementArtifact.make(dataset) }
            let artifact = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try store.validateNativeDocumentContext(instanceID: instance)
            try accept(artifact)
        }
    }
    private func accept(_ artifact: MeasurementArtifact) throws {
        try Task.checkCancellation()
        current = artifact.dataset; calibration = nil; anonymous = nil; calibrationSaved = false
        guard let persist = store.persistMeasurements else { throw NativeArtifactError.unsupportedRecord }
        do { try persist(artifact) } catch { self.error = "测量仍在会话中，未保存：\(error.localizedDescription)"; throw error }
    }
    private func calibrate(_ dataset: MeasurementDataset) {
        guard let project = store.project, let device = store.currentScenario?.inputs.hvac.first(where: { $0.id == deviceID }), let port = device.ports.first(where: { $0.id == portID && $0.role == .supply }),
              let r = Double(radius), let d = Double(distance), let limit = Double(errorLimit) else { error = "请提供实测半径、距离和误差门槛，并选择含送风口的设备。"; return }
        let instance = store.documentInstanceID, inputRevision = store.revision
        start {
            let worker = Task.detached {
                let geometryHash = AnalysisHasher.sha256(try JSONTreeCoding.encode(project.geometry).data())
                let input = FiniteJetCalibrationInput(dataset: dataset, deviceID: device.id, geometrySHA256: geometryHash,
                    origin: port.position, direction: port.direction, outletRadiusMeters: r, maximumDistanceMeters: d, maximumValidationRMSE: limit)
                return try CalibrationArtifact.make(input)
            }
            let artifact = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try store.validateNativeDocumentContext(instanceID: instance)
            guard store.revision == inputRevision, current?.id == dataset.id else { throw PreviewConfigurationEditingError.staleDraft }
            try Task.checkCancellation()
            calibration = artifact.record; calibrationSaved = false; historicalCalibration = false
            guard let persist = store.persistCalibration else { throw NativeArtifactError.unsupportedRecord }
            try persist(artifact); calibrationSaved = true
        }
    }
    private func start(_ action: @escaping @MainActor () async throws -> Void) {
        work?.cancel(); token = UUID(); let generation = token; busy = true; error = nil
        work = Task {
            defer { if token == generation { busy = false; work = nil } }
            do { try await action() } catch { if !Task.isCancelled, token == generation { self.error = error.localizedDescription } }
        }
    }
}

@MainActor private struct ManualMeasurementEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let deviceID: UUID?
    let onSave: (MeasurementDataset) -> Void
    @State private var quantity: MeasurementQuantity = .temperature
    @State private var timestamp = Date().ISO8601Format()
    @State private var value = ""
    @State private var x = ""
    @State private var y = ""
    @State private var z = ""
    @State private var instrument = ""
    @State private var fan = "unknown"
    @State private var partition: MeasurementPartition = .unassigned
    @State private var valid = false
    @State private var error: String?
    init(projectID: UUID, deviceID: UUID?, onSave: @escaping (MeasurementDataset) -> Void) {
        self.projectID = projectID; self.deviceID = deviceID; self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("测量类型", selection: $quantity) { ForEach(MeasurementQuantity.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField("时间 · ISO 8601（需时区）", text: $timestamp)
                TextField("测量值 · \(quantity.unit)", text: $value)
                TextField("仪表标识", text: $instrument)
                TextField("风档（未知写 unknown）", text: $fan)
                TextField("位置 X · m", text: $x); TextField("位置 Y · m", text: $y); TextField("位置 Z · m", text: $z)
                Text("位置可全部留空；风速校准需要完整位置。门窗与仪表校准状态在此简表中保留未知，需 CSV 补充后再参与校准。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("数据分组", selection: $partition) { Text("未分组").tag(MeasurementPartition.unassigned); Text("校准组").tag(MeasurementPartition.calibration); Text("独立验证组").tag(MeasurementPartition.validation) }
                Toggle("确认这是仪表测量且质量已核对", isOn: $valid)
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle("记录现场测量")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("记录") { record() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
    }
    private func record() {
        do {
            guard let number = Double(value), number.isFinite else { throw ProjectDataError.contract("请填写有限测量值。") }
            let position: Position3D?
            if [x,y,z].allSatisfy(\.isEmpty) { position = nil }
            else { guard let xx = Double(x), let yy = Double(y), let zz = Double(z) else { throw ProjectDataError.contract("位置需完整 x/y/z。") }; position = .init(x: xx, y: yy, z: zz) }
            let row = MeasurementRecord(timestamp: timestamp, position: position, quantity: quantity, value: number, instrument: instrument,
                quality: valid ? .valid : .suspect, qualityReason: valid ? nil : "仪表质量尚未核对", fanSetting: fan,
                doorState: .unknown, windowState: .unknown, partition: partition, deviceID: deviceID)
            try MeasurementDatasetCodec.validate(row)
            let source = try JSONTreeCoding.encode(row).data()
            onSave(.init(projectID: projectID, sourceSHA256: AnalysisHasher.sha256(source), records: [row], issues: [])); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
