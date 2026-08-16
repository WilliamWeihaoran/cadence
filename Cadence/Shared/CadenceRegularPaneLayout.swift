import CoreGraphics

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

/// How the Calendar pane divides between the calendar itself and the day inspector.
///
/// `iOSCalendarView.regularInspectorWidth(for:)` was `min(max(width * 0.30, 340), 430)` — a floor
/// treated as a guarantee, and the same mistake `iPadTodayView.taskPaneWidth(for:)` was carrying.
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
    static let inspectorMaxWidth: CGFloat = 430
    static let inspectorFraction: CGFloat = 0.30
    static let paneDividerWidth: CGFloat = 1

    /// 681pt of pane. A 13" iPad in portrait (844pt) keeps the inspector at exactly the width it had
    /// before; an 11" in portrait (632pt) gives the whole pane to the calendar.
    static var splitMinimumWidth: CGFloat {
        inspectorMinWidth * 2 + paneDividerWidth
    }

    static func showsInspector(paneWidth: CGFloat) -> Bool {
        paneWidth >= splitMinimumWidth
    }

    /// Only meaningful where `showsInspector(paneWidth:)` is true.
    static func inspectorWidth(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        let preferred = min(max(paneWidth * inspectorFraction, inspectorMinWidth), inspectorMaxWidth)
        return min(preferred, (paneWidth - paneDividerWidth) / 2)
    }
}
