#if os(macOS)
import SwiftUI

struct TodayView: View {
    var body: some View {
        HSplitView {
            NotePanel(useStandardHeaderHeight: true)
                .frame(minWidth: 449, idealWidth: 588)
                .layoutPriority(0.34)

            TasksPanel(enableControls: true, useStandardHeaderHeight: true)
                .frame(minWidth: 300, idealWidth: 440)
                .layoutPriority(0.43)

            SchedulePanel(useStandardHeaderHeight: true)
                .frame(minWidth: 343, idealWidth: 406)
                .layoutPriority(0.23)
        }
        .background(Theme.bg)
    }
}
#endif
