import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-147: a cancelled task was unreachable. The decision was **show them in Completed**, struck
/// through rather than in the green done treatment.
///
/// The bug was a *pair* of filters that did not partition the set. The active lists asked
/// `!isDone && !isCancelled` and the Completed lists asked `isDone && !isCancelled` — and a
/// cancelled task satisfies neither, so it fell out of every list in the app. On iOS, where the
/// inspector's Cancel button, the swipe tray and the row's context menu can all produce that
/// status, cancelling was deleting without saying so.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning `isFinishedTask` proves
/// the predicate is right and proves nothing about anybody using it: T-161 is the standing example
/// of a committed fix reverted with the whole suite green because the tests pinned a helper while
/// nothing observed the call sites. So the behavioural tests below run the real queries, and the
/// source-scanning tests read the real files with exact per-file counts. The iOS half has no other
/// option — `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS —
/// which is why `iOSTaskRow`'s share is asserted as source text and `theSourceScanIsNotVacuous`
/// exists to stop a broken reader making the absence assertions pass silently.
@MainActor
struct CadenceCancelledTaskReachabilityTests {

    private let todayKey = "2026-08-20"

    private func task(
        _ title: String,
        status: TaskStatus = .todo,
        doDate: String = "",
        dueDate: String = "",
        area: Area? = nil,
        completedAt: Date? = nil
    ) -> AppTask {
        let task = AppTask(title: title)
        task.status = status
        task.scheduledDate = doDate
        task.dueDate = dueDate
        task.area = area
        task.completedAt = completedAt
        return task
    }

    // MARK: - The predicate

    /// "Over, however it ended." Both settled statuses, neither open one.
    @Test func finishedMeansDoneOrCancelled() {
        #expect(CadenceTaskQuerySupport.isFinishedTask(task("d", status: .done)))
        #expect(CadenceTaskQuerySupport.isFinishedTask(task("c", status: .cancelled)))
        #expect(!CadenceTaskQuerySupport.isFinishedTask(task("t", status: .todo)))
        #expect(!CadenceTaskQuerySupport.isFinishedTask(task("p", status: .inProgress)))
    }

    /// The whole bug, stated as a property: open and finished must **partition** every status, so
    /// no task can be in neither list. `.inProgress` is the reminder that the status set has grown
    /// before and can grow again.
    @Test func openAndFinishedPartitionEveryStatus() {
        for status in TaskStatus.allCases {
            let subject = task("t", status: status)
            let isOpen = CadenceTaskQuerySupport.openTasks(from: [subject]).count == 1
            let isFinished = CadenceTaskQuerySupport.isFinishedTask(subject)
            #expect(isOpen != isFinished, "\(status.rawValue) is in \(isOpen && isFinished ? "both" : "neither") half")
        }
    }

    // MARK: - The three completed queries

    @Test func aCancelledTaskIsReturnedByTheCompletedListQueryAndNotTheActiveOne() {
        let cancelled = task("cancelled", status: .cancelled)
        let open = task("open")
        let done = task("done", status: .done)
        let all = [cancelled, open, done]

        #expect(
            CadenceTaskQuerySupport.completedTasks(from: all).map(\.title).sorted()
                == ["cancelled", "done"]
        )
        #expect(
            CadenceTaskQuerySupport.activeTasks(from: all, sortMode: .listOrder).map(\.title)
                == ["open"]
        )
    }

    @Test func aCancelledInboxTaskIsReturnedByTheCompletedInboxQuery() {
        let area = Area(name: "Filed")
        let cancelledInbox = task("cancelled-inbox", status: .cancelled)
        let cancelledFiled = task("cancelled-filed", status: .cancelled, area: area)
        let all = [cancelledInbox, cancelledFiled, task("open")]

        #expect(
            CadenceTaskQuerySupport.completedInboxTasks(from: all).map(\.title) == ["cancelled-inbox"]
        )
        #expect(
            CadenceTaskQuerySupport.activeInboxTasks(from: all, sortMode: .listOrder).map(\.title)
                == ["open"]
        )
    }

    /// Today's Completed section admits a cancelled task on the same three grounds a done one gets
    /// in: planned today, due today, or settled today.
    @Test func aCancelledTaskReachesTodaysCompletedSection() {
        let planned = task("planned", status: .cancelled, doDate: todayKey)
        let due = task("due", status: .cancelled, dueDate: todayKey)
        let settled = task(
            "settled",
            status: .cancelled,
            completedAt: DateFormatters.date(from: todayKey)
        )
        let elsewhere = task("elsewhere", status: .cancelled, doDate: "2026-08-01")
        let all = [planned, due, settled, elsewhere]

        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: all, todayKey: todayKey)
                .map(\.title).sorted() == ["due", "planned", "settled"]
        )
        #expect(
            CadenceTaskQuerySupport.activeTodayTasks(from: all, todayKey: todayKey, sortMode: .listOrder)
                .isEmpty
        )
    }

    /// The upstream filter that was defeating the downstream one. `inboxTasks` is the whole Inbox
    /// universe `TasksListView` then splits in two; while it dropped cancelled work, macOS's Inbox
    /// hid it and macOS's All Tasks — which scopes with `isInActiveContainer` instead — showed it.
    @Test func theInboxUniverseCarriesCancelledWorkThroughToItsCompletedHalf() {
        let all = [task("cancelled", status: .cancelled), task("open"), task("done", status: .done)]
        let universe = CadenceTaskQuerySupport.inboxTasks(from: all)

        #expect(universe.count == 3)
        #expect(universe.filter { CadenceTaskQuerySupport.isFinishedTask($0) }.map(\.title).sorted()
            == ["cancelled", "done"])
    }

    /// …and no badge moved. Both `inboxTasks` callers re-filter to open work, so widening the
    /// universe must not change a count.
    @Test func wideningTheInboxUniverseDidNotChangeAnyOpenCount() {
        let all = [task("cancelled", status: .cancelled), task("open"), task("done", status: .done)]

        #expect(CadenceTaskQuerySupport.openTaskCount(from: CadenceTaskQuerySupport.inboxTasks(from: all)) == 1)
        #expect(CadenceTaskQuerySupport.openInboxTaskCount(from: all) == 1)
    }

    // MARK: - Deliberately unchanged

    /// `completedTaskCount` backs the "N done" summary and the Settings Completed tile. That is a
    /// count of work *finished*, and a cancellation is not an accomplishment — reachability is what
    /// a Completed section owes you, not credit.
    @Test func theDoneCountStillCountsOnlyDoneWork() {
        let all = [task("cancelled", status: .cancelled), task("done", status: .done), task("open")]

        #expect(CadenceTaskQuerySupport.completedTaskCount(from: all) == 1)
    }

    /// Every active list keeps excluding cancelled work — that half was never the bug.
    @Test func theActiveFiltersStillExcludeCancelledWork() {
        let all = [task("cancelled", status: .cancelled, doDate: todayKey, dueDate: todayKey)]

        #expect(CadenceTaskQuerySupport.openTasks(from: all).isEmpty)
        #expect(CadenceTaskQuerySupport.activeTasks(from: all, sortMode: .listOrder).isEmpty)
        #expect(CadenceTaskQuerySupport.activeInboxTasks(from: all, sortMode: .listOrder).isEmpty)
        #expect(CadenceTaskQuerySupport.activeTodayTasks(from: all, todayKey: todayKey, sortMode: .listOrder).isEmpty)
    }

    /// A cancelled task holds no timeline slot and is on no rail, and is not work you are late on.
    /// Three judgements this ticket deliberately left alone, pinned so the next sweep past
    /// `isCancelled` does not take them with it.
    ///
    /// The rail/day-column half is `CalendarBoardPlannerSupport`, declared in a file called
    /// `CadenceCalendarPlanningSupport.swift` — the name mismatch `Cadence/Shared/AGENTS.md` warns
    /// about, and the reason this test failed to compile the first time.
    @Test func aCancelledTaskIsStillOffTheScheduleTheRailsAndTheOverdueCount() {
        let scheduled = task("cancelled", status: .cancelled, doDate: todayKey, dueDate: "2026-08-01")
        scheduled.scheduledStartMin = 540

        #expect(
            CadenceScheduleSupport.scheduledTasks(
                on: todayKey,
                from: [scheduled],
                includeCompleted: true,
                excludeBundled: true
            ).isEmpty
        )
        #expect(CalendarBoardPlannerSupport.railTasks(from: [scheduled], todayKey: todayKey).isEmpty)
        #expect(CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: [scheduled]).isEmpty)
        #expect(CadenceSidebarLayout.overdueTaskCount(from: [scheduled], todayKey: todayKey) == 0)
    }

    // MARK: - The row must not read as done

    /// Strikethrough, dim, a cross — and never `Theme.doneFill`. Both platforms resolve the row's
    /// circle through this one decision, so the ring and the title cannot disagree.
    @Test func aCancelledRowIsSettledWithoutBeingGreen() {
        let cancelled = CadenceTaskCompletionGlyph.resolve(status: .cancelled, priority: .high)
        let done = CadenceTaskCompletionGlyph.resolve(status: .done, priority: .high)

        #expect(CadenceTaskCompletionState.resolve(status: .cancelled).isSettled)
        #expect(CadenceTaskCompletionState.resolve(status: .done).isSettled)
        #expect(!CadenceTaskCompletionState.resolve(status: .todo).isSettled)

        #expect(cancelled.mark == .cross)
        #expect(cancelled.isFilled)
        #expect(cancelled.tint == Theme.dim)
        #expect(cancelled.tint != Theme.doneFill)
        #expect(done.tint == Theme.doneFill)
        #expect(cancelled.symbolName != done.symbolName)
    }

    // MARK: - Call sites

    /// The predicate is only worth one place if the three completed queries actually read it, and
    /// only three of the six filters in that file may still mention `isCancelled` — the active ones.
    @Test func theCompletedQueriesAllReadTheOnePredicate() throws {
        try expectOccurrences(
            of: "isFinishedTask(",
            at: [
                "Cadence/Shared/CadenceTaskQuerySupport.swift": 3,
                "Cadence/Shared/CadenceTaskQuerySharedSupport.swift": 2
            ]
        )
        try expectOccurrences(
            of: "isCancelled",
            at: [
                // activeTodayTasks, activeInboxTasks, activeTasks — and nothing else.
                "Cadence/Shared/CadenceTaskQuerySupport.swift": 3,
                // openTasks, isFinishedTask, isOpenTask. `inboxTasks` is no longer one of them.
                "Cadence/Shared/CadenceTaskQuerySharedSupport.swift": 3
            ]
        )
        // The three retired spellings, each chosen so it cannot also match the *active* filter it
        // sits beside — `"$0.isDone && !$0.isCancelled }"` is a substring of
        // `"!$0.isDone && !$0.isCancelled }"`, which is how a first draft of this test failed
        // against correct code.
        for retired in ["guard task.isDone", ".filter { $0.isDone", "&& $0.isDone && !"] {
            try expectOccurrences(
                of: retired,
                at: ["Cadence/Shared/CadenceTaskQuerySupport.swift": 0]
            )
        }
    }

    /// `iOSTaskRow` struck through on `task.isDone` alone, so a cancelled row drew a dim cross in
    /// its circle beside a full-contrast, un-struck title. It reads the shared settled state now —
    /// which is also what resolved that circle — and mentions `isCancelled` nowhere itself.
    ///
    /// The three surviving `task.isDone` mentions are the accessibility label, the over-do test and
    /// the due-urgency call, each of which correctly asks about *done* specifically.
    @Test func theIOSRowAndTheInspectorTitleBothReadTheSharedSettledState() throws {
        try expectOccurrences(
            of: "isSettled",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 5,
                "Cadence/iOS/iOSTaskDetailComponents.swift": 4
            ]
        )
        try expectOccurrences(
            of: "CadenceTaskCompletionState.resolve(task: task).isSettled",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSTaskDetailComponents.swift": 1
            ]
        )
        try expectOccurrences(
            of: "strikethrough(task.isDone",
            at: ["Cadence/iOS/iOSTaskViews.swift": 0]
        )
        try expectOccurrences(
            of: "task.isDone || task.isCancelled",
            at: ["Cadence/iOS/iOSTaskDetailComponents.swift": 0]
        )
        try expectOccurrences(
            of: "task.isDone",
            at: ["Cadence/iOS/iOSTaskViews.swift": 3]
        )
    }

    /// macOS's row has spelled the settled test `isDone || isCancelled` all along, in three places
    /// in one file. It is left as it is on purpose — but if it ever loses that spelling, the two
    /// platforms are disagreeing about a cancelled row again.
    @Test func theMacRowStillTreatsCancelledAsSettled() throws {
        try expectOccurrences(
            of: "isDone || task.isCancelled",
            at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 3]
        )
    }

    /// Without this, every zero above could be a scan reading an empty string — the exact failure
    /// mode a `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuous() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Shared/CadenceTaskQuerySupport.swift"))
        #expect(files.contains("Cadence/Shared/CadenceTaskQuerySharedSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskDetailComponents.swift"))
        #expect(files.contains("Cadence/macOS/Views/TasksPanelComponents.swift"))

        let queries = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskQuerySharedSupport.swift"))
        #expect(queries.contains("static func isFinishedTask"))

        let row = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        #expect(row.contains("struct iOSTaskRow: View"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
///
/// Exact counts, not "contains": a mutation run against `CadenceSharedBoardChromeTests` caught a
/// version asserting only that each file mentioned the shared decision somewhere, and reverting one
/// of four call sites left it green.
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

/// Blanks `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
