import SwiftUI

/// Today's two past-due summary cards — one view each, both platforms (T-195, second half).
///
/// They were `TodayOverdueListCard` and `TodayOverdueSectionCard` under `macOS/Views/`. Nothing in
/// either is AppKit-shaped: an icon tile in the list's own `colorHex`, a title, one caption from
/// `CadenceOverdueSummaryPresentation`, and — on the section card — two counts. Bringing them here
/// rather than writing an iOS twin is the call `CompactTagStrip` records the cost of not making.
///
/// **The tap target is a closure, and that is the point.** macOS's action hops
/// `ListNavigationManager`, which is macOS-only; iOS's presents the list detail. Neither reaches
/// for a manager from inside the card, so the one genuinely platform-shaped piece of this feature
/// stays outside the shared view. What both sides agree on is `CadenceListOpenRequest`, which the
/// host builds from `CadenceTodayOverdueSummarySupport.openRequest(for:)`.

/// Shared chrome for both cards: a neutral surface with one hover layer at one radius.
///
/// It used to be a `Theme.red.opacity(0.08)` wash under `.cadencePlain`, whose blue hover fill and
/// stroke are drawn at radius 10 behind an opaque radius-18 card — a second hover layer at a second
/// radius, visible only as four coloured nicks at the corners. `.plain` plus the elevated resting
/// fill is the treatment the kanban cards and `CollapsibleTaskGroupHeader` already use.
private struct CadenceOverdueSummaryCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    /// The same two stops `TaskHoverVisuals.cardFill` gives macOS's task-like cards. Spelled here
    /// rather than imported because that enum is inside `#if os(macOS)`; `isHovered` can only ever
    /// be `true` on a platform that reports hover, so the resting value is what iOS draws.
    private var fill: Color {
        isHovered ? Theme.surfaceElevated : Theme.surface
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(16)
                .cadenceCard(
                    background: fill,
                    cornerRadius: Theme.radiusCard,
                    shadowRadius: 12,
                    shadowY: 5
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(CadenceOverdueSummaryHoverTracking(isHovered: $isHovered))
    }
}

/// The one seam in this file. Same shape as `CadenceHoverStyles`' own tracking modifier: a pointer
/// is a macOS affordance, and `onHover` on a touch surface reports nothing worth drawing.
private struct CadenceOverdueSummaryHoverTracking: ViewModifier {
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { isHovered = $0 }
        #else
        content
        #endif
    }
}

/// The caption both cards share, so they cannot drift apart on how a past due date reads.
struct CadenceOverdueSummaryCaption: View {
    let line: CadenceOverdueSummaryLine

    var body: some View {
        HStack(spacing: 0) {
            if let leadingDetail = line.leadingDetail {
                Text(leadingDetail).foregroundStyle(Theme.dim)
                Text(CadenceOverdueSummaryLine.separator).foregroundStyle(Theme.dim)
            }
            Text(line.dateText).foregroundStyle(line.dateTint)
            if let trailingDetail = line.trailingDetail {
                Text(CadenceOverdueSummaryLine.separator).foregroundStyle(Theme.dim)
                Text(trailingDetail).foregroundStyle(Theme.dim)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.plainText)
    }
}

/// The list's own `colorHex` icon stays coloured — that is identity the user chose, not state.
/// State is carried by the date alone.
struct CadenceTodayOverdueListCard: View {
    let summary: CadenceTodayOverdueListSummary
    let action: () -> Void

    var body: some View {
        CadenceOverdueSummaryCard(action: action) {
            HStack(spacing: 12) {
                CadenceOverdueSummaryIconTile(
                    systemImage: summary.icon,
                    colorHex: summary.colorHex
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    // No "List" chip beside this: the card is already sitting under a heading
                    // reading PAST DUE LISTS, so the chip was the same fact a third time.
                    CadenceOverdueSummaryCaption(
                        line: CadenceOverdueSummaryPresentation.line(
                            dueDateKey: summary.dueDateKey,
                            trailingDetail: CadenceOverdueSummaryPresentation.activeTaskDetail(
                                count: summary.activeTaskCount
                            )
                        )
                    )
                }

                Spacer()
            }
        }
    }
}

struct CadenceTodayOverdueSectionCard: View {
    let summary: CadenceTodayOverdueSectionSummary
    let action: () -> Void

    var body: some View {
        CadenceOverdueSummaryCard(action: action) {
            HStack(spacing: 12) {
                CadenceOverdueSummaryIconTile(
                    systemImage: summary.parentIcon,
                    colorHex: summary.parentColorHex
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.sectionName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    CadenceOverdueSummaryCaption(
                        line: CadenceOverdueSummaryPresentation.line(
                            dueDateKey: summary.dueDateKey,
                            leadingDetail: summary.parentName
                        )
                    )
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(summary.openTaskCount) open")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if summary.completedTaskCount > 0 {
                        Text("\(summary.completedTaskCount) done")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }
}

/// The list's glyph in the list's own colour. Not `CommitmentIconTile` / `iOSIconTile`: those are
/// larger identity tiles for rows and pickers, and this is a 30pt badge sized to a two-line card.
private struct CadenceOverdueSummaryIconTile: View {
    let systemImage: String
    let colorHex: String

    private var tint: Color {
        Color(hex: colorHex)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(tint.opacity(0.16))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

/// The heading over a run of either card — the eyebrow and its count.
///
/// Neutral rather than `Theme.red`: it used to be the third telling of "late" over rows that
/// already say so, above cards that said so twice more.
struct CadenceTodayOverdueSummaryHeading: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            SectionEyebrowLabel(text: title)

            // The count is the eyebrow's own size, not a point larger. It used to inherit an 11pt
            // font applied to the whole `HStack` — the one place in the app where the eyebrow tier
            // was 11 — so adopting the shared label dropped both to 10 together. That is the rule
            // `CadenceBoardColumnHeaderMetrics` and `CadenceTaskGroupHeadingMetrics.countSize`
            // already state: a count is demoted by weight and by its capsule, and must never be
            // bigger than the label it counts. No capsule here on purpose — this heading sits over
            // cards that already carry their own chrome.
            Text("\(count)")
                .font(.system(size: SectionEyebrowLabel.fontSize, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
    }
}
