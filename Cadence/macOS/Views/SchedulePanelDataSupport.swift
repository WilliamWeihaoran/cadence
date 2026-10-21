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

    /// **The Today timeline's drag-create writes its task here, in place** ([[T-3171]]).
    ///
    /// It used to hand the draft to `TaskCreationManager.present`, which raises
    /// `CreateTaskPanelSurface` over the whole window — so a user who dragged a slot, typed a title
    /// into the shared schedule panel and pressed Add was shown the old create-task sheet **a second
    /// time**, pre-filled with what they had just typed, with nothing created until they confirmed
    /// again. That is the owner's own report ("still using the old task and event creation sheet")
    /// surviving on the one macOS page the seventh adoption slice did not convert: the Calendar
    /// page's `CalDayColumn` has composed in place since [[T-655]], and this is the same write.
    ///
    /// **The draft's own day, not the panel's `todayKey`.** T-1433 gave the popover editable date
    /// and time fields, and `QuickCreateChoicePopover.hostWritesDraftDay` tells the panel this host
    /// honours them — so a slot dragged on this timeline and then moved to tomorrow must land on
    /// tomorrow rather than being silently filed under today. The Calendar page's column answers
    /// that question the other way, which is why it passes `usesTaskPanelForTaskCreation: false`.
    ///
    /// Throws what `TaskCreationService` throws, so the host can name a refused write (T-655)
    /// rather than closing the popover over a task that was never stored.
    @discardableResult
    static func insertDragCreatedTask(
        _ draft: QuickCreateTaskDraft,
        areas: [Area],
        projects: [Project],
        in modelContext: ModelContext
    ) throws -> AppTask? {
        try SchedulingActions.insertTask(
            title: draft.title,
            dateKey: draft.dateKey,
            startMin: draft.startMin,
            endMin: draft.endMin,
            containerSelection: draft.container,
            sectionName: draft.sectionName,
            priority: draft.priority,
            notes: draft.notes,
            subtaskTitles: draft.subtaskTitles,
            areas: areas,
            projects: projects,
            in: modelContext
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
