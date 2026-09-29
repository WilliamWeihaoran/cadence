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

    /// Today's timed events, **through the same day cache the calendar page uses** (T-1499).
    ///
    /// This used to call `calendarManager.fetchEvents(for:)` directly, which builds an `NSPredicate`
    /// and runs `EKEventStore.events(matching:)` with no memoisation at all. `CalDayColumn` — the
    /// calendar page's host of the *same* `TimelineDayCanvas` — has always gone through
    /// `CalendarEventDayCache`, so the two hosts of one canvas disagreed about whether drawing a
    /// day costs a store query. T-1498 made this cost once per gesture rather than once per frame;
    /// it was still one query per *render* of a panel that re-renders on every task change, every
    /// store refresh and every zoom step.
    ///
    /// The cache is the caller's, not this function's: it belongs to the view's lifetime
    /// (`@State private var eventCache`), exactly as `CalendarPageView` holds it, and passing it in
    /// is what lets a test hold one across calls and count what reached the store.
    static func externalEventItems(
        calendarManager: any CalendarEventDaySource,
        date: Date,
        cache: CalendarEventDayCache
    ) -> [CalendarEventItem] {
        CalendarEventItem.timedSegments(
            from: cache.timedEvents(for: date, calendarManager: calendarManager),
            for: date
        )
    }

    static func syncLinkedTasks(
        allTasks: [AppTask],
        modelContext: ModelContext,
        calendarManager: CalendarManager
    ) {
        CalendarLinkedTaskSupport.clearMissingEventLinks(
            in: allTasks,
            modelContext: modelContext,
            calendarManager: calendarManager
        )
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
