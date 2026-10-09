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
/// grid queried `AppTask` and `TaskBundle` and **never opened EventKit at all**, so there was no
/// event to drop anywhere; it carried no `iOSNewTaskDropTarget`, so a dragged `+` had nothing to
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
    @Query private var allBundles: [TaskBundle]
    /// Shared with the Calendar page through `CadenceCalendarZoom.storageKey`. See the type note.
    @AppStorage(CadenceCalendarZoom.storageKey) private var zoomLevel = CadenceCalendarZoom.defaultZoom
    /// Today's events, cached rather than fetched from `body`.
    ///
    /// **T-570's rule, restated on the surface that now needs it.** A synchronous EventKit
    /// predicate query in a computed property runs on every body pass, which here would mean once
    /// per frame of a pinch. One day's fetch, re-run only when the store changes or the day does.
    @State private var todayEvents: [EKEvent] = []
    @State private var quickCreateStartMin: Int?
    @State private var quickCreateTitle = ""
    @State private var quickCreateError: String?

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// **Read, not re-derived.** These are the identical calls `iOSCalendarView` makes for the same
    /// grid, so a block that is on the Calendar's today column is on this pane and the other way
    /// about. A narrower query here — "today's tasks only" — is what would let the two surfaces
    /// disagree about what a scheduled task is.
    private var scheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.tasksByScheduledDate(allTasks, includeCompleted: false)
    }

    private var bundlesByDate: [String: [TaskBundle]] {
        CadenceScheduleSupport.bundlesByDate(allBundles, includeCompleted: false)
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
            && CadenceScheduleSupport.items(on: todayKey, in: bundlesByDate).isEmpty
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
                // The day header is the only thing that draws these and a single-day grid has none.
                unscheduledTasksByDate: [:],
                bundlesByDate: bundlesByDate,
                eventsByDate: [todayKey: todayEvents],
                allTasks: allTasks,
                zoom: $zoomLevel,
                onCreateAt: { _, startMin in selectQuickCreateStart(startMin) }
            )

            quickCreateComposer
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
    }

    /// The composer, docked under the grid rather than inserted into it.
    ///
    /// It used to open inline, directly beneath the hour row that was tapped, and that placement
    /// was load-bearing *for that grid*: an hour row is a flow, so a composer inserted above the
    /// fold pushed every later hour down and the lane you had just aimed at slid out from under
    /// your finger. The Calendar's day column is not a flow — every block is placed absolutely over
    /// a fixed ladder — so nothing above or below the tapped minute moves when this appears, and
    /// there is no row to open "beneath" in the first place. Docking it at the foot of the pane
    /// keeps the grid still, which is the property the inline placement was bought for.
    ///
    /// It still names the minute it will create at, which is what makes a docked bar legible: the
    /// tap is a quarter-hour (`CadenceScheduleSupport.timelineMinute`), and the bar says so.
    @ViewBuilder
    private var quickCreateComposer: some View {
        if let quickCreateStartMin {
            iOSScheduleQuickCreateBar(
                startMin: quickCreateStartMin,
                title: $quickCreateTitle,
                errorMessage: quickCreateError,
                create: createScheduledTask,
                cancel: cancelQuickCreate
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            // **T-589.** "Add a title first." used to stay red under the field while you typed the
            // title it was asking for. `selectQuickCreateStart` and `cancelQuickCreate` were the
            // only two clears, so the one edit that answers the complaint — typing — did not.
            // The notice is about the field's *current* contents; the moment they change it is
            // stating something that is no longer true, whichever of the two messages it is
            // carrying. Attached to the composer rather than to the pane because the title can
            // only change while the composer is up, and a clear that outlives its own field is the
            // shape this is fixing.
            .onChange(of: quickCreateTitle) { _, _ in
                quickCreateError = nil
            }
        }
    }

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

    private func selectQuickCreateStart(_ startMin: Int) {
        quickCreateStartMin = startMin
        quickCreateError = nil
    }

    private func cancelQuickCreate() {
        quickCreateStartMin = nil
        quickCreateTitle = ""
        quickCreateError = nil
    }

    private func createScheduledTask() {
        guard let startMin = quickCreateStartMin else { return }
        let pendingTitle = quickCreateTitle
        do {
            guard (try CadenceTaskMutationSupport.insertScheduledTask(
                title: pendingTitle,
                allTasks: allTasks,
                modelContext: modelContext,
                scheduledDate: todayKey,
                scheduledStartMin: startMin,
                estimatedMinutes: 30
            )) != nil else {
                quickCreateError = "Add a title first."
                return
            }
            cancelQuickCreate()
        } catch {
            quickCreateTitle = pendingTitle
            quickCreateError = "Couldn't save this timed task."
        }
    }
}

private struct iOSScheduleQuickCreateBar: View {
    let startMin: Int
    @Binding var title: String
    let errorMessage: String?
    let create: () -> Void
    let cancel: () -> Void
    @FocusState private var isFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                iOSIconTile(systemImage: "clock.badge.plus", color: Theme.blue, size: 28, iconSize: 12, bordered: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create at \(TimeFormatters.timeString(from: startMin))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text("Adds a 30 minute task to Today.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                // 26pt of plate, 44pt of hit area — the same trick `iOSIconButton` uses, rather
                // than a 26pt tap target on the control that gets you out of the composer.
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 26, height: 26)
                        .background(Theme.surfaceElevated.opacity(0.38))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .contentShape(Rectangle())
                        .iOSExpandedHitArea(9)
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel("Cancel timed task")
            }

            HStack(spacing: 7) {
                TextField("Timed task title...", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .focused($isFocused)
                    .submitLabel(.done)
                    // **Deliberately not guarded the way the `+` beside it is disabled** (T-589).
                    // The button can refuse in a way you can see: it greys out, so an empty title
                    // has already been answered before you reach for it. Return has no such
                    // affordance, so guarding it would make the key do nothing at all and look
                    // broken — the "inert control, no word on it" failure T-470/T-471 went through
                    // this app removing. `create` reports instead, and the notice now clears on
                    // the next keystroke.
                    .onSubmit(create)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Theme.surface.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.52), lineWidth: 1)
                    }

                Button(action: create) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(trimmedTitle.isEmpty ? Theme.dim : Theme.onColor(for: Theme.blue))
                        .frame(width: 44, height: 44)
                        .background(trimmedTitle.isEmpty ? Theme.surfaceElevated.opacity(0.42) : Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.iosPressable)
                .disabled(trimmedTitle.isEmpty)
                .accessibilityLabel("Create timed task")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.36), cornerRadius: Theme.radiusCard)
        .onAppear {
            isFocused = true
        }
    }
}

#endif
