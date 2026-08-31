#if os(macOS)
import SwiftUI

let todayPanelHeaderHeight: CGFloat = 100

/// Name only. See `DesktopPageHeader`, which this is the `.pane`-role spelling of.
///
/// The name survives because "panel header" is what the header of one of Today's three columns is,
/// and because its callers — the notepad and the schedule — are exactly that. (The task column
/// reaches `DesktopPageHeader` directly through `TasksPanelHeader`, which carries a count and a
/// capture button this wrapper does not take.)
///
/// It set its title at the full page size, so Today drew three column headings at the volume the
/// Inbox uses for the whole screen, on the one page that has no page title above them at all.
/// iPad Today's task column had the same bug and is already `.pane`; this is the same fix.
///
/// `background: nil` because the hosts paint their own plate behind the header band.
///
/// **Both remaining callers pass no eyebrow, and that is the point (T-602).** They read
/// `NOTES / Today` and `SCHEDULE / Timeline` — an eyebrow naming the column over a title naming the
/// same column again, which is the header-describes-its-own-page rule one row down, the same defect
/// `TasksPanelHeader` was fixed for. The task column had a second fact to promote (the date, and the
/// day's summary beside it); these two have none, so the honest fix is one name each rather than an
/// invented one. iPad reached the same answer from the other side: its notes and timeline panes draw
/// no header at all, because `iPadTodayInspectorSwitcher` already names them — see
/// `iOSTodaySchedulePanel` and `iOSNotesView.showsTitle`. macOS keeps the title because three
/// columns stand side by side here with nothing else naming them.
///
/// The cost, stated: with no eyebrow line, these two titles sit ~14pt higher in the 100pt header
/// band than the task column's, which keeps its date. The band and the divider under it are
/// unchanged, so the columns still meet at the same edge.
struct PanelHeader: View {
    /// `nil` wherever the column has no second fact to say. See the note above: an eyebrow that
    /// only renames the title is what this parameter stopped being used for.
    var eyebrow: String? = nil
    let title: String

    var body: some View {
        DesktopPageHeader(
            role: .pane,
            eyebrow: eyebrow,
            title: title,
            background: nil,
            spreads: false
        )
    }
}
#endif
