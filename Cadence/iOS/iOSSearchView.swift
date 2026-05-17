#if os(iOS)
import SwiftData
import SwiftUI

struct iOSSearchView: View {
    @Query(sort: \AppTask.createdAt, order: .reverse) private var tasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var query = ""
    @State private var selectedTask: AppTask?
    @State private var selectedNote: Note?
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
            iOSSearchListCandidate(
                title: area.name.isEmpty ? "Untitled Area" : area.name,
                subtitle: area.context?.name ?? "Area",
                detail: activeTaskCount(for: area) == 1 ? "1 task" : "\(activeTaskCount(for: area)) tasks",
                icon: area.icon,
                color: Color(hex: area.colorHex),
                route: .area(area.id),
                fields: [area.name, area.desc, area.context?.name ?? ""]
            )
        } + projects.filter(\.isActive).map { project in
            iOSSearchListCandidate(
                title: project.name.isEmpty ? "Untitled Project" : project.name,
                subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / "),
                detail: activeTaskCount(for: project) == 1 ? "1 task" : "\(activeTaskCount(for: project)) tasks",
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
                        Text("Find tasks, lists, and notes across Cadence.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Scope", selection: $scope) {
                    ForEach(iOSSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if showsTasks {
                    Toggle("Include completed tasks", isOn: $includeCompletedTasks)
                }
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

            if isSearching && visibleResultsAreEmpty {
                iOSEmptyPanel(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a task, note, area, project, tag, or section name."
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tasks, lists, notes")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
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
        .sheet(item: $selectedTask) { task in
            iOSTaskDetailSheet(task: task)
        }
        .sheet(item: $selectedNote) { note in
            iOSNoteDetailSheet(note: note)
        }
    }

    private var visibleResultsAreEmpty: Bool {
        (!showsTasks || taskResults.isEmpty) &&
        (!showsLists || listResults.isEmpty) &&
        (!showsNotes || noteResults.isEmpty)
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
                    } else {
                        Button {
                            if let task = result.task {
                                selectedTask = task
                            } else if let note = result.note {
                                selectedNote = note
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

    private func activeTaskCount(for area: Area) -> Int {
        (area.tasks ?? []).filter { !$0.isDone && !$0.isCancelled }.count
    }

    private func activeTaskCount(for project: Project) -> Int {
        (project.tasks ?? []).filter { !$0.isDone && !$0.isCancelled }.count
    }
}

private enum iOSSearchScope: String, CaseIterable, Identifiable {
    case all
    case tasks
    case lists
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .tasks: return "Tasks"
        case .lists: return "Lists"
        case .notes: return "Notes"
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

private struct iOSSearchResult: Identifiable {
    enum Kind {
        case task
        case list
        case note
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
    var listRoute: iOSListRoute?
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $note.content)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                    .padding(12)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(note.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
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
        }
        .preferredColorScheme(.dark)
    }
}
#endif
