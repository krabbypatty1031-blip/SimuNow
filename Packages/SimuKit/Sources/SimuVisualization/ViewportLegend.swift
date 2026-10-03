import SwiftUI
import SimuCore

/// Shared temperature and flow legend so Canvas and RealityKit state the
/// same physical ranges. Arrow length is a display scale, not displacement.
struct ViewportLegend: View {
    var palette: SlicePalette?
    var flow: FlowOverlay?
    @Environment(\.userFacingCopy) private var copy

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
                    Text(palette.legendText(copy))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let flow, let maxMag = flow.stats.maxMag {
                let minMag = flow.stats.minMag ?? 0
                Text(copy.legendFlow(min: UserFacingCopy.displayNumber(minMag), max: UserFacingCopy.displayNumber(maxMag)))
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
            parts.append(copy.legendTemperatureAccessibility(palette.legendText(copy)))
        }
        if let flow, let maxMag = flow.stats.maxMag {
            let minMag = flow.stats.minMag ?? 0
            parts.append(copy.legendFlowAccessibility(
                min: UserFacingCopy.displayNumber(minMag),
                max: UserFacingCopy.displayNumber(maxMag)
            ))
        }
        return parts.joined(separator: copy.language == .chinese ? "，" : ", ")
    }
}
