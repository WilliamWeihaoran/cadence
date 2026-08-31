import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-344 decided, and T-357 pinned.** Two things this file exists to stop.
///
/// The first is a product question the audit filed rather than answered: what does the completion
/// circle *mean* on a cancelled task? The answer implemented here is that the circle toggles
/// **settled**, not **done** — see `CadenceTaskMutationSupport.toggleCompletion` for the reasoning.
/// The behavioural tests pin the transition and the source scan pins that the four labels
/// describing that gesture read the same predicate that decides it, because a label and an action
/// disagreeing is the state T-344 reported.
///
/// The second is structural. `TaskCompletionAnimationManager` had two different direct
/// `task.status =` assignments found by two independent audits ([[T-341]], [[T-357]]). Fixing the
/// two known ones invites a third, so the scan below bans the *shape* rather than the two
/// instances.
@MainActor
struct CadenceTaskStatusLifecycleSurfaceTests {

    // MARK: - T-344: the circle toggles settled, not done

    @Test func theCircleRestoresACancelledTaskRatherThanCompletingIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "abandoned")
        task.status = .cancelled
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test func theCircleStillRestoresADoneTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "finished")
        task.status = .done
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test func theCircleStillCompletesAnOpenTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        for status in [TaskStatus.todo, .inProgress] {
            let task = AppTask(title: "open \(status.rawValue)")
            task.status = status
            context.insert(task)
            try context.save()

            CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

            #expect(task.status == .done)
            #expect(task.completedAt != nil)
        }
    }

    /// Says the rule instead of listing its cases: the toggle's destination is decided by
    /// `isFinishedTask` and nothing else, so a fifth `TaskStatus` cannot land in a gap.
    @Test func theCircleSendsExactlyTheFinishedStatusesBackToTodo() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        var sawFinished = false
        var sawOpen = false

        for status in TaskStatus.allCases {
            let task = AppTask(title: "task \(status.rawValue)")
            task.status = status
            context.insert(task)
            try context.save()
            let wasFinished = CadenceTaskQuerySupport.isFinishedTask(task)
            sawFinished = sawFinished || wasFinished
            sawOpen = sawOpen || !wasFinished

            CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

            #expect(
                task.status == (wasFinished ? .todo : .done),
                "\(status) is \(wasFinished ? "finished" : "open") and the toggle sent it to \(task.status)"
            )
        }

        // Non-vacuity: the loop must have exercised both halves of the rule.
        #expect(sawFinished)
        #expect(sawOpen)
    }

    /// The reason the decision went this way round rather than the other: `markDone` advances a
    /// recurring series. Under the old rule, a tap meant to un-cancel a recurring task minted a
    /// fresh live occurrence of it; under this one it does not.
    @Test func restoringACancelledRecurringTaskDoesNotMintANewOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "weekly review")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        task.status = .cancelled
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        let all = try context.fetch(FetchDescriptor<AppTask>())
        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(all.count == 1)
    }

    // MARK: - T-344: the labels describe the gesture they trigger

    /// Four places name what a tap or a swipe on the completion control will do. All four now ask
    /// `isFinishedTask`, so none of them can promise "Done" on a task the tap will restore.
    @Test func everyLabelForTheCompletionGestureReadsTheSamePredicate() throws {
        try expectOccurrences(
            of: "CadenceTaskQuerySupport.isFinishedTask(task)",
            at: [
                // One `let isFinished`, read by the swipe's title, image and tint.
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSTaskDetailComponents.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1
            ]
        )
        try expectOccurrences(of: "isFinished ?", at: ["Cadence/iOS/iOSTaskRowActionViews.swift": 3])

        // And no label in those files still branches on `isDone` alone. The needle carries a
        // leading non-identifier character on purpose: `subtask.isDone ? "Mark subtask todo"` in
        // the detail components is a *subtask's* control, correct as it stands, and a bare
        // `task.isDone ? "` needle would fail on it.
        for path in [
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskDetailComponents.swift",
            "Cadence/iOS/iOSBoardCards.swift"
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(
                code.matchCount(ofPattern: taskLevelDoneLabel) == 0,
                "\(path) still labels a task-level completion control by isDone alone"
            )
        }

        // The needle is not vacuous, and it does not reach the spelling that is fine.
        #expect(#"title: task.isDone ? "Todo" : "Done""#.matchCount(ofPattern: taskLevelDoneLabel) == 1)
        #expect(#"(task.isDone ? "Mark not done" : "Mark done")"#.matchCount(ofPattern: taskLevelDoneLabel) == 1)
        #expect(#"(subtask.isDone ? "Mark subtask todo" : "Complete subtask")"#.matchCount(ofPattern: taskLevelDoneLabel) == 0)
    }

    /// The shared toggle is the one place the decision lives; the macOS animation manager defers to
    /// the same predicate rather than keeping its own copy of the rule.
    @Test func bothToggleEntryPointsReadTheFinishedPredicate() throws {
        try expectOccurrences(
            of: "if CadenceTaskQuerySupport.isFinishedTask(task)",
            at: [
                "Cadence/Shared/CadenceTaskMutationSupport.swift": 1,
                "Cadence/macOS/Services/TaskCompletionAnimationManager.swift": 1
            ]
        )
        try expectOccurrences(
            of: "if task.isDone {",
            at: [
                "Cadence/Shared/CadenceTaskMutationSupport.swift": 0,
                "Cadence/macOS/Services/TaskCompletionAnimationManager.swift": 0
            ]
        )
    }

    // MARK: - T-357: no status write in the animation manager escapes the shared path

    /// Two audits, two different bypasses, one file. This bans the shape rather than the two
    /// instances: nothing in `TaskCompletionAnimationManager` may assign `status` or `completedAt`,
    /// and the three transitions it performs must each reach the shared workflow exactly once.
    ///
    /// A behavioural test cannot do this job. The contextless branch is unreachable in the shipping
    /// app — the manager's context is injected on root appear — so a *new* direct assignment added
    /// beside the funnel would break no behaviour anyone could observe until it did.
    @Test func noStatusIsAssignedDirectlyInTheAnimationManager() throws {
        let path = "Cadence/macOS/Services/TaskCompletionAnimationManager.swift"
        let code = try strippingComments(sourceFile(path))

        #expect(code.matchCount(ofPattern: directStatusAssignment) == 0, "\(path) assigns a task's status directly")
        #expect(code.matchCount(ofPattern: directCompletedAtAssignment) == 0, "\(path) stamps completedAt directly")

        // Every transition goes through the macOS wrapper, which is what adds the notification
        // reconcile hop around the shared recurrence transitions.
        try expectOccurrences(
            of: "TaskWorkflowService.markDone(task, in: context)",
            at: [path: 1]
        )
        try expectOccurrences(
            of: "TaskWorkflowService.markCancelled(task, in: context)",
            at: [path: 1]
        )
        try expectOccurrences(of: "TaskWorkflowService.markTodo(task)", at: [path: 1])
        // One funnel, and every call site of it.
        try expectOccurrences(of: "private func write(", at: [path: 1])
        try expectOccurrences(of: "write(.restored, to: task)", at: [path: 2])
        try expectOccurrences(of: "self.write(.done, to: task)", at: [path: 1])
        try expectOccurrences(of: "self.write(.cancelled, to: task)", at: [path: 1])

        // The needles are not vacuous, and they do not fire on a comparison or an equality test.
        #expect("task.status = .todo".matchCount(ofPattern: directStatusAssignment) == 1)
        #expect("self.task.status = status".matchCount(ofPattern: directStatusAssignment) == 1)
        #expect("task.status == .todo".matchCount(ofPattern: directStatusAssignment) == 0)
        #expect("status: task.status,".matchCount(ofPattern: directStatusAssignment) == 0)
        #expect("task.completedAt = Date()".matchCount(ofPattern: directCompletedAtAssignment) == 1)
        #expect("task.completedAt == nil".matchCount(ofPattern: directCompletedAtAssignment) == 0)
    }

    // MARK: - T-342: the freeze filter reads the shared predicate

    /// `TaskSurfaceFreezeSupportTests` pins the behaviour; this pins that it is the *shared*
    /// predicate doing it rather than a second local spelling of "done or cancelled", which is the
    /// defect shape T-374 is about.
    @Test func theFrozenSurfaceFiltersOnTheSharedFinishedPredicate() throws {
        // Two resolvers now, in `TaskSurfaceFreezeModels`. The audit counted two and this test
        // once counted four: `TasksPanel` hand-rolled `resolvedFrozenListGroups` and
        // `resolvedFrozenFlatSections` with a different result type, and both were readers of the
        // `.byDoDate` frozen snapshots — unreachable, and deleted with the mode in T-487. The
        // shared pair is what Today has always gone through, so the rule this pins is intact; the
        // two zeros below still hold `TasksPanel` to it if the hand-rolled shape ever comes back.
        try expectOccurrences(
            of: "CadenceTaskQuerySupport.isFinishedTask($0)",
            at: [
                "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift": 2
            ]
        )
        try expectOccurrences(
            of: "!$0.isDone",
            at: [
                "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift": 0,
                "Cadence/macOS/Views/TasksPanel.swift": 0
            ]
        )
        // And neither file grew a second local spelling of the rule beside the shared one.
        try expectOccurrences(
            of: "isCancelled",
            at: [
                "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift": 0,
                "Cadence/macOS/Views/TasksPanel.swift": 0
            ]
        )
    }

    // MARK: - Non-vacuity

    /// Without this, every zero above could be a scan reading an empty string — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuousInTaskStatusLifecycleSurface() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")

        let scanned = [
            "Cadence/Shared/CadenceTaskMutationSupport.swift",
            "Cadence/macOS/Services/TaskCompletionAnimationManager.swift",
            "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift",
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskDetailComponents.swift",
            "Cadence/iOS/iOSBoardCards.swift"
        ]
        for path in scanned {
            #expect(files.contains(path), "\(path) is not among the files the scan enumerated")
        }

        let manager = try strippingComments(sourceFile("Cadence/macOS/Services/TaskCompletionAnimationManager.swift"))
        #expect(manager.contains("final class TaskCompletionAnimationManager"))
        let mutation = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift"))
        #expect(mutation.contains("static func toggleCompletion"))
        let freeze = try strippingComments(sourceFile("Cadence/macOS/Views/TaskSurfaceFreezeModels.swift"))
        #expect(freeze.contains("func applyFrozenTaskOrder"))
        // `private var resolvedFrozenListGroups` / `resolvedFrozenFlatSections` were the two
        // needles here; both were `.byDoDate`-only and went with it (T-487). The scan still has to
        // prove it is reading this file, so it reads something Today actually draws.
        let panel = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(panel.contains("struct TasksPanel: View"))
        #expect(panel.contains("HoverFreezeObserver("))
        let actions = try strippingComments(sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift"))
        #expect(actions.contains("static func trailing("))
    }
}

// MARK: - Needles

/// A task-level completion control labelled by `isDone` alone. The leading `[^A-Za-z0-9_.]` keeps it
/// off `subtask.isDone`, whose control genuinely owns done/todo and nothing else.
private let taskLevelDoneLabel = #"[^A-Za-z0-9_.]task\.isDone \? ""#

/// An assignment to a task's `status`, and not a comparison (`==`), a labelled argument
/// (`status: task.status`) or a pattern match.
private let directStatusAssignment = #"task\.status\s*=\s*[^=]"#

private let directCompletedAtAssignment = #"task\.completedAt\s*=\s*[^=]"#

// MARK: - Source-reading helpers

private extension String {
    func matchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
