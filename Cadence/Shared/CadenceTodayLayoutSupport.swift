import CoreGraphics

/// Which Today layout a pane of a given width can actually render.
enum CadenceTodayLayout: Equatable {
    /// One scrolling column. Compact width, and any regular width too narrow for two.
    case compact
    /// Task column plus one switchable inspector (notes *or* timeline).
    case twoPane
}

/// The width arithmetic behind `iPadTodayView`'s layout choice.
///
/// **There is one iPad Today layout with a choice in it, and this is not it.** Today is task column
/// plus inspector, or one column when even that does not fit; the inspector's Notes/Timeline
/// switcher is the only thing the user picks. A third, Mac-shaped `notes | tasks | timeline` layout
/// and the `iPadTodayLayoutMode` picker that selected it — in the Today header *and* again in
/// Settings → Navigation — were deleted at the user's direction, even though an 11" or 13" Pro in
/// landscape could reach the 1022pt floor it needed.
///
/// The stored preference behind that picker was `ios.today.layoutMode`, a `UserDefaults` key and
/// **not** a SwiftData property, so removing it drops a preference rather than data. Nothing reads
/// the key any more, which is what makes a stored `mac` safe: `layout(...)` no longer takes a
/// preference at all, so there is no path by which one can select a layout that does not exist.
/// `CadenceTodayLayoutSupportTests` pins that — the function's whole range is `.compact` and
/// `.twoPane`.
enum CadenceTodayLayoutSupport {
    /// The task column's declared `minWidth`. It is the column the inspector exists to serve, so it
    /// is the one that must not be starved.
    static let taskPaneMinWidth: CGFloat = 440
    static let paneDividerWidth: CGFloat = 1

    /// `iPadTodayView.sidePanelMinWidth(for:)`'s narrow value — the least the notes/timeline
    /// inspector will accept before its own content starts clipping.
    static let inspectorPaneMinWidth: CGFloat = 320

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
}
