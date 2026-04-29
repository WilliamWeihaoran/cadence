#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import EventKit

enum RootCommandActionSupport {
    static func handleDeleteShortcut(task: AppTask, context: RootCommandContext) {
        context.deleteConfirmationManager.present(
            title: "Delete Task?",
            message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
        ) {
            context.modelContext.deleteTask(task)
            context.hoveredTaskManager.hoveredTask = nil
        }
    }

    static func toggleTodayDate(for task: AppTask, kind: HoveredTaskDateKind) {
        let todayKey = DateFormatters.todayKey()
        switch kind {
        case .doDate:
            task.scheduledDate = task.scheduledDate == todayKey ? "" : todayKey
        case .dueDate:
            task.dueDate = task.dueDate == todayKey ? "" : todayKey
        }
    }

    static func handleCompletion(context: RootCommandContext) -> NSEvent? {
        guard !context.taskCreationManager.isPresented else { return nil }
        if let task = context.hoveredTaskManager.hoveredTask {
            context.taskCompletionAnimationManager.toggleCompletion(for: task)
            return nil
        }
        if context.hoveredSectionManager.triggerToggleComplete() { return nil }
        return nil
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

    static func nudgeDate(for task: AppTask, kind: HoveredTaskDateKind, delta: Int) {
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
            task.scheduledDate = nudgedKey
        case .dueDate:
            task.dueDate = nudgedKey
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
        case .goals:
            context.setSelection(.goals)
        case .habits:
            context.setSelection(.habits)
        case .task(let id):
            let descriptor = FetchDescriptor<AppTask>()
            guard let task = (try? context.modelContext.fetch(descriptor))?.first(where: { $0.id == id }) else { break }
            if let project = task.project {
                context.listNavigationManager.open(projectID: project.id, page: .tasks)
                context.setSelection(.project(project.id))
            } else if let area = task.area {
                context.listNavigationManager.open(areaID: area.id, page: .tasks)
                context.setSelection(.area(area.id))
            } else if task.goal != nil {
                context.setSelection(.allTasks)
            } else {
                context.setSelection(.inbox)
            }
        case .event(let eventID):
            let event = context.calendarManager.searchEvents(matching: "")
                .first { ($0.eventIdentifier ?? "") == eventID }
            if let startDate = event?.startDate {
                context.calendarNavigationManager.open(date: startDate)
            }
            context.setSelection(.calendar)
        case .eventNote(let noteID):
            context.notesNavigationManager.openMeetingNote(id: noteID)
            context.setSelection(.notes)
        }

        context.globalSearchManager.dismiss()
    }
}
#endif
