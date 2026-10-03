import SwiftUI
import SimuCore

/// Shared temperature and flow legend so Canvas and RealityKit state the
/// same physical ranges. Arrow length is a display scale, not displacement.
struct ViewportLegend: View {
    var palette: SlicePalette?
    var flow: FlowOverlay?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let palette {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.color(forC: palette.minC),
                                    palette.color(forC: palette.minC + (palette.maxC - palette.minC) * 0.5),
                                    palette.color(forC: palette.maxC),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 120, height: 10)
                    Text(palette.legendText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let flow, let maxMag = flow.stats.maxMag {
                let minMag = flow.stats.minMag ?? 0
                Text("气流 \(UserFacingCopy.displayNumber(minMag))–\(UserFacingCopy.displayNumber(maxMag)) m/s。圆点沿流线循环是示意，箭头已放大，不是开机降温。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // The solver's simplifications, stated where the flow is shown:
                // windows are per-rectangle (P4-07), supply/return stay full-wall bands.
                Text("窗按实际墙面与宽度进入计算（每扇单独进网格）；送回风仍按整墙高度带进入计算（速度已按风量缩放），「送风」「回风」标注指该带，墙上空调只标位置。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let palette {
            parts.append("温度色标 \(palette.legendText)")
        }
        if let flow, let maxMag = flow.stats.maxMag {
            let minMag = flow.stats.minMag ?? 0
            parts.append("气流 \(UserFacingCopy.displayNumber(minMag)) 到 \(UserFacingCopy.displayNumber(maxMag)) 米每秒，圆点循环是示意流向")
            parts.append("墙上「送风」「回风」标注求解进风口与回风口，空调外形只标位置")
        }
        return parts.joined(separator: "，")
    }
}
