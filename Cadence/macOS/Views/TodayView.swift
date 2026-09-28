#if os(macOS)
import SwiftUI

struct TodayView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        // The pane width read here is the guarantee; the three `minWidth`s below are wishes an
        // `HSplitView` will happily overflow rather than report upward. See
        // `CadenceDesktopSplitLayout` for the measurement and for why the window floor was not the
        // place to fix it. A `GeometryReader` rather than `onGeometryChange` because this split
        // fills its pane in both axes, so it takes the proposal instead of sizing from content —
        // and so there is no unmeasured first frame to guess a layout for.
        GeometryReader { proxy in
            split(layout: CadenceDesktopSplitLayout.todayLayout(paneWidth: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        // **The page's corner, not the task column's (T-1503).** The owner asked for the `+` "at
        // the bottom right of the page", and this is the modifier every other macOS task page
        // already captures through — `TasksPageView` and `ListTasksView` both take it. Nothing new
        // was spelled for it: `iOSFloatingCreateTaskButton` is the iOS half of the same pair and
        // cannot be reached from here (`#if os(iOS)`, and it carries drag-to-seed and
        // hold-for-palette machinery macOS has no gesture for).
        //
        // It sits *below* the timeline's own export and zoom controls, which are that pane's
        // top-trailing corner, so the two do not meet.
        //
        // The seed survives the move: this is the day's page, and the button it replaces already
        // opened the composer with today's do date filled in.
        .floatingNewTaskButton {
            taskCreationManager.present(doDateKey: DateFormatters.todayKey())
        }
        .accessibilityIdentifier("screen.today")
    }

    @ViewBuilder
    private func split(layout: CadenceDesktopTodayLayout) -> some View {
        HSplitView {
            if layout == .notesTasksAndSchedule {
                NotePanel(useStandardHeaderHeight: true)
                    .frame(minWidth: CadenceDesktopSplitLayout.todayNotesPaneMinWidth, idealWidth: 588)
                    .layoutPriority(0.34)
                    // Named so a test can tell "the note's picture is missing" from "this window is
                    // too narrow for the notes column to be drawn at all". They are different
                    // findings and only one of them is a defect.
                    //
                    // **`.contain` is load-bearing, not decoration.** An identifier on a view that
                    // is not itself an accessibility element produces no element to find: measured
                    // 2026-09-06, `screen.today` a few lines below has been on this file since it
                    // was written and does not appear in the app's accessibility tree at all. The
                    // grouping is what creates the element the identifier then names.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(CadenceAccessibilityIdentifiers.todayNotesPane)
            }

            TasksPanel(
                enableControls: true,
                useStandardHeaderHeight: true,
                // Only when this pane *is* the page. See `TasksPanel.bottomClearance`.
                bottomClearance: layout == .tasksOnly ? FloatingNewTaskButton.scrollClearance : 0
            )
            .frame(minWidth: CadenceDesktopSplitLayout.todayTaskPaneMinWidth, idealWidth: 440)
            .layoutPriority(0.43)

            if layout != .tasksOnly {
                SchedulePanel(useStandardHeaderHeight: true)
                    .frame(minWidth: CadenceDesktopSplitLayout.todaySchedulePaneMinWidth, idealWidth: 406)
                    .layoutPriority(0.23)
            }
        }
    }
}
#endif
