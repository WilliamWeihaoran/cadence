import Foundation

/// **What one launch of `CadenceSeededSidebarTimingUITests` actually established — and, above all,
/// what it did not.**
///
/// [[T-710]] asks one question: are the seeded sidebar rows *late* or *absent*? Those need
/// opposite fixes, so the instrument that answers it must keep them apart. It must also keep apart
/// a third outcome that neither T-710 nor the suite's first version had a name for, and that is
/// the one this type exists for.
///
/// **The measurement that forced it (`coordgated`, 2026-10-01; re-measured by `seedrace`,
/// 2026-10-02).** The suite launches the app, then times two identifiers from the same instant:
///
/// - `sidebar.destination.today` — a **static** sidebar destination. It is drawn from
///   `CadenceSidebarLayout`, not from the store, so it appears on every launch whether anything
///   was seeded or not. It is the **control**.
/// - `sidebar.list.area.alpha-area` — a row that exists only because
///   `CadenceUITestSupport.seedDataIfNeeded` inserted and committed an `Area`. It is the
///   **subject**.
///
/// In 38 launches across the two runs the subject arrived **38 times**, between 0.04s and 0.52s,
/// **none of them past `CadenceUITestBounds.sidebarRow`**. In the two launches where it did not
/// arrive — `coordgated` runs 7 and 8 — *the control did not arrive either*:
///
///     T710 run  7/20 launch=1.51s today=ABSENT alpha=ABSENT beta=ABSENT gamma=ABSENT
///     T710 run  8/20 launch=1.29s today=ABSENT alpha=ABSENT beta=ABSENT gamma=ABSENT
///
/// A launch where the *static* row never appears in 60s has no visible UI at all. It cannot be
/// evidence about seeding, because nothing that launch drew would have been visible either way.
/// Run 7 said so on its own line — *"app did not reach the foreground; state is 3"*
/// (`.runningBackground`, [[T-563]]'s signature); run 8 reached the foreground and still published
/// an empty tree ([[T-1890]]'s shape).
///
/// **The suite printed that control on the same line and then ignored it**, failing both launches
/// with *"They are ABSENT, not late — T-710 is a seeding or @Query refresh bug and
/// CadenceUITestBounds.sidebarRow is irrelevant."* That sentence is unconditional in the first
/// version: it is what the failure *says*, not what the run *showed*. It was then read as settled
/// fact into [[T-1954]], which re-filed a launch failure as a product seeding defect and sent the
/// next reader looking for a race in `prepareAppState`.
///
/// So the verdict is computed here, from both observations, rather than asserted at the failure
/// site — and `blamesTheSeed` is the property that matters: **only `seedNeverArrived` may.**
enum CadenceSeededSidebarArrival: Equatable {

    /// The control never appeared, so neither did anything else. This launch says nothing about
    /// the seed — the app's UI was never on screen to be asked.
    case uiNeverAppeared

    /// The control appeared and the seeded row never did. **This, and only this, is T-710's
    /// "absent" case**: the window was up and the accessibility tree was live, and the row that
    /// depends on the seed was still missing.
    case seedNeverArrived(controlAt: TimeInterval)

    /// The seeded row arrived inside `CadenceUITestBounds.sidebarRow`. The ordinary outcome.
    case arrivedWithinBound(TimeInterval)

    /// The seeded row arrived, but past the bound. **This is T-710's "late" case**, and it is the
    /// only finding that would ever justify revisiting `CadenceUITestBounds.sidebarRow` — which no
    /// run has yet produced.
    case arrivedPastBound(TimeInterval)

    /// Whether this outcome is evidence of a seeding or `@Query` refresh defect.
    ///
    /// `false` for `uiNeverAppeared` is the whole point of this type. It is also `false` for
    /// `arrivedPastBound`, which is a bound question rather than a seeding one.
    var blamesTheSeed: Bool {
        if case .seedNeverArrived = self { return true }
        return false
    }

    /// `nil` when the launch proved nothing worth failing on, otherwise the sentence to fail with.
    ///
    /// Each sentence names the evidence it rests on, so a reader of the log never has to take the
    /// verdict on trust — that is exactly what went wrong the first time.
    var failureMessage: String? {
        switch self {
        case .uiNeverAppeared:
            return "the app's UI never appeared at all: the STATIC row "
                + "`sidebar.destination.today`, which no seed creates, was absent for the whole "
                + "observation window. This launch is evidence about the launch (T-563/T-1890), "
                + "NOT about seeding — the seeded rows had nothing to be missing from."
        case .seedNeverArrived(let controlAt):
            return "the static row `sidebar.destination.today` arrived at "
                + String(format: "%.2fs", controlAt)
                + " and the seeded rows never did. The window was up and the tree was live, so "
                + "they are ABSENT, not late — T-710 is a seeding or @Query refresh bug here and "
                + "CadenceUITestBounds.sidebarRow is irrelevant."
        case .arrivedWithinBound:
            return nil
        case .arrivedPastBound:
            // Recorded, not failed: T-710 asks for the distribution, and a late arrival is a
            // number for `sidebarRow` to be re-argued from rather than a red run.
            return nil
        }
    }
}

/// Turns the two observations one launch made into the finding that launch supports.
///
/// Pure and parameterised so the discriminating cases can be driven directly — see
/// `CadenceSeededSidebarArrivalVerdictTests`. The alternative is 20 real launches per assertion,
/// and the case that matters most (`uiNeverAppeared`) cannot be provoked on demand at all.
enum CadenceSeededSidebarArrivalVerdict {

    /// - Parameters:
    ///   - control: when `sidebar.destination.today` was first seen, or `nil` if never.
    ///   - seeded: when `sidebar.list.area.alpha-area` was first seen, or `nil` if never.
    ///   - bound: `CadenceUITestBounds.sidebarRow`, the bound under investigation.
    ///
    /// **The control is consulted first and the order is the correctness contract.** A missing
    /// subject is only a seeding finding once the control has established that *something* was on
    /// screen; asking about the subject first is precisely the mistake this replaces.
    static func verdict(
        control: TimeInterval?,
        seeded: TimeInterval?,
        bound: TimeInterval
    ) -> CadenceSeededSidebarArrival {
        guard let control else { return .uiNeverAppeared }
        guard let seeded else { return .seedNeverArrived(controlAt: control) }
        return seeded > bound ? .arrivedPastBound(seeded) : .arrivedWithinBound(seeded)
    }
}

/// **Which of the two observed blank-launch shapes a blank launch was — [[T-2020]].**
///
/// `CadenceSeededSidebarArrivalVerdict` above decides whether a launch may be read as evidence
/// about the seed. It deliberately says nothing about *why* a blank launch was blank, and that is
/// the half T-2020 is still open on. The two that have been seen are not the same failure:
///
///     T710 run  7/20 launch=1.51s today=ABSENT …   "app did not reach the foreground; state is 3"
///     T710 run  8/20 launch=1.29s today=ABSENT …   foreground reached, empty tree
///
/// Run 7 never left `.runningBackground` ([[T-563]]'s signature) and run 8 reached the foreground
/// and published nothing ([[T-1890]]'s, whose closing observation was a window the window server
/// reports `isOnScreen = false`). The entry says the honest reading is that they *may* be one
/// failure seen from two sides and that **nothing settles that** — so the next occurrence has to
/// arrive already labelled, because n=1 of each is exactly what has made this unanswerable twice.
///
/// **The third case is the one nothing was looking for, and it is why this type takes a
/// predecessor at all.** `CadenceSeededSidebarTimingUITests` is the only test in the target that
/// relaunches the app in a loop — 20 times inside one test — and it is the only test that has ever
/// produced a blank launch. Between launches it called `app.terminate()` and then **discarded** the
/// result of `app.wait(for: .notRunning, …)` (`_ =`), so a termination that did not complete inside
/// `CadenceUITestBounds.settle` was invisible. A second instance of the same bundle id is a
/// mechanism for *both* of the other two shapes — `launch()` activates the live instance rather
/// than the new one, which leaves the new process in the background and the old window carrying a
/// store the new launch did not seed. It also predicts what the measured runs show and a per-launch
/// 5% flake does not: **runs 7 and 8 were CONSECUTIVE**, which is the shape of one host condition
/// spanning two launches, not two independent draws. (Given exactly 2 blanks in 20 launches, two
/// being adjacent has probability 19/190 = 10% by chance, so this is suggestive and not proof.)
///
/// So the predecessor is consulted **first**: when the previous launch is still running, neither of
/// the other two readings is safe, and saying "T-563" of a launch that was merely talking to a
/// leftover app is the same class of mistake T-1954 made one layer out.
enum CadenceBlankLaunchSignature: Equatable {

    /// The preceding launch in the loop had not stopped when this one started. This launch is
    /// evidence about the TEARDOWN, not about T-563 or T-1890.
    case previousLaunchStillRunning

    /// The app never reached `.runningForeground`. [[T-563]]'s shape — `state` carried so the
    /// reading can be checked rather than taken on trust (3 is `.runningBackground`).
    case neverReachedForeground(state: Int)

    /// The app reached the foreground and still drew nothing. [[T-1890]]'s shape.
    case foregroundButNothingDrawn

    /// What to print beside a blank launch so the next reader does not have to infer it.
    var report: String {
        switch self {
        case .previousLaunchStillRunning:
            return "the PREVIOUS launch was still running when this one started, so this launch is "
                + "evidence about the loop's teardown and about neither T-563 nor T-1890 — "
                + "`launch()` activates a live instance rather than the new one"
        case .neverReachedForeground(let state):
            return "the app never reached the foreground (state \(state)); T-563's shape, on a "
                + "launch whose predecessor had stopped"
        case .foregroundButNothingDrawn:
            return "the app reached the foreground and drew nothing; T-1890's shape — a window the "
                + "window server will not composite publishes no accessibility tree"
        }
    }
}

/// Names a blank launch from the three observations the launch loop already makes.
enum CadenceBlankLaunchClassifier {

    /// - Parameters:
    ///   - predecessorStopped: whether `wait(for: .notRunning, …)` succeeded after the PREVIOUS
    ///     launch. `true` for the first launch of a loop, which has no predecessor.
    ///   - reachedForeground: whether `wait(for: .runningForeground, …)` succeeded.
    ///   - state: `XCUIApplication.state.rawValue` as observed.
    ///
    /// **The predecessor is consulted before the state, and the order is the correctness
    /// contract** — same shape, and same reason, as the control-first rule above.
    static func signature(
        predecessorStopped: Bool,
        reachedForeground: Bool,
        state: Int
    ) -> CadenceBlankLaunchSignature {
        guard predecessorStopped else { return .previousLaunchStillRunning }
        guard reachedForeground else { return .neverReachedForeground(state: state) }
        return .foregroundButNothingDrawn
    }
}
