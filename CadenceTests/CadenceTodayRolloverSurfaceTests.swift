import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-195: Today's rollover notice was macOS-only in three separate pieces — the `@AppStorage` key,
/// an inline visibility predicate on `TasksPanel`, and a withhold-while-showing method on
/// `TasksPanelDerivedState` — over a mutation that sat in `macOS/Services/` while importing nothing
/// platform-specific.
///
/// The decision is `CadenceTodayRolloverSupport` now and the mutation is
/// `CadenceTaskMutationSupport.rollOverTaskToToday`. These tests pin the decision directly, the
/// mutation against a real store, and — because `Cadence/iOS/` is inside `#if os(iOS)` and this
/// target builds for macOS — the iOS call sites by scanning source.
@Suite("Today rollover")
struct CadenceTodayRolloverSurfaceTests {

    // MARK: - The over-do bucket

    @Test func pastDoTasksAreOpenWorkPlannedForADayThatHasGoneBy() throws {
        let today = "2026-08-20"
        let planned = task(title: "Yesterday's plan", scheduled: "2026-08-19")
        let plannedToday = task(title: "Today's plan", scheduled: today)
        let plannedTomorrow = task(title: "Tomorrow", scheduled: "2026-08-21")
        let unplanned = task(title: "No date")

        let rolled = CadenceTodayRolloverSupport.pastDoTasks(
            from: [planned, plannedToday, plannedTomorrow, unplanned],
            todayKey: today
        )

        #expect(rolled.map(\.title) == ["Yesterday's plan"])
    }

    @Test func pastDoTasksExcludeSettledWork() throws {
        let today = "2026-08-20"
        let done = task(title: "Finished", scheduled: "2026-08-19")
        done.status = .done
        let cancelled = task(title: "Dropped", scheduled: "2026-08-19")
        cancelled.status = .cancelled
        // T-213's invariant: a cancellation keeps the timestamp it was given. It must not be what
        // decides whether the banner offers the task — status alone does.
        cancelled.completedAt = Date()
        let open = task(title: "Still open", scheduled: "2026-08-19")

        let rolled = CadenceTodayRolloverSupport.pastDoTasks(
            from: [done, cancelled, open],
            todayKey: today
        )

        #expect(rolled.map(\.title) == ["Still open"])
    }

    /// A due date outranks a do date everywhere on Today, so a task the Overdue or Due Today group
    /// already claims is not something the banner offers to reschedule.
    @Test func pastDoTasksYieldToADueDateClaim() throws {
        let today = "2026-08-20"
        let alsoOverdue = task(title: "Overdue", scheduled: "2026-08-19", due: "2026-08-18")
        let alsoDueToday = task(title: "Due today", scheduled: "2026-08-19", due: today)
        let dueLater = task(title: "Due later", scheduled: "2026-08-19", due: "2026-08-25")

        let rolled = CadenceTodayRolloverSupport.pastDoTasks(
            from: [alsoOverdue, alsoDueToday, dueLater],
            todayKey: today
        )

        #expect(rolled.map(\.title) == ["Due later"])
    }

    /// The same set `CadenceTaskQuerySupport.todayGroups` puts in `.pastDo`. If these two ever
    /// disagree the banner lists tasks the section below it does not, or the other way round.
    @Test func pastDoTasksMatchTheSharedTodayGroup() throws {
        let today = "2026-08-20"
        let tasks = [
            task(title: "Past do", scheduled: "2026-08-19"),
            task(title: "Overdue", due: "2026-08-18"),
            task(title: "Due today", due: today),
            task(title: "Planned today", scheduled: today),
            task(title: "Past do and due later", scheduled: "2026-08-01", due: "2026-09-01")
        ]

        let active = CadenceTaskQuerySupport.activeTodayTasks(from: tasks, todayKey: today, sortMode: .listOrder)
        let groupPastDo = CadenceTaskQuerySupport
            .todayGroups(from: active, todayKey: today)
            .first { $0.kind == .pastDo }?
            .tasks ?? []

        let bannerPastDo = CadenceTodayRolloverSupport.pastDoTasks(from: tasks, todayKey: today)

        #expect(Set(groupPastDo.map(\.id)) == Set(bannerPastDo.map(\.id)))
        #expect(bannerPastDo.count == 2)
    }

    /// Idempotent: the host may hand it the whole store or an already-Today-filtered array.
    @Test func pastDoTasksAreStableUnderRefiltering() throws {
        let today = "2026-08-20"
        let tasks = [
            task(title: "Past do", scheduled: "2026-08-19"),
            task(title: "Planned today", scheduled: today)
        ]
        let once = CadenceTodayRolloverSupport.pastDoTasks(from: tasks, todayKey: today)
        let twice = CadenceTodayRolloverSupport.pastDoTasks(from: once, todayKey: today)
        #expect(once.map(\.id) == twice.map(\.id))
    }

    // MARK: - Visibility

    @Test func noticeShowsOnlyWhenThereIsSomethingToRoll() {
        #expect(CadenceTodayRolloverSupport.isNoticeVisible(pastDoTaskCount: 2, dismissedDateKey: "", todayKey: "2026-08-20"))
        #expect(!CadenceTodayRolloverSupport.isNoticeVisible(pastDoTaskCount: 0, dismissedDateKey: "", todayKey: "2026-08-20"))
    }

    /// The dismissal is a day key, not a flag, which is what makes it expire overnight without
    /// anything having to clear it.
    @Test func dismissalExpiresWithTheDay() {
        #expect(!CadenceTodayRolloverSupport.isNoticeVisible(
            pastDoTaskCount: 3,
            dismissedDateKey: "2026-08-20",
            todayKey: "2026-08-20"
        ))
        #expect(CadenceTodayRolloverSupport.isNoticeVisible(
            pastDoTaskCount: 3,
            dismissedDateKey: "2026-08-19",
            todayKey: "2026-08-20"
        ))
    }

    // MARK: - Withholding

    @Test func theGroupedListWithholdsExactlyWhatTheBannerIsOffering() throws {
        let today = "2026-08-20"
        let pastDo = task(title: "Past do", scheduled: "2026-08-19")
        let plannedToday = task(title: "Planned today", scheduled: today)
        let all = [pastDo, plannedToday]

        let whileShowing = CadenceTodayRolloverSupport.groupedTasks(
            from: all,
            withholding: [pastDo],
            isNoticeVisible: true
        )
        #expect(whileShowing.map(\.title) == ["Planned today"])

        let afterDismiss = CadenceTodayRolloverSupport.groupedTasks(
            from: all,
            withholding: [pastDo],
            isNoticeVisible: false
        )
        #expect(afterDismiss.map(\.title) == ["Past do", "Planned today"])
    }

    // MARK: - The mutation

    @Test func rollingOverClearsTheSlotItLeaves() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Carry me")
        task.scheduledDate = "2026-08-19"
        task.scheduledStartMin = 540
        task.calendarEventID = "legacy-event-id"
        context.insert(task)

        CadenceTaskMutationSupport.rollOverTaskToToday(task, todayKey: "2026-08-20", modelContext: context)

        #expect(task.scheduledDate == "2026-08-20")
        #expect(task.scheduledStartMin == -1)
        #expect(task.calendarEventID.isEmpty)
    }

    /// A do date that was never a timed slot still moves, and the event field still ends empty —
    /// the clear is unconditional, not gated on `scheduledStartMin >= 0`.
    @Test func rollingOverAnUntimedTaskStillClearsAStaleEventLink() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Untimed")
        task.scheduledDate = "2026-08-19"
        task.scheduledStartMin = -1
        task.calendarEventID = "legacy-event-id"
        context.insert(task)

        CadenceTaskMutationSupport.rollOverTaskToToday(task, todayKey: "2026-08-20", modelContext: context)

        #expect(task.calendarEventID.isEmpty)
        #expect(task.scheduledDate == "2026-08-20")
    }

    @Test func rollingOverTheLastActiveMemberRemovesTheBlockItLeaves() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Carry me")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-08-19", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        CadenceTaskMutationSupport.addTask(task, to: bundle, modelContext: context)

        CadenceTaskMutationSupport.rollOverTaskToToday(task, todayKey: "2026-08-20", modelContext: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-08-20")
        #expect(task.scheduledStartMin == -1)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func rollingOverOneMemberLeavesABlockThatStillHasActiveWork() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "Carry me")
        let second = AppTask(title: "Stay bundled")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-08-19", startMin: 600, durationMinutes: 30)
        [first, second].forEach(context.insert)
        context.insert(bundle)
        [first, second].forEach { CadenceTaskMutationSupport.addTask($0, to: bundle, modelContext: context) }

        CadenceTaskMutationSupport.rollOverTaskToToday(first, todayKey: "2026-08-20", modelContext: context)

        #expect(first.bundle == nil)
        #expect(second.bundle?.id == bundle.id)
        #expect(bundle.sortedTasks.map(\.id) == [second.id])
        #expect(second.bundleOrder == 0)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).map(\.id) == [bundle.id])
    }

    @Test func rollingOverABatchReturnsTheDayKeyToStoreAsDismissed() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = ["One", "Two"].map { title -> AppTask in
            let task = AppTask(title: title)
            task.scheduledDate = "2026-08-19"
            context.insert(task)
            return task
        }

        let dismissed = CadenceTodayRolloverSupport.rollOver(tasks, todayKey: "2026-08-20", modelContext: context)

        #expect(dismissed == "2026-08-20")
        #expect(tasks.allSatisfy { $0.scheduledDate == "2026-08-20" })
        // The roll is what makes the notice go away; nothing about it settles a task.
        #expect(tasks.allSatisfy { !$0.isDone && !$0.isCancelled })
        #expect(CadenceTodayRolloverSupport.pastDoTasks(from: tasks, todayKey: "2026-08-20").isEmpty)
    }

    /// The Mac spelling delegates. T-190's lesson: a `Shared/`-shaped mutation with a second body
    /// behind a platform guard is the whole defect this ticket was about.
    @Test func theMacSpellingDelegatesToTheSharedMutation() throws {
        let source = try strippingComments(sourceFile("Cadence/macOS/Services/SchedulingService.swift"))
        #expect(source.contains("CadenceTaskMutationSupport.rollOverTaskToToday("))
        // The body that used to be here, gone: no re-spelling of the block/slot clearing.
        #expect(!source.contains("cleanupInactiveBundleIfNeeded"))
    }

    // MARK: - Call-site wiring (source-scanned; `Cadence/iOS/` is invisible to this target)

    @Test func iOSTodayReadsTheSharedRolloverDecision() throws {
        let host = try strippingComments(sourceFile("Cadence/iOS/iPadTodayView.swift"))
        #expect(host.contains("CadenceTodayRolloverSupport.pastDoTasks("))
        #expect(host.contains("CadenceTodayRolloverSupport.isNoticeVisible("))
        #expect(host.contains("CadenceTodayRolloverSupport.groupedTasks("))
        #expect(host.contains("CadenceTodayRolloverSupport.rollOver("))
        #expect(host.contains("CadenceTodayRolloverSupport.dismissedDateStorageKey"))
    }

    /// Both widths draw the banner because both draw `iOSTodayTaskSections` — the one list. If the
    /// banner ever moves into a host, this is the assertion that has to be reconsidered rather than
    /// quietly satisfied by a second copy.
    @Test func iOSTodayDrawsTheSharedBannerFromTheOneList() throws {
        let list = try strippingComments(sourceFile("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(list.contains("CadenceTodayRolloverBanner("))
        #expect(list.contains("rolloverNotice"))

        for host in ["Cadence/iOS/iPadTodayView.swift", "Cadence/iOS/iPadTodayCompactViews.swift"] {
            let source = try strippingComments(sourceFile(host))
            #expect(source.contains("rolloverNotice"), "\(host) does not pass the notice through")
            #expect(
                !source.contains("CadenceTodayRolloverBanner("),
                "\(host) draws its own banner instead of going through iOSTodayTaskSections"
            )
        }
    }

    @Test func macOSTodayDrawsTheSameSharedBanner() throws {
        let panel = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(panel.contains("CadenceTodayRolloverBanner(tasks: derived.overdoTasks, style: .panelBand)"))
        #expect(panel.contains("CadenceTodayRolloverSupport.isNoticeVisible("))
        #expect(panel.contains("CadenceTodayRolloverSupport.rollOver("))
        #expect(panel.contains("CadenceTodayRolloverSupport.dismissedDateStorageKey"))
    }

    /// One key and one set of strings. A second literal anywhere is how the phone would re-offer a
    /// roll the Mac had already done, or describe the same offer in different words.
    @Test func neitherPlatformRespellsTheKeyOrTheCopy() throws {
        let owner = "Cadence/Shared/CadenceTodayRolloverSupport.swift"
        let literals = [
            "\"todayRolloverNoticeDismissedDate\"",
            "\"Leftover tasks are rolling over to today\"",
            "\"Roll Over\""
        ]
        var scanned = 0
        for path in try swiftFiles(under: "Cadence") where path != owner {
            let source = try strippingComments(sourceFile(path))
            scanned += 1
            for literal in literals {
                #expect(!source.contains(literal), "\(path) re-spells \(literal)")
            }
        }
        // Non-vacuity: the sweep really read the tree, and the owner really holds the literals.
        #expect(scanned > 300, "only \(scanned) files scanned — the enumerator read nothing")
        let ownerSource = try strippingComments(sourceFile(owner))
        for literal in literals {
            #expect(ownerSource.contains(literal), "\(owner) no longer declares \(literal)")
        }
    }

    /// The comment stripper is load-bearing above — several of these files explain the rollover in
    /// prose that names the very strings being banned.
    @Test func theCommentStripperStrips() throws {
        let stripped = try strippingComments("let a = 1 // \"Roll Over\"\n/* \"Roll Over\" */ let b = 2\n")
        #expect(!stripped.contains("Roll Over"))
        #expect(stripped.contains("let a = 1"))
        #expect(stripped.contains("let b = 2"))
    }

    // MARK: - macOS behaviour preservation

    /// Rewiring `TasksPanelDerivedState` to the shared predicate is a refactor of a **live**
    /// surface, so this recomputes the two values it changed with the *old* inline expressions and
    /// asserts the new ones are identical — order included, because both feed a sort whose
    /// tie-break is total and a reordering would be visible.
    @Test func theMacDerivedStateStillDerivesExactlyWhatItUsedTo() throws {
        let today = "2026-08-20"
        let allTasks = [
            task(title: "Past do", scheduled: "2026-08-19"),
            task(title: "Past do, older", scheduled: "2026-08-01"),
            task(title: "Overdue", due: "2026-08-18"),
            task(title: "Overdue and past do", scheduled: "2026-08-17", due: "2026-08-18"),
            task(title: "Due today", due: today),
            task(title: "Due today, planned yesterday", scheduled: "2026-08-19", due: today),
            task(title: "Planned today", scheduled: today),
            task(title: "Planned tomorrow", scheduled: "2026-08-21"),
            task(title: "No dates")
        ]
        let settled = task(title: "Finished yesterday", scheduled: "2026-08-19")
        settled.status = .done
        let cancelled = task(title: "Cancelled yesterday", scheduled: "2026-08-19")
        cancelled.status = .cancelled
        cancelled.completedAt = Date()
        let tasks = allTasks + [settled, cancelled]

        let derived = TasksPanelDerivedState(
            allTasks: tasks,
            areas: [],
            projects: [],
            mode: .todayOverview,
            todayKey: today,
            sortField: .date,
            sortDirection: .ascending
        )

        // The expression that used to be inline in `TasksPanelDerivedState.init`, verbatim.
        let legacyOverdue = tasks.filter { !$0.isDone && !$0.isCancelled && !$0.dueDate.isEmpty && $0.dueDate < today }
        let legacyDueToday = tasks.filter { !$0.isDone && !$0.isCancelled && $0.dueDate == today }
        let legacyExclusions = Set(legacyOverdue.map(\.id)).union(legacyDueToday.map(\.id))
        let legacyOverdo = tasks.filter {
            !$0.isDone &&
            !$0.isCancelled &&
            !$0.scheduledDate.isEmpty &&
            $0.scheduledDate < today &&
            !legacyExclusions.contains($0.id)
        }

        #expect(derived.overdoTasks.map(\.id) == legacyOverdo.map(\.id))
        #expect(!legacyOverdo.isEmpty, "fixture no longer exercises the over-do bucket")

        // And the expression that used to be inline in `todayGroupedTaskItems`, verbatim.
        func legacyGrouped(showRolloverNotice: Bool) -> [AppTask] {
            let legacyDoToday = tasks.filter {
                !$0.isDone && !$0.isCancelled && $0.scheduledDate == today && !legacyExclusions.contains($0.id)
            }
            let combined = showRolloverNotice
                ? (legacyOverdue + legacyDueToday + legacyDoToday)
                : (legacyOverdue + legacyOverdo + legacyDueToday + legacyDoToday)
            var seen = Set<UUID>()
            return combined.filter { seen.insert($0.id).inserted }
        }

        #expect(Set(derived.todayGroupedTaskItems(showRolloverNotice: true).map(\.id))
                == Set(legacyGrouped(showRolloverNotice: true).map(\.id)))
        #expect(Set(derived.todayGroupedTaskItems(showRolloverNotice: false).map(\.id))
                == Set(legacyGrouped(showRolloverNotice: false).map(\.id)))
        #expect(derived.todayGroupedTaskItems(showRolloverNotice: true).count
                == derived.todayGroupedTaskItems(showRolloverNotice: false).count - legacyOverdo.count)
    }

    // MARK: - Fixtures

    private func task(title: String, scheduled: String = "", due: String = "") -> AppTask {
        let task = AppTask(title: title)
        task.scheduledDate = scheduled
        task.dueDate = due
        return task
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
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

private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
