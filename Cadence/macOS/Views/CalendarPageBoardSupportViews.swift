#if os(macOS)
import EventKit
import SwiftData
import SwiftUI

/// What one day column of the Calendar Board draws from EventKit, **through the page's day cache**
/// (T-1570).
///
/// This was `CalendarPageBoardView.calendarDisplayItems(for:)`, and it called
/// `calendarManager.fetchAllDayEvents(for:)` and `calendarManager.fetchEvents(for:)` back to back
/// with no memoisation of any kind — two `NSPredicate` builds and two `EKEventStore.events(matching:)`
/// runs per *realized day column*, per render, inside a `ForEach` over
/// `CalendarBoardPlannerSupport.plannerRenderDayCount`. The board re-renders on every task change,
/// every store refresh and every rail toggle, so a `LazyHStack` holding six to ten columns paid
/// twelve to twenty queries each time. It is the same defect T-1499 closed on Today's timeline, on
/// the surface T-1499 used as its control — and, like that one, **it is a query count and not a
/// duration**: the board is reported smooth and nothing here claims otherwise.
///
/// The cache is the caller's, not this function's, for T-1499's reason: it has to belong to a
/// lifetime longer than one body evaluation or the memo never survives one. Here that lifetime is
/// `CalendarPageView.calendarEventDayCache`, the cache the month grid and the timeline viewport
/// were already given — so the board is no longer the one presentation on that page that queries
/// the store directly, and switching presentations reuses the warm days rather than re-querying
/// them.
///
/// Taking `any CalendarEventDaySource` rather than `CalendarManager` is also what makes the cost
/// countable: the test host is not calendar-authorised, so against the shipping manager every
/// fetch-count reads zero whatever the code does.
enum CalendarPageBoardDataSupport {
    @MainActor
    static func calendarDisplayItems(
        for date: Date,
        calendarManager: any CalendarEventDaySource,
        cache: CalendarEventDayCache,
        calendar: Calendar = .current
    ) -> [CalendarBoardEventDisplayItem] {
        // **The UI-test seam, and it is first on purpose** ([[T-1843]]). The host that runs this
        // target holds no EventKit authorisation, so the guard below answers `[]` for every day
        // and the board's event card has never been on screen in a test. When — and only when —
        // the scenario asks for it, the day's events come from `CalendarBoardUITestEventSupport`
        // instead and EventKit is not consulted at all. `nil` is "not under that scenario", which
        // is every shipping launch.
        if let injected = CalendarBoardUITestEventSupport.injectedItems(for: date, calendar: calendar) {
            return injected
        }
        guard calendarManager.isAuthorized else { return [] }
        let allDay = cache.allDayEvents(for: date, calendarManager: calendarManager).map {
            CalendarBoardEventDisplayItem(allDay: $0, date: date, calendar: calendar)
        }
        let timed = CalendarEventItem
            .timedSegments(
                from: cache.timedEvents(for: date, calendarManager: calendarManager),
                for: date,
                calendar: calendar
            )
            .map(CalendarBoardEventDisplayItem.init(timed:))
        return (allDay + timed).sorted { $0.sortKey < $1.sortKey }
    }
}

/// **The one way a `CalendarBoardEventCard` reaches the screen under test** ([[T-1843]]).
///
/// The board's event card is the third of its `attachmentAnchor: .rect(.bounds)` popovers and the
/// only one [[T-1740]]'s sweep could not read, because the card is drawn from an `EKEvent` and
/// `CadenceUITestScenarioSeed` writes SwiftData. The two ways out were an EventKit authorisation
/// the runner could hold — which is the signed-in person's own calendar, on a host that must never
/// be written to — or a seam that injects a display item without one. This is the second.
///
/// **The event is never saved and never asked for.** `EKEvent(eventStore:)` on an unsaved event
/// needs no TCC prompt and touches no store, and that is a reading rather than an assumption —
/// two tests in `CadenceTests` have been building unsaved events this way since T-693.
///
/// **It carries an unsaved `EKCalendar`, and that is not decoration — it is MEASURED.** The first
/// cut of this seam left `event.calendar` nil, which every surrounding type tolerates:
/// `CalendarEventItem` and `CalendarBoardEventDisplayItem` both read `event.calendar?.cgColor ??`
/// and `event.calendar?.title ??`, so the card drew, tinted and titled itself from the product's
/// own fallbacks. **Then the card was clicked and the app died in `EXC_BREAKPOINT` inside**
/// `CalendarEventEditPopover.init` (2026-10-03, crash report `Cadence-2026-10-03-135632.ips`):
/// `EKEvent.calendar` is an implicitly-unwrapped `EKCalendar!` and that initialiser is the one
/// place in this path that reads it straight through, at
/// `_selectedCalendarID = State(initialValue: item.ekEvent.calendar.calendarIdentifier)`. No event
/// fetched from a real store can have a nil calendar, so this is not a defect a user can reach;
/// it is a constraint on what this seam is allowed to hand it, and it is written down as
/// [[T-2047]] rather than left as a surprise for whoever builds the next fixture event.
///
/// **Held once.** The item is rebuilt per call but the `EKEvent` under it is not: the board
/// re-renders on every store change and a fresh event each time would give the card a new
/// `calendarItemIdentifier`, a new `ForEach` identity and therefore a reset `@State showPopover`
/// — a popover that closes itself at the next render is not something a placement reading can be
/// taken from.
@MainActor
enum CalendarBoardUITestEventSupport {

    /// Both halves, and both are required. `CADENCE_UI_TEST_MODE` alone is not enough: the other
    /// UI suites in this target run under it too, and an event card appearing in their columns
    /// would change what they are measuring.
    static var isActive: Bool {
        CadenceUITestSupport.isEnabled && CadenceUITestScenarioSeed.requestedScenario == .popoverAnchors
    }

    /// `nil` when the scenario is not asking — which is every shipping launch, and is what keeps
    /// the authorisation guard below the only thing a real board consults.
    ///
    /// When it *is* asking it owns the whole answer, including the empty one for every day that is
    /// not today: falling through to EventKit for the other columns would mean the board under
    /// test had two sources, and a card appearing in the wrong column would read as a sorting
    /// defect rather than as a second source.
    static func injectedItems(for date: Date, calendar: Calendar = .current) -> [CalendarBoardEventDisplayItem]? {
        guard isActive else { return nil }
        guard DateFormatters.dateKey(from: date) == DateFormatters.todayKey() else { return [] }
        guard let item = CalendarEventItem(event: event(on: date, calendar: calendar), clippedTo: date, calendar: calendar) else {
            return []
        }
        return [CalendarBoardEventDisplayItem(timed: item)]
    }

    private static var heldEvent: EKEvent?

    private static func event(on date: Date, calendar: Calendar) -> EKEvent {
        if let heldEvent { return heldEvent }
        let store = EKEventStore()
        let created = EKEvent(eventStore: store)
        // See the note above: `CalendarEventEditPopover` reads `ekEvent.calendar` through an
        // implicitly-unwrapped optional, so a fixture event without one crashes the app the
        // moment its card is clicked. An unsaved `EKCalendar` needs no authorisation either and
        // carries a `calendarIdentifier` of its own from the moment it is made.
        let calendarForEvent = EKCalendar(for: .event, eventStore: store)
        calendarForEvent.title = CadenceUITestScenarioSeed.Fixture.boardEventCalendarTitle
        created.calendar = calendarForEvent
        created.title = CadenceUITestScenarioSeed.Fixture.boardEventTitle
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(
            byAdding: .minute,
            value: CadenceUITestScenarioSeed.Fixture.boardEventStartMinute,
            to: dayStart
        ) ?? dayStart
        created.startDate = start
        created.endDate = start.addingTimeInterval(
            TimeInterval(CadenceUITestScenarioSeed.Fixture.boardEventDurationMinutes * 60)
        )
        created.isAllDay = false
        heldEvent = created
        return created
    }
}

/// What the Calendar Board's Unscheduled rail does with a dropped card, with the commit it reports
/// on injectable ([[T-1952]]).
///
/// **What the user saw.** The view's own unschedule drop handler — renamed to
/// `CalendarPageBoardView.handleUnscheduleDrop` by this same change, so the old spelling no
/// longer resolves and is deliberately not written here — ended
/// `try? modelContext.save(); return true`, and that `true` is what `.dropDestination` reads to
/// decide whether the card stays where it was released. A drop the store refused was accepted,
/// drawn on the Unscheduled rail, and put back at the next launch with nothing to retry — the
/// [[T-566]] shape, the sibling of the All Tasks drop [[T-1580]] fixed, and the two were listed
/// together under one [[T-636]](b) comment in `CadenceSaveCommitRule.reportExemptions`.
///
/// **Where it is not the same shape, and why that mattered.** `TasksPanelSupport.assignTask` writes
/// nothing but task fields. This drop changes *existence* one frame down before it touches the
/// date: a card dragged off a block runs `SchedulingActions.removeTaskFromBundle`, which empties the
/// task out of `TaskBundle.tasks`, nils its `bundle`, and renumbers every remaining member through
/// `normalizeBundleOrder`. So T-1580's undo was not enough on its own —
/// `CadenceTaskFieldSnapshot` carried neither `bundle` nor `bundleOrder`, and a `.refused` answered
/// over that snapshot would have left the card out of the block it was still being drawn in while
/// telling the user nothing had changed. The snapshot carries both now, and the block's other
/// members ride along in `alsoRestoring:` so the renumbering comes back with them.
///
/// **Resolution happens before anything is written**, for `assignTask`'s reason: a payload this
/// board cannot place must not reach `commit` at all, or a drop that moved no field would commit
/// whatever unrelated pending work the app's single `ModelContext` is holding.
@MainActor
enum CalendarPageBoardDropSupport {
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and an
    ///   undo path no test can reach is an undo path no test can prove.
    static func unschedule(
        _ items: [String],
        in allTasks: [AppTask],
        modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        guard let action = CalendarBoardPlannerSupport.dropAction(for: .rail(.unscheduled)),
              let payload = items.first,
              let taskID = TaskDragPayload.taskID(from: payload),
              let task = allTasks.first(where: { $0.id == taskID }) else { return .resolvedNothing }

        // The block's other members, snapshotted beside the dragged card because
        // `normalizeBundleOrder` renumbers them as part of the detach. Read off the inverse rather
        // than the array, which can still list a task whose own `bundle` has moved on.
        let blockSiblings = (task.bundle?.tasks ?? []).filter {
            $0.id != task.id && $0.bundle?.id == task.bundle?.id
        }

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            alsoRestoring: blockSiblings,
            in: modelContext,
            reconciler: reconciler,
            commit: commit
        ) {
            if task.bundle != nil {
                SchedulingActions.removeTaskFromBundle(task, keepOnBundleDate: false)
            }
            CalendarBoardPlannerSupport.apply(action, to: task)
        }
        return landed ? .applied : .refused
    }

    /// A **day column's** drop of a card ([[T-1980]]), the sibling of `unschedule` above and the
    /// same three answers.
    ///
    /// It was the second of the two swallows left in this file when T-1952 closed, and the pair is
    /// worth a sentence about *why* the sweep could not see them: both returned `Void`, so there
    /// was no answer for `CadenceSaveCommitRule`'s report half to read, and the `true` the drop
    /// actually reports is built one frame up in another file — `CalendarBoardDayColumn.handleDrop`
    /// returned it unconditionally. Invisible rather than exempted. The detector half of that is
    /// [[T-1990]]; this is the defect half.
    ///
    /// **Three fields past the do date, and the reason this is not a one-line change.** A card
    /// dragged onto a day runs `SchedulingActions.removeTaskFromBundle` first, exactly as the rail
    /// drop does, so `bundle`/`bundleOrder` move and the block's remaining members are renumbered —
    /// they ride in `alsoRestoring:`. The drop also materialises `estimatedMinutes` when the card
    /// has none, so the block it draws on the timeline is the length the board already shows.
    static func schedule(
        _ task: AppTask,
        on dateKey: String,
        modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        guard let action = CalendarBoardPlannerSupport.dropAction(for: .day(dateKey)) else {
            return .resolvedNothing
        }

        // Read off the inverse rather than the array, for `unschedule`'s reason: the array can
        // still list a task whose own `bundle` has moved on.
        let blockSiblings = (task.bundle?.tasks ?? []).filter {
            $0.id != task.id && $0.bundle?.id == task.bundle?.id
        }

        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            alsoRestoring: blockSiblings,
            in: modelContext,
            reconciler: reconciler,
            commit: commit
        ) {
            if task.bundle != nil {
                SchedulingActions.removeTaskFromBundle(task, keepOnBundleDate: false)
            }
            CalendarBoardPlannerSupport.apply(action, to: task)
            if task.estimatedMinutes <= 0 {
                task.estimatedMinutes = AppTask.defaultTimelineDurationMinutes
            }
        }
        return landed ? .applied : .refused
    }

    /// A **day column's** drop of a whole block ([[T-1980]]), the third of this board's drops and
    /// the only one whose subject is not a task.
    ///
    /// `SchedulingActions.dropBundle` writes the block's own `dateKey`/`startMin`/`durationMinutes`
    /// and then every member's `scheduledDate`, `scheduledStartMin` and `calendarEventID`. So the
    /// undo is `CadenceTaskFieldEditCommit.commitBlockMove`: the slot through
    /// `CadenceTaskBundleSlotSnapshot`, the members through the same `CadenceTaskFieldSnapshot`
    /// every other commit on this board uses — which is why `calendarEventID` joined that set in
    /// this change rather than being snapshotted a second way here.
    ///
    /// **An empty `dateKey` answers `.resolvedNothing`** rather than committing: it is the same
    /// "this board cannot place that" the rail drop guards for, and `dropAction(for: .day(""))` is
    /// already `nil` — asked here so a block move and a card move refuse the same input.
    static func move(
        _ bundle: TaskBundle,
        to dateKey: String,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        guard CalendarBoardPlannerSupport.dropAction(for: .day(dateKey)) != nil else {
            return .resolvedNothing
        }

        let members = (bundle.tasks ?? []).filter { $0.bundle?.id == bundle.id }
        let landed = CadenceTaskFieldEditCommit.commitBlockMove(
            bundle,
            members: members,
            in: modelContext,
            commit: commit
        ) {
            SchedulingActions.dropBundle(bundle, to: dateKey, startMin: bundle.startMin)
        }
        return landed ? .applied : .refused
    }
}

/// The Calendar Board: day columns that scroll horizontally, flanked by two pinned rails.
///
/// The rails are what the retired Planning page turned into. Overdue and Unscheduled were two of
/// its five buckets; the other three (Today / This Week / Later) *are* day columns here, so they
/// needed no equivalent. Everything else Planning did — its bucketing, its drag-to-reschedule, its
/// drag-back-to-unscheduled, its "N unscheduled · N overdue" summary — lives on this surface now.
struct CalendarPageBoardView: View {
    private static let columnWidth = CadenceCalendarBoardLayout.dayColumnWidth
    private static let columnSpacing = CadenceCalendarBoardLayout.dayColumnSpacing
    private static let horizontalPadding = CadenceCalendarBoardLayout.dayColumnHorizontalPadding

    let anchorDate: Date
    @Binding var selectedDate: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let bundlesByDate: [String: [TaskBundle]]
    /// The calendar page's own `CalendarEventDayCache`, handed down rather than made here (T-1570).
    /// The month grid and the timeline viewport were always given it; the board was the one
    /// presentation reading `EKEventStore` straight through, once per realized column per render.
    let eventCache: CalendarEventDayCache

    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    /// Latches a `selectedDate` write this view made itself, so the `anchorDate` change it comes
    /// back as does not re-run `resetWindowAndScroll` and re-scroll the board a second time.
    @State private var isEchoingSelectedDate = false
    @State private var isProgrammaticScroll = false
    @State private var windowStartDate: Date?
    /// Which rail the user has opened while the pane is too narrow to keep both open. One at a
    /// time, so the fixed side never costs more than one expanded rail plus one strip — the whole
    /// point of the gate. Ignored above `CadenceCalendarBoardLayout.expandedRailsMinimumWidth`.
    @State private var userExpandedRail: CalendarBoardRail?
    /// The board's one notice slot, and it had none at all before [[T-1952]] — which is why that
    /// ticket was a surface decision on top of a commit rather than the commit alone. Cleared by
    /// the next drop, like every other `*FailureNotice` on a drop surface: the retry is the report.
    @State private var dropFailureNotice: String?

    private let calendar = Calendar.current

    private var renderDays: Int {
        CalendarBoardPlannerSupport.plannerRenderDayCount
    }

    /// Floored at today: this board's Overdue rail already shows every past-dated card, so a past
    /// day column would show the same card twice.
    private var activeWindowStartDate: Date {
        windowStartDate ?? CalendarBoardPlannerSupport.plannerWindowStart(
            for: anchorDate,
            notBefore: Date(),
            calendar: calendar
        )
    }

    private var boardTasksByDate: [String: [AppTask]] {
        CalendarBoardPlannerSupport.tasksByBoardDate(from: allTasks)
    }

    private var railTasks: [CalendarBoardRail: [AppTask]] {
        CalendarBoardPlannerSupport.railTasks(from: allTasks, todayKey: DateFormatters.todayKey())
    }

    var body: some View {
        // The width read here is the guarantee. The `HStack` below has two fixed-width children
        // and one horizontal `ScrollView`, and a horizontal scroller declares no minimum — so
        // nothing but this measurement stands between the day columns and 74pt. See
        // `CadenceCalendarBoardLayout`, and `CadenceDesktopSplitLayout` for why the window floor
        // is not where this can be fixed. A `GeometryReader` rather than `onGeometryChange` for
        // `TodayView`'s reason: the board fills its pane in both axes, so there is no unmeasured
        // first frame to guess a layout for.
        GeometryReader { proxy in
            // The surface asks the house file and passes the *answer* down, never the width —
            // `TodayView`'s shape, and what keeps `CadencePaneWidthRuleHomesTests`' scan honest
            // about where a width-derived decision may be declared.
            board(boardForm: CadenceCalendarBoardLayout.railForm(paneWidth: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }

    private func board(boardForm: CadenceCalendarBoardRailForm) -> some View {
        let rails = railTasks

        return VStack(spacing: 0) {
            summary(rails)

            // Indented to the summary's gutter, above the rails rather than inside one: the drop
            // it reports on can land on a rail that is collapsed to a strip, and a sentence drawn
            // in there would be a sentence nobody can read.
            if let dropFailureNotice {
                CadenceInlineFailureNotice(text: dropFailureNotice)
                    .padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 0) {
                rail(.overdue, tasks: rails[.overdue] ?? [], boardForm: boardForm)
                dayColumns
                rail(.unscheduled, tasks: rails[.unscheduled] ?? [], boardForm: boardForm)
            }
        }
    }

    /// What one rail draws: the board's own answer where the pane can pay for both, and otherwise
    /// the strip — unless this is the one the user has opened.
    private func form(
        for rail: CalendarBoardRail,
        boardForm: CadenceCalendarBoardRailForm
    ) -> CadenceCalendarBoardRailForm {
        guard boardForm == .collapsed else { return .expanded }
        return userExpandedRail == rail ? .expanded : .collapsed
    }

    /// The Planning page's "N unscheduled · N overdue" line, kept because it is the one thing the
    /// rails cannot say on their own: each header counts its own pile, this reads both at a glance.
    /// Indented to the toolbar's page padding, not the board's, so it lines up under "Calendar".
    private func summary(_ rails: [CalendarBoardRail: [AppTask]]) -> some View {
        Text(CalendarBoardPlannerSupport.railSummaryLine(rails))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    private func rail(
        _ rail: CalendarBoardRail,
        tasks: [AppTask],
        boardForm: CadenceCalendarBoardRailForm
    ) -> some View {
        // Only the Unscheduled rail takes drops or offers an add row; the Overdue rail gets `nil`
        // for both because a card cannot be dragged — or created — *into* being late.
        CalendarBoardRailColumn(
            rail: rail,
            tasks: tasks,
            add: addBehavior(for: .rail(rail)),
            form: form(for: rail, boardForm: boardForm),
            // `nil` where the pane can pay for both rails: there is nothing to toggle, so there is
            // no control offering to.
            onToggleForm: boardForm == .collapsed ? { toggleRail(rail) } : nil,
            onDrop: { items in rail == .unscheduled ? handleUnscheduleDrop(items) : false }
        )
    }

    /// One rail open at a time. Opening the other closes the first rather than stacking two
    /// expanded columns back onto a pane that was too narrow for them.
    private func toggleRail(_ rail: CalendarBoardRail) {
        withAnimation(kanbanColumnStateAnimation) {
            userExpandedRail = userExpandedRail == rail ? nil : rail
        }
    }

    private var dayColumns: some View {
        let tasksByDate = boardTasksByDate
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(0..<renderDays, id: \.self) { dayIndex in
                        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
                        let dateKey = DateFormatters.dateKey(from: date)
                        CalendarBoardDayColumn(
                            dayIndex: dayIndex,
                            date: date,
                            dateKey: dateKey,
                            tasks: tasksByDate[dateKey] ?? [],
                            bundles: bundlesByDate[dateKey] ?? [],
                            events: calendarDisplayItems(for: date),
                            allTasks: allTasks,
                            allBundles: allBundles,
                            areas: areas,
                            projects: projects,
                            add: addBehavior(for: .day(dateKey)),
                            onDropTaskOnDay: { task in handleDayColumnDrop(task, on: dateKey) },
                            onDropBundleOnDay: { bundle in handleBlockMoveDrop(bundle, on: dateKey) },
                            onDropTaskOnBundle: { task, bundle in
                                SchedulingActions.addTask(task, to: bundle)
                                try? modelContext.save()
                            }
                        )
                        .frame(width: Self.columnWidth)
                        .id(dayIndex)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .horizontal)
            .frame(maxWidth: .infinity)
            .onScrollGeometryChange(for: Int.self) { geometry in
                visibleDayIndex(for: geometry.contentOffset.x)
            } action: { _, dayIndex in
                updateSelectedDate(for: dayIndex, proxy: proxy)
            }
            .onAppear {
                resetWindowAndScroll(proxy, to: anchorDate, animated: false)
            }
            .onChange(of: anchorDate) { _, newDate in
                if isEchoingSelectedDate {
                    isEchoingSelectedDate = false
                    return
                }
                resetWindowAndScroll(proxy, to: newDate, animated: true)
            }
        }
    }

    private func visibleDayIndex(for offsetX: CGFloat) -> Int {
        let stride = Self.columnWidth + Self.columnSpacing
        let rawIndex = Int(((offsetX - Self.horizontalPadding) / stride).rounded())
        return min(max(rawIndex, 0), renderDays - 1)
    }

    private func resetWindowAndScroll(_ proxy: ScrollViewProxy, to date: Date, animated: Bool) {
        // A remembered anchor can point into the past (the timeline and month views browse
        // freely), but the board no longer renders past days — so clamp, and write the clamp back
        // so the toolbar title agrees with the column the board actually lands on. `selectedDate`
        // is the same state this view reads as `anchorDate`, so latch the write: unlatched it
        // returns as an anchor change and scrolls the board a second time, animated, on appear.
        let clampedDate = CalendarBoardPlannerSupport.clampedBoardDate(date, calendar: calendar)
        if !calendar.isDate(clampedDate, inSameDayAs: selectedDate) {
            isEchoingSelectedDate = true
            selectedDate = clampedDate
        }

        let startDate = CalendarBoardPlannerSupport.plannerWindowStart(
            for: clampedDate,
            notBefore: Date(),
            calendar: calendar
        )
        isProgrammaticScroll = true
        windowStartDate = startDate
        let target = CalendarBoardPlannerSupport.dayIndex(
            for: clampedDate,
            bufferStart: startDate,
            calendar: calendar,
            renderDays: renderDays
        )
        scroll(proxy, to: target, anchor: .leading, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.26 : 0.08)) {
            isProgrammaticScroll = false
        }
    }

    private func recenterWindowIfNeeded(_ proxy: ScrollViewProxy, visibleDayIndex dayIndex: Int, visibleDate: Date) {
        guard !isProgrammaticScroll else { return }
        // The window rests against its leading edge here — today is column 0 — so proximity alone
        // would fire on nearly every column crossing in the first six weeks and yank the board
        // mid-scroll. Only recenter when the window would genuinely move.
        guard let startDate = CalendarBoardPlannerSupport.recenteredWindowStart(
            visibleDayIndex: dayIndex,
            visibleDate: visibleDate,
            currentWindowStart: activeWindowStartDate,
            renderDays: renderDays,
            notBefore: Date(),
            calendar: calendar
        ) else { return }

        let recenteredDayIndex = CalendarBoardPlannerSupport.dayIndex(
            for: visibleDate,
            bufferStart: startDate,
            calendar: calendar,
            renderDays: renderDays
        )

        isProgrammaticScroll = true
        windowStartDate = startDate
        scroll(proxy, to: recenteredDayIndex, anchor: .leading, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isProgrammaticScroll = false
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to dayIndex: Int, anchor: UnitPoint, animated: Bool) {
        DispatchQueue.main.async {
            let clampedDayIndex = min(max(dayIndex, 0), renderDays - 1)
            if animated {
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(clampedDayIndex, anchor: anchor)
                }
            } else {
                proxy.scrollTo(clampedDayIndex, anchor: anchor)
            }
        }
    }

    private func updateSelectedDate(for dayIndex: Int, proxy: ScrollViewProxy) {
        guard !isProgrammaticScroll else { return }
        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: selectedDate) {
            isEchoingSelectedDate = true
            selectedDate = date
        }
        recenterWindowIfNeeded(proxy, visibleDayIndex: dayIndex, visibleDate: date)
    }

    /// A day column's "+" composes inline — the column supplies the do date, so the inline composer
    /// only has to ask for a name. The Unscheduled rail has no date to supply, so it opens the
    /// create sheet instead; that is what the Planning page's add row did before this board
    /// absorbed it.
    ///
    /// `insertInline` used to mean *insert*: it built an `AppTask` titled "New Task" and saved it,
    /// with no prompt at all, so a mis-click left an untitled card in the column. It now opens the
    /// composer over the same date, and creation runs through `TaskCreationService` like every
    /// other create path in the app.
    private func addBehavior(for target: CalendarBoardDropTarget) -> KanbanColumnAddBehavior? {
        switch CalendarBoardPlannerSupport.addAction(for: target) {
        case .none:
            return nil
        case .presentCreateSheet:
            return .presentSheet { taskCreationManager.present() }
        case .insertInline(let dateKey):
            // Whole-day columns: this board has no per-column time range, so the composer seeds no
            // timeline slot. `InlineTaskComposerSurface.day` carries one for a board that does.
            return .compose(.day(dateKey: dateKey, startMin: -1))
        }
    }

    /// The Unscheduled rail's drop. Clears the do date *and* the timeline slot together — an
    /// earlier version of this drag wrote only one of the two, which left the card bucketed
    /// exactly where it started and made the drop look like it had done nothing.
    ///
    /// **Three outcomes and not two ([[T-1952]]), the mapping [[T-1580]] spelled for All Tasks.**
    /// `.resolvedNothing` says nothing: the payload named a task this board is not holding, the row
    /// springs back, and that is the whole report. `.refused` borrows the board's one notice slot —
    /// `CadencePendingChangePersistence.editFailureNotice` is "Nothing was changed", and
    /// `CalendarPageBoardDropSupport.unschedule` has already put the do date, the timeline slot and
    /// the block membership back by the time it answers.
    private func handleUnscheduleDrop(_ items: [String]) -> Bool {
        let outcome = withAnimation(kanbanCardReorderAnimation) {
            CalendarPageBoardDropSupport.unschedule(
                items,
                in: allTasks,
                modelContext: modelContext
            )
        }
        dropFailureNotice = outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil
        return outcome == .applied
    }

    /// A day column's drop of a card. Goes through the same `apply` the Unscheduled rail uses, so
    /// both directions of the drag write the one field the board buckets on, and maps the same
    /// three answers onto the board's one notice slot ([[T-1980]]).
    private func handleDayColumnDrop(_ task: AppTask, on dateKey: String) -> Bool {
        let outcome = withAnimation(kanbanCardReorderAnimation) {
            CalendarPageBoardDropSupport.schedule(
                task,
                on: dateKey,
                modelContext: modelContext
            )
        }
        dropFailureNotice = outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil
        return outcome == .applied
    }

    /// A day column's drop of a whole block ([[T-1980]]). Same mapping, same slot.
    private func handleBlockMoveDrop(_ bundle: TaskBundle, on dateKey: String) -> Bool {
        let outcome = withAnimation(kanbanCardReorderAnimation) {
            CalendarPageBoardDropSupport.move(
                bundle,
                to: dateKey,
                modelContext: modelContext
            )
        }
        dropFailureNotice = outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil
        return outcome == .applied
    }

    /// **T-1570.** Served from `eventCache`, keyed by each column's `yyyy-MM-dd`. The
    /// `storeVersion` read stays here because it is the SwiftUI subscription — and it is also what
    /// invalidates the cache, since `CalendarEventDayCache` drops everything when that number
    /// moves.
    @MainActor
    private func calendarDisplayItems(for date: Date) -> [CalendarBoardEventDisplayItem] {
        let _ = calendarManager.storeVersion  // subscribe to store change refreshes
        return CalendarPageBoardDataSupport.calendarDisplayItems(
            for: date,
            calendarManager: calendarManager,
            cache: eventCache,
            calendar: calendar
        )
    }
}

#endif
