import SwiftData
import Foundation

/// Top-level life/work domain. Contains areas, projects, pursuits, milestones, and habits.
@Model final class Context {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#4a9eff"
    var icon: String = "square.stack.fill"
    var order: Int = 0
    var isArchived: Bool = false

    @Relationship(inverse: \Area.context) var areas: [Area]? = nil
    @Relationship(inverse: \Project.context) var projects: [Project]? = nil
    @Relationship(inverse: \Pursuit.context) var pursuits: [Pursuit]? = nil
    @Relationship(inverse: \AppTask.context) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Goal.context) var goals: [Goal]? = nil
    @Relationship(inverse: \Habit.context) var habits: [Habit]? = nil

    init(name: String, colorHex: String = "#4a9eff", icon: String = "square.stack.fill") {
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }
}

/// The one order contexts are drawn in, on every surface and both platforms ([[T-18950]]):
/// `order`, then name case-insensitively, then `id`.
///
/// **Why a bare `order` is not an order.** Every surface used to take `@Query(sort: \Context.order)`
/// as handed, and among equal keys SwiftData promises nothing. Equal keys are reachable without
/// any bug: an archive import under `mergeKeepingExistingRows` copies a context's `order` onto a
/// number a live context already holds, and each creator (`CreateContextSheet`, the iOS Settings
/// card, MCP) takes `max + 1` locally, so two devices creating one offline collide. The sidebars'
/// sections, Today and All Tasks' by-list groups and the Mac Kanban's list columns then came out
/// in whatever order the store returned the tie — which need not agree between the Mac and the
/// iPhone, or between two renders.
///
/// **Why these three keys.** `CadenceMCPOrdering.precedes(_: Context, _:)` was already total on
/// exactly this rule, so an agent's `list_contexts` and the screen now agree on the same store;
/// `CadenceDisplayOrderTests` pins that parity. `id` ends it the way it ends `TaskOrdering` and
/// `CadenceSidebarLists.precedes`: unique, stable across launches and processes, never visible.
///
/// **How a surface reads it.** A view's query stays `@Query(sort: \Context.order)` — the store
/// sort is a cheap pre-order — but is named `storedContexts` and read only through
/// `CadenceDisplayOrder.contexts(storedContexts)`. `CadenceDisplayOrderTests` is the census that
/// keeps any `@Query` over `Context` from being read bare again.
nonisolated enum CadenceDisplayOrder {
    /// What an ordered element is ordered by.
    struct Key {
        let order: Int
        let name: String
        let id: UUID
    }

    /// Total: two keys compare equal only when they name the same row.
    static func precedes(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }

        let names = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if names != .orderedSame { return names == .orderedAscending }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func key(_ context: Context) -> Key {
        Key(order: context.order, name: context.name, id: context.id)
    }

    static func precedes(_ lhs: Context, _ rhs: Context) -> Bool {
        precedes(key(lhs), key(rhs))
    }

    /// `contexts` in the order every surface draws them.
    static func contexts(_ contexts: [Context]) -> [Context] {
        contexts.sorted(by: precedes)
    }
}
