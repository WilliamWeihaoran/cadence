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
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Habit.order) private var habits: [Habit]

    /// iOS Search draws a page row in the tint the sidebar draws that destination in, override
    /// included — the same `CadenceSidebarTint` reading `iOSRootSidebar` uses. It read
    /// `destination.tint` (the *default*) until T-244, which agreed on hue with the sidebar and
    /// silently disagreed with it for anyone who had retinted a row.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = CadencePreferenceKeys.emptySidebarPreference

    @State private var query = ""
    @State private var selectedTask: AppTask?
    @State private var selectedNote: Note?
    @State private var selectedEvent: iOSCalendarEventSelection?
    @State private var calendarSearchEvents: [EKEvent] = []
    @State private var scope: iOSSearchScope = .all
    @State private var includeCompletedTasks = false
    /// Pushes are driven by these two rather than by `NavigationLink(value:)`.
    ///
    /// A whole result group is a *single* `List` row (`iOSSearchResultGroup` draws the eyebrow and
    /// one card around N rows), and `List` gives a row containing navigation links one row-wide
    /// activation that fires **every** link in it. Tapping "Today" in PAGES pushed Today, All
    /// Tasks, Focus, Inbox and Calendar in order and left you on Calendar; tapping the first list
    /// result pushed both lists and left you on the second. The `Button` rows in the same group
    /// were always correct, because `List` does not extend row activation to plain buttons.
    @State private var pushedListRoute: iOSListRoute?
    @State private var pushedDestination: CadenceFeatureDestination?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// The scope picker's "Completed" toggle is a user setting, not a second inclusion policy —
    /// which tasks are searchable at all is `CadenceTaskSearchSupport`'s to say (T-377).
    private var searchableTasks: [AppTask] {
        tasks.filter { CadenceTaskSearchSupport.isSearchable($0, includingCompleted: includeCompletedTasks) }
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
        let candidates = searchableFeatureDestinations.map { destination in
            iOSSearchFeatureCandidate(
                title: destination.title,
                subtitle: destination.subtitle,
                detail: destination.searchSummary,
                icon: destination.systemImage,
                color: Color(hex: CadenceSidebarTint.hex(for: destination, overridesRaw: sidebarTabColorsRaw)),
                destination: destination,
                fields: [destination.title, destination.subtitle, destination.searchSummary, destination.searchAliases]
            )
        }

        if isSearching {
            return iOSSearchIndexSupport.rankedResults(candidates.compactMap { candidate in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: candidate.fields) else {
                    return nil
                }
                return candidate.result(score: score)
            })
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

        return suggested.map { taskResult($0, score: 0) }
    }

    /// Which lists search can reach is `CadenceListSearchSupport`'s decision, not this view's —
    /// the T-378 rule and the evidence for it are recorded there. This screen used to pre-filter
    /// to `isActive`, so a completed or archived list was findable on the Mac and invisible here
    /// even though tapping one would have opened its detail page perfectly well.
    private var listResults: [iOSSearchResult] {
        let listItems = areas.filter { CadenceListSearchSupport.isSearchable($0, query: trimmedQuery) }.map { area in
            let count = CadenceTaskQuerySupport.openTaskCount(for: area)
            return iOSSearchListCandidate(
                title: area.name.isEmpty ? "Untitled Area" : area.name,
                subtitle: area.context?.name ?? "Area",
                detail: listDetail(lifecycle: CadenceListSearchSupport.lifecycle(of: area), openTaskCount: count),
                icon: area.icon,
                color: Color(hex: area.colorHex),
                route: .area(area.id),
                fields: CadenceListSearchSupport.searchFields(for: area)
            )
        } + projects.filter { CadenceListSearchSupport.isSearchable($0, query: trimmedQuery) }.map { project in
            let count = CadenceTaskQuerySupport.openTaskCount(for: project)
            return iOSSearchListCandidate(
                title: project.name.isEmpty ? "Untitled Project" : project.name,
                subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / "),
                detail: listDetail(lifecycle: CadenceListSearchSupport.lifecycle(of: project), openTaskCount: count),
                icon: project.icon,
                color: Color(hex: project.colorHex),
                route: .project(project.id),
                fields: CadenceListSearchSupport.searchFields(for: project)
            )
        }

        if isSearching {
            return iOSSearchIndexSupport.rankedResults(listItems.compactMap { candidate in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: candidate.fields) else {
                    return nil
                }
                return candidate.result(score: score)
            })
        }

        return Array(listItems.prefix(8)).map { $0.result(score: 0) }
    }

    private var noteResults: [iOSSearchResult] {
        let searchableNotes = notes.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // Task embeds are matched and excerpted under the task's live title, not the copy cached in
        // the note text — see `MarkdownTaskEmbedTitleCache`. Built once per pass, not per note.
        let taskTitles = MarkdownTaskEmbedTitleCache.titles(for: tasks)

        if isSearching {
            return iOSSearchIndexSupport.rankedResults(searchableNotes.compactMap { note in
                let tagText = CadenceSearchTagSupport.text(for: note.sortedTags)
                let content = MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
                guard let score = CadenceSearchMatcher.matchScore(
                    query: trimmedQuery,
                    fields: [note.displayTitle, content, noteSubtitle(note), tagText]
                ) else {
                    return nil
                }
                return noteResult(note, score: score, taskTitles: taskTitles)
            })
        }

        return searchableNotes.prefix(8).map { noteResult($0, score: 0, taskTitles: taskTitles) }
    }

    private var progressResults: [iOSSearchResult] {
        let candidates = goals.filter { $0.status != .done }.map { goal in
            let summary = GoalContributionResolver.summary(for: goal)
            return iOSSearchResult(
                // The destination is the Goals *page* — this row navigates there rather than to
                // the goal — so it cannot supply the identity, and neither can `.feature(.habits)`
                // below. That is the whole reason `iOSSearchResult.id` is stored rather than
                // derived from `destination`: this one section merges two tables behind one
                // destination apiece, so deriving would give every goal `page-goals`.
                id: CadenceSearchIdentity.goal(goal.id),
                destination: .feature(.goals),
                title: goal.title.isEmpty ? "Untitled Goal" : goal.title,
                subtitle: goal.parentGoal?.title ?? goal.context?.name ?? goal.kind.label,
                detail: summary.percentLabel,
                icon: goal.icon,
                color: Color(hex: goal.colorHex),
                score: CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: [goal.title, goal.desc, goal.parentGoal?.title ?? "", goal.context?.name ?? ""]) ?? 0
            )
        } + habits.map { habit in
            iOSSearchResult(
                id: CadenceSearchIdentity.habit(habit.id),
                destination: .feature(.habits),
                title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                subtitle: habit.goal?.title ?? habit.context?.name ?? habit.frequencySummary,
                detail: habit.isDueToday ? "Due today" : habit.frequencySummary,
                icon: "flame.fill",
                color: Color(hex: habit.colorHex),
                score: CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: [habit.title, habit.goal?.title ?? "", habit.context?.name ?? "", habit.frequencySummary]) ?? 0
            )
        }

        if isSearching {
            return iOSSearchIndexSupport.rankedResults(candidates.filter { $0.score > 0 })
        }

        return Array(candidates.prefix(8))
    }

    private var eventResults: [iOSSearchResult] {
        if isSearching {
            return iOSSearchIndexSupport.rankedResults(calendarSearchEvents.compactMap { event in
                let fields = eventSearchFields(for: event)
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: fields) else {
                    return nil
                }
                return eventResult(event, score: score)
            })
        }

        return calendarSearchEvents.prefix(8).map { eventResult($0, score: 0) }
    }

    /// Fields and aliases come from `CadenceTaskSearchSupport`; this view keeps the row. The list
    /// this used to build by hand had no lifecycle aliases and no tag slugs, so *done*,
    /// *completed* and a hand-set slug found tasks on the Mac and nothing here (T-377).
    private var rankedTaskResults: [iOSSearchResult] {
        iOSSearchIndexSupport.rankedResults(searchableTasks.compactMap { task in
            guard let score = CadenceTaskSearchSupport.matchScore(query: trimmedQuery, task: task) else {
                return nil
            }
            return taskResult(task, score: score)
        })
    }

    private func taskResult(_ task: AppTask, score: Int) -> iOSSearchResult {
        iOSSearchResult(
            id: CadenceSearchIdentity.task(task.id),
            destination: .task(task),
            title: TaskTitleSupport.displayTitle(task.title),
            subtitle: taskSubtitle(task),
            detail: taskDetail(task),
            icon: taskIcon(for: CadenceTaskSearchSupport.glyph(for: task)),
            color: Theme.priorityColor(task.priority),
            score: score,
            dueLabel: taskDueLabel(task)
        )
    }

    /// This screen's symbols for the three shared glyph states. A task with a timeline slot drew a
    /// plain `circle` here and `calendar.badge.clock` on the Mac; the two rows may keep their own
    /// vocabulary for done-ness, but not their own idea of which states exist.
    private func taskIcon(for glyph: CadenceTaskSearchGlyph) -> String {
        switch glyph {
        case .scheduled: "calendar.badge.clock"
        case .completed: "checkmark.circle.fill"
        case .active: "circle"
        }
    }

    /// A finished list says so where an active one shows its open-task count: the count is zero or
    /// stale on a list nobody is working, and "Archived" is what the row needs to say instead.
    private func listDetail(lifecycle: CadenceListSearchLifecycle, openTaskCount: Int) -> String {
        guard lifecycle.isActive else { return lifecycle.statusLabel }
        return openTaskCount == 1 ? "1 task" : "\(openTaskCount) tasks"
    }

    var body: some View {
        List {
            // No page header. The navigation title and the search field already say
            // "Search", and the standfirst under it ("Find tasks, lists, notes, calendar
            // events, and progress") described the screen you were already looking at.
            Section {
                iOSSearchScopePicker(
                    selection: $scope,
                    includeCompletedTasks: $includeCompletedTasks,
                    showsCompletedToggle: showsTasks
                )
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

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
                resultSection("Goals and Habits", results: progressResults)
            }

            if isSearching && visibleResultsAreEmpty && !(showsEvents && !calendarManager.isAuthorized) {
                iOSEmptyPanel(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a task, note, area, project, event, tag, or section name."
                )
                .frame(minHeight: 220)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tasks, lists, notes, events")
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 10)
        }
        .task(id: calendarSearchRequestID) {
            refreshCalendarSearchEvents()
        }
        // `item:` rather than `for:`. Besides being what the button rows above need, this keeps
        // Search from registering a *second* destination for either type in the iPhone stack,
        // where `iOSCompactHomeView` already registers `CadenceFeatureDestination` and a pushed
        // `iOSListsView` registers `iOSListRoute`. Two registrations for one type in one stack is
        // undefined behaviour in SwiftUI, and these were only ever duplicate clones of them.
        .navigationDestination(item: $pushedListRoute) { route in
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
        .navigationDestination(item: $pushedDestination) { destination in
            switch destination {
            case .today:
                iOSTodayView()
            case .allTasks:
                iOSAllTasksView()
            case .focus:
                iOSFocusView()
            case .inbox:
                iOSInboxView()
            case .calendar:
                iOSCalendarView()
            case .notes:
                iOSNotesView()
            case .lists:
                iOSListsView()
            case .goals:
                iOSGoalsView()
            case .habits:
                iOSHabitsView()
            case .search:
                iOSSearchView()
            case .settings:
                iOSSettingsView()
            }
        }
        .sheet(item: $selectedTask) { task in
            iOSTaskInspectorSheet(task: task) { selectedTask = nil }
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
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrowLabel(text: "Calendar Events")
                        .padding(.horizontal, 4)

                    HStack(alignment: .top, spacing: 12) {
                        iOSIconTile(
                            systemImage: calendarManager.isDenied ? "calendar.badge.exclamationmark" : "calendar",
                            color: calendarManager.isDenied ? Theme.amber : Theme.blue
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(calendarManager.isDenied ? "Calendar access is disabled" : "Calendar access is off")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)

                            Text(calendarManager.isDenied ? "Enable Calendar access in Settings to include Apple Calendar events in search." : "Allow Calendar access to search and edit Apple Calendar events from Cadence.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            iOSActionButton(
                                title: calendarManager.isDenied ? "Open Settings" : "Allow Calendar Access",
                                systemImage: calendarManager.isDenied ? "gearshape.fill" : "checkmark.shield.fill",
                                role: .primary,
                                size: .compact,
                                tint: calendarManager.isDenied ? Theme.amber : Theme.blue
                            ) {
                                if calendarManager.isDenied {
                                    openAppSettings()
                                } else {
                                    Task { await calendarManager.requestAccess() }
                                }
                            }
                            .padding(.top, 2)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var visibleResultsAreEmpty: Bool {
        (!showsTasks || taskResults.isEmpty) &&
        (!showsLists || listResults.isEmpty) &&
        (!showsNotes || noteResults.isEmpty) &&
        (!showsEvents || eventResults.isEmpty) &&
        (!showsProgress || pageResults.isEmpty && progressResults.isEmpty)
    }

    private var searchableFeatureDestinations: [CadenceFeatureDestination] {
        CadenceFeatureDestination.allCases.filter { $0 != .search }
    }

    @ViewBuilder
    private func resultSection(_ title: String, results: [iOSSearchResult]) -> some View {
        if !results.isEmpty {
            let visible = Array(results.prefix(isSearching ? 24 : 8))
            Section {
                iOSSearchResultGroup(title: title, count: visible.count) { index in
                    searchResultRow(visible[index])
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// One button, one exhaustive switch. This was three near-identical `Button`s selected by an
    /// ordered chain of `if let`s over five optionals — a shape that could not fail loudly if a
    /// result ever carried two of them.
    private func searchResultRow(_ result: iOSSearchResult) -> some View {
        Button {
            open(result.destination)
        } label: {
            iOSSearchResultRow(result: result)
        }
        .buttonStyle(.iosPressable)
    }

    private func open(_ destination: iOSSearchResult.Destination) {
        switch destination {
        case .task(let task):
            selectedTask = task
        case .note(let note):
            selectedNote = note
        case .event(let event):
            selectedEvent = iOSCalendarEventSelection(event: event)
        case .list(let route):
            pushedListRoute = route
        case .feature(let featureDestination):
            pushedDestination = featureDestination
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
        if task.estimatedMinutes > 0 {
            parts.append(CadenceTaskPresentationSupport.estimateLabel(for: task))
        }
        return parts.joined(separator: " · ")
    }

    /// Carried beside `detail` rather than inside it — see `iOSSearchResult.dueLabel`.
    private func taskDueLabel(_ task: AppTask) -> String? {
        guard !task.dueDate.isEmpty else { return nil }
        return "Due \(CadenceTaskPresentationSupport.dueDateLabel(for: task))"
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
            // Occurrence-scoped. `rawIdentifier` is shared by every occurrence of a recurring
            // series, and a week of standups scores and titles identically — so the raw one is not
            // a tie-break here at all. See `CadenceSearchIdentity.event`.
            id: CadenceSearchIdentity.event(CadenceEventNoteSupport.identifier(for: event)),
            destination: .event(event),
            title: iOSCalendarEventSupport.title(for: event),
            subtitle: event.calendar?.title ?? "Apple Calendar",
            detail: eventDetail(event),
            icon: event.isAllDay ? "calendar.badge.clock" : "calendar",
            color: iOSCalendarEventSupport.color(for: event.calendar),
            score: score
        )
    }

    /// The shared spelling, not one of three (T-239). This switch was the detail form's better
    /// half — it is where "Daily / <key>" and the container name for a `.list` note come from —
    /// but its `.permanent` said "Permanent note", the retired name of the Notepad tab, and this
    /// string is scored as a search *field*, so the notepad did not match the app's own word for
    /// it. See `NoteReferencePanelSupport.noteKindDetail`.
    private func noteSubtitle(_ note: Note) -> String {
        NoteReferencePanelSupport.noteKindDetail(note)
    }

    private func noteResult(_ note: Note, score: Int, taskTitles: [UUID: String]) -> iOSSearchResult {
        iOSSearchResult(
            id: CadenceSearchIdentity.note(note.id),
            destination: .note(note),
            title: note.displayTitle,
            subtitle: noteSubtitle(note),
            detail: excerpt(MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)),
            icon: "doc.text",
            color: Theme.purple,
            score: score
        )
    }

    private func excerpt(_ value: String) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(from: value, limit: 120)
    }

}

#endif
