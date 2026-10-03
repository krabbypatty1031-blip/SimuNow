import Foundation
import SimuCore

public struct FiniteJetCalibrationInput: Sendable {
    public let dataset: MeasurementDataset
    public let deviceID: UUID
    public let geometrySHA256: String
    public let origin: Position3D
    public let direction: Direction3D
    public let outletRadiusMeters: Double
    public let maximumDistanceMeters: Double
    public let maximumValidationRMSE: Double
    public init(dataset: MeasurementDataset, deviceID: UUID, geometrySHA256: String, origin: Position3D, direction: Direction3D,
                outletRadiusMeters: Double, maximumDistanceMeters: Double, maximumValidationRMSE: Double) {
        self.dataset = dataset; self.deviceID = deviceID; self.origin = origin; self.direction = direction
        self.geometrySHA256 = geometrySHA256
        self.outletRadiusMeters = outletRadiusMeters; self.maximumDistanceMeters = maximumDistanceMeters
        self.maximumValidationRMSE = maximumValidationRMSE
    }
}
/// Bounded empirical free-jet experiment. It is never registered as a production preview executor.
public struct ScopedFiniteJetModel: Sendable {
    public let evidence: JetCalibrationRecord
    private init(evidence: JetCalibrationRecord) { self.evidence = evidence }
    /// Decoded flags alone are not authority: rebuild against the exact measured parent.
    public static func verified(record: JetCalibrationRecord, dataset: MeasurementDataset) throws -> Self {
        let tree = try JSONTreeCoding.encode(record)
        try WireSchema.validate(tree, schema: NativeAnalysisCodec.schema(.jetCalibration))
        let bytes = try MeasurementDatasetCodec.encode(dataset)
        guard record.datasetID == dataset.id, record.projectID == dataset.projectID,
              record.datasetSHA256 == AnalysisHasher.sha256(bytes), record.acceptedForScopedResearch else {
            throw ProjectDataError.contract("校准记录未通过或不属于所选测量证据。")
        }
        let input = FiniteJetCalibrationInput(dataset: dataset, deviceID: record.deviceID, geometrySHA256: record.geometrySHA256,
            origin: record.origin, direction: record.direction, outletRadiusMeters: record.outletRadiusMeters,
            maximumDistanceMeters: record.maximumDistanceMeters, maximumValidationRMSE: record.maximumValidationRMSE)
        guard try FiniteJetCalibration.calibrate(input, recordID: record.id) == record else {
            throw ProjectDataError.contract("校准参数或留出结果与固定测量不一致。")
        }
        return .init(evidence: record)
    }
}

public enum FiniteJetCalibration {
    public static let method = "simunow.experimental.finiteJet.v1"
    private struct Sample { let record: MeasurementRecord; let axial: Double; let radial: Double; let measured: Double }
    public static func calibrate(_ input: FiniteJetCalibrationInput, recordID: UUID = UUID()) throws -> JetCalibrationRecord {
        let bytes = try MeasurementDatasetCodec.encode(input.dataset)
        let magnitude = sqrt(input.direction.x * input.direction.x + input.direction.y * input.direction.y + input.direction.z * input.direction.z)
        guard [input.origin.x, input.origin.y, input.origin.z, input.outletRadiusMeters, input.maximumDistanceMeters, input.maximumValidationRMSE, magnitude].allSatisfy(\.isFinite),
              abs(magnitude - 1) <= 1e-6, input.outletRadiusMeters > 0, input.outletRadiusMeters <= 1,
              input.maximumDistanceMeters > input.outletRadiusMeters * 2, input.maximumDistanceMeters <= 30,
              input.maximumValidationRMSE > 0,
              input.geometrySHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw ProjectDataError.contract("射流校准需要有效安装方向、出口尺寸、几何身份、有限距离和明确误差门槛。") }
        let scoped = input.dataset.records.filter { $0.deviceID == input.deviceID && $0.quality == .valid }
        guard scoped.count <= 2000 else { throw ProjectDataError.contract("一次校准最多使用 2000 条有效测量。") }
        let speed = scoped.filter { $0.quantity == .outletSpeed && $0.partition == .calibration }
        guard !speed.isEmpty, speed.allSatisfy({ $0.value.map { $0 > 0 } == true && $0.instrumentCalibration?.isEmpty == false && $0.instrumentRange?.isEmpty == false }),
              let outlet = speed.first?.value else { throw ProjectDataError.contract("请提供 calibration 分组的实测出口风速、仪表范围和校准记录；展示档案不提供出口速度。") }
        guard speed.allSatisfy({ abs(($0.value ?? 0) - outlet) <= max(0.05, outlet * 0.05) }) else { throw ProjectDataError.contract("出口速度变化过大，应按运行工况拆分数据。") }
        let candidates = scoped.filter { $0.quantity == .airSpeed && $0.partition != .unassigned }
        guard let fan = speed.first?.fanSetting, fan != "unknown", !fan.isEmpty,
              (speed + candidates).allSatisfy({ $0.fanSetting == fan && $0.doorState == .closed && $0.windowState == .closed }),
              candidates.allSatisfy({ $0.position != nil && $0.value != nil && $0.instrumentCalibration?.isEmpty == false && $0.instrumentRange?.isEmpty == false }) else {
            throw ProjectDataError.contract("需同一明确风档、关闭门窗、有位置及仪表校准信息的实测风速。请拆分不同条件或补齐信息。")
        }
        let samples = try candidates.map { record -> Sample in
            let p = record.position!, o = input.origin, d = input.direction
            let x = p.x - o.x, y = p.y - o.y, z = p.z - o.z
            let axial = x * d.x + y * d.y + z * d.z
            let radial = sqrt(max(0, x*x + y*y + z*z - axial*axial))
            guard axial >= input.outletRadiusMeters * 2, axial <= input.maximumDistanceMeters else {
                throw ProjectDataError.contract("测点处于出口近场、射流后方或声明范围外，不能用于此有限模型。")
            }
            return .init(record: record, axial: axial, radial: radial, measured: record.value!)
        }
        let training = samples.filter { $0.record.partition == .calibration }, validation = samples.filter { $0.record.partition == .validation }
        guard training.count >= 6, validation.count >= 3,
              let minX = training.map(\.axial).min(), let maxX = training.map(\.axial).max(), maxX - minX > input.outletRadiusMeters * 2,
              training.contains(where: { $0.radial > input.outletRadiusMeters }),
              Set(training.map { pointKey($0.record) }).count == training.count,
              Set(validation.map { pointKey($0.record) }).isDisjoint(with: Set(training.map { pointKey($0.record) })) else {
            throw ProjectDataError.contract("参数不可辨识或留出泄漏：至少 6 个有轴向/径向差异的校准点及 3 个独立位置或时段验证点。")
        }
        // Validation never participates in parameter selection.
        var bestSpread = 0.1, bestDecay = 0.1, bestError = Double.infinity, bestS = 0, bestK = 0
        for s in 0...40 {
            try Task.checkCancellation()
            let spread = 0.02 + Double(s) * 0.008
            for k in 0...40 {
                let decay = 0.01 + Double(k) * 0.025
                let error = training.reduce(0.0) { sum, point in
                    let diff = predict(point, outlet: outlet, radius: input.outletRadiusMeters, spread: spread, decay: decay) - point.measured
                    return sum + diff * diff
                }
                if error < bestError { bestError = error; bestSpread = spread; bestDecay = decay; bestS = s; bestK = k }
            }
        }
        let before = metrics(validation, outlet: outlet, radius: input.outletRadiusMeters, spread: 0.1, decay: 0.1)
        let after = metrics(validation, outlet: outlet, radius: input.outletRadiusMeters, spread: bestSpread, decay: bestDecay)
        let trainingMetrics = metrics(training, outlet: outlet, radius: input.outletRadiusMeters, spread: bestSpread, decay: bestDecay)
        // Boundary optima indicate an unidentifiable/out-of-model solution and remain rejected evidence.
        let boundary = bestS == 0 || bestS == 40 || bestK == 0 || bestK == 40
        let accepted = !boundary && after.rootMeanSquaredErrorMetersPerSecond <= input.maximumValidationRMSE
            && after.rootMeanSquaredErrorMetersPerSecond <= before.rootMeanSquaredErrorMetersPerSecond
        return .init(id: recordID, projectID: input.dataset.projectID, datasetID: input.dataset.id, datasetSHA256: AnalysisHasher.sha256(bytes), deviceID: input.deviceID, geometrySHA256: input.geometrySHA256,
            origin: input.origin, direction: input.direction, outletSpeedMetersPerSecond: outlet, outletRadiusMeters: input.outletRadiusMeters,
            spreadingRate: bestSpread, decayRatePerMeter: bestDecay, fanSetting: fan,
            calibrationIDs: training.map(\.record.id), validationIDs: validation.map(\.record.id), calibrationMetrics: trainingMetrics,
            validationMetrics: after, uncalibratedValidationMetrics: before, maximumDistanceMeters: samples.map(\.axial).max()!,
            minimumDistanceMeters: samples.map(\.axial).min()!, maximumRadialDistanceMeters: samples.map(\.radial).max()!, maximumValidationRMSE: input.maximumValidationRMSE,
            acceptedForScopedResearch: accepted)
    }
    public static func speed(model: ScopedFiniteJetModel, projectID: UUID, deviceID: UUID, geometrySHA256: String, fanSetting: String, currentOutletOrigin: Position3D, currentOutletDirection: Direction3D, position: Position3D) throws -> Double {
        let record = model.evidence
        guard record.acceptedForScopedResearch, record.projectID == projectID, record.deviceID == deviceID,
              record.geometrySHA256 == geometrySHA256, record.fanSetting == fanSetting,
              record.origin == currentOutletOrigin, record.direction == currentOutletDirection, [position.x, position.y, position.z].allSatisfy(\.isFinite) else {
            throw ProjectDataError.contract("模型未通过独立留出门槛，或已超出绑定的房间/设备/风档。")
        }
        let d = record.direction, o = record.origin, x = position.x-o.x, y = position.y-o.y, z = position.z-o.z
        let axial = x*d.x + y*d.y + z*d.z, radial = sqrt(max(0, x*x + y*y + z*z - axial*axial))
        guard axial >= record.minimumDistanceMeters, axial <= record.maximumDistanceMeters, radial <= record.maximumRadialDistanceMeters else { throw ProjectDataError.contract("位置超过实测模型距离范围。") }
        return formula(axial: axial, radial: radial, outlet: record.outletSpeedMetersPerSecond, radius: record.outletRadiusMeters, spread: record.spreadingRate, decay: record.decayRatePerMeter)
    }
    private static func pointKey(_ record: MeasurementRecord) -> String {
        let p = record.position!
        let instant = MeasurementDatasetCodec.timestamp(record.timestamp)!.timeIntervalSince1970
        return "\(p.x),\(p.y),\(p.z),\(instant)"
    }
    private static func formula(axial: Double, radial: Double, outlet: Double, radius: Double, spread: Double, decay: Double) -> Double {
        let width = radius + spread * axial
        return outlet / (1 + decay * axial) * exp(-pow(radial / width, 2))
    }
    private static func predict(_ p: Sample, outlet: Double, radius: Double, spread: Double, decay: Double) -> Double {
        formula(axial: p.axial, radial: p.radial, outlet: outlet, radius: radius, spread: spread, decay: decay)
    }
    private static func metrics(_ samples: [Sample], outlet: Double, radius: Double, spread: Double, decay: Double) -> JetValidationMetrics {
        let errors = samples.map { abs(predict($0, outlet: outlet, radius: radius, spread: spread, decay: decay) - $0.measured) }
        return .init(sampleCount: samples.count, meanAbsoluteErrorMetersPerSecond: errors.reduce(0,+) / Double(errors.count),
            rootMeanSquaredErrorMetersPerSecond: sqrt(errors.reduce(0) { $0 + $1*$1 } / Double(errors.count)), maximumAbsoluteErrorMetersPerSecond: errors.max() ?? 0)
    }
}
