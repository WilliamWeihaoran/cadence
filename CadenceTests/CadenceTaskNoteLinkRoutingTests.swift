#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-5061: **a `[[note]]` link in a macOS task's notes did nothing**, in the inspector's notes box
/// and in the floating Task Notes panel its expand button opens.
///
/// The inspector box passed `MarkdownEditor` no `referenceNotes:` (so a link resolved to nothing)
/// and no `onOpenNoteReference:` (whose default is a no-op); its expand button opened the panel
/// with `referenceNotes` defaulted to `[]`; and the panel built `TaskNoteEditorPane` with no
/// `onOpenNote`, whose default is a no-op too. Now both hosts hand a resolved link to
/// `TaskNoteLinkRouting`, which takes the route global search already takes, and `macOSRootView`
/// answers a `NotesNavigationManager` request by selecting the Notes page.
///
/// The routing is driven directly; the view wiring is private to SwiftUI views and is pinned as
/// source text, the way `CadenceMarkdownEditorEmbedWiringTests` pins the card handlers.
@MainActor
@Suite(.serialized)
struct CadenceTaskNoteLinkRoutingTests {

    // MARK: - Behavioural: where a resolved link goes

    @Test func aStandaloneNoteLinkRequestsTheNotesPageOnThatNote() {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }

        for (kind, page) in [(NoteKind.daily, NotesView.NotesPage.daily), (.weekly, .weekly), (.permanent, .notepad), (.meeting, .meeting)] {
            let note = Note(kind: kind, title: "Plan")
            TaskNoteLinkRouting.open(note)
            #expect(notes.request?.page == page)
            #expect(notes.request?.noteID == note.id)
            #expect(lists.request == nil)
            notes.clear()
        }
    }

    @Test func aListNoteLinkOpensItsListsNotesTab() throws {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Work")
        let project = Project(name: "Home")
        let areaNote = Note(kind: .list, title: "Retro", area: area)
        let projectNote = Note(kind: .list, title: "Punch list", project: project)
        context.insert(area)
        context.insert(project)
        context.insert(areaNote)
        context.insert(projectNote)

        TaskNoteLinkRouting.open(areaNote)
        #expect(lists.request?.areaID == area.id)
        #expect(lists.request?.page == .documents)
        #expect(notes.request == nil)

        TaskNoteLinkRouting.open(projectNote)
        #expect(lists.request?.projectID == project.id)
        #expect(lists.request?.page == .documents)
        #expect(notes.request == nil)
    }

    /// [[T-6092]]: the list's Notes tab opens **on the linked note**, not on whatever document
    /// `ListNotesView` reaches first — the request carries the note's id, as global search's does.
    @Test func aListNoteLinkSelectsThatNoteInTheTab() throws {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Work")
        let project = Project(name: "Home")
        let areaNote = Note(kind: .list, title: "Retro", area: area)
        let projectNote = Note(kind: .list, title: "Punch list", project: project)
        context.insert(area)
        context.insert(project)
        context.insert(areaNote)
        context.insert(projectNote)

        TaskNoteLinkRouting.open(areaNote)
        #expect(lists.request?.listNoteID == areaNote.id)
        #expect(lists.request?.eventNoteID == nil)

        TaskNoteLinkRouting.open(projectNote)
        #expect(lists.request?.listNoteID == projectNote.id)
        #expect(lists.request?.eventNoteID == nil)
    }

    /// [[T-5151]] (b): a link clicked in the meeting-note sheet closes the sheet, exactly once and
    /// before the request is raised, then takes the same route as any other note link.
    @Test func aLinkFromAModalDismissesItThenOpensTheNote() throws {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }

        let standalone = Note(kind: .permanent, title: "Roadmap")
        var dismissals = 0
        var requestWhenDismissed: NotesNavigationManager.Request?
        TaskNoteLinkRouting.openDismissing(standalone, dismiss: {
            dismissals += 1
            requestWhenDismissed = notes.request
        })
        #expect(dismissals == 1)
        #expect(requestWhenDismissed == nil)
        #expect(notes.request?.page == .notepad)
        #expect(notes.request?.noteID == standalone.id)
        #expect(lists.request == nil)
        notes.clear()

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Home")
        let listNote = Note(kind: .list, title: "Punch list", project: project)
        context.insert(project)
        context.insert(listNote)
        TaskNoteLinkRouting.openDismissing(listNote, dismiss: { dismissals += 1 })
        #expect(dismissals == 2)
        #expect(lists.request?.projectID == project.id)
        #expect(lists.request?.listNoteID == listNote.id)
        #expect(notes.request == nil)
    }

    @Test func aLinkResolvesByIDFirstThenByTitle() {
        let first = Note(kind: .permanent, title: "Roadmap")
        let second = Note(kind: .permanent, title: "Ideas")
        let notes = [first, second]
        #expect(TaskNoteLinkRouting.note(id: second.id, title: "Roadmap", in: notes) === second)
        #expect(TaskNoteLinkRouting.note(id: UUID(), title: "  roadmap ", in: notes) === first)
        #expect(TaskNoteLinkRouting.note(id: nil, title: "IDEAS", in: notes) === second)
        #expect(TaskNoteLinkRouting.note(id: nil, title: "Nowhere", in: notes) == nil)
        #expect(TaskNoteLinkRouting.note(id: nil, title: "  ", in: notes) == nil)
    }

    // MARK: - [[T-8041]]: links opened from the Notes page's own four editors

    /// A link to a note this tab lists selects it in place and raises no navigation request.
    @Test func aNotesPageLinkToANoteThisTabListsSelectsItInPlace() {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }
        let monday = Note(kind: .daily, dateKey: "2026-10-26")
        let tuesday = Note(kind: .daily, dateKey: "2026-10-27")
        var selection: UUID? = monday.id
        NotesView.EditorLinkRouting.open(tuesday, tabNotes: [monday, tuesday], selection: &selection)
        #expect(selection == tuesday.id)
        #expect(notes.request == nil)
        #expect(lists.request == nil)
    }

    /// The defect: on the Notepad tab a link to a daily note set `selectedNoteID` to an id the tab
    /// does not list, so the editor fell to "Select a note". Now the selection is left alone and
    /// the request names the target's own tab, whose `RequestedSelection.apply` then selects it.
    @Test func aNotesPageLinkToAnotherKindSwitchesToThatNotesTabAndSelectsIt() {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }
        let daily = Note(kind: .daily, dateKey: "2026-10-27")
        let weekly = Note(kind: .weekly, title: "Week 44")
        let notepad = Note(kind: .permanent, title: "Ideas")
        let meeting = Note(kind: .meeting, title: "Standup")
        let all = [daily, weekly, notepad, meeting]
        let cases: [(Note, NotesView.NotesPage)] = [(daily, .daily), (weekly, .weekly), (notepad, .notepad), (meeting, .meeting)]
        var crossKindOpens = 0
        for (source, _) in cases {
            for (target, targetPage) in cases where target.kind != source.kind {
                let tabNotes = all.filter { $0.kind == source.kind }
                var selection: UUID? = source.id
                NotesView.EditorLinkRouting.open(target, tabNotes: tabNotes, selection: &selection)
                // The tab the link was clicked in keeps its editor; it never selects an id it cannot show.
                #expect(selection == source.id)
                #expect(notes.request?.page == targetPage)
                #expect(notes.request?.noteID == target.id)
                #expect(lists.request == nil)

                // The target tab answers the request by selecting the linked note.
                var requested = notes.request?.noteID
                var targetSelection: UUID?
                let applied = NotesView.RequestedSelection.apply(
                    &requested,
                    selection: &targetSelection,
                    notes: all.filter { $0.kind == target.kind }
                )
                #expect(applied)
                #expect(targetSelection == target.id)
                notes.clear()
                crossKindOpens += 1
            }
        }
        #expect(crossKindOpens == 12)
    }

    @Test func aNotesPageLinkToAListNoteOpensItsList() throws {
        let notes = NotesNavigationManager.shared
        let lists = ListNavigationManager.shared
        notes.clear()
        lists.request = nil
        defer {
            notes.clear()
            lists.request = nil
        }
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Home")
        let listNote = Note(kind: .list, title: "Punch list", project: project)
        context.insert(project)
        context.insert(listNote)
        let daily = Note(kind: .daily, dateKey: "2026-10-27")
        var selection: UUID? = daily.id
        NotesView.EditorLinkRouting.open(listNote, tabNotes: [daily], selection: &selection)
        #expect(selection == daily.id)
        #expect(lists.request?.projectID == project.id)
        #expect(lists.request?.listNoteID == listNote.id)
        #expect(notes.request == nil)
    }

    /// Every tab's editor is handed every note -- its `[[` picker, Linked/Backlinks chips and
    /// unlinked-mention footer all read `relatedNotes` -- and opens links through the router.
    @Test func everyNotesPageEditorSeesAllNotesAndRoutesItsLinks() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NotesView.swift")
        )
        var checked = 0
        for page in ["DailyNotesPage", "WeeklyNotesPage", "NotepadPage", "MeetingNotesPage"] {
            let body = try #require(CadenceSourceScan.declarationBody("struct \(page)", in: source), "\(page)")
            #expect(body.contains("@Query(sort: \\Note.updatedAt, order: .reverse) private var allNotes: [Note]"), "\(page)")
            let pane = try Self.arguments(ofFirst: "NoteEditorPane(", in: body)
            #expect(pane.contains("relatedNotes: allNotes"), "\(page)")
            #expect(
                pane.contains("onOpenNote: { NotesView.EditorLinkRouting.open($0, tabNotes: notes, selection: &selectedNoteID) }"),
                "\(page)"
            )
            checked += 1
        }
        #expect(checked == 4)
    }

    @Test func theRootSelectsTheNotesPageForANotesRequest() {
        var selection: SidebarItem? = .today
        macOSRootLifecycleSupport.handleNotesNavigationRequest(request: nil, selection: &selection)
        #expect(selection == .today)
        let request = NotesNavigationManager.Request(page: .notepad, eventNoteID: nil, noteID: UUID())
        macOSRootLifecycleSupport.handleNotesNavigationRequest(request: request, selection: &selection)
        #expect(selection == .notes)
    }

    // MARK: - Source pins: the hosts hand their links to the router

    private static func inspectorSource() throws -> String {
        CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        )
    }

    private static func arguments(ofFirst call: String, in body: String) throws -> String {
        let hit = try #require(body.range(of: call))
        return try #require(
            CadenceSourceScan.matchedBody(after: body.index(before: hit.upperBound), in: body, open: "(", close: ")")
        )
    }

    @Test func theInspectorNotesBoxResolvesAndOpensNoteLinks() throws {
        let section = try #require(
            CadenceSourceScan.declarationBody("struct TaskDetailNotesSection", in: try Self.inspectorSource())
        )
        let editor = try Self.arguments(ofFirst: "MarkdownEditor(", in: section)
        #expect(editor.contains("referenceNotes: referenceNotes"))
        #expect(editor.contains("onOpenNoteReference: openNoteReference"))

        let handler = try #require(CadenceSourceScan.functionBody(named: "openNoteReference", in: section))
        #expect(handler.contains("TaskNoteLinkRouting.note("))
        #expect(handler.contains("TaskNoteLinkRouting.open("))

        // The expand button hands the panel the same notes, so links resolve there too.
        let expand = try Self.arguments(ofFirst: "TaskNotesPanelController.shared.show(", in: section)
        #expect(expand.contains("referenceNotes: referenceNotes"))
    }

    @Test func theTaskNotesPanelOpensAResolvedNoteLink() throws {
        let sheet = try #require(
            CadenceSourceScan.declarationBody("struct TaskNotesExpandedEditorSheet", in: try Self.inspectorSource())
        )
        let pane = try Self.arguments(ofFirst: "TaskNoteEditorPane(", in: sheet)
        #expect(pane.contains("relatedNotes: referenceNotes"))
        #expect(pane.contains("onOpenNote:"))
        #expect(pane.contains("TaskNoteLinkRouting.open("))
    }

    /// T-5180: the Today page's core-note panel passed neither `referenceNotes:` nor
    /// `onOpenNoteReference:`, so its `[[note]]` links neither resolved nor acted.
    @Test func theTodayNotePanelResolvesAndOpensNoteLinks() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NotePanel.swift")
        )
        let panel = try #require(CadenceSourceScan.declarationBody("struct NotePanel", in: source))
        #expect(panel.contains("@Query(sort: \\Note.updatedAt, order: .reverse) private var referenceNotes: [Note]"))
        let editor = try Self.arguments(ofFirst: "MarkdownEditor(", in: panel)
        #expect(editor.contains("referenceNotes: referenceNotes"))
        #expect(editor.contains("onOpenNoteReference: openNoteReference"))

        let handler = try #require(CadenceSourceScan.functionBody(named: "openNoteReference", in: panel))
        #expect(handler.contains("TaskNoteLinkRouting.note(id: id, title: title, in: referenceNotes)"))
        #expect(handler.contains("TaskNoteLinkRouting.open(note)"))
    }

    /// [[T-6461]]: the Focus page's task-notes panel passed neither `referenceNotes:` nor
    /// `onOpenNoteReference:`, so its `[[note]]` links neither resolved nor acted.
    @Test func theFocusNotesPanelResolvesAndOpensNoteLinks() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusNotesPanel.swift")
        )
        let panel = try #require(CadenceSourceScan.declarationBody("struct FocusNotesPanel", in: source))
        #expect(panel.contains("@Query(sort: \\Note.updatedAt, order: .reverse) private var referenceNotes: [Note]"))
        let editor = try Self.arguments(ofFirst: "MarkdownEditor(", in: panel)
        #expect(editor.contains("referenceNotes: referenceNotes"))
        #expect(editor.contains("onOpenNoteReference: openNoteReference"))

        let handler = try #require(CadenceSourceScan.functionBody(named: "openNoteReference", in: panel))
        #expect(handler.contains("TaskNoteLinkRouting.note(id: id, title: title, in: referenceNotes)"))
        #expect(handler.contains("TaskNoteLinkRouting.open(note)"))
    }

    /// [[T-5151]] (b): the meeting-note sheet's pane is handed an `onOpenNote` — its default is a
    /// no-op — and that handler dismisses the sheet through the router.
    @Test func theMeetingNoteSheetDismissesAndRoutesANoteLink() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/EventNoteSupportViews.swift")
        )
        let sheet = try #require(CadenceSourceScan.declarationBody("struct EventNoteEditorSheet", in: source))
        let pane = try Self.arguments(ofFirst: "NoteEditorPane(", in: sheet)
        #expect(pane.contains("onOpenNote: { TaskNoteLinkRouting.openDismissing($0, dismiss: { dismiss() }) }"))
    }

    @Test func theRootViewAnswersNotesNavigationRequests() throws {
        let root = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift"))
        let hit = try #require(root.range(of: ".onChange(of: notesNavigationManager.request?.token)"))
        let brace = try #require(root.range(of: "{", range: hit.upperBound..<root.endIndex))
        let body = try #require(CadenceSourceScan.matchedBody(after: brace.lowerBound, in: root, open: "{", close: "}"))
        #expect(body.contains("macOSRootLifecycleSupport.handleNotesNavigationRequest("))
    }
}
#endif
