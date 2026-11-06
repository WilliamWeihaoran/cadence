import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-6481]]: the user-invoked **Merge Duplicates** action (Settings > Data Safety, both
/// platforms) and the one thing it does that the automatic passes refuse to — fold two same-id
/// tasks equal in every field. `DataIntegrityRepairServiceTests.sameIDTasksEqualInEveryFieldAreLeftAlone`
/// still pins the automatic half, so the two together say the tie is decided **only** on request.
///
/// `.preservesTheStoredLaunchReports` because `mergeDuplicatesOnRequest` writes `lastReport()`,
/// the same key the launch reads back. Every container is in memory.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct DataIntegrityUserMergeTests {
    private struct RefusedCommit: Error {}

    /// Two rows carrying one id and equal in every scalar, each holding one distinct subtask.
    private func fullTiePair(in modelContext: ModelContext) -> (id: UUID, first: AppTask, second: AppTask) {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000)
        let first = AppTask(title: "Same")
        let second = AppTask(title: "Same")
        for task in [first, second] {
            task.id = id
            task.notes = "same notes"
            task.createdAt = created
            modelContext.insert(task)
        }
        let firstSubtask = Subtask(title: "only on the first")
        let secondSubtask = Subtask(title: "only on the second")
        modelContext.insert(firstSubtask)
        modelContext.insert(secondSubtask)
        firstSubtask.parentTask = first
        first.subtasks = [firstSubtask]
        secondSubtask.parentTask = second
        second.subtasks = [secondSubtask]
        return (id, first, second)
    }

    @Test func aFullTieIsFoldedIntoOneTaskWhenThePersonAsks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let pair = fullTiePair(in: modelContext)
        try modelContext.save()

        let report = try DataIntegrityRepairService.mergeDuplicatesOnRequest(in: modelContext)

        #expect(report.success)
        #expect(report.duplicateTasksMerged == 1)
        #expect(report.duplicatesMerged == 1)
        let fresh = ModelContext(container)
        let tasks = try fresh.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 1, "the tie was left unmerged")
        #expect(tasks.first?.id == pair.id)
        // Nothing the deleted copy held is lost: both subtasks are on the survivor.
        let titles = Set((tasks.first?.subtasks ?? []).map(\.title))
        #expect(titles == ["only on the first", "only on the second"])
        #expect(try fresh.fetchCount(FetchDescriptor<Subtask>()) == 2)
    }

    /// The same store through the launch's own entry point keeps both rows — so the tie-break is
    /// the request's alone and not a change to the automatic policy.
    @Test func theLaunchRepairStillLeavesTheSameFullTieAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        _ = fullTiePair(in: modelContext)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateTasksMerged == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AppTask>()) == 2)
    }

    /// The request runs every merge, not only the task pass: two active lists with one name fold
    /// into one, as the deferred launch merge would.
    @Test func theRequestAlsoMergesDuplicateContainers() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        modelContext.insert(Context(name: "Work"))
        modelContext.insert(Context(name: "work"))
        try modelContext.save()

        let report = try DataIntegrityRepairService.mergeDuplicatesOnRequest(in: modelContext)

        #expect(report.duplicateContextsMerged == 1)
        #expect(report.duplicatesMerged == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Context>()) == 1)
    }

    /// A store with nothing to merge takes no commit at all, so a person's unrelated pending edit
    /// is not committed behind their back.
    @Test func nothingToMergeTakesNoCommit() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        modelContext.insert(AppTask(title: "Alone"))
        try modelContext.save()
        var commits = 0

        let report = try DataIntegrityRepairService.mergeDuplicatesOnRequest(
            in: modelContext,
            commit: { _ in commits += 1 },
            refusing: false
        )

        #expect(report.success)
        #expect(report.duplicatesMerged == 0)
        #expect(commits == 0)
    }

    /// A refused commit puts the context back: both copies are still there to see, the error
    /// reaches the caller, and the stored report records a failure rather than the merge.
    @Test func aRefusedCommitLeavesBothCopiesAndReportsTheFailure() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        _ = fullTiePair(in: modelContext)
        try modelContext.save()

        #expect(throws: RefusedCommit.self) {
            try DataIntegrityRepairService.mergeDuplicatesOnRequest(
                in: modelContext,
                commit: { _ in throw RefusedCommit() },
                refusing: false
            )
        }

        #expect(try modelContext.fetchCount(FetchDescriptor<AppTask>()) == 2)
        #expect(!modelContext.hasChanges)
        #expect(DataIntegrityRepairService.lastReport()?.success == false)
        #expect(DataIntegrityRepairService.lastReport()?.source == "user-merge-duplicates")
    }

    @Test func aMirroringStoreWaitsForItsFirstImportAndNothingElseDoes() {
        typealias Presentation = CadenceDuplicateMergePresentation
        #expect(Presentation.readiness(storeMirrorsToCloudKit: true, firstImportCompleted: false) == .waitingForFirstSync)
        #expect(Presentation.readiness(storeMirrorsToCloudKit: true, firstImportCompleted: true) == .ready)
        #expect(Presentation.readiness(storeMirrorsToCloudKit: false, firstImportCompleted: false) == .ready)
    }

    /// The waiting branch of the shared sequence touches nothing: the tie is still two rows.
    @Test func theSharedSequenceDoesNotMergeWhileWaitingForTheFirstImport() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        _ = fullTiePair(in: modelContext)
        try modelContext.save()

        let message = CadenceDuplicateMergePresentation.run(
            in: modelContext,
            storeMirrorsToCloudKit: true,
            firstImportCompleted: false
        )

        #expect(message == CadenceDuplicateMergePresentation.waitingForFirstSyncMessage)
        #expect(try modelContext.fetchCount(FetchDescriptor<AppTask>()) == 2)
    }

    @Test func theSharedSequenceReportsWhatItMergedAndWhatFailed() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        _ = fullTiePair(in: modelContext)
        try modelContext.save()

        let refused = CadenceDuplicateMergePresentation.run(
            in: modelContext,
            storeMirrorsToCloudKit: false,
            firstImportCompleted: false,
            commit: { _ in throw RefusedCommit() }
        )
        #expect(refused.hasPrefix("Merge failed, nothing was changed"))
        #expect(try modelContext.fetchCount(FetchDescriptor<AppTask>()) == 2)

        let merged = CadenceDuplicateMergePresentation.run(
            in: modelContext,
            storeMirrorsToCloudKit: false,
            firstImportCompleted: false
        )
        #expect(merged == "Merged 1 duplicate.")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AppTask>()) == 1)

        let again = CadenceDuplicateMergePresentation.run(
            in: modelContext,
            storeMirrorsToCloudKit: false,
            firstImportCompleted: false
        )
        #expect(again == CadenceDuplicateMergePresentation.outcomeMessage(mergedCount: 0))
    }
}
