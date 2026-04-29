import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    var sharedModelContainer: ModelContainer = PersistenceController.shared.container

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            macOSRootView()
                .environment(ThemeManager.shared)
                .environment(CalendarManager.shared)
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
#endif
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}
