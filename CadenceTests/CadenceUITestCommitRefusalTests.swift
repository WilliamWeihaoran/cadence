import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-11512 — `CADENCE_UI_TEST_REFUSE_COMMITS`, the switch that makes a refusal notice sightable.**
///
/// Three claims, each mutation-tested:
/// 1. **Off ⇒ the commit proceeds.** The test host carries neither variable, so every default
///    `refusing:` is `false` and the caller's `commit:` runs.
/// 2. **The variable without UI-test mode ⇒ off.** The gate is both halves; a shipping launch carries
///    neither, and the refuse variable alone must not arm it.
/// 3. **Armed ⇒ every commit throws `CadenceUITestCommitRefusal.Refused` BEFORE the caller's `commit:` runs**, and
///    then takes the same undo a real refused save takes. "Before" is the whole hazard: the two
///    out-of-process levers that reach SQLite freeze or crash the app instead of refusing.
///
/// The armed half is driven through each commit's `refusing:` parameter rather than the process
/// environment, which a unit test cannot set before the switch is read.
@MainActor
struct CadenceUITestCommitRefusalTests {

    private typealias Persistence = CadencePendingChangePersistence

    /// Counts how often a caller's `commit:` actually ran; an armed refusal must leave it at zero.
    private final class CommitCounter {
        var count = 0
        func commit(_ modelContext: ModelContext) throws {
            count += 1
            try modelContext.save()
        }
    }

    // MARK: - The gate

    @Test func theGateArmsOnlyWhenBothVariablesSayOne() {
        let refuse = CadenceUITestCommitRefusal.variable
        #expect(refuse == "CADENCE_UI_TEST_REFUSE_COMMITS")

        #expect(CadenceUITestCommitRefusal.isArmed(in: ["CADENCE_UI_TEST_MODE": "1", refuse: "1"]))

        #expect(!CadenceUITestCommitRefusal.isArmed(in: [:]))
        #expect(
            !CadenceUITestCommitRefusal.isArmed(in: [refuse: "1"]),
            "the refuse variable alone armed the switch outside UI-test mode"
        )
        #expect(
            !CadenceUITestCommitRefusal.isArmed(in: ["CADENCE_UI_TEST_MODE": "1"]),
            "UI-test mode alone refused commits, so every UI test would now refuse"
        )
        #expect(!CadenceUITestCommitRefusal.isArmed(in: ["CADENCE_UI_TEST_MODE": "0", refuse: "1"]))
        #expect(!CadenceUITestCommitRefusal.isArmed(in: ["CADENCE_UI_TEST_MODE": "1", refuse: "0"]))
        #expect(!CadenceUITestCommitRefusal.isArmed(in: ["CADENCE_UI_TEST_MODE": "1", refuse: "true"]))
    }

    /// The app's own name for it is the seam's, not a second spelling.
    @Test func theUITestSupportNamesTheSameVariable() {
        #expect(CadenceUITestSupport.refuseCommitsVariable == CadenceUITestCommitRefusal.variable)
    }

    // MARK: - Off: the commit proceeds

    @Test func theTestHostIsNotArmedAndADefaultCommitReachesTheStore() throws {
        #expect(
            !Persistence.refusesCommitsForUITest,
            "the test host is armed, so every default commit in every suite would refuse"
        )

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Committed with the switch off")
        modelContext.insert(task)
        let counter = CommitCounter()

        try Persistence.commitInsert(of: task, in: modelContext, commit: counter.commit)

        #expect(counter.count == 1, "the caller's commit did not run with the switch off")
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(stored.map(\.title) == ["Committed with the switch off"])
    }

    // MARK: - Armed: every commit refuses before the caller's commit runs

    @Test func anArmedInsertRefusesBeforeCommittingAndTakesTheInsertBackOut() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Refused insert")
        modelContext.insert(task)
        let counter = CommitCounter()

        #expect(throws: CadenceUITestCommitRefusal.Refused.self) {
            try Persistence.commitInsert(of: task, in: modelContext, commit: counter.commit, refusing: true)
        }

        #expect(counter.count == 0, "an armed refusal still ran the caller's commit")
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty, "the refused insert is still in the context")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    @Test func anArmedEditRefusesBeforeCommittingAndRunsTheUndo() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Old")
        modelContext.insert(task)
        try modelContext.save()
        task.title = "New"
        let counter = CommitCounter()

        #expect(throws: CadenceUITestCommitRefusal.Refused.self) {
            try Persistence.commitEdit(in: modelContext, commit: counter.commit, refusing: true) {
                task.title = "Old"
            }
        }

        #expect(counter.count == 0, "an armed refusal still ran the caller's commit")
        #expect(task.title == "Old", "the refused edit was not undone")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Old"])
    }

    @Test func anArmedTypedContentFlushAnswersFalseAndLeavesTheTextPending() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Typed")
        modelContext.insert(task)
        let counter = CommitCounter()

        let committed = Persistence.commitTypedContent(in: modelContext, commit: counter.commit, refusing: true)

        #expect(!committed)
        #expect(counter.count == 0, "an armed refusal still ran the caller's commit")
        #expect(modelContext.hasChanges, "the typed content was discarded rather than left pending")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    @Test func anArmedDeleteRefusesBeforeCommittingAndPutsTheRowBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Survives a refused delete")
        modelContext.insert(task)
        try modelContext.save()
        modelContext.delete(task)
        let counter = CommitCounter()

        #expect(throws: CadenceUITestCommitRefusal.Refused.self) {
            try Persistence.commitDelete(in: modelContext, commit: counter.commit, refusing: true)
        }

        #expect(counter.count == 0, "an armed refusal still ran the caller's commit")
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1, "the refused delete still hides the row")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    @Test func anArmedBuildingDeleteRefusesAfterBuildingAndRollsBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Survives a refused reset")
        modelContext.insert(task)
        try modelContext.save()
        let counter = CommitCounter()

        #expect(throws: CadenceUITestCommitRefusal.Refused.self) {
            try Persistence.commitDelete(in: modelContext, commit: counter.commit, refusing: true) {
                modelContext.delete(task)
            }
        }

        #expect(counter.count == 0, "an armed refusal still ran the caller's commit")
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// The refusal belongs to the LEAF of a cascade: the survivor undo runs, then the rollback —
    /// the order a real refused save takes. A `commitDelete` that refused first would roll back
    /// with the held undo never run.
    @Test func anArmedCascadeRunsItsSurvivorUndoBeforeRollingBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let doomed = AppTask(title: "Doomed")
        let survivor = AppTask(title: "Survivor")
        modelContext.insert(doomed)
        modelContext.insert(survivor)
        try modelContext.save()
        let counter = CommitCounter()
        let effects = CadenceDeferredDeleteEffects()

        #expect(throws: CadenceUITestCommitRefusal.Refused.self) {
            try Persistence.commitCascade(
                in: modelContext,
                commit: counter.commit,
                refusing: true,
                effects: effects
            ) {
                modelContext.delete(doomed)
                survivor.title = "Rewritten by the cascade"
                CadenceDeferredDeleteEffects.current?.holdUndo { survivor.title = "Survivor" }
                return true
            }
        }

        #expect(counter.count == 0, "an armed refusal still ran the caller's commit")
        #expect(effects.heldUndoCount == 0, "the cascade's survivor undo never ran")
        #expect(survivor.title == "Survivor", "the refused cascade left the survivor rewritten")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).count == 2)
    }

    /// The surface reads `localizedDescription` in places; it must say what refused.
    @Test func theRefusalNamesTheSwitch() {
        let error: any Error = CadenceUITestCommitRefusal.Refused()
        #expect(error.localizedDescription.contains("CADENCE_UI_TEST_REFUSE_COMMITS"))
    }

    // MARK: - Every commit goes through the one refusing seam

    /// Read from the source: a commit added later that calls its `commit:` directly would be the
    /// one surface the switch cannot reach, and nothing behavioural above would notice.
    @Test func everyCommitInThePersistenceSpineRunsThroughTheRefusingSeam() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadencePendingChangePersistence.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.contains("enum CadencePendingChangePersistence"), "non-vacuity: the reader returned no content")

        #expect(
            CadenceSourceScan.matchCount(#"try commit\("#, in: code) == 1,
            "a commit runs its caller's commit: outside `perform`, so the UI-test switch cannot refuse it"
        )
        #expect(
            CadenceSourceScan.matchCount(#"commit: \(ModelContext\) throws -> Void = \{ try \$0\.save\(\) \},\s+refusing: Bool = refusesCommitsForUITest"#, in: code) == 7,
            "a commit in the spine no longer defaults its refusal to the process switch"
        )
        #expect(CadenceSourceScan.matchCount(#"try perform\(commit, on: modelContext, refusing: refusing\)"#, in: code) == 4)
    }
}
