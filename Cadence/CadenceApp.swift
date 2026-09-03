import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    // Optional since T-817: `PersistenceController.shared.container` is `nil` when the CloudKit
    // store, an on-disk recovery store, and a fully in-memory container have all failed to open.
    // `body` below reads this rather than force-unwrapping it, and falls back to
    // `CadenceTerminalRecoveryView` instead of a window group built around a store that does not
    // exist.
    let sharedModelContainer: ModelContainer?
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
        // T-817. `SceneBuilder` cannot branch on this the way `body` used to try to: its only
        // `if`-support is `#available`, so there is no Scene-level "show a different window group
        // when there's no container". The `if let`/`else` therefore lives one level down, inside
        // `WindowGroup`'s plain `@ViewBuilder` content, and `.modelContainer(_:)` moves from the
        // `Scene` to each branch's own `View` — the same call `QuickTaskPanelController` and
        // `TaskNotesPanelController` already make on a floating panel's content, not the window
        // group around it. No container at all is not "run the normal app anyway": every view
        // under `macOSRootView`/`iOSRootView` assumes a working `ModelContext` exists, and forcing
        // one into existence around a store that failed three separate ways would be the
        // "wrong-but-running app" this launch already refused to be.
        // `CadenceTerminalRecoveryView` asks for no `.modelContainer` at all — it opens its own,
        // read-only, only if the user asks it to try.
        WindowGroup {
            if let sharedModelContainer {
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
                    .modelContainer(sharedModelContainer)
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
                    .modelContainer(sharedModelContainer)
#endif
            } else {
                CadenceTerminalRecoveryView(failure: PersistenceController.terminalFailure)
#if os(macOS)
                    .frame(minWidth: 520, minHeight: 560)
#endif
            }
        }
        // **T-735.** Every `@AppStorage` in the app resolves against this rather than against
        // `UserDefaults.standard` directly. With no `-CadenceSuiteName` launch argument the two are
        // the same object, so this is inert in the product; under `scripts/simulator-claim.sh` it
        // is what stops one agent's remembered position from reading as another's date bug.
        .defaultAppStorage(CadenceDefaults.store)
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}
