#if os(iOS)
import SwiftData
import SwiftUI

enum iOSSidebarItem: Hashable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case goals
    case habits
    case notes
    case lists
    case search
    case settings
    case area(UUID)
    case project(UUID)
}

struct iOSRootView: View {
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasksForNotifications: [AppTask]
    @Query private var allHabitsForNotifications: [Habit]
    @State private var selection: iOSSidebarItem? = .today
    @State private var compactPath: [CadenceFeatureDestination] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadMacStyleRootShell(selection: $selection) {
                    detailView(for: selection ?? .today)
                }
            } else {
                iOSCompactRootShell(path: $compactPath)
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .statusBarHidden(horizontalSizeClass == .regular)
        .onOpenURL { url in
            CadenceDeepLinkManager.shared.handle(url)
        }
        .onChange(of: deepLinkManager.route?.token) { _, _ in
            handleDeepLinkRoute()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                CadenceWidgetRefreshCenter.reloadAllWidgets()
                let tasks = allTasksForNotifications
                let habits = allHabitsForNotifications
                Task { await NotificationManager.shared.reconcile(tasks: tasks, habits: habits) }
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: iOSSidebarItem) -> some View {
        switch item {
        case .today:
            iPadTodayView()
        case .allTasks:
            iOSAllTasksView()
        case .focus:
            iOSFocusView()
        case .inbox:
            iPadInboxView()
        case .calendar:
            iOSCalendarView()
        case .goals:
            iOSGoalsView()
        case .habits:
            iOSHabitsView()
        case .notes:
            NavigationStack {
                iOSCompactNotesView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .lists:
            NavigationStack {
                iOSListsView()
            }
        case .search:
            NavigationStack {
                iOSSearchView()
            }
        case .settings:
            iOSSettingsView()
        case .area(let id):
            if let area = areas.first(where: { $0.id == id }) {
                iOSListDetailView(area: area)
            } else {
                iOSMissingListView()
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                iOSListDetailView(project: project)
            } else {
                iOSMissingListView()
            }
        }
    }
}

/// iPhone navigation, modeled directly on Things 3: no persistent tab bar at all — a single
/// NavigationStack rooted at a home list of every destination, with an always-available
/// floating quick-add button for capture. iPad keeps its own sidebar shell untouched.
private struct iOSCompactRootShell: View {
    @Binding var path: [CadenceFeatureDestination]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @State private var showQuickCapture = false
    @State private var quickCaptureTitle = ""

    var body: some View {
        NavigationStack(path: $path) {
            iOSCompactHomeView()
                .navigationDestination(for: CadenceFeatureDestination.self, destination: destinationView)
        }
        .tint(Theme.blue)
        .overlay(alignment: .bottomTrailing) {
            iOSQuickAddButton {
                quickCaptureTitle = ""
                showQuickCapture = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showQuickCapture) {
            iOSQuickCaptureSheet(title: $quickCaptureTitle, onAdd: captureQuickTask)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: CadenceFeatureDestination) -> some View {
        switch destination {
        case .today:
            iPadTodayView()
        case .allTasks:
            iOSAllTasksView()
        case .focus:
            iOSFocusView()
        case .inbox:
            iPadInboxView()
        case .calendar:
            iOSCalendarView()
        case .notes:
            iOSCompactNotesView()
        case .lists:
            iOSListsView()
        case .goals:
            iOSGoalsView()
        case .habits:
            iOSHabitsView()
        case .search:
            iOSSearchView()
        case .settings:
            iOSSettingsView()
        }
    }

    private func captureQuickTask() {
        let trimmed = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? CadenceTaskMutationSupport.insertTask(title: trimmed, allTasks: allTasks, modelContext: modelContext)
        quickCaptureTitle = ""
        showQuickCapture = false
    }
}

private struct iOSQuickAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.blue)
                .clipShape(Circle())
                .shadow(color: Theme.overlayCardShadow, radius: 12, x: 0, y: 6)
        }
        .accessibilityLabel("New Task")
    }
}

private struct iOSQuickCaptureSheet: View {
    @Binding var title: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Task")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(onAdd)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 16) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.dim)
                Button("Add", action: onAdd)
                    .foregroundStyle(Theme.blue)
                    .fontWeight(.semibold)
                    .disabled(TaskTitleSupport.isEmpty(title))
            }
        }
        .padding(18)
        .presentationDetents([.height(150)])
        .presentationBackground(Theme.surface)
        .onAppear { isFocused = true }
    }
}

private extension iOSRootView {
    func handleDeepLinkRoute() {
        guard let route = deepLinkManager.route?.deepLink else { return }
        switch route {
        case .today, .task:
            selection = .today
            compactPath = [.today]
        case .habits:
            selection = .habits
            compactPath = [.habits]
        case .goals:
            selection = .goals
            compactPath = [.goals]
        case .calendar:
            selection = .calendar
            compactPath = [.calendar]
        }
    }
}
#endif
