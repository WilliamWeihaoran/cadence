import CoreGraphics

/// Which Today layout a pane of a given width can actually render.
enum CadenceTodayLayout: Equatable {
    /// One scrolling column. Compact width only.
    case compact
    /// Task column plus one switchable inspector (notes *or* timeline).
    case twoPane
    /// Notes, tasks and timeline side by side — the Mac's Today shape.
    case threePane
}

/// The width arithmetic behind `iPadTodayView`'s layout choice.
///
/// This exists because the three-pane threshold was a bare `width >= 1_500` literal, and no iPad
/// has ever been that wide: the widest is the 13" iPad Pro at 1366–1376pt, and Today is measured
/// *after* the 188pt shell sidebar, so the real ceiling is around 1188pt. `iPadTodayLayoutMode.mac`
/// was therefore a mode the user could pick in two places that did nothing on every shipping
/// device.
///
/// The floor is derived from the panes rather than picked, so it cannot drift away from the layout
/// it is gating: it is exactly the width at which the three columns and their two dividers first
/// fit at their own minimums. Lower it and the notes or schedule column starts getting squeezed
/// below the width it declares it needs.
enum CadenceTodayLayoutSupport {
    /// `min(max(width * 0.23, 280), 340)` in `threePaneTodayLayout` — 280 is the floor.
    static let notesPaneMinWidth: CGFloat = 280
    /// `min(max(width * 0.24, 300), 360)` — 300 is the floor.
    static let schedulePaneMinWidth: CGFloat = 300
    /// The task column's declared `minWidth`. It is the column the other two exist to serve, so it
    /// is the one that must not be starved.
    static let taskPaneMinWidth: CGFloat = 440
    static let paneDividerWidth: CGFloat = 1

    /// 1022pt of *pane* width. Reached by an 11" and a 13" iPad Pro in landscape (1210pt and
    /// 1376pt of window, less the 188pt sidebar) and by nothing narrower.
    static var threePaneMinimumWidth: CGFloat {
        notesPaneMinWidth + schedulePaneMinWidth + taskPaneMinWidth + paneDividerWidth * 2
    }

    static func supportsThreePane(paneWidth: CGFloat) -> Bool {
        paneWidth >= threePaneMinimumWidth
    }

    /// `iPadTodayView.sidePanelMinWidth(for:)`'s narrow value — the least the notes/timeline
    /// inspector will accept before its own content starts clipping.
    static let inspectorPaneMinWidth: CGFloat = 320

    /// 761pt of pane. Two panes had **no** floor: `layout(...)` returned `.twoPane` for every
    /// regular-width device however little room there was, and only the three-pane case was gated.
    ///
    /// On an 11" iPad in portrait that meant 632pt split into a 312pt task column beside the
    /// inspector — narrow enough that the column could not fit its own header, which wrapped the
    /// date to "SUND AY, …" and truncated the layout picker to "Fo…". Below this floor a single
    /// full-width column is simply better than two starved ones.
    static var twoPaneMinimumWidth: CGFloat {
        taskPaneMinWidth + inspectorPaneMinWidth + paneDividerWidth
    }

    static func supportsTwoPane(paneWidth: CGFloat) -> Bool {
        paneWidth >= twoPaneMinimumWidth
    }

    /// The layout to render, given the user's stored preference and the space actually available.
    ///
    /// A stored preference is never discarded — an iPad that cannot fit three panes today is one
    /// rotation or one Split View drag away from being able to, and the same iCloud account may be
    /// driving a wider device.
    static func layout(
        prefersThreePane: Bool,
        isRegularWidth: Bool,
        paneWidth: CGFloat
    ) -> CadenceTodayLayout {
        guard isRegularWidth else { return .compact }
        if prefersThreePane && supportsThreePane(paneWidth: paneWidth) { return .threePane }
        return supportsTwoPane(paneWidth: paneWidth) ? .twoPane : .compact
    }
}
