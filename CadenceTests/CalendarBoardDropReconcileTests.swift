#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-1478]] (parity finding PA-14): a TAKEN Mac Calendar Board date drop reconciles
/// notifications immediately, exactly once, after its commit.**
///
/// The owner chose immediate over the scene-phase checkpoint. Before this, both board drops in
/// `CalendarPageBoardDropSupport` answered `landed ? .applied : .refused` and reconciled only on a
/// refusal (inside `CadenceTaskFieldEditCommit`'s undo), so a reminder kept describing the
/// previous schedule for as long as the window stayed frontmost. iOS's board already reconciles on
/// the spot through `CadenceTaskDateEditing`.
///
/// **Why a counting recorder and never a real reminder.** The reconciler is injected; the recorder
/// is `isLive: false` and only counts, so no user notification is ever scheduled. The recorder
/// also reads the store through a SECOND context at the moment it runs, which is what proves the
/// reconcile came after the commit rather than inside the write — a reconcile fetches, and it must
/// read the arrangement the store took.
///
/// Every case is non-parameterised on purpose: `scripts/mutate.sh` cannot baseline a parameterised
/// test ([[T-3212]]).
///
/// Beside `CalendarBoardDayDropCommitTests` rather than inside it: that suite is Codex-leased and
/// holds PA-13's refusal coverage; this one is only about the reconcile count.
@MainActor
struct CalendarBoardDropReconcileTests {

    private struct Refused: Error {}

    /// Counts runs and records what a fresh context reads for the task's do date at each run.
    @MainActor
    private final class Recorder {
        private(set) var storedDatesAtRun: [String] = []
        let modelContainer: ModelContainer
        let taskID: UUID

        init(modelContainer: ModelContainer, taskID: UUID) {
            self.modelContainer = modelContainer
            self.taskID = taskID
        }

        var reconciler: CadenceWindDownReconciler {
            CadenceWindDownReconciler(isLive: false) { [self] _ in
                let fresh = ModelContext(modelContainer)
                let stored = (try? fresh.fetch(FetchDescriptor<AppTask>()))?.first { $0.id == taskID }
                storedDatesAtRun.append(stored?.scheduledDate ?? "<missing>")
            }
        }
    }

    private struct Fixture {
        let modelContainer: ModelContainer
        let modelContext: ModelContext
        let task: AppTask
        let recorder: Recorder
    }

    private func fixture() throws -> Fixture {
        let modelContainer = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        let task = AppTask(title: "Dragged on the board")
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = 600
        modelContext.insert(task)
        try modelContext.save()
        return Fixture(
            modelContainer: modelContainer,
            modelContext: modelContext,
            task: task,
            recorder: Recorder(modelContainer: modelContainer, taskID: task.id)
        )
    }

    // MARK: - Day column (schedule)

    @Test func aTakenDayColumnDropReconcilesOnceAfterItsCommit() throws {
        let board = try fixture()
        let outcome = CalendarPageBoardDropSupport.schedule(
            board.task,
            on: "2026-07-04",
            modelContext: board.modelContext,
            reconciler: board.recorder.reconciler
        )
        #expect(outcome == .applied)
        #expect(board.recorder.storedDatesAtRun == ["2026-07-04"], "once, and reading the committed date")
    }

    @Test func aRefusedDayColumnDropReconcilesOnceOverTheRestoredDate() throws {
        let board = try fixture()
        let outcome = CalendarPageBoardDropSupport.schedule(
            board.task,
            on: "2026-07-04",
            modelContext: board.modelContext,
            reconciler: board.recorder.reconciler,
            commit: { _ in throw Refused() }
        )
        #expect(outcome == .refused)
        #expect(board.task.scheduledDate == "2026-06-01")
        #expect(board.recorder.storedDatesAtRun == ["2026-06-01"], "the undo's one reconcile, and no second")
    }

    @Test func aDayColumnDropWithNoDayNeverReconciles() throws {
        let board = try fixture()
        let outcome = CalendarPageBoardDropSupport.schedule(
            board.task,
            on: "",
            modelContext: board.modelContext,
            reconciler: board.recorder.reconciler
        )
        #expect(outcome == .resolvedNothing)
        #expect(board.recorder.storedDatesAtRun.isEmpty)
    }

    // MARK: - Unscheduled rail (unschedule)

    @Test func aTakenUnscheduleDropReconcilesOnceAfterItsCommit() throws {
        let board = try fixture()
        let outcome = CalendarPageBoardDropSupport.unschedule(
            [TaskDragPayload.string(for: board.task.id)],
            in: [board.task],
            modelContext: board.modelContext,
            reconciler: board.recorder.reconciler
        )
        #expect(outcome == .applied)
        #expect(board.recorder.storedDatesAtRun == [""], "once, and reading the cleared date")
    }

    @Test func aRefusedUnscheduleDropReconcilesOnceOverTheRestoredDate() throws {
        let board = try fixture()
        let outcome = CalendarPageBoardDropSupport.unschedule(
            [TaskDragPayload.string(for: board.task.id)],
            in: [board.task],
            modelContext: board.modelContext,
            reconciler: board.recorder.reconciler,
            commit: { _ in throw Refused() }
        )
        #expect(outcome == .refused)
        #expect(board.task.scheduledDate == "2026-06-01")
        #expect(board.recorder.storedDatesAtRun == ["2026-06-01"], "the undo's one reconcile, and no second")
    }

    @Test func anUnscheduleDropOfAnUnknownCardNeverReconciles() throws {
        let board = try fixture()
        let outcome = CalendarPageBoardDropSupport.unschedule(
            [TaskDragPayload.string(for: UUID())],
            in: [board.task],
            modelContext: board.modelContext,
            reconciler: board.recorder.reconciler
        )
        #expect(outcome == .resolvedNothing)
        #expect(board.recorder.storedDatesAtRun.isEmpty)
    }

    // MARK: - The product callers take the live default

    /// The view's two handlers must not pass `.inert` (or any reconciler): `nil` falls to
    /// `CadenceWindDownReconciler.default`, which is `.live` outside the test host. A handler
    /// that passed `.inert` would keep every count above green while the app never reconciled.
    @Test func theBoardHandlersLeaveTheReconcilerToTheLiveDefault() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"
        )
        for handler in ["handleDayColumnDrop", "handleUnscheduleDrop"] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: handler, in: source)
            #expect(body.contains("CalendarPageBoardDropSupport."), "\(handler) still routes through the unit")
            #expect(!body.contains("reconciler:"), "\(handler) must leave the reconciler to the default")
        }
    }
}
#endif
