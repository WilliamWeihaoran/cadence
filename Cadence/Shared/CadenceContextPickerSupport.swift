import Foundation

/// The context half of `CadencePickerSupport` — the two facts that are `Context`'s rather than the
/// picker's, and the name its call sites read it by.
///
/// **Why the shared list exists (T-446, residue from T-288).** Four surfaces ask the user to pick a
/// context — macOS's `CadenceContextPickerList`, the iOS project/area editor, and the iOS goal and
/// habit sheets. T-288 looked at converging the *views* and correctly refused: the macOS control is
/// keyboard-first (`onMoveCommand`, a focused search field, an arrow-driven highlight, `onSubmit`)
/// and the iOS sites are `CadenceChoicePopoverList` popovers. Those are two legitimate
/// presentations. What was duplicated underneath them is the *list*: the sort, which contexts are
/// offerable, what an unnamed one is called, and where the "none" row goes. Each of the four spelled
/// it, and — because they were four spellings — they did not agree.
///
/// **They had diverged, and the divergence was a bug, not a distinction:**
///
/// - **An archived context stayed assignable on three of the four.** `Context.isArchived` is
///   excluded everywhere a context is *offered* — both sidebars, both settings panes' active list,
///   and `CadenceReadService`'s default over MCP — but only the iOS project/area editor filtered it
///   in a picker. Archive a context and macOS's habit and goal sheets, plus both iOS tracking
///   sheets, still offered it as a fresh choice.
/// - **The one site that did filter then lied about the current value.** `iOSListEditorSheet` read
///   its *button label* out of the filtered array and its *saved value* out of the unfiltered one,
///   so editing a project whose context had since been archived showed "None" while saving the
///   archived context anyway. Hence `selectable(_:selectedID:)`: the archive rule hides contexts you
///   could newly pick, never the one already assigned. A picker that cannot show you what is
///   selected is worse than one that offers a stale option.
/// - **Equal `order` values resolved differently per platform.** macOS broke the tie on name;
///   iOS took `@Query(sort: \Context.order)` alone, whose order among equal keys SwiftData does not
///   promise. `Context.order` defaults to `0`, so every context created outside the reorder UI ties.
/// - **An empty name rendered three ways** — "Untitled Context" on the iOS list editor, blank on
///   both tracking sheets and on macOS.
///
/// So this type owns the facts and the two presentations stay two. A call site that re-derives any
/// of them is what `CadenceContextPickerConsolidationTests` is red on.
///
/// **T-488 made the list generic.** The Area row one line down the same `Form` had the identical
/// defect, and a near-copy of this file to fix it would have been the [[T-374]] defect committed by
/// the ticket meant to remove one. The rules moved to `CadencePickerSupport`; only the two facts
/// below are `Context`'s. Nothing at a call site moved — `CadenceContextPickerSupport.items(...)`
/// still resolves, because the name is now a typealias for the same rules with `Context` filled in.
typealias CadenceContextPickerSupport = CadencePickerSupport<Context>

extension Context: CadencePickable {
    /// Archiving retires a context from future choices. It does **not** hide the one a list is
    /// already in; `CadencePickerSupport.selectable(_:selectedID:)` owns that half.
    var isOfferableInPicker: Bool { !isArchived }

    /// Declared in `CadenceTitleNormalization`, in `Models/`, because this label was previously
    /// spelled *three* times: `CadenceReadService` answers MCP with the same words and could not
    /// read a constant from `Shared/`, which `CadenceMCPServer` does not compile (T-499).
    static var untitledPickerName: String { CadenceTitleNormalization.defaultContextName }
}
