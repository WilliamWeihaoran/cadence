#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

enum SchedulePanelDataSupport {
    static func scheduledTasks(from allTasks: [AppTask], todayKey: String) -> [AppTask] {
        CadenceScheduleSupport.scheduledTasks(
            on: todayKey,
            from: allTasks,
            includeCompleted: true,
            excludeBundled: true
        )
    }

    static func externalEventItems(
        calendarManager: CalendarManager,
        date: Date
    ) -> [CalendarEventItem] {
        CalendarEventItem.timedSegments(from: calendarManager.fetchEvents(for: date), for: date)
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
