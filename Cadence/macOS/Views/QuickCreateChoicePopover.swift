#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

/// Everything the drag-create popover's **Task** arm decides, in one value.
///
/// **T-1433.** It used to hand back five loose arguments and let the canvas supply the slot from
/// the ghost it had drawn, because the popover's date and time were `Text`. They are fields now —
/// the owner asked for editable date and time at the top of the inspector — so the slot the user
/// confirms is the popover's, not the drag's, and a sixth, seventh and eighth positional argument
/// on a closure three hosts pass through is how call sites start transposing them.
///
/// **It is the shape of the two hosts' write closures, not of the form** ([[T-3171]], the seventh
/// adoption slice). The form is `CadenceSchedulePanel` now; this is what both hosts carry into
/// `SchedulePanelDataSupport.insertDragCreatedTask`, which writes through
/// `SchedulingActions.insertTask` and so `TaskCreationService.createTask` — the commit every macOS
/// task composer uses.
///
/// **It carries Due and Repeat** ([[T-3171]] (iii)). The popover used to withhold both rows because
/// this value had no member for them; `TaskCreationService` has always been able to write them, so
/// the rows are offered and the answers travel here. A field the panel offers that has no member
/// here still has nowhere to go, and the popover refuses such a draft out loud rather than
/// dropping it (T-470) — see `QuickCreateChoicePopover.hostLimitNotice`.
struct QuickCreateTaskDraft {
    var title: String
    /// `yyyy-MM-dd`, the repo's persisted form.
    var dateKey: String
    var startMin: Int
    var endMin: Int
    var container: TaskContainerSelection
    var sectionName: String
    var priority: TaskPriority
    var notes: String
    /// The shared panel's checklist, forwarded by both timeline hosts to the task insert.
    var subtaskTitles: [String]
    /// `yyyy-MM-dd`, or empty for no due date.
    var dueDateKey: String = ""
    var repeatRule: TaskRecurrenceRule = .none
    /// The series' end, already resolved through `CadenceScheduleDraft.effectiveSeriesEndMode`, so
    /// an `.onDate` with no day or an `.afterCount` with no count arrives as `.never`.
    var seriesEndMode: TaskRecurrenceEndMode = .never
    var seriesEndDateKey: String = ""
    var seriesEndCount: Int = 0
    /// The panel's All day: the task is filed on `dateKey` with no time, `scheduledStartMin -1`
    /// ([[T-6581]]). `startMin`/`endMin` are not written for it.
    var isAllDay: Bool = false
    /// The panel's Estimate, written as named — `0` is None. `nil` means "the slot's length",
    /// which is what a value built without the panel (a plain drag-out) has always meant.
    var estimateMinutes: Int? = nil
}

extension QuickCreateTaskDraft {
    /// The boundary between the shared form and both macOS creation closures.
    init(scheduleDraft draft: CadenceScheduleDraft) {
        self.init(
            title: draft.title,
            dateKey: draft.startDateKey,
            startMin: draft.startMin,
            endMin: draft.endMin,
            container: CadenceScheduleDraftChoices.container(for: draft),
            sectionName: draft.sectionName,
            priority: draft.priority,
            notes: draft.notes,
            subtaskTitles: draft.subtaskTitles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            dueDateKey: draft.dueDateKey,
            repeatRule: draft.repeatRule,
            seriesEndMode: draft.effectiveSeriesEndMode,
            seriesEndDateKey: draft.seriesEndDateKey,
            seriesEndCount: draft.seriesEndCount,
            isAllDay: draft.isAllDay,
            estimateMinutes: draft.estimateMinutes
        )
    }
}

/// What the drag-create popover's **Event** arm hands its host, in one value ([[T-3171]] (iv)).
///
/// It was five positional arguments — `(title, startMin, endMin, calendarID, notes)` — and no day,
/// so both hosts gave `CalendarManager.createStandaloneEvent` their own date and the popover had to
/// refuse any draft whose day the panel's grid had moved. The day travels now, as `dateKey`, and
/// the host resolves it through `day(or:)`.
///
/// **It carries All day, Location and Repeat** ([[T-3171]] (iii), the event half). The popover
/// used to withhold the Repeat and Location rows and refuse All day because this value, and the
/// write behind it, had nowhere to put them. Both hosts now hand the whole value to
/// `CalendarManager.createStandaloneEvent(_:hostDay:)`, which writes all three.
struct QuickCreateEventDraft: Equatable {
    var title: String
    /// `yyyy-MM-dd`: the day the panel's Starts row names.
    var dateKey: String
    var startMin: Int
    var endMin: Int
    var calendarID: String
    var notes: String
    /// When set, the event covers `dateKey`'s whole day and `startMin`/`endMin` are not written.
    var isAllDay: Bool = false
    /// Untrimmed; `CadenceEventCreationSupport.storedLocation` trims it at the write.
    var location: String = ""
    var repeatRule: TaskRecurrenceRule = .none
    /// The series' end, already resolved through `CadenceScheduleDraft.effectiveSeriesEndMode`, so
    /// an `.onDate` with no day or an `.afterCount` with no count arrives as `.never` — the same
    /// rule the task draft beside this one follows.
    var seriesEndMode: TaskRecurrenceEndMode = .never
    var seriesEndDateKey: String = ""
    var seriesEndCount: Int = 0
    /// `yyyy-MM-dd`: the day the panel's Ends row names ([[T-6582]]). Empty, or equal to `dateKey`,
    /// for an event inside one day — the case the write builds from a day and a length.
    var endDateKey: String = ""

    /// The day to create on: the draft's own, or `hostDay` only when the key does not parse — which
    /// the panel never produces, so the fallback exists to keep the write total, not as a rule.
    func day(or hostDay: Date) -> Date {
        DateFormatters.date(from: dateKey) ?? hostDay
    }

    var spansMultipleDays: Bool {
        endDateKey > dateKey
    }

    /// The two instants of an event that ends on a later day than it starts, all-day or timed
    /// ([[T-6582]]) — **`CadenceScheduleDraft.eventDateRange`'s answer, not a second spelling of
    /// it**, which is what iOS's drag-create writes through (`iOSScheduleDraftCreation.createEvent`).
    /// So an all-day end is exclusive and a timed end is a wall-clock reading on the end day, on
    /// both platforms. `nil` for an event inside one day, and for keys that cannot form a range.
    func multiDayRange(calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard spansMultipleDays else { return nil }
        var schedule = CadenceScheduleDraft(dateKey: dateKey, startMin: startMin, kind: .event)
        schedule.startMin = startMin
        schedule.endMin = endMin
        schedule.endDateKey = endDateKey
        schedule.isAllDay = isAllDay
        return schedule.eventDateRange(calendar: calendar)
    }
}

extension QuickCreateEventDraft {
    init(scheduleDraft draft: CadenceScheduleDraft) {
        self.init(
            title: draft.title,
            dateKey: draft.startDateKey,
            startMin: draft.startMin,
            endMin: draft.endMin,
            calendarID: draft.calendarID,
            notes: draft.notes,
            isAllDay: draft.isAllDay,
            location: draft.location,
            repeatRule: draft.repeatRule,
            seriesEndMode: draft.effectiveSeriesEndMode,
            seriesEndDateKey: draft.seriesEndDateKey,
            seriesEndCount: draft.seriesEndCount,
            endDateKey: draft.endDateKey
        )
    }
}

/// The prose each kind of the drag-create popover composes, kept apart.
///
/// **[[T-1610]].** There was one `@State private var notes` and both composers were handed it, so
/// a note typed on the **Event** tab rode into whatever the **Task** tab created next. That is not
/// a carry like `title`'s — the two fields are not the same field. The Event arm's prose is
/// `EKEvent.notes` and leaves the store entirely; the Task arm's is `AppTask.notes`.
///
/// **Two slots and not a clear-on-switch**, which is the same decision made without the loss: a
/// user who flips Task → Event → Task finds the task's own notes where they left them, and the
/// Event arm's where *they* were left. `title` keeps its single slot, because a title is the one
/// thing both arms genuinely share.
///
/// **Re-keyed to `CadenceScheduleDraftKind`** ([[T-3171]]), with the popover's own kind enum —
/// and the Block spelling of its first case, which [[T-3170]] missed because every Block pass hunted surfaces
/// that *display* a block and this one only creates. The rule is unchanged: `CadenceScheduleDraft`
/// carries one `notes`, so the popover parks the outgoing kind's prose here on every kind switch
/// and loads the incoming kind's back.
struct QuickCreateNotesDraft: Equatable {
    /// The Task arm's.
    var task = ""
    /// The Event arm's — Apple Calendar's note, not a task's.
    var event = ""

    /// What the draft carries while `kind` is selected.
    func notes(for kind: CadenceScheduleDraftKind) -> String {
        switch kind {
        case .task: return task
        case .event: return event
        }
    }

    /// Parks the draft's prose in the slot the kind being left owns.
    mutating func set(_ notes: String, for kind: CadenceScheduleDraftKind) {
        switch kind {
        case .task: task = notes
        case .event: event = notes
        }
    }
}

/// **The macOS calendar's drag-to-create surface, as the shared schedule panel** ([[T-3171]], the
/// seventh adoption slice, owner-reported: *"the task and event creation from the calendar view …
/// is still using the old task and event creation sheet"*).
///
/// It was the last creation surface in the app with a form of its own — 448 lines of Task/Event
/// tabs, two near-duplicate Task composers, a second copy of the `~` list flow and an
/// `enum Mode { case timeBlock, calendarEvent }` that outlived the Block feature. All of it is
/// `CadenceSchedulePanel` now, in **create** mode (`delete: nil`), exactly as
/// `CalendarEventEditPopover` hosts it in edit mode one file over.
///
/// ## What this host can actually write, and what it therefore does not offer
///
/// The popover is drawn by `TimelineDayCanvas`, whose two hosts are the Today timeline and the
/// Calendar page's day column:
///
/// - `onCreateTask` takes a `QuickCreateTaskDraft`, which both hosts write through
///   `SchedulePanelDataSupport.insertDragCreatedTask` — the draft's own day, Due and Repeat
///   included ([[T-3171]] (iii), (iv)).
/// - `onCreateEvent` takes a `QuickCreateEventDraft`, which both hosts hand
///   `CalendarManager.createStandaloneEvent(_:hostDay:)` — the draft's own day, All day, Location
///   and Repeat included ([[T-3171]] (iii)).
///
/// So every row the panel draws is offered, and every schedule it can state is written: All day and
/// an Estimate of None on a task ([[T-6581]]), and an event that ends on a later day ([[T-6582]]).
/// What remains unwritable — a task spanning days, which an `AppTask` cannot hold — is **named
/// and refused** rather than silently dropped (T-470), in `hostLimitNotice`, drawn through the
/// panel's existing `failureNotice:` with `canCommit: false`.
struct QuickCreateChoicePopover: View {
    let startMin: Int
    let endMin: Int
    /// The day the drag was drawn on. It seeds the draft; the panel's Do/Starts grid can move the
    /// draft off it, and both hosts then create on the draft's day, not this one.
    let dateKey: String
    let onCreateTask: (QuickCreateTaskDraft) -> Void
    /// The range and the day travel: the panel's Start and End rollers and its Starts day can move
    /// what the drag drew, and the canvas used to capture the drag's own `start`/`end` and create
    /// those instead.
    let onCreateEvent: ((QuickCreateEventDraft) -> Void)?
    let onCancel: () -> Void
    /// What to say when the event the user just typed was refused by Apple Calendar (T-658).
    ///
    /// Host-owned, like `CalendarEventEditPopover`'s: the host is the frame that dismisses this
    /// popover, so it is the only frame that can decide to keep the draft on screen instead. The
    /// Task arm deliberately keeps its alerts — both hosts now commit the draft themselves
    /// ([[T-3171]]'s eighth slice) and this popover has already dismissed itself by the time the
    /// store answers, so there is nothing left here to write a notice under.
    @Binding var createFailureNotice: String?

    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var draft: CadenceScheduleDraft
    @State private var notesDraft = QuickCreateNotesDraft()

    init(
        startMin: Int,
        endMin: Int,
        dateKey: String,
        onCreateTask: @escaping (QuickCreateTaskDraft) -> Void,
        onCreateEvent: ((QuickCreateEventDraft) -> Void)?,
        onCancel: @escaping () -> Void,
        createFailureNotice: Binding<String?>,
        defaultsToCalendarEvent: Bool = false
    ) {
        self.startMin = startMin
        self.endMin = endMin
        self.dateKey = dateKey
        self.onCreateTask = onCreateTask
        self.onCreateEvent = onCreateEvent
        self.onCancel = onCancel
        _createFailureNotice = createFailureNotice
        _draft = State(
            initialValue: Self.openingDraft(
                dateKey: dateKey,
                startMin: startMin,
                endMin: endMin,
                // The Event arm opens selected on a calendar page, and only where there is an
                // event host to create through.
                defaultsToCalendarEvent: defaultsToCalendarEvent && onCreateEvent != nil
            )
        )
    }

    /// The draft the drag leaves behind — static so what a dragged slot hands the panel is checked
    /// rather than inferred from the view, the way `CalendarEventEditPopover.openingDraft(for:)` is.
    ///
    /// **The drag's own length, not `CadenceScheduleDraft.quickCreateLengthMinutes`.** That half
    /// hour is the calendar *sheet*'s opening length, for a surface whose slot is a tap; this
    /// popover is opened by a range the user drew, and opening it on thirty minutes would redraw
    /// their block the instant it appeared.
    static func openingDraft(
        dateKey: String,
        startMin: Int,
        endMin: Int,
        defaultsToCalendarEvent: Bool
    ) -> CadenceScheduleDraft {
        CadenceScheduleDraft(
            dateKey: dateKey,
            startMin: startMin,
            kind: defaultsToCalendarEvent ? .event : .task,
            durationMinutes: endMin - startMin
        )
    }

    var body: some View {
        CadenceSchedulePanel(
            draft: $draft,
            listChoices: CadenceScheduleDraftChoices.listChoices(for: draft, areas: areas, projects: projects),
            sectionChoices: CadenceScheduleDraftChoices.sectionChoices(for: draft, areas: areas, projects: projects),
            calendarChoices: calendarChoices,
            calendarUnavailableNotice: calendarUnavailableNotice,
            failureNotice: createFailureNotice ?? hostLimitNotice,
            canCommit: canCommit,
            // Both writes carry every row offered here ([[T-3171]] (iii)): the task write Due and
            // Repeat, the event write Repeat, Location and All day.
            offersEventRepeat: true,
            offersTaskRepeat: true,
            offersTaskDue: true,
            offersEventLocation: true,
            offersSubtasks: true,
            actions: CadenceSchedulePanelActions(
                commit: create,
                cancel: onCancel,
                // Nothing exists yet on this path, so there is nothing to delete. The control is
                // absent rather than disabled — see `CadenceSchedulePanelActions.delete`.
                delete: nil
            )
        )
        .frame(width: CadenceSchedulePanelMetrics.preferredWidth)
        .background(Theme.surface)
        .onAppear(perform: resolveCalendarSelection)
        .onChange(of: draft.kind) { previousKind, newKind in
            carryNotes(leaving: previousKind, entering: newKind)
            resolveCalendarSelection()
        }
        // The Section row follows the List row inside the panel ([[T-8591]]); this host's own
        // copy of that rule went with [[T-8601]].
    }

    // MARK: - What the host can carry

    /// Why Add is refused, in the user's words — or `nil` when the draft is one the host can write.
    ///
    /// **Every arm is a field the panel legitimately offers and neither write closure can carry.**
    /// Refusing out loud is the rule T-470 settled: the alternative is a control that looks like it
    /// worked and a record that does not say what the user said.
    var hostLimitNotice: String? {
        Self.hostLimitNotice(for: draft)
    }

    /// Static so the rule is testable without a view — it is the whole of what this surface refuses.
    ///
    /// **No day rule** ([[T-3171]] (iv)). It used to refuse a draft whose day the panel had moved
    /// off the column's, because the Calendar page's column and both event writes supplied the
    /// host's own day. Both hosts now create on the draft's day, so a moved day is honoured.
    ///
    /// **No all-day or Repeat rule for events** ([[T-3171]] (iii)). The event write used to set
    /// `isAllDay = false` and attach no recurrence, so both were refused here; it writes both now.
    ///
    /// **No all-day or None rule for tasks** ([[T-6581]]). `SchedulingActions.insertTask` used to
    /// store the slot's minute and floor the estimate at five, so an untimed task and Estimate:
    /// None were refused here; it writes `scheduledStartMin -1` and an estimate of `0` now.
    ///
    /// **No multi-day rule for events** ([[T-6582]]). `createStandaloneEvent` took one day, so an
    /// event ending on a later day — all-day or timed — was refused; it writes the draft's range
    /// through `CadenceScheduleDraft.eventDateRange` now, as iOS does. A **task** cannot span days
    /// (an `AppTask` has one `scheduledDate`), so a task draft that somehow does is still refused.
    static func hostLimitNotice(for draft: CadenceScheduleDraft) -> String? {
        if draft.kind == .task && draft.spansMultipleDays {
            return "A dragged slot creates a task inside one day. End it on \(dayLabel(draft.startDateKey))."
        }
        return nil
    }

    private static func dayLabel(_ key: String) -> String {
        DateFormatters.shortDateString(from: key)
    }

    private var canCommit: Bool {
        guard hostLimitNotice == nil else { return false }
        guard draft.kind == .event else { return true }
        return selectedCalendar != nil
    }

    // MARK: - Creating

    /// `nil` when the draft left this popover, the sentence to draw when it did not.
    ///
    /// The **event** arm answers `nil` on a draft that reached `onCreateEvent`, including one the
    /// store then refused: the canvas is the frame that sees `CalendarWriteFailure` and the frame
    /// that decides not to dismiss, so that refusal comes back through `createFailureNotice`
    /// (T-658) rather than as a return value here.
    private func create() -> String? {
        if let hostLimitNotice { return hostLimitNotice }
        switch draft.kind {
        case .task:
            onCreateTask(QuickCreateTaskDraft(scheduleDraft: draft))
            return nil
        case .event:
            // Reachable only on a canvas given no event host at all, which neither shipping host
            // is. Spelled as a refusal rather than a silent `return nil`, so the Event arm can
            // never look like it created something on a timeline that cannot.
            guard let onCreateEvent else { return "This timeline creates tasks only." }
            onCreateEvent(QuickCreateEventDraft(scheduleDraft: draft))
            return nil
        }
    }

    // MARK: - Notes, per kind

    private func carryNotes(leaving previousKind: CadenceScheduleDraftKind, entering newKind: CadenceScheduleDraftKind) {
        notesDraft.set(draft.notes, for: previousKind)
        draft.notes = notesDraft.notes(for: newKind)
    }

    // MARK: - Calendars

    private var selectedCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
    }

    private var calendarChoices: [CadenceSchedulePanelChoice] {
        let _ = calendarManager.storeVersion
        return calendarManager.writableCalendars.map {
            CadenceSchedulePanelChoice(
                id: $0.calendarIdentifier,
                name: $0.title,
                // `cgColor` is implicitly unwrapped and nil on a calendar EventKit has not coloured
                // yet; read as the dim row rather than trapping (T-2047's shape).
                color: $0.cgColor.map { Color(cgColor: $0) } ?? Theme.dim,
                systemImage: "calendar"
            )
        }
    }

    /// Said instead of the picker when there is nothing to pick.
    ///
    /// **It never offers to request access.** A popover hanging off a timeline is not the place to
    /// raise a system permission prompt, so it names what is missing and leaves the request to the
    /// surface that owns it — the same ruling `iOSTimelineDraftPanelHost` records.
    private var calendarUnavailableNotice: String? {
        guard draft.kind == .event else { return nil }
        if !calendarManager.isAuthorized {
            return "Calendar access is needed to create events. Turn it on in Settings, then try again."
        }
        if calendarManager.writableCalendars.isEmpty {
            return "No writable calendars are available."
        }
        return nil
    }

    private func resolveCalendarSelection() {
        guard draft.kind == .event, selectedCalendar == nil else { return }
        draft.calendarID = calendarManager.defaultWritableCalendar?.calendarIdentifier
            ?? calendarManager.writableCalendars.first?.calendarIdentifier
            ?? ""
    }
}
#endif
