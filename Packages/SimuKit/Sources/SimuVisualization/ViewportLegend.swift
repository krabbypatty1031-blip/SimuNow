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
                // Range numbers stay; the not-cooling caveat stays visible
                // (steady state must never read as start-up cooling).
                Text("气流 \(UserFacingCopy.displayNumber(minMag))–\(UserFacingCopy.displayNumber(maxMag)) m/s · 箭头已放大；圆点是示意流向，不是开机降温")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // The pointer to the (temporarily hidden, 2026-10-03) 计算过程
                // disclosure is removed so no visible text references a hidden
                // section. Restore it together with the WorkspaceView
                // disclosures (showsDetailDisclosures). The per-window /
                // full-wall-band modeling disclosure itself lives in 计算过程
                // and the 计算准备 inspector page.
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
            // Keep the not-cooling caveat for VoiceOver; modeling disclosure
            // lives in 计算过程 (hidden 2026-10-03), so the pointer line is
            // removed and the legend audio stays short too.
            parts.append("气流 \(UserFacingCopy.displayNumber(minMag)) 到 \(UserFacingCopy.displayNumber(maxMag)) 米每秒，箭头已放大，圆点是示意流向，不是开机降温")
        }
        return parts.joined(separator: "，")
    }
}
