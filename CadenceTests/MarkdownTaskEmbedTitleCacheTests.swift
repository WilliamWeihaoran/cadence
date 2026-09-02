import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The title inside `[[task:UUID|Title]]` is a **cache**, and the task is the record.
///
/// Nothing sweeps notes when a task is renamed — that would be an unindexed scan over every note on
/// a field with no commit boundary — so the note text is expected to go stale, and every reader
/// that shows a title to a user resolves it through `MarkdownTaskEmbedTitleCache` first. These
/// tests are that contract: a renamed task is named by its new title everywhere it is read, a
/// deleted task keeps the only name it has left, and a note with no embeds is not touched at all.
@MainActor
struct MarkdownTaskEmbedTitleCacheTests {
    private static let taskID = UUID(uuidString: "6F3B7C1E-0A2D-4E5F-8B90-1C2D3E4F5A6B")!
    private static let otherID = UUID(uuidString: "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D")!

    private func reference(_ id: UUID, _ title: String) -> String {
        "[[task:\(id.uuidString)|\(title)]]"
    }

    private func makeContainer() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    // MARK: - Resolution

    @Test func staleEmbedTitleReadsAsTheTasksCurrentTitle() {
        let note = """
        # Standup

        \(reference(Self.taskID, "Draft the brief"))
        """

        let resolved = MarkdownTaskEmbedTitleCache.resolving(
            note,
            titles: [Self.taskID: "Draft the Q3 brief"]
        )

        #expect(resolved.contains(reference(Self.taskID, "Draft the Q3 brief")))
        #expect(!resolved.contains("Draft the brief]]"))
    }

    /// Every reference to the same task is resolved, not just the first — a note can embed one task
    /// in a checklist and again in a summary line.
    @Test func everyReferenceToTheSameTaskIsResolved() {
        let note = """
        \(reference(Self.taskID, "Old"))

        Later: \(reference(Self.taskID, "Old"))
        """

        let resolved = MarkdownTaskEmbedTitleCache.resolving(note, titles: [Self.taskID: "New"])

        #expect(!resolved.contains("|Old]]"))
        #expect(resolved.components(separatedBy: "|New]]").count == 3)
    }

    /// A task that no longer exists is not in `titles`, and its cached title is the only name that
    /// reference has left — the same string `MarkdownTaskEmbedRenderInfo.missing(reference:)` draws.
    @Test func aDeletedTasksReferenceKeepsItsCachedTitle() {
        let note = "\(reference(Self.taskID, "Renamed"))\n\(reference(Self.otherID, "Gone forever"))"

        let resolved = MarkdownTaskEmbedTitleCache.resolving(note, titles: [Self.taskID: "Renamed twice"])

        #expect(resolved.contains(reference(Self.taskID, "Renamed twice")))
        #expect(resolved.contains(reference(Self.otherID, "Gone forever")))
    }

    @Test func markdownWithoutEmbedsIsReturnedUnchanged() {
        let note = "# Notes\n\nNothing embedded here, just [[Another Note]] and text."

        #expect(MarkdownTaskEmbedTitleCache.resolving(note, titles: [Self.taskID: "Whatever"]) == note)
        #expect(MarkdownTaskEmbedTitleCache.resolving(note, titles: [:]) == note)
    }

    @Test func emptyTitleIndexLeavesEveryReferenceAlone() {
        let note = reference(Self.taskID, "Cached name")

        #expect(MarkdownTaskEmbedTitleCache.resolving(note, titles: [:]) == note)
    }

    /// A live title carrying `]` or `|` would end the reference early and leave raw brackets in the
    /// note where a card used to be, so resolution goes through the same sanitizer a rename does.
    @Test func aLiveTitleWithReferenceSyntaxStaysParseable() throws {
        let note = reference(Self.taskID, "Read chapter three")

        let resolved = MarkdownTaskEmbedTitleCache.resolving(
            note,
            titles: [Self.taskID: "Read [ch. 3] | notes"]
        )

        let parsed = try #require(MarkdownTaskEmbedParser.standaloneTaskReference(in: resolved))
        #expect(parsed.id == Self.taskID)
        #expect(parsed.title == "Read (ch. 3) - notes")
    }

    /// An untitled task falls back rather than collapsing the reference to `[[task:UUID|]]`, which
    /// the parser does not match at all.
    @Test func anEmptyLiveTitleFallsBackInsteadOfBreakingTheReference() throws {
        let note = reference(Self.taskID, "Had a name once")

        let resolved = MarkdownTaskEmbedTitleCache.resolving(note, titles: [Self.taskID: "   "])

        let parsed = try #require(MarkdownTaskEmbedParser.standaloneTaskReference(in: resolved))
        #expect(parsed.title == MarkdownTaskEmbedRenderInfo.untitledTaskTitle)
    }

    // MARK: - Title index

    @Test func titleIndexMapsEveryTaskByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "Book the venue")
        let second = AppTask(title: "Call the supplier")
        context.insert(first)
        context.insert(second)

        let titles = MarkdownTaskEmbedTitleCache.titles(for: [first, second])

        #expect(titles[first.id] == "Book the venue")
        #expect(titles[second.id] == "Call the supplier")
    }

    /// The whole point, spelled with real models: rename the task, and the note reads as the new
    /// name without anything having rewritten the note.
    @Test func renamingATaskChangesHowItsNoteReads() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Draft the brief")
        context.insert(task)
        let note = "Today: \(reference(task.id, "Draft the brief"))"

        task.title = "Draft the Q3 brief"

        let resolved = MarkdownTaskEmbedTitleCache.resolving(note, tasks: [task])
        #expect(resolved.contains("|Draft the Q3 brief]]"))
        #expect(!resolved.contains("|Draft the brief]]"))
    }

    // MARK: - Search shape

    /// What note-content search actually does with the resolved text: the note is findable under
    /// the task's current name and no longer under the one cached in its text.
    @Test func contentSearchFollowsTheRenameInBothDirections() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Draft the Q3 brief")
        context.insert(task)
        let content = "Agenda\n\n\(reference(task.id, "Draft the brief"))"

        let searchable = MarkdownTaskEmbedTitleCache.resolving(content, tasks: [task])

        #expect(searchable.localizedCaseInsensitiveContains("Q3 brief"))
        #expect(!searchable.localizedCaseInsensitiveContains("Draft the brief"))
    }

    // MARK: - Targeted fetch

    /// Export has no task query in scope, so it fetches by the ids in the note. The predicate is
    /// worth a test of its own: an unsupported `#Predicate` fails at *runtime*, and this is the one
    /// call site that would only discover that when a user clicks Export.
    @Test func embeddedTasksFetchesOnlyTheTasksTheNoteReferences() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let embedded = AppTask(title: "Book the venue")
        let unrelated = AppTask(title: "Call the supplier")
        context.insert(embedded)
        context.insert(unrelated)
        try context.save()
        let content = "\(reference(embedded.id, "Book the venue"))\n\(reference(Self.otherID, "Deleted"))"

        let fetched = MarkdownTaskEmbedTitleCache.embeddedTasks(in: content, modelContext: context)

        #expect(fetched.map(\.id) == [embedded.id])
    }

    @Test func embeddedTasksIsEmptyForANoteWithNoReferences() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(AppTask(title: "Book the venue"))
        try context.save()

        #expect(MarkdownTaskEmbedTitleCache.embeddedTasks(in: "Plain note", modelContext: context).isEmpty)
    }
}
