import XCTest

/// **The discriminating cases for `CadenceSeededSidebarArrivalVerdict`, driven rather than
/// launched.**
///
/// Nothing here starts an app. `CadenceSeededSidebarTimingUITests` needs 20 real launches to
/// produce one distribution, and the case that actually matters — a launch whose UI never appears
/// — happened twice in 40 launches and cannot be provoked on demand. A verdict that is pure can be
/// handed the exact observations those launches made, including the two that were misread.
///
/// The fixtures below are **real measured rows**, not invented ones: the arrivals are from
/// `seedrace`'s 20/20 run on 2026-10-02 and `coordgated`'s 18/20 on 2026-10-01, and the two
/// absences are `coordgated` runs 7 and 8 verbatim.
///
/// There is deliberately more than one failing-shaped row (a control that never came up, and a
/// control that did while the seed never came) so that collapsing the two — which is what the
/// first version of the instrument did — flips exactly one of them and cannot be left green by a
/// single-row table (the one-candidate trap).
final class CadenceSeededSidebarArrivalVerdictTests: XCTestCase {

    /// The bound under investigation, mirrored rather than imported so a change to
    /// `CadenceUITestBounds.sidebarRow` cannot silently restate what these cases mean.
    private let bound: TimeInterval = 5

    /// **The regression this type exists for.** `coordgated` runs 7 and 8: every identifier
    /// absent, the static control included. The old instrument called this a seeding bug and
    /// [[T-1954]] inherited that as fact.
    func testALaunchWhoseStaticControlNeverAppearedIsNotASeedingFinding() {
        let verdict = CadenceSeededSidebarArrivalVerdict.verdict(
            control: nil,
            seeded: nil,
            bound: bound
        )

        XCTAssertEqual(verdict, .uiNeverAppeared)
        XCTAssertFalse(
            verdict.blamesTheSeed,
            "a launch that drew no UI at all cannot be evidence about seeding: the seeded rows "
            + "had nothing to be missing from, and `sidebar.destination.today` — which no seed "
            + "creates — was absent for the whole window"
        )
        XCTAssertEqual(
            verdict.failureMessage?.contains("NOT about seeding"),
            true,
            "the failure has to say what it actually established, because the last one did not"
        )
    }

    /// T-710's genuine "absent" case, and the control for the one above: the window was up, the
    /// tree was live, and the seeded row still never came. This one *is* a seeding finding, so a
    /// fix that stops blaming the seed everywhere would break it.
    func testASeedThatNeverArrivesBesideALiveControlIsASeedingFinding() {
        let verdict = CadenceSeededSidebarArrivalVerdict.verdict(
            control: 0.32,
            seeded: nil,
            bound: bound
        )

        XCTAssertEqual(verdict, .seedNeverArrived(controlAt: 0.32))
        XCTAssertTrue(verdict.blamesTheSeed)
        XCTAssertEqual(verdict.failureMessage?.contains("ABSENT, not late"), true)
    }

    /// T-710's "late" case — the only finding that would ever reopen the bound, and one no run has
    /// produced. It must not be collapsed into "absent", and it must not be collapsed into
    /// "fine" either: it is reported as a number and fails nothing.
    func testASeedPastTheBoundIsLateRatherThanAbsent() {
        let verdict = CadenceSeededSidebarArrivalVerdict.verdict(
            control: 0.32,
            seeded: 7.5,
            bound: bound
        )

        XCTAssertEqual(verdict, .arrivedPastBound(7.5))
        XCTAssertFalse(
            verdict.blamesTheSeed,
            "arriving late is a question about the bound, not evidence of a seeding defect"
        )
        XCTAssertNil(verdict.failureMessage, "a late arrival is a measurement, not a red run")
    }

    /// The ordinary outcome, and the empty-denominator guard: 38 of 40 measured launches landed
    /// here, so a verdict that answered `uiNeverAppeared` to everything would still have to fail
    /// this.
    func testASeedInsideTheBoundIsTheOrdinaryOutcomeAndFailsNothing() {
        let verdict = CadenceSeededSidebarArrivalVerdict.verdict(
            control: 0.03,
            seeded: 0.06,
            bound: bound
        )

        XCTAssertEqual(verdict, .arrivedWithinBound(0.06))
        XCTAssertFalse(verdict.blamesTheSeed)
        XCTAssertNil(verdict.failureMessage)
    }

    /// **Two readings that must DIFFER.** Replaying both measured runs end to end: 38 arrivals and
    /// two blank launches, and exactly **zero** verdicts that blame the seed.
    ///
    /// Asserting the count rather than a duration keeps this true on CI's Xcode 26 as well as this
    /// Mac — no row here is a timing, every row is an observation already taken.
    func testReplayingBothMeasuredRunsBlamesTheSeedNotOnce() {
        // `coordgated` 2026-10-01: 18 arrivals, min 0.29s, max 0.39s, and runs 7 and 8 blank.
        let coordgated: [(TimeInterval?, TimeInterval?)] =
            [(0.32, 0.34), (0.37, 0.39), (0.30, 0.31), (0.35, 0.36), (0.32, 0.35), (0.28, 0.30),
             (nil, nil), (nil, nil),
             (0.38, 0.39), (0.32, 0.34), (0.36, 0.37), (0.36, 0.38), (0.35, 0.37), (0.28, 0.31),
             (0.34, 0.36), (0.31, 0.32), (0.27, 0.29), (0.35, 0.37), (0.28, 0.29), (0.35, 0.37)]
        // `seedrace` 2026-10-02: 20 arrivals, min 0.04s, max 0.52s, none blank.
        let seedrace: [(TimeInterval?, TimeInterval?)] =
            [(0.50, 0.52), (0.05, 0.07), (0.04, 0.05), (0.04, 0.07), (0.05, 0.07), (0.04, 0.07),
             (0.03, 0.05), (0.03, 0.06), (0.03, 0.05), (0.03, 0.04), (0.04, 0.06), (0.04, 0.06),
             (0.04, 0.07), (0.03, 0.04), (0.04, 0.06), (0.09, 0.11), (0.03, 0.05), (0.07, 0.09),
             (0.04, 0.06), (0.04, 0.06)]

        let verdicts = (coordgated + seedrace).map {
            CadenceSeededSidebarArrivalVerdict.verdict(control: $0.0, seeded: $0.1, bound: bound)
        }

        XCTAssertEqual(verdicts.count, 40)
        XCTAssertEqual(
            verdicts.filter(\.blamesTheSeed).count,
            0,
            "no launch in either measured run supports a seeding defect; T-1954 was filed as one"
        )
        XCTAssertEqual(
            verdicts.filter { $0 == .uiNeverAppeared }.count,
            2,
            "coordgated runs 7 and 8 drew no UI at all, control included"
        )
        // The denominator, asserted so the two readings above cannot both be vacuously zero.
        XCTAssertEqual(
            verdicts.filter { if case .arrivedWithinBound = $0 { return true } else { return false } }.count,
            38
        )
        XCTAssertEqual(
            verdicts.filter { if case .arrivedPastBound = $0 { return true } else { return false } }.count,
            0,
            "not one of 38 arrivals was past the 5s bound, so raising it answers nothing"
        )
    }
}
