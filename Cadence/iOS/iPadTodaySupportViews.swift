#if os(iOS)
import SwiftUI

/// Today's page header — and, since the layout picker left it, Today's *only* chrome row.
///
/// Two things moved onto this row rather than keeping a band each below it:
/// - **The sort / completed controls.** `iOSTaskViewOptionsBar` sat in a 13pt-padded deck of its
///   own directly underneath, which cost ~70pt of the task column to hold two chips that fit in
///   the space the picker vacated. It is the same shared bar the Inbox and All Tasks use, hosted
///   with `spreads: false` so its internal `Spacer` does not fight this row's.
/// - **The day's summary**, into the eyebrow beside the date. Left where it was it would have been
///   a padded band holding one dim sentence — the exact "row existing to hold one thing" shape the
///   Notes header fix deleted — and a *conditional* one at that (`CadenceTodaySummary.line` is nil
///   on an unplanned day), so the band would appear and vanish under the header as the day filled.
///   The date and the summary are both already `Theme.dim`; side by side they read as one quiet
///   line, with the date keeping its uppercase/kerned treatment and the summary in sentence case
///   so the two halves stay distinguishable.
///
/// Both of those are now `iOSPageHeader`'s own: the trailing slot and `eyebrowDetail`. This is a
/// `.pane` header, because the task column is one of Today's panes and not the page — the date
/// above it is not the screen's only title. The count moved from beside the title to the trailing
/// edge, which is where the other five headers put it and where it now sits next to the bar it
/// counts for. The 92pt fixed height went with the hand-tuned type: the row's content is a 44pt
/// control against two lines of text either way, so it does not need pinning to stay still.
struct iPadTodayTaskHeader: View {
    let eyebrow: String
    let title: String
    let summary: CadenceTodaySummary
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool

    /// The same gate the compact layout puts on its own bar. It was unconditional here, so a
    /// surface that ever stopped offering these controls would have lost them on the phone and kept
    /// them on the tablet — the exact shape of divergence `CadenceTaskSurfaceOptions` exists to
    /// rule out, left open by one call site not asking.
    private var options: CadenceTaskViewOptions {
        CadenceTaskSurfaceOptions.options(for: .today)
    }

    var body: some View {
        iOSPageHeader(
            role: .pane,
            eyebrow: eyebrow,
            // The half that gives way: `iOSPageHeader` gives the eyebrow proper the layout
            // priority, so a squeezed header truncates "· 3 timed" before "SUNDAY, AUGUST 17".
            eyebrowDetail: summary.line,
            title: title,
            color: Theme.amber,
            count: summary.activeCount
        ) {
            if options.showsSort || options.showsCompletedToggle {
                iOSTaskViewOptionsBar(
                    sortMode: $sortMode,
                    showCompleted: $showCompleted,
                    completedCount: summary.completedCount,
                    spreads: false
                )
            }
        }
        .background(Theme.surface)
    }
}

/// The inspector pane's only chrome row: which of the two panels it is showing, and nothing else.
///
/// It used to be a title reading `selection.title` beside this picker, above a pane whose own
/// header read `SCHEDULE / Timeline` — the word "Timeline" three times within 120pt, the first two
/// of them naming the panel already selected in the control on the same row. That is the Notes
/// header bug `775833d` fixed, and the fix is the same one: the panel keeps its identity, the
/// duplicates go. The hosted panels draw no title of their own here, so this row is the pane's
/// header rather than an extra one above it.
struct iPadTodayInspectorSwitcher: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        HStack(spacing: 12) {
            iOSSegmentedPillGroup {
                ForEach(iPadTodaySidePanel.allCases) { panel in
                    iOSSegmentedPill(
                        title: panel.title,
                        systemImage: panel.icon,
                        isSelected: selection == panel,
                        minWidth: 84
                    ) {
                        selection = panel
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }
}

enum iPadTodaySidePanel: String, CaseIterable, Identifiable {
    case notes
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .timeline: return "Timeline"
        }
    }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .timeline: return "clock"
        }
    }
}

#endif
