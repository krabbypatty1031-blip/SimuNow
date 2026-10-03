import SwiftUI

/// A wrapping row layout: items stay on one leading-aligned row while they
/// fit and fold to the next line only when the width runs out.
///
/// Why not a plain HStack: an HStack never wraps, so a row of buttons wider
/// than its container is clipped at the trailing edge instead of folding
/// (2026-10-04: the four furniture add-buttons in the macOS inspector lost
/// half of 添加柜子 and all of 添加屏风). Why not a VStack: the buttons were
/// asked for as a leading horizontal row, so the layout keeps the single row
/// on every width that fits it — iPhone full width and a wide inspector
/// collapse to one line, a narrow inspector column folds to two.
///
/// The `Layout` protocol needs macOS 13 / iOS 16, below the package's
/// macOS 14 / iOS 17 floor, so no availability guard is required.
public struct FlowLayout: Layout {
    /// Gap between neighbours, horizontal and between folded lines.
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    /// Shared line-breaking pass: measuring and placing run the exact same
    /// computation, so the two passes can never disagree about where a fold
    /// happens (same rule as the plan view's screen↔metres transform).
    ///
    /// `width` is the fold limit; `.infinity` keeps everything on one line.
    private func placements(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        for subview in subviews {
            // Ideal size: buttons keep their intrinsic label width here,
            // which is what `.fixedSize()` guarantees at the call site.
            let size = subview.sizeThatFits(.unspecified)
            // Fold before placing, never after: an item that would cross the
            // limit starts the next line. The first item on a line never
            // folds, so one over-wide item cannot loop or vanish.
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            contentWidth = max(contentWidth, frames[frames.count - 1].maxX)
        }
        return (frames, CGSize(width: contentWidth, height: y + lineHeight))
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // No proposed width means no fold limit: report the one-line size.
        let width = proposal.width ?? .infinity
        return placements(width: width, subviews: subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Same width source as sizeThatFits (proposal, not bounds), so a
        // parent that stretches the laid-out view keeps the measured folds.
        let width = proposal.width ?? .infinity
        let frames = placements(width: width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}
