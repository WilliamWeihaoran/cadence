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
        sharedModelContainer = PersistenceController.shared.container
    }

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            macOSRootView()
                .environment(ThemeManager.shared)
                .environment(CadenceDeepLinkManager.shared)
                .environment(CalendarManager.shared)
                .environment(RemindersManager.shared)
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
#else
            iOSRootView()
                .environment(ThemeManager.shared)
                .environment(CadenceDeepLinkManager.shared)
                .environment(AISettingsManager.shared)
                .environment(iOSCalendarManager.shared)
#endif
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}
