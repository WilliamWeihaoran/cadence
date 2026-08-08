import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    let sharedModelContainer: ModelContainer
#if os(macOS)
    @NSApplicationDelegateAdaptor(CadenceAppDelegate.self) private var appDelegate
#endif

    init() {
#if os(macOS)
        CadenceRemoteNotificationRegistrar.registerIfNeeded()
#endif
        // Touch the singleton now so its init runs and registers the UNUserNotificationCenterDelegate
        // early. Deliberately does NOT call requestAuthorization() here — that stays gated behind an
        // explicit Settings button so there's no jarring cold-launch permission prompt.
        _ = NotificationManager.shared
        sharedModelContainer = PersistenceController.shared.container
    }

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            macOSRootView()
                .environment(CadenceDeepLinkManager.shared)
                .environment(CalendarManager.shared)
                .environment(RemindersManager.shared)
                .environment(NotificationManager.shared)
                .environment(AISettingsManager.shared)
                .environment(AppleAccountManager.shared)
                .environment(FocusManager.shared)
                .environment(DeleteConfirmationManager.shared)
                .environment(HoveredTaskManager.shared)
                .environment(HoveredEditableManager.shared)
                .environment(HoveredKanbanColumnManager.shared)
                .environment(HoveredSectionManager.shared)
                .environment(HoveredTaskDatePickerManager.shared)
                .environment(TaskCompletionAnimationManager.shared)
                .environment(SectionCompletionAnimationManager.shared)
                .environment(TaskCreationManager.shared)
                .environment(TodayTimelineFocusManager.shared)
                .environment(GlobalSearchManager.shared)
                .environment(ListNavigationManager.shared)
                .environment(NotesNavigationManager.shared)
                .environment(CalendarNavigationManager.shared)
                .environment(TaskSubtaskEntryManager.shared)
                // The densest bar in the app is the list-detail Kanban tab bar: 220pt of
                // minimum sidebar, ~350pt of tab cluster, ~310pt of Sort/Order/Show Archived
                // controls, plus gaps and page padding — roughly 950pt before anything has to
                // compress or truncate. Below that the window was reachable but visibly broken,
                // so the floor is set just past it rather than left to the user to discover.
                .frame(minWidth: 960, minHeight: 600)
#else
            iOSRootView()
                .environment(CadenceDeepLinkManager.shared)
                .environment(AISettingsManager.shared)
                .environment(iOSCalendarManager.shared)
                .environment(NotificationManager.shared)
#endif
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}
