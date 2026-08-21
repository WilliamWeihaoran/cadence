import Foundation

/// T-201, then T-217. **Whose lifetime a detail panel has, and when it closes on its own.**
///
/// The bug this exists to close, twice over. `iOSTaskDetailSheet` was presented by the *row*, so a
/// status write made from inside the inspector — Cancel, Restore, mark done — moved the task out of
/// the section's `ForEach`, SwiftUI tore the row down, and the sheet went with it. No status path
/// called `dismiss()`; the control experiment was **Start**, which is the same `onSetStatus` path but
/// keeps the row in ACTIVE, and left the sheet open. `iOSCalendarBundleDetailSheet` had the identical
/// shape on a different subject (T-217): presented by `iOSCalendarBoardBundleCard` and
/// `iOSTimelineBundleBlock`, both of which live in a `ForEach(bundles)` filtered by day — and on
/// Today's schedule pane, by *hour* — so saving a new date or start time from inside the panel moved
/// the card and tore the panel down at the moment the edit landed.
///
/// Moving presentation up to a host that outlives the row fixes that and immediately raises the
/// opposite question, which is what this type answers: a host holds the *model*, not a row, so the
/// selection now survives the subject leaving the page's own query. It must therefore say what to do
/// about a selection the page can no longer see.
///
/// **The rule is subject-neutral, and that is a finding rather than a convenience.** Nothing in it is
/// about an `AppTask`: both facts it reads are properties every `PersistentModel` has, and both
/// panels want the same answer for the same reason. It was `CadenceTaskInspectorPresentation`, with
/// `task`-shaped parameter names, until the bundle panel needed exactly it; a second copy of a
/// measured rule is the one outcome worth avoiding here, so the names lost the noun instead.
///
/// **Leaving the page's query is not a reason to close.** Cancelling a task from Today drops it out
/// of every Today section, and closing the inspector at that moment would be the original bug wearing
/// a decision's clothes — the user cancelled a task and the next thing they may want is Restore,
/// which is in the panel that just vanished. For a bundle it is sharper still: the query it leaves is
/// the one the user's own edit moved it out of, so closing on it would mean the panel disappears
/// precisely when a re-date succeeds. The host keeps a strong reference to the model, so the panel
/// keeps rendering the subject it was opened on whether or not any list still lists it.
///
/// **Deletion is.** A deleted model is the one case where staying is not an option: `@Bindable` over
/// a row that no longer exists has no defined reading, and the fields the panel binds to are gone.
/// Both panels' own Delete buttons already call `dismiss()` first, so the path this covers is the one
/// nothing else can — a delete arriving from CloudKit, or from a data reset, while the panel is open.
///
/// Lives in `Shared/` rather than beside the hosts because `Cadence/iOS/` is inside `#if os(iOS)` and
/// invisible to the macOS-built `CadenceTests`; the decision is the half worth pinning.
nonisolated enum CadenceDetailPanelPresentation {

    /// What a host does with the selection it is holding.
    enum Resolution: Equatable, Sendable {
        /// Keep presenting the subject the panel was opened on.
        case stay
        /// Clear the selection, which dismisses the sheet.
        case close
    }

    /// The whole rule, with both facts stated so neither can be smuggled in later.
    ///
    /// `subjectLeftThePageQuery` is deliberately **not** consulted. It is a parameter rather than an
    /// omission so that the next reader can see it was considered and rejected, and so that a
    /// mutation which starts closing on it fails a test instead of shipping.
    static func resolve(subjectIsGone: Bool, subjectLeftThePageQuery: Bool) -> Resolution {
        subjectIsGone ? .close : .stay
    }

    /// **Whether a held model is still real, and it takes two signals — measured, not assumed.**
    ///
    /// Against a real in-memory store (pinned by `CadenceTaskInspectorHostTests` for a task and
    /// `CadenceBundleInspectorHostTests` for a bundle):
    /// - between `ModelContext.delete(_:)` and the save, `isDeleted` is `true` while `modelContext`
    ///   is still set;
    /// - **after** the save, `isDeleted` reads `false` again and `modelContext` becomes `nil` —
    ///   while the property snapshot stays readable, so a stale panel goes on looking perfectly
    ///   alive.
    ///
    /// So a guard on `isDeleted` alone never fires for the committed delete, which is the only one
    /// that reaches a panel from outside it. That is not a hypothetical: it is what the first draft
    /// of this type did, and the test that caught it is the reason both signals are here.
    static func heldSubjectIsGone(isDeleted: Bool, hasNoModelContext: Bool) -> Bool {
        isDeleted || hasNoModelContext
    }

    /// The spelling a live host calls, and the only one it can: a host owns the model itself, so the
    /// page's query is never its business. It passes the worst case for the fact it cannot observe —
    /// assume the subject *has* left every list on the page — and still stays.
    ///
    /// Evaluated whenever the host re-renders, which is what makes it reliable at the moment that
    /// matters: the panel cannot *open* onto a model that is already gone. A delete that lands from
    /// CloudKit while the panel is up closes it on the next re-render rather than instantly —
    /// neither of these two signals is an observable property, so nothing publishes the change.
    /// That is a bounded claim on purpose; the alternative is a live query in the host, which is the
    /// page's filter creeping back into the panel's lifetime by another route.
    static func resolveHeldSubject(isDeleted: Bool, hasNoModelContext: Bool) -> Resolution {
        resolve(
            subjectIsGone: heldSubjectIsGone(isDeleted: isDeleted, hasNoModelContext: hasNoModelContext),
            subjectLeftThePageQuery: true
        )
    }
}
