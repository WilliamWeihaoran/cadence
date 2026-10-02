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
