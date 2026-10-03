import SwiftUI

/// Quiet native surfaces; the small floor plan is the visual signature.
public enum RoomStyle {
    public static let ink = Color(red: 0.09, green: 0.24, blue: 0.29) // #173C49
    public static let air = Color(red: 0.08, green: 0.42, blue: 0.45) // #146A73
    public static let mist = Color(red: 0.92, green: 0.95, blue: 0.96) // #EAF3F4
    public static let slate = Color(red: 0.35, green: 0.43, blue: 0.46) // #596E76
    public static let caution = Color(red: 0.71, green: 0.44, blue: 0.09) // #B66F16
    public static let heading = Font.system(.title2, design: .rounded).weight(.semibold)
}

public struct RoomTheme: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public init() {}
    public func body(content: Content) -> some View {
        content.tint(colorScheme == .dark ? Color(red: 0.33, green: 0.72, blue: 0.75) : RoomStyle.air)
    }
}

public struct RoomPageIntro: View {
    let title: String
    let detail: String
    public init(_ title: String, detail: String) { self.title = title; self.detail = detail }
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(RoomStyle.heading)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// A floor plan, not a simulated field. Also explains the editor's screen-relative walls.
public struct RoomPlanMark: View {
    let classroom: Bool
    let showWalls: Bool
    public init(classroom: Bool = false, showWalls: Bool = false) {
        self.classroom = classroom; self.showWalls = showWalls
    }
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.5), lineWidth: 2)
                .padding(18)
            HStack(spacing: classroom ? 9 : 22) {
                ForEach(0..<(classroom ? 4 : 2), id: \.self) { _ in
                    VStack(spacing: 12) {
                        ForEach(0..<(classroom ? 3 : 2), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2).fill(RoomStyle.air.opacity(0.65))
                                .frame(width: 16, height: 10)
                        }
                    }
                }
            }
            if showWalls {
                Text("远侧墙").frame(maxHeight: .infinity, alignment: .top)
                Text("近侧墙").frame(maxHeight: .infinity, alignment: .bottom)
                HStack { Text("左"); Spacer(); Text("右") }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(width: 148, height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showWalls ? "俯视图：左墙、右墙、近侧墙、远侧墙；不代表东南西北" : "房间布局示意，不是计算结果")
    }
}
