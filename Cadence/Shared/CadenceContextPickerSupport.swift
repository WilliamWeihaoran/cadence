import Foundation
import SwiftUI

/// The one answer to "which contexts may I pick, in what order, called what".
///
/// **Why this exists (T-446, residue from T-288).** Four surfaces ask the user to pick a context —
/// macOS's `CadenceContextPickerList`, the iOS project/area editor, and the iOS goal and habit
/// sheets. T-288 looked at converging the *views* and correctly refused: the macOS control is
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
enum CadenceContextPickerSupport {

    /// What a context with no name is called. One spelling, because it was previously two.
    static let untitledName = "Untitled Context"

    /// One row of a context picker, in either presentation. `id == nil` is the "none" row, whose
    /// title is the caller's — "No context", "None", "Use Parent Context" and "Use Goal Context" all
    /// mean different things and are legitimately per-site.
    struct Item: Identifiable, Equatable {
        let id: UUID?
        let title: String
        let icon: String?
        let colorHex: String?

        var isNone: Bool { id == nil }
    }

    /// `order`, then name case-insensitively.
    ///
    /// The tie-break is the load-bearing half; see the type's doc.
    static func sorted(_ contexts: [Context]) -> [Context] {
        contexts.sorted {
            if $0.order == $1.order {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    /// Every unarchived context, **plus the one currently assigned even when it is archived**.
    ///
    /// The second clause is not a softening of the archive rule: archiving retires a context from
    /// future choices, and a picker that silently drops the value it is displaying reports the
    /// wrong current state.
    static func selectable(_ contexts: [Context], selectedID: UUID?) -> [Context] {
        contexts.filter { !$0.isArchived || $0.id == selectedID }
    }

    /// Case-insensitive substring match on the name. An empty or whitespace-only query matches
    /// everything. Only macOS's picker has a search field; the iOS popovers pass no query.
    static func matching(_ contexts: [Context], query: String) -> [Context] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return contexts }
        let needle = trimmed.localizedLowercase
        return contexts.filter { $0.name.localizedLowercase.contains(needle) }
    }

    /// The context's display name, or `untitledName`.
    static func title(for context: Context) -> String {
        let trimmed = context.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledName : trimmed
    }

    /// The rows a picker draws: the optional "none" row, then the selectable contexts that match
    /// `query`, sorted.
    ///
    /// - Parameters:
    ///   - noneTitle: `nil` on a picker that does not offer "no context" at all.
    static func items(
        from contexts: [Context],
        selectedID: UUID?,
        query: String = "",
        noneTitle: String?
    ) -> [Item] {
        var items: [Item] = []
        if let noneTitle {
            items.append(Item(id: nil, title: noneTitle, icon: nil, colorHex: nil))
        }
        let offerable = matching(selectable(contexts, selectedID: selectedID), query: query)
        items.append(contentsOf: sorted(offerable).map { item(for: $0) })
        return items
    }

    /// The row for the current selection — the context's own if it resolves, the "none" row
    /// otherwise. What a picker's trigger button shows.
    static func selectedItem(
        from contexts: [Context],
        selectedID: UUID?,
        noneTitle: String
    ) -> Item {
        guard let selectedID, let context = contexts.first(where: { $0.id == selectedID }) else {
            return Item(id: nil, title: noneTitle, icon: nil, colorHex: nil)
        }
        return item(for: context)
    }

    /// `selectedItem(from:selectedID:noneTitle:).title`, for the call sites that only want the word.
    static func selectionTitle(
        from contexts: [Context],
        selectedID: UUID?,
        noneTitle: String
    ) -> String {
        selectedItem(from: contexts, selectedID: selectedID, noneTitle: noneTitle).title
    }

    private static func item(for context: Context) -> Item {
        Item(
            id: context.id,
            title: title(for: context),
            icon: context.icon,
            colorHex: context.colorHex
        )
    }
}

extension CadenceContextPickerSupport.Item {
    /// The context's own colour, or the quiet neutral the "none" row takes. Here rather than at
    /// three call sites, which is what "shared item model" has to mean to be worth having.
    var tint: Color { colorHex.map(Color.init(hex:)) ?? Theme.dim }
}
