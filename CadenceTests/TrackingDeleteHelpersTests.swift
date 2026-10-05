import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **The goal and habit delete tests are gone with the helpers they covered** ([[T-2079]]).
///
/// This suite held fifteen of them: that deleting a goal took its milestones and links but kept
/// the tasks and habits it had organised, that the macOS confirmation counted the whole subtree
/// rather than the direct children ([[T-1327]]), that deleting a habit took its completions and
/// cancelled its reminder only below the commit ([[T-1301]]/[[T-1348]]), and that a refused delete
/// left the persisted tree intact ([[T-1376]]). Every one of them was an assertion about
/// `ModelContext.deleteGoal` / `.deleteHabit`, which no longer exist: the owner retired goals and
/// habits at the depth *"remove the UI and stop writing, keep the schema"*, and a delete is a
/// write. They are not weakened here, they are **obsolete** — the behaviour they described is the
/// behaviour that was removed — and the replacement claim, that nothing in the app removes a
/// `Goal` or a `Habit` row, is what the inverted construction scans and the surviving list-cascade
/// suite hold between them.
///
/// **One claim really did lose half of its pair, and it is worth naming.**
/// `deletingAGoalTakesAMilestoneWhoseOwnContextIsElsewhere` was one side of a deliberate
/// disagreement with `ListDeleteHelpersTests
/// .deleteContextLeavesAMilestoneFiledElsewhereAliveAsATopLevelGoal` ([[T-1324]]): the goal cascade
/// walked `subGoals` with no container filter, the context cascade did not, and both halves were
/// pinned so the disagreement could not go quiet. The context half survives, because
/// `ModelContext.deleteContext` still cascades through a context's goals — it is the one path left
/// that can remove one of these rows, and [[T-2077]] records why it was left alone.
///
/// **Why this file and this name survive at all:** the three tests below are about
/// `TaskPriority.rank` and were always squatters here. Moving them would rename a suite that
/// `CadenceTests/CadenceRealTreeSweepManifest.txt` lists by name, so they keep their address and
/// the file keeps its, which is the cheaper of the two wrong-looking options. Renaming it is
/// follow-up work, not this ticket's.
@MainActor
struct TrackingDeleteHelpersTests {

    /// Every "sort by priority" in the app means one ordering. It existed as eight independent
    /// switches; the enum owns it now, and **nothing forwards to it any more** — every caller
    /// reads `priority.rank`.
    ///
    /// This used to end in a loop over `TaskPriority.allCases` asserting each surviving
    /// free-function spelling against the enum, because a forwarder that drifts is a sort that
    /// silently disagrees with every other sort. T-1011 inlined the last four call sites and
    /// deleted both forwarders, so there is nothing left for that loop to name — the empty
    /// declaring set is asserted directly by
    /// `everyPriorityRankSpellingInProductionSourceIsOneTheRankLoopReaches` below, which is now
    /// the whole of the anti-drift guard.
    ///
    /// What stays here is the property the rest of the codebase cites this test by name for:
    /// `TaskPriority.rank` is **ordered and injective**. `CadenceTaskQuerySupport.sortKeyOrder`
    /// and `MobileTaskSortStabilityTests` both lean on the injectivity to treat
    /// `lhs.priority != rhs.priority` and a rank comparison as the same question.
    ///
    /// A third spelling used to be asserted here: `taskPriorityRank` in
    /// `macOS/Views/TaskSortHelpers.swift`, described above as "the spelling that drives every
    /// macOS task sort". It drove nothing — `TaskOrdering.precedes` reads `priority.rank`
    /// directly — and the file is gone (T-639).
    @Test func priorityRankIsOneOrderingSharedByEveryCaller() {
        #expect(TaskPriority.high.rank > TaskPriority.medium.rank)
        #expect(TaskPriority.medium.rank > TaskPriority.low.rank)
        #expect(TaskPriority.low.rank > TaskPriority.none.rank)

        // The ordering is total: no two priorities may share a rank.
        #expect(Set(TaskPriority.allCases.map(\.rank)).count == TaskPriority.allCases.count)
    }

    /// **The declaring set is empty, and that is now the whole guard.**
    ///
    /// The history is a shrinking list. Eight hand-written priority switches became one enum
    /// property plus forwarders; T-670 removed the two forwarders no test could *reach*
    /// (`CadenceTodayWidgetSupport` and `GoalContributionSummary`, both `private static`, both
    /// correct — the state that precedes drift, and the widget's was the dangerous one because
    /// `CadenceWidgets` compiles `Services/` and `Models/` but not `Shared/`, so a divergence
    /// there ships to the Home Screen with this suite green). T-1011 removed the last two, in
    /// `CadenceTaskQuerySupport` and `CalendarBoardPlannerSupport`: between them they had four
    /// call sites, all now spelling `priority.rank` directly.
    ///
    /// So there is no longer a set of "blessed" forwarders to keep honest against the enum, and
    /// the loop that did that is gone with them. What remains is stronger and cheaper: **no**
    /// `func priorityRank(` may exist in production source at all. A re-grown forwarder — private
    /// or not, correct or not — fails here the day it is written, rather than the day it drifts.
    @Test func everyPriorityRankSpellingInProductionSourceIsOneTheRankLoopReaches() throws {
        let readStripped = CadenceSourceScan.strippedSourceReader()
        var declaringFiles: [String] = []
        var scannedFiles = 0

        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                scannedFiles += 1
                if try readStripped(path).contains("func priorityRank(") {
                    declaringFiles.append(path)
                }
            }
        }

        #expect(declaringFiles.sorted() == [String]())

        // Non-vacuity matters more for an empty expectation than for any other kind, because a
        // walk that opened nothing produces exactly the same answer as a walk that found nothing.
        // Three separate ways for this to have been a real sweep:
        //
        // 1. It really walked the tree, not an empty directory list.
        #expect(scannedFiles > 400)
        // 2. The two files that lost a forwarder are still readable and still hold their other
        //    contents, so the paths did not silently stop resolving.
        #expect(try readStripped("Cadence/Shared/CadenceTaskQuerySupport.swift")
            .contains("static func sortKeyOrder("))
        #expect(try readStripped("Cadence/Shared/CadenceCalendarPlanningSupport.swift")
            .contains("static func railTaskSort("))
        // 3. The needle itself still matches when a file really does declare a function that way,
        //    which the stripped reader is what decides — so a stripper that started returning
        //    empty strings cannot pass this test.
        #expect(try readStripped("Cadence/Shared/CadenceCalendarPlanningSupport.swift")
            .contains("func railAnchorKey("))
    }

    /// Asserting the rank forwarders is not enough on its own — the comparator could stop calling
    /// them. This pins the pair the rank loop above cannot reach: `.low` against `.none`, through
    /// `TaskOrdering.precedes` itself.
    ///
    /// It used to go through `taskSortPrecedes`, a macOS-only forwarder with no production caller
    /// of its own, deleted by T-639. The assertions are the same ones; only the spelling under
    /// test changed, from a wrapper nothing ran to the comparator every surface runs.
    @Test func prioritySortRanksALowPriorityTaskAboveAnUnprioritisedOne() {
        let low = AppTask(title: "Low")
        low.priority = .low
        low.order = 1
        let unset = AppTask(title: "Unset")
        unset.priority = TaskPriority.none
        unset.order = 0

        #expect(TaskOrdering.precedes(low, unset, field: .priority, direction: .descending))
        #expect(!TaskOrdering.precedes(unset, low, field: .priority, direction: .descending))
        // Ascending is the same ordering read backwards, not a different ordering.
        #expect(TaskOrdering.precedes(unset, low, field: .priority, direction: .ascending))
    }

    // MARK: - The refusal path

    private struct CommitRefused: Error {}

}
