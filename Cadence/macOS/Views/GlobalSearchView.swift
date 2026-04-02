#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

enum GlobalSearchCategory: String, CaseIterable {
    case commands = "Commands"
    case pages = "Pages"
    case areas = "Areas"
    case projects = "Projects"
    case tasks = "Tasks"
    case events = "Calendar Events"
    case goals = "Goals"
    case habits = "Habits"
}

enum GlobalSearchDestination: Hashable {
    case command(GlobalSearchCommand)
    case sidebar(SidebarItem)
    case area(UUID)
    case project(UUID)
    case task(UUID)
    case event(String)
    case goals
    case habits
}

enum GlobalSearchCommand: String, Hashable {
    case newTask
    case focus
    case today
    case allTasks
    case calendar
    case settings
}

struct GlobalSearchResult: Identifiable, Hashable {
    let id: String
    let category: GlobalSearchCategory
    let title: String
    let subtitle: String
    let icon: String
    let tintHex: String
    let destination: GlobalSearchDestination

    var tint: Color { Color(hex: tintHex) }
}

private struct GlobalSearchSection: Identifiable {
    let category: GlobalSearchCategory
    let results: [GlobalSearchResult]

    var id: String { category.rawValue }
}

struct GlobalSearchOverlay: View {
    let onSelect: (GlobalSearchResult) -> Void
    let onDismiss: () -> Void

    @Environment(GlobalSearchManager.self) private var searchManager
    @Environment(CalendarManager.self) private var calendarManager
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""

    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var tasks: [AppTask]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Habit.order) private var habits: [Habit]

    @State private var eventResults: [GlobalSearchResult] = []
    @State private var highlightedResultID: String?
    @State private var pendingEventSearch: DispatchWorkItem?
    @FocusState private var isSearchFocused: Bool

    private var query: String { searchManager.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarHiddenTabsRaw.split(separator: ",").compactMap { SidebarStaticDestination(rawValue: String($0)) })
    }

    private var sections: [GlobalSearchSection] {
        var built: [GlobalSearchSection] = []
        let commandMatches = commandResults()
        if !commandMatches.isEmpty { built.append(.init(category: .commands, results: commandMatches)) }

        let staticResults = pageResults()
        if !staticResults.isEmpty { built.append(.init(category: .pages, results: staticResults)) }

        let areaMatches = areaResults()
        if !areaMatches.isEmpty { built.append(.init(category: .areas, results: areaMatches)) }

        let projectMatches = projectResults()
        if !projectMatches.isEmpty { built.append(.init(category: .projects, results: projectMatches)) }

        let taskMatches = taskResults()
        if !taskMatches.isEmpty { built.append(.init(category: .tasks, results: taskMatches)) }

        if !eventResults.isEmpty { built.append(.init(category: .events, results: eventResults)) }

        let goalMatches = goalResults()
        if !goalMatches.isEmpty { built.append(.init(category: .goals, results: goalMatches)) }

        let habitMatches = habitResults()
        if !habitMatches.isEmpty { built.append(.init(category: .habits, results: habitMatches)) }

        return built
    }

    private var flattenedResults: [GlobalSearchResult] {
        sections.flatMap(\.results)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                searchHeader

                Divider()
                    .background(Theme.borderSubtle)

                if sections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.category.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.dim)
                                        .kerning(0.8)
                                        .padding(.horizontal, 16)

                                    VStack(spacing: 4) {
                                        ForEach(section.results) { result in
                                            resultRow(result)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(width: 760, height: 620)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.borderSubtle.opacity(0.95), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 36, x: 0, y: 20)
            .onAppear {
                isSearchFocused = true
                runEventSearch()
                syncHighlightToAvailableResults()
            }
            .onChange(of: searchManager.query) { _, _ in
                runEventSearch()
                syncHighlightToAvailableResults()
            }
            .onMoveCommand { direction in
                guard !flattenedResults.isEmpty else { return }
                let currentIndex = flattenedResults.firstIndex(where: { $0.id == highlightedResultID }) ?? 0
                switch direction {
                case .down:
                    highlightedResultID = flattenedResults[min(currentIndex + 1, flattenedResults.count - 1)].id
                case .up:
                    highlightedResultID = flattenedResults[max(currentIndex - 1, 0)].id
                default:
                    break
                }
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.dim)

            TextField("Jump anywhere or run a command…", text: Binding(
                get: { searchManager.query },
                set: { searchManager.query = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.text)
            .focused($isSearchFocused)
            .onSubmit {
                guard let highlighted = flattenedResults.first(where: { $0.id == highlightedResultID }) else { return }
                onSelect(highlighted)
            }

            if !searchManager.query.isEmpty {
                Button {
                    searchManager.query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.surface.opacity(0.48))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.8))
            Text(query.isEmpty ? "Start typing to search or run a command" : "No matches found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(query.isEmpty ? "Pages, lists, tasks, events, goals, habits, and quick commands all show up here." : "Try a cleaner title, list name, or command like new task.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func resultRow(_ result: GlobalSearchResult) -> some View {
        let isHighlighted = highlightedResultID == result.id

        Button {
            onSelect(result)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(result.tint.opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: result.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(result.tint)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? result.tint.opacity(0.09) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHighlighted ? result.tint.opacity(0.18) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.cadencePlain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            if hovering {
                highlightedResultID = result.id
            }
        }
    }

    private func commandResults() -> [GlobalSearchResult] {
        let commands: [(GlobalSearchCommand, String, String, String, String, String)] = [
            (.newTask, "New Task", "Create a task from anywhere in the app", "plus.circle.fill", Theme.blue.toHexString() ?? "#5AA2FF", "create task add"),
            (.focus, "Focus", "Jump straight to the Focus page", "timer", Theme.red.toHexString() ?? "#FF6B6B", "pomodoro timer focus"),
            (.today, "Today", "Open the Today page", "sun.max.fill", Theme.amber.toHexString() ?? "#FFB84D", "today dashboard daily"),
            (.allTasks, "All Tasks", "Open the full task index", "checklist", Theme.blue.toHexString() ?? "#5AA2FF", "tasks all"),
            (.calendar, "Calendar", "Open the calendar and timeline", "calendar", Theme.purple.toHexString() ?? "#9E8CFF", "calendar schedule events"),
            (.settings, "Settings", "Open app settings", "gearshape.fill", Theme.dim.toHexString() ?? "#7B8492", "preferences settings")
        ]

        return rankResults(
            commands.compactMap { command, title, subtitle, icon, tintHex, aliases in
                guard matchScore(title, subtitle, aliases) != nil else { return nil }
                return GlobalSearchResult(
                    id: "command-\(command.rawValue)",
                    category: .commands,
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    tintHex: tintHex,
                    destination: .command(command)
                )
            }
        )
    }

    private func pageResults() -> [GlobalSearchResult] {
        let pages: [(String, SidebarItem, String, String, String, String, SidebarStaticDestination?)] = [
            ("Today", .today, "sun.max.fill", Theme.amber.toHexString() ?? "#FFB84D", "Daily dashboard and timeline", "today dashboard daily", .today),
            ("All Tasks", .allTasks, "checklist", Theme.blue.toHexString() ?? "#5AA2FF", "Everything across your workspace", "tasks all", .allTasks),
            ("Inbox", .inbox, "tray.fill", Theme.blue.toHexString() ?? "#5AA2FF", "Unsorted capture tasks", "inbox capture", .inbox),
            ("Focus", .focus, "timer", Theme.red.toHexString() ?? "#FF6B6B", "Focus timer and active task", "focus timer pomodoro", .focus),
            ("Calendar", .calendar, "calendar", Theme.purple.toHexString() ?? "#9E8CFF", "Full calendar and time blocks", "calendar schedule events", .calendar),
            ("Goals", .goals, "target", Theme.green.toHexString() ?? "#4ECB71", "Goals and progress", "goals target", .goals),
            ("Habits", .habits, "flame.fill", Theme.amber.toHexString() ?? "#FFB84D", "Habits and streaks", "habits streaks", .habits),
            ("Notes", .notes, "doc.text", Theme.purple.toHexString() ?? "#9E8CFF", "Workspace notes", "notes docs", nil),
            ("Settings", .settings, "gearshape.fill", Theme.dim.toHexString() ?? "#7B8492", "Appearance, calendar, and sidebar preferences", "settings preferences", nil)
        ]

        return rankResults(pages.compactMap { label, item, icon, tintHex, baseSubtitle, aliases, toggleable in
            let subtitle: String
            if let toggleable, hiddenTabs.contains(toggleable) {
                subtitle = "\(baseSubtitle) • Hidden from sidebar"
            } else {
                subtitle = baseSubtitle
            }
            guard matchScore(label, subtitle, aliases) != nil else { return nil }
            return GlobalSearchResult(
                id: "page-\(label)",
                category: .pages,
                title: label,
                subtitle: subtitle,
                icon: icon,
                tintHex: tintHex,
                destination: .sidebar(item)
            )
        })
    }

    private func areaResults() -> [GlobalSearchResult] {
        rankResults(areas.compactMap { area in
            let contextName = area.context?.name ?? "No context"
            let lifecycle = area.isArchived ? "archived" : (area.isDone ? "completed done" : "active")
            guard matchScore(area.name, area.desc, contextName, lifecycle) != nil else { return nil }
            return GlobalSearchResult(
                id: "area-\(area.id.uuidString)",
                category: .areas,
                title: area.name,
                subtitle: "\(contextName) • \(area.tasks?.filter { !$0.isDone }.count ?? 0) active tasks • \(area.isArchived ? "Archived" : (area.isDone ? "Completed" : "Active"))",
                icon: area.icon,
                tintHex: area.colorHex,
                destination: .area(area.id)
            )
        })
    }

    private func projectResults() -> [GlobalSearchResult] {
        rankResults(projects.compactMap { project in
            let contextName = project.context?.name ?? "No context"
            let areaName = project.area?.name
            let summary = [contextName, areaName].compactMap { $0 }.joined(separator: " • ")
            let lifecycle = project.isArchived ? "archived" : (project.isDone ? "completed done" : "active")
            guard matchScore(project.name, project.desc, summary, lifecycle) != nil else { return nil }
            return GlobalSearchResult(
                id: "project-\(project.id.uuidString)",
                category: .projects,
                title: project.name,
                subtitle: "\(summary) • \(project.tasks?.filter { !$0.isDone }.count ?? 0) active tasks • \(project.isArchived ? "Archived" : (project.isDone ? "Completed" : "Active"))",
                icon: project.icon,
                tintHex: project.colorHex,
                destination: .project(project.id)
            )
        })
    }

    private func taskResults() -> [GlobalSearchResult] {
        let base = tasks
            .filter { !$0.isCancelled }
            .sorted {
                if $0.isDone != $1.isDone { return !$0.isDone && $1.isDone }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt > $1.createdAt
            }

        return Array(rankResults(base.compactMap { task in
            let container = task.project?.name ?? task.area?.name ?? (task.goal?.title ?? "Inbox")
            let contextName = task.context?.name ?? ""
            let notesSnippet = task.notes.isEmpty ? "" : task.notes
            let statusAliases = [
                task.isDone ? "completed done" : "active todo",
                task.priority.label,
                task.resolvedSectionName
            ].joined(separator: " ")
            guard matchScore(task.title, container, contextName, notesSnippet, statusAliases) != nil else { return nil }

            let meta: [String] = [
                container,
                task.scheduledDate.isEmpty ? nil : "Do \(DateFormatters.relativeDate(from: task.scheduledDate))",
                task.dueDate.isEmpty ? nil : "Due \(DateFormatters.relativeDate(from: task.dueDate))",
                task.isDone ? "Completed" : "Active"
            ].compactMap { $0 }

            return GlobalSearchResult(
                id: "task-\(task.id.uuidString)",
                category: .tasks,
                title: task.title.isEmpty ? "Untitled Task" : task.title,
                subtitle: meta.joined(separator: " • "),
                icon: task.scheduledStartMin >= 0 ? "calendar.badge.clock" : "checkmark.circle",
                tintHex: task.containerColor,
                destination: .task(task.id)
            )
        }).prefix(query.isEmpty ? 10 : 14))
    }

    private func goalResults() -> [GlobalSearchResult] {
        Array(rankResults(goals.compactMap { goal in
            let contextName = goal.context?.name ?? "No context"
            guard matchScore(goal.title, goal.desc, contextName) != nil else { return nil }
            return GlobalSearchResult(
                id: "goal-\(goal.id.uuidString)",
                category: .goals,
                title: goal.title,
                subtitle: "\(contextName) • \(Int(goal.progress * 100))% complete",
                icon: "target",
                tintHex: goal.colorHex,
                destination: .goals
            )
        }).prefix(query.isEmpty ? 6 : 10))
    }

    private func habitResults() -> [GlobalSearchResult] {
        Array(rankResults(habits.compactMap { habit in
            let contextName = habit.context?.name ?? "No context"
            guard matchScore(habit.title, contextName) != nil else { return nil }
            return GlobalSearchResult(
                id: "habit-\(habit.id.uuidString)",
                category: .habits,
                title: habit.title,
                subtitle: "\(contextName) • \(habit.currentStreak) day streak",
                icon: habit.icon,
                tintHex: habit.colorHex,
                destination: .habits
            )
        }).prefix(query.isEmpty ? 6 : 10))
    }

    private func runEventSearch() {
        pendingEventSearch?.cancel()
        guard calendarManager.isAuthorized else {
            eventResults = []
            return
        }

        let workItem = DispatchWorkItem {
            let matchedEvents = calendarManager.searchEvents(matching: query)
            let mapped = Array(matchedEvents.prefix(query.isEmpty ? 6 : 12)).map { event in
                let item = CalendarEventItem(event: event)
                let startDate = event.startDate ?? Date()
                let timeLabel = "\(DateFormatters.dayOfWeek.string(from: startDate)), \(DateFormatters.shortDate.string(from: startDate))"
                let subtitle = [
                    item.calendarTitle,
                    timeLabel,
                    TimeFormatters.timeRange(
                        startMin: item.startMin,
                        endMin: item.startMin + item.durationMinutes
                    )
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")

                return GlobalSearchResult(
                    id: "event-\(item.id)",
                    category: .events,
                    title: item.title,
                    subtitle: subtitle,
                    icon: "calendar",
                    tintHex: item.calendarColor.toHexString() ?? (Theme.purple.toHexString() ?? "#9E8CFF"),
                    destination: .event(item.id)
                )
            }

            DispatchQueue.main.async {
                eventResults = rankResults(mapped)
                syncHighlightToAvailableResults()
            }
        }

        pendingEventSearch = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func rankResults(_ results: [GlobalSearchResult]) -> [GlobalSearchResult] {
        results.sorted { lhs, rhs in
            let leftScore = matchScore(lhs.title, lhs.subtitle) ?? Int.min
            let rightScore = matchScore(rhs.title, rhs.subtitle) ?? Int.min
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func matchScore(_ fields: String...) -> Int? {
        if query.isEmpty { return 1 }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return 1 }

        let normalizedQuery = normalize(trimmedQuery)
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !queryTokens.isEmpty else { return 1 }

        let normalizedFields = fields
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !normalizedFields.isEmpty else { return nil }

        let title = normalizedFields.first ?? ""
        let body = normalizedFields.joined(separator: " ")
        let titleWords = title.split(separator: " ").map(String.init)
        let allWords = body.split(separator: " ").map(String.init)

        var score = 0

        if title == normalizedQuery {
            score += 1_000
        } else if title.hasPrefix(normalizedQuery) {
            score += 800
        } else if body.contains(normalizedQuery) {
            score += 320
        }

        for token in queryTokens {
            if let index = titleWords.firstIndex(where: { $0.hasPrefix(token) }) {
                score += max(260 - (index * 14), 180)
                continue
            }
            if let index = allWords.firstIndex(where: { $0.hasPrefix(token) }) {
                score += max(170 - (index * 6), 90)
                continue
            }
            if title.contains(token) {
                score += 85
                continue
            }
            if body.contains(token) {
                score += 35
                continue
            }
            return nil
        }

        return score
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func syncHighlightToAvailableResults() {
        guard !flattenedResults.isEmpty else {
            highlightedResultID = nil
            return
        }
        if let highlightedResultID,
           flattenedResults.contains(where: { $0.id == highlightedResultID }) {
            return
        }
        highlightedResultID = flattenedResults.first?.id
    }
}

private extension Color {
    func toHexString() -> String? {
        let platformColor = NSColor(self).usingColorSpace(.deviceRGB)
        guard let platformColor else { return nil }
        let r = Int(round(platformColor.redComponent * 255))
        let g = Int(round(platformColor.greenComponent * 255))
        let b = Int(round(platformColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
