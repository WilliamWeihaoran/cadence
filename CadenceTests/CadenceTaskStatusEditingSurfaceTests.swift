import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-343: six iOS surfaces changed a task's status and never reconciled OS notifications, so a
/// reminder could fire for work already done — until the next `scenePhase` checkpoint retired it.
///
/// `CadenceTaskStatusEditing` is the app-side wrapper the fix routes them through: shared mutation,
/// then reconcile, at one place — the same shape [[T-362]] gave the date/time half. This file pins
/// both halves, because either alone is worth little:
///
/// - **Behaviour.** Every entry point writes the status *and* reconciles, once, with the write
///   already visible to the reconciler. Injecting a recorder is the only way to see this: the live
///   reconcile bottoms out in `NotificationManager`, which early-returns in a test host, so a real
///   call and no call look identical from outside.
/// - **Shape.** A source scan that the seven status surfaces actually call the wrapper. All seven live
///   under `Cadence/iOS/`, which is behind `#if os(iOS)` while this target builds for macOS, so for
///   these files a scan is the only tool there is. It proves nobody re-typed a raw
///   `CadenceTaskMutationSupport.toggleCompletion`, not that the wrapper does anything.
@MainActor
struct CadenceTaskStatusEditingSurfaceTests {

    // MARK: - Fixtures

    /// Records one snapshot of the task per `run(in:)`, read out of the context the reconciler was
    /// handed. Snapshotting rather than counting pins the **ordering** too: a wrapper that
    /// reconciled before its mutation would record the old status and still call once.
    @MainActor
    private final class Recorder {
        struct Snapshot: Equatable {
            var status: TaskStatus
            var hasCompletedAt: Bool
            var actualMinutes: Int
        }

        var seen: [Snapshot] = []

        func reconciler() -> CadenceWindDownReconciler {
            CadenceWindDownReconciler { context in
                let tasks = (try? context.fetch(FetchDescriptor<AppTask>())) ?? []
                guard let task = tasks.first else { return }
                self.seen.append(
                    Snapshot(
                        status: task.status,
                        hasCompletedAt: task.completedAt != nil,
                        actualMinutes: task.actualMinutes
                    )
                )
            }
        }
    }

    private func statusContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func seededOpenTask(in context: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Finish me")
        task.scheduledDate = "2026-03-01"
        task.scheduledStartMin = 9 * 60
        context.insert(task)
        try context.save()
        return task
    }

    // MARK: - Behaviour: the wrapper reconciles, after the write

    /// The whole vocabulary, one case each. Every entry point must reconcile **exactly once**, and
    /// the snapshot the reconciler took must already carry the transition — that is the difference
    /// between this fix and the bug, which reconciled at some unrelated later moment or not at all.
    @Test func everyStatusEditingEntryPointReconcilesOnceAfterItsWriteLands() throws {
        let cases: [(name: String, edit: (AppTask, ModelContext, CadenceWindDownReconciler) -> Void, check: (Recorder.Snapshot) -> Bool)] = [
            ("toggleCompletion", { CadenceTaskStatusEditing.toggleCompletion($0, in: $1, reconciler: $2) },
             { $0.status == .done && $0.hasCompletedAt }),
            ("setStatus(.cancelled)", { CadenceTaskStatusEditing.setStatus(.cancelled, for: $0, in: $1, reconciler: $2) },
             { $0.status == .cancelled }),
            ("setStatus(.inProgress)", { CadenceTaskStatusEditing.setStatus(.inProgress, for: $0, in: $1, reconciler: $2) },
             { $0.status == .inProgress && !$0.hasCompletedAt }),
            ("completeFocusSession", { CadenceTaskStatusEditing.completeFocusSession($0, elapsedSeconds: 25 * 60, in: $1, reconciler: $2) },
             { $0.status == .done && $0.hasCompletedAt && $0.actualMinutes == 25 })
        ]

        // Non-vacuity: the table is the wrapper's whole surface, so an entry point deleted from it
        // cannot quietly stop being covered.
        #expect(cases.count == 3 + 1, "the entry-point table has \(cases.count) cases")

        for testCase in cases {
            let modelContext = try statusContext()
            let task = try seededOpenTask(in: modelContext)
            let recorder = Recorder()

            testCase.edit(task, modelContext, recorder.reconciler())

            #expect(recorder.seen.count == 1, "\(testCase.name) reconciled \(recorder.seen.count) times")
            guard let snapshot = recorder.seen.first else { continue }
            #expect(
                testCase.check(snapshot),
                "\(testCase.name) reconciled against \(snapshot) — the transition was not visible yet"
            )
        }
    }

    /// Reopening reconciles too, and that direction is the one a "reconcile only when it is
    /// finished" shortcut would silently drop: a task pulled back to todo needs its reminder
    /// **re**scheduled, not retired.
    @Test func reopeningADoneTaskThroughTheWrapperAlsoReconciles() throws {
        let modelContext = try statusContext()
        let task = try seededOpenTask(in: modelContext)
        CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext, reconciler: .inert)
        #expect(task.isDone)

        let recorder = Recorder()
        CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext, reconciler: recorder.reconciler())

        #expect(recorder.seen.count == 1)
        #expect(recorder.seen.first?.status == .todo)
        #expect(recorder.seen.first?.hasCompletedAt == false)
    }

    /// The transition is committed, not left pending — the reconcile fetches, and a fetch that has
    /// to see uncommitted state is a different contract from the one the app relies on.
    @Test func aRoutedStatusEditIsCommittedBeforeTheReconcileReadsTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = try seededOpenTask(in: modelContext)

        CadenceTaskStatusEditing.setStatus(.cancelled, for: task, in: modelContext, reconciler: .inert)

        #expect(!modelContext.hasChanges, "the status edit was left pending in the context")
        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).first?.status == .cancelled)
    }

    // MARK: - Shape: the surfaces route through it

    /// Every routed status surface. All seven are iOS, which is why this is a scan.
    ///
    /// `iOSTaskDetailSheet.swift` joined the list with **T-407**. It was the residue T-343 recorded
    /// rather than fixed — the file was owned by another change in flight — and it is the one
    /// surface whose status changes belong to a sheet's lifecycle rather than to a row action,
    /// which is why neither wrapper reached it. Its `normalizeCompletionState` is deliberately
    /// *not* routed and deliberately not matched by `unwrappedStatusMutation`; see
    /// `IOSTaskDetailSheetResidueTests` for why routing it would reconcile on every appearance.
    private static let routedStatusSurfaces = [
        "Cadence/iOS/iOSTaskRowActionViews.swift",
        "Cadence/iOS/iOSTaskViews.swift",
        "Cadence/iOS/iOSBoardCards.swift",
        "Cadence/iOS/iOSMarkdownEditingSurface.swift",
        "Cadence/iOS/iOSCalendarBundleDetailSheet.swift",
        "Cadence/iOS/iOSFocusView.swift",
        "Cadence/iOS/iOSTaskDetailSheet.swift"
    ]

    /// The pure mutation layer's status entry points, called directly. Correct for a service or an
    /// out-of-process writer; wrong for a user surface, because it saves and stops.
    ///
    /// `deleteFailureNotice`, `setPriority`, `moveToContainer` and the rest of that enum are not in
    /// here — the rule is about status, and a needle that matched the whole enum would fail on
    /// files that legitimately use it.
    private static let unwrappedStatusMutation =
        #"CadenceTaskMutationSupport\.(?:toggleCompletion|setStatus|applyStatusCompletion)\b"#

    /// The focus timer's completion, called directly. It logs the elapsed minutes *and* marks the
    /// task done in one save, so it is a status transition wearing a different name.
    private static let unwrappedFocusCompletion = #"CadenceFocusSupport\.complete\("#

    /// A raw assignment to `task.status`. `[^=]` keeps `if task.status == .inProgress` out of it.
    private static let rawStatusWrite = #"\btask\.status\s*=[^=]"#

    @Test func theSevenStatusSurfacesRouteEveryTransitionThroughTheSharedWrapper() throws {
        var filesRead = 0

        for path in Self.routedStatusSurfaces {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(path): the stripper changed the length")

            // Positive first: the file names the wrapper. This doubles as the non-vacuity check —
            // an empty or wrong file cannot satisfy it.
            #expect(
                stripped.contains("CadenceTaskStatusEditing."),
                "\(path) no longer routes any status change through CadenceTaskStatusEditing"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: stripped) == 0,
                "\(path) calls the pure status mutation layer directly, so its change never reconciles (T-343)"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.unwrappedFocusCompletion, in: stripped) == 0,
                "\(path) completes a focus session without reconciling (T-343)"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.rawStatusWrite, in: stripped) == 0,
                "\(path) writes task.status directly instead of through the wrapper (T-343)"
            )

            filesRead += 1
        }

        #expect(filesRead == 7, "the scan read \(filesRead) of 7 routed status surfaces")
    }

    /// Every entry point on the wrapper ends in the one private reconcile. Stated as a relation
    /// rather than two magic numbers, so adding a fourth transition is only green if it reconciles.
    @Test func everyStatusWrapperEntryPointEndsInTheOneReconcile() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskStatusEditing.swift")
        #expect(raw.count > 400, "CadenceTaskStatusEditing.swift read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let entryPoints = CadenceSourceScan.matchCount(#"static func "#, in: stripped)
        let reconciles = CadenceSourceScan.matchCount(#"reconcile\(context, reconciler\)"#, in: stripped)
        #expect(entryPoints >= 4, "the wrapper declares only \(entryPoints) functions")
        #expect(
            reconciles == entryPoints - 1,
            "\(entryPoints) functions but \(reconciles) reconcile calls — an entry point skips it"
        )

        // The fallback has to be `.default`, which is inert in a test host. `.live` here would put
        // a store-wide fetch into NotificationManager behind every status unit test.
        #expect(stripped.contains("(reconciler ?? .default).run(in: context)"))
        #expect(CadenceSourceScan.matchCount(#"\?\?\s*\.live"#, in: stripped) == 0)
    }

    /// T-343's own constraint, and the reason the wrapper exists at all: the reconcile must **not**
    /// move into the shared status helpers, which widgets and MCP also drive.
    /// `HabitNotificationReconcileSupport` fans out to `NotificationManager`, which reads the app's
    /// `UserDefaults` suite and `UNUserNotificationCenter` — an extension sees neither.
    ///
    /// Scoped to the two status function bodies rather than the whole file on purpose:
    /// `deleteTasks` in the same enum legitimately calls `NotificationManager.shared.cancel(taskIDs:)`
    /// — a cancel by id, which needs no store read and no desired-set computation — so a file-wide
    /// ban would be a rule this repository does not actually hold.
    @Test func theSharedStatusHelpersStillReconcileNothing() throws {
        // This used to strip `= { try $0.save() }` out of the text first, because
        // `functionBody(named:)` stopped at the first `{` after the name — which for a declaration
        // carrying that default is the closure and not the body, so the scan read a one-expression
        // closure and found no `HabitNotificationReconcileSupport` in it. **T-644 fixed the reader**
        // (it balances the parameter list now), so the workaround is gone and the raw text is
        // scanned. `CadenceSourceScanReaderTests.theFunctionBodyReaderSkipsADefaultedClosureInTheParameterList`
        // pins the reader; the assertion below pins that this file still has the shape it must skip.
        let mutationLayer = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        )
        #expect(mutationLayer.count > 400)
        #expect(
            mutationLayer.contains("commit: (ModelContext) throws -> Void = { try $0.save() }"),
            "the commit default this scan reads past is gone; re-derive what the body reader must skip"
        )

        for name in ["toggleCompletion", "setStatus", "applyStatusCompletion"] {
            let body = CadenceSourceScan.functionBody(named: name, in: mutationLayer)
            #expect(body != nil, "could not read \(name)'s body, so this test proves nothing")
            guard let body else { continue }
            // Non-vacuity: the body really is the status helper's.
            #expect(
                body.contains("CadenceTaskRecurrenceWorkflowSupport") || body.contains("applyStatusCompletion"),
                "\(name)'s body does not look like the status helper: \(body)"
            )
            #expect(
                !body.contains("HabitNotificationReconcileSupport"),
                "\(name) reconciles inside the shared layer, which widgets and MCP must not do (T-343)"
            )
            #expect(!body.contains("NotificationManager"), "\(name) reaches NotificationManager (T-343)")
        }
    }

    /// The needles match what they hunt and miss what they must not, and the reader reaches real
    /// files — without this, the `== 0` assertions above are true of any text at all.
    @Test func theStatusEditingScanNeedlesAndReaderAreNotVacuous() throws {
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: "CadenceTaskMutationSupport.toggleCompletion(t, modelContext: c)") == 1
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: "CadenceTaskMutationSupport.setStatus(s, for: t, modelContext: c)") == 1
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: "CadenceTaskStatusEditing.toggleCompletion(t, in: c)") == 0
        )
        // The parts of that enum a status rule has no business banning.
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: "CadenceTaskMutationSupport.setPriority(p, for: t, modelContext: c)") == 0
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: "Text(CadenceTaskMutationSupport.deleteFailureNotice)") == 0
        )
        #expect(CadenceSourceScan.matchCount(Self.unwrappedFocusCompletion, in: "CadenceFocusSupport.complete(t, elapsedSeconds: s, modelContext: c)") == 1)
        #expect(CadenceSourceScan.matchCount(Self.unwrappedFocusCompletion, in: "CadenceFocusSupport.completedCount(x)") == 0)
        #expect(CadenceSourceScan.matchCount(Self.rawStatusWrite, in: "task.status = .todo\n") == 1)
        #expect(CadenceSourceScan.matchCount(Self.rawStatusWrite, in: "if task.status == .inProgress {") == 0)

        // The reader really does return the repository's own text, and the positive control is the
        // wrapper: it is the one file that is *supposed* to call the pure status layer, so the
        // needle must fire there and nowhere among the six routed surfaces.
        //
        // Not `CadenceTaskMutationSupport.swift`, which is the intuitive choice and the wrong one:
        // the enum calls its own helpers **unqualified** (`applyStatusCompletion(status, …)`), so a
        // needle anchored on the `CadenceTaskMutationSupport.` prefix reads zero there. That read as
        // "the file was not loaded" when it actually meant "the prefix is never written inside the
        // type that declares it".
        let wrapper = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskStatusEditing.swift")
        )
        #expect(wrapper.contains("enum CadenceTaskStatusEditing"), "the scan read the wrong file")
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedStatusMutation, in: wrapper) >= 2,
            "the scan read no status mutation calls in the wrapper, so it read the wrong file"
        )
    }
}
