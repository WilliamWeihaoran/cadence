import Foundation

/// The sidebar's scrolling lists region: which context owns which area/project, and in what order.
///
/// This sits beside `CadenceSidebarLayout` in `Shared/` for the same reason that file does — the
/// macOS sidebar and the iPad sidebar draw the same region, and "which context does this list
/// belong to, and where in the column does it go" is exactly the kind of rule that gets written
/// twice and then drifts.
///
/// It deals in plain values rather than in `Area` / `Project`, so the ordering rule can be tested
/// without a model container and so the row views stay ignorant of SwiftData.
nonisolated enum CadenceSidebarLists {
    enum Kind: Equatable, Hashable {
        case area
        case project

        /// Areas sort ahead of projects when two rows claim the same `order`. Both models number
        /// their own sequence from zero, so a context holding one of each routinely has two rows
        /// claiming slot 0 — without a tie-break the region reshuffles between renders.
        var rank: Int {
            switch self {
            case .area: return 0
            case .project: return 1
            }
        }
    }

    /// One area or project, flattened to what a sidebar row draws and sorts by.
    struct Item: Identifiable, Equatable, Hashable {
        let id: UUID
        let kind: Kind
        let name: String
        let colorHex: String
        let order: Int
        /// `nil` for a list with no context, or one whose context is archived — see `sections`.
        let contextID: UUID?
        /// Projects only, and only when set. Areas have no due date.
        let dueDateKey: String?
        let openTaskCount: Int

        init(
            id: UUID,
            kind: Kind,
            name: String,
            colorHex: String,
            order: Int,
            contextID: UUID?,
            dueDateKey: String? = nil,
            openTaskCount: Int = 0
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.colorHex = colorHex
            self.order = order
            self.contextID = contextID
            self.dueDateKey = dueDateKey
            self.openTaskCount = openTaskCount
        }
    }

    /// A context header and the rows under it.
    struct Section: Identifiable, Equatable {
        /// `nil` on the trailing catch-all section, which belongs to no context and therefore
        /// offers no "new list in this context" button.
        let contextID: UUID?
        let title: String
        let items: [Item]

        var id: String { contextID?.uuidString ?? Self.ungroupedID }

        static let ungroupedID = "ungrouped"
    }

    /// The same section, for a caller that has to keep its own element type — the grouping twin of
    /// `sorted(_:item:)`, and it exists for the same reason (T-538).
    ///
    /// macOS's rows drag and their drop delegate writes `order` back, so `ContextSection` holds
    /// live `Area` / `Project` objects and cannot render a flattened `Item`. Before this existed it
    /// therefore could not call `sections(contexts:items:)` at all, and did the grouping itself by
    /// iterating each `Context`'s relationship — which is how the catch-all below came to be drawn
    /// on iPad and nowhere else.
    struct ElementSection<Element>: Identifiable {
        /// `nil` on the trailing catch-all section, exactly as on `Section`.
        let contextID: UUID?
        let title: String
        let elements: [Element]

        var id: String { contextID?.uuidString ?? Section.ungroupedID }
    }

    /// A context, reduced to what the region needs. Callers pass these already filtered and in the
    /// order the sidebar shows them.
    struct ContextRef: Identifiable, Equatable, Hashable {
        let id: UUID
        let name: String

        init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// The header the catch-all section carries.
    ///
    /// macOS iterates contexts and never looks at the leftovers, so a list with no context — or one
    /// whose context has been archived — is simply absent from that column. On iPad the lists were
    /// reached through a flat picker that showed everything, so silently dropping them here would
    /// lose rows that are on screen today. They get a section instead.
    static let ungroupedTitle = "Other"

    /// Whether a list's context is one of the ones a control was actually handed.
    ///
    /// **The membership half of the catch-all, and it is shared because it is the half that keeps
    /// getting respelled.** Five surfaces have now been filed for folding over contexts and losing
    /// the lists that match none of them (T-534, T-538, T-558), and the fix each time is a bucket
    /// keyed on this question rather than on `context == nil` — because "no context" and "a context
    /// this caller did not offer" are the same row to the user and different expressions in code.
    /// An archived context is the ordinary way to reach the second case: every sidebar and picker
    /// filters those out of what it offers, and the lists inside one do not disappear with it.
    ///
    /// Takes the id rather than the model so it stays in `Shared/` beside the title it pairs with.
    static func isOffered(_ contextID: UUID?, among offered: Set<UUID>) -> Bool {
        guard let contextID else { return false }
        return offered.contains(contextID)
    }

    /// One area's or project's place, as far as numbering a new sibling needs: where it is filed and
    /// what `order` it holds.
    typealias OrderSlot = (contextID: UUID?, order: Int)

    /// The `order` a NEW area or project takes: one past the highest among the areas **and**
    /// projects already filed in the context it is created in (`nil` is the unfiled bucket,
    /// compared optional-to-optional so it is numbered the same way as a filed one).
    ///
    /// **[[T-14621]].** Both kinds share one section, and `sorted(_:)` keeps a user-dragged
    /// interleaving only while every row in it holds a distinct `order`. The iOS list editor used to
    /// number a new area against every area in the store and a new project against every project,
    /// so after a dense renumber (`CadenceSidebarListReorder.commit`) a new project could take a
    /// number an area in its own section already held — the section dropped to areas-first and the
    /// project the user had dragged to the top fell to the bottom, on every device, because the
    /// numbers sync. The Mac's `CreateListSheet` had the right rule privately; both editors now ask
    /// here so they cannot drift again. MCP's `CadenceWriteService.nextListOrder` spells the same
    /// rule in a target that does not compile this file.
    static func nextOrder(
        inContextWithID contextID: UUID?,
        areas: [OrderSlot],
        projects: [OrderSlot]
    ) -> Int {
        CadenceOrderAllocation.nextOrder(
            after: (areas + projects).filter { $0.contextID == contextID },
            order: { $0.order }
        )
    }

    /// The region, top to bottom, for the touch columns — the iPad sidebar and the iPhone Tasks
    /// index, both `iOSSidebarListsRegion` — which render flattened `Item`s.
    ///
    /// `contexts` supplies the order and the naming. **A context with no lists keeps its section**,
    /// as on the Mac ([[T-14793]]): since [[T-3073]] every header on these columns carries the `+`
    /// that opens the list editor seeded with that context, so dropping an empty one hid the only
    /// door to a list in a context just made in Settings. Nothing about touch forces a difference
    /// here ([[T-8201]]). The empty catch-all is still dropped, as everywhere — see below.
    static func sections(contexts: [ContextRef], items: [Item]) -> [Section] {
        sections(contexts: contexts, elements: items, keepingEmptyContexts: true, item: { $0 })
            .map { Section(contextID: $0.contextID, title: $0.title, items: $0.elements) }
    }

    /// The same region, for a caller that has to keep its own element type.
    ///
    /// **This is the whole of T-538.** A list whose `context` is `nil` — or whose context has been
    /// archived, so it is not in `contexts` — belongs to no context section, and a column that
    /// derives its rows by *iterating contexts* cannot draw it at all. It is not un-grouped there;
    /// it is absent. iOS offers "None" in the context row of every list editor, in new and edit
    /// mode alike, so this state is one tap away on the phone and arrives on the Mac by sync. Both
    /// columns route through here now, so neither can reach the leftovers by not looking.
    ///
    /// `keepingEmptyContexts` is true for every sidebar — the macOS column and, through the
    /// flattened overload above, both touch columns ([[T-14793]]) — and it is not cosmetic: each
    /// header carries a control — the "+" that opens `CreateListSheet` on macOS and the seeded
    /// list editor on iOS — so dropping an empty context would make a newly created context
    /// unusable. Only a caller that draws no header, the Mac's Kanban board flattening this into
    /// columns, passes false. The catch-all is never
    /// kept when empty either way: it draws a "+" on macOS since T-559, but that button only
    /// pre-selects "No context" in a sheet every other header can also reach, so an empty catch-all
    /// would be a heading over nothing that offers nothing the column does not already offer.
    static func sections<Element>(
        contexts: [ContextRef],
        elements: [Element],
        keepingEmptyContexts: Bool,
        item: (Element) -> Item
    ) -> [ElementSection<Element>] {
        // Decorated once, not re-read per phase: `item` walks a SwiftData relationship on macOS
        // (the open-task tally), so calling it in the bucketing loop and again inside the sort
        // would double that walk for every row on every render.
        let decorated = elements.map { (element: $0, item: item($0)) }
        let known = Set(contexts.map(\.id))
        typealias Decorated = (element: Element, item: Item)
        var byContext: [UUID: [Decorated]] = [:]
        var ungrouped: [Decorated] = []

        for entry in decorated {
            if let contextID = entry.item.contextID, isOffered(contextID, among: known) {
                byContext[contextID, default: []].append(entry)
            } else {
                ungrouped.append(entry)
            }
        }

        func section(_ contextID: UUID?, _ title: String, _ owned: [Decorated]) -> ElementSection<Element> {
            ElementSection(
                contextID: contextID,
                title: title,
                elements: sorted(owned, item: \.item).map(\.element)
            )
        }

        var sections = contexts.compactMap { context -> ElementSection<Element>? in
            let owned = byContext[context.id] ?? []
            guard keepingEmptyContexts || !owned.isEmpty else { return nil }
            return section(context.id, context.name, owned)
        }

        if !ungrouped.isEmpty {
            sections.append(section(nil, ungroupedTitle, ungrouped))
        }

        return sections
    }

    /// One context's rows.
    ///
    /// When every row in the section holds a distinct `order`, that number is a single sequence the
    /// user dragged and areas and projects interleave freely. When it does not — the usual case for
    /// a context holding both, since each model numbers from zero — the two kinds are kept apart so
    /// a shared `order` value cannot interleave them arbitrarily.
    static func sorted(_ items: [Item]) -> [Item] {
        sorted(items, item: { $0 })
    }

    /// The same rule, for a caller that has to keep its own element type.
    ///
    /// **T-333.** macOS's `ContextSection` holds `Area` / `Project` model objects, because its rows
    /// drag and its drop delegate writes `order` back — it cannot render a flattened `Item`. So it
    /// carried its own copy of the rule above, and the copy stopped one leg short: it ended at
    /// `order`, kind, then name, with no `id` tail, and the two per-kind pre-sorts feeding it were
    /// a bare `$0.order < $1.order`. Ordinary data behaves. Legacy, imported or CloudKit data with
    /// two same-kind rows sharing an `order` **and** a name reshuffles between renders on the Mac
    /// while the iPad — which routes through `sections(_:_:)` — holds still.
    ///
    /// Decorate–sort–undecorate on the caller's own values, so nothing is looked back up by `id`:
    /// two rows may legitimately share one (a restore that duplicated a row is exactly the data
    /// this exists for), and a dictionary keyed on `id` would silently drop one of them.
    static func sorted<Element>(_ elements: [Element], item: (Element) -> Item) -> [Element] {
        let decorated = elements.map { (element: $0, item: item($0)) }
        let hasGlobalOrder = Set(decorated.map(\.item.order)).count == decorated.count

        func ordered(_ subset: [(element: Element, item: Item)]) -> [Element] {
            subset.sorted { precedes($0.item, $1.item) }.map(\.element)
        }

        guard hasGlobalOrder else {
            return ordered(decorated.filter { $0.item.kind == .area })
                + ordered(decorated.filter { $0.item.kind == .project })
        }
        return ordered(decorated)
    }

    /// A **total** order: `order`, then kind, then name, then id. A partial one here is an unstable
    /// sort, which is a column that reorders itself between renders — the same failure
    /// `TaskOrdering.fallbackPrecedes` exists to prevent on task lists.
    private static func precedes(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.kind != rhs.kind { return lhs.kind.rank < rhs.kind.rank }
        let names = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if names != .orderedSame { return names == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
