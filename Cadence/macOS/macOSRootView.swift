#if os(macOS)
import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case today
    case inbox
    case area(UUID)
    case project(UUID)
    case goals
    case habits
    case notes
    case calendar
    case focus
}

struct macOSRootView: View {
    @State private var selection: SidebarItem? = .today
    @Environment(FocusManager.self) private var focusManager

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .today, .none:
                TodayView()
            case .inbox:
                InboxPlaceholderView()
            case .area(let id):
                AreaDetailLoader(id: id)
            case .project(let id):
                ProjectDetailLoader(id: id)
            case .goals:
                GoalsView()
            case .habits:
                HabitsView()
            case .notes:
                NotesView()
            case .calendar:
                CalendarPageView()
            case .focus:
                FocusView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .onChange(of: focusManager.isRunning) {
            // When focus is started from a task row, navigate to focus view
        }
    }
}

private struct InboxPlaceholderView: View {
    var body: some View {
        ZStack {
            Theme.bg
            EmptyStateView(message: "Inbox coming soon", icon: "tray.fill")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
