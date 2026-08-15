import Foundation
import SwiftData
import Testing
@testable import Cadence

/// A list owns exactly one note, and `firstOrCreateNote` is the only thing that decides whether one
/// needs making. Getting that wrong is not a cosmetic bug: the panel shows the *first* match, so a
/// spurious second note reads as the user's writing having vanished.
@MainActor
struct ListNoteSupportTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    @Test func repeatedCallsReuseTheSameListNote() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Documents")
        modelContext.insert(area)
        try modelContext.save()

        let first = try #require(CadenceListNoteSupport.firstOrCreateNote(for: area, project: nil, in: modelContext))
        first.content = "Draft"
        try modelContext.save()

        let second = try #require(CadenceListNoteSupport.firstOrCreateNote(for: area, project: nil, in: modelContext))

        #expect(second.id == first.id)
        #expect(second.content == "Draft")
        #expect(try modelContext.fetch(FetchDescriptor<Note>()).count == 1)
    }

    /// Two lists do not share a note, and one list's note is not mistaken for another's.
    @Test func eachListGetsItsOwnNote() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Documents")
        let project = Project(name: "Launch")
        modelContext.insert(area)
        modelContext.insert(project)
        try modelContext.save()

        let areaNote = try #require(CadenceListNoteSupport.firstOrCreateNote(for: area, project: nil, in: modelContext))
        let projectNote = try #require(CadenceListNoteSupport.firstOrCreateNote(for: nil, project: project, in: modelContext))

        #expect(areaNote.id != projectNote.id)
        #expect(areaNote.area?.id == area.id)
        #expect(projectNote.project?.id == project.id)
        #expect(try modelContext.fetch(FetchDescriptor<Note>()).count == 2)
    }

    /// With neither a list nor a project there is nothing to attach a note to, so nothing is
    /// created.
    @Test func noContainerCreatesNothing() throws {
        let modelContext = try makeContext()

        #expect(CadenceListNoteSupport.firstOrCreateNote(for: nil, project: nil, in: modelContext) == nil)
        #expect(try modelContext.fetch(FetchDescriptor<Note>()).isEmpty)
    }
}
