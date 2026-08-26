import SwiftUI

/// Every measurement the one board-column header draws itself with.
///
/// **There is deliberately no surface axis here**, which is the finding rather than an omission.
/// `CadencePageHeaderMetrics` needs three tiers because a page header is as wide as whatever
/// contains it — a phone screen, an iPad pane, a Mac window — and type that does not scale with
/// that would be wrong at one of them. A board column is the opposite kind of object: it is a
/// *fixed-width* column on every surface Cadence draws one on (macOS 236pt kanban / 306pt day /
/// 248pt rail, iOS 300pt, and on a phone one column sized to the screen). A Mac gives a column
/// header no more room than an iPhone does, so it gets no bigger type, and the "iPhone and iPad
/// are one style" rule then collapses the remaining two into one. One set of numbers is the
/// correct answer here, not the lazy one.
///
/// It is a value type outside every platform conditional so `CadenceTests` — which builds for
/// macOS and cannot see `Cadence/iOS/` at all — can pin the figures both platforms draw with.
nonisolated struct CadenceBoardColumnHeaderMetrics: Sendable {
    /// The uppercased, kerned, semibold column label.
    ///
    /// **10 wins, and macOS had it.** Every uppercased-kerned-semibold label in Cadence is 10pt —
    /// `SectionEyebrowLabel`, `CadencePageHeaderMetrics.eyebrowSize`, and 14 call sites besides.
    /// iOS's board column header was set at 11 and was one of only two exceptions in the app. An
    /// eyebrow is *vocabulary*, not volume; `5aa11dc` already established that it does not vary
    /// by surface, and a board column is the one place that was still disagreeing.
    static let labelSize: CGFloat = 10

    static let labelKerning: CGFloat = 0.4

    /// The task/item count at the trailing edge.
    ///
    /// **10 wins, and neither platform had it.** macOS drew 9 and iOS drew 11. The count is
    /// already demoted twice against the label beside it — `.medium` against `.semibold`, and
    /// `Theme.dim` against `Theme.muted` — so macOS's third demotion took it to 9pt, smaller than
    /// anything else Cadence sets, for the one glyph in the header a user actually reads a value
    /// off. iOS's 11 went the other way and made the number louder than the name it counts.
    /// Setting it *at* the label's size lets the weight and the colour do the demoting.
    static let countSize: CGFloat = 10

    /// The single dot of colour that survives in an otherwise containerless column header. Both
    /// platforms already drew 7, macOS through a `kanbanColumnDotSize` constant that this
    /// replaces, so the figure is stated once rather than twice.
    static let dotSize: CGFloat = 7

    /// Dot → label → count.
    static let titleRowSpacing: CGFloat = 7
    /// The label row's minimum gap before the count, so a long section name truncates instead of
    /// colliding with it.
    static let countLeadingGap: CGFloat = 6
    /// Title row → optional detail line (the section board's due-date row).
    static let detailSpacing: CGFloat = 5
    /// Indent that lines a detail line up under the label rather than under the dot. macOS spelled
    /// this 14 twice; iOS's board needs the same number now that it draws a detail line too, so it
    /// is stated once here instead of a third time.
    static let detailLeadingInset: CGFloat = 14

    /// **macOS's padding wins, including the 2pt top the iOS copy dropped.** macOS spells this
    /// once in `kanbanColumnHeaderPadding()`, documented as "padding shared by both boards' column
    /// header blocks"; the iOS fork reproduced the horizontal 4 and the bottom 8 and lost the top.
    /// That is what a copy loses, not what a platform chooses.
    static let horizontalPadding: CGFloat = 4
    static let topPadding: CGFloat = 2
    static let bottomPadding: CGFloat = 8

    /// The closing hairline. The accent variant carries colour in the same 1pt slot, so the one
    /// sanctioned exception — the Calendar Board's *today* column — costs no layout difference.
    static let ruleHeight: CGFloat = 1

    /// The accent rule's gradient stops, leading to trailing. Both platforms already agreed on
    /// these three numbers; stating them once is what stops them drifting the way the type sizes
    /// did.
    static let accentRuleOpacities: [Double] = [0.85, 0.45, 0.16]
}

/// Whether a board column's header draws its due-date line, and what that line reads.
///
/// This is the metadata iOS was not handing the shared header (T-331). The header component was
/// already shared and already had a `detail` slot; only macOS filled it, so a section due date set
/// in the iOS column editor was stored, was honoured by every date query, and was invisible on the
/// board that set it. iOS now fills the same slot from the same rule.
///
/// The rule is a value type outside every platform conditional for the reason the metrics above
/// are: `CadenceTests` builds for macOS and cannot see `Cadence/iOS/` at all, so a shared *value*
/// is the only way an assertion can cover both boards' behaviour rather than one board's source.
nonisolated struct CadenceBoardColumnDueDatePlan: Equatable, Sendable {
    /// Whether the header draws the line at all. A column with no due date still draws one — reading
    /// `emptyLabel` — unless the list asked for empty ones to be hidden.
    let isVisible: Bool
    /// Distinguishes "shows a date" from "shows the empty placeholder", which is what the flag glyph
    /// and its tint key off.
    let hasDueDate: Bool
    /// The text of the line: a relative date, or `emptyLabel`.
    let label: String
    /// Past due and not settled. A completed column is never overdue — the date it missed stopped
    /// mattering when the column wound down.
    let isOverdue: Bool

    /// What a column with no due date says when it is shown anyway. macOS has always drawn this
    /// string; it is stated once now so iOS cannot drift a second wording into the same slot.
    static let emptyLabel = "No due date"

    static func plan(
        dueDate: String,
        hideWhenEmpty: Bool,
        isCompleted: Bool,
        relativeTo referenceDate: Date = Date()
    ) -> CadenceBoardColumnDueDatePlan {
        let hasDueDate = !dueDate.isEmpty
        return CadenceBoardColumnDueDatePlan(
            isVisible: hasDueDate || !hideWhenEmpty,
            hasDueDate: hasDueDate,
            label: hasDueDate
                ? DateFormatters.relativeDate(from: dueDate, relativeTo: referenceDate)
                : emptyLabel,
            isOverdue: hasDueDate
                && !isCompleted
                && dueDate < DateFormatters.dateKey(from: referenceDate)
        )
    }
}

/// The one drawing of a column's due date: flag glyph, then the date or "No due date".
///
/// Shared rather than mirrored. macOS wraps it in a `Button` that opens the header's date popover
/// and iOS draws it plain — the board that sets a section's due date on iOS is the column editor,
/// not the column — but the glyph, the two type sizes and the two tints are one definition, so the
/// half of T-331 that was "iOS shows nothing" cannot become "iOS shows something slightly else".
struct CadenceBoardColumnDueDateLine: View {
    let plan: CadenceBoardColumnDueDatePlan

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(plan.hasDueDate ? Theme.red : Theme.dim)
            Text(plan.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(plan.isOverdue ? Theme.red : Theme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// The dot + uppercased label + count that opens every board column, on both platforms.
///
/// `trailing` is where a board adds its own controls: the macOS section board puts the completion
/// and overflow buttons there, every other caller passes `EmptyView()`.
struct CadenceBoardColumnTitleRow<Trailing: View>: View {
    let dotColor: Color
    let title: String
    let count: Int
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CadenceBoardColumnHeaderMetrics.titleRowSpacing) {
            Circle()
                .fill(dotColor)
                .frame(
                    width: CadenceBoardColumnHeaderMetrics.dotSize,
                    height: CadenceBoardColumnHeaderMetrics.dotSize
                )

            Text(title.uppercased())
                .font(.system(size: CadenceBoardColumnHeaderMetrics.labelSize, weight: .semibold))
                .kerning(CadenceBoardColumnHeaderMetrics.labelKerning)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: CadenceBoardColumnHeaderMetrics.countLeadingGap)

            Text("\(count)")
                .font(.system(size: CadenceBoardColumnHeaderMetrics.countSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)

            trailing()
        }
    }
}

extension CadenceBoardColumnTitleRow where Trailing == EmptyView {
    init(dotColor: Color, title: String, count: Int) {
        self.init(dotColor: dotColor, title: title, count: count) { EmptyView() }
    }
}

/// The **one** column-header treatment, shared by every board surface on **both** platforms: the
/// macOS section and list kanban columns, the macOS Calendar Board's day columns and pinned rails,
/// the iOS Calendar Board's day columns, the iOS list kanban columns, and the iOS month agenda's
/// day sections. Same dot, same label size and casing, same count placement, same padding, same
/// closing hairline.
///
/// It is width-agnostic on purpose: the Calendar Board's rails are narrower than its day columns
/// and still line up, because the header fills whatever width its column hands it.
///
/// Exactly three things may differ per board, because they are genuinely different content:
/// - `title` — bucket name / section name / weekday + date.
/// - `trailing` — per-column controls (the macOS section board's complete + overflow buttons).
/// - `detail` — an optional second line (the macOS section board's due-date row).
///
/// `accentRule` replaces the neutral hairline with a coloured one. The Calendar Board's *today*
/// column — on either platform — is the single sanctioned user of it; nothing else should pass a
/// colour here.
///
/// This was `BoardColumnHeader` on macOS and a 60-line `iOSBoardColumnHeader` in
/// `iOSDesignSystem.swift`, whose own doc comment opened "iOS counterpart of macOS's
/// `BoardColumnHeader`" — the fork announcing itself and surviving anyway, because a diff adding
/// `iOSBoardColumnHeader` reads as an iOS thing rather than as a second copy of a component the
/// repo's own non-negotiables name as one that must never be forked.
struct CadenceBoardColumnHeader<Trailing: View, Detail: View>: View {
    private let dotColor: Color
    private let title: String
    private let count: Int
    private let accentRule: Color?
    private let trailing: () -> Trailing
    private let detail: () -> Detail

    init(
        dotColor: Color,
        title: String,
        count: Int,
        accentRule: Color? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.dotColor = dotColor
        self.title = title
        self.count = count
        self.accentRule = accentRule
        self.trailing = trailing
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: CadenceBoardColumnHeaderMetrics.detailSpacing) {
                CadenceBoardColumnTitleRow(
                    dotColor: dotColor,
                    title: title,
                    count: count,
                    trailing: trailing
                )
                detail()
            }
            .padding(.horizontal, CadenceBoardColumnHeaderMetrics.horizontalPadding)
            .padding(.top, CadenceBoardColumnHeaderMetrics.topPadding)
            .padding(.bottom, CadenceBoardColumnHeaderMetrics.bottomPadding)

            rule
        }
    }

    @ViewBuilder
    private var rule: some View {
        if let accentRule {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: CadenceBoardColumnHeaderMetrics.accentRuleOpacities.map { accentRule.opacity($0) },
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: CadenceBoardColumnHeaderMetrics.ruleHeight)
        } else {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: CadenceBoardColumnHeaderMetrics.ruleHeight)
        }
    }
}

extension CadenceBoardColumnHeader where Detail == EmptyView {
    init(
        dotColor: Color,
        title: String,
        count: Int,
        accentRule: Color? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            dotColor: dotColor,
            title: title,
            count: count,
            accentRule: accentRule,
            trailing: trailing,
            detail: { EmptyView() }
        )
    }
}

// A `where Trailing == EmptyView` convenience taking only `detail:` is deliberately **not** here.
// It compiles, and it makes every existing bare trailing closure on this type ambiguous with the
// `where Detail == EmptyView` init above it — `CalendarBoardRailSupportViews` fails to build the
// moment it exists. A board that wants a detail line and no controls spells both slots out.

extension CadenceBoardColumnHeader where Trailing == EmptyView, Detail == EmptyView {
    init(dotColor: Color, title: String, count: Int, accentRule: Color? = nil) {
        self.init(
            dotColor: dotColor,
            title: title,
            count: count,
            accentRule: accentRule,
            trailing: { EmptyView() },
            detail: { EmptyView() }
        )
    }
}
