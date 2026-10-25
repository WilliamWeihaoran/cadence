#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// T-6451 and T-6452: two crash shapes the RC crash audit found by reading, pinned by behaviour.
///
/// T-6451 — every id-keyed map over live `AppTask` / `MarkdownImageAsset` rows used
/// `Dictionary(uniqueKeysWithValues:)`, which traps the moment two rows share an `id`. Each test
/// below hands a builder two rows sharing one id: before the fix the test host died on
/// `Fatal error: Duplicate values for key`; now the first row wins.
///
/// T-6452 — the macOS New Task sheet's draft subtasks were `[String]` rows keyed by index.
@MainActor
struct CadenceIdentityMapTests {

    @Test func identityMapKeepsTheFirstOfTwoRowsSharingAnID() {
        let shared = UUID()
        let other = UUID()

        let map = CadenceIdentityMap.firstWins([(shared, "first"), (other, "other"), (shared, "second")])

        #expect(map.count == 2)
        #expect(map[shared] == "first")
        #expect(map[other] == "other")
    }

    @Test func liveEditorTaskEmbedMapSurvivesTwoTasksSharingAnID() {
        let first = AppTask(title: "Original")
        let duplicate = AppTask(title: "Restored copy")
        duplicate.id = first.id

        // The map `MarkdownEditorView`, `iOSMarkdownEditingSurface` and `iOSFocusView` render from.
        let infos = NoteExportSupport.taskEmbedRenderInfos(for: [first, duplicate])

        #expect(infos.count == 1)
        #expect(infos[first.id]?.title == "Original")
    }

    @Test func frozenTaskGroupsResolveWhenTwoTasksShareAnID() {
        let first = AppTask(title: "Original")
        let duplicate = AppTask(title: "Restored copy")
        duplicate.id = first.id
        let snapshot = [FrozenTaskGroupSnapshot(id: "g", title: "Group", taskIDs: [first.id])]

        let resolved = resolveFrozenTaskGroups(snapshot, from: [first, duplicate])

        #expect(resolved?.first?.tasks.map(\.title) == ["Original"])
    }

    @Test func recurrenceLinkRepairSurvivesTwoDeletedTasksSharingAnID() {
        let predecessor = AppTask(title: "Monday")
        let deleted = AppTask(title: "Tuesday")
        let deletedTwin = AppTask(title: "Tuesday")
        deletedTwin.id = deleted.id
        predecessor.recurrenceSpawnedTaskID = deleted.id

        CadenceTaskRecurrenceWorkflowSupport.repairDanglingRecurrenceLinks(
            forDeleted: [deleted, deletedTwin],
            allTasks: [predecessor, deleted, deletedTwin]
        )

        // Nothing in the chain survives, so the predecessor's pointer is cleared rather than left
        // dangling — the repair ran to completion instead of trapping on the duplicate key.
        #expect(predecessor.recurrenceSpawnedTaskID == nil)
    }

    // MARK: - T-6452: draft subtasks keyed by identity

    @Test func removingADraftSubtaskRemovesExactlyThatDraftAndKeepsTheOthersIdentities() {
        let drafts = CreateTaskSubtaskDraft.drafts(from: ["One", "Two", "Three"])

        let remaining = CreateTaskSubtaskDraft.removing(drafts[1].id, from: drafts)

        #expect(remaining.map(\.title) == ["One", "Three"])
        #expect(remaining.map(\.id) == [drafts[0].id, drafts[2].id])
    }

    @Test func draftSubtaskTitlesReachTheSavePathExactlyAsTyped() {
        // The save path used to hand `[String]` state straight to `TaskCreationDraft`; the drafts
        // must hand over the same array, untrimmed and with blanks kept — trimming is the
        // creation service's job, not the sheet's.
        let typed = ["  Draft the deck  ", "", "Rehearse", "Rehearse"]

        #expect(CreateTaskSubtaskDraft.titles(of: CreateTaskSubtaskDraft.drafts(from: typed)) == typed)
        #expect(Set(CreateTaskSubtaskDraft.drafts(from: typed).map(\.id)).count == typed.count)
    }
}
#endif
