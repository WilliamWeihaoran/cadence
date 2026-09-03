#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

struct QuickCreateChoicePopover: View {
    enum Mode { case timeBlock, calendarEvent, bundle }

    let startMin: Int
    let endMin: Int
    let dateKey: String
    let onCreateTask: (String, TaskContainerSelection, String, String, [String]) -> Void
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
    @State private var notes = ""
    @State private var subtaskDraft = ""
    @State private var subtaskTitles: [String] = []
    @State private var selectedContainer: TaskContainerSelection = .inbox
    @State private var selectedSectionName: String = TaskSectionDefaults.defaultName
    @State private var tildeMode: Bool = false
    @State private var tildeSearchQuery = ""
    @State private var bundleTaskSearch = ""
    @State private var selectedBundleTaskIDs: [UUID] = []
    @FocusState private var focused: Bool

    private var usesCalendarCreationPanel: Bool {
        !usesTaskPanelForTaskCreation
    }

    private var modeFormMinHeight: CGFloat {
        switch mode {
        case .timeBlock:
            return usesCalendarCreationPanel ? 246 : 188
        case .calendarEvent:
            return 232
        case .bundle:
            return 300
        }
    }

    private var popoverWidth: CGFloat {
        if mode == .bundle { return 404 }
        return usesCalendarCreationPanel ? 392 : 304
    }

    init(
        startMin: Int,
        endMin: Int,
        dateKey: String,
        onCreateTask: @escaping (String, TaskContainerSelection, String, String, [String]) -> Void,
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
        let initialMode: Mode = defaultsToCalendarEvent && onCreateEvent != nil ? .calendarEvent : .timeBlock
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !usesCalendarCreationPanel {
                Text(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

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
                                .foregroundStyle(Theme.onColor)
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
                    QuickCreateTaskPanelHandoffView(
                        dateKey: dateKey,
                        startMin: startMin,
                        endMin: endMin,
                        containerName: selectedContainerName
                    )
                } else if mode == .timeBlock {
                    QuickCreateTaskDetailsView(
                        dateKey: dateKey,
                        startMin: startMin,
                        endMin: endMin,
                        selectedContainer: $selectedContainer,
                        selectedSectionName: $selectedSectionName,
                        notes: $notes,
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
                        notes: $notes
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
            onCreateTask(title, selectedContainer, selectedSectionName, notes, resolvedSubtasks)
        } else if mode == .bundle {
            onCreateBundle?(
                TaskBundle.storedTitle(title),
                selectedBundleTasks
            )
        } else {
            onCreateEvent?(title, selectedCalendar?.calendarIdentifier ?? selectedCalendarID, notes)
        }
    }

    private var titlePlaceholder: String {
        switch mode {
        case .timeBlock: return usesTaskPanelForTaskCreation ? "Task title, then continue" : "Task title"
        case .bundle: return "Bundle title"
        case .calendarEvent: return "Event title"
        }
    }

    private var primaryActionTitle: String {
        mode == .timeBlock && usesTaskPanelForTaskCreation ? "Open Task Panel" : "Create"
    }

    private var selectedContainerName: String {
        switch selectedContainer {
        case .inbox:
            return "Inbox"
        case .area(let areaID):
            return areas.first(where: { $0.id == areaID })?.name ?? "Selected list"
        case .project(let projectID):
            return projects.first(where: { $0.id == projectID })?.name ?? "Selected list"
        }
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
                    modeButton("Bundle", for: .bundle, tint: Theme.amber)
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
