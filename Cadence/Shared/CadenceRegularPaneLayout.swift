import CoreGraphics

// MARK: - The register: where "derive a pane decision from handed width" may live
//
// One rule, nine expressions, four files — and this is the house file, so the register lives here
// rather than in a doc that the code cannot be checked against. T-182 was raised as "four
// expressions in four places"; the count was short by two, T-248/T-249 added the seventh,
// T-250/T-252 the eighth and T-251 the ninth. What is actually there:
//
//   Here, in `CadenceRegularPaneLayout.swift`
//     - `CadenceRegularSplitLayout`     a *width*, for a chooser column beside a detail, **and**
//                                       since T-252 the gate under it.
//     - `CadenceCalendarWeekGridLayout` a *width*, N columns rather than two panes, and the
//                                       supplier of the minimum the gate below reads.
//     - `CadenceCalendarPaneLayout`     a *Bool* gate, plus the two widths behind it.
//     - `CadenceSettingsTemplatesCardLayout`
//                                       an *enum* (`CadenceSettingsCardLayout`), for the one
//                                       settings *card* that splits. It is here rather than in a
//                                       surface file because its two surfaces are
//                                       `Cadence/macOS/Views/SettingsTemplatesSection.swift` and
//                                       `Cadence/iOS/iOSSettingsTemplateAndListSections.swift` —
//                                       one behind `#if os(macOS)`, one behind `#if os(iOS)` and
//                                       therefore invisible to the macOS-built test target. There
//                                       is no file either surface can put its parts in *except*
//                                       out here, which is the same argument
//                                       `CadenceNotesListSupport.swift` opens with.
//     - `CadenceDesktopSplitLayout`     an *enum* (`CadenceDesktopTodayLayout`) and two *Bool*
//                                       gates, for the three macOS `HSplitView` pages. Here for
//                                       the `CadenceSettingsTemplatesCardLayout` reason one level
//                                       further along: its three surfaces are all behind
//                                       `#if os(macOS)`, and it is the first expression written
//                                       because the *window* could not hold the rule — see its
//                                       own doc for why raising `CadenceApp`'s floor was rejected.
//     - `CadenceCalendarBoardLayout`    an *enum* (`CadenceCalendarBoardRailForm`) and the widths
//                                       behind it, for the macOS Calendar Board's two pinned
//                                       rails. Here for `CadenceDesktopSplitLayout`'s reason, plus
//                                       one this file had not met before: the parts the floor sums
//                                       — the day column's width, the rail's, their insets — were
//                                       top-level `let`s in `macOS/Views/KanbanBoardSupport.swift`,
//                                       behind `#if os(macOS)`, so the floor could not have been
//                                       written as a sum of them without moving them. It is also
//                                       the first expression where the **fixed** side is the one
//                                       that yields, and the first whose fallback is a *reduced*
//                                       column rather than a dropped one — see its own doc for why
//                                       neither rail may vanish.
//   `CadenceTodayLayoutSupport.swift`
//     - `CadenceTodayLayoutSupport`     an *enum* (`CadenceTodayLayout`), plus the fixed side's width.
//   `CadenceNotesListSupport.swift`
//     - `CadenceNotesListMetrics`       an *enum* (`CadenceNotesLayout`); the floor and the gate only.
//   `CadenceRootShellLayout.swift`
//     - `CadenceRootShellLayout`        a *Bool* (labelled column or icon rail), plus both widths.
//
// **They stay where they are, and this register is the consolidation.** Three reasons, in the order
// that decided it:
//
// 1. They do not answer with the same kind of thing — a width, a Bool, an enum — and the one shape
//    they all reduce to is `handedWidth >= a + divider + b`. Hoisting a three-term sum into a
//    shared `splits(width:sides:)` would trade five readable domain expressions for one generic
//    one, and it would cost `CadenceCalendarPaneLayout` the property its own doc calls
//    load-bearing: that gate is *derived from* `inspectorWidth` rather than stated in parallel with
//    it, "so the two cannot drift apart". A parallel sum is the drift it was written to prevent.
// 2. Every floor is a **sum of its parts** deliberately, so that raising a column moves the floor —
//    and the parts are local to the surface. `regularColumnWidth` is a notes-list figure;
//    `taskPaneMinWidth` is a Today figure. Moving the sums here without the parts would put "raise
//    the column" in one file and "the floor follows it" in another, weakening the exact property
//    the sums exist for. Moving the parts here too means dragging a row-metrics struct about font
//    sizes and cell padding into a file about pane arithmetic.
// 3. Co-location is not what prevents the recurrence, and there is evidence rather than a hunch:
//    three of these already cross-reference each other by name and a fourth copy was still written.
//    `CadenceNotesListMetrics.minimumEditorWidth` *is*
//    `CadenceTodayLayoutSupport.inspectorPaneMinWidth`, by reference, across a file boundary — the
//    coupling that matters is already expressed and needed no shared file to hold it.
//
// The obligation therefore sits on the register: a new width-derived pane decision either joins one
// of the four files above and is listed here, or it is a fifth copy.
// `CadenceTests/CadencePaneWidthRuleHomesTests.swift` counts the declarations per file and fails on
// both — on a new file, and on a new function inside one of the four that this list does not
// mention. Editing that count is how you are made to edit this list.
//
// The one file that takes a `paneWidth` and is deliberately **not** on the list is the model to
// copy: `CadenceCalendarMonthLayout.placement(paneWidth:)` (`CadenceCalendarAgendaSupport.swift`)
// answers a placement question by *calling* `CadenceCalendarPaneLayout.showsInspector` and states no
// floor of its own. That is what "a new split surface belongs in the house file" looks like from the
// surface's side, and the test pins it as a delegation rather than as an exemption.
//
// The shape of the mistake, stated once here so the docs below need not each restate it: a fixed
// `.frame(width:)` beside a flexing pane, with nothing asserting the flexing side stays usable. It
// has shipped three times — Today wrapping its own header date to "SUND AY" in a 312pt column, the
// notes editor drawn at 39pt inside a 320pt inspector, and the shell sidebar reading "KSPACE" after
// a pane three levels down declared a minimum wider than the window. Each time a floor existed and
// was read as a guarantee. The floor is the wish; what is actually available is the guarantee.

/// How a regular-width pane divides between a list column and the detail beside it.
///
/// Every split feature surface on iPad — Goals, Habits, Focus, Lists — declared its own geometry,
/// and three of the four declared a `minWidth`/`idealWidth` with **no maximum**. An `HStack` given
/// two flexible children splits the difference, so on a 13" iPad in portrait (844pt of pane after
/// the 188pt sidebar) the Goals list column took 422pt to draw one-line rows while the detail beside
/// it wrapped "Ship Cadence on iPad" onto two lines. The list column is a chooser; the detail is the
/// thing being read. The proportion should reflect that at every width, and the maximum is what
/// makes it.
///
/// The rule is the one `CadenceTodayLayoutSupport` settled on: a floor is a preference, and what is
/// actually available is the guarantee. `listPaneWidth(forPaneWidth:)` therefore ends by clamping to
/// half the pane — below about 790pt the fraction has already fallen under the 300pt floor, and
/// without that last clamp a "minimum" would start taking *more* than half of a narrow pane, which
/// is the same shape as the bug that made an 11" iPad split 632pt into 312 and 320.
enum CadenceRegularSplitLayout {
    /// The least a list column can be and still show an icon, a two-line row and a count badge.
    static let listPaneMinWidth: CGFloat = 300
    /// Past this a wider pane is better spent on the detail. `iOSListsView` already declared it;
    /// Goals, Habits and Focus did not, which is what let them take half of a 13" pane.
    static let listPaneMaxWidth: CGFloat = 380
    /// The share of the pane the list column asks for between those two bounds. Chosen so that a
    /// 13" iPad in portrait lands on 338 — within a couple of points of the 340 `idealWidth`
    /// `iOSListsView` had already settled on by hand, so the one surface that was **not** broken
    /// keeps the proportion it had.
    static let listPaneFraction: CGFloat = 0.40
    static let paneDividerWidth: CGFloat = 1

    static func listPaneWidth(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        guard paneWidth > 0 else { return listPaneMinWidth }
        let preferred = min(max(paneWidth * listPaneFraction, listPaneMinWidth), listPaneMaxWidth)
        // Never more than the detail beside it. This is the guarantee; `preferred` is the wish.
        return min(preferred, (paneWidth - paneDividerWidth) / 2)
    }

    /// 750pt of pane — the width below which two panes is worse than one, and the last of the
    /// registered rules to get one (T-252).
    ///
    /// **Derived, and derived from this type's own parts, because the four details cannot supply a
    /// floor.** Goals, Habits, Focus and Lists each put a different thing in the detail pane and
    /// none of them states a minimum, so there is nothing to borrow the way
    /// `CadenceSettingsTemplatesCardLayout` borrows `CadenceNotesListMetrics.minimumEditorWidth`.
    /// Inventing one is what T-183 exists to prevent. What *is* already stated here is the
    /// proportion the split is for: the chooser asks for `listPaneFraction` of the pane, and
    /// `listPaneMinWidth` is the least it can be and still draw a row. Below
    /// `listPaneMinWidth / listPaneFraction` those two disagree — the floor is bigger than the
    /// share — and from there on every point the pane loses comes out of the detail, which is the
    /// side the split exists to serve. That is the same sentence as "two starved panes are worse
    /// than one whole one", said in terms this file already has.
    ///
    /// It lands where the ticket said it had to: the 11" iPad Pro in portrait with the shell
    /// sidebar out is 646pt of pane and becomes one column, on the same device and orientation
    /// where `CadenceTodayLayoutSupport` gives Today one column (761) and
    /// `CadenceCalendarPaneLayout` drops the day inspector (681). With the sidebar folded it is
    /// 834 and splits, at a 333.6pt chooser — the proportion, not the floor. `listPaneWidth` is
    /// unchanged and still answers for every width; this only decides whether anything asks it.
    static var twoPaneMinimumWidth: CGFloat {
        listPaneMinWidth / listPaneFraction
    }

    static func supportsTwoPanes(paneWidth: CGFloat) -> Bool {
        paneWidth >= twoPaneMinimumWidth
    }
}

/// The Week timeline's own width arithmetic: an hour rail, then one column per day, with all seven
/// of them on screen at once.
///
/// `iOSCalendarTimelineGrid` computed this inline as
/// `max(dates.count <= 7 ? available / count : 126, isRegular ? 112 : 104)` — a floor treated as a
/// guarantee, the same shape as the two bugs below, and the one that survived them. That `max`
/// means the grid needs `58 + 7 × 112 = 842pt` before a week fits without a horizontal scroller,
/// and no iPad pane is that wide once the day inspector has taken its 340: an 11" Pro in landscape
/// is 1022 and keeps 682, a 13" in portrait is 844 and keeps 503. So Week ran behind a scroller
/// showing roughly six of seven days on the primary target and four and a half on a 13" — the
/// seventh day off the right edge of the one view whose entire subject is the week. It starved
/// *below* the split too: an 11" in portrait gives the grid its whole 632pt pane and 632 is still
/// short of 842, so removing the inspector there had taken it from two visible days to five, not
/// to seven.
///
/// The inversion is the one the rest of this file already made: **seven columns on screen is the
/// guarantee and 112pt is the wish.** A pane that cannot pay for seven full-width columns gets
/// seven narrower ones rather than five and a scrollbar, down to `minimumDayColumnWidth`.
///
/// Compression alone was not enough, though, and the reason is worth keeping: at a 13" iPad's
/// 844pt pane the inspector's 340 leaves 445, which divides into seven columns of 63.6 — over the
/// touch floor, so it *fits*, and every block in it reads `[S…` over `3…`. Seven columns that say
/// nothing are not a week either. So `fullSizeWidth` is what
/// `CadenceCalendarPaneLayout.showsInspector(paneWidth:calendarMinimumWidth:)` gates on: the
/// inspector may only have space the week does not need to draw itself at full size. Compression is
/// for panes that are simply small, where the alternative is not a narrower inspector but a missing
/// day.
enum CadenceCalendarWeekGridLayout {
    static let daysInWeek = 7

    /// The hour rail down the left of the canvas, as `iOSCalendarTimelineGrid` already had it.
    static func timeRailWidth(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 58 : 48
    }

    /// What a day column asks for when the pane can pay for it — wide enough for a block to label
    /// itself with a title *and* a time range. This is the number that used to be spelled `max(…)`.
    static func preferredDayColumnWidth(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 112 : 104
    }

    /// A timeline block is inset this far from each edge of its column — `colWidth - 18` in
    /// `iOSCalendarTimelineDayColumn`, at `x: 9`.
    static let blockHorizontalInset: CGFloat = 9
    /// The floor any control has to clear to stay usable.
    static let minimumTouchTarget: CGFloat = 44

    /// The least a day column can be. Derived, not picked: a column's widest hard requirement is
    /// that the block drawn inside it stays tappable, and that block is inset by
    /// `blockHorizontalInset` on both sides. Below this a column stops being *usable* rather than
    /// merely tight, so there is nothing left to buy by compressing further and the grid scrolls
    /// instead. The narrowest iPad pane, 632pt of 11" portrait, lands at 82 — comfortably clear.
    static var minimumDayColumnWidth: CGFloat {
        minimumTouchTarget + blockHorizontalInset * 2
    }

    /// A span longer than a week scrolls by design: fourteen columns cannot be a fortnight and a
    /// legible day at the same time on any iPad. `.twoWeeks` is not in `pickerCases`, so this is
    /// only reachable from a value persisted by an older build.
    static let multiWeekDayColumnWidth: CGFloat = 126

    /// The width at which every day column is the size it asks for — the rail plus seven columns at
    /// `preferredDayColumnWidth`. 842pt at regular width.
    ///
    /// This is what the grid claims before an inspector may take anything, so it is the number that
    /// decides where Week splits: 842 + 340 + 1 = 1183pt of pane. On the target iPad in landscape
    /// that is reached with the shell sidebar **folded** (1210pt of pane — seven 112.6pt columns
    /// *and* an inspector) and not with it out (1022pt, which gives the week the whole pane at
    /// 137.7pt a column). Either way the week is legible, which is the trade this makes and the
    /// reason the gate is stated as "the inspector may only have space the week does not need".
    static func fullSizeWidth(isRegularWidth: Bool) -> CGFloat {
        timeRailWidth(isRegularWidth: isRegularWidth)
            + preferredDayColumnWidth(isRegularWidth: isRegularWidth) * CGFloat(daysInWeek)
    }

    /// The width of one day column in `availableWidth` (the grid less its hour rail).
    ///
    /// Wider than the preference where there is room — a week is meant to fill its pane — and
    /// narrower where there is not, down to `minimumDayColumnWidth`. Under that there is nothing to
    /// be gained by shrinking further, so the grid falls back to the preferred width and scrolls,
    /// which is what a phone does and has always done: 393pt of iPhone leaves 49pt a column.
    ///
    /// **`dayCount` is how many columns are meant to be *visible*, not how many exist.** It used to
    /// be `dates.count`, which was the same number only because the grid rendered exactly one week
    /// and stopped. The grid now scrolls through hundreds of columns
    /// (`CadenceCalendarTimelineWindow`), so a column width divided by the number of columns in
    /// existence would come out at a fraction of a point. Dividing by the *visible* count is what
    /// makes the width fixed — the pane decides how many columns fit, not how many there are — and
    /// it is also what keeps `545f429`'s guarantee true: at `visibleDayCount(for: .week)` the
    /// arithmetic is "seven columns fill the pane exactly", so seven is what is on screen at every
    /// width, with the rest a scroll away.
    static func dayColumnWidth(
        availableWidth: CGFloat,
        dayCount: Int,
        isRegularWidth: Bool
    ) -> CGFloat {
        let preferred = preferredDayColumnWidth(isRegularWidth: isRegularWidth)
        guard dayCount > 0 else { return preferred }
        guard dayCount <= daysInWeek else { return max(multiWeekDayColumnWidth, preferred) }
        let fitted = availableWidth / CGFloat(dayCount)
        return fitted >= minimumDayColumnWidth ? fitted : preferred
    }

    /// How many day columns a view mode wants on screen at once.
    ///
    /// This is the whole of what a timed view mode means now. It used to also decide which days
    /// existed — Week built seven `Date`s and the chevrons rebuilt them a week at a time — and with
    /// the grid scrolling through a wide window that half of the job is gone.
    static func visibleDayCount(for viewMode: CadenceCalendarViewMode) -> Int {
        switch viewMode {
        case .week:     return daysInWeek
        case .twoWeeks: return daysInWeek * 2
        // Month does not use the timed grid at all; it has its own. Answering with a week keeps
        // this total rather than trapping, and nothing reaches it.
        case .month:    return daysInWeek
        }
    }

    /// How many whole columns of `columnWidth` fit in `availableWidth`.
    ///
    /// The restated form of the seven-column guarantee: `545f429` fixed a Week that put four and a
    /// half of its seven days behind a scroller, and with an infinitely scrolling grid the way to
    /// state that is no longer "the content is not wider than the pane" — the content is always
    /// wider than the pane now — but "at least this many columns are on screen".
    static func visibleColumnCount(availableWidth: CGFloat, columnWidth: CGFloat) -> Int {
        guard columnWidth > 0, availableWidth > 0 else { return 0 }
        // A hair of tolerance, because the fitted width is `available / 7` and floating point can
        // land the seventh column a ten-thousandth of a point over the edge.
        return Int(((availableWidth + 0.01) / columnWidth).rounded(.down))
    }
}

/// How the Calendar pane divides between the calendar itself and the day inspector.
///
/// `iOSCalendarView.regularInspectorWidth(for:)` was `min(max(width * 0.30, 340), 430)` — a floor
/// treated as a guarantee, and the same mistake `CadenceTodayLayoutSupport.taskPaneWidth` (then
/// spelled on `iOSTodayView`) was carrying.
/// On an 11" iPad in portrait the pane is 632pt: 30% of it is 190, the `max` raised that to 340, and
/// the inspector took **54% of the pane** away from the surface it annotates. What was left ran the
/// week grid at its 112pt minimum column width behind a horizontal scroller, so a week view showed
/// two of its seven days.
///
/// The inspector is a companion to the calendar, so the rule is simply that it never takes more than
/// the calendar does, and that below the width where two panes each clear its own minimum there is
/// no inspector at all — the calendar takes the pane, exactly as it does on a phone. The floor is
/// derived from the minimum rather than picked, so the two cannot drift apart.
enum CadenceCalendarPaneLayout {
    /// The least the day inspector will accept before its own rows start clipping. This was already
    /// the `max(...)` floor in `regularInspectorWidth(for:)`; it is a gate now instead of a promise.
    static let inspectorMinWidth: CGFloat = 340
    /// There is no maximum. `min(…, 430)` used to close this expression, and it needed 1434pt of
    /// pane to bind — 430 is 30% of 1433 — where the widest pane a target device produces is 1210:
    /// an 11" Pro in landscape with the shell sidebar folded. What actually bounds the inspector at
    /// every reachable width is the second clamp in `inspectorWidth`, which is what the calendar
    /// beside it needs.
    static let inspectorFraction: CGFloat = 0.30
    static let paneDividerWidth: CGFloat = 1

    /// 681pt of pane, for a calendar that states no minimum of its own. A 13" iPad in portrait
    /// (844pt) keeps the inspector at exactly the width it had before; an 11" in portrait (632pt)
    /// gives the whole pane to the calendar.
    static var splitMinimumWidth: CGFloat {
        inspectorMinWidth * 2 + paneDividerWidth
    }

    /// The inspector's share of the pane — never more than what is left once the calendar has taken
    /// the width it needs to draw itself.
    ///
    /// `calendarMinimumWidth` defaults to `inspectorMinWidth`, which is the stand-in the original
    /// `min(preferred, (paneWidth - paneDividerWidth) / 2)` amounted to: absent a real number from
    /// the surface being annotated, "at least as much as the thing annotating it" is the honest
    /// guess, and it is still the one Month's grid uses, which flexes. Week is the case where the
    /// guess was short by 500pt — see `CadenceCalendarWeekGridLayout`. At the default this returns
    /// exactly what it always did at every pane width where `showsInspector` is true.
    ///
    /// The Board no longer asks: its day columns each carry their own date header and their own
    /// items, so an inspector beside them restated a column already on screen. It takes the pane.
    ///
    /// Only meaningful where `showsInspector(paneWidth:calendarMinimumWidth:)` is true.
    static func inspectorWidth(
        forPaneWidth paneWidth: CGFloat,
        calendarMinimumWidth: CGFloat = inspectorMinWidth
    ) -> CGFloat {
        let preferred = max(paneWidth * inspectorFraction, inspectorMinWidth)
        return min(preferred, paneWidth - paneDividerWidth - calendarMinimumWidth)
    }

    /// What the calendar keeps when the inspector sits beside it.
    static func calendarWidth(
        forPaneWidth paneWidth: CGFloat,
        calendarMinimumWidth: CGFloat = inspectorMinWidth
    ) -> CGFloat {
        paneWidth - paneDividerWidth
            - inspectorWidth(forPaneWidth: paneWidth, calendarMinimumWidth: calendarMinimumWidth)
    }

    /// Whether both sides clear their own minimum — which is what this type always claimed to check
    /// and, until Week supplied a minimum, never did on the calendar's side.
    static func showsInspector(
        paneWidth: CGFloat,
        calendarMinimumWidth: CGFloat = inspectorMinWidth
    ) -> Bool {
        inspectorWidth(forPaneWidth: paneWidth, calendarMinimumWidth: calendarMinimumWidth)
            >= inspectorMinWidth
    }

    /// Whether the Calendar page draws the day inspector as a column beside the calendar.
    ///
    /// **Timeline only.** The Board is a row of day columns, each already headed with its own date
    /// and each already listing that day's items; an inspector beside it spent 340pt restating a
    /// column that was on screen a finger's width away, and cost the board a column and a half of
    /// the days it exists to show. The Board takes the whole pane.
    ///
    /// **Month is not routed through here.** It has two readings and two placements of its own and
    /// asks `CadenceCalendarMonthLayout` instead. Week supplies a `calendarMinimumWidth` that puts
    /// its split at 1183pt, which the target iPad reaches only in landscape with the shell sidebar
    /// folded — so `Day` is where the inspector usually lives.
    static func showsDayInspector(
        isCompact: Bool,
        presentation: CadenceCalendarPresentation,
        viewMode: CadenceCalendarViewMode,
        paneWidth: CGFloat
    ) -> Bool {
        guard !isCompact, presentation == .timeline, viewMode != .month else { return false }
        return showsInspector(
            paneWidth: paneWidth,
            calendarMinimumWidth: calendarMinimumWidth(for: viewMode)
        )
    }

    // The one-line day summary band under the toolbar is gone from the Calendar page entirely, and
    // with it the gate that used to decide where it appeared.
    //
    // It carried the selected date and a count of that day's items. The Board lost it first
    // (`42de745`): its columns *are* days, each already headed with its date and its count. Month
    // followed, for the same reason one step removed — the grid lights the day up in a cell that
    // prints the count. Week was the last holdout, kept because seven columns say which days exist
    // rather than which one you are on. What removed it there was the header becoming a date
    // control: `iOSDateJumpTitle` names the leftmost visible column, so the band's first line was
    // a second date a few points below the first. Its counts could not survive on their own —
    // stripped of the date they were a count with no subject, since the header names the leading
    // column and the band counted the *selected* day.

    /// What has to fit beside the inspector before there is one.
    ///
    /// Week is the mode that can answer this with a real number: an hour rail and seven day columns,
    /// none of which can be dropped, at the width a column needs to label a block with more than an
    /// ellipsis. The only other mode that reaches it is `.twoWeeks`, whose fourteen columns scroll
    /// by design and which the picker no longer offers, so it keeps the inspector's own width — the
    /// stand-in every mode used to use.
    static func calendarMinimumWidth(for viewMode: CadenceCalendarViewMode) -> CGFloat {
        viewMode == .week
            ? CadenceCalendarWeekGridLayout.fullSizeWidth(isRegularWidth: true)
            : inspectorMinWidth
    }
}

/// One column or two, inside a settings card that pairs a chooser with the thing it edits.
///
/// The seventh expression of the rule, and the first that is about a *card* rather than a page or a
/// pane. That is the whole of what T-248/T-249 were: the defect does not care how big the container
/// is, only that a fixed column was subtracted from a flexing one with nothing asserting what was
/// left.
nonisolated enum CadenceSettingsCardLayout: Equatable, Sendable {
    /// Chooser above the editor, both full width. On iOS this is the phone's form, which already
    /// ships; on macOS it is the same shape with the same rows.
    case oneColumn
    /// Chooser column beside the editor.
    case twoColumn
}

/// How the Settings → Templates card divides between its template chooser and the editor beside it.
///
/// **T-177's defect, one level down.** Both surfaces split unconditionally — iOS on
/// `horizontalSizeClass == .regular` alone, macOS on nothing at all — with a fixed
/// `.frame(width:)` chooser beside a `maxWidth: .infinity` editor and no floor under what was left.
/// Every term of the chain that ate the pane is chrome the card cannot see: on iOS, `paneWidth`
/// less the 248pt settings rail, its 1pt divider, `settingsDetailScroll`'s 28pt horizontal padding
/// on each side, `iOSSettingsCard`'s 16pt inset on each side, then the chooser, the divider and two
/// 16pt gaps — `paneWidth − 630`. Measured with an `NSHostingView` reproduction of that exact
/// modifier chain, the editor came out at **16.0pt on an iPad Pro 11" in portrait with the shell
/// sidebar out** (646pt of pane — the primary target device in its default configuration, no
/// multitasking), 0.0 at 570, 146 at 776, 204 at 834, 392 at 1022 and 580 at 1210. macOS's chain is
/// `paneWidth − 596` and its ordinary minimum pane — a 960pt window less the stored 264pt sidebar —
/// leaves the editor 100pt.
///
/// **The fallback is one column, not a dropped chooser**, and the two precedents in this file are
/// what decide it. `CadenceCalendarPaneLayout` drops its inspector because the inspector *restates*
/// a day column that is already on screen a finger's width away; nothing is lost. The template
/// chooser is the only thing that selects what the editor is editing, so dropping it leaves a card
/// permanently stuck on whichever template `selectedTemplateID` happens to hold. That makes this
/// `CadenceTodayLayoutSupport`'s case rather than the calendar's: below the floor, render the form
/// the narrow host already has.
///
/// The width this asks about is the one the split `HStack` is actually handed — the card's inner
/// content width, measured with `onGeometryChange` — and **not** the pane. Every term between the
/// two is chrome owned by the settings shell, and re-stating the shell's rail width and paddings
/// here would be a second copy of them that nothing would keep in step. The pane translation, for
/// the record and for the device the ticket was filed from: on iOS the card's content is
/// `paneWidth − 249 − 56 − 32`, so `twoColumnMinimumWidth` of 613 is reached at **950pt of pane**,
/// which an 11" iPad Pro sees in landscape (1022) and not in portrait (646).
nonisolated enum CadenceSettingsTemplatesCardLayout {
    /// macOS's chooser column, as `SettingsTemplatesSection` already had it.
    static let desktopChooserWidth: CGFloat = 230
    /// iOS's chooser column at regular width, as `iOSTemplatesSettingsSection` already had it. The
    /// two differ because the rows do — macOS sets a 12pt title where iOS sets 15 — and unifying
    /// them is a visual change this floor does not need to make.
    static let regularChooserWidth: CGFloat = 260
    /// The gap on each side of the divider. 16 on both surfaces already: `iOSEditorSheetMetrics
    /// .groupSpacing` on one and the `HStack`'s own spacing on the other.
    static let columnSpacing: CGFloat = 16
    /// The 1pt rule between the two columns. Counted, because a floor that forgets it is a floor
    /// that is one point wrong — the mistake `CadenceTodayLayoutSupport.taskPaneWidth` records.
    static let columnDividerWidth: CGFloat = 1

    /// The least the editor half may be handed before two columns is worse than one.
    ///
    /// **Borrowed, not invented**, and borrowed from the surface with the same content: it is
    /// `CadenceNotesListMetrics.minimumEditorWidth`, which is in turn
    /// `CadenceTodayLayoutSupport.inspectorPaneMinWidth`. The template editor is a title field, a
    /// description field and a markdown body well — a note editor with two fields over it — so "the
    /// least a markdown editor will accept before its own content starts clipping" is the same
    /// question, already answered at 320. Spelled as a reference so the three cannot drift.
    ///
    /// The corroboration is that the choice does not have to be exactly right to be right *here*.
    /// No plausible floor keeps the target iPad's portrait pane in two columns — even a 100pt
    /// editor would need 730pt of pane against the 646 it has — so the only band where the number
    /// changes an outcome is 776…950 of pane, and 834 (the same iPad with the shell sidebar folded)
    /// is the case that decides it: 204pt of markdown well beside a 260pt chooser is the "worse
    /// than one column" this floor exists to name.
    static var minimumEditorWidth: CGFloat { CadenceNotesListMetrics.minimumEditorWidth }

    static func chooserWidth(isDesktop: Bool) -> CGFloat {
        isDesktop ? desktopChooserWidth : regularChooserWidth
    }

    /// 613pt of card content on iOS, 583 on macOS. **A sum, not a constant** — widen the chooser and
    /// this moves with it, which is the whole reason it is spelled this way.
    static func twoColumnMinimumWidth(isDesktop: Bool) -> CGFloat {
        chooserWidth(isDesktop: isDesktop) + columnSpacing * 2 + columnDividerWidth + minimumEditorWidth
    }

    static func supportsTwoColumns(hostWidth: CGFloat, isDesktop: Bool) -> Bool {
        hostWidth >= twoColumnMinimumWidth(isDesktop: isDesktop)
    }

    /// The form the card renders, given the width its content was actually handed.
    ///
    /// **`hostWidth <= 0` means "not measured yet" and answers `.oneColumn`** — the opposite call
    /// from `CadenceNotesListMetrics.layout`, deliberately, and for the reason that file gives for
    /// making it the other way. There, the two-column form is what the host almost always resolves
    /// to, so assuming it avoids a flash. Here the majority host is the target iPad in portrait,
    /// which resolves to one column; and the guess that is wrong for one frame is the one that
    /// draws the 16pt editor this type exists to prevent. A frame of the fallback is a worse-looking
    /// correct layout; a frame of the split is the bug.
    static func layout(
        isRegularWidth: Bool,
        hostWidth: CGFloat,
        isDesktop: Bool
    ) -> CadenceSettingsCardLayout {
        guard isRegularWidth else { return .oneColumn }
        return supportsTwoColumns(hostWidth: hostWidth, isDesktop: isDesktop) ? .twoColumn : .oneColumn
    }
}

/// Which of Today's three panes a macOS window is wide enough to draw.
///
/// Ordered by what the page cannot do without. The task column is Today; the notepad and the
/// timeline are companions, and both have a whole page of their own — the daily note is the Notes
/// page's Daily tab, the day's timeline is the Calendar page.
nonisolated enum CadenceDesktopTodayLayout: Equatable, Sendable {
    /// Task column only.
    case tasksOnly
    /// Task column and the day's timeline.
    case tasksAndSchedule
    /// The full three-pane page.
    case notesTasksAndSchedule
}

/// How many panes each macOS `HSplitView` page can actually draw at the width it was handed.
///
/// **The eighth expression of the rule, and the first written because a *window* could not hold
/// it.** Today, Goals and Focus each declared more `HSplitView` minimum width than
/// `CadenceApp`'s 960pt window floor can pay, and an `HSplitView` propagates none of it upward:
/// measured with `NSHostingView`, each of the three splits reports `fittingSize.width == 0` and
/// `intrinsicContentSize.width == -1` whatever its children declare. So the floor never hears the
/// page, the window goes narrower than the page needs, and `NSSplitView` lays out at the sum of
/// its minimums and overflows **leading-aligned** — off the trailing edge.
///
/// What that looked like, measured at the 960pt floor with the sidebar at its 220pt minimum, its
/// stored 264pt default and its 390pt maximum (740 / 696 / 570 of pane):
///
///   - Today, `449 + 300 + 343` + 2 dividers = **1094**: `449, 290, 0` — `449, 246, 0` —
///     `449, 120, 0`. The Schedule pane is **entirely off the right edge in all three**, and so is
///     the divider that would drag it back.
///   - Goals, `560 + 340` + 1 = **901**: the inspector shows 179, 135 and **9** of its 340.
///   - Focus, `520 + 320` + 1 = **841**: the sidebar shows 219, 175 and **49** of its 320.
///
/// **The window floor was the other candidate and it was rejected on measurement, not taste.** The
/// pane is the window *less the sidebar*, and the sidebar is independently 220–390pt
/// (`macOSRootShellViews.swift`) and can be hidden outright with `Cmd+O`. A floor that pays for
/// Today's 1094 at the stored 264pt sidebar is 1358; at the 390pt maximum it is **1484**, which is
/// wider than a 13" MacBook Air's whole 1470pt screen — so the floor that actually closes the bug
/// makes the app unopenable at full width on a shipping Mac, and any floor short of it leaves the
/// bug live for everyone who has widened their sidebar. **A single window minimum cannot express a
/// rule whose input is `window − sidebar`.** It would also tax every page that already fits — the
/// 960 was derived from the list-detail Kanban tab bar and nothing else asks for more — and it
/// would not fix what is broken, because the next pane minimum anyone raises re-opens the same
/// silent overflow. Below, a raised minimum simply changes where a page folds.
///
/// **Which pane gives is decided per page, and each answer has a reason.**
///
/// *Today* drops the **notepad** first, and that is a measurement rather than a preference: the
/// ordinary minimum pane is 696 (960 less the stored sidebar), `tasks + schedule` is 644 and fits,
/// and `notes + tasks` is 750 and does not — dropping the notepad is the only two-pane form the
/// app's own minimum window can pay for. It is also the pair with a behaviour: a task dragged out
/// of the task column onto the timeline is the whole unprefixed drag payload in `TaskDragPayload`,
/// and it exists only while those two panes are on screen together. Below 644 the task column takes
/// the window.
///
/// *Goals* drops the **inspector** *as a column*. Its list column is not just a list — the page
/// header, the search field, the status filter and the only "New Goal" button are all inside it,
/// which is what the 560 is a floor for, so the list is not the side that can yield. The inspector
/// is already unusable rather than merely tight at every width below the floor: at the 390pt
/// sidebar it is nine points of a 340pt layout.
///
/// **But the inspector is not only a column, and T-271 is that correction.** Dropping it took Edit,
/// Attach List and per-list detach with it, and mission mode has no other route to any of the
/// three — so for one release the page traded an unusable control for an absent one. It is
/// `CadenceSettingsTemplatesCardLayout`'s case rather than `CadenceCalendarPaneLayout`'s in exactly
/// that respect: a day inspector restates a day column that is on screen a finger's width away and
/// costs nothing when it goes, whereas this one is the only thing that can *change* a goal. So
/// below 901 the same `GoalInspectorView` is reached by opening a card instead of by selecting it
/// (`GoalInspectorSheet`), which is `iOSFeatureRowLink`'s own rule — select beside a pane, push
/// without one — spelled for a page that has no navigation stack. The gate is still this one, read
/// once: it decides both whether the column is drawn and what tapping a card means.
///
/// *Focus* drops the **sidebar**, which is the `CadenceCalendarPaneLayout` case: a status chip
/// restating the session header and four "Next up" shortcuts into the same picker the idle screen
/// already is. The idle layout's trailing pane is a compact `SchedulePanel`, i.e. a second reading
/// of the Calendar page. Nothing there is reachable only from there.
///
/// Every floor is a **sum of the panes' own declared minimums**, and the views read the constants
/// back rather than re-typing them, so raising a pane moves the floor with it. That is the property
/// this whole file exists for; a floor typed as `1094` satisfies every value assertion on the day
/// it is written and stops following its parts the next day.
///
/// `paneWidth <= 0` means "not measured", and answers with the fewest panes for
/// `CadenceSettingsTemplatesCardLayout`'s reason: a frame of the fallback is a correct layout that
/// looks sparse, and a frame of the split is the bug. In practice the three surfaces read their
/// width from a `GeometryReader` they fill, so there is no unmeasured frame to guess at.
nonisolated enum CadenceDesktopSplitLayout {
    /// The `Divider` an `HSplitView` puts between two panes. Counted, for the reason
    /// `CadenceTodayLayoutSupport.taskPaneWidth` records: a floor that forgets it is a floor that
    /// is a point wrong, and a point is what comes off the trailing edge.
    static let paneDividerWidth: CGFloat = 1

    // MARK: - Today — notepad │ tasks │ schedule

    /// `NotePanel`'s declared minimum, as `TodayView` already had it.
    static let todayNotesPaneMinWidth: CGFloat = 449
    /// `TasksPanel`'s. **Not** `CadenceTodayLayoutSupport.taskPaneMinWidth`, which is 440: that is
    /// the iPad's task column, which is one of *two* panes and carries the day's whole task list
    /// with no notepad beside it. Two different pages that happen to share a name.
    static let todayTaskPaneMinWidth: CGFloat = 300
    /// `SchedulePanel`'s.
    static let todaySchedulePaneMinWidth: CGFloat = 343

    /// 1094pt of pane. Reached at the 960pt window floor only with the sidebar hidden and a window
    /// 134pt wider than the floor; at the stored sidebar it needs a 1358pt window.
    static var todayThreePaneMinimumWidth: CGFloat {
        todayNotesPaneMinWidth + todayTaskPaneMinWidth + todaySchedulePaneMinWidth
            + paneDividerWidth * 2
    }

    /// 644pt of pane — under the 696 the app's own minimum window leaves at the stored sidebar,
    /// which is the point of dropping the notepad rather than the timeline.
    static var todayTwoPaneMinimumWidth: CGFloat {
        todayTaskPaneMinWidth + todaySchedulePaneMinWidth + paneDividerWidth
    }

    static func todayLayout(paneWidth: CGFloat) -> CadenceDesktopTodayLayout {
        if paneWidth >= todayThreePaneMinimumWidth { return .notesTasksAndSchedule }
        return paneWidth >= todayTwoPaneMinimumWidth ? .tasksAndSchedule : .tasksOnly
    }

    // MARK: - Goals — mission list │ inspector

    /// The mission column's declared minimum, as `GoalsView` already had it. It is a floor for the
    /// page *header* inside it — title, view-mode toggle, New Goal, search, status filter — not
    /// for the cards, which is why this is not the side that yields.
    static let goalListPaneMinWidth: CGFloat = 560
    /// `GoalInspectorView`'s.
    static let goalInspectorPaneMinWidth: CGFloat = 340

    /// 901pt of pane.
    static var goalsSplitMinimumWidth: CGFloat {
        goalListPaneMinWidth + goalInspectorPaneMinWidth + paneDividerWidth
    }

    static func goalsShowsInspector(paneWidth: CGFloat) -> Bool {
        paneWidth >= goalsSplitMinimumWidth
    }

    // MARK: - Focus — session │ sidebar

    /// The timer-and-notes column's declared minimum, as all three of `FocusView`'s splits already
    /// had it — the active task layout, the active bundle layout and the idle picker.
    static let focusSessionPaneMinWidth: CGFloat = 520
    /// `FocusSidebar` / `FocusBundleSidebar` / the idle layout's compact `SchedulePanel`.
    static let focusSidebarPaneMinWidth: CGFloat = 320

    /// 841pt of pane.
    static var focusSplitMinimumWidth: CGFloat {
        focusSessionPaneMinWidth + focusSidebarPaneMinWidth + paneDividerWidth
    }

    static func focusShowsSidebar(paneWidth: CGFloat) -> Bool {
        paneWidth >= focusSplitMinimumWidth
    }
}

/// Which form the macOS Calendar Board's two pinned rails take at the width the page was handed.
///
/// **Collapsed is not dropped**, and that distinction is the whole of T-251. See
/// `CadenceCalendarBoardLayout` for why neither rail may vanish.
nonisolated enum CadenceCalendarBoardRailForm: Equatable, Sendable {
    /// The full inbox column: header, cards, add row, drop target.
    case expanded
    /// The same column reduced to what identifies it — its dot, its count and its name — and still
    /// a drop target. `CadenceRootShellLayout`'s labelled-column-to-icon-rail fallback, for a board.
    case collapsed
}

/// How the macOS Calendar Board divides its pane between the two pinned rails and the day columns
/// scrolling between them.
///
/// **The ninth expression of the rule, and the first where the *fixed* side is the one that has to
/// give.** `CalendarPageBoardView` is `HStack(spacing: 0) { rail; dayColumns; rail }` with each rail
/// at a fixed `expandedRailWidth` and the day columns a horizontal `ScrollView` at
/// `.frame(maxWidth: .infinity)`. A horizontal scroller declares no minimum — measured, the board
/// reports **496** as its own minimum, which is exactly the two rails — so the columns get
/// `paneWidth − 496`: **74.0pt at a 570 pane, 200.0 at 696, 244.0 at 740** and 464.0 at 960, against
/// a 306pt day column. At the app's own minimum window with the stored sidebar the Board showed two
/// thirds of one day column between two inboxes holding 71% of the surface.
///
/// **What gives is the rails, and the reason is which side is already unusable.** Goals' inspector
/// was nine points of a 340pt layout below its floor, so dropping it cost an already-unusable
/// control; here the rails render perfectly at every reachable width and the *day columns* are the
/// unreadable side. The subject of a board of days is the days.
///
/// **But the rails may not be dropped, and that is measured rather than assumed.** The
/// `CadenceCalendarPaneLayout` case — drop it, because it restates something on screen a finger's
/// width away — was checked against this surface and does not hold for either rail:
///
///   - *Overdue.* The board's day columns are floored at today
///     (`CalendarBoardPlannerSupport.plannerWindowStart(notBefore:)`) **because** this rail already
///     shows every past-dated card. The one route was removed in favour of the other; dropping the
///     rail leaves neither, and the Board would then have no reading of late work at all.
///   - *Unscheduled.* `tasksByBoardDate` buckets strictly by do date, so a task with no do date has
///     no day column anywhere on the board. The Timeline presentation's all-day chips are **not**
///     the same set: `CadenceScheduleSupport.unscheduledTasksByDate` requires `!scheduledDate
///     .isEmpty` — it means "has a day, no start minute", the opposite population.
///
/// So this is `CadenceSettingsTemplatesCardLayout`'s case, not the calendar inspector's: the fallback
/// is a reduced form of the same thing, not its absence. A collapsed rail keeps its dot, its count,
/// its name and — the part that matters — its **drop destination**, so dragging a card out of a day
/// column onto Unscheduled still works at every width. Tapping one expands it in place over the
/// board, which is the only state where a day column is squeezed and is the user's own, reversible,
/// one-click choice.
///
/// **Three alternatives were rejected on measurement.**
///
/// 1. *Compress the rails instead of collapsing them.* `CadenceCalendarWeekGridLayout`'s shape, and
///    it cannot reach. The narrowest reachable pane is 570 (the 960pt window floor less the 390pt
///    maximum sidebar), which leaves 220pt for two rails once one whole day column is paid for —
///    110pt each, narrower than any column of `KanbanCard`s in the app. Compression would only
///    change the answer between 750 and 846pt of pane, and buying that band costs a second mechanism
///    and a second invented minimum.
/// 2. *Un-pin the rails into the same horizontal scroller.* Nothing is dropped and the day columns
///    get the whole pane, but the pair loses its behaviour: dragging a card from a day column to
///    Unscheduled needs both on screen at once, and un-pinned they never are below 816pt. That is
///    the same argument that keeps Today's task column and timeline together.
/// 3. *Raise `CadenceApp`'s window floor.* Rejected by `CadenceDesktopSplitLayout` already, for a
///    reason that applies unchanged here: the pane is `window − sidebar` and the sidebar is
///    independently 220–390pt and hideable, so no single window minimum can express it.
// Not `nonisolated`, unlike `CadenceSettingsTemplatesCardLayout` and `CadenceDesktopSplitLayout`
// above, and the reason is the borrowed floor: `collapsedRailWidth` reads
// `CadenceCalendarWeekGridLayout.minimumTouchTarget`, and that type — like `CadenceRegularSplitLayout`
// and `CadenceCalendarPaneLayout`, its neighbours here — takes the project's default actor
// isolation. A `nonisolated` type reading a main-actor static is a main-actor isolation warning
// against a zero baseline, and the two ways out are to stop borrowing (which is the whole point of
// the reference) or to sit where the thing it borrows from sits. This sits.
enum CadenceCalendarBoardLayout {
    // MARK: The board's own parts
    //
    // These four moved here from `Cadence/macOS/Views/KanbanBoardSupport.swift`, which is behind
    // `#if os(macOS)` and so cannot be read by a file that is not. They are the parts the floor
    // below is a sum of, and the register's second reason is why they had to travel with it: a
    // floor in one file whose terms live in another stops following them.

    /// The Calendar Board's day columns run wider than a kanban column because they stack calendar
    /// events and bundle blocks above the task cards, not task cards alone.
    static let dayColumnWidth: CGFloat = 306
    /// The `LazyHStack`'s inset at each end of the day-column run.
    static let dayColumnHorizontalPadding: CGFloat = 22
    /// The gap between two day columns.
    static let dayColumnSpacing: CGFloat = 14
    /// The Overdue / Unscheduled rails are inboxes rather than days, so they sit narrower than a day
    /// column. `CadenceBoardColumnHeader` fills whatever width it is handed, so the narrower rail
    /// still lines its dot, label, count and closing hairline up with the day columns beside it.
    static let expandedRailWidth: CGFloat = 248
    /// A rail's own inset, matching `CalendarBoardDayColumn`'s so the two headers share a baseline.
    static let railHorizontalPadding: CGFloat = 8

    /// The rotated name on a collapsed rail needs a slot tall enough for the longest of them —
    /// "UNSCHEDULED" at `CadenceBoardColumnHeaderMetrics.labelSize`. A rotation is a render
    /// transform and does not change layout bounds, so the slot has to be stated rather than
    /// measured.
    static let collapsedRailLabelSlotHeight: CGFloat = 96

    // MARK: The guarantee

    /// One whole day column with the run's inset on both sides — 350pt. The least the scrolling
    /// region can be handed and still show the thing the Board is a board *of*.
    ///
    /// One rather than two deliberately. Two columns and the gap between them is 670, which with
    /// two expanded rails needs 1166pt of pane — a 1430pt window at the stored sidebar, wider than
    /// the target Mac. One column is what the app's own minimum window can be made to pay for, and
    /// `dayColumnSpacing` is not in the sum because nothing is guaranteed to sit beside it.
    static var oneDayColumnMinimumWidth: CGFloat {
        dayColumnWidth + dayColumnHorizontalPadding * 2
    }

    /// **Borrowed, not invented.** A collapsed rail is not primarily a click target — it is a *drop*
    /// target, hit under a card already in motion — so the floor any control has to clear applies to
    /// it at least as strongly as to a button. That floor is stated once in this file already, as
    /// `CadenceCalendarWeekGridLayout.minimumTouchTarget`, and it is spelled as a reference here for
    /// the reason `CadenceSettingsTemplatesCardLayout.minimumEditorWidth` is: typing `44` satisfies
    /// every value assertion on the day it is written and stops following its source the next.
    /// Plus the rail's own inset on each side, which is `minimumDayColumnWidth`'s construction.
    static var collapsedRailWidth: CGFloat {
        CadenceCalendarWeekGridLayout.minimumTouchTarget + railHorizontalPadding * 2
    }

    /// 846pt of pane — two expanded rails and one whole day column. Above this the Board is exactly
    /// what it was; below it the rails collapse.
    ///
    /// A sum of this type's own parts, so widening a rail or a day column moves the gate with it.
    /// Reached at the 960pt window floor only with the sidebar hidden; at the stored 264pt sidebar
    /// it needs a 1110pt window, and a MacBook Pro 14" at 1512 has always cleared it — which is why
    /// this shipped.
    static var expandedRailsMinimumWidth: CGFloat {
        expandedRailWidth * 2 + oneDayColumnMinimumWidth
    }

    /// The form both rails take unasked.
    ///
    /// `paneWidth <= 0` means "not measured" and answers `.collapsed`, for
    /// `CadenceSettingsTemplatesCardLayout`'s reason: a frame of the fallback is a correct layout
    /// that looks sparse, and a frame of the wide form is the 74pt day column this type exists to
    /// prevent. In practice the Board fills its pane in both axes and reads the width from a
    /// `GeometryReader`, so there is no unmeasured frame.
    static func railForm(paneWidth: CGFloat) -> CadenceCalendarBoardRailForm {
        paneWidth >= expandedRailsMinimumWidth ? .expanded : .collapsed
    }

    /// What one rail is drawn at in a given form. Not width-derived — a rail the user has expanded
    /// under the gate is expanded at whatever width the pane happens to be.
    static func railWidth(form: CadenceCalendarBoardRailForm) -> CGFloat {
        form == .expanded ? expandedRailWidth : collapsedRailWidth
    }

    /// What the scrolling day-column region is actually handed, both rails in their unasked form.
    /// This is the number T-251 measured, and the guarantee is that it never falls below
    /// `oneDayColumnMinimumWidth` at any pane the app can produce.
    static func dayColumnsWidth(paneWidth: CGFloat) -> CGFloat {
        max(0, paneWidth - railWidth(form: railForm(paneWidth: paneWidth)) * 2)
    }
}
