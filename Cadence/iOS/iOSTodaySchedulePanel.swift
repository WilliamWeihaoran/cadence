#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Today's timeline, hosted in the two-pane inspector. It draws no header of its own:
/// `iPadTodayInspectorSwitcher` sits directly above it with "Timeline" lit up in it.
///
/// **It IS the Calendar's timeline, pinned to today ([[T-3081]]).** This pane used to own a second
/// timed surface — `iOSScheduleHourRow`, a flow of 24 hour rows — and the owner reported three
/// things wrong with it in one sentence: a `+` could not be dragged onto it, it showed none of the
/// day's calendar events, and it could not be pinched. All three were the same defect. The hour-row
/// grid queried `AppTask` alone and **never opened EventKit at all**, so there was no event to
/// drop anywhere; it carried no `iOSNewTaskDropTarget`, so a dragged `+` had nothing to
/// land on; and `MagnifyGesture` was attached to `iOSCalendarTimelineGrid`'s container, which this
/// pane did not build. Every one of the three is a property of the Calendar's day column, and the
/// fix the owner chose is to draw that column rather than to re-grow three behaviours beside it —
/// this repository's documented failure mode being a rule re-spelled per surface and then drifting
/// (the DST family, the day-snapping fork, and T-588's own three hand-typed hour figures, which
/// were this exact pair of files).
///
/// So the pane is now a thin adapter: it names today, it reads the day's events, it hands the grid
/// the same `CadenceScheduleSupport` dictionaries the Calendar page hands it, and it owns the
/// composer that the grid's create gesture opens. `iOSCalendarTimelineSpan.singleDay` is the one
/// thing it asks the grid to do differently, and that is a statement about *paging*, not about what
/// a day looks like: one column, no horizontal scroller, so no day snapping, no day header band and
/// no second date on a screen whose task column is already headed with it.
///
/// **The zoom is the Calendar's own stored multiplier, deliberately.** One `@AppStorage` key, so a
/// pinch here and a pinch there are the same control on the same number — which is the rule T-588
/// already settled for the hour *height* in prose ("the app's one answer to how tall an hour on an
/// iOS timeline is") and which only now has one expression rather than two.
struct iOSSchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    /// The one EventKit reader on iOS. Today's pane never opens a store of its own — see
    /// `refreshTodayEvents`, which is the whole of this pane's calendar access.
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    /// Shared with the Calendar page through `CadenceCalendarZoom.storageKey`. See the type note.
    @AppStorage(CadenceCalendarZoom.storageKey) private var zoomLevel = CadenceCalendarZoom.defaultZoom
    /// Today's events, cached rather than fetched from `body`.
    ///
    /// **T-570's rule, restated on the surface that now needs it.** A synchronous EventKit
    /// predicate query in a computed property runs on every body pass, which here would mean once
    /// per frame of a pinch. One day's fetch, re-run only when the store changes or the day does.
    @State private var todayEvents: [EKEvent] = []

    /// The invalidation token for the day this pane draws (T-3120, after [[T-3104]]).
    /// `iOSTodayView` builds this pane with no arguments, so its own midnight body pass does not
    /// reach this one, and the `.onChange(of: todayKey)` below never saw the key move.
    @State private var observedDay = CadenceObservedDay()

    private var todayKey: String {
        observedDay.todayKey
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// **Read, not re-derived.** These are the identical calls `iOSCalendarView` makes for the same
    /// grid, so a block that is on the Calendar's today column is on this pane and the other way
    /// about. A narrower query here — "today's tasks only" — is what would let the two surfaces
    /// disagree about what a scheduled task is.
    private var scheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.tasksByScheduledDate(allTasks, includeCompleted: true)
    }

    /// Drives the one-line hint, and it is about the *grid*, not the day: the hint's job is to say
    /// that tapping an hour is what fills the grid, so it stays for as long as the grid is empty —
    /// which is also the only time there is room for it. It goes the moment the first block lands,
    /// by which point the gesture has been used.
    ///
    /// **Events count towards "empty" now**, which they could not before, because the pane could
    /// not see them: a day with three meetings and no Cadence task is not a day with nothing on it,
    /// and "No timed blocks yet" printed over three drawn blocks would be the pane contradicting
    /// itself.
    private var hasNoBlocks: Bool {
        CadenceScheduleSupport.items(on: todayKey, in: scheduledTasksByDate).isEmpty
            && todayEvents.allSatisfy(\.isAllDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasNoBlocks {
                Text(iOSSchedulePanelCopy.emptyScheduleHint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
            }

            iOSCalendarTimelineGrid(
                // Constant on both: a single-day grid builds no horizontal scroller, so nothing in
                // it reports a leading column back or moves a selection, and a `@State` date here
                // would be a stored selection that only ever held one value. The day key is the
                // subject — `DateFormatters.todayKey()` — and `today` is that key as a `Date`.
                leadingDate: .constant(today),
                selectedDate: .constant(today),
                span: .singleDay,
                scheduledTasksByDate: scheduledTasksByDate,
                // **Empty on purpose, and it stays empty now that the single-day grid draws a
                // strip** ([[T-3163]]). The strip carries all-day EVENTS and nothing else: an
                // untimed task is already listed in full by the task column across the divider, so
                // repeating it above the hours would be the page header said twice. The grid
                // enforces that itself — `singleDaySplit` passes `unscheduledTasks: 0` rather than
                // reading this dictionary — so this argument is what the *scrolling* grid's header
                // would draw, and there is no scrolling grid here.
                unscheduledTasksByDate: [:],
                eventsByDate: [todayKey: todayEvents],
                todayKey: todayKey,
                zoom: $zoomLevel,
                // **Unused on this pane now, and deliberately still passed** ([[T-3169]]).
                // `drawsDraftBlocks` makes the column open a draft instead of calling this, but the
                // grid's other call site — the Calendar page — still routes its tap to a sheet, so
                // the closure stays part of the column's contract rather than becoming optional for
                // one caller. Nothing here can reach it.
                onCreateAt: { _, _ in },
                drawsDraftBlocks: true
            )
        }
        // **T-586.** `Theme.surface`, and it ignores the safe area, because this pane and
        // `iOSNotesView` are the two halves of one rail: the switcher above them selects between
        // them, and a background that changed with the selection made the selection look like a
        // change of page. This half drew `Theme.bg` inside the safe area and the other
        // `Theme.surface` beyond it. Surface is the side that wins — it is what the task column
        // beside the rail draws, what `iOSNotesView` draws everywhere it is hosted, and the one of
        // the two this pane could change without changing a page that also stands alone.
        .background(Theme.surface.ignoresSafeArea())
        .onChange(of: calendarManager.storeVersion, initial: true) { _, _ in
            refreshTodayEvents()
        }
        .onChange(of: calendarManager.isAuthorized) { _, _ in
            refreshTodayEvents()
        }
        // The midnight rollover. The day key is read from the clock, so the pane's subject changes
        // without anything telling it; this is the same `scenePhase` test the Calendar page uses to
        // flush its position, read the other way round.
        .onChange(of: todayKey) { _, _ in
            refreshTodayEvents()
        }
        .cadenceTracksDayChanges($observedDay)
    }

    // `quickCreateComposer` used to be declared here, and with it the whole of the docked bar.
    //
    // **It is gone because it was the ticket** ([[T-3169]]). The bar sat under the canvas and said
    // `Create at 4:00 PM` in words, so the user read a sentence about a time instead of seeing a
    // block at it; it could make a task and never an event, on a canvas that draws both; and
    // press-and-hold — the gesture every calendar on this platform uses to make something — did
    // nothing at all. The owner's verdict was "it looks so ugly."
    //
    // What replaced it is not a prettier bar. `drawsDraftBlocks` above makes the day column itself
    // answer the gesture: a press-and-hold draws a DRAFT BLOCK in place, at the pressed time, with
    // a default hour and a drag handle at each end, and the shared `CadenceSchedulePanel` hangs off
    // that block as a popover. The thing being created is visible on the canvas, at the time it
    // will occupy, before it is named — which is what the bar's placement could not do and is the
    // reason the bar's argument for docking (keeping the grid still) no longer has anything to buy.

    /// One day's events, through the shared manager and nothing else.
    ///
    /// `iOSCalendarManager` owns the app's single `EKEventStore`, the authorization state, the
    /// visible-calendar filter and the `EKEventStoreChanged` observer that drives `storeVersion`.
    /// This pane opens no store, requests no access and names no calendar; it asks for a day and is
    /// handed what the Calendar page would be handed for the same day. That is also what makes the
    /// disarmed-launch gate ([[T-3031]]) cover this surface for free.
    private func refreshTodayEvents() {
        guard calendarManager.isAuthorized else {
            if !todayEvents.isEmpty { todayEvents = [] }
            return
        }
        todayEvents = calendarManager.fetchEvents(for: today)
    }
}

#endif
