#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import EventKit

enum RootCommandActionSupport {
    static func handleDeleteShortcut(task: AppTask, context: RootCommandContext) {
        context.deleteConfirmationManager.presentTaskDelete(task, in: context.modelContext) {
            context.hoveredTaskManager.hoveredTask = nil
        }
    }

    /// Cmd+P over a hovered row: cycle the task's priority, and commit it ([[T-4970]]).
    ///
    /// The key handler used to write `task.priority = task.priority.nextCycled` and return, so the
    /// new flag sat pending in the app's single `ModelContext` until an unrelated save committed
    /// it or an unrelated `rollback()` discarded it — the [[T-4911]] / [[T-503]] shape. It goes
    /// through `CadenceTaskFieldEditCommit` now, whose snapshot undo puts the priority back on a
    /// refusal without rolling back anyone else's pending work. A keystroke has no surface to
    /// draw a notice on; the row's flag reverting is what the user sees.
    @discardableResult
    static func cyclePriority(
        of task: AppTask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        CadenceTaskFieldEditCommit.commit(task, in: modelContext, commit: commit) {
            task.priority = task.priority.nextCycled
        }
    }

    /// `T` / `D` over a hovered row. Both halves go through `CadenceTaskDateEditing`, so the
    /// keystroke that moves a task off today also retires today's reminder for it (T-362) — a
    /// keyboard toggle is exactly the case where nothing else is about to touch `scenePhase`.
    static func toggleTodayDate(for task: AppTask, kind: HoveredTaskDateKind, in context: ModelContext) {
        let todayKey = DateFormatters.todayKey()
        switch kind {
        case .doDate:
            if task.scheduledDate == todayKey {
                CadenceTaskDateEditing.clearScheduledDate(task, in: context)
            } else {
                CadenceTaskDateEditing.setScheduledDate(todayKey, for: task, in: context)
            }
        case .dueDate:
            if task.dueDate == todayKey {
                CadenceTaskDateEditing.clearDueDate(task, in: context)
            } else {
                CadenceTaskDateEditing.setDueDate(todayKey, for: task, in: context)
            }
        }
    }

    static func handleCancellation(context: RootCommandContext) -> NSEvent? {
        guard !context.taskCreationManager.isPresented,
              let task = context.hoveredTaskManager.hoveredTask else { return nil }
        if context.taskCompletionAnimationManager.isPending(task) {
            context.taskCompletionAnimationManager.cancelPending(for: task.id)
        }
        context.taskCompletionAnimationManager.toggleCancellation(for: task)
        return nil
    }

    /// What Cmd+\ does. Focusing Today's pane is only an answer while that pane is mounted
    /// ([[T-7986]]): in the tasks-only layout `SchedulePanel` is not built, the focus request was
    /// heard by nothing, and the key that opens the day's timeline on every other page was dead on
    /// the one page named for the day. Without a pane it takes the other pages' arm.
    enum TimelineShortcutAction: Equatable {
        /// Focus Today's own Timeline pane, closing the overlay first when it is open.
        case focusTodayPane(closeOverlay: Bool)
        /// Show or hide the timeline overlay.
        case setOverlay(Bool)
    }

    static func timelineShortcutAction(
        selection: SidebarItem?,
        showTimelineSidebar: Bool,
        isTodayTimelinePaneMounted: Bool
    ) -> TimelineShortcutAction {
        let isToday = selection == .today || selection == nil
        if isToday && isTodayTimelinePaneMounted {
            return .focusTodayPane(closeOverlay: showTimelineSidebar)
        }
        return .setOverlay(!showTimelineSidebar)
    }

    static func handleTimelineShortcut(context: RootCommandContext) {
        let action = timelineShortcutAction(
            selection: context.selection,
            showTimelineSidebar: context.showTimelineSidebar,
            isTodayTimelinePaneMounted: context.todayTimelineFocusManager.isTodayTimelinePaneMounted
        )
        switch action {
        case .focusTodayPane(let closeOverlay):
            if closeOverlay {
                withAnimation(.easeInOut(duration: 0.2)) {
                    context.setShowTimelineSidebar(false)
                }
            }
            context.todayTimelineFocusManager.requestFocus()
        case .setOverlay(let isShown):
            withAnimation(.easeInOut(duration: 0.2)) {
                context.setShowTimelineSidebar(isShown)
            }
        }
    }

    static func nudgeDate(for task: AppTask, kind: HoveredTaskDateKind, delta: Int, in context: ModelContext) {
        let currentKey: String
        switch kind {
        case .doDate:
            currentKey = task.scheduledDate
        case .dueDate:
            currentKey = task.dueDate
        }
        let baseDate = DateFormatters.date(from: currentKey) ?? Date()
        let nudged = Calendar.current.date(byAdding: .day, value: delta, to: baseDate) ?? baseDate
        let nudgedKey = DateFormatters.dateKey(from: nudged)
        switch kind {
        case .doDate:
            CadenceTaskDateEditing.setScheduledDate(nudgedKey, for: task, in: context)
        case .dueDate:
            CadenceTaskDateEditing.setDueDate(nudgedKey, for: task, in: context)
        }
    }

    static func handleSearchSelection(_ result: GlobalSearchResult, context: RootSearchSelectionContext) {
        switch result.destination {
        case .command(let command):
            performCommand(
                command,
                clearAppEditingFocus: context.clearAppEditingFocus,
                presentTaskCreation: context.presentTaskCreation,
                setSelection: context.setSelection
            )
        case .sidebar(let item):
            context.setSelection(item)
        case .area(let id):
            context.setSelection(.area(id))
        case .project(let id):
            context.setSelection(.project(id))
        case .task(let id):
            handleTaskSelection(
                id,
                modelContext: context.modelContext,
                listNavigationManager: context.listNavigationManager,
                setSelection: context.setSelection,
                presentTaskInspector: context.presentTaskInspector
            )
        case .event(let eventID):
            // The whole fetched window, not `searchEvents(matching: "")` — an empty query means
            // "what is coming up" and drops everything that has already ended, while search itself
            // reaches 60 days back. Resolving through it made a past event findable by Cmd+K and
            // impossible to open: picking it fell through to `setSelection(.calendar)` and left the
            // calendar wherever it already was, which reads as the row doing nothing.
            let event = CadenceCalendarEventSearchSupport.event(
                from: context.calendarManager.windowEvents(),
                identifier: eventID
            )
            if let startDate = event?.startDate {
                context.calendarNavigationManager.open(date: startDate)
            }
            context.setSelection(.calendar)
        case .eventNote(let noteID):
            context.notesNavigationManager.openMeetingNote(id: noteID)
            context.setSelection(.notes)
        case .note(let noteID):
            // The row carries an id, not a kind, so the note's *current* kind is resolved here:
            // a note refiled between the keystroke and the Return opens where it is now.
            let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })
            guard let note = (try? context.modelContext.fetch(descriptor))?.first else { break }
            if let route = GlobalSearchListNoteRoute.route(for: note) {
                openListNote(note.id, route: route, context: context)
            } else if NotesNavigationManager.page(for: note.kind) != nil {
                context.notesNavigationManager.openNote(id: note.id, kind: note.kind)
                context.setSelection(.notes)
            }
        }

        context.globalSearchManager.dismiss()
    }

    /// **[[T-7232]] — a menu item running a Cmd+K command**, as `CadenceMenuCommandRoute` hands it
    /// over. Dismisses the palette as a pick from it does, so Cmd+, with Cmd+K open does not leave
    /// the palette standing over the page it just opened.
    static func handleMenuCommand(_ command: GlobalSearchCommand, context: RootSearchSelectionContext) {
        handleMenuCommand(
            command,
            clearAppEditingFocus: context.clearAppEditingFocus,
            presentTaskCreation: context.presentTaskCreation,
            setSelection: context.setSelection,
            dismissSearch: { context.globalSearchManager.dismiss() }
        )
    }

    /// The same, with its dependencies named rather than the whole context, so a test can drive it:
    /// the context carries a `CalendarManager`, which owns a real `EKEventStore`.
    static func handleMenuCommand(
        _ command: GlobalSearchCommand,
        clearAppEditingFocus: () -> Void,
        presentTaskCreation: () -> Void,
        setSelection: (SidebarItem) -> Void,
        dismissSearch: () -> Void
    ) {
        performCommand(
            command,
            clearAppEditingFocus: clearAppEditingFocus,
            presentTaskCreation: presentTaskCreation,
            setSelection: setSelection
        )
        dismissSearch()
    }

    /// The one table of what each palette command does, shared by the palette's rows and the menu.
    private static func performCommand(
        _ command: GlobalSearchCommand,
        clearAppEditingFocus: () -> Void,
        presentTaskCreation: () -> Void,
        setSelection: (SidebarItem) -> Void
    ) {
        switch command {
        case .newTask:
            clearAppEditingFocus()
            presentTaskCreation()
        case .focus:
            setSelection(.focus)
        case .today:
            setSelection(.today)
        case .allTasks:
            setSelection(.allTasks)
        case .calendar:
            setSelection(.calendar)
        case .settings:
            setSelection(.settings)
        }
    }

    /// **[[T-5300]] — picking a task in Cmd+K opens that task, not just its list.**
    ///
    /// It used to open the list and stop: no scroll, no highlight, and with the include-completed
    /// search setting on a finished result landed inside a Completed group that `ListTasksView`
    /// collapses on appear, so the row picked was not on screen at all. iOS has always opened the
    /// task itself (`iOSSearchView` sets `selectedTask` and presents `iOSTaskInspectorSheet`).
    ///
    /// **The owner chose the inspector over a scroll-and-reveal**: the Mac already has
    /// `TaskDetailPopover`, iOS already opens the task, and a reveal would have had to reach into
    /// every list page's scroll position and un-fold its Completed tier. The list still opens
    /// behind it — the context is free and the inspector does not depend on it arriving.
    ///
    /// Split out of `handleSearchSelection` with its four dependencies named rather than the whole
    /// `RootSearchSelectionContext`, so the arm can be called from a test: the context carries a
    /// `CalendarManager`, which owns a real `EKEventStore`, and nothing in this arm wants one.
    static func handleTaskSelection(
        _ id: UUID,
        modelContext: ModelContext,
        listNavigationManager: ListNavigationManager,
        setSelection: (SidebarItem) -> Void,
        presentTaskInspector: (UUID) -> Void
    ) {
        let descriptor = FetchDescriptor<AppTask>()
        guard let task = (try? modelContext.fetch(descriptor))?.first(where: { $0.id == id }) else { return }
        if let project = task.project {
            listNavigationManager.open(projectID: project.id, page: .tasks)
            setSelection(.project(project.id))
        } else if let area = task.area {
            listNavigationManager.open(areaID: area.id, page: .tasks)
            setSelection(.area(area.id))
        } else {
            setSelection(.inbox)
        }
        presentTaskInspector(task.id)
    }

    /// A list document opens in its list's Documents tab with the document selected ([[T-3084]]),
    /// which is the only surface that draws one — the Notes page has no page for `.list`.
    private static func openListNote(
        _ noteID: UUID,
        route: GlobalSearchListNoteRoute,
        context: RootSearchSelectionContext
    ) {
        switch route {
        case .area(let areaID):
            context.listNavigationManager.open(areaID: areaID, page: .documents, listNoteID: noteID)
        case .project(let projectID):
            context.listNavigationManager.open(projectID: projectID, page: .documents, listNoteID: noteID)
        }
        context.setSelection(route.sidebarItem)
    }
}
#endif
