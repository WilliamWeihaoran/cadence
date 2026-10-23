// T-3244: compiled for macOS only. This suite reaches macOS-only app code, and `CadenceTests` also
// builds for an iOS destination. The gate is here, in the file, so the reason is visible where it
// applies.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

struct CadenceCodexFunctionalParityTests {
    @Test func mobileProjectDeadlineUsesTheMacFormatterAndLiveHeaderWiring() throws {
        #expect(DateFormatters.shortDateString(from: "2026-10-14") == "Oct 14")
        #expect(DateFormatters.shortDateString(from: "2027-01-05") == "Jan 5")
        #expect(DateFormatters.shortDateString(from: "not-a-date") == "not-a-date")
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/iOS/iOSListDetailView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct iOSListDetailView: View", in: source))
        #expect(page.contains("projectDueDate: project?.dueDate,"))
        #expect(page.contains("self.project = nil"))
        let header = try #require(CadenceSourceScan.declarationBody("private struct iOSListDetailHeader: View", in: source))
        #expect(header.contains("let projectDueDate: String?"))
        #expect(header.contains("if let projectDueDate, !projectDueDate.isEmpty {"))
        #expect(header.contains("Text(DateFormatters.shortDateString(from: projectDueDate))"))
        #expect(header.contains(".cadenceFont(.metadata, base: 11, weight: .regular)"))
        #expect(header.contains(".cadenceFont(.metadata, base: 10, weight: .regular)"))
        #expect(header.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(header.contains(".accessibilityLabel(\"Deadline \\(DateFormatters.shortDateString(from: projectDueDate))\")"))
        #expect(header.contains("accessibilityLabel: \"Edit list\",\n                    action: onEdit"))
        #expect(!header.contains("relativeDate"))
        #expect(!header.contains("fullShortDate"))
        let mac = try read("Cadence/macOS/Views/ListDetailView.swift")
        #expect(mac.contains("if let project = project, !project.dueDate.isEmpty {"))
        #expect(mac.contains("Text(DateFormatters.shortDateString(from: project.dueDate))"))
    }

    @Test func macNotesUsesFullSharedVocabularyWithoutChangingKindsOrOrder() throws {
        #expect(NotesView.NotesPage.allCases.map(\.vocabulary) == CadenceNotesTabVocabulary.allCases)
        #expect(NotesView.NotesPage.allCases.map(\.title) == ["Daily", "Weekly", "Notepad", "Event Notes"])
        #expect(NotesView.NotesPage.allCases.map(\.noteKind) == [.daily, .weekly, .permanent, .meeting])
        #expect(NoteKind.meeting.rawValue == "meeting")
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/NotesView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("enum NotesPage", in: source))
        #expect(page.contains("var title: String { vocabulary.label }"))
        #expect(source.contains("ForEach(NotesPage.allCases, id: \\.self)"))
        #expect(source.contains("CadenceQuietTabButton(title: page.title,"))
        #expect(!source.contains("usesFullLabels("))
        #expect(!source.contains("shortLabel"))
        for (declaration, tab) in [
            ("DailyNotesPage", "daily"), ("WeeklyNotesPage", "weekly"),
            ("NotepadPage", "notepad"), ("MeetingNotesPage", "meeting")
        ] {
            let body = try #require(CadenceSourceScan.declarationBody("private struct \(declaration): View", in: source))
            #expect(body.contains("NotesListHeader(title: NotesView.NotesPage.\(tab).vocabulary.columnTitle"))
            #expect(!body.contains("NotesListHeader(title: \""))
        }
        let list = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/ListNotesView.swift")
        let section = try #require(CadenceSourceScan.declarationBody("private var eventNoteSection: some View", in: list))
        #expect(section.contains("title: CadenceNotesTabVocabulary.events.columnTitle,"))
        #expect(section.contains("count: filteredEventNotes.count,"))
        #expect(section.contains("isCollapsed: $isEventNotesCollapsed"))
        #expect(section.contains("ListEventNoteSectionRows("))
    }

    @Test func boardEventActionReachesTheExistingProtectedEditor() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let board = try read("Cadence/iOS/iOSCalendarBoardView.swift")
        let editor = try read("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        #expect(board.contains("struct iOSCalendarBoardPlanner: View"))
        #expect(board.contains("private struct iOSCalendarBoardDayColumn: View"))
        #expect(board.contains("@State private var selectedEvent: iOSCalendarEventSelection?"))
        #expect(board.contains("onOpenEvent: { selectedEvent = iOSCalendarEventSelection(event: $0) }"))
        #expect(board.contains("let onOpenEvent: (EKEvent) -> Void"))
        #expect(board.contains("Button {\n                onOpenEvent(item.event)\n            } label: {\n                iOSCalendarBoardEventCard(item: item)"))
        #expect(board.contains(".sheet(item: $selectedEvent) { selection in\n            iOSCalendarEventEditSheet(event: selection.event)"))
        #expect(editor.contains("struct iOSCalendarEventEditSheet: View"))
        #expect(editor.contains("if isEditable {"))
        #expect(editor.contains(".disabled(!isEditable)"))
    }

    @MainActor @Test func boardCardsUseTheRowsSettledStateForAllThreeStyles() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/iOS/iOSBoardCards.swift")
        let card = try #require(CadenceSourceScan.declarationBody("struct iOSBoardTaskCard: View", in: source))
        #expect(card.contains("CadenceTaskCompletionState.resolve(task: task).isSettled"))
        #expect(card.contains(".foregroundStyle(isSettled ? Theme.dim : Theme.text)"))
        #expect(card.contains(".strikethrough(isSettled, color: Theme.dim)"))
        #expect(card.contains("listColor.opacity(isSettled ? 0.05 : 0.12)"))
        #expect(!card.contains(".strikethrough(task.isDone"))
        let task = AppTask(title: "Cancelled card")
        #expect(!CadenceTaskCompletionState.resolve(task: task).isSettled)
        task.status = .cancelled
        #expect(CadenceTaskCompletionState.resolve(task: task).isSettled)
        task.status = .done
        #expect(CadenceTaskCompletionState.resolve(task: task).isSettled)
    }

    @Test func completedControlRemainsOptOutWithoutChangingItsBehavior() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/iOS/iOSTaskViews.swift")
        let start = try #require(source.range(of: "struct iOSTaskViewOptionsBar: View"))
        let bar = String(source[start.lowerBound...])
        #expect(bar.contains("var showsCompletedControl = true"))
        #expect(bar.contains("if showsCompletedControl {\n                Button {\n                    showCompleted.toggle()"))
        #expect(bar.contains(".disabled(completedCount == 0)"))
        #expect(bar.contains(".opacity(completedCount == 0 ? 0.45 : 1)"))
        #expect(bar.contains("showSortPicker = true"))
        let compact = try read("Cadence/iOS/iOSTodayCompactViews.swift")
        #expect(compact.contains("struct iOSCompactTodayView"))
        #expect(compact.contains("completedCount: summary.completedCount,\n                showsCompletedControl: false"))
    }

    /// **Extended for the second half of [[T-3084]], and the extension is the point.** This body
    /// listed four note kinds and asserted the Notes section held exactly three of them — which is
    /// the coverage trap parity finding PA-20 named by id: list documents were excluded from the
    /// contract, so the suite stayed green for a year while a whole kind of thing the owner owns
    /// was missing from Cmd+K. The fifth kind is in the contract now, with its route.
    @MainActor @Test func macSearchFindsEveryGlobalNoteKindAndKeepsEventIdentity() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let area = Area(name: "Archive area")
        context.insert(area)
        let notes = [
            Note(kind: .daily, content: "unique archive", dateKey: "2026-01-02"),
            Note(kind: .weekly, content: "unique archive", weekKey: "2026-W01"),
            Note(kind: .permanent, title: "unique archive"),
            Note(kind: .list, title: "unique archive"),
            Note(kind: .meeting, title: "unique archive")
        ]
        for note in notes { context.insert(note) }
        CadenceListNoteSupport.attach(notes[3], to: area, project: nil)
        try context.save()

        let index = GlobalSearchIndexSupport.buildIndexedSource(
            query: "unique archive", hiddenTabs: [], areas: [], projects: [], tasks: [], notes: notes,
            eventResults: [], sidebarTabColorsRaw: "", includesCompletedTasks: false
        )
        let ordinary = index.sections.first { $0.category == .notes }?.results ?? []
        #expect(Set(ordinary.map(\.id)) == Set(notes.prefix(4).map { CadenceSearchIdentity.note($0.id) }))
        for note in notes.prefix(4) {
            #expect(ordinary.first { $0.id == CadenceSearchIdentity.note(note.id) }?.destination == .note(note.id))
        }
        #expect(ordinary.first { $0.id == CadenceSearchIdentity.note(notes[3].id) }?.subtitle == "List • Archive area")
        let events = index.sections.first { $0.category == .meetingNotes }?.results ?? []
        #expect(events.count == 1)
        #expect(events.first?.destination == .eventNote(notes[4].id))
        #expect(events.first?.id == CadenceSearchIdentity.eventNote(notes[4].id))
    }

    /// **REVISED FOR T-1473, deliberately, because its two count assertions were the pin that
    /// defended the bug.**
    ///
    /// This body used to end `...RanksBeforeItsLimit` with `results.count == 12` over sixteen
    /// matching notes and `== 8` over the idle branch. Those were not claims about ranking; they
    /// were the *silent* macOS cap written down, and the suite was green **because** the fifteenth
    /// and sixteenth matches were unreachable. The owner decided the cap reports what it holds
    /// back and offers a way to reveal it, so the numbers had to move from the returned array to
    /// `resultCap(for:query:)` — and an assertion on the array's length would have forced the old
    /// shape back.
    ///
    /// **Everything this test actually claims survives and is asserted more tightly than before:**
    /// live embed titles resolve and stale ones do not match, tags match, the exact title outranks
    /// the sixteen near-misses, and the order is stable across a reversed input. Ranking still
    /// happens *before* the limit, which is what the name promises — that is now checked on the
    /// visible prefix, where the user actually sees it.
    @MainActor @Test func macNoteSearchResolvesLiveEmbedsTagsAndRanksBeforeItsLimit() {
        let task = AppTask(title: "Live embedded title")
        let note = Note(kind: .permanent, content: "[[task:\(task.id.uuidString)|Obsolete title]]")
        note.tags = [Cadence.Tag(name: "ArchiveTag")]
        let titles = MarkdownTaskEmbedTitleCache.titles(for: [task])
        #expect(GlobalSearchIndexSupport.noteResults(notes: [note], query: "Live embedded title", taskTitles: titles).count == 1)
        #expect(GlobalSearchIndexSupport.noteResults(notes: [note], query: "Obsolete title", taskTitles: titles).isEmpty)
        #expect(GlobalSearchIndexSupport.noteResults(notes: [note], query: "ArchiveTag", taskTitles: titles).count == 1)

        let exact = Note(kind: .permanent, title: "Roadmap")
        let crowded = (0..<15).map { Note(kind: .permanent, title: "Roadmap followup \($0)") } + [exact]
        let results = GlobalSearchIndexSupport.noteResults(notes: crowded, query: "roadmap", taskTitles: [:])
        let cap = GlobalSearchIndexSupport.resultCap(for: .notes, query: "roadmap")

        // Sixteen matches, all sixteen returned — the two this suite used to drop are the ticket.
        #expect(crowded.count == 16)
        #expect(results.count == 16)
        // The number twelve is unchanged and still bounds the initial render; it now lives
        // somewhere that can be asked how many it is withholding.
        #expect(cap == 12)
        #expect(CadenceSearchResultCap.visibleCount(total: results.count, cap: cap, isExpanded: false) == 12)
        #expect(CadenceSearchResultCap.hiddenCount(total: results.count, cap: cap, isExpanded: false) == 4)
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 4) == "4 more results")

        // THE RANKING CLAIM, which is the real content of this test and is kept exact: the one
        // exact title wins, and it wins *inside the twelve the user is shown*, not merely
        // somewhere in a sixteen-long array they would have to expand to reach.
        #expect(results.first?.destination == .note(exact.id))
        #expect(Array(results.prefix(cap)).first?.destination == .note(exact.id))
        #expect(results.map(\.id) == GlobalSearchIndexSupport.noteResults(notes: crowded.reversed(), query: "roadmap", taskTitles: [:]).map(\.id))

        // The idle branch keeps its own, smaller cap. It was `== 8` on the returned array here too.
        let idle = GlobalSearchIndexSupport.noteResults(notes: crowded, query: "", taskTitles: [:])
        #expect(idle.count == 16)
        #expect(GlobalSearchIndexSupport.resultCap(for: .notes, query: "") == 8)
    }

    @MainActor @Test func requestedNoteSelectionConsumesOnlyAnExistingMatchingID() {
        let manager = NotesNavigationManager.shared
        defer { manager.clear() }
        for (kind, page) in [(NoteKind.daily, NotesView.NotesPage.daily), (.weekly, .weekly), (.permanent, .notepad), (.meeting, .meeting)] {
            let note = Note(kind: kind)
            manager.openNote(id: note.id, kind: kind)
            #expect(manager.request?.page == page)
            #expect(manager.request?.noteID == note.id)
            var request = manager.request?.noteID
            var selection: UUID? = UUID()
            let previous = selection
            #expect(!NotesView.RequestedSelection.apply(&request, selection: &selection, notes: []))
            #expect(request == note.id)
            #expect(selection == previous)
            #expect(NotesView.RequestedSelection.apply(&request, selection: &selection, notes: [note]))
            #expect(request == nil)
            #expect(selection == note.id)
            #expect(!NotesView.RequestedSelection.apply(&request, selection: &selection, notes: [note]))
            #expect(selection == note.id)
        }
    }

    @Test func macNoteSearchWiresRequestsToEveryGlobalPageWithoutReplacingNormalOpen() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let action = try read("Cadence/macOS/Views/macOSRootCommandActionSupport.swift")
        #expect(action.contains("enum RootCommandActionSupport"))
        let handle = try #require(CadenceSourceScan.functionBody(named: "handleSearchSelection", in: action))
        #expect(handle.contains("case .note(let noteID):"))
        #expect(handle.contains("context.notesNavigationManager.openNote(id: note.id, kind: note.kind)"))
        #expect(handle.contains("#Predicate { $0.id == noteID }"))
        let view = try read("Cadence/macOS/Views/NotesView.swift")
        #expect(view.contains("struct NotesView: View"))
        #expect(view.contains("requestedNoteID = request.noteID ?? request.eventNoteID"))
        for page in ["DailyNotesPage", "WeeklyNotesPage", "NotepadPage", "MeetingNotesPage"] {
            #expect(view.contains("\(page)(requestedNoteID: $requestedNoteID)"))
        }
        #expect(view.contains("if !applyRequestedSelection() { openNote(forDateKey: observedDay.todayKey) }"))
        #expect(view.contains("if !applyRequestedSelection() { openNote(forWeekKey: currentWeekKey) }"))
        #expect(view.contains("if !applyRequestedSelection() { loadOrCreateNotepad() }"))
        #expect(view.components(separatedBy: "NotesView.RequestedSelection.apply(&requestedNoteID, selection: &selectedNoteID, notes: notes)").count - 1 == 3)
    }

    /// [[T-3221]] / [[T-1467]] (parity PA-02): a parent with children lists the SAME subtasks on
    /// the iOS row, the macOS row and the macOS Kanban card. The fixture fixes the shared decision
    /// (unfinished only, in `order`, capped, "+N" for the rest, nothing under a finished parent);
    /// the scans pin that every surface asks that decision rather than re-deriving it, and that the
    /// card draws the row's own list view instead of a third copy of it.
    @MainActor @Test func aParentWithChildrenListsTheSameSubtasksOnBothRowsAndTheCard() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let parent = AppTask(title: "Parent")
        context.insert(parent)
        let limit = CadenceTaskPresentationSupport.rowSubtaskLimit
        let total = limit + 3
        let children = (0..<total).map { index in
            let child = Subtask(title: "Step \(index + 1)")
            child.order = total - index
            context.insert(child)
            child.parentTask = parent
            return child
        }
        parent.subtasks = children
        children[total - 1].isDone = true
        try context.save()

        let open = children.filter { !$0.isDone }.sorted { $0.order < $1.order }
        let listed = CadenceTaskPresentationSupport.listedSubtasks(for: parent)
        #expect(listed.map(\.title) == open.prefix(limit).map(\.title))
        #expect(CadenceTaskPresentationSupport.unlistedSubtaskCount(for: parent) == open.count - limit)
        parent.status = .done
        #expect(CadenceTaskPresentationSupport.listedSubtasks(for: parent).isEmpty)
        #expect(CadenceTaskPresentationSupport.unlistedSubtaskCount(for: parent) == nil)

        let read = CadenceSourceScan.strippedSourceReader()
        let iOSRow = try #require(CadenceSourceScan.declarationBody(
            "private var subtaskRows: some View", in: try read("Cadence/iOS/iOSTaskViews.swift")))
        let macRow = try #require(CadenceSourceScan.declarationBody(
            "private var inlineDetail: some View", in: try read("Cadence/macOS/Views/TasksPanelComponents.swift")))
        let card = try #require(CadenceSourceScan.declarationBody(
            "private var subtaskRows: some View", in: try read("Cadence/macOS/Views/KanbanCardView.swift")))
        for body in [iOSRow, macRow, card] {
            #expect(body.contains("CadenceTaskPresentationSupport.listedSubtasks(for: task)"))
            #expect(body.contains("CadenceTaskPresentationSupport.unlistedSubtaskCount(for: task)"))
        }
        for body in [macRow, card] {
            #expect(body.contains("MacTaskSubtaskPreviewList("))
            #expect(!body.contains("SubtaskRow(subtask:"), "a macOS surface spells its own subtask list")
            #expect(!body.contains("moreLabel("), "a macOS surface spells its own overflow line")
        }
        #expect(card.contains("overflowFontSize: 11"))
    }

    /// [[T-3221]] / [[T-1467]] (parity PA-01): a task with notes shows the same excerpt on the iOS
    /// row and the macOS row, and markup-only or blank notes draw nothing on either.
    @Test func aTaskWithNotesPreviewsTheSameExcerptOnBothRows() throws {
        let notes = "**Pick up** the dry cleaning before six"
        let tiers = [CadenceTaskRowMetrics.desktop, .compactWidth, .regularWidth]
        let excerpts = tiers.map {
            CadenceTaskPresentationSupport.plainPreviewText(from: notes, limit: $0.notesPreviewLimit)
        }
        for excerpt in excerpts {
            #expect(excerpt.contains("Pick up the dry cleaning"))
            #expect(!excerpt.contains("**"))
        }
        #expect(Set(excerpts).count == 1, "one short note previews differently across tiers: \(excerpts)")
        for empty in ["   \n  ", "---"] {
            for tier in tiers {
                #expect(CadenceTaskPresentationSupport.plainPreviewText(from: empty, limit: tier.notesPreviewLimit).isEmpty)
            }
        }

        let read = CadenceSourceScan.strippedSourceReader()
        let iOSSource = try read("Cadence/iOS/iOSTaskViews.swift")
        let macSource = try read("Cadence/macOS/Views/TasksPanelComponents.swift")
        let iOSLine = try #require(CadenceSourceScan.declarationBody("private var secondaryLine: String?", in: iOSSource))
        let macLine = try #require(CadenceSourceScan.declarationBody("private var notesPreview: String?", in: macSource))
        for body in [iOSLine, macLine] {
            #expect(body.contains("CadenceTaskPresentationSupport.plainPreviewText("))
            #expect(body.contains("from: task.notes,"))
            #expect(body.contains("limit: metrics.notesPreviewLimit"))
            #expect(body.contains("return preview.isEmpty ? nil : preview"))
        }
        #expect(iOSSource.contains("Text(secondaryLine)"))
        let macDetail = try #require(CadenceSourceScan.declarationBody("private var inlineDetail: some View", in: macSource))
        #expect(macDetail.contains("if let notesPreview {"))
        #expect(macDetail.contains("Text(notesPreview)"))
    }
}

#endif
