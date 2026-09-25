#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-1351: macOS's delete wrapper tore down hover, the completion animation, the subtask-entry
/// field **and the user's running focus session** from `willDelete`, which the shared core calls
/// before the rows are marked and therefore before any commit — its own on an ordinary delete, the
/// surface's on a list cascade. A refused delete put every row back under "Nothing was removed."
/// with the focus session already ended.
///
/// The two halves are separated rather than both moved, which is the whole of the ticket: hover,
/// the animation and the subtask field are transient and `willDelete` is placed early on purpose —
/// it exists to stop an animation aimed at a row that is about to go — while ending a session the
/// user started, and dropping a bundle selection they built by hand, is destructive and waits for
/// the commit through `CadenceDeferredDeleteEffects`.
///
/// Nothing here depends on a SwiftData timing: the assertions are about in-memory singleton state
/// and about which side of a commit a callback runs on.
@MainActor
struct CadenceFocusTeardownDeferralTests {

    private struct CommitRefused: Error {}
    private let refuseTheCommit: (ModelContext) throws -> Void = { _ in throw CommitRefused() }

    private func resetSharedManagers() {
        FocusManager.shared.activeSession = nil
        FocusManager.shared.selectedBundleTaskIDs = []
        FocusManager.shared.reset()
        HoveredTaskManager.shared.clear()
        TaskSubtaskEntryManager.shared.requestedTaskID = nil
    }

    // MARK: - The ordinary delete

    /// The headline: the session the user is running survives a delete the store refused.
    @Test func arefusedTaskDeleteLeavesTheFocusSessionRunning() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Deep work")
        modelContext.insert(task)
        try modelContext.save()

        try FocusManager.shared.startFocus(task: task, in: modelContext)
        #expect(FocusManager.shared.activeTask?.id == task.id)

        #expect(
            modelContext.deleteTask(task, commit: refuseTheCommit) == false,
            "a delete whose commit was refused reported success"
        )

        #expect(
            FocusManager.shared.activeTask?.id == task.id,
            "a refused delete ended the focus session of a task that is still in the store"
        )
        #expect(FocusManager.shared.activeSession != nil)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Deep work"])
    }

    /// Its other half, and not an oversight: the cheap state still goes above the commit, because
    /// `willDelete` exists to stop an animation aimed at a row that is about to disappear and the
    /// user re-acquires hover by moving the mouse.
    @Test func arefusedTaskDeleteStillClearsTheHoverAndSubtaskEntryItWasAskedTo() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Deep work")
        modelContext.insert(task)
        try modelContext.save()

        HoveredTaskManager.shared.beginHovering(task, source: .list)
        TaskSubtaskEntryManager.shared.requestedTaskID = task.id

        #expect(modelContext.deleteTask(task, commit: refuseTheCommit) == false)

        #expect(HoveredTaskManager.shared.hoveredTask == nil)
        #expect(TaskSubtaskEntryManager.shared.requestedTaskID == nil)
    }

    /// The selection a user assembled by hand is on the deferred side with the session.
    @Test func arefusedDeleteOfASelectedBundleMemberKeepsItSelected() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let bundle = TaskBundle(title: "Morning admin", dateKey: "2026-09-24", startMin: 540, durationMinutes: 30)
        let first = AppTask(title: "Reply to emails")
        first.bundle = bundle
        let second = AppTask(title: "Clear inbox")
        second.bundle = bundle
        bundle.tasks = [first, second]
        for model in [bundle, first, second] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        try FocusManager.shared.startFocus(bundle: bundle, in: modelContext)
        FocusManager.shared.selectedBundleTaskIDs = [first.id, second.id]

        #expect(modelContext.deleteTask(first, commit: refuseTheCommit) == false)

        #expect(
            FocusManager.shared.selectedBundleTaskIDs.contains(first.id),
            "a refused delete dropped a row the user had selected inside the running block"
        )
        #expect(FocusManager.shared.activeBundle?.id == bundle.id)
    }

    /// The success path, unchanged: a delete that lands still ends the session and drops the row.
    @Test func acommittedTaskDeleteStillEndsTheFocusSessionItInvalidates() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Deep work")
        modelContext.insert(task)
        try modelContext.save()

        try FocusManager.shared.startFocus(task: task, in: modelContext)
        #expect(modelContext.deleteTask(task))

        #expect(FocusManager.shared.activeSession == nil)
        #expect(FocusManager.shared.activeTask == nil)
        #expect(FocusManager.shared.isRunning == false)
    }

    // MARK: - The list cascade

    /// The deferred half, which is where the ticket was filed from: the cascade makes no commit of
    /// its own, so the teardown has to wait for `commitCascade`'s.
    @Test func arefusedListCascadeLeavesTheFocusSessionRunning() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()

        try FocusManager.shared.startFocus(task: task, in: modelContext)
        #expect(FocusManager.shared.activeTask?.id == task.id)

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: modelContext,
                commit: refuseTheCommit,
                cascade: { modelContext.deleteArea(area) }
            )
        }

        #expect(
            FocusManager.shared.activeTask?.id == task.id,
            "a refused list delete ended the focus session of a task the alert says was not removed"
        )
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Renew the domain"])
        #expect(try modelContext.fetch(FetchDescriptor<Area>()).map(\.name) == ["Operations"])
    }

    /// And the cascade's success path still ends it, so the deferral is a deferral rather than a
    /// removal.
    @Test func acommittedListCascadeEndsTheFocusSessionItInvalidates() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Operations")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()

        try FocusManager.shared.startFocus(task: task, in: modelContext)

        try CadencePendingChangePersistence.commitCascade(in: modelContext) {
            modelContext.deleteArea(area)
        }

        #expect(FocusManager.shared.activeSession == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    // MARK: - The source rule

    /// Which teardown is on which side of the commit, pinned in source.
    ///
    /// `willDelete` runs above the commit by construction, so a focus teardown written back into
    /// `cancelTransientTaskState` would be the T-1351 regression exactly — and the behavioural
    /// assertions above would catch it. What they cannot catch is the other direction: a deferral
    /// released unconditionally rather than on `deleted`, which is only reachable through a store
    /// that refuses a save.
    @Test func theMacOSDeleteWrapperReleasesItsTeardownOnlyOnASuccessfulDelete() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Services/TaskDeleteHelpers.swift")
        #expect(raw.count > 400, "the wrapper read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")

        let body = try #require(CadenceSourceScan.functionBody(named: "deleteTasks", in: stripped))
        #expect(
            body.contains("if deleted {\n            ownEffects?.release()"),
            "the wrapper releases its deferred teardown without checking that the delete landed (T-1351)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"FocusManager\.shared\.activeSession = nil"#, in: body) == 0,
            "the focus session is ended from the delete wrapper's own body again, above the commit (T-1351)"
        )

        let transient = try #require(
            CadenceSourceScan.functionBody(named: "cancelTransientTaskState", in: stripped)
        )
        #expect(
            CadenceSourceScan.matchCount(#"FocusManager\."#, in: transient) == 0,
            "focus teardown moved back into the callback that runs above the commit (T-1351)"
        )
        #expect(
            transient.contains("HoveredTaskManager.shared.clear()"),
            "the transient half stopped clearing hover, which willDelete is placed early to do"
        )
    }
}
#endif
