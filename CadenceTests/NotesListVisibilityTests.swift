#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The Notes list column is an index of days with content, so what counts as "content" and how the
/// survivors group into months are the two rules the column is made of.
@MainActor
struct NotesListVisibilityTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    @discardableResult
    private func daily(_ dateKey: String, content: String, in context: ModelContext) -> Note {
        let note = Note(kind: .daily, title: dateKey, content: content, dateKey: dateKey)
        context.insert(note)
        return note
    }

    // MARK: - What counts as empty

    @Test func emptyPastDayIsFilteredOut() throws {
        let context = try makeContext()
        let written = daily("2026-08-07", content: "Shipped the thing", in: context)
        let blank = daily("2026-08-06", content: "", in: context)
        let whitespaceOnly = daily("2026-08-05", content: "   \n\n  ", in: context)

        let listed = NotesListVisibility.dailyNotes(
            [written, blank, whitespaceOnly],
            todayKey: "2026-08-10"
        )

        #expect(listed.map(\.id) == [written.id])
    }

    @Test func whitespaceAndSeededHeadingBothReadAsEmpty() {
        #expect(NotesListVisibility.hasContent(rawContent: "", displayTitle: "2026-08-06") == false)
        #expect(NotesListVisibility.hasContent(rawContent: "  \n\t\n ", displayTitle: "2026-08-06") == false)
        // A note seeded with nothing but its own title heading says nothing. This is the case a
        // plain `content.isEmpty` test gets wrong.
        #expect(NotesListVisibility.hasContent(rawContent: "# 2026-08-06", displayTitle: "2026-08-06") == false)
        #expect(NotesListVisibility.hasContent(rawContent: "# 2026-08-06\n\nreal", displayTitle: "2026-08-06") == true)
    }

    @Test func emptyTodayIsKept() throws {
        let context = try makeContext()
        let today = daily("2026-08-10", content: "", in: context)
        let emptyPast = daily("2026-08-09", content: "", in: context)

        let listed = NotesListVisibility.dailyNotes([today, emptyPast], todayKey: "2026-08-10")

        #expect(listed.map(\.id) == [today.id])
    }

    /// The trap. Frontmatter renders at zero height, so a note that has only been tagged looks
    /// blank in the editor while carrying `---\ntags: [...]\n---`. Dropping its row would strand
    /// the tags: the row is the only handle on that note.
    @Test func frontmatterOnlyNoteIsKept() throws {
        let context = try makeContext()
        let tagged = daily(
            "2026-08-04",
            content: """
            ---
            tags: ["research"]
            ---

            """,
            in: context
        )

        #expect(NotesListVisibility.hasContent(tagged))
        #expect(NotesListVisibility.dailyNotes([tagged], todayKey: "2026-08-10").map(\.id) == [tagged.id])
        // ...and it still *reads* as empty, because it is: the body is blank.
        #expect(NotesListVisibility.isBlankBody(
            NotesListVisibility.previewBody(tagged),
            displayTitle: tagged.displayTitle
        ))
    }

    @Test func noteThatGainsThenLosesTextAppearsThenDisappears() throws {
        let context = try makeContext()
        let note = daily("2026-08-03", content: "", in: context)

        func listed() -> [UUID] {
            NotesListVisibility.dailyNotes([note], todayKey: "2026-08-10").map(\.id)
        }

        #expect(listed().isEmpty)
        note.content = "went for a walk"
        #expect(listed() == [note.id])
        note.content = ""
        #expect(listed().isEmpty)
    }

    @Test func weeklyPinsTheCurrentWeekOnly() throws {
        let context = try makeContext()
        let thisWeek = Note(kind: .weekly, title: "2026-W33", content: "", weekKey: "2026-W33")
        let pastEmpty = Note(kind: .weekly, title: "2026-W32", content: "", weekKey: "2026-W32")
        let pastWritten = Note(kind: .weekly, title: "2026-W31", content: "retro", weekKey: "2026-W31")
        [thisWeek, pastEmpty, pastWritten].forEach { context.insert($0) }

        let listed = NotesListVisibility.weeklyNotes(
            [thisWeek, pastEmpty, pastWritten],
            currentWeekKey: "2026-W33"
        )

        #expect(listed.map(\.id) == [thisWeek.id, pastWritten.id])
    }

    // MARK: - Notepad

    @discardableResult
    private func notepad(
        _ title: String,
        content: String = "",
        createdAt: Date,
        in context: ModelContext
    ) -> Note {
        let note = Note(kind: .permanent, title: title, content: content, createdAt: createdAt)
        context.insert(note)
        return note
    }

    /// The rule Notepad does *not* share with Daily and Weekly. There is no "today" to pin a
    /// notepad note to, so if blank notes were filtered a note would vanish the instant you made
    /// one — before you could type in it, and with no row left to select or delete it from.
    @Test func newlyCreatedBlankNotepadNoteIsListed() throws {
        let context = try makeContext()
        let blank = notepad("Untitled", createdAt: Date(), in: context)
        let seeded = notepad("Untitled", content: "# Untitled\n\n", createdAt: Date(), in: context)

        // Both read as empty by the shared body rule...
        #expect(NotesListVisibility.hasContent(blank) == false)
        #expect(NotesListVisibility.hasContent(seeded) == false)
        // ...and both are listed anyway.
        let listed = NotesListVisibility.notepadNotes([blank, seeded]).map(\.id)
        #expect(listed.count == 2)
        #expect(Set(listed) == Set([blank.id, seeded.id]))
    }

    @Test func notepadOrdersNewestCreatedFirst() throws {
        let context = try makeContext()
        let oldest = notepad("Oldest", content: "a", createdAt: Date(timeIntervalSince1970: 1_000), in: context)
        let middle = notepad("Middle", content: "b", createdAt: Date(timeIntervalSince1970: 2_000), in: context)
        let newest = notepad("Newest", content: "c", createdAt: Date(timeIntervalSince1970: 3_000), in: context)

        let listed = NotesListVisibility.notepadNotes([oldest, newest, middle])

        #expect(listed.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    /// The reason the order key is `createdAt` and not `updatedAt`: the editor commits content
    /// about a second after you stop typing, so an edit-ordered column would yank the row you are
    /// writing in to the top of the list — across a month header — mid-sentence.
    @Test func notepadOrderDoesNotMoveWhenANoteIsEdited() throws {
        let context = try makeContext()
        let older = notepad("Older", content: "a", createdAt: Date(timeIntervalSince1970: 1_000), in: context)
        let newer = notepad("Newer", content: "b", createdAt: Date(timeIntervalSince1970: 2_000), in: context)

        #expect(NotesListVisibility.notepadNotes([older, newer]).map(\.id) == [newer.id, older.id])

        older.content = "a lot more words than before"
        older.updatedAt = Date()

        #expect(NotesListVisibility.notepadNotes([older, newer]).map(\.id) == [newer.id, older.id])
    }

    @Test func notepadListIgnoresOtherNoteKinds() throws {
        let context = try makeContext()
        let note = notepad("Kept", content: "x", createdAt: Date(), in: context)
        let daily = daily("2026-08-09", content: "not a notepad note", in: context)
        let list = Note(kind: .list, title: "List note", content: "also not")
        context.insert(list)

        #expect(NotesListVisibility.notepadNotes([note, daily, list]).map(\.id) == [note.id])
    }

    /// Deleting is the only way a notepad note leaves the column, since nothing filters it.
    @Test func deletedNotepadNoteLeavesTheList() throws {
        let context = try makeContext()
        let kept = notepad("Kept", content: "a", createdAt: Date(timeIntervalSince1970: 1_000), in: context)
        let doomed = notepad("Doomed", content: "b", createdAt: Date(timeIntervalSince1970: 2_000), in: context)
        try context.save()

        #expect(NotesListVisibility.notepadNotes(try context.fetch(FetchDescriptor<Note>())).count == 2)

        context.delete(doomed)
        try context.save()

        let listed = NotesListVisibility.notepadNotes(try context.fetch(FetchDescriptor<Note>()))
        #expect(listed.map(\.id) == [kept.id])
    }

    /// Notepad rows group under the month they were created in, which is the only date they have.
    @Test func notepadGroupsUnderCreationMonth() throws {
        let context = try makeContext()
        let aug = notepad("Aug", content: "a", createdAt: DateFormatters.date(from: "2026-08-09")!, in: context)
        let jul = notepad("Jul", content: "b", createdAt: DateFormatters.date(from: "2026-07-02")!, in: context)

        let groups = NotesListGrouping.monthGroups(
            for: NotesListVisibility.notepadNotes([jul, aug]),
            dateKey: { DateFormatters.dateKey(from: $0.createdAt) }
        )

        #expect(groups.map(\.id) == ["2026-08", "2026-07"])
        #expect(groups[0].notes.map(\.id) == [aug.id])
        #expect(groups[1].notes.map(\.id) == [jul.id])
    }

    // MARK: - Month grouping over the filtered list

    @Test func monthGroupingFormsRunsOverTheFilteredList() throws {
        let context = try makeContext()
        let aug9 = daily("2026-08-09", content: "a", in: context)
        let aug2 = daily("2026-08-02", content: "b", in: context)
        let jul20 = daily("2026-07-20", content: "c", in: context)

        let groups = NotesListGrouping.monthGroups(for: [aug9, aug2, jul20], dateKey: { $0.dateKey })

        #expect(groups.map(\.id) == ["2026-08", "2026-07"])
        #expect(groups[0].notes.map(\.id) == [aug9.id, aug2.id])
        #expect(groups[1].notes.map(\.id) == [jul20.id])
        #expect(groups[0].title == "AUGUST 2026")
    }

    /// A month whose every note was filtered out must not leave its header behind. Grouping runs
    /// over the already-filtered list and only emits a group it has notes for, so July vanishes
    /// header and all — and August's run stays one run rather than splitting around the gap.
    @Test func monthEmptiedByFilteringRendersNoHeader() throws {
        let context = try makeContext()
        let aug9 = daily("2026-08-09", content: "a", in: context)
        let julEmpty1 = daily("2026-07-20", content: "", in: context)
        let julEmpty2 = daily("2026-07-19", content: "   ", in: context)
        let aug2 = daily("2026-06-30", content: "b", in: context)

        let listed = NotesListVisibility.dailyNotes(
            [aug9, julEmpty1, julEmpty2, aug2],
            todayKey: "2026-08-10"
        )
        let groups = NotesListGrouping.monthGroups(for: listed, dateKey: { $0.dateKey })

        #expect(groups.map(\.id) == ["2026-08", "2026-06"])
        #expect(groups.allSatisfy { !$0.notes.isEmpty })
    }

    @Test func groupsNeverRenderEmptyEvenWhenEverythingIsFiltered() throws {
        let context = try makeContext()
        let empties = [
            daily("2026-07-20", content: "", in: context),
            daily("2026-06-19", content: "\n\n", in: context)
        ]

        let listed = NotesListVisibility.dailyNotes(empties, todayKey: "2026-08-10")

        #expect(listed.isEmpty)
        #expect(NotesListGrouping.monthGroups(for: listed, dateKey: { $0.dateKey }).isEmpty)
    }
}
#endif
