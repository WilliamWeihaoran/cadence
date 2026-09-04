import SwiftUI

/// An `HStack` that wraps onto further lines instead of overflowing or scrolling.
///
/// Reach for this wherever a variable number of small chips has to fit a width you do not control.
/// The alternative that keeps appearing — a horizontal `ScrollView` — does not survive being
/// nested inside another scroll view under a tap gesture: the outer gestures win and the strip
/// silently stops scrolling, which is exactly how `iOSTaskRow`'s metadata became unreachable.
///
/// The line-breaking is `CadenceFlowLayoutSupport`, which is unfenced and unit-tested.
///
/// **This type itself is untestable by construction, not merely untested (T-883).** `Layout`'s
/// `Subviews` has no public initialiser, so nothing outside SwiftUI's own layout pass can construct
/// one to drive `sizeThatFits`/`placeSubviews` from a unit test — there is no seam, the way
/// `CadenceEmptyStateAuditTests` and `CadencePrivacyDataResetSurfaceTests` document for their own
/// no-seam cases. Both entry points delegate every line-breaking decision to
/// `CadenceFlowLayoutSupport`, which owns the actual test suite
/// (`CadenceFlowLayoutSupportTests.swift`). The one calculation that stays local — `itemSizes`'
/// per-item width clamp, below — is equally unreachable, for the same reason. None of that makes
/// this file dead: six `Cadence/iOS/` files call it across nine sites (`iOSTaskViews.swift`,
/// `iOSTrackingEditorComponents.swift`, `iOSAINoteActionsViews.swift`, `iOSFeatureDetailViews.swift`,
/// `iOSInboxRemindersSection.swift`, `iOSTaskDetailComponents.swift`). A future "which files have no
/// test" sweep should read this comment before re-filing the gap — it is an adapter with no seam,
/// already fully covered at the layer that can be covered.
struct CadenceWrappingHStack: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let sizes = itemSizes(for: subviews, width: proposal.width)
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes,
            availableWidth: proposal.width ?? .infinity,
            spacing: spacing
        )
        return CadenceFlowLayoutSupport.size(ofLines: lines, lineSpacing: lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let sizes = itemSizes(for: subviews, width: bounds.width)
        let lines = CadenceFlowLayoutSupport.lines(
            itemSizes: sizes,
            availableWidth: bounds.width,
            spacing: spacing
        )
        let points = CadenceFlowLayoutSupport.placements(
            itemSizes: sizes,
            lines: lines,
            origin: bounds.origin,
            spacing: spacing,
            lineSpacing: lineSpacing
        )

        for index in subviews.indices {
            subviews[index].place(
                at: points[index],
                anchor: .topLeading,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }

    /// Each subview at its natural size, clamped to the available width.
    ///
    /// The clamp is what stops one long chip — a goal with a wordy title — from running off the
    /// edge. It truncates instead, which its own `lineLimit(1)` already expects.
    private func itemSizes(for subviews: Subviews, width: CGFloat?) -> [CGSize] {
        let limit = (width?.isFinite ?? false) ? width! : CGFloat.infinity
        return subviews.map { subview in
            let natural = subview.sizeThatFits(.unspecified)
            guard limit.isFinite, natural.width > limit else { return natural }
            return subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
        }
    }
}
