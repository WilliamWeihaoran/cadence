#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

enum SidebarItem: Hashable {
    case today
    case allTasks
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
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(\.modelContext) private var modelContext
    @State private var keyMonitor: Any? = nil

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selection: $selection)
            } detail: {
                switch selection {
                case .today, .none:
                    TodayView()
                case .allTasks:
                    AllTasksPageView()
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

            if taskCreationManager.isPresented {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clearAppEditingFocus()
                            taskCreationManager.dismiss()
                        }

                    CreateTaskSheet(seed: taskCreationManager.seed)
                        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                        .onTapGesture {
                            // Prevent outside tap handler from firing when clicking inside the panel.
                        }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            installKeyMonitorIfNeeded()
            GlobalHotKeyManager.shared.registerIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
            GlobalHotKeyManager.shared.unregister()
        }
        .onChange(of: focusManager.isRunning) {
            // When focus is started from a task row, navigate to focus view
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
                return event
            }

            switch event.keyCode {
            case 51:
                guard let task = hoveredTaskManager.hoveredTask else { return event }
                modelContext.delete(task)
                hoveredTaskManager.hoveredTask = nil
                return nil
            case 14:
                if hoveredEditableManager.triggerEdit() {
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct AllTasksPageView: View {
    private enum AllTasksViewMode: String, CaseIterable {
        case byDoDate = "By Do Date"
        case kanban = "Kanban"
    }

    @State private var mode: AllTasksViewMode = .byDoDate
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("All Tasks")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Browse everything by do date or by list, then open the full task creator from here.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Button {
                    taskCreationManager.present()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("New Task")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                HStack(spacing: 2) {
                    ForEach(AllTasksViewMode.allCases, id: \.self) { viewMode in
                        Button(viewMode.rawValue) { mode = viewMode }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: mode == viewMode ? .semibold : .regular))
                            .foregroundStyle(mode == viewMode ? Theme.blue : Theme.dim)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(mode == viewMode ? Theme.blue.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            Group {
                switch mode {
                case .byDoDate:
                    TasksPanel(mode: .byDoDate, showsHeader: false)
                case .kanban:
                    TaskListsKanbanView()
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("All Tasks")
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
