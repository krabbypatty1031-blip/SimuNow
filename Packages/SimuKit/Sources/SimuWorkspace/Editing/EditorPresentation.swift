import SwiftUI
import SimuCore

/// Ephemeral navigation only. No presentation state enters project or analysis input.
struct EditorFocus: Equatable, Sendable {
    var entityID: UUID?
    var field: String?
    var ordinal: Int? = nil
}
private struct EditorFocusKey: EnvironmentKey {
    static let defaultValue = EditorFocus()
}
private struct EditorEntityKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
private struct EditorOrdinalKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}
struct EditorFieldAnchor: Hashable {
    var entityID: UUID?
    var field: String
    var ordinal: Int? = nil
}
extension EnvironmentValues {
    var editorFocus: EditorFocus {
        get { self[EditorFocusKey.self] }
        set { self[EditorFocusKey.self] = newValue }
    }
    var editorEntityID: UUID? {
        get { self[EditorEntityKey.self] }
        set { self[EditorEntityKey.self] = newValue }
    }
    var editorFieldOrdinal: Int? {
        get { self[EditorOrdinalKey.self] }
        set { self[EditorOrdinalKey.self] = newValue }
    }
}

struct EditorSheetSize: ViewModifier {
    var compact = false
    func body(content: Content) -> some View {
        #if os(macOS)
        content.frame(minWidth: compact ? 360 : 480, idealWidth: compact ? 440 : 640,
                      maxWidth: 960, minHeight: compact ? 200 : 360,
                      idealHeight: compact ? 260 : 540, maxHeight: 720)
        #else
        content
        #endif
    }
}

/// Bounded scroll area; toolbar remains outside it. Leading labels never depend on
/// macOS Form's label-column sizing, which clipped long Chinese labels.
struct EditorForm<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @SwiftUI.Environment(\.editorFocus) private var focus
    @SwiftUI.Environment(\.editorEntityID) private var entityID
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: focus) {
                // Let the selected disclosure mount its fields before locating them.
                await Task.yield()
                guard !Task.isCancelled else { return }
                if let id = focus.entityID { proxy.scrollTo(id, anchor: .top) }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if let field = focus.field {
                    proxy.scrollTo(EditorFieldAnchor(entityID: focus.entityID ?? entityID, field: field, ordinal: focus.ordinal), anchor: .top)
                }
            }
        }
    }
}

struct EditorTextField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @SwiftUI.Environment(\.editorFocus) private var focus
    @SwiftUI.Environment(\.editorEntityID) private var entityID
    @SwiftUI.Environment(\.editorFieldOrdinal) private var ordinal
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            TextField(title, text: $text).labelsHidden().textFieldStyle(.roundedBorder)
                .accessibilityLabel(title).focused($focused)
        }
        .id(EditorFieldAnchor(entityID: entityID, field: title, ordinal: ordinal))
        .onChange(of: focus, initial: true) { _, value in
            if value.field == title, value.entityID == nil || value.entityID == entityID,
               value.ordinal == ordinal { focused = true }
        }
    }
}

struct EditorSection<Content: View>: View {
    var title: String = ""
    @ViewBuilder let content: () -> Content
    init(_ title: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty { Text(title).font(.headline).fixedSize(horizontal: false, vertical: true) }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EditorDisclosure<Content: View>: View {
    let title: String
    var entityID: UUID? = nil
    var initiallyExpanded = false
    var fields: [String] = []
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    @SwiftUI.Environment(\.editorFocus) private var focus
    @SwiftUI.Environment(\.editorEntityID) private var parentEntityID
    var body: some View {
        Group {
            if let entityID { disclosure.id(entityID) }
            else { disclosure }
        }
        .onChange(of: focus, initial: true) { _, value in
            if initiallyExpanded || entityID != nil && value.entityID == entityID
                || (value.entityID == nil || value.entityID == (entityID ?? parentEntityID))
                    && value.field.map(fields.contains) == true { expanded = true }
        }
        .onChange(of: initiallyExpanded) { _, value in if value { expanded = true } }
    }
    private var disclosure: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) { content() }.padding(.top, 8)
                .environment(\.editorEntityID, entityID ?? parentEntityID)
        }
    }
}

struct MethodBoundaryView: View {
    var body: some View {
        Label("几何规则预览 · 未校准", systemImage: "info.circle").font(.caption)
            .help("只显示假设路径及首次遮挡；不能评价真实风速、温度、舒适或节能。")
    }
}

struct ClockMinuteField: View {
    let title: String
    @Binding var text: String
    @State private var editingText: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EditorTextField(title: title + "（HH:mm）", text: Binding(
                get: { editingText ?? InputDisplay.clock(text) },
                set: { editingText = $0; text = InputDisplay.minuteText($0) }))
            if InputDisplay.minutes(text) == nil {
                Label("请输入 00:00–24:00；24:00 仅用于时段结束。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: text) { _, value in
            if let editingText, InputDisplay.minuteText(editingText) != value { self.editingText = nil }
        }
    }
}

/// Incomplete text is retained. These conversions never replace invalid input with zero.
public enum InputDisplay {
    public static func minutes(_ text: String) -> Int? {
        guard let value = Int(text), (0...1440).contains(value) else { return nil }
        return value
    }
    public static func clock(_ text: String) -> String {
        guard let value = minutes(text) else { return text }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    public static func minuteText(_ text: String) -> String {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute), hour < 24 || minute == 0 else { return text }
        return String(hour * 60 + minute)
    }
    public static func source(_ kind: ParameterSource) -> String {
        switch kind {
        case .user: "用户输入"
        case .measured: "实测"
        case .manufacturer: "厂家资料"
        case .preset: "有来源预设"
        case .assumed: "假设"
        case .scan: "扫描"
        }
    }
    public static func unit(_ wire: String) -> String {
        switch wire {
        case "degC": "°C"
        case "deg": "°"
        case "m3/s": "m³/s"
        case "m2": "m²"
        case "kg/m3": "kg/m³"
        case "W/(m2.K)": "W/(m²·K)"
        case "W/m2": "W/m²"
        case "currency": "币种金额"
        case "currency/kWh": "币种/kWh"
        default: wire
        }
    }
    public static func powerBasis(_ basis: ElectricalPowerBasis) -> String {
        switch basis { case .measuredAverage: "实测平均功率"; case .declaredScenario: "明确采用的功率情景"; case .ratedContinuous: "额定功率连续运行" }
    }
    public static func equipment(_ id: UUID) -> String { "热源 · " + id.uuidString.prefix(6) }
}

struct RepresentativeDayField: View {
    @Binding var text: String
    @SwiftUI.Environment(\.editorEntityID) private var entityID
    private var formatter: DateFormatter {
        let value = DateFormatter()
        value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = .current
        value.dateFormat = "yyyy-MM-dd"; value.isLenient = false
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("记录代表日", isOn: Binding(get: { !text.isEmpty }, set: { value in
                text = value ? formatter.string(from: Date()) : ""
            }))
            if !text.isEmpty {
                DatePicker("代表日", selection: Binding(get: { formatter.date(from: text) ?? Date() },
                    set: { text = formatter.string(from: $0) }), displayedComponents: .date)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                    .environment(\.timeZone, TimeZone.current)
                if formatter.date(from: text) == nil { Label("原日期无效：" + text + "；请选择有效日期。", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            } else { Text("代表日未知；规则预览无需代表日。").font(.caption).foregroundStyle(.secondary) }
        }.id(EditorFieldAnchor(entityID: entityID, field: "代表日"))
    }
}
