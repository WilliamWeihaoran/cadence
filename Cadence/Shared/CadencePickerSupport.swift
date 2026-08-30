import Foundation
import SwiftUI

/// What a picker needs to know about a thing it can offer, and the one implementation of the rules
/// that follow from it.
///
/// **Why this is a generic and not a second support type (T-488).** `CadenceContextPickerSupport`
/// (T-446) answered "which contexts may I pick, in what order, called what" once, for the four
/// surfaces that ask. The row directly beneath it in `iOSListEditorSheet` asks the same question
/// about **areas**, and answered it for itself — with the same defect T-446 had just removed from
/// its neighbour: the trigger label resolved against `areas.filter(\.isActive)` while `save()`
/// resolved against the unfiltered query, so editing a project whose area had since been completed
/// or archived showed "None" and wrote the inactive area back.
///
/// The obvious fix — copy `CadenceContextPickerSupport`, change two words — is the [[T-374]]
/// defect, and it would have been committed by the ticket that exists to remove one. So the two
/// were diffed instead, and **everything was the same except two facts**:
///
/// | | `Context` | `Area` |
/// | --- | --- | --- |
/// | offerable as a fresh choice | `!isArchived` | `isActive` — excludes done *and* archived |
/// | what an unnamed one is called | "Untitled Context" | "Untitled Area" |
///
/// `name`, `order`, `icon` and `colorHex` both models already spell identically, so the protocol
/// asks for them by the names they already have.
///
/// Those two facts are the only ones `CadencePickable` adds; everything below them — the sort and
/// its tie-break, the "hide what you could newly pick, never the one already assigned" rule, the
/// search match, the "none" row, the item model — is `CadencePickerSupport`, written once. The
/// per-type facts live next to their typealias, in `CadenceContextPickerSupport.swift` and
/// `CadenceAreaPickerSupport.swift`, so `CadenceContextPickerSupport.items(...)` still reads the
/// way its eight call sites already spell it.
///
/// A third conformer is a five-line file. `Project` deliberately is not one yet: nothing picks a
/// project on its own — `iOSContainerChoicePopover` picks Inbox-or-area-or-project as one grouped
/// three-way control — and a conformance nothing reads is a claim nothing checks.
protocol CadencePickable {
    var id: UUID { get }
    var name: String { get }
    var order: Int { get }
    var icon: String { get }
    var colorHex: String { get }

    /// Whether this may be offered as a **fresh** choice.
    ///
    /// Not "whether it may appear": the already-assigned value appears whatever this says. See
    /// `CadencePickerSupport.selectable(_:selectedID:)`, which is where that distinction is the
    /// whole point.
    var isOfferableInPicker: Bool { get }

    /// What one of these with no name is called.
    static var untitledPickerName: String { get }
}

/// One row of a picker, in any presentation. `id == nil` is the "none" row, whose title is the
/// caller's — "No context", "None", "Use Parent Context", "Use Goal Context" and "None — top-level
/// goal" all mean different things and are legitimately per-site.
struct CadencePickerItem: Identifiable, Equatable {
    let id: UUID?
    let title: String
    let icon: String?
    let colorHex: String?

    var isNone: Bool { id == nil }
}

extension CadencePickerItem {
    /// The element's own colour, or the quiet neutral the "none" row takes. Here rather than at
    /// five call sites, which is what "shared item model" has to mean to be worth having.
    var tint: Color { colorHex.map(Color.init(hex:)) ?? Theme.dim }
}

/// The one answer to "which of these may I pick, in what order, called what".
enum CadencePickerSupport<Element: CadencePickable> {

    /// So a call site that already reads `CadenceContextPickerSupport.Item` keeps compiling, and so
    /// the two typealiases name one item type rather than two that happen to match.
    typealias Item = CadencePickerItem

    /// What an element with no name is called. One spelling per type, because it was previously
    /// two for contexts — "Untitled Context" on the iOS list editor, blank everywhere else — and
    /// two for areas: `areaTitle` called an unnamed area "None" while the popover listed it as
    /// "Untitled Area", so the trigger and the row it opened disagreed about the same area.
    static var untitledName: String { Element.untitledPickerName }

    /// `order`, then name case-insensitively.
    ///
    /// The tie-break is the load-bearing half. `@Query(sort: \Area.order)` is a sort on `order`
    /// alone, and among equal keys SwiftData promises nothing; `order` defaults to `0`, so every
    /// element created outside the reorder UI ties.
    static func sorted(_ elements: [Element]) -> [Element] {
        elements.sorted {
            if $0.order == $1.order {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    /// Every offerable element, **plus the one currently assigned even when it is not offerable**.
    ///
    /// The second clause is not a softening of the retirement rule: archiving or completing
    /// something retires it from future choices, and a picker that silently drops the value it is
    /// displaying reports the wrong current state. This is the whole of T-446 and T-488 — both were
    /// a label read out of the filtered array over a value saved from the unfiltered one, which
    /// showed "None" and then wrote the retired element back.
    static func selectable(_ elements: [Element], selectedID: UUID?) -> [Element] {
        elements.filter { $0.isOfferableInPicker || $0.id == selectedID }
    }

    /// Case-insensitive substring match on the name. An empty or whitespace-only query matches
    /// everything. Only macOS's context picker has a search field; the iOS popovers pass no query.
    static func matching(_ elements: [Element], query: String) -> [Element] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return elements }
        let needle = trimmed.localizedLowercase
        return elements.filter { $0.name.localizedLowercase.contains(needle) }
    }

    /// The element's display name, or `untitledName`.
    static func title(for element: Element) -> String {
        let trimmed = element.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledName : trimmed
    }

    /// The rows a picker draws: the optional "none" row, then the selectable elements that match
    /// `query`, sorted.
    ///
    /// - Parameters:
    ///   - noneTitle: `nil` on a picker that does not offer "none" at all.
    static func items(
        from elements: [Element],
        selectedID: UUID?,
        query: String = "",
        noneTitle: String?
    ) -> [Item] {
        var items: [Item] = []
        if let noneTitle {
            items.append(Item(id: nil, title: noneTitle, icon: nil, colorHex: nil))
        }
        let offerable = matching(selectable(elements, selectedID: selectedID), query: query)
        items.append(contentsOf: sorted(offerable).map { item(for: $0) })
        return items
    }

    /// The row for the current selection — the element's own if it resolves, the "none" row
    /// otherwise. What a picker's trigger button shows.
    ///
    /// It resolves against the **unfiltered** array on purpose, and `items(from:...)` keeps that
    /// same element in the list, so the trigger and the popover can never name two different
    /// things. That agreement is the fix; it is not an implementation detail of it.
    static func selectedItem(
        from elements: [Element],
        selectedID: UUID?,
        noneTitle: String
    ) -> Item {
        guard let selectedID, let element = elements.first(where: { $0.id == selectedID }) else {
            return Item(id: nil, title: noneTitle, icon: nil, colorHex: nil)
        }
        return item(for: element)
    }

    /// `selectedItem(from:selectedID:noneTitle:).title`, for the call sites that only want the word.
    static func selectionTitle(
        from elements: [Element],
        selectedID: UUID?,
        noneTitle: String
    ) -> String {
        selectedItem(from: elements, selectedID: selectedID, noneTitle: noneTitle).title
    }

    private static func item(for element: Element) -> Item {
        Item(
            id: element.id,
            title: title(for: element),
            icon: element.icon,
            colorHex: element.colorHex
        )
    }
}
