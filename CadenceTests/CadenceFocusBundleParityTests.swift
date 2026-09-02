import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-242: focusing a `TaskBundle` was macOS-only. The picker row model (`FocusPickItem`), the
/// minute distribution (`FocusSessionSupport.distributeBundleMinutes`) and the member selection all
/// sat inside `#if os(macOS)`, in files whose only platform dependency was the views around them —
/// the sixth instance of the shape `RemindersManager`, `PrivacyDataResetService`, `ListDeleteHelpers`
/// and T-190's bundle-forming gesture already had.
///
/// `FocusManager` itself is **not** the thing that needed lifting and is deliberately still
/// macOS-only: iOS's focus screen has never used it. It holds its stopwatch in
/// `CadenceFocusTimerState`, which was already shared, so un-guarding the singleton would have given
/// the phone a second timer authority rather than a feature.
///
/// **Two kinds of test here.** The behavioural half runs the real shared logic. The source half pins
/// that iOS *reaches* it: `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for
/// macOS, so there is no iOS symbol to reference and a source scan is the only tool. Per T-161 the
/// wiring is what gets pinned, not just the helper — a shared helper with no call site is the defect
/// this ticket describes, not the fix.
@MainActor
struct CadenceFocusBundleParityTests {

    // MARK: - Fixtures

    private func bundle(
        _ title: String,
        dateKey: String = "2026-08-22",
        startMin: Int = 540,
        estimates: [Int]
    ) -> TaskBundle {
        let bundle = TaskBundle(title: title, dateKey: dateKey, startMin: startMin, durationMinutes: 30)
        var members: [AppTask] = []
        for (index, estimate) in estimates.enumerated() {
            let task = AppTask(title: "\(title) \(index + 1)")
            task.estimatedMinutes = estimate
            task.bundleOrder = index
            task.bundle = bundle
            members.append(task)
        }
        bundle.tasks = members
        return bundle
    }

    private func timerState(elapsedSeconds: Int) -> CadenceFocusTimerState {
        var state = CadenceFocusTimerState()
        state.accumulatedSeconds = elapsedSeconds
        return state
    }

    // MARK: - The shared distribution

    /// The whole stopwatch reading is handed out — no minute is lost to independently rounded
    /// shares — and it is weighted by estimate, so the 45-minute member of a 60-minute block gets
    /// three quarters of the session rather than half of it.
    @Test func aBundleSessionSplitsItsMinutesByEstimateAndLosesNoneOfThem() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let block = bundle("Sweep", estimates: [45, 15])
        let members = block.sortedTasks

        CadenceFocusSupport.distributeMinutes(60, across: members, in: context)

        #expect(members.map(\.actualMinutes) == [45, 15])
        #expect(members.reduce(0) { $0 + $1.actualMinutes } == 60)
    }

    /// The remainder lands on the last member rather than evaporating. Three equal members over
    /// 100 minutes is 33.33…, and three independently rounded 33s would log 99 minutes of a
    /// 100-minute session.
    @Test func theLastMemberAbsorbsTheRemainderSoTheTotalIsExact() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let block = bundle("Uneven", estimates: [10, 10, 10])
        let members = block.sortedTasks

        CadenceFocusSupport.distributeMinutes(100, across: members, in: context)

        #expect(members.reduce(0) { $0 + $1.actualMinutes } == 100)
        #expect(members.map(\.actualMinutes) == [33, 33, 34])
    }

    /// The minutes roll up into the member's list, which is what an hours-mode goal reads. A
    /// distribution that moved `actualMinutes` alone would leave a block's work invisible to every
    /// goal that measures in hours.
    @Test func distributedMinutesRollUpIntoEachMembersList() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Ledger")
        let area = Area(name: "Admin")
        let block = bundle("Rollup", estimates: [30, 30])
        let members = block.sortedTasks
        members[0].project = project
        members[1].area = area
        context.insert(project)
        context.insert(area)
        context.insert(block)
        for member in members { context.insert(member) }

        CadenceFocusSupport.distributeMinutes(40, across: members, in: context)

        #expect(project.loggedMinutes == 20)
        #expect(area.loggedMinutes == 20)
    }

    /// Seconds become minutes through `minutes(fromElapsedSeconds:)` — the one definition of what a
    /// stopwatch reading is worth — so the same clock logs the same number whether the subject is a
    /// task or a block. A second rounding rule here is exactly the divergence the focus audit found
    /// between the timer and the log-session sheets.
    @Test func aBundleStopwatchRoundsTheSameWayASingleTaskStopwatchDoes() throws {
        let context = ModelContext(try CadenceTestStore.container())
        for seconds in [0, 20, 61, 90, 3_660] {
            let block = bundle("Rounding", estimates: [30])
            let single = AppTask(title: "Alone")

            CadenceFocusSupport.logElapsedSeconds(seconds, across: block.sortedTasks, in: context)
            CadenceFocusSupport.logElapsedSeconds(seconds, to: single, in: context)

            #expect(block.sortedTasks[0].actualMinutes == single.actualMinutes)
            #expect(single.actualMinutes == CadenceFocusSupport.minutes(fromElapsedSeconds: seconds))
        }
    }

    // MARK: - The member selection

    /// Every member is ticked when a block session starts, because a block you sat down to work
    /// through is presumed to be the work. Unticking is the exception and is what takes a tap.
    @Test func aBundleSessionStartsWithEveryMemberTicked() {
        let block = bundle("Sweep", estimates: [10, 20, 30])

        #expect(
            CadenceFocusSupport.defaultSelectedTaskIDs(for: block)
                == Set(block.sortedTasks.map(\.id))
        )
    }

    /// The selection resolves by filtering the bundle, not by mapping the id set: that keeps bundle
    /// order — which is the order the minutes are weighted in — and silently drops an id belonging
    /// to a task that has since left the block.
    @Test func resolvingTheSelectionKeepsBundleOrderAndDropsStrayIDs() {
        let block = bundle("Order", estimates: [10, 20, 30])
        let members = block.sortedTasks
        let selection: Set<UUID> = [members[2].id, members[0].id, UUID()]

        let resolved = CadenceFocusSupport.selectedTasks(in: block, selectedTaskIDs: selection)

        #expect(resolved.map(\.title) == [members[0].title, members[2].title])
    }

    /// Unticking a member excludes it from the time log, which is the only thing the ticks do.
    @Test func onlyTickedMembersReceiveTheSessionsTime() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let block = bundle("Partial", estimates: [30, 30])
        let members = block.sortedTasks

        CadenceFocusSupport.logElapsedSeconds(
            30 * 60,
            across: CadenceFocusSupport.selectedTasks(in: block, selectedTaskIDs: [members[0].id]),
            in: context
        )

        #expect(members[0].actualMinutes == 30)
        #expect(members[1].actualMinutes == 0)
    }

    // MARK: - Leaving a session

    /// Leaving a block banks its seconds against the members that were ticked while it ran, and
    /// hands the next subject a clock at zero. The task-shaped `commitElapsed` could not express
    /// this at all — it took an `AppTask?` — which is why iOS could not have run a block's timer
    /// even with a picker that offered one.
    @Test func leavingABundleBanksItsMinutesAgainstTheTickedMembers() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let block = bundle("Admin sweep", estimates: [10, 10])
        let members = block.sortedTasks
        let next = AppTask(title: "Something else")
        context.insert(block)
        for member in members { context.insert(member) }
        context.insert(next)

        let after = CadenceFocusSupport.commitElapsed(
            leaving: .bundle(block, selectedTaskIDs: [members[0].id]),
            switchingTo: .task(next.id),
            state: timerState(elapsedSeconds: 20 * 60),
            modelContext: context
        )

        #expect(members[0].actualMinutes == 20)
        #expect(members[1].actualMinutes == 0)
        #expect(after.elapsedSeconds() == 0)
        #expect(after.isRunning == false)
    }

    /// A bundle and one of its own members are different sessions. Comparing bare `UUID`s could
    /// never say that; comparing targets does, so switching from a block to a task inside it still
    /// banks the block's time.
    @Test func aBundleAndItsOwnMemberAreDifferentSessions() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let block = bundle("Sweep", estimates: [10, 10])
        let members = block.sortedTasks
        context.insert(block)
        for member in members { context.insert(member) }

        let after = CadenceFocusSupport.commitElapsed(
            leaving: .bundle(block, selectedTaskIDs: Set(members.map(\.id))),
            switchingTo: .task(members[0].id),
            state: timerState(elapsedSeconds: 30 * 60),
            modelContext: context
        )

        #expect(members.reduce(0) { $0 + $1.actualMinutes } == 30)
        #expect(after.elapsedSeconds() == 0)
    }

    /// Re-selecting the session already running is not leaving it, so the clock keeps counting and
    /// nothing is written. Tapping your own row is how a user checks what is focused.
    @Test func reselectingTheRunningBundleLeavesTheClockAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let block = bundle("Sweep", estimates: [10, 10])
        context.insert(block)
        for member in block.sortedTasks { context.insert(member) }

        let after = CadenceFocusSupport.commitElapsed(
            leaving: .bundle(block, selectedTaskIDs: CadenceFocusSupport.defaultSelectedTaskIDs(for: block)),
            switchingTo: .bundle(block.id),
            state: timerState(elapsedSeconds: 12 * 60),
            modelContext: context
        )

        #expect(after.elapsedSeconds() == 12 * 60)
        #expect(block.sortedTasks.allSatisfy { $0.actualMinutes == 0 })
    }

    /// The play control on a *different* row starts that subject from zero rather than inheriting
    /// the elapsed count, and the rule is now stated against targets so a bundle row behaves like a
    /// task row. On the row already focused it is a plain toggle.
    @Test func theTransportControlResetsAcrossSubjectsAndTogglesOnItsOwn() {
        let taskID = UUID()
        let bundleID = UUID()
        var running = CadenceFocusTimerState()
        running.accumulatedSeconds = 600

        let switched = CadenceFocusSupport.timerState(
            afterPlayTapOn: .bundle(bundleID),
            selectedTarget: .task(taskID),
            state: running
        )
        #expect(switched.isRunning)
        #expect(switched.accumulatedSeconds == 0)

        let toggled = CadenceFocusSupport.timerState(
            afterPlayTapOn: .bundle(bundleID),
            selectedTarget: .bundle(bundleID),
            state: running
        )
        #expect(toggled.isRunning)
        #expect(toggled.accumulatedSeconds == 600)
    }

    // MARK: - The picker

    /// The unfiltered cap is a decision the caller makes, not a constant baked into the model.
    /// macOS caps at 18 because you can type past the cap; iOS's picker has no search field, so it
    /// passes `nil` and a nineteenth ready session stays reachable instead of being silently hidden.
    @Test func theUnfilteredCapIsOptionalSoASurfaceWithNoSearchFieldCanShowEverything() {
        let tasks = (0..<25).map { AppTask(title: "Task \($0)") }

        let capped = CadenceFocusPickItem.filtered(tasks: tasks, bundles: [], query: "", todayKey: "2026-08-22")
        let uncapped = CadenceFocusPickItem.filtered(
            tasks: tasks,
            bundles: [],
            query: "",
            todayKey: "2026-08-22",
            limit: nil
        )

        #expect(capped.count == CadenceFocusPickItem.defaultUnfilteredLimit)
        #expect(uncapped.count == 25)
    }

    /// A block with nothing left to do is not something to sit down to, and neither is an empty one.
    @Test func thePickerOffersOnlyBlocksThereIsStillWorkIn() {
        let live = bundle("Live", estimates: [30])
        let finished = bundle("Finished", estimates: [30])
        finished.sortedTasks.forEach { $0.status = .done }
        let empty = TaskBundle(title: "Empty", dateKey: "2026-08-22", startMin: 540, durationMinutes: 30)

        let items = CadenceFocusPickItem.filtered(
            tasks: [],
            bundles: [live, finished, empty],
            query: "",
            todayKey: "2026-08-22"
        )

        #expect(items.map(\.id) == ["bundle-\(live.id.uuidString)"])
    }

    /// A pick item knows what session it is, which is what lets one row struct draw both kinds and
    /// one commit path leave either.
    @Test func aPickItemNamesItsOwnTarget() {
        let task = AppTask(title: "Alone")
        let block = bundle("Sweep", estimates: [30])

        #expect(CadenceFocusPickItem.task(task).target == .task(task.id))
        #expect(CadenceFocusPickItem.bundle(block).target == .bundle(block.id))
        #expect(CadenceFocusTarget.task(task.id) != .bundle(task.id))
    }

    /// One sentence about a block, one definition of it. macOS spelled this inline in
    /// `FocusPickItemRow.bundleDetail`; the phone's row needed the same facts in the same order and
    /// a second hand-written copy is the near-copy the bundle *member* row already had to be
    /// rescued from.
    @Test func aBundleDescribesItselfTheSameWayOnBothPlatforms() {
        let block = bundle("Admin sweep", dateKey: "2026-08-22", startMin: 540, estimates: [30, 25])

        let line = CadenceFocusBundlePresentation.summaryLine(for: block, todayKey: "2026-08-22")

        #expect(line.hasPrefix("Bundle / 2 tasks / Today / "))
        #expect(line.hasSuffix("55m tasks"))
        // The chip strip under a block's own title drops the leading "Bundle" label: the title is
        // already one, and a chip repeating it says nothing the screen does not.
        #expect(
            CadenceFocusBundlePresentation.summaryParts(for: block, todayKey: "2026-08-22").first == "Bundle"
        )
    }

    @Test func theSelectionSummaryStatesWhatUntickingCosts() {
        let block = bundle("Sweep", estimates: [10, 10, 10])
        let members = block.sortedTasks

        #expect(
            CadenceFocusBundlePresentation.selectionSummary(
                for: block,
                selectedTaskIDs: Set(members.map(\.id))
            ) == "3 of 3 tasks receive this session's time."
        )
        #expect(
            CadenceFocusBundlePresentation.selectionSummary(for: block, selectedTaskIDs: [members[0].id])
                == "1 of 3 tasks receive this session's time."
        )
        #expect(
            CadenceFocusBundlePresentation.selectionSummary(for: block, selectedTaskIDs: [])
                == "No tasks will receive this session's time."
        )
    }

    // MARK: - The Mac still runs through the same code

#if os(macOS)
    /// The Mac's spelling stays — the log-session popovers read better in `FocusSessionSupport`'s
    /// vocabulary — but it must forward rather than keep a body, or the two platforms drift again.
    @Test func theMacBundleTimerStillDistributesThroughTheSharedHelper() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let block = bundle("Sweep", estimates: [45, 15])
        let members = block.sortedTasks

        FocusSessionSupport.distributeBundleMinutes(60, across: members, in: context)

        #expect(members.map(\.actualMinutes) == [45, 15])
    }

    /// `FocusManager` is a singleton, so this restores it rather than leaving state behind.
    @Test func startingABundleSessionOnTheMacSeedsTheSharedDefaultSelection() throws {
        let manager = FocusManager.shared
        defer {
            manager.activeSession = nil
            manager.selectedBundleTaskIDs = []
            manager.reset()
            manager.wantsNavToFocus = false
        }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let block = bundle("Sweep", estimates: [10, 20])
        context.insert(block)
        for member in block.sortedTasks { context.insert(member) }

        manager.startFocus(bundle: block, in: context)

        #expect(manager.selectedBundleTaskIDs == CadenceFocusSupport.defaultSelectedTaskIDs(for: block))
    }
#endif

    // MARK: - The wiring (source scans)

    /// The point of the ticket. A shared picker model with no iOS call site would leave the phone
    /// exactly where it was.
    @Test func theIOSFocusScreenOffersBundlesAndRunsTheTimerAgainstThem() throws {
        let source = try strippingFocusTestComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(occurrencesInFocusSource(of: "CadenceFocusPickItem.filtered(", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "@Query private var allBundles: [TaskBundle]", in: source) == 1)
        // The cap is passed explicitly, because a picker with no search field must not inherit one.
        #expect(occurrencesInFocusSource(of: "limit: nil", in: source) == 1)
        // The block's minutes and its member ticks both go through the shared helpers.
        #expect(occurrencesInFocusSource(of: "CadenceFocusSupport.selectedTasks(in:", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "CadenceFocusSupport.defaultSelectedTaskIDs(for:", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "CadenceFocusSupport.logElapsedSeconds(", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "CadenceFocusSubject", in: source) == 1)
    }

    /// The screen must not grow its own copy of the arithmetic it was given. `actualMinutes +=` and
    /// `loggedMinutes +=` are the two lines that would mean a second, drifting distribution — the
    /// exact shape the shared helper exists to prevent.
    @Test func theIOSFocusScreenKeepsNoDistributionArithmeticOfItsOwn() throws {
        let source = try strippingFocusTestComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(occurrencesInFocusSource(of: "actualMinutes +=", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "loggedMinutes +=", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "totalWeight", in: source) == 0)
        // One row struct draws both kinds of session. A second one is the near-copy rule.
        #expect(occurrencesInFocusSource(of: "struct iOSFocusPickRow", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "iOSFocusBundlePickRow", in: source) == 0)
    }

    /// An exact count, not an absence: the Mac keeps the `FocusPickItem` name because the views in
    /// that file read better with it. What must be gone is the *body*.
    @Test func theMacPickerKeepsTheNameAndNoneOfTheBody() throws {
        let source = try strippingFocusTestComments(focusSourceFile("Cadence/macOS/Views/FocusPickerSupportViews.swift"))

        #expect(occurrencesInFocusSource(of: "enum FocusPickItem", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "typealias FocusPickItem = CadenceFocusPickItem", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "bundleDateRank", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "CadenceFocusBundlePresentation.summaryLine(", in: source) == 1)
    }

    /// Same for the distribution: the delegation survives, the weights do not.
    @Test func theMacSessionSupportKeepsNoWeightArithmetic() throws {
        let source = try strippingFocusTestComments(focusSourceFile("Cadence/macOS/Views/FocusSessionSupport.swift"))

        #expect(occurrencesInFocusSource(of: "totalWeight", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "CadenceFocusSupport.distributeMinutes(", in: source) == 1)
    }

    /// Non-vacuity. Every absence assertion above passes trivially against an empty string, so the
    /// reader itself is checked: a needle that is certainly present must be found, and a needle that
    /// is certainly absent must not be.
    @Test func theSourceReaderActuallyReadsTheseFilesInFocusBundleParity() throws {
        for path in [
            "Cadence/iOS/iOSFocusView.swift",
            "Cadence/macOS/Views/FocusPickerSupportViews.swift",
            "Cadence/macOS/Views/FocusSessionSupport.swift"
        ] {
            let source = try strippingFocusTestComments(focusSourceFile(path))
            #expect(source.count > 2_000)
            #expect(source.contains("#if os("))
            #expect(occurrencesInFocusSource(of: "ThisSymbolDoesNotExistAnywhere", in: source) == 0)
        }

        // Comment stripping works, and it is what makes the counts above read code rather than the
        // prose around it — every one of these files documents the feature in comments naming the
        // same symbols.
        let stripped = try strippingFocusTestComments(
            "let a = 1 // totalWeight\n/* actualMinutes += 3 */ let b = 2"
        )
        #expect(occurrencesInFocusSource(of: "totalWeight", in: stripped) == 0)
        #expect(occurrencesInFocusSource(of: "actualMinutes +=", in: stripped) == 0)
        #expect(stripped.contains("let a = 1"))
        #expect(stripped.contains("let b = 2"))
    }
}

private func focusTestRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func focusSourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: focusTestRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Non-overlapping count. Deliberately a count and not a `contains`: several assertions above need
/// "this call site exists exactly once" or "the body is gone while the name survives", and neither
/// is expressible with membership.
private func occurrencesInFocusSource(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchStart = haystack.startIndex
    while searchStart < haystack.endIndex,
          let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
        count += 1
        searchStart = range.upperBound
    }
    return count
}

/// Blanks `//` and `/* */` comments so the counts above read code rather than the prose around it.
/// Crude on purpose: a `//` inside a string literal is blanked too, which can only ever make these
/// checks stricter about what counts as a comment, never looser about live code.
private func strippingFocusTestComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
