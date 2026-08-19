import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Comparators that used to stop at a key two tasks can share.
///
/// The failure is not cosmetic on either of these surfaces. `MarkdownReferenceCompletionSupport`
/// feeds a `.prefix(6)` completion menu and `CadenceFocusSupport.readyTasks` is read head-first by
/// Focus, so an undefined tail changes *which* items are offered, not merely the order behind
/// them — the argument `GoalContributionSummary` already makes in code for its own sort.
///
/// Each test sorts the same set from two different starting permutations and requires identical
/// output. Swift's `sort` is not stable, so a comparator that leaves pairs undecided returns a
/// different arrangement for a different input order; a total one cannot.
@MainActor
struct TaskComparatorTotalityTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Eight tasks that tie on every key the old comparators looked at: same `isDone`, same
    /// priority, same `order` (which is what tasks from different containers look like, since
    /// `nextTaskOrder(in:)` maxes over one list), and the same `createdAt` — a rollover, a paste,
    /// or a migration creates a whole batch inside one timestamp.
    private func tieHeavyTasks(in context: ModelContext) -> [AppTask] {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let titles = [
            "Draft the agenda",
            "Book the venue",
            "Call the supplier",
            "Email the team",
            "File the receipts",
            "Gather the quotes",
            "Hire the contractor",
            "Invoice the client"
        ]

        return titles.map { title in
            let task = AppTask(title: title)
            task.order = 0
            task.createdAt = created
            context.insert(task)
            return task
        }
    }

    // MARK: - `[[` reference completion

    @Test func referenceCandidateTasksSortTheSameSetIdenticallyFromAnyStartingOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = tieHeavyTasks(in: context)

        let forward = MarkdownReferenceCompletionSupport.candidateTasks(from: tasks, query: "")
        let backward = MarkdownReferenceCompletionSupport.candidateTasks(from: tasks.reversed(), query: "")

        #expect(forward.map(\.title) == backward.map(\.title))
    }

    /// The menu shows six of eight. With an undecided tail, "which six" is whatever arrangement
    /// `sort` happened to return, so the same keystroke offers different tasks on different runs.
    @Test func theSixOfferedCompletionsDoNotDependOnTheInputOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = tieHeavyTasks(in: context)

        let forward = Set(
            MarkdownReferenceCompletionSupport.candidateTasks(from: tasks, query: "").prefix(6).map(\.id)
        )
        let backward = Set(
            MarkdownReferenceCompletionSupport.candidateTasks(from: tasks.reversed(), query: "").prefix(6).map(\.id)
        )

        #expect(forward.count == 6)
        #expect(forward == backward)
    }

    /// The ordering the tie-break sits *under* is unchanged: open before done, then priority.
    @Test func referenceCandidatesStillLeadWithOpenWorkThenPriority() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let done = AppTask(title: "Alpha")
        done.status = .done
        done.priority = .high
        let low = AppTask(title: "Beta")
        low.priority = .low
        let high = AppTask(title: "Gamma")
        high.priority = .high
        for task in [done, low, high] { context.insert(task) }

        let sorted = MarkdownReferenceCompletionSupport.candidateTasks(from: [done, low, high], query: "")

        #expect(sorted.map(\.title) == ["Gamma", "Beta", "Alpha"])
    }

    @Test func referenceCandidatesDropCancelledWorkAndHonourTheQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let cancelled = AppTask(title: "Cancelled venue")
        cancelled.status = .cancelled
        let match = AppTask(title: "Book the venue")
        let miss = AppTask(title: "Email the team")
        for task in [cancelled, match, miss] { context.insert(task) }

        let all = MarkdownReferenceCompletionSupport.candidateTasks(from: [cancelled, match, miss], query: "  ")
        let filtered = MarkdownReferenceCompletionSupport.candidateTasks(from: [cancelled, match, miss], query: "VENUE")

        #expect(all.count == 2)
        #expect(filtered.map(\.title) == ["Book the venue"])
    }

    /// The notes half of the same picker. Already total — `updatedAt` then title then `id` — and
    /// pinned so the shared spelling stays that way.
    @Test func referenceCandidateNotesSortTheSameSetIdenticallyFromAnyStartingOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let updated = Date(timeIntervalSince1970: 1_700_000_000)

        let notes = ["Weekly review", "Weekly review", "Weekly review"].map { title -> Note in
            let note = Note(kind: .permanent, title: title)
            note.updatedAt = updated
            context.insert(note)
            return note
        }

        let forward = MarkdownReferenceCompletionSupport.candidateNotes(from: notes, query: "")
        let backward = MarkdownReferenceCompletionSupport.candidateNotes(from: notes.reversed(), query: "")

        #expect(forward.map(\.id) == backward.map(\.id))
    }

    // MARK: - Focus's ready list

    @Test func focusReadyTasksSortTheSameSetIdenticallyFromAnyStartingOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = tieHeavyTasks(in: context)
        let todayKey = DateFormatters.todayKey()

        let forward = CadenceFocusSupport.readyTasks(from: tasks, todayKey: todayKey)
        let backward = CadenceFocusSupport.readyTasks(from: tasks.reversed(), todayKey: todayKey)

        #expect(forward.map(\.title) == backward.map(\.title))
    }

    /// Focus offers the head of this list, so "which task is offered" is the thing the tie-break
    /// actually decides.
    @Test func theTaskFocusOffersFirstDoesNotDependOnTheInputOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tasks = tieHeavyTasks(in: context)
        let todayKey = DateFormatters.todayKey()

        let forward = CadenceFocusSupport.readyTasks(from: tasks, todayKey: todayKey).first?.id
        let backward = CadenceFocusSupport.readyTasks(from: tasks.reversed(), todayKey: todayKey).first?.id

        #expect(forward != nil)
        #expect(forward == backward)
    }

    /// The scoring the tie-break sits under is unchanged: today's work still outranks undated
    /// work, and finished work is still excluded outright.
    @Test func focusReadyTasksStillScoreTodayAheadOfUndatedAndExcludeFinishedWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let todayKey = DateFormatters.todayKey()

        let today = AppTask(title: "Today")
        today.scheduledDate = todayKey
        let undated = AppTask(title: "Undated")
        let done = AppTask(title: "Done")
        done.status = .done
        done.scheduledDate = todayKey
        for task in [today, undated, done] { context.insert(task) }

        let ready = CadenceFocusSupport.readyTasks(from: [undated, done, today], todayKey: todayKey)

        #expect(ready.map(\.title) == ["Today", "Undated"])
    }
}
