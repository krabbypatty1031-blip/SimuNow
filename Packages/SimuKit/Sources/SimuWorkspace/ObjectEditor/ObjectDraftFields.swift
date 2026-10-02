import SwiftUI
import SimuCore

func objectNumber(_ text: String, label: String) throws -> Double {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
        throw ProjectDataError.contract("\(label)：请输入有限数字。")
    }
    return value
}
typealias ObjectParameterDraft = PhysicalParameterDraft
extension PhysicalParameterDraft {
    func parameter<Q: QuantityTag>(label: String, as: Q.Type = Q.self) throws -> PhysicalParameter<Q> {
        do { return try parameter(as: Q.self) }
        catch { throw ProjectDataError.contract("\(label)：\(error.localizedDescription)") }
    }
}
/// Keeps the object forms on the shared P2 parameter editor and its provenance rules.
struct ObjectParameterField: View {
    let title: String
    let unit: String
    @Binding var draft: PhysicalParameterDraft
    var body: some View {
        switch unit {
        case "m": PhysicalParameterEditor(title, draft: $draft, quantity: LengthTag.self, range: .positive)
        case "m²": PhysicalParameterEditor(title, draft: $draft, quantity: AreaTag.self, range: .positive)
        case "m³/s": PhysicalParameterEditor(title, draft: $draft, quantity: VolumeFlowTag.self, range: .nonnegative)
        case "m/s": PhysicalParameterEditor(title, draft: $draft, quantity: SpeedTag.self, range: .nonnegative)
        case "kg/m³": PhysicalParameterEditor(title, draft: $draft, quantity: DensityTag.self, range: .positive)
        case "°C": PhysicalParameterEditor(title, draft: $draft, quantity: TemperatureTag.self, range: .init(minimum: -273.15))
        case "met": PhysicalParameterEditor(title, draft: $draft, quantity: ActivityTag.self, range: .positive)
        case "clo": PhysicalParameterEditor(title, draft: $draft, quantity: ClothingTag.self, range: .nonnegative)
        case "0–1": PhysicalParameterEditor(title, draft: $draft, quantity: RatioTag.self, range: .fraction)
        case "COP": PhysicalParameterEditor(title, draft: $draft, quantity: RatioTag.self, range: .positive)
        default: PhysicalParameterEditor(title, draft: $draft, quantity: ThermalPowerTag.self, range: .nonnegative)
        }
    }
}
@ViewBuilder func objectTextField(_ title: String, text: Binding<String>) -> some View {
    TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(title)
}
struct ObjectPositionDraft: Equatable {
    var x: String; var y: String; var z: String
    init(_ p: Position3D) { x = String(p.x); y = String(p.y); z = String(p.z) }
    func position(label: String = "位置") throws -> Position3D {
        try .init(x: objectNumber(x, label: "\(label) X"), y: objectNumber(y, label: "\(label) Y"), z: objectNumber(z, label: "\(label) Z"))
    }
}
struct ObjectPositionFields: View {
    let title: String
    @Binding var draft: ObjectPositionDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            objectTextField("X（m）", text: $draft.x)
            objectTextField("Y（m）", text: $draft.y)
            objectTextField("Z（m）", text: $draft.z)
        }
    }
}
struct ObjectHeatDraft: Equatable {
    var sensible: ObjectParameterDraft
    var convective: ObjectParameterDraft
    var latent: ObjectParameterDraft
    init(_ gain: HeatGain) { sensible = .init(gain.sensible); convective = .init(gain.convectiveFraction); latent = .init(gain.latent) }
    func heat() throws -> HeatGain {
        try .init(sensible: sensible.parameter(label: "总显热"), convectiveFraction: convective.parameter(label: "对流比例"), latent: latent.parameter(label: "潜热"))
    }
}
struct ObjectHeatFields: View {
    @Binding var draft: ObjectHeatDraft
    var body: some View {
        ObjectParameterField(title: "总显热", unit: "W", draft: $draft.sensible)
        ObjectParameterField(title: "对流比例", unit: "0–1", draft: $draft.convective)
        ObjectParameterField(title: "潜热", unit: "W", draft: $draft.latent)
        Text("辐射显热由总显热 ×（1 − 对流比例）得到，不重复计入热源。未知参数会阻断计算准备。").font(.caption).foregroundStyle(.secondary)
    }
}
struct ObjectScheduleRow: Identifiable, Equatable {
    let id = UUID()
    var start: String
    var end: String
    var fraction: ObjectParameterDraft
    init(_ interval: ScheduleInterval) { start = String(interval.startMinute); end = String(interval.endMinute); fraction = .init(interval.fraction) }
    func interval() throws -> ScheduleInterval {
        guard let a = Int(start), let b = Int(end) else { throw ProjectDataError.contract("时间表起止分钟必须为整数。") }
        return try .init(startMinute: a, endMinute: b, fraction: fraction.parameter(label: "时间表比例"))
    }
}
struct ObjectScheduleDraft: Equatable {
    var rows: [ObjectScheduleRow]
    init(_ schedule: DailySchedule) { rows = schedule.intervals.map(ObjectScheduleRow.init) }
    func schedule() throws -> DailySchedule { try .init(intervals: rows.map { try $0.interval() }) }
}
struct ObjectScheduleFields: View {
    @Binding var draft: ObjectScheduleDraft
    var body: some View {
        Text("使用半开区间 [起始, 结束)，范围 0–1440 分钟。计算前应连续覆盖完整代表日。").font(.caption).foregroundStyle(.secondary)
        ForEach($draft.rows) { $row in
            VStack(alignment: .leading, spacing: 8) {
                objectTextField("起始分钟", text: $row.start)
                objectTextField("结束分钟", text: $row.end)
                ObjectParameterField(title: "启用 / 占用比例", unit: "0–1", draft: $row.fraction)
                Button("删除时间段", role: .destructive) { draft.rows.removeAll { $0.id == row.id } }
            }
        }
        Button("添加时间段", systemImage: "plus") {
            draft.rows.append(.init(.init(startMinute: 0, endMinute: 1440, fraction: .unknown(reason: "待确认使用条件"))))
        }
    }
}

struct ObjectRoomPicker: View {
    let project: ProjectDocument
    @Binding var roomID: UUID
    var body: some View {
        Picker("所属房间", selection: $roomID) {
            if !project.geometry.rooms.contains(where: { $0.id == roomID }) {
                Text("原房间不存在，待修复").tag(roomID)
            }
            ForEach(project.geometry.rooms, id: \.id) { room in Text(room.name).tag(room.id) }
        }
    }
}
