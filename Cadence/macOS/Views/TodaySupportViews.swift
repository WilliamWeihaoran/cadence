#if os(macOS)
import SwiftUI

/// The height every one of Today's three columns reserves for its header, so the three dividers
/// under them meet at one line. **One constant, not three** — `NotePanel`, `TasksPanel` and
/// `SchedulePanel` all read this name, which is what made T-1503's third part a one-line change.
///
/// **80, not 100 (T-1503), and the three figures below are measured rather than reasoned.**
/// `NSHostingView.fittingSize` on each of the three headers, at both 300pt (the task column's
/// declared minimum) and 440pt (its ideal), which answered identically at both:
///
///   - notes — `PanelHeader(title: "Notes")` at **49**, over a 30pt `NotePanelTabButton` strip: **79**
///   - tasks — `TasksPanelHeader` at **68**, with or without the Sort pill in its trailing slot
///   - timeline — `SchedulePanelHeader` at **49**, its export and zoom buttons riding inside the title row
///
/// So the band is the *tallest* column's, which is the notes column's 79, plus a point. It was 100
/// because the task column used to need two rows — the day header, and a second row under it
/// holding the Sort pill alone, 30pt of pill over 10pt of inset. That put the task column at 108
/// and it was the only column that came near the band at all; the other two spent the difference as
/// dead space, and the owner photographed exactly that in the notes column, between its tab strip
/// and its markdown toolbar, in a pane that has no sort pill to show for it.
///
/// The pill is in the task header's trailing slot now (see `TasksPanelHeader`), the second row is
/// gone, and every column moves up 20pt. The tasks and timeline columns still keep slack — 12 and
/// 31 — because one band is what makes three dividers meet at one line. That is the cost, and it is
/// 20pt cheaper than it was.
let todayPanelHeaderHeight: CGFloat = 80

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
/// The cost, stated: with no eyebrow line, these two titles sit ~14pt higher in the header band
/// than the task column's, which keeps its date. The band and the divider under it are the same
/// for all three, so the columns still meet at the same edge. (The band itself is 20pt shorter
/// since T-1503 — see `todayPanelHeaderHeight` above.)
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
