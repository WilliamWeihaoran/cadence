#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Creates a task or an event from the calendar through **the one shared schedule panel, in the
/// one capture presentation** ([[T-3171]]'s seventh adoption slice).
///
/// The form has been `CadenceSchedulePanel` in create mode since the third slice. What was still
/// different was the **chrome**: the `+` palette reached `iOSCreateTaskSheet`, which applies
/// `.capturePresentation(…)` and opens the floating card, while a dragged calendar slot reached
/// this sheet, which wrapped the same panel in a full `NavigationStack` sheet with a day header and
/// a markdown well. Same fields, two surfaces — and the owner read the second as "the old creation
/// sheet", correctly: nothing on screen said they were the same thing. So this file now applies the
/// same `.capturePresentation(…)` and the same detent-sized, clear-backed presentation, and the two
/// entry points are one surface that differs only in what it opens seeded with.
///
/// What stays here is only what is this sheet's own: the writable-calendar gate the draft cannot
/// see, and the **Allow Calendar Access** request (the panel deliberately never raises a system
/// prompt, so the request sits in the host's slot, drawn above the card's notes).
///
/// **Each kind keeps its own time choice across a switch** — an untimed task switched to Event
/// opens as a timed event, and switching back finds the task untimed again. That is no longer this
/// sheet's own pair of flags: `CadenceCaptureKindMemory`, inside the card, remembers each kind's
/// whole draft and is what every capture host already gets.
///
/// **Retired with the full-sheet chrome** (deliberate, not lost in the move): the day header and
/// its "Create around …" subtitle, which the card states as the Do chip; and the platform's
/// markdown well with its reference sheets and T-422's per-kind image rule, which the capture card
/// has never carried on the `+` path either. Both are the cost of the two entry points being one
/// surface; the Notes field the card draws writes the same `draft.notes` either way.
struct iOSCalendarQuickCreateSheet: View {
    let dateKey: String
    let initialStartMinute: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var draft: CadenceScheduleDraft
    /// The card sizes the sheet, as it does on the `+` path: a capture surface is as tall as what
    /// it is showing, not as tall as a sheet.
    @State private var cardHeight: CGFloat = 260
    /// [[T-5174]] (b): the draft as `onAppear`'s calendar normalisation left it, against which a
    /// swipe-down is refused. `nil` until then, so that normalisation is never read as typing.
    @State private var openedDraft: CadenceScheduleDraft?

    /// `initialKind` is what the capture palette's **Event** segment needs: the kind switch is
    /// still there and still switches, but a palette that says "Event" and opens on Task would be
    /// the choice being taken twice. Defaults to `.task`, which is what every other caller — a
    /// tapped empty slot on the calendar — means.
    init(dateKey: String, initialStartMinute: Int? = nil, initialKind: CadenceScheduleDraftKind = .task) {
        self.dateKey = dateKey
        self.initialStartMinute = initialStartMinute
        let opensTimed = initialStartMinute != nil
        _draft = State(initialValue: .quickCreate(
            dateKey: dateKey,
            startMin: Self.defaultStartMinute(dateKey: dateKey, startMinute: initialStartMinute),
            opensTimed: opensTimed,
            kind: initialKind
        ))
    }

    /// Both kinds agree that a thing being created needs a name (T-567), and an event needs a
    /// calendar it can be written to. The Block arm that used to sit between them is gone with the
    /// Block feature itself ([[T-3170]]). Handed to the panel as `canCommit`, so the card's create
    /// arrow greys out exactly as the sheet's Add did.
    private var canCreate: Bool {
        let title = draft.title
        switch draft.kind {
        case .task:
            return !TaskTitleSupport.isEmpty(title)
        case .event:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedWritableCalendar != nil
        }
    }

    private var selectedWritableCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
    }

    var body: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: CadenceScheduleDraftChoices.listChoices(for: draft, areas: areas, projects: projects),
                sectionChoices: CadenceScheduleDraftChoices.sectionChoices(for: draft, areas: areas, projects: projects),
                calendarChoices: iOSScheduleDraftCreation.calendarChoices(calendarManager),
                calendarUnavailableNotice: calendarUnavailableNotice,
                canCommit: canCreate,
                actions: CadenceSchedulePanelActions(
                    commit: create,
                    cancel: { dismiss() },
                    // Nothing exists yet, so there is nothing to delete: absent, not disabled.
                    delete: nil
                )
            ) {
                calendarAccessRequest
            }
            .capturePresentation(CadenceScheduleCaptureOptions())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 + 24 }
            .frame(maxWidth: 540)
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .cadenceScaledTypography()
        .scrollDismissesKeyboard(.never)
        .scrollIndicators(.hidden)
        // The sheet declares its scope independently of the capture card.
        // The control-host inventory records this independent scope.
        .tint(Theme.blue)
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(cardHeight)])
        // [[T-5174]] (b), the owner's "one rule for every sheet": a swipe-down cannot discard a
        // half-typed new task or event. Presented by `.sheet(item:)` from `iOSCalendarView` and
        // never by `.popover` — [[T-3240]] measured this modifier pushing an iPad popover
        // presentation out of its popover and clipping it, and a test pins every presenter.
        .interactiveDismissDisabled(
            CadenceSheetDismissGuard.blocksSwipe(opened: openedDraft, current: currentDraft)
        )
        .onChange(of: draft.listToken) { _, _ in normalizeSection() }
        .onChange(of: draft.kind) { _, _ in normalizeCalendarSelection() }
        .onChange(of: calendarManager.writableCalendars.map(\.calendarIdentifier)) { _, _ in normalizeCalendarSelection() }
        .onAppear {
            normalizeCalendarSelection()
            // [[T-5174]] (b). After the normalisation, which picks a writable calendar before the
            // user has touched anything; once, because this fires again on a return from a picker.
            if openedDraft == nil { openedDraft = currentDraft }
        }
    }

    /// [[T-5174]] (b): what the sheet holds right now. The draft is the whole of it here — this
    /// sheet has no tag selection of its own, unlike the `+` path's.
    private var currentDraft: CadenceScheduleDraft { draft }

    /// What the panel's calendar row says when there is no calendar to pick. Access missing is
    /// answered by `calendarAccessRequest` directly below it.
    private var calendarUnavailableNotice: String? {
        if !calendarManager.isAuthorized {
            return "Calendar access is needed to create events."
        }
        if calendarManager.writableCalendars.isEmpty {
            return "No writable calendars are available."
        }
        return nil
    }

    /// **The request the panel will not make, kept in the host** ([[T-3171]]). The panel's calendar
    /// row names what is missing; this sheet is a surface opened on purpose, with room to ask, so
    /// it offers the system prompt from the host's own slot.
    @ViewBuilder
    private var calendarAccessRequest: some View {
        if draft.kind == .event && !calendarManager.isAuthorized {
            iOSActionButton(
                title: "Allow Calendar Access",
                systemImage: "calendar.badge.plus",
                role: .primary,
                size: .compact
            ) {
                Task {
                    _ = await calendarManager.requestAccess()
                    normalizeCalendarSelection()
                }
            }
        }
    }

    /// Every exit that is not a created record says why, through the panel (T-470, T-324): the
    /// shared writes return the sentence, and only a `nil` — the write landed — dismisses.
    private func create() -> String? {
        let failure: String?
        switch draft.kind {
        case .task:
            failure = iOSScheduleDraftCreation.createTask(
                from: draft,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
        case .event:
            failure = iOSScheduleDraftCreation.createEvent(from: draft, calendarManager: calendarManager)
        }
        if failure == nil { dismiss() }
        return failure
    }

    private func normalizeSection() {
        draft.sectionName = CadenceScheduleDraftChoices.normalizedSectionName(for: draft, areas: areas, projects: projects)
    }

    private func normalizeCalendarSelection() {
        iOSScheduleDraftCreation.resolveCalendarSelection(&draft, calendarManager: calendarManager)
    }

    /// The minute the draft opens at: the tapped slot, or the next whole hour inside the drawn day.
    /// Through the shared gap rule, so a slot inside the spring-forward gap opens at 03:00 (T-3119).
    private static func defaultStartMinute(dateKey: String, startMinute: Int?) -> Int {
        let baseDate = DateFormatters.date(from: dateKey) ?? Date()
        let minute: Int
        if let startMinute {
            minute = startMinute
        } else {
            let hour = Calendar.current.component(.hour, from: Date())
            minute = min(max(hour + 1, CadenceScheduleSupport.calendarStartHour), CadenceScheduleSupport.calendarEndHour - 1) * 60
        }
        guard let start = CadenceCalendarEventTiming.settingStartMinute(minute, of: baseDate) else { return minute }
        return CadenceCalendarEventTiming.minuteOfDay(of: start)
    }
}

#endif
