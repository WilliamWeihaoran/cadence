#if os(macOS)
import SwiftUI

struct TodayView: View {
    private var dateString: String {
        DateFormatters.longDate.string(from: Date())
    }

    var body: some View {
        HSplitView {
            NotePanel()
                .frame(minWidth: 240, idealWidth: 300)

            TasksPanel()
                .frame(minWidth: 260, idealWidth: 320)

            SchedulePanel()
                .frame(minWidth: 280, idealWidth: 360)
        }
        .background(Theme.bg)
        .navigationTitle("Today")
        .navigationSubtitle(dateString)
    }
}

// MARK: - Panel Header

struct PanelHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
#endif
