import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-8762]]: iPhone and iPad could not move a list note, nor delete the open note from its
/// editor.** The Mac's Actions popover offers Move Note for a list note and Delete Note wherever
/// its host passes `onDelete`; iOS had no list-to-list move anywhere and delete only from a row's
/// long-press. Neither difference answers a hardware constraint ([[T-8201]]).
///
/// Not gated on macOS: the move helper and the offer rule are shared now
/// (`Cadence/Shared/CadenceNoteMoveSupport.swift`), so these run on both destinations.
@MainActor
struct CadenceNoteMoveParityTests {

    private struct CommitRefused: Error {}

    // MARK: - The offer rule, per kind

    /// Both platforms ask one function whether a note can be moved, so the answer per kind is
    /// pinned once: a list note with somewhere to go, and nothing else.
    @Test func moveNoteIsOfferedForAListNoteWithADestinationAndNoOtherKind() {
        for kind in NoteKind.allCases {
            let withAreas = CadenceNoteMoveDestinations.offersMove(kind: kind, hasAreas: true, hasProjects: false)
            let withProjects = CadenceNoteMoveDestinations.offersMove(kind: kind, hasAreas: false, hasProjects: true)
            let withNothing = CadenceNoteMoveDestinations.offersMove(kind: kind, hasAreas: false, hasProjects: false)
            #expect(withAreas == (kind == .list), "\(kind) with an area")
            #expect(withProjects == (kind == .list), "\(kind) with a project")
            #expect(!withNothing, "\(kind) with no list to move to")
        }
    }

    // MARK: - Destinations: active lists plus the current one (T-9062)

    /// Move Note offers only active lists, as a task's Move to List does, and keeps the note's
    /// own list when that list is inactive so its checked row still reads.
    @Test func moveNoteDestinationsAreActiveListsPlusTheNotesCurrentOne() throws {
        let live = Area(name: "Live")
        let doneArea = Area(name: "Done Area")
        doneArea.status = .done
        let archivedArea = Area(name: "Archived Area")
        archivedArea.status = .archived
        let activeProject = Project(name: "Active")
        var retired: [Project] = []
        for status in ProjectStatus.allCases where status != .active {
            let project = Project(name: status.rawValue)
            project.status = status
            retired.append(project)
        }
        #expect(retired.count == 4, "paused, done, archived and cancelled")
        let areas = [live, doneArea, archivedArea]
        let projects = [activeProject] + retired

        let unfiled = Note(kind: .list, title: "Loose")
        let loose = CadenceNoteMoveDestinations.destinations(for: unfiled, areas: areas, projects: projects)
        #expect(loose.areas.map(\.name) == ["Live"])
        #expect(loose.projects.map(\.name) == ["Active"])

        let filed = Note(kind: .list, title: "Filed")
        filed.area = archivedArea
        let fromArchived = CadenceNoteMoveDestinations.destinations(for: filed, areas: areas, projects: projects)
        #expect(Set(fromArchived.areas.map(\.name)) == ["Live", "Archived Area"])
        #expect(fromArchived.projects.map(\.name) == ["Active"])

        let inPaused = Note(kind: .list, title: "Paused")
        let paused = try #require(retired.first { $0.status == .paused })
        inPaused.project = paused
        let fromPaused = CadenceNoteMoveDestinations.destinations(for: inPaused, areas: areas, projects: projects)
        #expect(Set(fromPaused.projects.map(\.name)) == ["Active", "paused"])
        #expect(fromPaused.areas.map(\.name) == ["Live"])
    }

    /// A store whose only lists are retired offers no Move page: the offer reads the filtered
    /// lists, not the raw query.
    @Test func moveNoteIsNotOfferedWhenEveryListIsRetired() {
        let archived = Area(name: "Old")
        archived.status = .archived
        let done = Project(name: "Shipped")
        done.status = .done
        let note = Note(kind: .list, title: "Plan")
        let destinations = CadenceNoteMoveDestinations.destinations(for: note, areas: [archived], projects: [done])
        #expect(destinations.areas.isEmpty && destinations.projects.isEmpty)
        #expect(!CadenceNoteMoveDestinations.offersMove(kind: .list, destinations: destinations))

        let live = Area(name: "Live")
        let withLive = CadenceNoteMoveDestinations.destinations(for: note, areas: [archived, live], projects: [done])
        #expect(CadenceNoteMoveDestinations.offersMove(kind: .list, destinations: withLive))
    }

    /// Both menus draw from the filtered destinations, not their raw `@Query`.
    @Test func bothNoteMenusReadTheFilteredMoveDestinations() throws {
        let mac = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/AIActionsSupportViews.swift")
        let iOS = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSNoteManageMenu.swift")
        let call = "CadenceNoteMoveDestinations.destinations(for: note, areas: areas, projects: projects)"
        #expect(mac.contains(call))
        #expect(iOS.contains(call))
        #expect(mac.contains("let areas = moveDestinations.areas"))
        #expect(mac.contains("let projects = moveDestinations.projects"))
        #expect(iOS.contains("let areas = destinations.areas"))
        #expect(iOS.contains("let projects = destinations.projects"))
        for (name, source) in [("macOS", mac), ("iOS", iOS)] {
            #expect(!source.contains("hasAreas: !areas.isEmpty"), "\(name) gates the offer on the raw query")
        }
    }

    // MARK: - The shared move, behaviourally

    /// The path the iOS menu now calls: a list note filed under a project lands there **in the
    /// store**, read back through a second context, and leaves its old area.
    @Test func aListNoteMovedToAProjectIsInTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        let project = Project(name: "Launch")
        let note = Note(kind: .list, title: "Plan")
        context.insert(area)
        context.insert(project)
        context.insert(note)
        note.area = area
        try context.save()

        try NoteActionSupport.move(note, toProject: project, modelContext: context)

        let noteID = note.id
        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first)
        #expect(stored.project?.name == "Launch")
        #expect(stored.area == nil)
        #expect(!context.hasChanges)
    }

    /// A refused move leaves the note where it was, so the iOS menu's notice is not describing a
    /// note that moved anyway.
    @Test func aRefusedMoveLeavesTheNoteInItsList() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Launch")
        let note = Note(kind: .list, title: "Plan")
        context.insert(project)
        context.insert(note)
        note.project = project
        try context.save()

        #expect(throws: CommitRefused.self) {
            try NoteActionSupport.move(note, toArea: nil, modelContext: context) { _ in
                throw CommitRefused()
            }
        }
        #expect(note.project?.name == "Launch")
        #expect(CadenceNoteMoveDestinations.isUnfiled(note) == false)
    }

    /// [[T-13973]]: a moved note lands **last** among the destination's list notes, as a new note
    /// does, rather than keeping an `order` drawn from its old list's sequence. The source list is
    /// young (order 0) and the destination old (orders 4 and 9), so the carried order would have
    /// drawn the note above both residents. A daily note filed under the same area is not a list
    /// note and does not count.
    @Test func aMovedNoteLandsLastInItsDestinationList() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let home = Area(name: "Home")
        let work = Area(name: "Work")
        let launch = Project(name: "Launch")
        let note = Note(kind: .list, title: "Plan")
        let older = Note(kind: .list, title: "Older")
        let newer = Note(kind: .list, title: "Newer")
        let projectResident = Note(kind: .list, title: "Brief")
        let dated = Note(kind: .daily, title: "Day")
        for model in [home, work] { context.insert(model) }
        context.insert(launch)
        for model in [note, older, newer, projectResident, dated] { context.insert(model) }
        note.area = home
        note.order = 0
        older.area = work
        older.order = 4
        newer.area = work
        newer.order = 9
        dated.area = work
        dated.order = 50
        projectResident.project = launch
        projectResident.order = 2
        let homeResident = Note(kind: .list, title: "Home resident")
        context.insert(homeResident)
        homeResident.area = home
        homeResident.order = 6
        try context.save()

        // Re-choosing the list it is already in (the checked row) is not an arrival: the note
        // keeps its place rather than jumping below `homeResident`.
        try NoteActionSupport.move(note, toArea: home, modelContext: context)
        #expect(note.order == 0, "re-choosing the current list moved the note to the end")

        try NoteActionSupport.move(note, toArea: work, modelContext: context)
        #expect(note.order == 10, "the moved note kept an order from its old list")

        try NoteActionSupport.move(note, toProject: launch, modelContext: context)
        #expect(note.order == 3, "the project move kept an order from its old list")

        let noteID = note.id
        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first)
        #expect(stored.order == 3)
    }

    /// A refused move puts the old `order` back with the old list, so the note does not sit in its
    /// own list at a number allocated for somewhere else.
    @Test func aRefusedMoveRestoresTheNotesOrder() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let home = Area(name: "Home")
        let work = Area(name: "Work")
        let launch = Project(name: "Launch")
        let note = Note(kind: .list, title: "Plan")
        let resident = Note(kind: .list, title: "Resident")
        let projectResident = Note(kind: .list, title: "Brief")
        context.insert(home)
        context.insert(work)
        context.insert(launch)
        for model in [note, resident, projectResident] { context.insert(model) }
        note.area = home
        note.order = 1
        resident.area = work
        resident.order = 7
        projectResident.project = launch
        projectResident.order = 5
        try context.save()

        #expect(throws: CommitRefused.self) {
            try NoteActionSupport.move(note, toArea: work, modelContext: context) { _ in throw CommitRefused() }
        }
        #expect(note.order == 1)
        #expect(note.area?.name == "Home")

        #expect(throws: CommitRefused.self) {
            try NoteActionSupport.move(note, toProject: launch, modelContext: context) { _ in throw CommitRefused() }
        }
        #expect(note.order == 1)
        #expect(note.project == nil)
    }

    // MARK: - Source shape: both platforms' chrome reach the same helpers

    /// The two note menus — the Mac popover and the iOS editor menu — offer Move Note through the
    /// same rule and the same three helper calls (No List, an area, a project), and Delete Note
    /// through each platform's one delete request.
    @Test func bothPlatformsNoteMenusOfferTheSameMoveAndDelete() throws {
        let mac = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/AIActionsSupportViews.swift")
        let iOS = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSNoteManageMenu.swift")

        for (name, source) in [("macOS", mac), ("iOS", iOS)] {
            #expect(source.contains("CadenceNoteMoveDestinations.offersMove("), "\(name) gates Move Note on the shared rule")
            #expect(source.contains("\"Move Note\""), "\(name) names it Move Note")
            #expect(source.contains("NoteActionSupport.move(note, toArea: nil, modelContext: modelContext)"), "\(name) offers No List")
            #expect(source.contains("NoteActionSupport.move(note, toArea: area, modelContext: modelContext)"), "\(name) offers areas")
            #expect(source.contains("NoteActionSupport.move(note, toProject: project, modelContext: modelContext)"), "\(name) offers projects")
            #expect(source.contains("CadenceNoteMoveDestinations.noListTitle"), "\(name) names No List from the shared copy")
            #expect(source.contains("CadencePendingChangePersistence.editFailureNotice"), "\(name) reports a refused move")
        }
        #expect(iOS.contains("iOSNoteDeleteMenuButton(note: note, request: onDelete)"))
    }

    /// Each iOS editor host offers Delete Note where its Mac counterpart passes `onDelete`: the
    /// Notepad tab and a list's Notes tab, in both the cover and the regular-width header.
    @Test func everyIOSEditorChromeCarriesTheNoteMenuWhereTheMacOffersDelete() throws {
        let notes = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSNotesView.swift")
        let list = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSListNotesView.swift")

        // The cover: the menu in its toolbar, the delete gated by the host, its own confirmation
        // that takes the cover down once the note is gone.
        #expect(notes.contains("onDelete: allowsDelete ? { noteToDelete = $0 } : nil"))
        #expect(notes.contains("allowsDelete: activeTab == .notepad"))
        #expect(list.contains("allowsDelete: true"))
        #expect(notes.contains(".iOSNoteDeletion(note: $noteToDelete) {"))

        // The regular-width headers.
        #expect(notes.contains("activeTab == .notepad, let note = selectedNote {\n                iOSNoteManageMenu(note: note, onDelete: { noteToDelete = $0 })"))
        #expect(list.contains("moveFailureNotice: $moveFailureNotice,\n                    onDelete: { noteToDelete = $0 }"))
    }

    /// An editor that deletes its own note is told only after a **committed** delete, and only
    /// once the confirmation has gone: `didDelete` is set below the commit, so a refused delete
    /// (the confirmation stays open naming it, T-320) never takes the editor down behind it.
    @Test func theEditorIsToldOnlyAfterTheDeleteCommits() throws {
        let support = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSNoteDeletionSupport.swift")
        let perform = try #require(CadenceSourceScan.functionBody(named: "perform", in: support))
        let commit = try #require(perform.range(of: "try CadencePendingChangePersistence.commitDelete(in: modelContext)"))
        let flag = try #require(perform.range(of: "didDelete = true"))
        #expect(commit.upperBound <= flag.lowerBound, "the editor would be told before the store took the delete")

        let report = try #require(CadenceSourceScan.functionBody(named: "reportDeletion", in: support))
        #expect(report.contains("guard didDelete else { return }"))
        #expect(report.contains("onDeleted?()"))
        #expect(support.contains(".onDisappear(perform: reportDeletion)"))
    }
}
