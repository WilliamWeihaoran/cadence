#if os(iOS)
import EventKit
import SwiftData
import SwiftUI
import UIKit

struct iOSSearchView: View {
    @Environment(\.openURL) private var openURL
    @Environment(iOSCalendarManager.self) private var calendarManager

    @Query(sort: \AppTask.createdAt, order: .reverse) private var tasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Habit.order) private var habits: [Habit]

    @State private var query = ""
    @State private var selectedTask: AppTask?
    @State private var selectedNote: Note?
    @State private var selectedEvent: iOSCalendarEventSelection?
    @State private var calendarSearchEvents: [EKEvent] = []
    @State private var scope: iOSSearchScope = .all
    @State private var includeCompletedTasks = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    private var searchableTasks: [AppTask] {
        tasks.filter { task in
            guard !task.isCancelled else { return false }
            return includeCompletedTasks || !task.isDone
        }
    }

    private var showsTasks: Bool {
        scope == .all || scope == .tasks
    }

    private var showsLists: Bool {
        scope == .all || scope == .lists
    }

    private var showsNotes: Bool {
        scope == .all || scope == .notes
    }

    private var showsEvents: Bool {
        scope == .all || scope == .events
    }

    private var showsProgress: Bool {
        scope == .all || scope == .progress
    }

    private var calendarSearchRequestID: String {
        [
            trimmedQuery,
            scope.rawValue,
            calendarManager.isAuthorized ? "authorized" : "unauthorized",
            String(calendarManager.storeVersion)
        ].joined(separator: "|")
    }

    private var pageResults: [iOSSearchResult] {
        let candidates = iOSSearchFeatureDestination.allCases.map { destination in
            iOSSearchFeatureCandidate(
                title: destination.title,
                subtitle: destination.subtitle,
                detail: destination.detail,
                icon: destination.icon,
                color: destination.color,
                destination: destination,
                fields: [destination.title, destination.subtitle, destination.detail, destination.aliases]
            )
        }

        if isSearching {
            return candidates.compactMap { candidate in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: candidate.fields) else {
                    return nil
                }
                return candidate.result(score: score)
            }
            .sorted { $0.score > $1.score }
        }

        return candidates.prefix(5).map { $0.result(score: 0) }
    }

    private var taskResults: [iOSSearchResult] {
        if isSearching {
            return rankedTaskResults
        }

        let today = DateFormatters.todayKey()
        let suggested = searchableTasks
            .filter {
                !$0.isCancelled &&
                !$0.isDone &&
                ($0.scheduledDate == today || $0.dueDate <= today && !$0.dueDate.isEmpty)
            }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate {
                    if lhs.dueDate.isEmpty { return false }
                    if rhs.dueDate.isEmpty { return true }
                    return lhs.dueDate < rhs.dueDate
                }
                return lhs.order < rhs.order
            }
            .prefix(8)

        return suggested.map {
            iOSSearchResult(
                kind: .task,
                title: $0.title.isEmpty ? "Untitled Task" : $0.title,
                subtitle: taskSubtitle($0),
                detail: taskDetail($0),
                icon: $0.isDone ? "checkmark.circle.fill" : "circle",
                color: Theme.priorityColor($0.priority),
                score: 0,
                task: $0
            )
        }
    }

    private var listResults: [iOSSearchResult] {
        let listItems = areas.filter(\.isActive).map { area in
            let count = CadenceTaskQuerySupport.openTaskCount(for: area)
            return iOSSearchListCandidate(
                title: area.name.isEmpty ? "Untitled Area" : area.name,
                subtitle: area.context?.name ?? "Area",
                detail: count == 1 ? "1 task" : "\(count) tasks",
                icon: area.icon,
                color: Color(hex: area.colorHex),
                route: .area(area.id),
                fields: [area.name, area.desc, area.context?.name ?? ""]
            )
        } + projects.filter(\.isActive).map { project in
            let count = CadenceTaskQuerySupport.openTaskCount(for: project)
            return iOSSearchListCandidate(
                title: project.name.isEmpty ? "Untitled Project" : project.name,
                subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / "),
                detail: count == 1 ? "1 task" : "\(count) tasks",
                icon: project.icon,
                color: Color(hex: project.colorHex),
                route: .project(project.id),
                fields: [project.name, project.desc, project.context?.name ?? "", project.area?.name ?? ""]
            )
        }

        if isSearching {
            return listItems.compactMap { candidate in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: candidate.fields) else {
                    return nil
                }
                return candidate.result(score: score)
            }
            .sorted { $0.score > $1.score }
        }

        return Array(listItems.prefix(8)).map { $0.result(score: 0) }
    }

    private var noteResults: [iOSSearchResult] {
        let searchableNotes = notes.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if isSearching {
            return searchableNotes.compactMap { note in
                let tagText = note.sortedTags.map(\.name).joined(separator: " ")
                guard let score = CadenceSearchMatcher.matchScore(
                    query: trimmedQuery,
                    fields: [note.displayTitle, note.content, noteSubtitle(note), tagText]
                ) else {
                    return nil
                }
                return noteResult(note, score: score)
            }
            .sorted { $0.score > $1.score }
        }

        return searchableNotes.prefix(8).map { noteResult($0, score: 0) }
    }

    private var progressResults: [iOSSearchResult] {
        let candidates = pursuits.filter { $0.status != .done }.map { pursuit in
            let summary = CadencePursuitSupport.summary(for: pursuit)
            return iOSSearchResult(
                kind: .progress,
                title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title,
                subtitle: pursuit.context?.name ?? pursuit.kind.label,
                detail: "\(summary.activeGoalCount) milestones / \(summary.activeHabitCount) habits",
                icon: pursuit.icon,
                color: Color(hex: pursuit.colorHex),
                score: CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: [pursuit.title, pursuit.kind.label, pursuit.context?.name ?? ""]) ?? 0,
                featureDestination: .pursuits
            )
        } + goals.filter { $0.status != .done }.map { goal in
            let summary = GoalContributionResolver.summary(for: goal)
            return iOSSearchResult(
                kind: .progress,
                title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                subtitle: goal.pursuit?.title ?? goal.context?.name ?? goal.status.rawValue.capitalized,
                detail: "\(Int((summary.progress * 100).rounded()))%",
                icon: "flag.fill",
                color: Color(hex: goal.colorHex),
                score: CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: [goal.title, goal.desc, goal.pursuit?.title ?? "", goal.context?.name ?? ""]) ?? 0,
                featureDestination: .milestones
            )
        } + habits.map { habit in
            iOSSearchResult(
                kind: .progress,
                title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                subtitle: habit.pursuit?.title ?? habit.context?.name ?? habit.frequencySummary,
                detail: habit.isDueToday ? "Due today" : habit.frequencySummary,
                icon: "flame.fill",
                color: Color(hex: habit.colorHex),
                score: CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: [habit.title, habit.pursuit?.title ?? "", habit.context?.name ?? "", habit.frequencySummary]) ?? 0,
                featureDestination: .habits
            )
        }

        if isSearching {
            return candidates.filter { $0.score > 0 }.sorted { $0.score > $1.score }
        }

        return Array(candidates.prefix(8))
    }

    private var eventResults: [iOSSearchResult] {
        if isSearching {
            return calendarSearchEvents.compactMap { event in
                let fields = eventSearchFields(for: event)
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: fields) else {
                    return nil
                }
                return eventResult(event, score: score)
            }
            .sorted { $0.score > $1.score }
        }

        return calendarSearchEvents.prefix(8).map { eventResult($0, score: 0) }
    }

    private var rankedTaskResults: [iOSSearchResult] {
        searchableTasks.compactMap { task in
            let tagText = task.sortedTags.map(\.name).joined(separator: " ")
            guard let score = CadenceSearchMatcher.matchScore(
                query: trimmedQuery,
                fields: [
                    task.title,
                    task.notes,
                    task.containerName,
                    task.resolvedSectionName,
                    task.priority.label,
                    tagText
                ]
            ) else {
                return nil
            }
            return iOSSearchResult(
                kind: .task,
                title: task.title.isEmpty ? "Untitled Task" : task.title,
                subtitle: taskSubtitle(task),
                detail: taskDetail(task),
                icon: task.isDone ? "checkmark.circle.fill" : "circle",
                color: Theme.priorityColor(task.priority),
                score: score,
                task: task
            )
        }
        .sorted { $0.score > $1.score }
    }

    var body: some View {
        List {
            if !isSearching {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("Find tasks, lists, notes, and calendar events across Cadence.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                iOSSearchScopePicker(selection: $scope)

                if showsTasks {
                    Toggle("Include completed tasks", isOn: $includeCompletedTasks)
                }
            }

            if showsProgress {
                resultSection("Pages", results: pageResults)
            }
            if showsTasks {
                resultSection("Tasks", results: taskResults)
            }
            if showsLists {
                resultSection("Lists", results: listResults)
            }
            if showsNotes {
                resultSection("Notes", results: noteResults)
            }
            if showsEvents {
                calendarAccessSection
                resultSection("Calendar Events", results: eventResults)
            }
            if showsProgress {
                resultSection("Pursuits, Milestones, Habits", results: progressResults)
            }

            if isSearching && visibleResultsAreEmpty && !(showsEvents && !calendarManager.isAuthorized) {
                iOSEmptyPanel(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a task, note, area, project, event, tag, or section name."
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tasks, lists, notes, events")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .task(id: calendarSearchRequestID) {
            refreshCalendarSearchEvents()
        }
        .navigationDestination(for: iOSListRoute.self) { route in
            switch route {
            case .area(let id):
                if let area = areas.first(where: { $0.id == id }) {
                    iOSListDetailView(area: area)
                } else {
                    iOSMissingListView()
                }
            case .project(let id):
                if let project = projects.first(where: { $0.id == id }) {
                    iOSListDetailView(project: project)
                } else {
                    iOSMissingListView()
                }
            }
        }
        .navigationDestination(for: iOSSearchFeatureDestination.self) { destination in
            switch destination {
            case .today:
                iPadTodayView()
            case .allTasks:
                iOSAllTasksView()
            case .inbox:
                iPadInboxView()
            case .notes:
                iOSCompactNotesView()
            case .focus:
                iOSFocusView()
            case .calendar:
                iOSCalendarView()
            case .pursuits:
                iOSPursuitsView()
            case .milestones:
                iOSMilestonesView()
            case .habits:
                iOSHabitsView()
            case .lists:
                iOSListsView()
            case .settings:
                iOSSettingsView()
            }
        }
        .sheet(item: $selectedTask) { task in
            iOSTaskDetailSheet(task: task)
        }
        .sheet(item: $selectedNote) { note in
            noteSheet(for: note)
        }
        .sheet(item: $selectedEvent) { selection in
            iOSCalendarEventEditSheet(event: selection.event)
        }
    }

    @ViewBuilder
    private func noteSheet(for note: Note) -> some View {
        if note.kind == .meeting {
            let event = calendarManager.event(withIdentifier: note.calendarEventID)
            iOSEventNoteEditorSheet(
                note: note,
                eventTitle: event.map { iOSCalendarEventSupport.title(for: $0) } ?? note.displayTitle,
                event: event
            )
        } else {
            iOSNoteDetailSheet(note: note)
        }
    }

    @ViewBuilder
    private var calendarAccessSection: some View {
        if !calendarManager.isAuthorized {
            Section("Calendar Events") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        calendarManager.isDenied ? "Calendar access is disabled" : "Calendar access is off",
                        systemImage: calendarManager.isDenied ? "calendar.badge.exclamationmark" : "calendar"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                    Text(calendarManager.isDenied ? "Enable Calendar access in Settings to include Apple Calendar events in search." : "Allow Calendar access to search and edit Apple Calendar events from Cadence.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)

                    Button {
                        if calendarManager.isDenied {
                            openAppSettings()
                        } else {
                            Task { await calendarManager.requestAccess() }
                        }
                    } label: {
                        Label(calendarManager.isDenied ? "Open Settings" : "Allow Calendar Access", systemImage: calendarManager.isDenied ? "gearshape.fill" : "checkmark.shield.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var visibleResultsAreEmpty: Bool {
        (!showsTasks || taskResults.isEmpty) &&
        (!showsLists || listResults.isEmpty) &&
        (!showsNotes || noteResults.isEmpty) &&
        (!showsEvents || eventResults.isEmpty) &&
        (!showsProgress || pageResults.isEmpty && progressResults.isEmpty)
    }

    @ViewBuilder
    private func resultSection(_ title: String, results: [iOSSearchResult]) -> some View {
        if !results.isEmpty {
            Section(title) {
                ForEach(results.prefix(isSearching ? 24 : 8)) { result in
                    if let route = result.listRoute {
                        NavigationLink(value: route) {
                            iOSSearchResultRow(result: result)
                        }
                    } else if let destination = result.featureDestination {
                        NavigationLink(value: destination) {
                            iOSSearchResultRow(result: result)
                        }
                    } else {
                        Button {
                            if let task = result.task {
                                selectedTask = task
                            } else if let note = result.note {
                                selectedNote = note
                            } else if let event = result.event {
                                selectedEvent = iOSCalendarEventSelection(event: event)
                            }
                        } label: {
                            iOSSearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func refreshCalendarSearchEvents() {
        guard showsEvents, calendarManager.isAuthorized else {
            calendarSearchEvents = []
            return
        }

        calendarSearchEvents = calendarManager.searchEvents(
            matching: trimmedQuery,
            pastDays: isSearching ? 60 : 0,
            futureDays: isSearching ? 365 : 30
        )
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func taskSubtitle(_ task: AppTask) -> String {
        if !task.containerName.isEmpty {
            return [task.containerName, task.resolvedSectionName].joined(separator: " / ")
        }
        return "Inbox"
    }

    private func taskDetail(_ task: AppTask) -> String {
        var parts: [String] = []
        if !task.scheduledDate.isEmpty {
            parts.append("Do \(DateFormatters.relativeDate(from: task.scheduledDate))")
        }
        if !task.dueDate.isEmpty {
            parts.append("Due \(DateFormatters.relativeDate(from: task.dueDate))")
        }
        if task.estimatedMinutes > 0 {
            parts.append(task.estimatedMinutes < 60 ? "\(task.estimatedMinutes)m" : "\(task.estimatedMinutes / 60)h")
        }
        return parts.joined(separator: " · ")
    }

    private func eventSearchFields(for event: EKEvent) -> [String] {
        [
            iOSCalendarEventSupport.title(for: event),
            event.notes ?? "",
            event.calendar?.title ?? "",
            eventDetail(event)
        ]
    }

    private func eventDetail(_ event: EKEvent) -> String {
        let startDate = event.startDate ?? event.occurrenceDate ?? Date()
        let dayLabel = "\(DateFormatters.dayOfWeek.string(from: startDate)), \(DateFormatters.shortDate.string(from: startDate))"
        return [
            dayLabel,
            iOSCalendarEventSupport.timeRangeLabel(for: event)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func eventResult(_ event: EKEvent, score: Int) -> iOSSearchResult {
        iOSSearchResult(
            kind: .event,
            title: iOSCalendarEventSupport.title(for: event),
            subtitle: event.calendar?.title ?? "Apple Calendar",
            detail: eventDetail(event),
            icon: event.isAllDay ? "calendar.badge.clock" : "calendar",
            color: iOSCalendarEventSupport.color(for: event.calendar),
            score: score,
            event: event
        )
    }

    private func noteSubtitle(_ note: Note) -> String {
        switch note.kind {
        case .daily:
            return note.dateKey.isEmpty ? "Daily note" : "Daily / \(note.dateKey)"
        case .weekly:
            return note.weekKey.isEmpty ? "Weekly note" : "Weekly / \(note.weekKey)"
        case .permanent:
            return "Permanent note"
        case .list:
            return [note.area?.name, note.project?.name].compactMap { $0 }.first ?? "List note"
        case .meeting:
            return note.eventDateKey.isEmpty ? "Meeting note" : "Meeting / \(note.eventDateKey)"
        }
    }

    private func noteResult(_ note: Note, score: Int) -> iOSSearchResult {
        iOSSearchResult(
            kind: .note,
            title: note.displayTitle,
            subtitle: noteSubtitle(note),
            detail: excerpt(note.content),
            icon: "doc.text",
            color: Theme.purple,
            score: score,
            note: note
        )
    }

    private func excerpt(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        return String(trimmed.prefix(117)) + "..."
    }

}

private enum iOSSearchScope: String, CaseIterable, Identifiable {
    case all
    case tasks
    case lists
    case notes
    case events
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .tasks: return "Tasks"
        case .lists: return "Lists"
        case .notes: return "Notes"
        case .events: return "Events"
        case .progress: return "More"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tasks: return "checkmark.circle"
        case .lists: return "folder"
        case .notes: return "note.text"
        case .events: return "calendar"
        case .progress: return "sparkles"
        }
    }
}

private enum iOSSearchFeatureDestination: String, CaseIterable, Hashable {
    case today
    case allTasks
    case inbox
    case notes
    case focus
    case calendar
    case pursuits
    case milestones
    case habits
    case lists
    case settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .inbox: return "Inbox"
        case .notes: return "Notes"
        case .focus: return "Focus"
        case .calendar: return "Calendar"
        case .pursuits: return "Pursuits"
        case .milestones: return "Milestones"
        case .habits: return "Habits"
        case .lists: return "Lists"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .today: return "Plan the day"
        case .allTasks: return "Full task index"
        case .inbox: return "Capture and triage"
        case .notes: return "Workspace notes"
        case .focus: return "Timer and current work"
        case .calendar: return "Timeline and month"
        case .pursuits: return "Long-running directions"
        case .milestones: return "Goals and progress"
        case .habits: return "Repeating commitments"
        case .lists: return "Areas and projects"
        case .settings: return "Preferences and diagnostics"
        }
    }

    var detail: String {
        switch self {
        case .today: return "tasks notes schedule"
        case .allTasks: return "tasks completed active"
        case .inbox: return "capture unsorted tasks"
        case .notes: return "daily weekly notepad markdown"
        case .focus: return "timer pomodoro session"
        case .calendar: return "calendar schedule timeline month"
        case .pursuits: return "pursuits aspirations directions"
        case .milestones: return "goals milestones progress"
        case .habits: return "habits streaks routines"
        case .lists: return "areas projects lists"
        case .settings: return "settings preferences sync tags themes"
        }
    }

    var aliases: String { "\(rawValue) \(title) \(subtitle) \(detail)" }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .inbox: return "tray.fill"
        case .notes: return "note.text"
        case .focus: return "timer"
        case .calendar: return "calendar"
        case .pursuits: return "sparkles"
        case .milestones: return "flag.fill"
        case .habits: return "flame.fill"
        case .lists: return "folder.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .today: return Theme.amber
        case .allTasks, .inbox, .settings: return Theme.blue
        case .notes, .calendar, .pursuits: return Theme.purple
        case .focus: return Theme.red
        case .milestones, .lists: return Theme.green
        case .habits: return Theme.amber
        }
    }
}

private struct iOSSearchListCandidate {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let route: iOSListRoute
    let fields: [String]

    func result(score: Int) -> iOSSearchResult {
        iOSSearchResult(
            kind: .list,
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            score: score,
            listRoute: route
        )
    }
}

private struct iOSSearchFeatureCandidate {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let destination: iOSSearchFeatureDestination
    let fields: [String]

    func result(score: Int) -> iOSSearchResult {
        iOSSearchResult(
            kind: .feature,
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            score: score,
            featureDestination: destination
        )
    }
}

private struct iOSSearchResult: Identifiable {
    enum Kind {
        case task
        case list
        case note
        case event
        case progress
        case feature
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let score: Int
    var task: AppTask?
    var note: Note?
    var event: EKEvent?
    var listRoute: iOSListRoute?
    var featureDestination: iOSSearchFeatureDestination?
}

private struct iOSSearchScopePicker: View {
    @Binding var selection: iOSSearchScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(iOSSearchScope.allCases) { scope in
                    iOSSearchScopeChip(
                        scope: scope,
                        isSelected: selection == scope
                    ) {
                        withAnimation(.snappy(duration: 0.16)) {
                            selection = scope
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

private struct iOSSearchScopeChip: View {
    let scope: iOSSearchScope
    let isSelected: Bool
    let action: () -> Void

    private var foreground: Color {
        isSelected ? .white : Theme.text
    }

    private var background: Color {
        isSelected ? Theme.blue : Theme.surfaceElevated
    }

    private var border: Color {
        Theme.borderSubtle.opacity(isSelected ? 0 : 0.9)
    }

    var body: some View {
        Button(action: action) {
            Label(scope.title, systemImage: scope.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct iOSSearchResultRow: View {
    let result: iOSSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(result.color)
                .frame(width: 30, height: 30)
                .background(result.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                if !result.detail.isEmpty {
                    Text(result.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim.opacity(0.78))
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct iOSNoteDetailSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isEditorFocused = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSMarkdownEditor(text: $note.content, isFocused: $isEditorFocused)
                    .background(Theme.surface)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(note.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isEditorFocused = false
                        note.updatedAt = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onChange(of: note.content) { _, _ in
                note.updatedAt = Date()
                try? modelContext.save()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isEditorFocused = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
