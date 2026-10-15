#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Creates a task or an event from the calendar through **the one shared schedule panel**
/// ([[T-3171]]'s third adoption slice).
///
/// The form is `CadenceSchedulePanel` in create mode — the same view the iPad timeline creates
/// with and the event and task editors edit with — and the writes are `iOSScheduleDraftCreation`'s,
/// shared with that timeline. What stays here is only what is this sheet's own: the header naming
/// the day it was opened on, the **Allow Calendar Access** request (the panel deliberately never
/// raises a system prompt; a full sheet has room to, so the request sits in the host's slot,
/// directly under the panel's calendar notice), the platform's markdown well for the notes —
/// image insertion on for a task and off for an event, T-422 — and its reference sheets.
///
/// **Each kind keeps its own time choice across a switch**, as the sheet's separate "Set time" and
/// "All day" toggles always did: an untimed task switched to Event opens as a timed event rather
/// than an all-day one, and switching back finds the task untimed again. See `isTimed(_:)`.
struct iOSCalendarQuickCreateSheet: View {
    let dateKey: String
    let initialStartMinute: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var draft: CadenceScheduleDraft
    /// The task's time choice while the draft is an event, and the event's while it is a task.
    /// The draft carries one `isAllDay` for whichever kind is showing; these remember the other.
    @State private var hasTime: Bool
    @State private var eventIsAllDay = false
    @State private var notesEditorFocused = false
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

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
        _hasTime = State(initialValue: opensTimed)
    }

    /// Both kinds agree that a thing being created needs a name (T-567), and an event needs a
    /// calendar it can be written to. The Block arm that used to sit between them is gone with the
    /// Block feature itself ([[T-3170]]). Handed to the panel as `canCommit`, so Add greys out
    /// exactly as the sheet's arrow button did.
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

    /// Whether `kind`, when the switch lands on it, is timed — read from that kind's own remembered
    /// choice rather than from the kind being left.
    private func isTimed(_ kind: CadenceScheduleDraftKind) -> Bool {
        switch kind {
        case .task: return hasTime
        case .event: return !eventIsAllDay
        }
    }

    private func rememberTimeChoice(of kind: CadenceScheduleDraftKind) {
        switch kind {
        case .task: hasTime = !draft.isAllDay
        case .event: eventIsAllDay = draft.isAllDay
        }
    }

    /// Read for the sheet's gutter only — a fact about the host. Nothing the panel draws consults it.
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                    header

                    CadenceSchedulePanel(
                        draft: $draft,
                        listChoices: iOSScheduleDraftCreation.listChoices(for: draft, areas: areas, projects: projects),
                        sectionChoices: iOSScheduleDraftCreation.sectionChoices(for: draft, areas: areas, projects: projects),
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
                        notesSection
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                }
                // One column now, so the widest column the old two-column form allowed is the cap —
                // the event editor's figure, which this sheet shares.
                .frame(maxWidth: iOSEditorSheetMetrics.secondaryColumnMaxWidth)
                .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: draft.listToken) { _, _ in normalizeSection() }
            .onChange(of: draft.kind) { oldKind, newKind in
                rememberTimeChoice(of: oldKind)
                draft.isAllDay = !isTimed(newKind)
                normalizeCalendarSelection()
            }
            .onAppear {
                normalizeCalendarSelection()
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    /// The day the thing will land on, and — when the sheet was opened on a slot — the time. The
    /// Cancel, Create and priority controls that used to sit at its trailing edge are the panel's
    /// Cancel and Add and its priority marks now.
    private var header: some View {
        HStack(spacing: 12) {
            iOSIconTile(systemImage: "calendar.badge.plus", color: Theme.blue, size: 42, iconSize: 19)

            VStack(alignment: .leading, spacing: 3) {
                // The draft's day, not the one the sheet opened on: the panel's Do and Starts rows
                // can move it, and a header naming the old day would contradict them.
                Text(DateFormatters.relativeDate(from: draft.startDateKey.isEmpty ? dateKey : draft.startDateKey))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.text)
                if let headerSubtitle {
                    Text(headerSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Only the slot the sheet was opened on, and only while the draft is still timed.
    private var headerSubtitle: String? {
        guard initialStartMinute != nil, !draft.isAllDay else { return nil }
        return "Create around \(CadenceScheduleSupport.timeRangeLabel(startMinute: draft.startMin, endMinute: draft.endMin))."
    }

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
    /// row names what is missing; this sheet is a full surface opened on purpose, with room to ask,
    /// so it offers the system prompt here — first in the host's slot, which the panel draws
    /// directly under that calendar row.
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

    private var notesSection: some View {
        iOSEditorSection(title: "Notes", style: .ruled) {
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.kind == .event ? "Apple Calendar note" : "Task note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.subdued)

                iOSMarkdownEditingSurface(
                    text: $draft.notes,
                    isFocused: $notesEditorFocused,
                    placeholder: "Add markdown notes...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    allowsEmbeddedTaskCreation: false,
                    // **T-422, and not the flat `false` its sibling sheet takes.** This one draft
                    // note has two destinations: `calendarManager.createEvent(notes:)` in event
                    // mode, which is `EKEvent.notes` and outside the store, and `task.notes` in
                    // `iOSScheduleDraftCreation.createTask` otherwise — and `AppTask.notes` *is* in
                    // the inventory, because widening the scan to reach it was the whole of
                    // [[T-411]]. Refusing images in both modes would take a working capability off
                    // task capture to fix a hazard task capture does not have.
                    allowsImageInsertion: draft.kind != .event
                )
                .iOSMarkdownWell()
            }
        }
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
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
        draft.sectionName = iOSScheduleDraftCreation.normalizedSectionName(for: draft, areas: areas, projects: projects)
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
