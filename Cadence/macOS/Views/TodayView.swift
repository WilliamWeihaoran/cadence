#if os(macOS)
import SwiftUI

struct TodayView: View {
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
        .accessibilityIdentifier("screen.today")
    }

    @ViewBuilder
    private func split(layout: CadenceDesktopTodayLayout) -> some View {
        HSplitView {
            if layout == .notesTasksAndSchedule {
                NotePanel(useStandardHeaderHeight: true)
                    .frame(minWidth: CadenceDesktopSplitLayout.todayNotesPaneMinWidth, idealWidth: 588)
                    .layoutPriority(0.34)
            }

            TasksPanel(enableControls: true, useStandardHeaderHeight: true)
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
