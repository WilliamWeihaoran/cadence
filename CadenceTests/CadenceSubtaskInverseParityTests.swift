import Foundation
import SwiftData
import Testing
@testable import Cadence

/// One question asked twice: is `Subtask.parentTask` trustworthy at the moment somebody reads it?
///
/// `CadenceTaskMutationSupport.deleteTasks` already answers "no" — it writes `subtask.parentTask = nil`
/// before deleting rather than letting SwiftData tear the inverse down on its own. T-296 and T-294
/// are the two places that answered "yes": two surfaces deleted a subtask without severing either
/// side, and the recurrence spawn built its subtask copies with only the parent's array assigned.
///
/// Every behavioural assertion below reads through a **second `ModelContext` on the same container**.
/// A first-context read cannot tell "the inverse is in the store" from "the inverse is a pointer
/// this context happens to be holding", which is the entire distinction both tickets turn on.
@MainActor
struct CadenceSubtaskInverseParityTests {
    private func makeContainer() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func fetchSubtasks(in container: ModelContainer) throws -> [Subtask] {
        try ModelContext(container).fetch(FetchDescriptor<Subtask>())
    }

    // MARK: - T-296: one shared subtask delete

    /// The shared helper must leave the store with no row *and* no surviving back-reference, and
    /// must not take the sibling with it.
    @Test func deletingASubtaskThroughTheSharedHelperLeavesNoRowAndNoBackReference() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Pack for the trip")
        let doomed = Subtask(title: "Find the passport")
        doomed.order = 0
        let survivor = Subtask(title: "Charge the camera")
        survivor.order = 1
        task.subtasks = [doomed, survivor]
        doomed.parentTask = task
        survivor.parentTask = task
        modelContext.insert(task)
        try modelContext.save()

        // Non-vacuity: the fixture really is two persisted subtasks before anything is deleted.
        #expect(try fetchSubtasks(in: container).count == 2)

        CadenceTaskMutationSupport.deleteSubtask(doomed, parent: task, modelContext: modelContext)

        // Read before any flush. This is the moment the surface that just called the helper
        // re-renders its subtask list from `task.subtasks`, and it is the only moment where the
        // strict path and the loose one differ: `modelContext.delete` alone leaves the deleted row
        // in the parent's array until `processPendingChanges` reconciles the inverse, so the row is
        // drawn from a model object that is already gone. Severing both sides by hand is what makes
        // the array correct immediately rather than eventually.
        #expect((task.subtasks ?? []).map(\.title) == ["Charge the camera"])

        modelContext.processPendingChanges()
        try modelContext.save()

        let remaining = try fetchSubtasks(in: container)
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Charge the camera")
        // The survivor keeps its own back-reference: the detach was aimed at one row, not the pair.
        #expect(remaining.first?.parentTask?.id == task.id)

        guard let storedTask = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first(where: { $0.id == task.id }) else {
            Issue.record("The parent task itself should have survived a subtask delete")
            return
        }
        #expect((storedTask.subtasks ?? []).map(\.title) == ["Charge the camera"])
    }

    /// The unpropagated-inverse case the helper exists for. macOS's `addSubtask` writes only
    /// `subtask.parentTask = task` and never appends to `task.subtasks`, so a caller that trusts the
    /// parent's array to know its own children is trusting back-population. Passing the owner in
    /// explicitly has to work when the array has not learned about the child yet.
    @Test func theSharedHelperDetachesASubtaskItsParentArrayNeverLearnedAbout() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Ship the release")
        modelContext.insert(task)
        let orphanedSide = Subtask(title: "Tag the build")
        orphanedSide.parentTask = task
        modelContext.insert(orphanedSide)
        try modelContext.save()

        #expect(try fetchSubtasks(in: container).count == 1)

        CadenceTaskMutationSupport.deleteSubtask(orphanedSide, parent: task, modelContext: modelContext)

        // Again before the flush: the owner was supplied by the caller rather than read back off
        // `subtask.parentTask`, and the parent's array must be right the instant the call returns.
        #expect((task.subtasks ?? []).isEmpty)

        modelContext.processPendingChanges()
        try modelContext.save()

        #expect(try fetchSubtasks(in: container).isEmpty)
        guard let storedTask = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first(where: { $0.id == task.id }) else {
            Issue.record("The parent task itself should have survived a subtask delete")
            return
        }
        #expect((storedTask.subtasks ?? []).isEmpty)
    }

    /// The two surfaces that used to open-code the delete now route through the shared helper.
    ///
    /// Source-scanned rather than called: both are `private func`s inside SwiftUI views, and
    /// `Cadence/iOS/` is not compiled into this macOS test target at all.
    @Test func theTwoSubtaskDeleteCallSitesRouteThroughTheSharedHelper() throws {
        let callSites = [
            "Cadence/iOS/iOSTaskDetailSheet.swift": "private func deleteSubtask(_ subtask: Subtask) {",
            "Cadence/macOS/Views/SchedulePanelComponents.swift": "onDeleteSubtask: { subtask in"
        ]

        for (relativePath, anchor) in callSites {
            let raw = try subtaskSourceFile(relativePath)
            let code = strippingSwiftComments(raw)

            // Non-vacuity: a missing or empty read, and a stripper that silently did nothing or
            // changed the file's length, all have to be red rather than quietly green.
            #expect(raw.count > 500, "\(relativePath) read back as \(raw.count) characters")
            #expect(code != raw, "\(relativePath) has no comments to strip; the stripper did nothing")
            #expect(code.count == raw.count, "\(relativePath) changed length under the stripper")
            #expect(code.contains(anchor), "\(relativePath) no longer contains \(anchor)")

            let routed = occurrences(
                of: "CadenceTaskMutationSupport.deleteSubtask(subtask, parent: task, modelContext: modelContext)",
                in: code
            )
            #expect(routed == 1, "\(relativePath) routes through the shared helper \(routed) times, expected 1")

            let openCoded = occurrences(of: "modelContext.delete(subtask)", in: code)
            #expect(openCoded == 0, "\(relativePath) still deletes a subtask directly \(openCoded) times")
        }
    }

    // MARK: - T-634: what a refused subtask commit leaves on the parent

    /// **Measurement, and the reason both task-detail surfaces carry one extra line.**
    ///
    /// `commitInsert`'s undo is `modelContext.delete(model)`, and `insertSubtask` had already
    /// written the row into `parent.subtasks`. The delete does **not** reach back into that array
    /// before the surface re-renders — the mirror image of the T-296 window this file already pins
    /// on the delete side — so a refused insert would leave a phantom subtask on screen. The
    /// caller's answer is the `CadenceListEditSnapshot` idiom shrunk to its one field: capture
    /// `task.subtasks` before the insert, put it back in the `catch`.
    ///
    /// The assertion order is load-bearing. Reading the array *before* the repair is the whole
    /// measurement; a test that only checked the end state would stay green if `commitInsert`
    /// started propagating on its own, and would tell nobody the extra line had become dead.
    @Test func arefusedSubtaskInsertLeavesAPhantomOnTheParentUntilTheCallerDropsIt() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Renew the passport")
        modelContext.insert(task)
        try modelContext.save()

        let restored = task.subtasks ?? []
        let subtask = try #require(
            CadenceTaskMutationSupport.insertSubtask(
                titled: "Book the appointment",
                into: task,
                modelContext: modelContext
            )
        )
        #expect((task.subtasks ?? []).map(\.title) == ["Book the appointment"])

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitInsert(of: subtask, in: modelContext) { _ in
                throw CommitRefused()
            }
        }

        // The store never took it, and the parent's array has not noticed.
        #expect(try fetchSubtasks(in: container).isEmpty)
        #expect((task.subtasks ?? []).map(\.title) == ["Book the appointment"])

        // The one line each surface adds.
        task.subtasks = restored
        #expect((task.subtasks ?? []).isEmpty)
    }

    /// The same question on the delete side, and it answers the opposite way round.
    ///
    /// `commitDelete` undoes with `rollback()`, which un-deletes the row — but `deleteSubtask` also
    /// *edited* `parent.subtasks` to drop it, and a rollback's undo of an edit is not visible on an
    /// already-materialised object until something refetches (T-402, pinned by
    /// `rollbackRestoresAnEditOnlyOnceSomethingRefreshesTheObject`). So a refused delete would take
    /// the row off the screen while the store still holds it: the user's subtask silently comes
    /// back on the next launch. Same repair, same captured array.
    @Test func arefusedSubtaskDeleteLeavesTheRowMissingFromTheParentUntilTheCallerPutsItBack() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Pack for the trip")
        modelContext.insert(task)
        let subtask = try #require(
            CadenceTaskMutationSupport.insertSubtask(
                titled: "Find the passport",
                into: task,
                modelContext: modelContext
            )
        )
        try modelContext.save()
        #expect(try fetchSubtasks(in: container).count == 1)

        let restored = task.subtasks ?? []
        CadenceTaskMutationSupport.deleteSubtask(subtask, parent: task, modelContext: modelContext)
        #expect((task.subtasks ?? []).isEmpty)

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitDelete(in: modelContext) { _ in
                throw CommitRefused()
            }
        }

        // The rollback put the row back in the store; it did not put it back on the parent.
        #expect(try fetchSubtasks(in: container).count == 1)
        #expect((task.subtasks ?? []).isEmpty)

        task.subtasks = restored
        #expect((task.subtasks ?? []).map(\.title) == ["Find the passport"])
    }

    private struct CommitRefused: Error {}

    // MARK: - T-294: recurrence copies own their back-reference

    /// The assertion the old recurrence test could not make. It read `next.subtasks` — the parent's
    /// array, which the spawn assigns by hand — so it stayed green whether or not the inverse was
    /// ever written. This fetches the `Subtask` rows themselves, from a second context, and reads
    /// `parentTask`.
    @Test func recurrenceCopiesCarryTheirParentBackReferenceIntoTheStore() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        let first = Subtask(title: "Kitchen windowsill")
        first.order = 0
        let second = Subtask(title: "Balcony pots")
        second.order = 1
        task.subtasks = [first, second]
        first.parentTask = task
        second.parentTask = task
        modelContext.insert(task)
        try modelContext.save()

        let originalIDs = Set([first.id, second.id])

        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        modelContext.processPendingChanges()
        try modelContext.save()

        guard let spawnedID = task.recurrenceSpawnedTaskID else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        #expect(spawnedID != task.id)

        let stored = try fetchSubtasks(in: container)
        #expect(stored.count == 4)

        let copies = stored.filter { !originalIDs.contains($0.id) }
        #expect(copies.count == 2)
        #expect(copies.map(\.title).sorted() == ["Balcony pots", "Kitchen windowsill"])
        // The point of the ticket: read the copy's own field, not the parent's array.
        #expect(copies.allSatisfy { $0.parentTask?.id == spawnedID })

        // And the originals still belong to the occurrence that was completed.
        let originals = stored.filter { originalIDs.contains($0.id) }
        #expect(originals.count == 2)
        #expect(originals.allSatisfy { $0.parentTask?.id == task.id })
    }

    /// The invariant itself, scanned rather than measured — and deliberately so.
    ///
    /// Measured, there is nothing to see: by the time the spawned occurrence reaches the store,
    /// SwiftData has back-populated `parentTask` on every copy on its own, so the test above passes
    /// with or without the explicit write (verified by mutation). The write is not there because
    /// the store currently needs it; it is there because every other subtask path in this codebase
    /// declines to depend on that back-population — `deleteTasks` nils the inverse before deleting,
    /// and `deleteSubtask` severs both sides — and one path quietly trusting it is how the two
    /// answers drift apart again. That makes this a convention with no observable consequence, which
    /// is exactly the kind of thing only a scan can hold.
    @Test func theRecurrenceSpawnWritesBothSidesOfTheSubtaskInverse() throws {
        let relativePath = "Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift"
        let raw = try subtaskSourceFile(relativePath)
        let code = strippingSwiftComments(raw)

        #expect(raw.count > 500, "\(relativePath) read back as \(raw.count) characters")
        #expect(code != raw, "\(relativePath) has no comments to strip; the stripper did nothing")
        #expect(code.count == raw.count, "\(relativePath) changed length under the stripper")
        #expect(code.contains("nextTask.subtasks = copies"), "the spawn no longer assigns the copies to the parent")

        let inverseWrites = occurrences(of: "copy.parentTask = nextTask", in: code)
        #expect(inverseWrites == 1, "the spawn writes the subtask inverse \(inverseWrites) times, expected 1")
    }

    /// Why the back-reference matters rather than being cosmetic. `Subtask.parentTask` has SwiftData's
    /// default nullify rule, so deleting a task does not take its subtasks with it — the shared
    /// delete path finds them by fetching every `Subtask` and matching `parentTask`. A copy the
    /// inverse never reached is a row that sweep cannot see, left behind forever.
    @Test func theSharedDeleteSweepFindsRecurrenceCopiesByTheirParentBackReference() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Weekly review")
        task.recurrenceRule = .weekly
        task.scheduledDate = "2026-08-04"
        let step = Subtask(title: "Clear the inbox")
        step.order = 0
        task.subtasks = [step]
        step.parentTask = task
        modelContext.insert(task)
        try modelContext.save()

        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        modelContext.processPendingChanges()
        try modelContext.save()

        guard let spawnedID = task.recurrenceSpawnedTaskID else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        #expect(try fetchSubtasks(in: container).count == 2)

        #expect(CadenceTaskMutationSupport.deleteTasks(withIDs: [spawnedID], modelContext: modelContext))

        let survivors = try fetchSubtasks(in: container)
        #expect(survivors.count == 1)
        #expect(survivors.first?.parentTask?.id == task.id)
    }

    // MARK: - T-338 / T-387: one shared subtask insert

    /// **The measurement the guide now cites, made into a test (T-401).**
    ///
    /// `Cadence/Models/AGENTS.md` says to append to an optional to-many by assigning a new array.
    /// On the delete side that is a repair for the window above. On the *create* side it is a
    /// convention, and this is why: inside the owning `ModelContext` SwiftData back-populates the
    /// inverse **and** the parent's array synchronously, so writing either side alone leaves the
    /// other already correct before any save. T-387 measured it by mutation — dropping
    /// `parent.subtasks = existing + [subtask]` and dropping `subtask.parentTask = parent` from
    /// the insert helper both left the suite green — but a surviving mutation is evidence that
    /// evaporates when the mutation is reverted. This asserts the fact directly, so it is still
    /// on record next time.
    ///
    /// Two independent audits filed a one-sided create as a defect (T-338, T-387) and T-294 hit it
    /// a third time; each cost real time fixing something that was not broken. **Red here does not
    /// mean the app regressed** — it means SwiftData stopped back-populating, the create-side rule
    /// became a repair after all, and the guide bullet needs rewriting.
    ///
    /// Read in the owning context on purpose, unlike every other test in this file: "is this true
    /// of a second context after a save" is a different and easier question, and the window the
    /// three tickets predicted is here, before the commit.
    @Test func swiftDataBackPopulatesEitherSideOfANewSubtaskInverse() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        // Half one: write only the child's back-reference and read the parent's array.
        let arrayNeverWritten = AppTask(title: "Attached from the child")
        modelContext.insert(arrayNeverWritten)
        #expect((arrayNeverWritten.subtasks ?? []).isEmpty, "the fixture starts with no children")

        let fromChild = Subtask(title: "Only parentTask was assigned")
        fromChild.parentTask = arrayNeverWritten
        modelContext.insert(fromChild)

        #expect(
            (arrayNeverWritten.subtasks ?? []).map(\.title) == ["Only parentTask was assigned"],
            """
            SwiftData no longer back-populates the parent's array from the inverse. \
            The create-side half of the to-many rule in Cadence/Models/AGENTS.md is now a repair; \
            rewrite that bullet before relaxing anything.
            """
        )

        // Half two: write only the parent's array and read the child's back-reference.
        let backReferenceNeverWritten = AppTask(title: "Attached from the parent")
        modelContext.insert(backReferenceNeverWritten)

        let fromParent = Subtask(title: "Only the array was assigned")
        modelContext.insert(fromParent)
        #expect(fromParent.parentTask == nil, "the fixture starts unattached")

        backReferenceNeverWritten.subtasks =
            (backReferenceNeverWritten.subtasks ?? []) + [fromParent]

        #expect(
            fromParent.parentTask?.id == backReferenceNeverWritten.id,
            """
            SwiftData no longer back-populates the inverse from the parent's array. \
            The create-side half of the to-many rule in Cadence/Models/AGENTS.md is now a repair; \
            rewrite that bullet before relaxing anything.
            """
        )

        // Non-vacuity for "before any commit": nothing above has been saved, so a second context
        // on the same container still sees an empty store. Last, because a fetch is exactly the
        // kind of refresh that would make this measure something else.
        #expect(try fetchSubtasks(in: container).isEmpty)
    }

    /// The insert helper's own contract: trimming, ordering, the blank-title guard, both sides
    /// before any save, and both sides again in the store afterwards.
    ///
    /// Read the `#expect`s on the two sides as a *specification*, not as a trap the one-sided
    /// writes would have sprung. They would not have: back-population makes them true either way
    /// (see the two call-site tests below). What they pin is that the helper never regresses to
    /// writing *neither* — dropping the insert, or attaching to the wrong parent.
    @Test func insertingASubtaskThroughTheSharedHelperWritesBothSidesBeforeAnySave() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Plan the offsite")
        modelContext.insert(task)
        try modelContext.save()

        // Non-vacuity: nothing is attached yet, so nothing below can be reading a fixture.
        #expect((task.subtasks ?? []).isEmpty)
        #expect(try fetchSubtasks(in: container).isEmpty)

        let first = try #require(CadenceTaskMutationSupport.insertSubtask(
            titled: "  Book the room  ",
            into: task,
            modelContext: modelContext
        ))
        let second = try #require(CadenceTaskMutationSupport.insertSubtask(
            titled: "Send the agenda",
            into: task,
            modelContext: modelContext
        ))

        #expect(first.title == "Book the room")
        #expect(first.order == 0)
        #expect(second.order == 1)

        // Both sides, in the window before the flush: the parent's array *and* each child's
        // back-reference.
        #expect((task.subtasks ?? []).sorted { $0.order < $1.order }.map(\.id) == [first.id, second.id])
        #expect(first.parentTask?.id == task.id)
        #expect(second.parentTask?.id == task.id)

        // A blank title is not a row, and does not consume an order slot.
        #expect(CadenceTaskMutationSupport.insertSubtask(
            titled: " \n ",
            into: task,
            modelContext: modelContext
        ) == nil)
        #expect((task.subtasks ?? []).count == 2)

        try modelContext.save()

        let sides = try storedSubtaskSides(in: container, taskID: task.id)
        #expect(sides.parentArray == ["Book the room", "Send the agenda"])
        #expect(sides.backReferenced == ["Book the room", "Send the agenda"])
    }

    /// The composer path, and the test that measured T-387's central claim and found it false.
    ///
    /// `TaskCreationService.insertTask` hands the task back *pending* — the sheet commits
    /// afterwards — so the window the ticket predicted is directly reachable here: a subtask
    /// attached by `subtask.parentTask = task` alone, read back through `task.subtasks` before any
    /// save. Run against the unfixed call site on 2026-08-28, every assertion below **passed**.
    /// SwiftData back-populates the inverse inside the owning context synchronously, so there is no
    /// interval in which the parent's array is stale. The create side is not the delete side, where
    /// T-296 measured a real window.
    ///
    /// It is kept because it is the first test on this path to read `Subtask.parentTask` at all —
    /// `TaskCreationServiceTests` asserts `task.subtasks` and nothing else, and the back-reference
    /// is the side `CadenceTaskMutationSupport.deleteTasks` sweeps by. A future change that leaves
    /// a subtask orphaned from its parent fails here rather than at the next delete.
    @Test func theComposerCreationPathWritesBothSidesBeforeItsCommit() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let draft = TaskCreationDraft(
            title: "Run the review",
            notes: "",
            priority: .none,
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: ["  Draft the deck  ", "", "Rehearse"],
            tags: []
        )

        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))

        // Non-vacuity for "before the commit": the rows are pending in this context only, so a
        // second context on the same container still sees an empty store.
        #expect(try fetchSubtasks(in: container).isEmpty)

        let pending = (task.subtasks ?? []).sorted { $0.order < $1.order }
        #expect(pending.map(\.title) == ["Draft the deck", "Rehearse"])
        #expect(pending.allSatisfy { $0.parentTask?.id == task.id })

        try modelContext.save()

        let sides = try storedSubtaskSides(in: container, taskID: task.id)
        #expect(sides.parentArray == ["Draft the deck", "Rehearse"])
        #expect(sides.backReferenced == ["Draft the deck", "Rehearse"])
    }

    /// The MCP path, which saves inside the call, so the store is the only place to look.
    ///
    /// T-387 called this the more dangerous of the two states — correct only because a save and a
    /// refetch happen before any reader does. Half of that is right: nothing pinned it. The other
    /// half is not, as the composer test above measured. What the ticket was actually pointing at
    /// survives the correction: this path had no assertion on the back-reference at all.
    @Test func theMCPCreatePathLandsBothSidesInTheStore() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let writeService = CadenceWriteService(context: modelContext, auditLogger: nil)

        let detail = try writeService.createTask(options: .init(
            title: "Wire the endpoint",
            subtaskTitles: ["  Schema  ", "", "Handler"]
        ))

        // This is the assertion the suite already had, and it is the one that could not tell the
        // difference: the returned detail is read back through the parent, which a one-sided write
        // satisfies once the save has back-populated it.
        #expect(detail.subtasks.map(\.title) == ["Schema", "Handler"])

        let storedTaskID = try #require(
            ModelContext(container)
                .fetch(FetchDescriptor<AppTask>())
                .first(where: { $0.title == "Wire the endpoint" })?
                .id
        )

        let sides = try storedSubtaskSides(in: container, taskID: storedTaskID)
        #expect(sides.parentArray == ["Schema", "Handler"])
        #expect(sides.backReferenced == ["Schema", "Handler"])
    }

    /// All five creation surfaces route through the one helper.
    ///
    /// Scanned because four of the five are unreachable from this target: three are `private func`s
    /// inside SwiftUI views and two of those live under `Cadence/iOS/`, which is not compiled into
    /// the macOS test bundle at all. The behavioural tests above cover the two that are callable.
    @Test func everySubtaskCreationCallSiteRoutesThroughTheSharedInsertHelper() throws {
        let callSites: [(path: String, call: String, anchor: String)] = [
            (
                "Cadence/macOS/Views/SchedulePanelComponents.swift",
                "CadenceTaskMutationSupport.insertSubtask(",
                "private func addSubtask() {"
            ),
            (
                "Cadence/iOS/iOSTaskDetailSheet.swift",
                "CadenceTaskMutationSupport.insertSubtask(",
                "private func addSubtask() {"
            ),
            (
                "Cadence/Services/TaskCreationService.swift",
                "CadenceTaskMutationSupport.insertSubtasks(",
                "func insertTask(from draft: TaskCreationDraft, into modelContext: ModelContext) -> AppTask? {"
            ),
            (
                "Cadence/iOS/iOSSampleDataSupport.swift",
                "CadenceTaskMutationSupport.insertSubtasks(",
                "private static func addSubtasks(_ titles: [String], to task: AppTask, modelContext: ModelContext) {"
            )
        ]

        for site in callSites {
            let raw = try subtaskSourceFile(site.path)
            let code = strippingSwiftComments(raw)

            // Non-vacuity: a missing or empty read, and a stripper that silently did nothing or
            // changed the file's length, all have to be red rather than quietly green.
            #expect(raw.count > 500, "\(site.path) read back as \(raw.count) characters")
            #expect(code != raw, "\(site.path) has no comments to strip; the stripper did nothing")
            #expect(code.count == raw.count, "\(site.path) changed length under the stripper")
            #expect(code.contains(site.anchor), "\(site.path) no longer contains \(site.anchor)")

            let routed = occurrences(of: site.call, in: code)
            #expect(routed == 1, "\(site.path) routes through \(site.call) \(routed) times, expected 1")

            // The two spellings a hand-rolled insert needs. Neither may survive anywhere in these
            // files: a second, open-coded path is exactly the divergence the helper removes.
            let constructed = occurrences(of: "Subtask(title:", in: code)
            #expect(constructed == 0, "\(site.path) still builds a Subtask directly \(constructed) times")

            let inverseWrites = occurrences(of: ".parentTask = ", in: code)
            #expect(inverseWrites == 0, "\(site.path) still writes the subtask inverse by hand \(inverseWrites) times")
        }
    }
}

// MARK: - Source access

private func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// `enumerator`-free sibling of the helper in `CadenceCancelledTaskReachabilityTests`: this file
/// sits directly under `CadenceTests/`, so the repository root is two levels up from `#filePath`.
private func subtaskRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func subtaskSourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: subtaskRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` line comments and `/* */` block comments with spaces of equal length, so the scanned
/// string is never shorter than the raw one and a length check is a real check.
private func strippingSwiftComments(_ source: String) -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            let width = result.distance(from: range.lowerBound, to: range.upperBound)
            result.replaceSubrange(range, with: String(repeating: " ", count: width))
        }
    }
    return result
}

/// Both sides of the subtask relationship as the **store** holds them, read back through a fresh
/// `ModelContext`: the parent's own array, and the rows that name the parent through `parentTask`.
///
/// The distinction is the whole point of T-387. A one-sided write makes these two disagree in the
/// window before a save; after a save they agree, which is why "assert both, after save and
/// refetch" is the assertion the old tests were missing rather than a stricter spelling of one
/// they had.
private func storedSubtaskSides(
    in container: ModelContainer,
    taskID: UUID
) throws -> (parentArray: [String], backReferenced: [String]) {
    let context = ModelContext(container)
    let storedTask = try context.fetch(FetchDescriptor<AppTask>()).first { $0.id == taskID }
    let parentArray = (storedTask?.subtasks ?? [])
        .sorted { $0.order < $1.order }
        .map(\.title)
    let backReferenced = try context.fetch(FetchDescriptor<Subtask>())
        .filter { $0.parentTask?.id == taskID }
        .sorted { $0.order < $1.order }
        .map(\.title)
    return (parentArray, backReferenced)
}
