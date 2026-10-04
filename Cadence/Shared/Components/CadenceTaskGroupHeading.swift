import SwiftUI

/// A task group's heading: what the group is, in the group's own colour.
///
/// **The heading iOS's task surfaces share — Today, Inbox and All Tasks all draw this one row.**
/// It began as the settlement between `iOSTaskGroupHeader` and macOS's Today section header, which
/// were two spellings of one row disagreeing about more than measurements: iOS said what a group
/// *is* by tinting the label with the group's accent, macOS said it in neutral `Theme.dim`. The
/// accent is the point of an intent group — Overdue is red because it is overdue — so it wins.
///
/// **There is no count here any more, and the metrics type that measured one is gone with it
/// (T-2056).** The owner asked for the per-section count capsule off iOS and iPadOS, and then for
/// it off macOS as well so the two platforms keep saying the same thing. So the whole vocabulary
/// the capsule needed — the digits' size, the capsule's two paddings, the label-to-count gap, and
/// the T-264 rule about when a count may be drawn at all — is deleted rather than left inert. A
/// parameter kept but not rendered is how `subtitle` survived long enough to need deleting three
/// times; see `CadencePageHeaderMetrics`.
///
/// **What T-264 decided is not re-opened, it is answered the other way.** That ticket was never
/// about iPhone-against-iPad: it was "APPLE REMINDERS 0" standing over an access card, where the
/// app did not know the count and a capsule asserted one anyway. A heading that draws no count
/// cannot state a quantity nobody measured, on either platform, so the two headings have one
/// answer instead of one shared rule.
///
/// **macOS's Today is not one of its callers, and that is a decision (T-605).** Desktop draws
/// `TaskListGroupHeader` — 3×22pt bar, 14pt bold sentence case — because All Tasks, Inbox and list
/// detail beside it already did, and one desktop app with two group headings was the sharper
/// inconsistency. So the two platforms' headings still differ on purpose; **do not re-file that as
/// drift.** The reasoning is on `TasksPanelIntentSectionView`.
struct CadenceTaskGroupHeading: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let title: String
    let tint: Color

    var body: some View {
        let wraps = scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
        SectionEyebrowLabel(text: title, tint: tint)
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: wraps)
            // **Load-bearing, and not decoration (T-2056).** This row used to be an `HStack` of the
            // eyebrow, a `Spacer` and the count badge, and the `Spacer` is what made it span its
            // container. `iOSTaskGroupHeader` wraps it in `iOSNewTaskDropTarget`, whose
            // `.contentShape(Rectangle())` is documented against exactly this geometry — the whole
            // block takes a dropped `+`, not just the glyphs. Taking the capsule out without this
            // would have collapsed the heading to the width of its own text and shrunk the drop
            // target to match, which is the defect that `contentShape` was added to fix.
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
