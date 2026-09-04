import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-868 / T-869 / T-870: every remaining drag-to-rearrange, held to the T-614 standard.**
///
/// T-614 settled the question these three inherit: **a rearrangement the user can see is a success
/// report.** A row that stays where you dropped it makes a stronger claim than a dismissed sheet,
/// and a refused reorder is the failure the rule exists to catch — a silent revert at next launch
/// with nothing to retry. `SettingsView.moveContext` was brought up to that standard there; the
/// audit that followed found five more sites, in three different states:
///
/// - **T-869 — no commit at all.** `ListTasksView.reorderTask` and the kanban card drop
///   (`KanbanBoardSupport.reorder`, reached from both column views) renumbered `order` across a
///   column and never saved. Verified before it was fixed: `ListDetailComponents.swift` contained
///   no `save()` anywhere, and `TaskListKanbanColumn.handleTaskDrop` answered `true` over it.
///   Invisible to `CadenceSaveCommitDisciplineTests` twice over — half 2 needs a *swallowed*
///   commit in the frame to hang the rule on and there was none, and half 3 fires on insert/delete
///   rather than on field writes.
/// - **T-868 — the T-614 shape exactly.** `TasksPanelSupport.reorderTask` and
///   `SidebarComponents.reorderList` ended a visible renumber with `try? modelContext.save()`.
/// - **T-870 — the same defect, stored as a blob.** The kanban *column* reorder writes
///   `sectionConfigsRaw` through `mutateSectionConfigs`, so it carries no `order` field for any
///   `\.order` sweep to find, and it reached no commit either.
///
/// **What the two behavioural tests below prove, and why they are not source scans.** A store that
/// never took the write is the whole defect, and a second `ModelContext` over the same container is
/// how this target already asks that question (`CadenceInPlaceEditFlushCommitTests`). Both were red
/// before the fix for exactly the reason the tickets state: the arrangement was in the objects and
/// not in the store.
///
/// **The refusal paths are behavioural too**, through the injected `commit:` — a `save()` that
/// throws cannot be provoked out of an in-memory container, which is why every commit unit in this
/// app takes one.
///
/// **The seven call sites are source scans**, because six of them are `private` members of SwiftUI
/// views. They pin the same four facts T-614's pair pins: the commit exists, the swallow is gone,
/// the undo is a snapshot rather than `rollback()`, and the refusal is reported where the user is
/// already looking.
///
/// ## What the instrument here cannot see
///
/// This suite names its six sites literally. It is **not** a detector, and the narrow detector that
/// suggests itself — "`\w+\.order = ` inside a loop, reaching a swallowed or absent commit" — would
/// have found T-868 and T-869 and been **blind to T-870**, whose ordering is a re-serialised
/// `[TaskSectionConfig]` blob with no `order` field at all. A detector whose blind spot is one of
/// the tickets it was written for is worse than a list, because the list does not claim coverage it
/// does not have. `CadenceSaveCommitDisciplineTests` remains the general instrument; this is the
/// per-site pinning its half 2 asks for.
@MainActor
struct CadenceReorderCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    // MARK: - Behavioural: the kanban card drop (T-869)

    /// **Behavioural, and red before T-869.** The column's new order is read back through a second
    /// `ModelContext`, which is the only reading that answers "does this survive a relaunch".
    ///
    /// Before the fix this failed with the store still holding `[0, 1, 2]` while the three live
    /// `AppTask`s answered the new arrangement — the exact split the ticket describes.
    @Test func akanbanCardDropIsInTheStoreAndNotOnlyOnScreen() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let third = AppTask(title: "Third")
        for (index, task) in [first, second, third].enumerated() {
            task.order = index
            modelContext.insert(task)
        }
        try modelContext.save()

        #expect(
            KanbanBoardSupport.reorder(
                [first, second, third],
                moving: third,
                before: first,
                in: modelContext
            )
        )

        #expect(!modelContext.hasChanges, "the drop is still pending after it answered yes")
        #expect(
            try storedOrder(in: modelContainer) == ["Third", "First", "Second"],
            "the store does not hold the arrangement the board is drawing"
        )
    }

    /// **Behavioural.** A refused drop puts every card back — including the container fields the
    /// drop's own `assigning:` closure wrote, which is what makes a cross-column drop restorable
    /// rather than half-applied.
    @Test func arefusedKanbanCardDropPutsEveryCardBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        modelContext.insert(area)
        for (index, task) in [first, second].enumerated() {
            task.order = index
            modelContext.insert(task)
        }
        try modelContext.save()

        #expect(
            !KanbanBoardSupport.reorder(
                [first, second],
                moving: second,
                before: first,
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                assigning: { second.area = area }
            )
        )

        #expect(second.order == 1 && first.order == 0, "the refused drop left the new order on screen")
        #expect(second.area == nil, "the refused drop left the card in the column it was dropped on")
    }

    // MARK: - Behavioural: the kanban column drop (T-870)

    /// **Behavioural, and red before T-870.** Column order is a re-serialised blob on the list, so
    /// the read-back is the list's own `sectionConfigs` through a second context.
    @Test func akanbanColumnDropIsInTheStoreAndNotOnlyOnScreen() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "Done")
        ]
        modelContext.insert(area)
        try modelContext.save()

        #expect(
            area.reorderSectionConfigs(in: modelContext) {
                KanbanBoardSupport.reorderedSectionConfigs($0, movingName: "Done", targetName: "Doing")
            }
        )

        #expect(!modelContext.hasChanges, "the column drop is still pending after it answered yes")
        #expect(
            try storedSectionNames(in: modelContainer) == [TaskSectionDefaults.defaultName, "Done", "Doing"],
            "the store does not hold the column order the board is drawing"
        )
    }

    /// **Behavioural.** A refused column drop puts the whole blob back, so the board redraws the
    /// order the store still holds rather than the one it refused.
    @Test func arefusedKanbanColumnDropPutsTheColumnsBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        project.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "Done")
        ]
        modelContext.insert(project)
        try modelContext.save()

        #expect(
            !project.reorderSectionConfigs(in: modelContext, commit: { _ in throw CommitRefused() }) {
                KanbanBoardSupport.reorderedSectionConfigs($0, movingName: "Done", targetName: "Doing")
            }
        )

        #expect(
            project.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing", "Done"],
            "the refused column drop left the new order on screen"
        )
    }

    // MARK: - Behavioural: the shared renumber unit (T-868, T-869)

    /// **Behavioural.** The unit the three row drops share commits the renumber, and reads back.
    @Test func acommittedRowRenumberIsInTheStore() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        for (index, task) in [first, second].enumerated() {
            task.order = index
            modelContext.insert(task)
        }
        try modelContext.save()

        #expect(
            CadenceOrderCommit.commit(
                [second, first],
                readOrder: { $0.order },
                writeOrder: { $0.order = $1 },
                in: modelContext
            )
        )

        #expect(try storedOrder(in: modelContainer) == ["Second", "First"])
    }

    /// **Behavioural.** A refused renumber puts **every** previous `order` back, not just the
    /// dragged row's — the rows either all moved or none did, and the second is what the store
    /// holds.
    @Test func arefusedRowRenumberPutsEveryPreviousOrderBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let third = AppTask(title: "Third")
        for (index, task) in [first, second, third].enumerated() {
            task.order = index * 10
            modelContext.insert(task)
        }
        try modelContext.save()

        #expect(
            !CadenceOrderCommit.commit(
                [third, first, second],
                readOrder: { $0.order },
                writeOrder: { $0.order = $1 },
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )

        let orders: [Int] = [first.order, second.order, third.order]
        #expect(orders == [0, 10, 20], "the refused renumber stuck")
    }

    /// The undo is a snapshot restore, not `modelContext.rollback()`: this is the app's single
    /// context, so a refused reorder must not take somebody's half-typed note with it. The same
    /// reason `CadencePendingChangePersistence.commitEdit` gives for not offering one.
    @Test func arefusedRowRenumberLeavesUnrelatedPendingWorkAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let note = Note(kind: .permanent, title: "Draft", content: "one")
        for (index, task) in [first, second].enumerated() {
            task.order = index
            modelContext.insert(task)
        }
        modelContext.insert(note)
        try modelContext.save()

        note.content = "one two"

        #expect(
            !CadenceOrderCommit.commit(
                [second, first],
                readOrder: { $0.order },
                writeOrder: { $0.order = $1 },
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )

        #expect(note.content == "one two", "the refused reorder discarded unrelated pending work")
    }

    // MARK: - Behavioural: the coordinator both task panels share

    /// **The coordinator answers the reorder's own answer (T-868).** Today and All Tasks/Inbox both
    /// route their row drops through `TasksPanelDropCoordinator`, so a `true` written over a refused
    /// commit would spring the row to a position neither the screen nor the store holds — on both
    /// screens at once, from one line.
    @Test func arowDropAnswersFalseWhenTheReorderWasRefused() throws {
        let modelContext = ModelContext(try container())
        let dropped = AppTask(title: "Draft")
        let target = AppTask(title: "Ship")
        modelContext.insert(dropped)
        modelContext.insert(target)

        func coordinator(reorderSucceeds: Bool) -> TasksPanelDropCoordinator {
            TasksPanelDropCoordinator(
                allTasks: [dropped, target],
                taskIDFromPayload: { TasksPanelSupport.taskID(from: $0) },
                assignTask: { _, _ in true },
                reorderTask: { _, _, _ in reorderSucceeds }
            )
        }
        let payload = TasksPanelSupport.taskDragPayload(for: dropped)

        // Non-vacuity first: the same drop, the same rows, and a commit that lands.
        #expect(
            coordinator(reorderSucceeds: true).handleTaskDrop(
                payload: payload,
                targetTask: target,
                scopeTasks: [dropped, target],
                dropKey: nil
            )
        )
        #expect(
            !coordinator(reorderSucceeds: false).handleTaskDrop(
                payload: payload,
                targetTask: target,
                scopeTasks: [dropped, target],
                dropKey: nil
            ),
            "a refused reorder was reported to the row as a drop that happened"
        )
    }

    // MARK: - The seven call sites

    /// **T-868(a).** Today's and All Tasks'/Inbox's row drop, which both reach this one function.
    @Test func thetaskRowDropCommitsProperlyRatherThanSwallowingIt() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/TasksPanelSupport.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "reorderTask", in: source)

        #expect(body.contains("CadenceOrderReassignment.moved("), "non-vacuity: not the rearranging body")
        #expect(!body.contains("try? modelContext.save()"), "the row drop swallows its save again")
        #expect(body.contains("CadenceOrderCommit.commit("))
    }

    /// **T-869(a).** A list's own Tasks tab, which reached no commit at all.
    @Test func thelistDetailRowDropReachesACommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailComponents.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "reorderTask", in: source)

        #expect(body.contains("sorted.insert(element"), "non-vacuity: not the rearranging body")
        #expect(body.contains("CadenceOrderCommit.commit("), "the list's Tasks tab still reaches no commit")
        #expect(!body.contains("try? modelContext.save()"))
    }

    /// **T-868(b).** The sidebar's list drag.
    @Test func thesidebarListDropCommitsProperlyRatherThanSwallowingIt() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/SidebarComponents.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "reorderList", in: source)

        #expect(body.contains("setOrder"), "non-vacuity: not the renumbering body")
        #expect(!body.contains("try? modelContext.save()"), "the sidebar drop swallows its save again")
        #expect(body.contains("CadenceOrderCommit.commit("))
        #expect(!body.contains("rollback()"), "the sidebar undo discards unrelated pending work")
    }

    /// **T-869(b).** Both kanban card drops — the two column implementations that share
    /// `KanbanBoardSupport.reorder`.
    ///
    /// `assigning:` is asserted at both sites because it is the half that makes the undo whole: the
    /// refiling has to be inside the commit, or a refused cross-column drop leaves the card in its
    /// new column at its old position.
    @Test func bothKanbanColumnsCommitTheirCardDrop() throws {
        for path in [
            "Cadence/macOS/Views/KanbanListColumnView.swift",
            "Cadence/macOS/Views/KanbanSectionColumnView.swift"
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            let body = try CadenceCommitSurfaceScan.declarationBody(named: "moveTask", in: source)

            #expect(body.contains("KanbanBoardSupport.reorder("), "non-vacuity: \(path) no longer reorders here")
            #expect(body.contains("in: modelContext"), "\(path) reorders cards without a commit")
            #expect(body.contains("assigning:"), "\(path) refiles the card outside its own commit")
            #expect(!body.contains("try? modelContext.save()"), "\(path) swallows its card drop")
        }
    }

    /// **T-870.** The kanban *column* drop, whose ordering is a blob.
    @Test func thekanbanColumnDropReachesACommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "reorderSection", in: source)

        #expect(body.contains("reorderedSectionConfigs("), "non-vacuity: not the column-reordering body")
        #expect(body.contains("reorderSectionConfigs(in: modelContext)"), "the column drop reaches no commit")
    }

    /// **All seven surfaces report, in one sentence, cleared by the next attempt.**
    ///
    /// The ternary is pinned whole rather than in halves because the two failure modes it rules out
    /// are opposite ones: a site that only ever *sets* the notice leaves a stale refusal up over a
    /// drag that has since landed, and a site that only ever clears it never says anything at all.
    /// Written as one expression they cannot come apart.
    @Test func everySurfaceNamesARefusedReorderInTheOneSharedSentence() throws {
        #expect(CadenceOrderCommit.failureNotice == "Couldn't save this new order. Nothing was moved.")

        var reporting = 0
        for path in [
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/macOS/Views/TasksListView.swift",
            "Cadence/macOS/Views/SidebarComponents.swift",
            "Cadence/macOS/Views/ListDetailComponents.swift",
            "Cadence/macOS/Views/KanbanListColumnView.swift",
            "Cadence/macOS/Views/KanbanSectionColumnView.swift",
            "Cadence/macOS/Views/KanbanListSectionSupportViews.swift"
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                !source.contains("\"Couldn't save this new order"),
                "\(path) retypes the reorder sentence instead of reading it"
            )
            #expect(
                source.contains("reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice"),
                "\(path) does not name and clear a refused reorder in one expression"
            )
            #expect(
                source.contains("CadenceInlineFailureNotice(text: reorderFailureNotice)")
                    || source.contains("failureNotice: columnFailureNotice"),
                "\(path) sets a notice nothing draws"
            )
            reporting += 1
        }
        #expect(reporting == 7, "expected seven reorder surfaces, checked \(reporting)")
    }

    // MARK: - Helpers

    private func storedOrder(in modelContainer: ModelContainer) throws -> [String] {
        try ModelContext(modelContainer)
            .fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))
            .map(\.title)
    }

    private func storedSectionNames(in modelContainer: ModelContainer) throws -> [String] {
        let areas = try ModelContext(modelContainer).fetch(FetchDescriptor<Area>())
        return areas.first?.sectionConfigs.map(\.name) ?? []
    }
}
