import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-319: iOS task creation reported success for a task that was not saved.
///
/// `iOSCreateTaskSheet.create()` built the task, called `try? modelContext.save()`, and then ran
/// the entire success experience over the result — a notification reconcile pass, `onCreated?`,
/// and a dismissal — with no branch in which the save had failed. The user watched the sheet close
/// on a task the store never took.
///
/// **Two halves, both load-bearing.** The behavioural half runs against a real container through
/// `TaskCreationService.createTask`, which is where the commit now lives and which this test
/// target can reach. The source half pins that the sheet uses it and that nothing below the commit
/// runs when it throws — `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS,
/// so a scan is the only tool available for the view itself.
@MainActor
struct CadenceCreateTaskCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private func draft(
        title: String,
        subtaskTitles: [String] = []
    ) -> TaskCreationDraft {
        TaskCreationDraft(
            title: title,
            notes: "Typed by hand.",
            priority: .high,
            container: .inbox,
            sectionName: "",
            dueDateKey: "2026-06-20",
            scheduledDateKey: "",
            subtaskTitles: subtaskTitles,
            tags: []
        )
    }

    // MARK: - What the commit actually does

    /// The success path, asserted from a **second context on the same container**: a single-context
    /// assertion passes against the bug, because the sheet's own context reports the task present
    /// whether or not the save threw.
    @Test func acreatedTaskIsInTheStoreBeforeTheSheetCouldClose() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let task = try #require(
            try TaskCreationService(areas: [], projects: [])
                .createTask(from: draft(title: "Ship the fix", subtaskTitles: ["First", "Second"]),
                            into: modelContext)
        )
        #expect(task.title == "Ship the fix")
        #expect(!modelContext.hasChanges, "the creation was left pending in the context")

        let store = ModelContext(container)
        let stored = try store.fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 1)
        #expect(stored.first?.title == "Ship the fix")
        #expect(stored.first?.notes == "Typed by hand.")
        #expect(stored.first?.priority == .high)
        #expect(stored.first?.dueDate == "2026-06-20")
        #expect(
            try store.fetch(FetchDescriptor<Subtask>()).map(\.title).sorted() == ["First", "Second"],
            "the subtasks were inserted but never committed"
        )
    }

    /// The failure path. A creation rolls back: the composer still holds every field the user
    /// typed, so undoing and reporting is strictly better than half-creating.
    @Test func acreationThatCannotBeCommittedTakesItsTaskAndSubtasksBackOut() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        #expect(throws: CommitRefused.self) {
            try TaskCreationService(areas: [], projects: [])
                .createTask(
                    from: draft(title: "Never lands", subtaskTitles: ["Orphan"]),
                    into: modelContext,
                    commit: { _ in throw CommitRefused() }
                )
        }

        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty,
            "the sheet's own context still holds the task the commit refused"
        )
        #expect(
            try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty,
            "the subtask outlived the task, attached to nothing"
        )
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// A failed creation must not take the user's existing tasks with it. This is why the insert
    /// undo deletes what it inserted rather than rolling the context back.
    @Test func afailedCreationLeavesTheTasksAlreadyInTheStoreAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let existing = AppTask(title: "Yesterday's task")
        modelContext.insert(existing)
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try TaskCreationService(areas: [], projects: [])
                .createTask(
                    from: draft(title: "Never lands"),
                    into: modelContext,
                    commit: { _ in throw CommitRefused() }
                )
        }

        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title)
                == ["Yesterday's task"])
    }

    /// An empty title is "nothing to create", not a failure — the same answer `insertTask` gave,
    /// and the reason `create()` can still `guard let task` after the `do`/`catch`.
    @Test func anEmptyDraftIsNilRatherThanAThrow() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        #expect(try TaskCreationService(areas: [], projects: [])
            .createTask(from: draft(title: "   "), into: modelContext) == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// The sentence the sheet shows, held next to the service that produces the failure so the
    /// composers cannot come to word it differently.
    @Test func theCreationFailureNoticeNamesTheSave() {
        #expect(TaskCreationService.saveFailureNotice == "Couldn't save this task.")
    }

    // MARK: - The sheet

    /// `create()` is a private method on a SwiftUI view, so this is scoped to its **function
    /// body**, and the ordering is asserted as positions rather than as "contains".
    ///
    /// The bug was not that the sheet failed to save. It was that everything after the save ran
    /// unconditionally: the reconcile, the callback and the dismissal are the success experience,
    /// and each one has to sit after the point where a throw has already returned.
    @Test func theIOSComposerCommitsBeforeItReportsSuccess() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCreateTaskSheet.swift")
        #expect(raw.count > 400, "iOSCreateTaskSheet.swift read as \(raw.count) characters")

        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let create = try #require(
            CadenceSourceScan.functionBody(named: "create", in: stripped),
            "could not find create()"
        )

        // It goes through the committing entry point, and the old swallowed save is gone.
        #expect(create.contains(".createTask("))
        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0,
            "create() still swallows an error"
        )
        #expect(CadenceSourceScan.matchCount(#"insertTask\("#, in: create) == 0)

        // The failure branch exists and says why.
        let failure = try #require(
            create.range(of: "actionError = TaskCreationService.saveFailureNotice"),
            "create() has no branch that reports a failed commit"
        )
        let failureReturn = try #require(
            create.range(of: "return", range: failure.upperBound..<create.endIndex),
            "the failure branch falls through into the success path"
        )

        // And every part of the success experience sits after it.
        for spelling in ["HabitNotificationReconcileSupport.scheduleReconcile", "onCreated?(", "dismiss()"] {
            let success = try #require(
                create.range(of: spelling),
                "create() no longer spells \(spelling)"
            )
            #expect(
                success.lowerBound > failureReturn.upperBound,
                "\(spelling) runs before the failed commit has returned"
            )
        }

        // Exactly one dismissal in create(), so there is no second unguarded one below.
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: create) == 1)
    }

    /// The needles above match the spelling they hunt and miss the one they protect — otherwise
    /// the two `== 0` assertions are true of any text at all.
    @Test func theSwallowedSaveNeedlesMatchTheOldSpellingsOnly() {
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try? modelContext.save()") == 1)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try service.createTask(from: draft, into: c)") == 0)
        #expect(CadenceSourceScan.matchCount(#"insertTask\("#, in: ".insertTask(from: draft, into: c)") == 1)
        #expect(CadenceSourceScan.matchCount(#"insertTask\("#, in: ".createTask(from: draft, into: c)") == 0)
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: "dismiss()") == 1)
    }
}
