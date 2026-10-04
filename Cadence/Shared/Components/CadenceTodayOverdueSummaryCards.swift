import SwiftUI

nonisolated enum CadenceOverdueSummaryMetrics {
    static func iconSide(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        CadenceTypeScale.height(30, holding: .controlLabel, at: size, scaling: scaling)
    }
}

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
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let line: CadenceOverdueSummaryLine

    var body: some View {
        let wraps = scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
        Group {
            if wraps {
                Text(Self.attributedCaption(line))
            } else {
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
            }
        }
        .cadenceFont(.metadata, base: 11, weight: .regular)
        .lineLimit(wraps ? nil : 1)
        .fixedSize(horizontal: false, vertical: wraps)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.plainText)
    }

    /// One wrapping line, with only the deadline tinted; the fixed layout above stays unchanged.
    static func attributedCaption(_ line: CadenceOverdueSummaryLine) -> AttributedString {
        var result = AttributedString()
        let segments: [(String?, Color)] = [
            (line.leadingDetail, Theme.dim), (line.dateText, line.dateTint), (line.trailingDetail, Theme.dim)
        ]
        for (text, tint) in segments {
            guard let text, !text.isEmpty else { continue }
            if !result.characters.isEmpty {
                var separator = AttributedString(CadenceOverdueSummaryLine.separator)
                separator.foregroundColor = Theme.dim
                result += separator
            }
            var segment = AttributedString(text)
            segment.foregroundColor = tint
            result += segment
        }
        return result
    }
}

/// The list's own `colorHex` icon stays coloured — that is identity the user chose, not state.
/// State is carried by the date alone.
struct CadenceTodayOverdueListCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let summary: CadenceTodayOverdueListSummary
    let action: () -> Void

    var body: some View {
        let wraps = scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
        let layout = wraps
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        CadenceOverdueSummaryCard(action: action) {
            layout {
                CadenceOverdueSummaryIconTile(
                    systemImage: summary.icon,
                    colorHex: summary.colorHex
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .cadenceFont(.controlLabel)
                        .foregroundStyle(Theme.text)
                        .lineLimit(wraps ? nil : 1)
                        .fixedSize(horizontal: false, vertical: wraps)
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

                if !wraps { Spacer() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CadenceTodayOverdueSectionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let summary: CadenceTodayOverdueSectionSummary
    let action: () -> Void

    var body: some View {
        let wraps = scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
        let layout = wraps
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        CadenceOverdueSummaryCard(action: action) {
            layout {
                CadenceOverdueSummaryIconTile(
                    systemImage: summary.parentIcon,
                    colorHex: summary.parentColorHex
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.sectionName)
                        .cadenceFont(.controlLabel)
                        .foregroundStyle(Theme.text)
                        .lineLimit(wraps ? nil : 1)
                        .fixedSize(horizontal: false, vertical: wraps)
                    CadenceOverdueSummaryCaption(
                        line: CadenceOverdueSummaryPresentation.line(
                            dueDateKey: summary.dueDateKey,
                            leadingDetail: summary.parentName
                        )
                    )
                }

                if !wraps { Spacer() }

                VStack(alignment: wraps ? .leading : .trailing, spacing: 2) {
                    Text("\(summary.openTaskCount) open")
                        .cadenceFont(.sectionLabel)
                        .foregroundStyle(Theme.text)
                    if summary.completedTaskCount > 0 {
                        Text("\(summary.completedTaskCount) done")
                            .cadenceFont(.sectionLabel, weight: .regular)
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The list's glyph in the list's own colour. Not `CommitmentIconTile` / `iOSIconTile`: those are
/// larger identity tiles for rows and pickers, and this is a 30pt badge sized to a two-line card.
private struct CadenceOverdueSummaryIconTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let systemImage: String
    let colorHex: String

    private var tint: Color {
        Color(hex: colorHex)
    }

    var body: some View {
        let side = CadenceOverdueSummaryMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)
        RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
            .fill(tint.opacity(0.16))
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: systemImage)
                    .cadenceFont(.controlLabel)
                    .foregroundStyle(tint)
            }
    }
}

/// The heading over a run of either card — the eyebrow and its count.
///
/// Neutral rather than `Theme.red`: it used to be the third telling of "late" over rows that
/// already say so, above cards that said so twice more.
struct CadenceTodayOverdueSummaryHeading: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let title: String
    let count: Int

    var body: some View {
        let wraps = scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
        HStack(spacing: 6) {
            SectionEyebrowLabel(text: title)
                .fixedSize(horizontal: false, vertical: wraps)

            // The count is the eyebrow's own size, not a point larger. It used to inherit an 11pt
            // font applied to the whole `HStack` — the one place in the app where the eyebrow tier
            // was 11 — so adopting the shared label dropped both to 10 together. That is the rule
            // `CadenceBoardColumnHeaderMetrics.countSize` already states: a count is demoted by
            // weight and by its colour, and must never be bigger than the label it counts. (The
            // task group heading used to state it too; T-2056 took its capsule off both platforms,
            // so this and the board column are the two counts beside an eyebrow that are left.)
            // No capsule here on purpose — this heading sits over cards that already carry their
            // own chrome.
            Text("\(count)")
                .cadenceFont(.sectionLabel, base: SectionEyebrowLabel.fontSize, weight: .semibold)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: wraps, vertical: wraps)
        }
    }
}
