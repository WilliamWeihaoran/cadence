#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct RootDetailContent: View {
    let selection: SidebarItem?

    var body: some View {
        switch selection {
        case .today, .none:
            TodayView()
        // One branch, one view: All Tasks and Inbox are two views of one page now, and giving them
        // separate `switch` arms would give SwiftUI two identities and reset the page's state every
        // time the command palette crossed between them.
        case .allTasks, .inbox:
            TasksPageView(requestedScope: selection == .inbox ? .inbox : nil)
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
        case .settings:
            SettingsView()
        }
    }
}

enum macOSRootStateSupport {
    @ViewBuilder
    static func detailContent(for selection: SidebarItem?) -> some View {
        RootDetailContent(selection: selection)
    }

    static func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.contentViewController != nil }) else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar = nil
            window.isMovableByWindowBackground = false
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    static func clearMissingCalendarLinkedTasks(
        modelContext: ModelContext,
        calendarManager: CalendarManager
    ) {
        CalendarLinkedTaskSupport.clearMissingEventLinks(
            modelContext: modelContext,
            calendarManager: calendarManager
        )
    }

    static func makeCommandContext(
        selection: SidebarItem?,
        showTimelineSidebar: Bool,
        modelContext: ModelContext,
        deleteConfirmationManager: DeleteConfirmationManager,
        hoveredTaskDatePickerManager: HoveredTaskDatePickerManager,
        taskCreationManager: TaskCreationManager,
        todayTimelineFocusManager: TodayTimelineFocusManager,
        globalSearchManager: GlobalSearchManager,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager,
        hoveredKanbanColumnManager: HoveredKanbanColumnManager,
        hoveredSectionManager: HoveredSectionManager,
        taskCompletionAnimationManager: TaskCompletionAnimationManager,
        taskSubtaskEntryManager: TaskSubtaskEntryManager,
        clearAppEditingFocus: @escaping () -> Void,
        setShowTimelineSidebar: @escaping (Bool) -> Void,
        toggleSidebarVisibility: @escaping () -> Void
    ) -> RootCommandContext {
        RootCommandContext(
            selection: selection,
            showTimelineSidebar: showTimelineSidebar,
            modelContext: modelContext,
            deleteConfirmationManager: deleteConfirmationManager,
            hoveredTaskDatePickerManager: hoveredTaskDatePickerManager,
            taskCreationManager: taskCreationManager,
            todayTimelineFocusManager: todayTimelineFocusManager,
            globalSearchManager: globalSearchManager,
            hoveredTaskManager: hoveredTaskManager,
            hoveredEditableManager: hoveredEditableManager,
            hoveredKanbanColumnManager: hoveredKanbanColumnManager,
            hoveredSectionManager: hoveredSectionManager,
            taskCompletionAnimationManager: taskCompletionAnimationManager,
            taskSubtaskEntryManager: taskSubtaskEntryManager,
            clearAppEditingFocus: clearAppEditingFocus,
            setShowTimelineSidebar: setShowTimelineSidebar,
            toggleSidebarVisibility: toggleSidebarVisibility
        )
    }

    static func makeSearchSelectionContext(
        modelContext: ModelContext,
        calendarManager: CalendarManager,
        globalSearchManager: GlobalSearchManager,
        listNavigationManager: ListNavigationManager,
        notesNavigationManager: NotesNavigationManager,
        calendarNavigationManager: CalendarNavigationManager,
        clearAppEditingFocus: @escaping () -> Void,
        setSelection: @escaping (SidebarItem) -> Void,
        presentTaskCreation: @escaping () -> Void
    ) -> RootSearchSelectionContext {
        RootSearchSelectionContext(
            modelContext: modelContext,
            calendarManager: calendarManager,
            globalSearchManager: globalSearchManager,
            listNavigationManager: listNavigationManager,
            notesNavigationManager: notesNavigationManager,
            calendarNavigationManager: calendarNavigationManager,
            clearAppEditingFocus: clearAppEditingFocus,
            setSelection: setSelection,
            presentTaskCreation: presentTaskCreation
        )
    }
}

/// T-345. **The macOS sidebar's half of the id-side deleted-model guard.**
///
/// `SidebarItem` is a mix of two kinds of destination, and only one of them can go stale. Today,
/// All Tasks, Inbox, Goals, Habits, Notes, Calendar, Focus and Settings are static — they name a
/// page, not a row, and no deletion can invalidate them. `.area(UUID)` and `.project(UUID)` name a
/// *model*, and deleting that model from its edit sheet or from Settings leaves the root selection
/// pointing at an id nothing answers to. `RootDetailContent` then hands the id to a loader whose
/// `@Query` finds nothing, and the detail pane renders blank — which reads as the app having lost
/// the page rather than as the list having been deleted.
///
/// iOS already normalizes exactly this, in `iOSListViews.effectiveSelectedRoute`; macOS had no
/// selection normalizer at all. The rule itself is `CadenceSelectionNormalization`, shared with
/// macOS Goals (T-346), so the two surfaces cannot drift into two answers.
///
/// **Existence, not visibility.** The id sets handed in are every area and every project, archived
/// included. Archiving a list takes it out of the sidebar but not out of the store, and kicking the
/// user off a page they are reading because they archived it would be a different behaviour change
/// wearing this fix's clothes. Only a real deletion retargets.
enum macOSRootSelectionNormalization {

    /// The selection to hold, given what the store still has. `fallback` is the destination a stale
    /// selection lands on; `.today` because it is the one page that always exists and is where the
    /// app opens.
    static func normalized(
        _ selection: SidebarItem?,
        areaIDs: Set<UUID>,
        projectIDs: Set<UUID>,
        fallback: SidebarItem = .today
    ) -> SidebarItem? {
        switch selection {
        case .area(let id):
            return CadenceSelectionNormalization.normalized(id, existingIDs: areaIDs, fallback: nil)
                .map(SidebarItem.area) ?? fallback
        case .project(let id):
            return CadenceSelectionNormalization.normalized(id, existingIDs: projectIDs, fallback: nil)
                .map(SidebarItem.project) ?? fallback
        default:
            // Static destinations and `nil`. Nothing about them can stop existing.
            return selection
        }
    }
}

/// Runs the rule above whenever the set of lists changes.
///
/// A `Color.clear` observer rather than two `@Query`s on `macOSRootView`, for the reason
/// `NotificationReconcileObserver` is one: the root is the most re-rendered view in the app and
/// unbounded queries on it are paid for by every frame. Placed in the root's background so it
/// resolves against the same context the shell reads.
struct SidebarSelectionNormalizer: View {
    @Binding var selection: SidebarItem?
    @Query private var areas: [Area]
    @Query private var projects: [Project]

    var body: some View {
        Color.clear
            // Hit-testable on macOS, and this one is a full-window background.
            .allowsHitTesting(false)
            .onChange(of: areas.map(\.id)) { _, _ in normalize() }
            .onChange(of: projects.map(\.id)) { _, _ in normalize() }
    }

    /// Assigning unconditionally would post a `selection` change on every list mutation, and
    /// `macOSRootLifecycleSupport.handleSelectionChange` moves the sidebar's column visibility off
    /// the back of one. Write only when the answer actually differs.
    private func normalize() {
        let normalized = macOSRootSelectionNormalization.normalized(
            selection,
            areaIDs: Set(areas.map(\.id)),
            projectIDs: Set(projects.map(\.id))
        )
        guard normalized != selection else { return }
        selection = normalized
    }
}

#endif
