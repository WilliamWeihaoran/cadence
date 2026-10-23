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

    static func handleTimelineShortcut(context: RootCommandContext) {
        if context.selection == .today || context.selection == nil {
            if context.showTimelineSidebar {
                withAnimation(.easeInOut(duration: 0.2)) {
                    context.setShowTimelineSidebar(false)
                }
            }
            context.todayTimelineFocusManager.requestFocus()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                context.setShowTimelineSidebar(!context.showTimelineSidebar)
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
            switch command {
            case .newTask:
                context.clearAppEditingFocus()
                context.presentTaskCreation()
            case .focus:
                context.setSelection(.focus)
            case .today:
                context.setSelection(.today)
            case .allTasks:
                context.setSelection(.allTasks)
            case .calendar:
                context.setSelection(.calendar)
            case .settings:
                context.setSelection(.settings)
            }
        case .sidebar(let item):
            context.setSelection(item)
        case .area(let id):
            context.setSelection(.area(id))
        case .project(let id):
            context.setSelection(.project(id))
        case .task(let id):
            let descriptor = FetchDescriptor<AppTask>()
            guard let task = (try? context.modelContext.fetch(descriptor))?.first(where: { $0.id == id }) else { break }
            if let project = task.project {
                context.listNavigationManager.open(projectID: project.id, page: .tasks)
                context.setSelection(.project(project.id))
            } else if let area = task.area {
                context.listNavigationManager.open(areaID: area.id, page: .tasks)
                context.setSelection(.area(area.id))
            } else {
                context.setSelection(.inbox)
            }
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
