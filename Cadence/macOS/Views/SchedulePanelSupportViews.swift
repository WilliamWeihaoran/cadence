#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

struct ScheduleTimeRailRow: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        Text(hourLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(width: timeLabelWidth, height: hourHeight, alignment: .topTrailing)
            .padding(.trailing, timeLabelPad)
            .offset(y: -6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hourLabel: String { "\(hour)" }
}

struct TaskInspectorDateControl: View {
    let label: String
    let icon: String
    var activeColor: Color = Theme.blue
    @Binding var isOn: Bool
    @Binding var date: Date

    @State private var showPicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var isHovered = false

    private let cal = Calendar.current

    private var isDoDate: Bool { icon == "calendar" }

    private var effectiveIcon: String {
        guard isOn, isDoDate else { return icon }
        return cal.isDateInToday(date) ? "star.fill" : icon
    }

    private var effectiveIconColor: Color {
        guard isOn else { return Theme.dim }
        if isDoDate && cal.isDateInToday(date) { return .yellow }
        return activeColor
    }

    private var displayLabel: String {
        guard isOn else { return label }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: date))
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { showPicker.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: effectiveIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(isOn ? effectiveIconColor : Theme.dim)

                    Text(displayLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            isOn
                                ? (isDoDate && cal.isDateInToday(date) ? .yellow : activeColor)
                                : Theme.dim
                        )
                        .lineLimit(1)

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .background(isHovered ? activeColor.opacity(0.08) : Theme.surface.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
            .onHover { isHovered = $0 }
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                pickerPopover
            }

            Button {
                isOn = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim.opacity(isOn ? 0.65 : 0))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.cadencePlain)
            .disabled(!isOn)
        }
        .onAppear {
            var comps = cal.dateComponents([.year, .month], from: isOn ? date : Date())
            comps.day = 1
            viewMonth = cal.date(from: comps) ?? Date()
        }
    }

    @ViewBuilder
    private var pickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                quickPill("Today", offset: 0)
                quickPill("Tomorrow", offset: 1)
                quickPill("This Weekend", weekend: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            MonthCalendarPanel(
                selection: Binding(
                    get: { date },
                    set: {
                        date = $0
                        isOn = true
                        showPicker = false
                    }
                ),
                viewMonth: $viewMonth,
                isOpen: $showPicker
            )

            if isOn {
                Button("Clear date") {
                    isOn = false
                    showPicker = false
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.red)
                .padding(.bottom, 10)
            }
        }
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private func quickPill(_ label: String, offset: Int = 0, weekend: Bool = false) -> some View {
        let target: Date = {
            let today = cal.startOfDay(for: Date())
            if weekend {
                let todayWeekday = cal.component(.weekday, from: today)
                if todayWeekday == 7 || todayWeekday == 1 { return today }
                let daysUntilSaturday = (7 - todayWeekday + 7) % 7
                return cal.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
            }
            return cal.date(byAdding: .day, value: offset, to: today) ?? today
        }()
        let isSelected = isOn && cal.isDate(date, inSameDayAs: target)

        Button {
            date = target
            isOn = true
            showPicker = false
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? activeColor : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(InspectorPickerHover(cornerRadius: 999))
    }
}

struct QuickCreateChoicePopover: View {
    enum TildeMode { case none, list, section }

    let startMin: Int
    let endMin: Int
    let onCreateTask: (String, TaskContainerSelection, String) -> Void
    let onCreateEvent: ((String, String, String) -> Void)?
    let onCancel: () -> Void

    enum Mode { case timeBlock, calendarEvent }

    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var mode: Mode = .timeBlock
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            if onCreateEvent != nil {
                HStack(spacing: 4) {
                    modeButton("Time Block", for: .timeBlock)
                    modeButton("Calendar Event", for: .calendarEvent)
                }
                .padding(3)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ZStack(alignment: .leading) {
                TextField(mode == .timeBlock ? "Task title" : "Event title", text: $title)
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
                            .popover(
                                isPresented: Binding(
                                    get: { tildeMode != .none },
                                    set: { if !$0 { tildeMode = .none } }
                                ),
                                arrowEdge: .bottom
                            ) {
                                if tildeMode == .list {
                                    tildeListSearchView
                                } else {
                                    tildeSectionSearchView
                                }
                            }
                        Spacer(minLength: 0)
                    }
                }
            }

            if mode == .calendarEvent {
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
                    isDisabled: mode == .calendarEvent && selectedCalendarID.isEmpty
                ) {
                    create()
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(Theme.surface)
        .onAppear {
            focused = true
            normalizeSelectedSection()
            if let first = calendarManager.writableCalendars.first {
                selectedCalendarID = first.calendarIdentifier
            }
        }
    }

    private func create() {
        if mode == .timeBlock {
            onCreateTask(title, selectedContainer, selectedSectionName)
        } else {
            onCreateEvent?(title, selectedCalendarID, notes)
        }
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
    private func modeButton(_ label: String, for target: Mode) -> some View {
        Button(label) { mode = target }
            .buttonStyle(.cadencePlain)
            .font(.system(size: 11, weight: mode == target ? .semibold : .regular))
            .foregroundStyle(mode == target ? Theme.text : Theme.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(mode == target ? Theme.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct TaskInspectorInfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct TaskInspectorSectionGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
    }
}

struct TaskInspectorDetailRow<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 11)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)
            .padding(.top, 7)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28, alignment: .top)
    }
}

struct TaskPriorityPill: View {
    let priority: TaskPriority
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.priorityColor(priority))
                .frame(width: 7, height: 7)
            Text(priority.label)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
        }
        .foregroundStyle(selected ? Theme.text : Theme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
        .background(selected ? Theme.surfaceElevated : Theme.surface.opacity(0.6))
        .clipShape(Capsule())
    }
}

struct InspectorPickerHover: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}

struct MinutesField: View {
    @Binding var value: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("—", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(value > 0 ? Theme.text : Theme.dim)
                .frame(width: 52)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { if !focused { commit() } }
            if value > 0 {
                Text("min")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
        }
        .onAppear { text = value > 0 ? "\(value)" : "" }
        .onChange(of: value) { text = value > 0 ? "\(value)" : "" }
    }

    private func commit() {
        if let parsed = Int(text.trimmingCharacters(in: .whitespaces)), parsed >= 0 {
            value = parsed
        } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
            value = 0
        }
        text = value > 0 ? "\(value)" : ""
    }
}
#endif
