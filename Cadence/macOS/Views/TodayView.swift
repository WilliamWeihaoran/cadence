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

// MARK: - Panel Header

struct PanelHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
#endif
