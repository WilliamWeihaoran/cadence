import CoreGraphics

/// Which Today layout a pane of a given width can actually render.
nonisolated enum CadenceTodayLayout: Equatable {
    /// One scrolling column. Compact width, and any regular width too narrow for two.
    case compact
    /// Task column plus one switchable inspector (notes *or* timeline).
    case twoPane
}

/// The width arithmetic behind `iOSTodayView`'s layout choice.
///
/// **There is one iPad Today layout with a choice in it, and this is not it.** Today is task column
/// plus inspector, or one column when even that does not fit; the inspector's Notes/Timeline
/// switcher is the only thing the user picks. A third, Mac-shaped `notes | tasks | timeline` layout
/// and the `iPadTodayLayoutMode` picker that selected it — in the Today header *and* again in
/// Settings → Navigation — were deleted at the user's direction, even though an 11" or 13" Pro in
/// landscape could reach the 1022pt floor it needed.
///
/// **Registered, not orphaned.** This is one of six expressions of "derive a pane decision from the
/// width you were handed", and `CadenceRegularPaneLayout.swift` is the house file that lists all of
/// them and argues why each stays where it is. Read the register there before adding a seventh — and
/// note that a new width-taking function *here* fails
/// `CadenceTests/CadencePaneWidthRuleHomesTests.swift` until the register names it.
///
/// The stored preference behind that picker was `ios.today.layoutMode`, a `UserDefaults` key and
/// **not** a SwiftData property, so removing it drops a preference rather than data. Nothing reads
/// the key any more, which is what makes a stored `mac` safe: `layout(...)` no longer takes a
/// preference at all, so there is no path by which one can select a layout that does not exist.
/// `CadenceTodayLayoutSupportTests` pins that — the function's whole range is `.compact` and
/// `.twoPane`.
nonisolated enum CadenceTodayLayoutSupport {
    /// The task column's declared `minWidth`. It is the column the inspector exists to serve, so it
    /// is the one that must not be starved.
    static let taskPaneMinWidth: CGFloat = 440
    static let paneDividerWidth: CGFloat = 1

    /// The least the notes/timeline inspector will accept before its own content starts clipping.
    static let inspectorPaneMinWidth: CGFloat = 320
    /// What that floor becomes once the pane can afford it.
    static let inspectorPaneWideMinWidth: CGFloat = 370
    /// Where the floor steps up.
    static let inspectorWidePaneThreshold: CGFloat = 900

    /// 761pt of pane. Two panes had **no** floor: `layout(...)` returned `.twoPane` for every
    /// regular-width device however little room there was, and only the (now deleted) three-pane
    /// case was gated.
    ///
    /// On an 11" iPad in portrait that meant 632pt split into a 312pt task column beside the
    /// inspector — narrow enough that the column could not fit its own header, which wrapped the
    /// date to "SUND AY, …". Below this floor a single full-width column is simply better than two
    /// starved ones.
    static var twoPaneMinimumWidth: CGFloat {
        taskPaneMinWidth + inspectorPaneMinWidth + paneDividerWidth
    }

    static func supportsTwoPane(paneWidth: CGFloat) -> Bool {
        paneWidth >= twoPaneMinimumWidth
    }

    /// The layout to render, given the space actually available. Width is the only input: there is
    /// no stored layout preference left to consult.
    static func layout(isRegularWidth: Bool, paneWidth: CGFloat) -> CadenceTodayLayout {
        guard isRegularWidth else { return .compact }
        return supportsTwoPane(paneWidth: paneWidth) ? .twoPane : .compact
    }

    // MARK: - Two-pane widths
    //
    // These three lived on `iOSTodayView` as `private` methods, which put them behind
    // `#if os(iOS)` where the macOS test target cannot see them — so `iPadTodayPaneWidthTests`
    // re-implemented them instead of calling them. A test that owns a *copy* of the rule cannot
    // fail when the rule changes, and this one did not: the copy carried the same divider bug the
    // view did, and asserted `task + floor <= pane` because the code it mirrored also forgot the
    // 1pt `Divider()` between them. They live here now, beside the floor they have to agree with.

    /// The inspector's floor at a given pane width.
    ///
    /// **Both branches are live**, and the shell's fold is what makes the narrow one so. With the
    /// sidebar out, the target iPad is 646pt of pane in portrait — one column, so this is never
    /// asked — and 1022 in landscape, which takes the wide floor. But a folded sidebar hands the
    /// detail the whole window: **834pt in portrait**, over `twoPaneMinimumWidth` and under 900.
    /// That is the narrow branch, on the target device, full screen, with no multitasking at all.
    /// A folded 2/3 Split View (~795pt) lands in the same band.
    static func inspectorPaneFloor(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        paneWidth < inspectorWidePaneThreshold ? inspectorPaneMinWidth : inspectorPaneWideMinWidth
    }

    /// The task column's width. It is the fixed side of the two-pane `HStack`; the inspector is the
    /// side that flexes, so everything the inspector needs has to come out of this number first.
    ///
    /// **`available` counts the divider, and it did not.** `twoPaneMinimumWidth` sums
    /// `taskPaneMinWidth + inspectorPaneMinWidth + paneDividerWidth`, so this file already knew the
    /// divider existed; the width arithmetic did not, and the two disagreed. Wherever `available`
    /// was the binding clamp the row asked for `task + 1 + floor == pane + 1`, and an `HStack` does
    /// not shrink a fixed `.frame(width:)` — the shell hard-sizes the pane and `.clipped()`s it, so
    /// the point came off the trailing edge. Two bands did it: **[761, 841)**, reachable on a
    /// full-screen portrait iPad with the sidebar folded (834), and **[900, 928)**, which only a
    /// resized window reaches. Subtracting the divider closes both, and at exactly
    /// `twoPaneMinimumWidth` the task column now lands on `taskPaneMinWidth` to the point.
    ///
    /// The floors are preferences; `available` is the guarantee. There is no upper cap on
    /// `preferred` — the `min(…, 760)` that used to close it needed a 1267pt pane, and the widest
    /// pane a target device produces is 1210: an 11" Pro in landscape with the sidebar folded.
    static func taskPaneWidth(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        let available = max(0, paneWidth - inspectorPaneFloor(forPaneWidth: paneWidth) - paneDividerWidth)
        guard available > 0 else { return paneWidth }

        let preferred = max(paneWidth * 0.60, 520)
        return min(preferred, available)
    }

    /// The inspector's ideal, uncapped for the same reason: 40% of the widest reachable pane is 484,
    /// where the `min(…, 540)` this used to end with needed 1350.
    static func inspectorPaneIdealWidth(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        max(paneWidth * 0.40, inspectorPaneFloor(forPaneWidth: paneWidth))
    }
}

/// Everything Today's list of task groups is drawn with, in one value — one entry per
/// `CadenceTodayLayout`.
///
/// The two hosts had each grown their own copy of the same list. The phone stacked its groups 14pt
/// apart inside a card and padded its empty state 14; the two-pane task column stacked the *same*
/// groups 15pt apart with no card and padded the same empty state 18. Nobody chose 14-against-15 —
/// it is what two copies of one list become after a few edits each, and it is the drift
/// `CadencePageHeaderMetrics` was written to stop for headers.
///
/// **There used to be a third difference — a card — and it is gone (T-587).** The compact layout
/// carried `drawsCard`/`cardPadding`, documented as "a `Theme.surface` card is what separates the
/// day's list from the `Theme.bg` page". `85809ff` deleted the `.cadenceCard()` behind it, on
/// purpose and at five sites at once, because macOS never drew one and the rows now read the same
/// on both platforms. What survived the deletion was the *inset*: the call site kept
/// `.padding(metrics.cardPadding)` with no fill behind it, so the phone's group headers and rows
/// sat 12pt inside the page header and options bar directly above them — the "header indented from
/// the rows under it" defect `CadencePageHeaderMetrics.horizontalPadding` keeps its own gutter to
/// avoid, only the other way round. Both fields are removed; each host already pads its own
/// gutter, and the two layouts now differ in exactly one figure.
///
/// `contentMaxWidth` is keyed on `CadenceTodayLayout` and **not** on the size class, so the iPad's
/// own narrow fallback — a regular-width pane under `twoPaneMinimumWidth`, which renders the
/// compact layout on a `Theme.bg` page — takes the phone's cap rather than the tablet's.
nonisolated struct CadenceTodaySectionMetrics: Equatable, Sendable {
    /// Between one counted task group and the next. **One number for both layouts**: the gap
    /// between "Overdue" and the first list under it is not something a wider pane needs more of,
    /// and it is the 14/15 split this type exists to close. It is also what Inbox and All Tasks
    /// stack at, so the three segments of one tab agree.
    ///
    /// This used to read "between Overdue and Planned Today", and cited that pair as a split that
    /// was deliberate rather than width-driven. The *spacing* claim still holds and is the only
    /// claim this property makes; the pair does not. T-305 removed "Planned Today" — on the Today
    /// page "today" is the page, so the heading restated it — and grouped the day's remaining work
    /// by list instead. Overdue is still the first group and still the only date-shaped one. See
    /// `CadenceTaskQuerySupport.todayGroups`.
    let groupSpacing: CGFloat
    /// How wide the column of rows grows before it stops. The one figure that legitimately differs:
    /// a task pane whose floor is `taskPaneMinWidth` can hold a wider readable column than a phone,
    /// and a line of text that runs the full width of an iPad is worse than one that does not.
    let contentMaxWidth: CGFloat

    static func metrics(layout: CadenceTodayLayout) -> CadenceTodaySectionMetrics {
        switch layout {
        case .compact:
            return CadenceTodaySectionMetrics(
                groupSpacing: groupSpacing,
                contentMaxWidth: 520
            )
        case .twoPane:
            return CadenceTodaySectionMetrics(
                groupSpacing: groupSpacing,
                contentMaxWidth: 720
            )
        }
    }

    private static let groupSpacing: CGFloat = 14
}
