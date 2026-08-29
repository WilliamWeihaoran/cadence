import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-362: eleven macOS/iOS surfaces changed a task's date or time and never reconciled OS
/// notifications, so a task moved from 9am to 3pm kept its 9am reminder pending until the next
/// `scenePhase` checkpoint — and the reminder fired at the old time.
///
/// `CadenceTaskDateEditing` is the app-side wrapper the fix routes them through: shared mutation,
/// then reconcile, at one place. This file pins both halves, because either alone is worth little:
///
/// - **Behaviour.** Every entry point in the wrapper writes the field *and* reconciles, once, with
///   the write already visible to the reconciler. Injecting a recorder is the only way to see this
///   — the live reconcile bottoms out in `NotificationManager`, which early-returns in a test host,
///   so a real call and no call look identical from outside.
/// - **Shape.** A source scan that the date/time surfaces actually call the wrapper. `Cadence/iOS/`
///   is behind `#if os(iOS)` and this target builds for macOS, so for half the routed files a scan
///   is the only tool there is. It is deliberately the weaker half: it proves nobody re-typed a raw
///   `task.dueDate = …`, not that the wrapper does anything.
///
/// Sibling ticket [[T-343]] (iOS *status* mutations) is still open at the time of writing; nothing
/// here touches the status paths.
@MainActor
struct CadenceTaskDateEditingSurfaceTests {

    // MARK: - Fixtures

    /// Records one snapshot of the task per `run(in:)`, read out of the context the reconciler was
    /// handed. Snapshotting rather than counting pins the **ordering** too: a wrapper that
    /// reconciled before its mutation would record the old date and still call once.
    @MainActor
    private final class Recorder {
        struct Snapshot: Equatable {
            var scheduledDate: String
            var dueDate: String
            var scheduledStartMin: Int
        }

        var seen: [Snapshot] = []

        func reconciler() -> CadenceWindDownReconciler {
            CadenceWindDownReconciler { context in
                let tasks = (try? context.fetch(FetchDescriptor<AppTask>())) ?? []
                guard let task = tasks.first else { return }
                self.seen.append(
                    Snapshot(
                        scheduledDate: task.scheduledDate,
                        dueDate: task.dueDate,
                        scheduledStartMin: task.scheduledStartMin
                    )
                )
            }
        }
    }

    private func seededTask(in context: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Move me")
        task.scheduledDate = "2026-03-01"
        task.dueDate = "2026-03-02"
        task.scheduledStartMin = 9 * 60
        context.insert(task)
        try context.save()
        return task
    }

    private func context() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: - Behaviour: the wrapper reconciles, after the write

    /// The whole vocabulary, one case each. Every entry point must reconcile **exactly once**, and
    /// the snapshot the reconciler took must already carry the edit — that is the difference
    /// between this fix and the bug, which reconciled at some unrelated later moment or not at all.
    @Test func everyDateEditingEntryPointReconcilesOnceAfterItsWriteLands() throws {
        // `check` is the field the edit is expected to have changed, read from the recorded
        // snapshot rather than from the live task, so a reconcile that ran too early is red.
        let cases: [(name: String, edit: (AppTask, ModelContext, CadenceWindDownReconciler) -> Void, check: (Recorder.Snapshot) -> Bool)] = [
            ("setScheduledDate", { CadenceTaskDateEditing.setScheduledDate("2026-04-04", for: $0, in: $1, reconciler: $2) },
             { $0.scheduledDate == "2026-04-04" }),
            ("scheduleToday", { CadenceTaskDateEditing.scheduleToday($0, in: $1, reconciler: $2) },
             { $0.scheduledDate == DateFormatters.todayKey() }),
            ("scheduleTomorrow", { CadenceTaskDateEditing.scheduleTomorrow($0, in: $1, reconciler: $2) },
             { $0.scheduledDate != "2026-03-01" && !$0.scheduledDate.isEmpty }),
            ("scheduleNextWeek", { CadenceTaskDateEditing.scheduleNextWeek($0, in: $1, reconciler: $2) },
             { $0.scheduledDate != "2026-03-01" && !$0.scheduledDate.isEmpty }),
            ("clearScheduledDate", { CadenceTaskDateEditing.clearScheduledDate($0, in: $1, reconciler: $2) },
             { $0.scheduledDate.isEmpty && $0.scheduledStartMin == -1 }),
            ("moveTaskToDate", { CadenceTaskDateEditing.moveTaskToDate($0, dateKey: "2026-05-05", in: $1, reconciler: $2) },
             { $0.scheduledDate == "2026-05-05" }),
            ("setScheduledTime", { CadenceTaskDateEditing.setScheduledTime(15 * 60, for: $0, in: $1, reconciler: $2) },
             { $0.scheduledStartMin == 15 * 60 }),
            ("clearScheduledTime", { CadenceTaskDateEditing.clearScheduledTime($0, in: $1, reconciler: $2) },
             { $0.scheduledStartMin == -1 }),
            ("setScheduledSlot", { CadenceTaskDateEditing.setScheduledSlot(dateKey: "2026-06-06", startMin: 13 * 60, for: $0, in: $1, reconciler: $2) },
             { $0.scheduledDate == "2026-06-06" && $0.scheduledStartMin == 13 * 60 }),
            ("setDueDate", { CadenceTaskDateEditing.setDueDate("2026-07-07", for: $0, in: $1, reconciler: $2) },
             { $0.dueDate == "2026-07-07" }),
            ("dueToday", { CadenceTaskDateEditing.dueToday($0, in: $1, reconciler: $2) },
             { $0.dueDate == DateFormatters.todayKey() }),
            ("dueTomorrow", { CadenceTaskDateEditing.dueTomorrow($0, in: $1, reconciler: $2) },
             { $0.dueDate != "2026-03-02" && !$0.dueDate.isEmpty }),
            ("dueNextWeek", { CadenceTaskDateEditing.dueNextWeek($0, in: $1, reconciler: $2) },
             { $0.dueDate != "2026-03-02" && !$0.dueDate.isEmpty }),
            ("clearDueDate", { CadenceTaskDateEditing.clearDueDate($0, in: $1, reconciler: $2) },
             { $0.dueDate.isEmpty }),
            ("setPlanningDates", { CadenceTaskDateEditing.setPlanningDates(scheduledDate: "2026-08-08", dueDate: "2026-08-09", for: $0, in: $1, reconciler: $2) },
             { $0.scheduledDate == "2026-08-08" && $0.dueDate == "2026-08-09" })
        ]

        // Non-vacuity: the table is the wrapper's whole surface, so an entry point deleted from it
        // cannot quietly stop being covered.
        #expect(cases.count == 15, "the entry-point table has \(cases.count) cases")

        for testCase in cases {
            let modelContext = try context()
            let task = try seededTask(in: modelContext)
            let recorder = Recorder()

            testCase.edit(task, modelContext, recorder.reconciler())

            #expect(recorder.seen.count == 1, "\(testCase.name) reconciled \(recorder.seen.count) times")
            guard let snapshot = recorder.seen.first else { continue }
            #expect(
                testCase.check(snapshot),
                "\(testCase.name) reconciled against \(snapshot) — the edit was not visible yet"
            )
        }
    }

    /// The edit is committed, not left pending — the reconcile fetches, and a fetch that has to
    /// see uncommitted state is a different contract from the one the app relies on.
    @Test func aRoutedDateEditIsCommittedBeforeTheReconcileReadsTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = try seededTask(in: modelContext)

        CadenceTaskDateEditing.setDueDate("2026-09-09", for: task, in: modelContext, reconciler: .inert)

        #expect(!modelContext.hasChanges, "the date edit was left pending in the context")
        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).first?.dueDate == "2026-09-09")
    }

    /// Clearing a do date drops the timeline slot with it. Two of the routed pickers used to write
    /// `task.scheduledDate = ""` alone and strand a `scheduledStartMin` on no day; routing them
    /// through the wrapper adopts `clearScheduledDate`'s existing contract.
    @Test func clearingADoDateThroughTheWrapperAlsoDropsTheTimelineSlot() throws {
        let modelContext = try context()
        let task = try seededTask(in: modelContext)

        CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext, reconciler: .inert)

        #expect(task.scheduledDate.isEmpty)
        #expect(task.scheduledStartMin == -1)
    }

    // MARK: - Shape: the surfaces route through it

    /// Every routed date/time surface, with what it must no longer contain.
    private static let routedSurfaces = [
        "Cadence/macOS/Views/TasksPanelComponents.swift",
        "Cadence/macOS/Views/KanbanCardView.swift",
        "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift",
        "Cadence/macOS/Services/HoveredTaskDatePickerManager.swift",
        "Cadence/macOS/Views/macOSRootCommandActionSupport.swift",
        "Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift",
        "Cadence/macOS/Views/TaskInspectorContentSupportViews.swift",
        "Cadence/macOS/Views/TasksPanelSupport.swift",
        "Cadence/iOS/iOSTaskRowActionViews.swift",
        "Cadence/iOS/iOSTodaySchedulePanel.swift",
        "Cadence/iOS/iOSTaskDetailSheet.swift",
        "Cadence/iOS/iOSCalendarBoardView.swift"
    ]

    /// A raw write to one of the three date/time fields. `[^=]` at the end is what keeps
    /// `task.dueDate == todayKey` — a comparison the keyboard toggle still makes — out of it.
    private static let rawDateWrite = #"\.(?:scheduledDate|dueDate|scheduledStartMin)\s*=[^=]"#

    /// The pure mutation layer, called directly. Correct for a service; wrong for a user surface,
    /// because it saves and stops.
    private static let unwrappedMutation =
        #"CadenceTaskMutationSupport\.(?:setScheduledDate|setDueDate|setScheduledTime|clearScheduledDate|clearScheduledTime|clearDueDate|scheduleToday|scheduleTomorrow|scheduleNextWeek|dueToday|dueTomorrow|dueNextWeek|moveTaskToDate|setPlanningDates)\b"#

    @Test func theDateAndTimeSurfacesRouteEveryEditThroughTheSharedWrapper() throws {
        var filesRead = 0

        for path in Self.routedSurfaces {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(path): the stripper changed the length")

            // Positive first: the file names the wrapper. This doubles as the non-vacuity check —
            // an empty or wrong file cannot satisfy it.
            #expect(
                stripped.contains("CadenceTaskDateEditing."),
                "\(path) no longer routes any date edit through CadenceTaskDateEditing"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.rawDateWrite, in: stripped) == 0,
                "\(path) writes a task date/time field directly instead of through the wrapper (T-362)"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.unwrappedMutation, in: stripped) == 0,
                "\(path) calls the pure mutation layer directly, so its edit never reconciles (T-362)"
            )

            filesRead += 1
        }

        #expect(filesRead == 12, "the scan read \(filesRead) of 12 routed surfaces")
    }

    /// Every entry point on the wrapper ends in the one private reconcile. Stated as a relation
    /// rather than two magic numbers, so adding a sixteenth edit is only green if it reconciles.
    @Test func everyWrapperEntryPointEndsInTheOneReconcile() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskDateEditing.swift")
        #expect(raw.count > 400, "CadenceTaskDateEditing.swift read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let entryPoints = CadenceSourceScan.matchCount(#"static func "#, in: stripped)
        let reconciles = CadenceSourceScan.matchCount(#"reconcile\(context, reconciler\)"#, in: stripped)
        #expect(entryPoints >= 16, "the wrapper declares only \(entryPoints) functions")
        #expect(
            reconciles == entryPoints - 1,
            "\(entryPoints) functions but \(reconciles) reconcile calls — an entry point skips it"
        )

        // The fallback has to be `.default`, which is inert in a test host. `.live` here would put
        // a store-wide fetch into NotificationManager behind every scheduling unit test.
        #expect(stripped.contains("(reconciler ?? .default).run(in: context)"))
        #expect(CadenceSourceScan.matchCount(#"\?\?\s*\.live"#, in: stripped) == 0)
    }

    /// The needles match what they hunt and miss what they must not, and the reader reaches real
    /// files — without this, the three `== 0` assertions above are true of any text at all,
    /// including the empty string a mistyped path would never produce but a silent `try?` would.
    @Test func theDateEditingScanNeedlesAndReaderAreNotVacuous() throws {
        #expect(CadenceSourceScan.matchCount(Self.rawDateWrite, in: #"task.dueDate = "" "#) == 1)
        #expect(CadenceSourceScan.matchCount(Self.rawDateWrite, in: "task.scheduledDate = key\n") == 1)
        #expect(CadenceSourceScan.matchCount(Self.rawDateWrite, in: "task.scheduledStartMin = -1\n") == 1)
        #expect(CadenceSourceScan.matchCount(Self.rawDateWrite, in: "if task.dueDate == todayKey {") == 0)
        #expect(CadenceSourceScan.matchCount(Self.rawDateWrite, in: "@State private var dueDate = Date()") == 0)
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedMutation, in: "CadenceTaskMutationSupport.setDueDate(k, for: t, modelContext: c)") == 1
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedMutation, in: "CadenceTaskDateEditing.setDueDate(k, for: t, in: c)") == 0
        )
        #expect(
            CadenceSourceScan.matchCount(Self.unwrappedMutation, in: "CadenceTaskMutationSupport.setPriority(p, for: t, modelContext: c)") == 0
        )

        // The reader really does return the repository's own text: the pure mutation layer is
        // *supposed* to write these fields directly, so the needle must fire there and only there.
        let mutationLayer = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(Self.rawDateWrite, in: mutationLayer) > 10,
            "the scan read no raw date writes in the mutation layer, so it read the wrong file"
        )
    }
}
