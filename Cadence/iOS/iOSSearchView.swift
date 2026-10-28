#if os(iOS)
import EventKit
import SwiftData
import SwiftUI
import UIKit

struct iOSSearchView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(iOSCalendarManager.self) private var calendarManager

    @Query(sort: \AppTask.createdAt, order: .reverse) private var tasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

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
    /// Persisted since T-1476, and shared in spelling with the Mac palette's toggle. It was a
    /// plain `@State` for as long as it existed, so it reset on every rebuild of this view and
    /// every launch — tolerable while the default *included* completed work and the toggle was a
    /// rare narrowing, and a constant papercut now that the default excludes it.
    @AppStorage(CadencePreferenceKeys.searchIncludesCompletedTasks) private var includeCompletedTasks = false
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
    /// Which sections the reader has expanded past `sectionResultCap`, keyed by section title.
    ///
    /// Scoped to one result set and cleared by `resultSetIdentity` below: the 38 results a
    /// section was withholding are a fact about *this* query, and a section left expanded would
    /// hand the next search an uncapped list that nobody asked for.
    @State private var expandedSections: Set<String> = []

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

    /// The **More** chip's scope. It gated two sections — Pages, and the "Goals and Habits" one
    /// that merged `Goal` and `Habit` behind a destination apiece — and T-2076 took the second
    /// away with the two destinations. The chip stays, because Pages is what a reader looking for
    /// a *screen* rather than a row is searching for, and it is the one section nothing else
    /// shows.
    private var showsProgress: Bool {
        scope == .all || scope == .progress
    }

    /// Everything that changes which results a section holds. Narrower than
    /// `calendarSearchRequestID` on one axis and wider on another: the Completed toggle rewrites
    /// the Tasks section without touching EventKit, and an EventKit store bump does not invalidate
    /// a reader's decision to expand the Tasks section.
    private var resultSetIdentity: String {
        [
            trimmedQuery,
            scope.rawValue,
            includeCompletedTasks ? "completed" : "active"
        ].joined(separator: "|")
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

        // Due date, then the user's manual order, then identity (T-498). `order` is per-list, so
        // two tasks due the same day in two different lists tie on both legs routinely — and a tie
        // at the eighth row decides *membership*, not only arrangement.
        let today = DateFormatters.todayKey()
        let suggested = CadenceSearchSuggestionWindow.take(
            searchableTasks.filter {
                !$0.isCancelled &&
                !$0.isDone &&
                ($0.scheduledDate == today || $0.dueDate <= today && !$0.dueDate.isEmpty)
            },
            limit: 8,
            identity: { CadenceSearchIdentity.task($0.id) },
            orderedBefore: { lhs, rhs in
                if lhs.dueDate != rhs.dueDate {
                    if lhs.dueDate.isEmpty { return false }
                    if rhs.dueDate.isEmpty { return true }
                    return lhs.dueDate < rhs.dueDate
                }
                return lhs.order < rhs.order
            }
        )

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
                title: area.name.isEmpty ? CadenceTitleNormalization.defaultAreaName : area.name,
                subtitle: area.context?.name ?? "Area",
                detail: listDetail(lifecycle: CadenceListSearchSupport.lifecycle(of: area), openTaskCount: count),
                icon: area.icon,
                color: Color(hex: area.colorHex),
                route: .area(area.id),
                suggestionOrder: area.order,
                fields: CadenceListSearchSupport.searchFields(for: area)
            )
        } + projects.filter { CadenceListSearchSupport.isSearchable($0, query: trimmedQuery) }.map { project in
            let count = CadenceTaskQuerySupport.openTaskCount(for: project)
            return iOSSearchListCandidate(
                title: project.name.isEmpty ? CadenceTitleNormalization.defaultProjectName : project.name,
                subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / "),
                detail: listDetail(lifecycle: CadenceListSearchSupport.lifecycle(of: project), openTaskCount: count),
                icon: project.icon,
                color: Color(hex: project.colorHex),
                route: .project(project.id),
                suggestionOrder: project.order,
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

        // Areas then projects, each in the user's arrangement, ties broken by identity (T-498).
        // `Area.order` and `Project.order` both default to 0, so the `@Query` sort this used to
        // prefix straight off is partial for every list made outside the reorder UI.
        return CadenceSearchSuggestionWindow.take(
            listItems,
            limit: 8,
            identity: \.identity,
            orderedBefore: { $0.suggestionRank < $1.suggestionRank }
        ).map { $0.result(score: 0) }
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
                    fields: [NoteReferencePanelSupport.searchTitle(note), content, noteSubtitle(note), tagText]
                        + NoteReferencePanelSupport.searchKeyFields(note)
                ) else {
                    return nil
                }
                return noteResult(note, score: score, taskTitles: taskTitles)
            })
        }

        // Most recently edited first, ties broken by identity (T-498). Two notes share an
        // `updatedAt` whenever one write touched both — a migration pass, an import, a bulk tag
        // edit — which is exactly when eight suggestions get cut out of a partial order.
        return CadenceSearchSuggestionWindow.take(
            searchableNotes,
            limit: 8,
            identity: { CadenceSearchIdentity.note($0.id) },
            orderedBefore: { $0.updatedAt > $1.updatedAt }
        ).map { noteResult($0, score: 0, taskTitles: taskTitles) }
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

            if isSearching && visibleResultsAreEmpty && !calendarAccessCardReplacesNoResults {
                iOSEmptyPanel(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    subtitle: CadenceEmptyStateCopy.searchWithheldCompletedTasks(count: withheldCompletedTaskCount)
                        ?? "Try a task, note, area, project, event, tag, or section name."
                )
                .frame(minHeight: 220)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // T-5013(b). The **idle** half, which had nothing at all. The panel above is gated on
            // `isSearching`, and `resultSection` draws nothing for an empty array, so narrowing to
            // Notes / Lists / Events with nothing to suggest -- a new store, or no events in the
            // window -- left the scope picker sitting over blank space.
            //
            // A line, not the panel: the panel's 220pt and its "try a tag or section name" advice
            // are answers to a *failed* search, and nothing has been searched yet. The Mac answers
            // the same idle state in `GlobalSearchEmptyState`, which has always had one.
            //
            // `calendarAccessCardReplacesNoResults` is honoured here for the same reason the panel
            // honours it ([[T-6113]]): on the Events scope with access off, the access card is the
            // whole answer and a second sentence under it would only repeat.
            if !isSearching && visibleResultsAreEmpty && !calendarAccessCardReplacesNoResults {
                CadenceInlineEmpty(
                    text: CadenceEmptyStateCopy.searchIdleTitle(scopeNoun: scope.idleNoun),
                    surface: .touch
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
        .cadenceScaledTypography()
        .task(id: calendarSearchRequestID) {
            refreshCalendarSearchEvents()
        }
        .onChange(of: resultSetIdentity) { _, _ in
            expandedSections.removeAll()
        }
        // `item:` rather than `for:`. Besides being what the button rows above need, this keeps
        // Search from registering a *second* destination for either type in the iPhone stack,
        // where `iOSCompactTabShell` already registers `CadenceFeatureDestination` and a pushed
        // `iOSListsView` registers `iOSListRoute`. Two registrations for one type in one stack is
        // undefined behaviour in SwiftUI, and these were only ever duplicate clones of them.
        .navigationDestination(item: $pushedListRoute) { route in
            Group {
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
            .cadenceFixedTypography()
        }
        .navigationDestination(item: $pushedDestination) { destination in
            // The shell's one destination view, not a copy of it (T-5308): a hand-kept switch here
            // fell behind T-2072 and pushed the old bare Inbox and All Tasks pages. Still an
            // `item:` registration, because a `for:` one would collide with the stack Search sits in.
            iOSCompactFeatureDestinationView(destination: destination)
            // Destination pages choose their own scope; Search cannot opt them in.
            .cadenceFixedTypography()
        }
        .sheet(item: $selectedTask) { task in
            iOSTaskInspectorSheet(task: task) { selectedTask = nil }
        }
        .sheet(item: $selectedNote) { note in
            iOSHeldNoteSheet(note: note) { selectedNote = nil } content: { note in
                noteSheet(for: note)
            }
            .cadenceFixedTypography()
        }
        .sheet(item: $selectedEvent) { selection in
            iOSCalendarEventEditSheet(event: selection.event)
                .cadenceFixedTypography()
        }
    }

    @ViewBuilder
    private func noteSheet(for note: Note) -> some View {
        if note.kind == .meeting {
            let event = calendarManager.event(for: note)
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
        // The title, glyph and button are the Calendar page's and Settings' words, by way of the
        // one notice type (T-5954), rather than a third spelling: this card said "Calendar access
        // is off" / "Allow Calendar Access" where the Calendar tab's bar above the same missing
        // events said "Connect Apple Calendar" / "Allow Access". The sentence stays Search's own,
        // because it says what the missing access costs *here*.
        if let notice = CadenceCalendarAccessNotice.resolve(
            isAuthorized: calendarManager.isAuthorized,
            isDenied: calendarManager.isDenied
        ) {
            // Geometry here belongs to the enabled page, outside its environment modifier.
            let stacks = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: .enabled)
            let layout = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrowLabel(text: "Calendar Events")
                        .padding(.horizontal, 4)

                    layout {
                        iOSIconTile(
                            systemImage: notice.systemImage,
                            color: notice == .denied ? Theme.amber : Theme.blue
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice.title)
                                .cadenceFont(.bodyText, weight: .semibold)
                                .foregroundStyle(Theme.text)

                            Text(notice == .denied ? "Enable Calendar access in Settings to include Apple Calendar events in search." : "Allow Calendar access to search and edit Apple Calendar events from Cadence.")
                                .cadenceFont(.fieldLabel, weight: .regular)
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            iOSActionButton(
                                title: notice.actionTitle(on: .mobile),
                                systemImage: notice == .denied ? "gearshape.fill" : "checkmark.shield.fill",
                                role: .primary,
                                size: .compact,
                                tint: notice == .denied ? Theme.amber : Theme.blue
                            ) {
                                switch notice.action {
                                case .openSystemSettings:
                                    openAppSettings()
                                case .requestAccess:
                                    Task { await calendarManager.requestAccess() }
                                }
                            }
                            .padding(.top, 2)
                        }

                        if !stacks { Spacer(minLength: 0) }
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

    /// Whether the calendar-access card is the whole answer to an empty search, so the
    /// "No results" panel would only repeat it. True on the **Events** scope alone (T-6113): there
    /// nothing else is searched, and the card says why nothing came back. On **All** the tasks,
    /// lists, notes and pages were searched and matched nothing, and that has to be said; gating
    /// on `showsEvents` left the card as the only thing on screen, reading as if search itself
    /// needed calendar access. The card still draws above the panel on All.
    private var calendarAccessCardReplacesNoResults: Bool {
        scope == .events && !calendarManager.isAuthorized
    }

    /// Finished tasks the query matches that the Completed toggle is holding back ([[T-6975]], the
    /// iOS half of [[T-6971]]). Read only by the "No results" panel, so the extra pass over the
    /// tasks is paid on an empty result set alone. Zero off the scopes that search tasks: the
    /// scope picker hides the Completed toggle there, and the hint would name a control the
    /// screen does not show.
    private var withheldCompletedTaskCount: Int {
        guard showsTasks else { return 0 }
        return CadenceTaskSearchSupport.withheldCompletedMatchCount(
            tasks: tasks,
            query: trimmedQuery,
            includingCompleted: includeCompletedTasks
        )
    }

    private var visibleResultsAreEmpty: Bool {
        (!showsTasks || taskResults.isEmpty) &&
        (!showsLists || listResults.isEmpty) &&
        (!showsNotes || noteResults.isEmpty) &&
        (!showsEvents || eventResults.isEmpty) &&
        (!showsProgress || pageResults.isEmpty)
    }

    private var searchableFeatureDestinations: [CadenceFeatureDestination] {
        CadenceFeatureDestination.allCases.filter { $0 != .search }
    }

    /// How many results a section lists before its count row. Unchanged by T-3089 — the cap was
    /// never the complaint, its silence was.
    private var sectionResultCap: Int {
        isSearching ? 24 : 8
    }

    @ViewBuilder
    private func resultSection(_ title: String, results: [iOSSearchResult]) -> some View {
        if !results.isEmpty {
            let isExpanded = expandedSections.contains(title)
            let visible = Array(results.prefix(CadenceSearchResultCap.visibleCount(
                total: results.count,
                cap: sectionResultCap,
                isExpanded: isExpanded
            )))
            // Both numbers come off the same uncapped array, so the rows and the sentence under
            // them cannot describe different searches.
            let hidden = CadenceSearchResultCap.hiddenCount(
                total: results.count,
                cap: sectionResultCap,
                isExpanded: isExpanded
            )
            Section {
                iOSSearchResultGroup(
                    title: title,
                    count: visible.count,
                    continuation: hidden.flatMap { hidden in
                        CadenceSearchResultCap.continuationLabel(hidden: hidden).map { label in
                            iOSSearchResultContinuation(label: label) {
                                expandedSections.insert(title)
                            }
                        }
                    }
                ) { index in
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
        CadenceTaskSearchSupport.resultSubtitle(for: task)
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

    /// "Sat, Mar 28" in the reference date's year and "Sat, Mar 28, 2027" outside it
    /// (`DateFormatters.absoluteDay`, [[T-6252]]) -- the spelling Cmd+K's event subtitle uses. The
    /// window runs 60 days back to 365 forward, so a recurring event's occurrences a year apart
    /// otherwise read identically. Static so a test can state its reference date.
    static func eventDayLabel(_ startDate: Date, relativeTo referenceDate: Date = Date()) -> String {
        "\(DateFormatters.dayOfWeek.string(from: startDate)), \(DateFormatters.absoluteDay(startDate, relativeTo: referenceDate))"
    }

    private func eventDetail(_ event: EKEvent) -> String {
        let startDate = event.startDate ?? event.occurrenceDate ?? Date()
        let dayLabel = Self.eventDayLabel(startDate)
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
            subtitle: event.calendar?.title ?? CadenceAppleCalendarNaming.unnamedCalendarTitle,
            detail: eventDetail(event),
            icon: event.isAllDay ? "calendar.badge.clock" : "calendar",
            color: iOSCalendarEventSupport.color(for: event.calendar),
            score: score
        )
    }

    /// The shared spelling, not one of three (T-239). This switch was the detail form's better
    /// half — it is where "Daily / <day>" and the container name for a `.list` note come from —
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
            title: NoteReferencePanelSupport.searchTitle(note),
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
