import Foundation
import SimuCore

public enum MeasurementCSVImporter {
    public static let maximumBytes = 4 * 1024 * 1024
    public static let maximumRecords = 10_000
    public static let template = "timestamp,x,y,z,quantity,value,unit,instrument,quality,quality_reason,fan_setting,door_state,window_state,partition,device_id,instrument_range,instrument_calibration\n"
    public static func importCSV(_ data: Data, projectID: UUID) throws -> MeasurementDataset {
        guard data.count <= maximumBytes, var text = String(data: data, encoding: .utf8) else { throw ProjectDataError.contract("测量 CSV 必须是至多 4 MiB 的 UTF-8 文件。") }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let rows = try parse(text)
        guard let header = rows.first, Set(header).count == header.count else { throw ProjectDataError.contract("CSV 字段名缺失或重复。") }
        let required = ["timestamp", "quantity", "value", "unit", "instrument", "quality", "fan_setting", "door_state", "window_state", "partition"]
        guard required.allSatisfy(header.contains) else { throw ProjectDataError.contract("CSV 需要字段：\(required.joined(separator: ","))。可从模板开始。") }
        var records: [MeasurementRecord] = []; var issues: [MeasurementImportIssue] = []
        for (index, row) in rows.dropFirst().enumerated() {
            try Task.checkCancellation()
            if row.allSatisfy(\.isEmpty) { continue }
            guard index < maximumRecords else { throw ProjectDataError.contract("测量最多 10000 行。") }
            do {
                guard row.count == header.count else { throw ProjectDataError.contract("列数与表头不同。") }
                let fields = Dictionary(uniqueKeysWithValues: zip(header, row))
                func field(_ name: String) -> String { (fields[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                func optional(_ name: String) -> String? { let value = field(name); return value.isEmpty ? nil : value }
                guard let quantity = MeasurementQuantity(rawValue: field("quantity")),
                      let quality = MeasurementQuality(rawValue: field("quality")),
                      let partition = MeasurementPartition(rawValue: field("partition")),
                      let door = OpeningObservation(rawValue: field("door_state")), let window = OpeningObservation(rawValue: field("window_state")) else {
                    throw ProjectDataError.contract("测量类型、质量、数据分组或门窗状态未知。")
                }
                guard MeasurementDatasetCodec.timestamp(field("timestamp")) != nil else { throw ProjectDataError.contract("时间需为含 Z 或明确时区偏移的 ISO 8601；本地时间不能静默解释。") }
                guard !field("instrument").isEmpty, !field("fan_setting").isEmpty else { throw ProjectDataError.contract("请记录仪表及风档；未知风档可显式写 unknown。") }
                let value: Double?
                if let raw = optional("value") {
                    guard let number = Double(raw), number.isFinite else { throw ProjectDataError.contract("数值不是有限数字；缺失不能填零。") }
                    value = try convert(number, quantity: quantity, unit: field("unit"))
                } else {
                    guard quality == .missing || quality == .rejected else { throw ProjectDataError.contract("缺失数值需标记 missing 或 rejected 并说明原因。") }; value = nil
                }
                if quality != .valid, optional("quality_reason") == nil { throw ProjectDataError.contract("非有效测量需要质量原因。") }
                let coordinates = [field("x"), field("y"), field("z")]
                let position: Position3D?
                if coordinates.allSatisfy(\.isEmpty) { position = nil }
                else {
                    let values = coordinates.compactMap(Double.init)
                    guard values.count == 3, values.allSatisfy(\.isFinite) else { throw ProjectDataError.contract("位置需完整有限 x/y/z，单位 m，右手 Z-up。") }
                    position = .init(x: values[0], y: values[1], z: values[2])
                }
                let device: UUID?
                if let raw = optional("device_id") { guard let id = UUID(uuidString: raw) else { throw ProjectDataError.contract("device_id 不是 UUID。") }; device = id } else { device = nil }
                let record = MeasurementRecord(timestamp: field("timestamp"), position: position, quantity: quantity, value: value,
                    instrument: field("instrument"), instrumentRange: optional("instrument_range"), instrumentCalibration: optional("instrument_calibration"),
                    quality: quality, qualityReason: optional("quality_reason"), fanSetting: field("fan_setting"), doorState: door,
                    windowState: window, partition: partition, deviceID: device)
                try MeasurementDatasetCodec.validate(record)
                records.append(record)
            } catch { issues.append(.init(row: index + 2, code: "row_rejected", message: error.localizedDescription)) }
        }
        return .init(projectID: projectID, sourceSHA256: AnalysisHasher.sha256(data), records: records, issues: issues)
    }
    private static func convert(_ value: Double, quantity: MeasurementQuantity, unit: String) throws -> Double {
        if unit == quantity.unit { return value }
        switch (quantity, unit) {
        case (.temperature, "K"): return value - 273.15
        case (.temperature, "degF"): return (value - 32) * 5 / 9
        case (.electricalPower, "kW"): return value * 1000
        case (.airSpeed, "km/h"), (.outletSpeed, "km/h"): return value / 3.6
        case (.outletFlow, "L/s"): return value / 1000
        case (.outletFlow, "m3/h"): return value / 3600
        default: throw ProjectDataError.contract("单位 \(unit) 不适用于 \(quantity.title)。")
        }
    }
    /// RFC 4180-style quoting, CRLF and embedded newlines; malformed quotes fail the import atomically.
    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []; var row: [String] = []; var field = ""
        var quoted = false; var endedQuote = false; var started = false
        let characters = Array(text); var i = 0
        while i < characters.count {
            if i % 4096 == 0 { try Task.checkCancellation() }
            let c = characters[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < characters.count, characters[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; endedQuote = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; started = false; endedQuote = false }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field); rows.append(row); row = []; field = ""; started = false; endedQuote = false
                if c == "\r", i + 1 < characters.count, characters[i + 1] == "\n" { i += 1 }
                guard rows.count <= maximumRecords + 1 else { throw ProjectDataError.contract("测量最多 10000 行。") }
            } else if c == "\"" {
                guard !started, !endedQuote, field.isEmpty else { throw ProjectDataError.contract("CSV 引号位置错误。") }
                quoted = true; started = true
            } else {
                guard !endedQuote else { throw ProjectDataError.contract("CSV 闭引号后存在非分隔字符。") }
                started = true; field.append(c)
            }
            i += 1
        }
        guard !quoted else { throw ProjectDataError.contract("CSV 引号没有闭合。") }
        if !field.isEmpty || !row.isEmpty || started { row.append(field); rows.append(row) }
        return rows
    }
}

public enum MeasurementDatasetCodec {
    public static func timestamp(_ value: String) -> Date? {
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$", options: .regularExpression) != nil else { return nil }
        let components = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard components.count == 3, components[0] > 0, (1...12).contains(components[1]) else { return nil }
        let year = components[0], leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[components[1] - 1]).contains(components[2]) else { return nil }
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: value) { return date }
        format.formatOptions = [.withInternetDateTime]; return format.date(from: value)
    }
    public static func validate(_ value: MeasurementRecord) throws {
        guard timestamp(value.timestamp) != nil, value.unit == value.quantity.unit,
              !value.instrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.fanSetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.quality == .valid || value.qualityReason?.isEmpty == false,
              value.quality != .valid || value.value != nil,
              value.quality != .missing || value.value == nil else { throw ProjectDataError.contract("测量来源、单位、时间或质量标记不完整。") }
        if let position = value.position { guard [position.x, position.y, position.z].allSatisfy(\.isFinite) else { throw ProjectDataError.contract("测量位置非有限。") } }
        if let number = value.value {
            guard number.isFinite, value.quantity == .temperature ? number >= -273.15 : number >= 0,
                  value.quantity != .relativeHumidity || number <= 100 else { throw ProjectDataError.contract("测量数值超出物理范围。") }
        }
    }
    public static func encode(_ dataset: MeasurementDataset) throws -> Data {
        try validate(dataset)
        let tree = try JSONTreeCoding.encode(dataset)
        try WireSchema.validate(tree, schema: NativeAnalysisCodec.schema(.measurementDataset))
        let data = try tree.data()
        guard data.count <= 8 * 1024 * 1024 else { throw ProjectDataError.contract("测量记录超过 8 MiB。") }; return data
    }
    public static func decode(_ data: Data) throws -> MeasurementDataset {
        guard data.count <= 8 * 1024 * 1024 else { throw ProjectDataError.contract("测量记录超过 8 MiB。") }
        let tree = try JSONValue(data: data)
        try WireSchema.validate(tree, schema: NativeAnalysisCodec.schema(.measurementDataset))
        let value = try JSONTreeCoding.decode(MeasurementDataset.self, from: tree)
        try validate(value); return value
    }
    private static func validate(_ dataset: MeasurementDataset) throws {
        guard dataset.datasetVersion == 1, dataset.owner == "com.simunow.measurements", dataset.coordinateSystem == "rightHandedZUp",
              dataset.records.count <= MeasurementCSVImporter.maximumRecords, dataset.issues.count <= MeasurementCSVImporter.maximumRecords,
              Set(dataset.records.map(\.id)).count == dataset.records.count,
              dataset.sourceSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw ProjectDataError.contract("不支持的测量版本、身份或预算。") }
        for record in dataset.records { try Task.checkCancellation(); try validate(record) }
    }
}
