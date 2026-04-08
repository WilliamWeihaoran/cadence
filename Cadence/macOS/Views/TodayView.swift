#if os(macOS)
import SwiftUI

struct TodayView: View {
    var body: some View {
        HSplitView {
            NotePanel()
                .frame(minWidth: 449, idealWidth: 588)
                .layoutPriority(0.34)

            TasksPanel(enableControls: true)
                .frame(minWidth: 300, idealWidth: 440)
                .layoutPriority(0.43)

            SchedulePanel()
                .frame(minWidth: 343, idealWidth: 406)
                .layoutPriority(0.23)
        }
        .background(Theme.bg)
    }
}
#endif
