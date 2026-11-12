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
    /// [[T-8791]]. Optional because a host that never asks (a preview, a future surface) need not
    /// provide one; `iOSRootView` does, and only its Cmd+K calls `request()`.
    @Environment(CadenceSearchFocusRequest.self) private var searchFocusRequest: CadenceSearchFocusRequest?
    @FocusState private var isSearchFieldFocused: Bool
    /// A request is honoured only by a Search that is on screen, so one kept alive on a hidden tab
    /// cannot consume it.
    @State private var isOnScreen = false
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
    /// **The hardware keyboard's highlight** ([[T-11196]] (2)): the row Up/Down rest on and Return
    /// opens, as Cmd+K's arrows do on the Mac. `nil` until an arrow key is pressed -- a touch screen
    /// has no highlight to show, so nothing is drawn for a reader who never reaches for the keys
    /// -- and cleared with the result set it pointed into.
    @State private var highlightedResultID: String?

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

    /// The sections this scope narrows to, in the one shared display order ([[T-8765]]).
    ///
    /// The chips are the filter and the sections are the vocabulary, and they are deliberately
    /// not the same list: **Lists** covers Areas and Projects, **Notes** covers Event Notes and
    /// Notes. `iOSSearchScope.sections` owns that mapping so the body below can iterate the
    /// shared order rather than spelling five `if shows…` gates of its own.
    private var visibleSections: [CadenceSearchSection] {
        scope.sections
    }

    private var showsTasks: Bool {
        scope.shows(.tasks)
    }

    private var showsEvents: Bool {
        scope.shows(.events)
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
                fields: destination.searchFields
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

        // The idle rule is shared with Cmd+K ([[T-8764]]): today's and overdue open work, due date
        // then manual order then identity (T-498).
        let suggested = CadenceSearchIdleSuggestions.tasks(
            searchableTasks,
            today: DateFormatters.todayKey(),
            limit: CadenceSearchIdleSuggestions.limit
        )

        return suggested.map { taskResult($0, score: 0) }
    }

    /// Which lists search can reach is `CadenceListSearchSupport`'s decision, not this view's —
    /// the T-378 rule and the evidence for it are recorded there. This screen used to pre-filter
    /// to `isActive`, so a completed or archived list was findable on the Mac and invisible here
    /// even though tapping one would have opened its detail page perfectly well.
    private var listResults: [CadenceSearchSection: [iOSSearchResult]] {
        let searchableAreas = areas.filter { CadenceListSearchSupport.isSearchable($0, query: trimmedQuery) }
        let searchableProjects = projects.filter { CadenceListSearchSupport.isSearchable($0, query: trimmedQuery) }

        if isSearching {
            let candidates = searchableAreas.map(listCandidate(for:)) + searchableProjects.map(listCandidate(for:))
            let matched = candidates.compactMap { candidate -> (CadenceSearchSection, iOSSearchResult)? in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: candidate.fields) else {
                    return nil
                }
                return (candidate.section, candidate.result(score: score))
            }
            return [.areas, .projects].reduce(into: [:]) { out, section in
                out[section] = iOSSearchIndexSupport.rankedResults(
                    matched.filter { $0.0 == section }.map(\.1)
                )
            }
        }

        // Areas then projects, each in the user's arrangement, ties broken by identity (T-498) --
        // the order Cmd+K's idle Areas and Projects read too ([[T-11194]]).
        //
        // **One window of eight across both kinds, split afterwards** ([[T-8765]]). The two are
        // separate sections now, but a window apiece would have doubled the idle suggestions on a
        // screen that shows five other sections under them; the rows a reader sees idle are the
        // same rows as before, under two headings instead of one.
        let suggested = CadenceSearchIdleSuggestions.lists(
            areas: searchableAreas,
            projects: searchableProjects,
            limit: CadenceSearchIdleSuggestions.limit
        )
        return [
            .areas: suggested.areas.map { listCandidate(for: $0).result(score: 0) },
            .projects: suggested.projects.map { listCandidate(for: $0).result(score: 0) }
        ]
    }

    // [[T-8526]]: the facts are `CadenceListSearchSupport.rowFacts`'s, the same Cmd+K draws; this
    // row keeps its own two lines and separators.
    private func listCandidate(for area: Area) -> iOSSearchListCandidate {
        let facts = CadenceListSearchSupport.rowFacts(for: area)
        return iOSSearchListCandidate(
            title: CadenceListSearchSupport.resultTitle(for: area),
            subtitle: facts.containers.joined(separator: " / "),
            detail: facts.status.joined(separator: " · "),
            icon: area.icon,
            color: Color(hex: area.colorHex),
            route: .area(area.id),
            fields: CadenceListSearchSupport.searchFields(for: area)
        )
    }

    private func listCandidate(for project: Project) -> iOSSearchListCandidate {
        let facts = CadenceListSearchSupport.rowFacts(for: project)
        return iOSSearchListCandidate(
            title: CadenceListSearchSupport.resultTitle(for: project),
            subtitle: facts.containers.joined(separator: " / "),
            detail: facts.status.joined(separator: " · "),
            icon: project.icon,
            color: Color(hex: project.colorHex),
            route: .project(project.id),
            fields: CadenceListSearchSupport.searchFields(for: project)
        )
    }

    /// **Event notes have their own section** ([[T-8765]]). They used to be mixed into Notes here
    /// while the Mac palette drew them apart, so one note read "Notes" on the phone and "Event
    /// Notes" on the Mac. The split is `Note.kind == .meeting`, which is the Mac's gate
    /// (`GlobalSearchIndexSupport.eventNoteResults`), not a second rule.
    private var eventNoteResults: [iOSSearchResult] {
        noteSectionResults(matching: { $0.kind == .meeting })
    }

    /// The **Notes** section proper: everything that is not an event note.
    private var noteResults: [iOSSearchResult] {
        noteSectionResults(matching: { $0.kind != .meeting })
    }

    /// One builder for both note sections. **An idle window apiece**, as the Mac caps
    /// `.meetingNotes` and `.notes` separately: the two sections answer different questions, and
    /// a shared window would have let a busy week of event notes crowd out every ordinary one.
    private func noteSectionResults(matching isMember: (Note) -> Bool) -> [iOSSearchResult] {
        let searchableNotes = notes.filter { CadenceSearchIdleSuggestions.hasVisibleText($0) && isMember($0) }
        // Task embeds are matched and excerpted under the task's live title, not the copy cached in
        // the note text — see `MarkdownTaskEmbedTitleCache`. Built once per pass, not per note.
        let taskTitles = MarkdownTaskEmbedTitleCache.titles(for: tasks)

        if isSearching {
            return iOSSearchIndexSupport.rankedResults(searchableNotes.compactMap { note in
                let tagText = CadenceSearchTagSupport.text(for: note.sortedTags)
                let content = CadenceSearchNoteText.body(of: note, taskTitles: taskTitles)
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

        // Most recently edited first, ties broken by identity (T-498) -- the rule Cmd+K shares
        // ([[T-8764]]).
        return CadenceSearchIdleSuggestions.notes(
            searchableNotes,
            limit: CadenceSearchIdleSuggestions.limit
        ).map { noteResult($0, score: 0, taskTitles: taskTitles) }
    }

    /// **One lookup from section to rows**, so the body above can iterate the shared order
    /// instead of spelling a gate per section ([[T-8765]]).
    ///
    /// `.commands` answers an empty array rather than being left out of the `switch`: it is a
    /// real case of the shared vocabulary that this platform does not draw, and saying so here is
    /// what makes `CadenceSearchSection.touchSections` the single place that decision lives. The
    /// body never asks for it, because `iOSSearchScope.sections` is cut from `touchSections`.
    private func results(for section: CadenceSearchSection) -> [iOSSearchResult] {
        switch section {
        case .commands: return []
        case .pages: return pageResults
        case .areas: return listResults[.areas] ?? []
        case .projects: return listResults[.projects] ?? []
        case .tasks: return taskResults
        case .events: return eventResults
        case .meetingNotes: return eventNoteResults
        case .notes: return noteResults
        }
    }

    private var eventResults: [iOSSearchResult] {
        if isSearching {
            // [[T-14622]]: ranked by the Events comparator Cmd+K shares -- a score tie breaks on
            // time, upcoming soonest first -- not the generic funnel, whose identity leg listed a
            // recurring series from its oldest occurrence in the 60-days-back window.
            return iOSSearchIndexSupport.rankedEventResults(calendarSearchEvents.compactMap { event in
                let fields = eventSearchFields(for: event)
                guard let score = CadenceSearchMatcher.matchScore(query: trimmedQuery, fields: fields) else {
                    return nil
                }
                return (event, eventResult(event, score: score))
            }, now: Date())
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
            icon: CadenceTaskSearchSupport.glyph(for: task).systemImage,
            color: Theme.priorityColor(task.priority),
            score: score,
            dueLabel: taskDueLabel(task)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            searchList
                .onChange(of: highlightedResultID) { _, id in
                    scrollToHighlighted(id, proxy: proxy)
                }
        }
    }

    private var searchList: some View {
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

            // **The shared section vocabulary and the shared order** ([[T-8765]]). This was five
            // `if shows…` blocks over five string literals — "Pages", "Tasks", "Lists", "Notes",
            // "Calendar Events" — in an order of their own. Both the names and the order are
            // `CadenceSearchSection`'s now, so the phone and the Mac palette name a found thing
            // the same way; the chips above stay iOS-only, which is the owner's call and the
            // reason this iterates `scope.sections` rather than every case.
            ForEach(visibleSections) { section in
                // Immediately above Calendar Events, where it was: the card explains why that one
                // section is empty, so it has to arrive before the heading it is about.
                if section == .events {
                    calendarAccessSection
                }
                resultSection(section.title, results: results(for: section))
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
            // are answers to a *failed* search, and nothing has been searched yet. The Mac palette
            // never reaches this state: idle, it always lists its commands and pages ([[T-14191]]).
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: CadenceSearchFieldPrompt.text(offersCommands: false))
        .searchFocused($isSearchFieldFocused)
        .onAppear {
            isOnScreen = true
            honourSearchFocusRequest()
        }
        .onDisappear { isOnScreen = false }
        .onChange(of: searchFocusRequest?.generation) { _, _ in
            honourSearchFocusRequest()
        }
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
            highlightedResultID = nil
        }
        // [[T-11196]] (2): Up/Down/Return from an iPad's hardware keyboard, Cmd+K's keys. On the
        // view that carries `.searchable`, so the field keeps every key it types with -- these
        // three are the only ones taken, and a single-line search field has no use for Up/Down.
        // `onKeyPress` hears hardware keys only, so a touch keyboard's Search key is not one.
        .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
            handleKeyboardPress(press.key)
        }
        // Return in the field reaches `.searchable`'s submit rather than a key press. It opens a
        // row only once the arrows have highlighted one: the touch keyboard's Search key submits
        // here too, and on a phone it has only ever meant "done typing".
        .onSubmit(of: .search) {
            guard highlightedResultID != nil else { return }
            submitHighlightedResult()
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

    /// Raise the field if Cmd+K asked for it ([[T-8791]]). Deferred a turn, as the other focus
    /// requests here are: set synchronously in `onAppear`, the search bar is not on screen yet.
    private func honourSearchFocusRequest() {
        guard isOnScreen, searchFocusRequest?.take() == true else { return }
        DispatchQueue.main.async { isSearchFieldFocused = true }
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
            // [[T-9663]]: the Notes tab's editor, with its Export, tags, AI actions and
            // Move/Delete, not a thinner sheet of Search's own. Titled as the row was ([[T-8523]]).
            iOSNoteEditorCover(reachedFrom: note, title: NoteReferencePanelSupport.searchTitle(note))
        }
    }

    @ViewBuilder
    private var calendarAccessSection: some View {
        // The title, glyph and button are the Calendar page's and Settings' words, by way of the
        // one notice type (T-5954), rather than a third spelling: this card said "Calendar access
        // is off" / "Allow Calendar Access" where the Calendar tab's bar above the same missing
        // events said "Connect Apple Calendar" / "Allow Access". The offer's sentence stays
        // Search's own, because it says what the missing access costs *here*; the denied one is
        // the notice's ([[T-10050]]), because it says where the button beside it lands.
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
                        .padding(.horizontal, SectionEyebrowLabel.cardListInset)

                    layout {
                        iOSIconTile(
                            systemImage: notice.systemImage,
                            color: notice == .denied ? Theme.amber : Theme.blue
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice.title)
                                .cadenceFont(.bodyText, weight: .semibold)
                                .foregroundStyle(Theme.text)

                            Text(notice == .denied ? notice.detail(on: .mobile) : "Allow Calendar access to search and edit Apple Calendar events from Cadence.")
                                .cadenceFont(.fieldLabel, weight: .regular)
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            iOSActionButton(
                                title: notice.actionTitle(on: .mobile),
                                systemImage: notice.mobileButtonSystemImage,
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
        visibleSections.allSatisfy { results(for: $0).isEmpty }
    }

    /// The one Pages order both surfaces draw ([[T-11194]]); the idle five are its first five.
    private var searchableFeatureDestinations: [CadenceFeatureDestination] {
        CadenceFeatureDestination.searchPages
    }

    /// How many results a section lists before its count row. Unchanged by T-3089 — the cap was
    /// never the complaint, its silence was.
    private var sectionResultCap: Int {
        isSearching ? 24 : 8
    }

    /// The rows a section draws and how many it is holding back. One answer for the drawing and
    /// the keyboard walk, so the arrows cannot reach a row the list is not showing ([[T-11196]]).
    private func visibleSlice(_ title: String, results: [iOSSearchResult]) -> (visible: [iOSSearchResult], hidden: Int?) {
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
        return (visible, hidden)
    }

    @ViewBuilder
    private func resultSection(_ title: String, results: [iOSSearchResult]) -> some View {
        if !results.isEmpty {
            let (visible, hidden) = visibleSlice(title, results: results)
            let continuationID = CadenceSearchKeyboardHighlight.continuationID(forSection: title)
            Section {
                iOSSearchResultGroup(
                    title: title,
                    count: visible.count,
                    continuation: hidden.flatMap { hidden in
                        CadenceSearchResultCap.continuationLabel(hidden: hidden).map { label in
                            iOSSearchResultContinuation(
                                label: label,
                                isHighlighted: highlightedResultID == continuationID
                            ) {
                                expandedSections.insert(title)
                            }
                        }
                    }
                ) { index in
                    searchResultRow(visible[index])
                }
                .id(Self.sectionScrollID(title))
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
            iOSSearchResultRow(result: result, isHighlighted: highlightedResultID == result.id)
        }
        .buttonStyle(.iosPressable)
    }

    // MARK: Hardware keyboard ([[T-11196]] (2))

    /// One stop on the arrow-key path, in draw order: a result, or a capped section's
    /// "N more results" row, exactly as Cmd+K's `GlobalSearchKeyboardRow` walks it.
    private struct KeyboardStop {
        let id: String
        let sectionTitle: String
        /// `nil` for a continuation row, which reveals its section rather than opening anything.
        let result: iOSSearchResult?
    }

    private var keyboardStops: [KeyboardStop] {
        visibleSections.flatMap { section -> [KeyboardStop] in
            let all = results(for: section)
            guard !all.isEmpty else { return [] }
            let (visible, hidden) = visibleSlice(section.title, results: all)
            let rows = visible.map { KeyboardStop(id: $0.id, sectionTitle: section.title, result: $0) }
            guard let hidden, CadenceSearchResultCap.continuationLabel(hidden: hidden) != nil else { return rows }
            return rows + [KeyboardStop(
                id: CadenceSearchKeyboardHighlight.continuationID(forSection: section.title),
                sectionTitle: section.title,
                result: nil
            )]
        }
    }

    private func handleKeyboardPress(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow, .downArrow:
            let ids = keyboardStops.map(\.id)
            guard !ids.isEmpty else { return .ignored }
            highlightedResultID = CadenceSearchKeyboardHighlight.engagedMove(
                key == .upArrow ? .up : .down,
                currentID: highlightedResultID,
                ids: ids
            )
            return .handled
        case .return:
            return submitHighlightedResult() ? .handled : .ignored
        default:
            return .ignored
        }
    }

    /// Return on the highlighted row, or on the first when none is highlighted yet: a result opens
    /// as a tap would, a continuation row reveals its section in place and moves the highlight to
    /// the first row it revealed -- Cmd+K's Return ([[T-4320]]).
    @discardableResult
    private func submitHighlightedResult() -> Bool {
        let stops = keyboardStops
        guard let targetID = CadenceSearchKeyboardHighlight.submitTarget(
            highlightedID: highlightedResultID,
            ids: stops.map(\.id)
        ), let stop = stops.first(where: { $0.id == targetID }) else { return false }
        if let result = stop.result {
            open(result.destination)
        } else {
            let revealedFrom = stops.filter { $0.sectionTitle == stop.sectionTitle && $0.result != nil }.count
            expandedSections.insert(stop.sectionTitle)
            let section = visibleSections.first { $0.title == stop.sectionTitle }
            let revealed = section.map { results(for: $0) } ?? []
            highlightedResultID = revealed.indices.contains(revealedFrom) ? revealed[revealedFrom].id : nil
        }
        return true
    }

    private static func sectionScrollID(_ title: String) -> String {
        "search-section-\(title)"
    }

    /// Brings the highlighted row's group on screen. A whole group is one `List` row (see
    /// `iOSSearchResultGroup`), and `scrollTo` reaches rows, not views inside one.
    private func scrollToHighlighted(_ id: String?, proxy: ScrollViewProxy) {
        guard let id, let stop = keyboardStops.first(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(Self.sectionScrollID(stop.sectionTitle))
        }
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
            pastDays: CadenceCalendarEventSearchSupport.windowPastDays,
            futureDays: CadenceCalendarEventSearchSupport.windowFutureDays
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
    /// [[T-15491]]: the builder's words carry their own "Due" / "Overdue".
    private func taskDueLabel(_ task: AppTask) -> String? {
        CadenceTaskPresentationSupport.dueDateLabel(for: task)
    }

    /// The shared ranking list Cmd+K reads too ([[T-12803]]); this view supplies only its row's
    /// day-and-time line.
    private func eventSearchFields(for event: EKEvent) -> [String] {
        CadenceCalendarEventSearchSupport.rankingFields(for: event, dayTimeLine: eventDetail(event))
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
            icon: CadenceSearchEventGlyph.systemImage,
            color: iOSCalendarEventSupport.color(for: event.calendar),
            score: score
        )
    }

    /// The shared spelling, not one of three (T-239). This switch was the detail form's better
    /// half — it is where "Daily / <day>" and the container name for a `.list` note come from —
    /// but its `.permanent` said "Permanent note", the retired name of the Notepad tab, and this
    /// string is scored as a search *field*, so the notepad did not match the app's own word for
    /// it. See `NoteReferencePanelSupport.noteKindDetail`.
    ///
    /// An event note is the exception ([[T-11195]] (c)): it sits in its own Event Notes section,
    /// so it names the day and time Cmd+K names, joined in this screen's ` · `, not the kind again.
    private func noteSubtitle(_ note: Note) -> String {
        guard note.kind == .meeting else { return NoteReferencePanelSupport.noteKindDetail(note) }
        return CadenceSearchEventNoteSupport.subtitleFacts(for: note).joined(separator: " · ")
    }

    private func noteResult(_ note: Note, score: Int, taskTitles: [UUID: String]) -> iOSSearchResult {
        iOSSearchResult(
            id: CadenceSearchIdentity.note(note.id),
            destination: .note(note),
            title: NoteReferencePanelSupport.searchTitle(note),
            subtitle: noteSubtitle(note),
            detail: CadenceSearchNoteExcerpt.text(for: note, taskTitles: taskTitles),
            icon: "doc.text",
            color: Theme.purple,
            score: score
        )
    }

}

#endif
