import Foundation
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

    @MainActor @Test func macSearchFindsEveryGlobalNoteKindAndKeepsEventIdentity() {
        let notes = [
            Note(kind: .daily, content: "unique archive", dateKey: "2026-01-02"),
            Note(kind: .weekly, content: "unique archive", weekKey: "2026-W01"),
            Note(kind: .permanent, title: "unique archive"),
            Note(kind: .meeting, title: "unique archive")
        ]
        let index = GlobalSearchIndexSupport.buildIndexedSource(
            query: "unique archive", hiddenTabs: [], areas: [], projects: [], tasks: [], notes: notes,
            eventResults: [], sidebarTabColorsRaw: ""
        )
        let ordinary = index.sections.first { $0.category == .notes }?.results ?? []
        #expect(Set(ordinary.map(\.id)) == Set(notes.prefix(3).map { CadenceSearchIdentity.note($0.id) }))
        for note in notes.prefix(3) {
            #expect(ordinary.first { $0.id == CadenceSearchIdentity.note(note.id) }?.destination == .note(note.id))
        }
        let events = index.sections.first { $0.category == .meetingNotes }?.results ?? []
        #expect(events.count == 1)
        #expect(events.first?.destination == .eventNote(notes[3].id))
        #expect(events.first?.id == CadenceSearchIdentity.eventNote(notes[3].id))
    }

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
        #expect(results.count == 12)
        #expect(results.first?.destination == .note(exact.id))
        #expect(GlobalSearchIndexSupport.noteResults(notes: crowded, query: "", taskTitles: [:]).count == 8)
        #expect(results.map(\.id) == GlobalSearchIndexSupport.noteResults(notes: crowded.reversed(), query: "roadmap", taskTitles: [:]).map(\.id))
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
        #expect(view.contains("if !applyRequestedSelection() { openNote(forDateKey: DateFormatters.todayKey()) }"))
        #expect(view.contains("if !applyRequestedSelection() { openNote(forWeekKey: DateFormatters.currentWeekKey()) }"))
        #expect(view.contains("if !applyRequestedSelection() { loadOrCreateNotepad() }"))
        #expect(view.components(separatedBy: "NotesView.RequestedSelection.apply(&requestedNoteID, selection: &selectedNoteID, notes: notes)").count - 1 == 3)
    }
}
