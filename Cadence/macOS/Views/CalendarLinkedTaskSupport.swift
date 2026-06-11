#if os(macOS)
import SwiftData

enum CalendarLinkedTaskSupport {
    static func clearMissingEventLinks(
        in tasks: [AppTask],
        modelContext: ModelContext,
        calendarManager: CalendarManager
    ) {
        guard calendarManager.isAuthorized else { return }

        var changed = false
        for task in tasks where shouldClearCalendarLink(for: task, calendarManager: calendarManager) {
            task.calendarEventID = ""
            changed = true
        }

        if changed {
            try? modelContext.save()
        }
    }

    static func clearMissingEventLinks(
        modelContext: ModelContext,
        calendarManager: CalendarManager
    ) {
        let descriptor = FetchDescriptor<AppTask>()
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        clearMissingEventLinks(in: tasks, modelContext: modelContext, calendarManager: calendarManager)
    }

    private static func shouldClearCalendarLink(
        for task: AppTask,
        calendarManager: CalendarManager
    ) -> Bool {
        guard !task.calendarEventID.isEmpty else { return false }

        let lookupID = CalendarEventIdentity.lookupIdentifier(from: task.calendarEventID)
        guard !lookupID.hasPrefix("event-fallback|") else { return false }

        return calendarManager.event(withIdentifier: lookupID) == nil
    }
}
#endif
