import CoreGraphics

// MARK: - The register: where "derive a pane decision from handed width" may live
//
// One rule, seven expressions, four files — and this is the house file, so the register lives here
// rather than in a doc that the code cannot be checked against. T-182 was raised as "four
// expressions in four places"; the count was short by two, and T-248/T-249 added the seventh. What
// is actually there:
//
//   Here, in `CadenceRegularPaneLayout.swift`
//     - `CadenceRegularSplitLayout`     a *width*, for a chooser column beside a detail.
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
/// spelled on `iPadTodayView`) was carrying.
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
