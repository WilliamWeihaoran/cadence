#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

/// Everything the quick-create popover's Task tab decides, in one value.
///
/// **T-1433.** It used to hand back five loose arguments and let the canvas supply the slot from
/// the ghost it had drawn, because the popover's date and time were `Text`. They are fields now —
/// the owner asked for editable date and time at the top of the inspector — so the slot the user
/// confirms is the popover's, not the drag's, and a sixth, seventh and eighth positional argument
/// on a closure three hosts pass through is how call sites start transposing them.
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
    var subtaskTitles: [String]

    /// Moving the start moves the whole slot: the end follows by the duration the drag drew,
    /// rather than the block growing or shrinking behind a control that never named a duration.
    ///
    /// Clamped to the end of the day, because the time field offers every quarter hour up to
    /// 23:45 and the drag it is seeded from cannot reach past midnight. Floored at five minutes
    /// for the same reason `SchedulePanel` floors the estimate it derives from this.
    static func endMinute(forStart start: Int, holdingDuration duration: Int) -> Int {
        min(24 * 60, start + max(5, duration))
    }
}

/// The prose each tab of the quick-create popover composes, kept apart.
///
/// **[[T-1610]].** There was one `@State private var notes` and both composers were handed it, so
/// a note typed on the **Event** tab rode into whatever the **Task** tab created next. That is not
/// a carry like `title`'s — the two fields are not the same field. The Event tab's prose is
/// `EKEvent.notes` and leaves the store entirely; the Task tab's is `AppTask.notes`. And the carry
/// was invisible on the path that matters most: of the **two** Task spellings this popover draws,
/// `QuickCreateTaskSlotInspectorView` (the `usesTaskPanelForTaskCreation` one, which the schedule
/// panel takes) has no Notes row at all — so `SchedulePanel` forwarded `draft.notes` to
/// `TaskCreationManager.present` and the create sheet opened pre-filled with a paragraph about an
/// event the user had abandoned, with nothing on screen that had ever shown it.
///
/// **Two slots and not a clear-on-switch**, which is the same decision made without the loss: a
/// user who flips Task → Event → Task finds the task's own notes where they left them, and the
/// Event tab's where *they* were left. `title` keeps its single slot, because a title is the one
/// thing all three tabs genuinely share — `selectMode` swapping `TaskBundle.defaultDisplayTitle`
/// in and out is that sharing being managed, and it is what made this field's silence conspicuous.
struct QuickCreateNotesDraft: Equatable {
    /// The Task tab's. On the panel-handoff path this stays empty by construction: that spelling
    /// draws no Notes row, so nothing can write it, and the create sheet opens clean.
    var task = ""
    /// The Event tab's — Apple Calendar's note, not a task's.
    var event = ""

    /// What `create()` hands the host for `mode`. The Bundle tab composes no prose at all, and
    /// answers the empty string rather than whichever neighbour's happens to be non-empty.
    func notes(for mode: QuickCreateChoicePopover.Mode) -> String {
        switch mode {
        case .timeBlock: return task
        case .calendarEvent: return event
        case .bundle: return ""
        }
    }
}

struct QuickCreateChoicePopover: View {
    enum Mode { case timeBlock, calendarEvent, bundle }

    let startMin: Int
    let endMin: Int
    let dateKey: String
    let onCreateTask: (QuickCreateTaskDraft) -> Void
    let onCreateBundle: ((String, [AppTask]) -> Void)?
    let onCreateEvent: ((String, String, String) -> Void)?
    let onCancel: () -> Void
    /// What to say when the event the user just typed was refused by Apple Calendar (T-658).
    ///
    /// Host-owned, like `CalendarEventEditPopover`'s: the host is the frame that dismisses this
    /// popover, so it is the only frame that can decide to keep the draft on screen instead. The
    /// Task and Bundle tabs deliberately keep their alerts — their hosts hand the draft to a
    /// separate panel or sheet, so by the time the store answers there is nothing left here.
    @Binding var createFailureNotice: String?
    let usesTaskPanelForTaskCreation: Bool

    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.createdAt, order: .reverse) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var mode: Mode
    @State private var title = ""
    @State private var selectedCalendarID = ""
    @State private var notesDraft = QuickCreateNotesDraft()
    @State private var subtaskDraft = ""
    @State private var subtaskTitles: [String] = []
    @State private var selectedContainer: TaskContainerSelection = .inbox
    @State private var selectedPriority: TaskPriority = .none
    /// The Task tab's own slot, seeded from the drag and editable from T-1433's inspector. The
    /// Event and Block tabs still create the range the ghost drew: their hosts take the slot as
    /// arguments the popover never sees.
    @State private var draftDateKey: String
    @State private var draftStartMin: Int
    @State private var selectedSectionName: String = TaskSectionDefaults.defaultName
    @State private var tildeMode: Bool = false
    @State private var tildeSearchQuery = ""
    @State private var bundleTaskSearch = ""
    @State private var selectedBundleTaskIDs: [UUID] = []
    @FocusState private var focused: Bool

    /// The length of the slot the drag drew, which the Task tab's start-time field moves rather
    /// than resizes.
    private var slotDurationMinutes: Int {
        endMin - startMin
    }

    private var draftEndMin: Int {
        QuickCreateTaskDraft.endMinute(forStart: draftStartMin, holdingDuration: slotDurationMinutes)
    }

    /// One height for the Task tab now that both spellings of it compose rather than one of them
    /// pointing elsewhere.
    private var modeFormMinHeight: CGFloat {
        switch mode {
        case .timeBlock:
            return 246
        case .calendarEvent:
            return 232
        case .bundle:
            return 300
        }
    }

    private var popoverWidth: CGFloat {
        mode == .bundle ? 404 : 392
    }

    init(
        startMin: Int,
        endMin: Int,
        dateKey: String,
        onCreateTask: @escaping (QuickCreateTaskDraft) -> Void,
        onCreateBundle: ((String, [AppTask]) -> Void)? = nil,
        onCreateEvent: ((String, String, String) -> Void)?,
        onCancel: @escaping () -> Void,
        createFailureNotice: Binding<String?>,
        usesTaskPanelForTaskCreation: Bool = true,
        defaultsToCalendarEvent: Bool = false
    ) {
        self.startMin = startMin
        self.endMin = endMin
        self.dateKey = dateKey
        self.onCreateTask = onCreateTask
        self.onCreateBundle = onCreateBundle
        self.onCreateEvent = onCreateEvent
        self.onCancel = onCancel
        _createFailureNotice = createFailureNotice
        self.usesTaskPanelForTaskCreation = usesTaskPanelForTaskCreation
        _draftDateKey = State(initialValue: dateKey)
        _draftStartMin = State(initialValue: startMin)
        let initialMode: Mode = defaultsToCalendarEvent && onCreateEvent != nil ? .calendarEvent : .timeBlock
        _mode = State(initialValue: initialMode)
    }

    /// **T-1433 deduped the time display.** This opened with a bare
    /// `TimeFormatters.timeRange` above the Task/Event/Block control while every tab below it
    /// drew the same range again — the handoff card's `clock` row, and `QuickCreateSlotSummary`
    /// on the other two. The owner's instruction was to move the date and time to the top of the
    /// inspector, and moving them under a header that already said one of them would have left
    /// two time displays rather than one. The header's copy is the one that went: the tab owns
    /// the slot, and on the Task tab it is now editable.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            modeSelector

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .leading) {
                    TextField(titlePlaceholder, text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .focused($focused)
                        .onSubmit { create() }
                        .onChange(of: title) { _, newValue in
                            guard mode == .timeBlock, !tildeMode, newValue.hasSuffix("~") else { return }
                            let prefix = String(newValue.dropLast())
                            if prefix.isEmpty || prefix.hasSuffix(" ") {
                                title = prefix
                                tildeSearchQuery = ""
                                tildeMode = true
                            }
                        }
                        .opacity(tildeMode ? 0 : 1)
                        .allowsHitTesting(!tildeMode)

                    if tildeMode {
                        HStack(spacing: 4) {
                            if !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .fixedSize()
                            }
                            Text("~")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.onColor(for: Theme.blue))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Spacer(minLength: 0)
                        }
                    }
                }

                if tildeMode {
                    tildeInlineSearchView
                }

                if mode == .timeBlock && usesTaskPanelForTaskCreation {
                    QuickCreateTaskSlotInspectorView(
                        dateKey: $draftDateKey,
                        startMin: $draftStartMin,
                        selectedContainer: $selectedContainer,
                        selectedSectionName: $selectedSectionName,
                        priority: $selectedPriority,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        availableSections: availableSections,
                        onContainerChanged: normalizeSelectedSection
                    )
                } else if mode == .timeBlock {
                    QuickCreateTaskDetailsView(
                        dateKey: dateKey,
                        startMin: startMin,
                        endMin: endMin,
                        selectedContainer: $selectedContainer,
                        selectedSectionName: $selectedSectionName,
                        priority: $selectedPriority,
                        notes: $notesDraft.task,
                        subtaskDraft: $subtaskDraft,
                        subtaskTitles: $subtaskTitles,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        availableSections: availableSections,
                        onContainerChanged: normalizeSelectedSection
                    )
                } else if mode == .calendarEvent {
                    let _ = calendarManager.storeVersion
                    QuickCreateEventDetailsView(
                        dateKey: dateKey,
                        startMin: startMin,
                        endMin: endMin,
                        calendars: calendarManager.writableCalendars,
                        selectedCalendarID: $selectedCalendarID,
                        notes: $notesDraft.event
                    )
                } else if mode == .bundle {
                    QuickCreateBundleDetailsView(
                        dateKey: dateKey,
                        startMin: startMin,
                        endMin: endMin,
                        bundleDateKey: dateKey,
                        allTasks: allTasks,
                        areas: areas,
                        projects: projects,
                        searchText: $bundleTaskSearch,
                        selectedTaskIDs: $selectedBundleTaskIDs
                    )
                }
            }
            .frame(minHeight: modeFormMinHeight, alignment: .topLeading)

            if mode == .calendarEvent, let createFailureNotice {
                CadenceInlineFailureNotice(text: createFailureNotice)
            }

            HStack(spacing: 8) {
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    onCancel()
                }
                Spacer()
                CadenceActionButton(
                    title: primaryActionTitle,
                    role: .secondary,
                    size: .compact,
                    tint: mode == .bundle ? Theme.amber : Theme.blue,
                    isDisabled: mode == .calendarEvent && selectedCalendar == nil
                ) {
                    create()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: popoverWidth)
        .background(Theme.surface)
        .onAppear {
            focused = true
            normalizeSelectedSection()
            if selectedCalendar == nil,
               let calendar = calendarManager.defaultWritableCalendar {
                selectedCalendarID = calendar.calendarIdentifier
            }
        }
    }

    private func create() {
        if mode == .timeBlock {
            let pendingSubtask = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedSubtasks = pendingSubtask.isEmpty ? subtaskTitles : subtaskTitles + [pendingSubtask]
            onCreateTask(
                QuickCreateTaskDraft(
                    title: title,
                    dateKey: draftDateKey,
                    startMin: draftStartMin,
                    endMin: draftEndMin,
                    container: selectedContainer,
                    sectionName: selectedSectionName,
                    priority: selectedPriority,
                    notes: notesDraft.notes(for: .timeBlock),
                    subtaskTitles: resolvedSubtasks
                )
            )
        } else if mode == .bundle {
            onCreateBundle?(
                TaskBundle.storedTitle(title),
                selectedBundleTasks
            )
        } else {
            onCreateEvent?(
                title,
                selectedCalendar?.calendarIdentifier ?? selectedCalendarID,
                notesDraft.notes(for: .calendarEvent)
            )
        }
    }

    private var titlePlaceholder: String {
        switch mode {
        case .timeBlock: return usesTaskPanelForTaskCreation ? "Task title, then continue" : "Task title"
        case .bundle: return TaskBundle.titleFieldPlaceholder
        case .calendarEvent: return "Event title"
        }
    }

    private var primaryActionTitle: String {
        mode == .timeBlock && usesTaskPanelForTaskCreation ? "Open Task Panel" : "Create"
    }

    private var selectedCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == selectedCalendarID }
            ?? calendarManager.defaultWritableCalendar
    }

    private var selectedBundleTasks: [AppTask] {
        selectedBundleTaskIDs.compactMap { id in
            allTasks.first { $0.id == id }
        }
    }

    private var containerResolver: TaskContainerResolver {
        TaskContainerResolver(areas: areas, projects: projects)
    }

    private var availableSections: [String] {
        containerResolver.availableSections(for: selectedContainer)
    }

    private func normalizeSelectedSection() {
        selectedSectionName = containerResolver.normalizedSectionName(
            selectedSectionName,
            for: selectedContainer
        )
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        TildeContainerPickerSupport.applySelection(
            tag,
            container: $selectedContainer,
            sectionName: $selectedSectionName,
            areas: areas,
            projects: projects
        )
        tildeSearchQuery = ""
        tildeMode = false
        DispatchQueue.main.async { focused = true }
    }

    /// Puts the `~` and everything typed after it back in the title, the way the title field's
    /// panel has always done. This copy of the panel had no way out at all before T-287: Escape
    /// fell through to the enclosing popover and discarded the draft, and backspace on an empty
    /// query did nothing.
    private func restoreLiteralTildeShortcut() {
        title += "~\(tildeSearchQuery)"
        tildeSearchQuery = ""
        tildeMode = false
        DispatchQueue.main.async { focused = true }
    }

    /// The `~` panel, from `TildeContainerPicker` (T-287) — the same one `TaskTitleEntryField`
    /// shows. This file used to carry a second copy of it under the same five names.
    private var tildeListSearchView: some View {
        TildeContainerPicker(
            query: $tildeSearchQuery,
            items: TildeContainerPickerSupport.flatContainers(
                query: tildeSearchQuery,
                contexts: contexts,
                areas: areas,
                projects: projects,
                selection: selectedContainer
            ),
            selection: selectedContainer,
            onSelect: selectTildeContainerItem,
            onRestoreLiteral: restoreLiteralTildeShortcut
        )
    }

    @ViewBuilder
    private var tildeInlineSearchView: some View {
        tildeListSearchView
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var modeSelector: some View {
        if onCreateEvent != nil || onCreateBundle != nil {
            HStack(spacing: 6) {
                modeButton("Task", for: .timeBlock, tint: Theme.blue)
                if onCreateEvent != nil {
                    modeButton("Event", for: .calendarEvent, tint: Theme.purple)
                }
                if onCreateBundle != nil {
                    modeButton(TaskBundle.shortLabel, for: .bundle, tint: Theme.amber)
                }
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ label: String, for target: Mode, tint: Color) -> some View {
        Button {
            selectMode(target)
        } label: {
            let isSelected = mode == target
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? tint : Theme.dim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                        .fill(isSelected ? tint.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                        .strokeBorder(isSelected ? tint.opacity(0.24) : Theme.borderSubtle.opacity(0.38), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        }
        .buttonStyle(.cadencePlain)
    }

    private func selectMode(_ target: Mode) {
        mode = target
        tildeMode = false
        if target == .bundle,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = TaskBundle.defaultDisplayTitle
        } else if target != .bundle,
                  title.trimmingCharacters(in: .whitespacesAndNewlines) == TaskBundle.defaultDisplayTitle {
            title = ""
        }
        if target == .calendarEvent,
           selectedCalendar == nil,
           let calendar = calendarManager.defaultWritableCalendar {
            selectedCalendarID = calendar.calendarIdentifier
        }
    }
}
#endif
