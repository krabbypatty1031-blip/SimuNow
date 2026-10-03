import Foundation

public enum MeasurementQuantity: String, Codable, CaseIterable, Sendable {
    case airSpeed, outletSpeed, outletFlow, temperature, electricalPower, relativeHumidity, co2
    public var unit: String {
        switch self {
        case .airSpeed, .outletSpeed: "m/s"
        case .outletFlow: "m3/s"
        case .temperature: "degC"
        case .electricalPower: "W"
        case .relativeHumidity: "%"
        case .co2: "ppm"
        }
    }
    public var title: String {
        switch self {
        case .airSpeed: "位置风速"; case .outletSpeed: "出口风速"; case .outletFlow: "出口风量"
        case .temperature: "温度"; case .electricalPower: "电功率"; case .relativeHumidity: "相对湿度"; case .co2: "CO₂ 浓度"
        }
    }
}
public enum MeasurementQuality: String, Codable, CaseIterable, Sendable { case valid, suspect, missing, rejected }
public enum MeasurementPartition: String, Codable, CaseIterable, Sendable { case calibration, validation, unassigned }
public enum OpeningObservation: String, Codable, CaseIterable, Sendable { case open, closed, unknown }
public struct MeasurementRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: String
    public let position: Position3D?
    public let quantity: MeasurementQuantity
    public let value: Double?
    public let unit: String
    public let instrument: String
    public let instrumentRange: String?
    public let instrumentCalibration: String?
    public let quality: MeasurementQuality
    public let qualityReason: String?
    public let fanSetting: String
    public let doorState: OpeningObservation
    public let windowState: OpeningObservation
    public let partition: MeasurementPartition
    public let deviceID: UUID?
    public init(id: UUID = UUID(), timestamp: String, position: Position3D?, quantity: MeasurementQuantity,
                value: Double?, instrument: String, instrumentRange: String? = nil, instrumentCalibration: String? = nil,
                quality: MeasurementQuality, qualityReason: String? = nil, fanSetting: String,
                doorState: OpeningObservation, windowState: OpeningObservation, partition: MeasurementPartition, deviceID: UUID?) {
        self.id = id; self.timestamp = timestamp; self.position = position; self.quantity = quantity
        self.value = value; unit = quantity.unit; self.instrument = instrument
        self.instrumentRange = instrumentRange; self.instrumentCalibration = instrumentCalibration
        self.quality = quality; self.qualityReason = qualityReason; self.fanSetting = fanSetting
        self.doorState = doorState; self.windowState = windowState; self.partition = partition; self.deviceID = deviceID
    }
}
public struct MeasurementImportIssue: Codable, Equatable, Sendable {
    public let row: Int
    public let code: String
    public let message: String
    public init(row: Int, code: String, message: String) { self.row = row; self.code = code; self.message = message }
}
public struct MeasurementDataset: Codable, Equatable, Sendable, Identifiable {
    public let datasetVersion: Int
    public let owner: String
    public let id: UUID
    public let projectID: UUID
    public let sourceSHA256: String
    public let coordinateSystem: String
    public let records: [MeasurementRecord]
    public let issues: [MeasurementImportIssue]
    public init(id: UUID = UUID(), projectID: UUID, sourceSHA256: String, records: [MeasurementRecord], issues: [MeasurementImportIssue]) {
        datasetVersion = 1; owner = "com.simunow.measurements"; self.id = id; self.projectID = projectID
        self.sourceSHA256 = sourceSHA256; coordinateSystem = "rightHandedZUp"; self.records = records; self.issues = issues
    }
}

public struct JetValidationMetrics: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let meanAbsoluteErrorMetersPerSecond: Double
    public let rootMeanSquaredErrorMetersPerSecond: Double
    public let maximumAbsoluteErrorMetersPerSecond: Double
    public init(sampleCount: Int, meanAbsoluteErrorMetersPerSecond: Double, rootMeanSquaredErrorMetersPerSecond: Double, maximumAbsoluteErrorMetersPerSecond: Double) {
        self.sampleCount = sampleCount; self.meanAbsoluteErrorMetersPerSecond = meanAbsoluteErrorMetersPerSecond
        self.rootMeanSquaredErrorMetersPerSecond = rootMeanSquaredErrorMetersPerSecond
        self.maximumAbsoluteErrorMetersPerSecond = maximumAbsoluteErrorMetersPerSecond
    }
}
/// An experimental model scoped to one project/device and measured installation, never a preview upgrade.
public struct JetCalibrationRecord: Codable, Equatable, Sendable, Identifiable {
    public let calibrationVersion: Int
    public let method: String
    public let id: UUID
    public let projectID: UUID
    public let datasetID: UUID
    public let datasetSHA256: String
    public let deviceID: UUID
    public let geometrySHA256: String
    public let origin: Position3D
    public let direction: Direction3D
    public let outletSpeedMetersPerSecond: Double
    public let outletRadiusMeters: Double
    public let spreadingRate: Double
    public let decayRatePerMeter: Double
    public let fanSetting: String
    public let calibrationIDs: [UUID]
    public let validationIDs: [UUID]
    public let calibrationMetrics: JetValidationMetrics
    public let validationMetrics: JetValidationMetrics
    public let uncalibratedValidationMetrics: JetValidationMetrics
    public let maximumDistanceMeters: Double
    public let minimumDistanceMeters: Double
    public let maximumRadialDistanceMeters: Double
    public let maximumValidationRMSE: Double
    public let acceptedForScopedResearch: Bool
    public let limitations: [String]
    public init(id: UUID = UUID(), projectID: UUID, datasetID: UUID, datasetSHA256: String, deviceID: UUID, geometrySHA256: String,
                origin: Position3D, direction: Direction3D, outletSpeedMetersPerSecond: Double, outletRadiusMeters: Double,
                spreadingRate: Double, decayRatePerMeter: Double, fanSetting: String, calibrationIDs: [UUID], validationIDs: [UUID],
                calibrationMetrics: JetValidationMetrics, validationMetrics: JetValidationMetrics,
                uncalibratedValidationMetrics: JetValidationMetrics, maximumDistanceMeters: Double, minimumDistanceMeters: Double,
                maximumRadialDistanceMeters: Double, maximumValidationRMSE: Double, acceptedForScopedResearch: Bool) {
        calibrationVersion = 1; method = "simunow.experimental.finiteJet.v1"; self.id = id
        self.projectID = projectID; self.datasetID = datasetID; self.datasetSHA256 = datasetSHA256; self.deviceID = deviceID
        self.geometrySHA256 = geometrySHA256
        self.origin = origin; self.direction = direction; self.outletSpeedMetersPerSecond = outletSpeedMetersPerSecond
        self.outletRadiusMeters = outletRadiusMeters; self.spreadingRate = spreadingRate; self.decayRatePerMeter = decayRatePerMeter
        self.fanSetting = fanSetting; self.calibrationIDs = calibrationIDs; self.validationIDs = validationIDs
        self.calibrationMetrics = calibrationMetrics; self.validationMetrics = validationMetrics
        self.uncalibratedValidationMetrics = uncalibratedValidationMetrics; self.maximumDistanceMeters = maximumDistanceMeters
        self.minimumDistanceMeters = minimumDistanceMeters; self.maximumRadialDistanceMeters = maximumRadialDistanceMeters
        self.maximumValidationRMSE = maximumValidationRMSE
        self.acceptedForScopedResearch = acceptedForScopedResearch
        limitations = ["仅适用于记录的房间、设备、安装方向、风档和实测距离范围。", "自由射流实验不含家具绕流、贴壁、回流、浮力或舒适；不得覆盖原规则结果。", "独立实测与仪表质量需另行验收；模型门槛通过不代表通用物理验证。"]
    }
}
