import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5015]] (b)'s store write, which is the half of the owner's decision that can lose data.**
///
/// Removing a control is visible the moment it is wrong. A migration is not: it runs once, on a
/// store nobody is looking at, and a sweep that is too wide reads exactly like a sweep that is
/// correct. So the assertions here are deliberately two-sided — what moves, *and* what must not —
/// and the pass is driven through a real container, saved, and re-read through a fresh
/// `ModelContext` rather than asserted on the objects it was handed. An in-memory container over
/// `CadenceSchema` via `CadenceTestStore`, per `CadenceInMemoryStoreHygieneTests`; nothing here
/// goes near the real store, the app group or a backup directory.
struct CadenceInProgressStatusRetirementTests {

    /// Writes the **raw value**, never `task.status = .inProgress`, because what the pass has to
    /// find is the string on disk — and because the Swift case is one rename away from a fixture
    /// that silently stops seeding the thing under test.
    private static func task(_ title: String, storedAs raw: String, completedAt: Date? = nil) -> AppTask {
        let task = AppTask(title: title)
        task.statusRaw = raw
        task.completedAt = completedAt
        return task
    }

    private static func statuses(in container: ModelContainer) throws -> [String: String] {
        let rows = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0.statusRaw) })
    }

    // MARK: - The claim

    /// **A stored `.inprogress` row comes back `.todo`, and no other status is touched.**
    ///
    /// The three survivors are the whole point. A pass that wrote `.todo` over everything would
    /// satisfy the first clause and destroy the user's completed and cancelled work, and that is
    /// the realistic way this goes wrong — so `done` and `cancelled` are asserted to still be
    /// `done` and `cancelled`, by raw value, after the save.
    @Test func aStoredInProgressRowComesBackTodoAndNoOtherStatusMoves() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        seed.insert(Self.task("started", storedAs: "inprogress"))
        seed.insert(Self.task("open", storedAs: "todo"))
        seed.insert(Self.task("finished", storedAs: "done", completedAt: Date(timeIntervalSince1970: 1)))
        seed.insert(Self.task("abandoned", storedAs: "cancelled", completedAt: Date(timeIntervalSince1970: 2)))
        try seed.save()

        // Non-vacuity: the fixture really is in the store as the retired raw value before the pass.
        #expect(try Self.statuses(in: container)["started"] == "inprogress")

        let outcome = CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container))
        #expect(outcome == .changed)

        let after = try Self.statuses(in: container)
        #expect(after["started"] == "todo", "the stranded row did not come back: \(after)")
        #expect(after["open"] == "todo", "a plain to-do was disturbed: \(after)")
        #expect(after["finished"] == "done", "a completed task was reopened: \(after)")
        #expect(after["abandoned"] == "cancelled", "a cancelled task was reopened: \(after)")
    }

    /// The settled rows keep their timestamps too. `completedAt` is "when this stopped being open"
    /// (T-202) and three surfaces read it to decide what belongs in Today's Completed section, so a
    /// sweep that cleared it store-wide would empty that section for every user without touching a
    /// single status — a silent loss the status assertions above cannot see.
    @Test func theSettledRowsKeepTheirCompletionTimestamps() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        seed.insert(Self.task("started", storedAs: "inprogress"))
        seed.insert(Self.task("finished", storedAs: "done", completedAt: stamp))
        seed.insert(Self.task("abandoned", storedAs: "cancelled", completedAt: stamp))
        try seed.save()

        _ = CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container))

        let rows = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        let kept = rows.filter { $0.title == "finished" || $0.title == "abandoned" }
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { $0.completedAt == stamp }, "a settled row lost its timestamp")
    }

    /// The rewritten row carries no timestamp. `.inProgress` was an open status, so a row in it
    /// should have had none — but an older build could have stamped one, and `.todo` with a
    /// `completedAt` is the inconsistent state `normalizeCompletionState` exists to rule out. The
    /// pass goes through `CadenceTaskRecurrenceWorkflowSupport.markTodo` rather than assigning
    /// `status` raw for exactly this.
    @Test func theRewrittenRowIsLeftConsistentlyOpen() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        seed.insert(Self.task("started", storedAs: "inprogress", completedAt: Date(timeIntervalSince1970: 99)))
        try seed.save()

        _ = CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container))

        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(row.statusRaw == "todo")
        #expect(row.completedAt == nil, "a reopened task kept a completion timestamp")
    }

    /// Nothing else on the task moves. The honest failure of a migration is not that it misses a
    /// row; it is that it rewrites a neighbouring field while it is in there.
    @Test func noFieldOtherThanStatusAndCompletionIsRewritten() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        let task = Self.task("started", storedAs: "inprogress")
        task.priority = .high
        task.scheduledDate = "2026-10-24"
        task.scheduledStartMin = 9 * 60
        task.estimatedMinutes = 75
        task.recurrenceRule = .weekly
        seed.insert(task)
        try seed.save()

        _ = CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container))

        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(row.priority == .high)
        #expect(row.scheduledDate == "2026-10-24")
        #expect(row.scheduledStartMin == 9 * 60)
        #expect(row.estimatedMinutes == 75)
        #expect(row.recurrenceRule == .weekly)
    }

    // MARK: - Running it more than once

    /// **Idempotent, and self-guarding rather than flag-guarded.** A second run over the store the
    /// first one produced answers `nothingToDo` and changes nothing — which is what "do not run it
    /// more than once per store" asks for, delivered by the fetch instead of by a `UserDefaults`
    /// latch that would also stop it seeing rows arriving later from CloudKit or an archive.
    @Test func asecondRunFindsNothingToDo() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        seed.insert(Self.task("started", storedAs: "inprogress"))
        seed.insert(Self.task("finished", storedAs: "done", completedAt: Date(timeIntervalSince1970: 3)))
        try seed.save()

        #expect(CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container)) == .changed)
        #expect(CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container)) == .nothingToDo)

        let after = try Self.statuses(in: container)
        #expect(after["started"] == "todo")
        #expect(after["finished"] == "done")
    }

    /// A store that never held one is `nothingToDo` on the first run, so the pass is inert on a
    /// first launch and on every launch after the one that cleaned up.
    @Test func astoreWithNoInProgressRowIsNothingToDo() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        seed.insert(Self.task("open", storedAs: "todo"))
        try seed.save()

        #expect(CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container)) == .nothingToDo)
    }

    /// **A row arriving after the first pass is still rescued**, which is the behaviour a latched
    /// one-shot would not have. This is the CloudKit / archive-import case stated as a test:
    /// another device on an older build writes `.inprogress` long after this device's first
    /// launch, and the next launch must still take it.
    @Test func arowArrivingAfterTheFirstPassIsStillRetired() throws {
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        seed.insert(Self.task("first", storedAs: "inprogress"))
        try seed.save()
        #expect(CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container)) == .changed)

        let late = ModelContext(container)
        late.insert(Self.task("arrived later", storedAs: "inprogress"))
        try late.save()

        #expect(CadenceInProgressStatusRetirement.runIfNeeded(modelContext: ModelContext(container)) == .changed)
        #expect(try Self.statuses(in: container)["arrived later"] == "todo")
    }

    // MARK: - Refusal

    /// A refused save is `couldNotRead`, never `nothingToDo` — the distinction [[T-1402]] drew,
    /// because a launch that *could not* retire the rows must not read like a launch with no rows
    /// to retire — and the rows are put back rather than left half-rewritten in the context.
    @Test func arefusedSaveReportsFailureAndPutsTheRowsBack() throws {
        struct Refused: Error {}
        let container = try CadenceTestStore.container()
        let seed = ModelContext(container)
        seed.insert(Self.task("started", storedAs: "inprogress"))
        try seed.save()

        let context = ModelContext(container)
        let outcome = CadenceInProgressStatusRetirement.runIfNeeded(modelContext: context) { _ in
            throw Refused()
        }
        #expect(outcome == .couldNotRead)

        let row = try #require(try context.fetch(FetchDescriptor<AppTask>()).first)
        #expect(row.status == .inProgress, "the refusal left the row rewritten in the context")
        #expect(try Self.statuses(in: container)["started"] == "inprogress", "a refused save reached the store")
    }

    // MARK: - The drawing rule

    /// `.inProgress` draws no chip, exactly as `.todo` draws none, and the two settled statuses
    /// still do. The markdown task embed reads a *snapshot* `statusRaw`, so it can be handed
    /// "inprogress" from an index written before the pass ran; it must draw like the plain to-do
    /// the store now holds.
    @Test func inProgressDrawsNoStatusChipAndTheSettledStatusesStillDo() {
        #expect(CadenceInProgressStatusRetirement.drawsStatusChip(.inProgress) == false)
        #expect(CadenceInProgressStatusRetirement.drawsStatusChip(.todo) == false)
        #expect(CadenceInProgressStatusRetirement.drawsStatusChip(.done))
        #expect(CadenceInProgressStatusRetirement.drawsStatusChip(.cancelled))
    }

    // MARK: - The enum case, which must survive all of this

    /// **The case stays, and this is the test that says why.** `"inprogress"` is a persisted raw
    /// value: deleting the case would make every row an earlier build wrote fail to decode. So the
    /// requirement is not "In Progress is gone from the type", it is "In Progress is gone from the
    /// controls and the surfaces, and still decodes" — and a future cleanup that reaches for the
    /// enum reds here instead of shipping.
    @Test func theRetiredRawValueStillDecodes() {
        #expect(TaskStatus(rawValue: "inprogress") == .inProgress)
        #expect(CadenceInProgressStatusRetirement.retiredRawValue == "inprogress")
    }

    /// **No control anywhere offers the status.** `StatusAction` is the shared set all three former
    /// writers render — `iOSTaskStatusActionsSection`, `TaskDetailActionsSection` and the
    /// macOS note-embed `TaskEmbedFieldEditorPopover` — so a case reappearing here is a Start
    /// button reappearing on three surfaces, and this is the one assertion that catches it.
    @Test func noStatusActionCanWriteInProgress() {
        let reachable = CadenceTaskInspectorSupport.StatusAction.allCases.flatMap { action in
            TaskStatus.allCases.map { action.target(from: $0) }
        }
        #expect(!reachable.contains(.inProgress), "a status control can still write In Progress")
        #expect(CadenceTaskInspectorSupport.StatusAction.allCases.map(\.status) == [.cancelled])
    }
}
