import Foundation
import CryptoKit
import SimuCore

/// A redacted derivative for sharing, deliberately unsuitable for fitting a spatial model.
public enum MeasurementSummaryExporter {
    private struct Row: Encodable {
        let quantity: MeasurementQuantity
        let value: Double?
        let unit: String
        let quality: MeasurementQuality
        let partition: MeasurementPartition
        let deviceAlias: String?
        let instrumentAlias: String
        let fanAlias: String
        let doorState: OpeningObservation
        let windowState: OpeningObservation
    }
    private struct Snapshot: Encodable {
        let summaryVersion = 1
        let sourceSHA256: String
        let records: [Row]
        let rejectedRowCount: Int
        let redactedFields = ["projectID", "datasetID", "recordIDs", "deviceIDs", "positions", "timestamps", "instrumentNames", "instrumentNotes", "fanNames", "qualityFreeText", "importFreeText"]
        let limitations = ["这是匿名测量摘要，位置与绝对时间已移除，不能据此校准空间模型。", "sourceSHA256 仅用于追溯原始来源，不能从删减摘要重算原文件哈希。"]
    }
    private struct Envelope: Encodable {
        let owner = "com.simunow.redacted-measurements"
        let exportVersion = 1
        let hashFormat = "sha256.sorted-json.v1"
        let exportHash: String
        let snapshot: Snapshot
    }
    public static func export(_ dataset: MeasurementDataset) throws -> Data {
        try WireSchema.validate(JSONTreeCoding.encode(dataset), schema: NativeAnalysisCodec.schema(.measurementDataset))
        guard dataset.records.allSatisfy({ $0.unit == $0.quantity.unit && ($0.value?.isFinite ?? true) }) else {
            throw ProjectDataError.contract("测量单位或数值不符合摘要契约。")
        }
        let devices = Array(Set(dataset.records.compactMap(\.deviceID))).sorted { $0.uuidString < $1.uuidString }
        let instruments = Array(Set(dataset.records.map(\.instrument))).sorted()
        let fans = Array(Set(dataset.records.map(\.fanSetting))).sorted()
        let rows = dataset.records.map { row in
            Row(quantity: row.quantity, value: row.value, unit: row.unit, quality: row.quality, partition: row.partition,
                deviceAlias: row.deviceID.flatMap { devices.firstIndex(of: $0).map { "设备\($0 + 1)" } },
                instrumentAlias: "仪表\((instruments.firstIndex(of: row.instrument) ?? 0) + 1)",
                fanAlias: row.fanSetting == "unknown" ? "未知" : "风档\((fans.firstIndex(of: row.fanSetting) ?? 0) + 1)",
                doorState: row.doorState, windowState: row.windowState)
        }
        let snapshot = Snapshot(sourceSHA256: dataset.sourceSHA256, records: rows, rejectedRowCount: dataset.issues.count)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(snapshot)
        guard bytes.count <= 4 * 1024 * 1024 else { throw ProjectDataError.contract("匿名摘要超过 4 MiB 上限。") }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let data = try encoder.encode(Envelope(exportHash: hash, snapshot: snapshot))
        try WireSchema.validate(JSONValue(data: data), schema: NativeAnalysisCodec.schema(.redactedMeasurements))
        return data
    }
}
