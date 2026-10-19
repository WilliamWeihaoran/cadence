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
/// adoption slice). The form is `CadenceSchedulePanel` now; this is what survives the handoff into
/// `SchedulingActions.insertTask` on the Calendar page and into `TaskCreationManager.present` on
/// the Today timeline. Both call sites are fixed — one of them is in a Codex-leased file — so a
/// field the panel offers that has no member here has nowhere to go, and the popover refuses such
/// a draft out loud rather than dropping it (T-470). See `QuickCreateChoicePopover.hostLimitNotice`.
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
    /// **Always empty from the drag-create popover** ([[T-3171]]'s seventh slice), and deliberately
    /// kept rather than removed: `CadenceScheduleDraft` has no subtasks, so adopting the shared
    /// panel dropped the old Task tab's subtask composer, and the Calendar page's leased host still
    /// declares a `subtaskTitles:` argument this value has to fill. Nothing else writes it — the
    /// composer a drag-created task's subtasks were typed into is gone, and the full create sheet
    /// the Today timeline hands off to has its own. Retiring the member means editing
    /// `CalendarPageMonthSupportViews.swift`, which is on the Codex lease.
    var subtaskTitles: [String]
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
/// Calendar page's day column — and the day column is **Codex-leased**, so the shapes of both write
/// closures are fixed:
///
/// - `onCreateTask` is a `QuickCreateTaskDraft`, which has no due date, no recurrence and no
///   estimate of its own; the Calendar page's column also supplies **its own day** and ignores the
///   draft's.
/// - `onCreateEvent` reaches `CalendarManager.createStandaloneEvent`, which takes a day from the
///   host, writes `isAllDay = false`, and has no `location:` and no recurrence.
///
/// So the Due, Repeat and Location rows are **withheld** (`offersTaskDue`, `offersTaskRepeat`,
/// `offersEventRepeat`, `offersEventLocation`), and the schedule facts the user can still reach
/// from the rows that remain — another day, a span across midnight, all-day, an estimate of None —
/// are **named and refused** rather than silently dropped (T-470). Each is one sentence in
/// `hostLimitNotice`, drawn through the panel's existing `failureNotice:` with `canCommit: false`,
/// so this slice adds no shape to the panel's contract beyond the two `offers*` flags above.
///
/// The real fix for the day is that both hosts take one; it is recorded as REMAINING on
/// [[T-3171]].
struct QuickCreateChoicePopover: View {
    let startMin: Int
    let endMin: Int
    /// The day the **host** creates on. The panel's own Do/Starts grid can move the draft off it;
    /// `hostLimitNotice` is what stops that becoming a silent write to the wrong day.
    let dateKey: String
    let onCreateTask: (QuickCreateTaskDraft) -> Void
    /// `(title, startMin, endMin, calendarID, notes)`. The minutes travel now: the panel's Start
    /// and End rollers can move the range the drag drew, and the canvas used to capture the drag's
    /// own `start`/`end` and create those instead.
    let onCreateEvent: ((String, Int, Int, String, String) -> Void)?
    let onCancel: () -> Void
    /// What to say when the event the user just typed was refused by Apple Calendar (T-658).
    ///
    /// Host-owned, like `CalendarEventEditPopover`'s: the host is the frame that dismisses this
    /// popover, so it is the only frame that can decide to keep the draft on screen instead. The
    /// Task arm deliberately keeps its alerts — its hosts hand the draft to a separate panel or
    /// sheet, so by the time the store answers there is nothing left here.
    @Binding var createFailureNotice: String?
    /// Whether the host hands the draft on to the task panel (the Today timeline) or creates in
    /// place (the Calendar page's day column). **Kept** although both arms now draw one form:
    /// `CalendarPageMonthSupportViews.swift` passes `false` and is Codex-leased, and it is also the
    /// one fact that says whether the host honours the draft's own **day** — the panel-handoff host
    /// forwards `draft.dateKey` to `TaskCreationManager.present`, the day column overwrites it with
    /// its column's.
    let usesTaskPanelForTaskCreation: Bool

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
        onCreateEvent: ((String, Int, Int, String, String) -> Void)?,
        onCancel: @escaping () -> Void,
        createFailureNotice: Binding<String?>,
        usesTaskPanelForTaskCreation: Bool = true,
        defaultsToCalendarEvent: Bool = false
    ) {
        self.startMin = startMin
        self.endMin = endMin
        self.dateKey = dateKey
        self.onCreateTask = onCreateTask
        self.onCreateEvent = onCreateEvent
        self.onCancel = onCancel
        _createFailureNotice = createFailureNotice
        self.usesTaskPanelForTaskCreation = usesTaskPanelForTaskCreation
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
            // Neither write closure carries a recurrence, a due date or a location. See the type
            // note: withheld, not drawn-and-dropped.
            offersEventRepeat: false,
            offersTaskRepeat: false,
            offersTaskDue: false,
            offersEventLocation: false,
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
        .onChange(of: draft.listToken) { _, _ in
            draft.sectionName = CadenceScheduleDraftChoices.normalizedSectionName(
                for: draft,
                areas: areas,
                projects: projects
            )
        }
    }

    // MARK: - What the host can carry

    /// Why Add is refused, in the user's words — or `nil` when the draft is one the host can write.
    ///
    /// **Every arm is a field the panel legitimately offers and neither write closure can carry.**
    /// Refusing out loud is the rule T-470 settled: the alternative is a control that looks like it
    /// worked and a record that does not say what the user said.
    var hostLimitNotice: String? {
        Self.hostLimitNotice(
            for: draft,
            hostDateKey: dateKey,
            hostWritesDraftDay: hostWritesDraftDay
        )
    }

    /// Whether the host stores the day the panel's grid names, or supplies its own.
    ///
    /// Only the Today timeline's task handoff does: it forwards `draft.dateKey` into
    /// `TaskCreationManager.present`. The Calendar page's day column overwrites it with its own
    /// column's, and **both** hosts give `createStandaloneEvent` their own date, so no event
    /// created here can name another day.
    private var hostWritesDraftDay: Bool {
        draft.kind == .task && usesTaskPanelForTaskCreation
    }

    /// Static so the rule is testable without a view — it is the whole of what this surface refuses.
    static func hostLimitNotice(
        for draft: CadenceScheduleDraft,
        hostDateKey: String,
        hostWritesDraftDay: Bool
    ) -> String? {
        let kindWord = draft.kind == .event ? "event" : "task"
        if draft.isAllDay {
            return draft.kind == .event
                ? "A dragged slot creates a timed event. Turn All day off to create it here."
                : "A dragged slot creates a task at a time. Add a time to create it here."
        }
        if draft.spansMultipleDays {
            return "A dragged slot creates an \(kindWord) inside one day. End it on \(dayLabel(draft.startDateKey))."
        }
        if !hostWritesDraftDay && draft.startDateKey != hostDateKey {
            return "A slot dragged on \(dayLabel(hostDateKey)) creates on that day. Drag a slot on \(dayLabel(draft.startDateKey)) to create there."
        }
        if draft.kind == .task && draft.estimateMinutes <= 0 {
            return "A dragged slot gives the task its length, so Estimate cannot be None here."
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
            onCreateTask(
                QuickCreateTaskDraft(
                    title: draft.title,
                    dateKey: draft.startDateKey,
                    startMin: draft.startMin,
                    endMin: draft.endMin,
                    container: CadenceScheduleDraftChoices.container(for: draft),
                    sectionName: draft.sectionName,
                    priority: draft.priority,
                    notes: draft.notes,
                    subtaskTitles: []
                )
            )
            return nil
        case .event:
            // Reachable only on a canvas given no event host at all, which neither shipping host
            // is. Spelled as a refusal rather than a silent `return nil`, so the Event arm can
            // never look like it created something on a timeline that cannot.
            guard let onCreateEvent else { return "This timeline creates tasks only." }
            onCreateEvent(draft.title, draft.startMin, draft.endMin, draft.calendarID, draft.notes)
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
