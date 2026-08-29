import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    let sharedModelContainer: ModelContainer
#if os(macOS)
    @NSApplicationDelegateAdaptor(CadenceAppDelegate.self) private var appDelegate
#endif

    init() {
        // Silent-push registration is **not** here. `CadenceAppDelegate.applicationDidFinishLaunching`
        // is the one production caller of `CadenceRemoteNotificationRegistrar.registerIfNeeded()`,
        // and this initializer used to call it too — two launch callers for one registrar, while
        // every doc and commit message described the delegate as *the* registration site (T-468).
        // `@NSApplicationDelegateAdaptor` above guarantees the delegate exists on macOS, so nothing
        // is lost by leaving it to the one owner. Pinned by
        // `CadenceLaunchWiringTests.exactlyOneProductionCallSiteRegistersForSilentPush`.
        //
        // Touch the singleton now so its init runs and registers the UNUserNotificationCenterDelegate
        // early. Deliberately does NOT call requestAuthorization() here — that stays gated behind an
        // explicit Settings button so there's no jarring cold-launch permission prompt.
        _ = NotificationManager.shared
        // The notes editor's Live/Edit/Preview picker is gone and live is the only mode, so the
        // stored selection is a key nobody reads. Clearing it is idempotent and touches no model
        // state — see `CadenceNotesEditorPreferences`.
        CadenceNotesEditorPreferences.purgeRetiredKeys()
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
                // Injected beside the deep-link manager because it is the same kind of thing: a
                // one-slot inbox a distant surface drops a navigation request into. iOS only —
                // macOS says this with `FocusManager.startFocus(…)`, which it already has.
                .environment(CadenceFocusHandoffCenter.shared)
                .environment(AISettingsManager.shared)
                .environment(iOSCalendarManager.shared)
                .environment(NotificationManager.shared)
                .environment(RemindersManager.shared)
#endif
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}
