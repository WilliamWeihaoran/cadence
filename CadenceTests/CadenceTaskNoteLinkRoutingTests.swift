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

    @Test func theRootViewAnswersNotesNavigationRequests() throws {
        let root = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift"))
        let hit = try #require(root.range(of: ".onChange(of: notesNavigationManager.request?.token)"))
        let brace = try #require(root.range(of: "{", range: hit.upperBound..<root.endIndex))
        let body = try #require(CadenceSourceScan.matchedBody(after: brace.lowerBound, in: root, open: "{", close: "}"))
        #expect(body.contains("macOSRootLifecycleSupport.handleNotesNavigationRequest("))
    }
}
#endif
