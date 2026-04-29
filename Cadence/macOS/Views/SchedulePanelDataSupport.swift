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
        calendarManager: CalendarManager,
        date: Date
    ) -> [CalendarEventItem] {
        return calendarManager.fetchEvents(for: date)
            .map { CalendarEventItem(event: $0) }
    }

    static func syncLinkedTasks(
        allTasks: [AppTask],
        modelContext: ModelContext
    ) {
        var changed = false
        for task in allTasks where !task.calendarEventID.isEmpty {
            task.calendarEventID = ""
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
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
