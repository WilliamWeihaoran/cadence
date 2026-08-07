#if os(macOS)
import EventKit
import SwiftData

/// Minimal seam over `CalendarManager` so calendar-link reconciliation (deciding whether a task's
/// stale `calendarEventID` should be cleared) can be regression-tested with a fake implementation
/// instead of requiring live EventKit authorization/data.
protocol CalendarEventLookup {
    var isAuthorized: Bool { get }
    func event(withIdentifier identifier: String) -> EKEvent?
}

extension CalendarManager: CalendarEventLookup {}

enum CalendarLinkedTaskSupport {
    static func clearMissingEventLinks(
        in tasks: [AppTask],
        modelContext: ModelContext,
        calendarManager: CalendarEventLookup
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
        calendarManager: CalendarEventLookup
    ) {
        let descriptor = FetchDescriptor<AppTask>()
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        clearMissingEventLinks(in: tasks, modelContext: modelContext, calendarManager: calendarManager)
    }

    static func shouldClearCalendarLink(
        for task: AppTask,
        calendarManager: CalendarEventLookup
    ) -> Bool {
        guard !task.calendarEventID.isEmpty else { return false }

        let lookupID = CalendarEventIdentity.lookupIdentifier(from: task.calendarEventID)
        guard !lookupID.hasPrefix("event-fallback|") else { return false }

        return calendarManager.event(withIdentifier: lookupID) == nil
    }
}
#endif
