// T-3084 (second half): compiled for macOS only. This suite reaches macOS-only app code —
// `GlobalSearchIndexSupport`, `ListNavigationManager`, `ListNotesView` — and `CadenceTests` also
// builds for an iOS destination. The gate is here, in the file, so the reason is visible where it
// applies.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **Mac global search finds list documents, and selecting one opens it** ([[T-3084]]).
///
/// The first half of this ticket extended the palette to Daily, Weekly, Notepad and Event Notes
/// and stopped at `case .list, .meeting: return nil`, because routing a list document needed an
/// owner scope decision (parity finding PA-20). That decision landed 2026-10-23: lists are found,
/// and containers rank above their contents.
///
/// Every test here names the thing that breaks if the change is reverted. The ticket's own history
/// is the standard — the previous author proved their work by showing which tests a restored
/// candidate filter killed — so these assert the *route*, not merely the candidate set: a hit that
/// cannot be opened is the half-fix this ticket was reopened for.
@MainActor
struct CadenceMacListDocumentSearchTests {
    /// An area, a project and the four list documents the cases below need, all inserted and
    /// saved, because SwiftData relationships are only safe to assign on managed objects.
    @MainActor private struct Fixture {
        let container: ModelContainer
        let area: Area
        let project: Project
        /// Filed under the area.
        let areaNote: Note
        /// Filed under the project.
        let projectNote: Note
        /// Filed under neither — unreachable in the app, so unofferable here.
        let orphanNote: Note
        /// Filed under the area, matched only through a tag.
        let taggedNote: Note

        init() throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let context = container.mainContext
            area = Area(name: "Marketing")
            project = Project(name: "Launch")
            context.insert(area)
            context.insert(project)

            areaNote = Note(kind: .list, title: "Quarterly plan")
            projectNote = Note(kind: .list, title: "Rollout plan")
            orphanNote = Note(kind: .list, title: "Stranded plan")
            taggedNote = Note(kind: .list, title: "Untagged heading")
            for note in [areaNote, projectNote, orphanNote, taggedNote] { context.insert(note) }
            CadenceListNoteSupport.attach(areaNote, to: area, project: nil)
            CadenceListNoteSupport.attach(projectNote, to: nil, project: project)
            CadenceListNoteSupport.attach(taggedNote, to: area, project: nil)

            let tag = Cadence.Tag(name: "PlanTag")
            context.insert(tag)
            taggedNote.tags = [tag]
            try context.save()
        }

        var notes: [Note] { [areaNote, projectNote, orphanNote, taggedNote] }
    }

    /// **The candidate set.** A list document is found by title and by tag, it says which list it
    /// belongs to, and it carries the same `note-<uuid>` identity every other Notes row carries.
    ///
    /// Reverting `noteSubtitle(for:)`'s `.list` arm to `return nil` empties `found` and fails the
    /// first expectation here.
    @Test func listDocumentsAreFoundUnderTheirOwnNamesAndTags() throws {
        let fixture = try Fixture()
        let found = GlobalSearchIndexSupport.noteResults(
            notes: fixture.notes, query: "plan", taskTitles: [:]
        )
        #expect(found.map(\.id).contains(CadenceSearchIdentity.note(fixture.areaNote.id)))
        #expect(found.map(\.id).contains(CadenceSearchIdentity.note(fixture.projectNote.id)))

        let row = try #require(found.first { $0.id == CadenceSearchIdentity.note(fixture.areaNote.id) })
        #expect(row.category == .notes)
        #expect(row.title == "Quarterly plan")
        #expect(row.subtitle == "List • Marketing")
        #expect(row.destination == .note(fixture.areaNote.id))
        let projectRow = try #require(found.first {
            $0.id == CadenceSearchIdentity.note(fixture.projectNote.id)
        })
        #expect(projectRow.subtitle == "List • Launch")

        // Tags reach a list document exactly as they reach the other kinds.
        let tagged = GlobalSearchIndexSupport.noteResults(
            notes: fixture.notes, query: "PlanTag", taskTitles: [:]
        )
        #expect(tagged.map(\.id) == [CadenceSearchIdentity.note(fixture.taggedNote.id)])
    }

    /// **A list document filed under no list is not offered**, because nothing can open one: the
    /// Documents tab is the only surface that draws a `.list` note and it is reached through a
    /// list. Dropping the `GlobalSearchListNoteRoute.route(for:) != nil` guard in
    /// `noteSubtitle(for:)` puts the stranded note in the result set and fails this.
    @Test func aListDocumentWithNoListIsNotOffered() throws {
        let fixture = try Fixture()
        let found = GlobalSearchIndexSupport.noteResults(
            notes: fixture.notes, query: "stranded", taskTitles: [:]
        )
        #expect(found.isEmpty)
        #expect(GlobalSearchListNoteRoute.route(for: fixture.orphanNote) == nil)
        #expect(GlobalSearchIndexSupport.noteSubtitle(for: fixture.orphanNote) == nil)
        // The bare subtitle is still spelled for a list whose name is blank, so a routable
        // document never renders a trailing bullet with nothing after it.
        #expect(GlobalSearchIndexSupport.listNoteSubtitle(for: fixture.orphanNote) == "List")
    }

    /// **Where the hit goes**: the note's own list, the Documents tab, that document selected.
    ///
    /// `.meeting` keeps its own route (it has its own section and its own page), and the three
    /// Notes-page kinds keep theirs — `route(for:)` answering anything but `nil` for them would
    /// send a Daily note to a list.
    @Test func aListDocumentRoutesToItsOwnListsDocumentsTab() throws {
        let fixture = try Fixture()
        #expect(GlobalSearchListNoteRoute.route(for: fixture.areaNote) == .area(fixture.area.id))
        #expect(GlobalSearchListNoteRoute.route(for: fixture.projectNote) == .project(fixture.project.id))
        #expect(GlobalSearchListNoteRoute.route(for: fixture.areaNote)?.sidebarItem == .area(fixture.area.id))
        #expect(GlobalSearchListNoteRoute.route(for: fixture.projectNote)?.sidebarItem == .project(fixture.project.id))
        for kind in [NoteKind.daily, .weekly, .permanent, .meeting] {
            #expect(GlobalSearchListNoteRoute.route(for: Note(kind: kind)) == nil)
        }

        let manager = ListNavigationManager.shared
        defer { manager.request = nil }

        manager.open(areaID: fixture.area.id, page: .documents, listNoteID: fixture.areaNote.id)
        var request = try #require(manager.request)
        #expect(request.page == .documents)
        #expect(request.areaID == fixture.area.id)
        #expect(request.projectID == nil)
        #expect(request.listNoteID == fixture.areaNote.id)
        // Not the event-note field: the two land in different columns of `ListNotesView`.
        #expect(request.eventNoteID == nil)
        #expect(manager.consumeIfMatches(areaID: fixture.area.id, projectID: nil)?.listNoteID == fixture.areaNote.id)
        #expect(manager.request == nil)

        manager.open(projectID: fixture.project.id, page: .documents, listNoteID: fixture.projectNote.id)
        request = try #require(manager.request)
        #expect(request.areaID == nil)
        #expect(request.projectID == fixture.project.id)
        #expect(request.listNoteID == fixture.projectNote.id)
    }

    /// **A missing id stays pending rather than selecting some other document as though it were
    /// the hit** — the behaviour the first half of this ticket won on the Notes page, held here.
    @Test func aRequestForADocumentThisListDoesNotHoldStaysPending() throws {
        let fixture = try Fixture()
        let held = [fixture.areaNote, fixture.taggedNote]
        #expect(ListNotesView.RequestedListNote.resolve(
            requestedID: fixture.projectNote.id, notes: held
        ) == nil)
        #expect(ListNotesView.RequestedListNote.resolve(requestedID: nil, notes: held) == nil)
        #expect(ListNotesView.RequestedListNote.resolve(
            requestedID: fixture.areaNote.id, notes: held
        ) == fixture.areaNote.id)
        #expect(ListNotesView.RequestedListNote.resolve(
            requestedID: fixture.areaNote.id, notes: []
        ) == nil)
    }

    /// **Containers rank above their contents** — the owner's 2026-10-23 ranking decision, read
    /// off the rows the palette actually draws rather than off the section array, because the
    /// draw order is what buries a list under its own tasks.
    ///
    /// Moving `.tasks` above `.areas`/`.projects` in `buildIndexedSource` fails this.
    @Test func containersRankAboveTheirContents() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let area = Area(name: "Marketing")
        let project = Project(name: "Marketing launch")
        context.insert(area)
        context.insert(project)
        let tasks = (0..<30).map { index -> AppTask in
            let task = AppTask(title: "Marketing task \(index)")
            context.insert(task)
            task.area = area
            return task
        }
        try context.save()

        let index = GlobalSearchIndexSupport.buildIndexedSource(
            query: "marketing", hiddenTabs: [], areas: [area], projects: [project], tasks: tasks,
            notes: [], eventResults: [], sidebarTabColorsRaw: "", includesCompletedTasks: false
        )
        let rows = GlobalSearchOverlayStateSupport.keyboardRows(
            from: GlobalSearchDataSupport.visibleSections(from: index.sections, expandedCategories: [])
        ).compactMap { row -> GlobalSearchResult? in
            guard case .result(let result) = row else { return nil }
            return result
        }

        let areaRow = try #require(rows.firstIndex { $0.id == CadenceSearchIdentity.area(area.id) })
        let projectRow = try #require(rows.firstIndex { $0.id == CadenceSearchIdentity.project(project.id) })
        let firstTaskRow = try #require(rows.firstIndex { $0.category == .tasks })
        #expect(areaRow < firstTaskRow)
        #expect(projectRow < firstTaskRow)
        // Thirty matching tasks, and the list is still the row above all of them — this is the
        // "rather than burying it under thirty of its own tasks" the decision names.
        #expect(rows.filter { $0.category == .tasks }.count == GlobalSearchIndexSupport.resultCap(for: .tasks, query: "marketing"))
    }

    /// The wiring the two pure halves above cannot reach: the selection handler asks
    /// `GlobalSearchListNoteRoute` and opens the Documents tab, the detail view carries the
    /// requested id into that tab only, and the Documents column applies it.
    @Test nonisolated func theListDocumentRouteIsWiredFromTheHandlerToTheDocumentsColumn() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        let action = try read("Cadence/macOS/Views/macOSRootCommandActionSupport.swift")
        let handle = try #require(CadenceSourceScan.functionBody(named: "handleSearchSelection", in: action))
        #expect(handle.contains("if let route = GlobalSearchListNoteRoute.route(for: note) {"))
        #expect(handle.contains("openListNote(note.id, route: route, context: context)"))
        // The pre-existing Notes-page branch is preserved, not replaced.
        #expect(handle.contains("context.notesNavigationManager.openNote(id: note.id, kind: note.kind)"))
        let open = try #require(CadenceSourceScan.functionBody(named: "openListNote", in: action))
        #expect(open.contains("context.listNavigationManager.open(areaID: areaID, page: .documents, listNoteID: noteID)"))
        #expect(open.contains("context.listNavigationManager.open(projectID: projectID, page: .documents, listNoteID: noteID)"))
        #expect(open.contains("context.setSelection(route.sidebarItem)"))

        let detail = try read("Cadence/macOS/Views/ListDetailView.swift")
        #expect(detail.contains("requestedListNoteID = request.page == .documents ? request.listNoteID : nil"))
        #expect(detail.contains("requestedListNoteID: $requestedListNoteID"))

        let column = try read("Cadence/macOS/Views/ListNotesView.swift")
        let apply = try #require(CadenceSourceScan.functionBody(named: "applyRequestedListNoteSelection", in: column))
        #expect(apply.contains("RequestedListNote.resolve("))
        #expect(apply.contains("notes: listNotes"))
        #expect(apply.contains("select(.list(noteID), clearsRequestedEventNote: false)"))
        #expect(apply.contains("requestedListNoteID = nil"))
        #expect(column.contains(".onChange(of: requestedListNoteID) { _, _ in"))
    }
}
#endif
