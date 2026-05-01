#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

struct QuickCreateChoicePopover: View {
    enum TildeMode { case none, list, section }
    enum Mode { case timeBlock, calendarEvent, bundle }

    let startMin: Int
    let endMin: Int
    let onCreateTask: (String, TaskContainerSelection, String) -> Void
    let onCreateBundle: ((String) -> Void)?
    let onCreateEvent: ((String, String, String) -> Void)?
    let onCancel: () -> Void

    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var mode: Mode
    @State private var title = ""
    @State private var selectedCalendarID = ""
    @State private var notes = ""
    @State private var selectedContainer: TaskContainerSelection = .inbox
    @State private var selectedSectionName: String = TaskSectionDefaults.defaultName
    @State private var tildeMode: TildeMode = .none
    @State private var tildeSearchQuery = ""
    @State private var tildeHighlightIdx = 0
    @FocusState private var focused: Bool
    @FocusState private var isTildeSearchFocused: Bool
    private let modeFormMinHeight: CGFloat = 190

    init(
        startMin: Int,
        endMin: Int,
        onCreateTask: @escaping (String, TaskContainerSelection, String) -> Void,
        onCreateBundle: ((String) -> Void)? = nil,
        onCreateEvent: ((String, String, String) -> Void)?,
        onCancel: @escaping () -> Void,
        defaultsToCalendarEvent: Bool = false
    ) {
        self.startMin = startMin
        self.endMin = endMin
        self.onCreateTask = onCreateTask
        self.onCreateBundle = onCreateBundle
        self.onCreateEvent = onCreateEvent
        self.onCancel = onCancel
        let initialMode: Mode = defaultsToCalendarEvent && onCreateEvent != nil ? .calendarEvent : .timeBlock
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            modeSelector

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .leading) {
                    TextField(titlePlaceholder, text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .focused($focused)
                        .onSubmit { create() }
                        .onChange(of: title) { _, newValue in
                            guard mode == .timeBlock, newValue.hasSuffix("~") else { return }
                            let prefix = String(newValue.dropLast())
                            if prefix.isEmpty || prefix.hasSuffix(" ") {
                                title = prefix
                                tildeSearchQuery = ""
                                tildeHighlightIdx = 0
                                tildeMode = .list
                            }
                        }
                        .opacity(tildeMode == .none ? 1 : 0)
                        .allowsHitTesting(tildeMode == .none)

                    if tildeMode != .none {
                        HStack(spacing: 4) {
                            if !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .fixedSize()
                            }
                            Text("~")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Spacer(minLength: 0)
                        }
                    }
                }

                if tildeMode != .none {
                    tildeInlineSearchView
                }

                if mode == .calendarEvent {
                    let _ = calendarManager.storeVersion
                    let calendars = calendarManager.writableCalendars
                    if !calendars.isEmpty {
                        CadenceCalendarPickerButton(
                            calendars: calendars,
                            selectedID: $selectedCalendarID,
                            allowNone: false,
                            style: .compact
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        TextEditor(text: $notes)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .frame(minHeight: 84)
                            .padding(8)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: modeFormMinHeight, alignment: .topLeading)

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
                    title: "Create",
                    role: .secondary,
                    size: .compact,
                    tint: mode == .bundle ? Theme.amber : Theme.blue,
                    isDisabled: mode == .calendarEvent && selectedCalendar == nil
                ) {
                    create()
                }
            }
        }
        .padding(14)
        .frame(width: 286)
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
            onCreateTask(title, selectedContainer, selectedSectionName)
        } else if mode == .bundle {
            onCreateBundle?(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Task Bundle" : title)
        } else {
            onCreateEvent?(title, selectedCalendar?.calendarIdentifier ?? selectedCalendarID, notes)
        }
    }

    private var titlePlaceholder: String {
        switch mode {
        case .timeBlock: return "Task title"
        case .bundle: return "Bundle title"
        case .calendarEvent: return "Event title"
        }
    }

    private var selectedCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == selectedCalendarID }
            ?? calendarManager.defaultWritableCalendar
    }

    private var availableSections: [String] {
        switch selectedContainer {
        case .inbox:
            return [TaskSectionDefaults.defaultName]
        case .area(let areaID):
            return areas.first(where: { $0.id == areaID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        case .project(let projectID):
            return projects.first(where: { $0.id == projectID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        }
    }

    private struct TildeContainerItem: Identifiable {
        let tag: TaskContainerSelection
        let icon: String
        let name: String
        let color: Color
        var id: TaskContainerSelection { tag }
    }

    private var tildeFlatContainers: [TildeContainerItem] {
        let query = tildeSearchQuery.lowercased()
        func matches(_ name: String) -> Bool { query.isEmpty || name.lowercased().hasPrefix(query) }

        var result: [TildeContainerItem] = []
        if matches("Inbox") {
            result.append(.init(tag: .inbox, icon: "tray", name: "Inbox", color: Theme.dim))
        }
        for context in contexts {
            for area in areas.filter({ $0.context?.id == context.id }).sorted(by: { $0.order < $1.order }) {
                if matches(area.name) {
                    result.append(.init(tag: .area(area.id), icon: area.icon, name: area.name, color: Color(hex: area.colorHex)))
                }
            }
            for project in projects.filter({ $0.context?.id == context.id }).sorted(by: { $0.order < $1.order }) {
                if matches(project.name) {
                    result.append(.init(tag: .project(project.id), icon: project.icon, name: project.name, color: Color(hex: project.colorHex)))
                }
            }
        }
        return result
    }

    private func normalizeSelectedSection() {
        let validSections = availableSections
        if !validSections.contains(where: { $0.caseInsensitiveCompare(selectedSectionName) == .orderedSame }) {
            selectedSectionName = validSections.first ?? TaskSectionDefaults.defaultName
        }
    }

    private func selectTildeContainer() {
        let items = tildeFlatContainers
        guard !items.isEmpty else { return }
        selectTildeContainerItem(items[min(tildeHighlightIdx, items.count - 1)].tag)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        selectedContainer = tag
        normalizeSelectedSection()
        tildeSearchQuery = ""
        tildeHighlightIdx = 0
        tildeMode = .section
    }

    private var tildeListSearchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Button("") {
                    let count = tildeFlatContainers.count
                    if count > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, count - 1) }
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("") { tildeHighlightIdx = max(tildeHighlightIdx - 1, 0) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .clipped()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                TextField("Search lists…", text: $tildeSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($isTildeSearchFocused)
                    .onSubmit { selectTildeContainer() }
                    .onKeyPress(.upArrow) {
                        tildeHighlightIdx = max(tildeHighlightIdx - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        let count = tildeFlatContainers.count
                        if count > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, count - 1) }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        title += "~"
                        tildeMode = .none
                        DispatchQueue.main.async { focused = true }
                        return .handled
                    }
                if !tildeSearchQuery.isEmpty {
                    Button { tildeSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim.opacity(0.5))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Theme.borderSubtle)

            let items = tildeFlatContainers
            if items.isEmpty {
                Text("No results")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TildeContainerPickerRow(
                            icon: item.icon,
                            name: item.name,
                            color: item.color,
                            isHighlighted: index == tildeHighlightIdx,
                            isSelected: selectedContainer == item.tag,
                            action: { selectTildeContainerItem(item.tag) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 200)
        .background(Theme.surfaceElevated)
        .onAppear { DispatchQueue.main.async { isTildeSearchFocused = true } }
        .onChange(of: tildeSearchQuery) { _, _ in tildeHighlightIdx = 0 }
    }

    @ViewBuilder
    private var tildeInlineSearchView: some View {
        Group {
            if tildeMode == .list {
                tildeListSearchView
            } else {
                tildeSectionSearchView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
        )
    }

    private var tildeSectionSearchView: some View {
        TildeSectionSearchPanel(
            sections: availableSections,
            selectedSectionName: selectedSectionName,
            onSelect: { section in
                selectedSectionName = section
                tildeMode = .none
                DispatchQueue.main.async { focused = true }
            },
            onDismiss: {
                tildeMode = .none
                DispatchQueue.main.async { focused = true }
            }
        )
    }

    @ViewBuilder
    private var modeSelector: some View {
        if onCreateEvent != nil || onCreateBundle != nil {
            HStack(spacing: 6) {
                modeButton("Time Block", for: .timeBlock, tint: Theme.blue)
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
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? tint.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? tint.opacity(0.24) : Theme.borderSubtle.opacity(0.38), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
    }

    private func selectMode(_ target: Mode) {
        mode = target
        tildeMode = .none
        if target == .bundle,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = "Task Bundle"
        } else if target != .bundle,
                  title.trimmingCharacters(in: .whitespacesAndNewlines) == "Task Bundle" {
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
