#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

enum SchedulePanelDataSupport {
    static func scheduledTasks(from allTasks: [AppTask], todayKey: String) -> [AppTask] {
        allTasks.filter {
            $0.scheduledDate == todayKey && $0.scheduledStartMin >= 0 && !$0.isCancelled
        }
    }

    static func externalEventItems(
        from allTasks: [AppTask],
        calendarManager: CalendarManager,
        date: Date
    ) -> [CalendarEventItem] {
        let linkedIDs = Set(allTasks.compactMap { $0.calendarEventID.isEmpty ? nil : $0.calendarEventID })
        return calendarManager.fetchEvents(for: date)
            .filter { event in
                guard let id = event.eventIdentifier else { return true }
                return !linkedIDs.contains(id)
            }
            .map { CalendarEventItem(event: $0) }
    }

    static func syncLinkedTasks(
        allTasks: [AppTask],
        modelContext: ModelContext,
        calendarManager: CalendarManager
    ) {
        for task in allTasks where !task.calendarEventID.isEmpty {
            calendarManager.syncTaskFromLinkedEvent(task)
        }
        try? modelContext.save()
    }

    static func restoreScroll(
        proxy: ScrollViewProxy,
        rememberedScrollHour: Int,
        setRestoring: @escaping (Bool) -> Void,
        setDidRestore: @escaping (Bool) -> Void
    ) {
        let scrollHour = SchedulePanelStateSupport.restoreScrollHour(
            rememberedScrollHour: rememberedScrollHour
        )
        setRestoring(true)
        DispatchQueue.main.async {
            proxy.scrollTo(scrollHour, anchor: .top)
            DispatchQueue.main.async {
                setDidRestore(true)
                setRestoring(false)
            }
        }
    }
}
#endif
