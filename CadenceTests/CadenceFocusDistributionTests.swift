import Foundation
import SwiftData
import Testing
@testable import Cadence

/// What is left of T-242's parity suite once the Block feature is gone ([[T-3170]]).
///
/// T-242 lifted the focus picker's row model, the minute distribution and the member selection out
/// of `#if os(macOS)` so an iPhone could run a block's timer. The member selection and the block
/// row went with the feature; the two pieces that were never block-shaped stayed, and this suite is
/// their home:
///
/// - `CadenceFocusSupport.distributeMinutes(_:across:in:commit:)` — a stopwatch reading handed out
///   across a credit list, weighted by estimate, rolled up into each task's list, with the
///   remainder on the last entry so the minutes handed out total exactly what was measured.
/// - `CadenceFocusPickItem` living in `Shared/`, which is what lets both pickers read one rule.
///
/// Every test below is stated over plain tasks. None of them needed a `TaskBundle` to be true; the
/// retired ones did, and they are named in the ticket rather than left here as stubs.
@MainActor
struct CadenceFocusDistributionTests {

    // MARK: - Fixtures

    private func tasks(_ title: String, estimates: [Int]) -> [AppTask] {
        estimates.enumerated().map { index, estimate in
            let task = AppTask(title: "\(title) \(index + 1)")
            task.estimatedMinutes = estimate
            return task
        }
    }

    // MARK: - The shared distribution

    /// The whole stopwatch reading is handed out — no minute is lost to independently rounded
    /// shares — and it is weighted by estimate, so the 45-minute task in a 60-minute credit list
    /// gets three quarters of the session rather than half of it.
    @Test func asessionSplitsItsMinutesByEstimateAndLosesNoneOfThem() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let credited = tasks("Sweep", estimates: [45, 15])

        try CadenceFocusSupport.distributeMinutes(60, across: credited, in: context)

        #expect(credited.map(\.actualMinutes) == [45, 15])
        #expect(credited.reduce(0) { $0 + $1.actualMinutes } == 60)
    }

    /// The remainder lands on the last entry rather than evaporating. Three equal tasks over
    /// 100 minutes is 33.33…, and three independently rounded 33s would log 99 minutes of a
    /// 100-minute session.
    @Test func thelastTaskAbsorbsTheRemainderSoTheTotalIsExact() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let credited = tasks("Uneven", estimates: [10, 10, 10])

        try CadenceFocusSupport.distributeMinutes(100, across: credited, in: context)

        #expect(credited.reduce(0) { $0 + $1.actualMinutes } == 100)
        #expect(credited.map(\.actualMinutes) == [33, 33, 34])
    }

    /// The minutes roll up into the task's list, which is what an hours-mode goal reads. A
    /// distribution that moved `actualMinutes` alone would leave the work invisible to every goal
    /// that measures in hours.
    @Test func distributedMinutesRollUpIntoEachTasksList() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Ledger")
        let area = Area(name: "Admin")
        let credited = tasks("Rollup", estimates: [30, 30])
        credited[0].project = project
        credited[1].area = area
        context.insert(project)
        context.insert(area)
        for task in credited { context.insert(task) }

        try CadenceFocusSupport.distributeMinutes(40, across: credited, in: context)

        #expect(project.loggedMinutes == 20)
        #expect(area.loggedMinutes == 20)
    }

    /// Seconds become minutes through `minutes(fromElapsedSeconds:)` — the one definition of what a
    /// stopwatch reading is worth — so the same clock logs the same number whichever door it came
    /// through. A second rounding rule here is exactly the divergence the focus audit found
    /// between the timer and the log-session sheets.
    @Test func thedistributingDoorRoundsTheSameWayTheSingleTaskBankDoes() throws {
        let context = ModelContext(try CadenceTestStore.container())
        for seconds in [0, 20, 61, 90, 3_660] {
            let credited = tasks("Rounding", estimates: [30])
            let single = AppTask(title: "Alone")

            try CadenceFocusSupport.logElapsedSeconds(seconds, across: credited, in: context)
            CadenceFocusSupport.bankElapsedSeconds(seconds, to: single, in: context)

            #expect(credited[0].actualMinutes == single.actualMinutes)
            #expect(single.actualMinutes == CadenceFocusSupport.minutes(fromElapsedSeconds: seconds))
        }
    }

    // MARK: - The picker cap

    /// macOS caps its unfiltered list at 18 on the understanding that you can type past the cap;
    /// iOS's picker passes `nil` and lists every ready task, with or without a query ([[T-8733]]).
    @Test func theunfilteredCapIsOptionalSoASurfaceWithNoSearchFieldCanShowEverything() {
        let ready = (0..<25).map { AppTask(title: "Ready \($0)") }

        let capped = CadenceFocusPickItem.filtered(tasks: ready, query: "", todayKey: "2026-08-22")
        let uncapped = CadenceFocusPickItem.filtered(
            tasks: ready,
            query: "",
            todayKey: "2026-08-22",
            limit: nil
        )

        #expect(capped.count == CadenceFocusPickItem.defaultUnfilteredLimit)
        #expect(uncapped.count == 25)
    }

    /// A row names the subject it would run against, which is how a surface re-finds the session it
    /// started without comparing titles.
    @Test func apickItemNamesItsOwnTarget() {
        let task = AppTask(title: "Deep work")

        #expect(CadenceFocusPickItem.task(task).target == .task(task.id))
        #expect(CadenceFocusPickItem.task(task).target.taskID == task.id)
    }

    // MARK: - The wiring (source scans)

    /// An exact count, not an absence: the Mac keeps the `FocusPickItem` name because the views in
    /// that file read better with it. What must be gone is the *body* — and, since [[T-3170]], the
    /// block row it used to draw.
    @Test func themacPickerKeepsTheNameAndNoneOfTheBody() throws {
        let source = try strippingFocusTestComments(focusSourceFile("Cadence/macOS/Views/FocusPickerSupportViews.swift"))

        #expect(occurrencesInFocusSource(of: "enum FocusPickItem", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "typealias FocusPickItem = CadenceFocusPickItem", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "bundleDateRank", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "CadenceFocusBundlePresentation", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "onSelectBundle", in: source) == 0)
    }

    /// The iOS screen must not grow its own copy of the arithmetic it was given. `actualMinutes +=`
    /// and `loggedMinutes +=` are the two lines that would mean a second, drifting distribution —
    /// the exact shape the shared helper exists to prevent — and `totalWeight` is its signature.
    @Test func theiOSFocusScreenKeepsNoDistributionArithmeticOfItsOwn() throws {
        let source = try strippingFocusTestComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(occurrencesInFocusSource(of: "CadenceFocusPickItem.filtered(", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "limit: nil", in: source) == 1)
        #expect(occurrencesInFocusSource(of: "actualMinutes +=", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "loggedMinutes +=", in: source) == 0)
        #expect(occurrencesInFocusSource(of: "totalWeight", in: source) == 0)
        // One row struct draws the picker. A second one is the near-copy rule.
        #expect(occurrencesInFocusSource(of: "struct iOSFocusPickRow", in: source) == 1)
    }

    /// Non-vacuity. Every absence assertion above passes trivially against an empty string, so the
    /// reader itself is checked: a needle that is certainly present must be found, and a needle that
    /// is certainly absent must not be.
    @Test func thesourceReaderActuallyReadsTheseFilesInFocusDistribution() throws {
        for path in [
            "Cadence/iOS/iOSFocusView.swift",
            "Cadence/macOS/Views/FocusPickerSupportViews.swift"
        ] {
            let source = try strippingFocusTestComments(focusSourceFile(path))
            #expect(source.count > 2_000)
            #expect(source.contains("#if os("))
            #expect(occurrencesInFocusSource(of: "ThisSymbolDoesNotExistAnywhere", in: source) == 0)
        }

        // Comment stripping works, and it is what makes the counts above read code rather than the
        // prose around it — both of these files document the feature in comments naming the same
        // symbols.
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
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
