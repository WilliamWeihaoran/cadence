import Foundation
import SwiftData

/// Reading and writing the synced sidebar layout (T-1274).
///
/// The parse, the duplicate rule, the visibility floor and the reorder arithmetic live here and
/// nowhere else: both sidebars, both Settings surfaces and the command palette have to agree about
/// what the stored strings mean, and four copies of that is how two columns come to draw different
/// layouts from one record.
///
/// Everything above the write helpers is pure, so `CadenceSidebarLayoutPreferenceTests` can pin the
/// rules without a model container.
///
/// Main-actor isolated by the project default, like `CadenceSidebarLayout` itself: it is read by
/// views and by the Settings screens, and nothing off the main actor — no widget, no MCP target —
/// compiles this file.
enum CadenceSidebarLayoutPreferenceStore {

    /// A resolved layout: what the user dragged, and what they hid.
    struct Layout: Equatable {
        /// Only the destinations the user actually moved, in their order. Never defaults-filled —
        /// see `CadenceSidebarLayout.resolvedDestinations`, which treats an unnamed destination as
        /// "leave it where the layout declares it".
        var order: [CadenceFeatureDestination] = []
        var hidden: Set<CadenceFeatureDestination> = []

        static let declared = Layout()
    }

    // MARK: - Parsing

    /// Destinations named by a stored string, in order, without duplicates.
    ///
    /// Unrecognised raw values are dropped rather than kept: this build cannot place a row it has
    /// no case for, and carrying the token forward would mean writing back a string whose meaning
    /// this build does not know.
    static func destinations(fromRaw raw: String) -> [CadenceFeatureDestination] {
        raw.split(separator: ",")
            .compactMap { CadenceFeatureDestination(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
            .reduce(into: [CadenceFeatureDestination]()) { partial, destination in
                if !partial.contains(destination) { partial.append(destination) }
            }
    }

    static func raw(from destinations: [CadenceFeatureDestination]) -> String {
        destinations.map(\.rawValue).joined(separator: ",")
    }

    // MARK: - Which record

    /// The row every device must agree on when more than one exists.
    ///
    /// Newest edit wins, because that is what a person means by changing a preference on the device
    /// in front of them. `id.uuidString` breaks a tie so two devices reading the same pair pick the
    /// same row rather than each picking its own and writing over the other forever.
    static func current(from records: [SidebarLayoutPreference]) -> SidebarLayoutPreference? {
        records.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The layout to draw.
    ///
    /// `legacy*` are the device-local `CadencePreferenceKeys.sidebarTabOrder` /
    /// `sidebarHiddenTabs` values this preference replaced. They are the fallback for a store that
    /// holds no synced row yet, so the Mac that has been customised for months does not reset
    /// itself the day the layout became synced; the first edit writes a row and the local values
    /// stop being consulted.
    static func layout(
        from records: [SidebarLayoutPreference],
        legacyOrderRaw: String = "",
        legacyHiddenRaw: String = ""
    ) -> Layout {
        guard let record = current(from: records) else {
            return Layout(
                order: destinations(fromRaw: legacyOrderRaw),
                hidden: Set(destinations(fromRaw: legacyHiddenRaw))
            )
        }
        return Layout(
            order: destinations(fromRaw: record.orderRaw),
            hidden: Set(destinations(fromRaw: record.hiddenRaw))
        )
    }

    // MARK: - Editing

    /// The rows the user may hide and reorder. Settings itself is not among them: it is the only
    /// door to the screen that would hide it, and a stored value naming it is inert rather than
    /// obeyed.
    static var customisableDestinations: Set<CadenceFeatureDestination> {
        CadenceSidebarLayout.customisableDestinations
    }

    /// Every customisable row, in the order the sidebar will draw it — the Settings screen's list.
    ///
    /// Walks the groups in sidebar order, so the nav rows come first and Focus, which lives in the
    /// footer, comes last.
    static func orderedCustomisableDestinations(for layout: Layout) -> [CadenceFeatureDestination] {
        CadenceSidebarLayout.NavGroup.allCases.flatMap { group in
            CadenceSidebarLayout.resolvedDestinations(
                in: group,
                customisable: customisableDestinations,
                storedOrder: layout.order,
                hidden: []
            )
            .filter { customisableDestinations.contains($0) }
        }
    }

    /// The hidden set after a visibility toggle, or `nil` when the toggle changes nothing or is
    /// refused.
    ///
    /// **The floor is one visible nav row.** Hiding the last one would leave a column of lists with
    /// no way to a page, and "every row is hidden" is a state a person can reach in six clicks and
    /// cannot read their way out of. Refusing the final toggle is the rule; the Settings screen
    /// says so rather than silently flipping the switch back. Focus is not part of the floor — the
    /// footer glyph is not one of the places the sidebar navigates *to* in the same sense, and
    /// Settings, which is always drawn, is the door back either way.
    static func hidden(
        setting destination: CadenceFeatureDestination,
        visible: Bool,
        in layout: Layout
    ) -> Set<CadenceFeatureDestination>? {
        guard customisableDestinations.contains(destination) else { return nil }
        var hidden = layout.hidden
        if visible {
            guard hidden.contains(destination) else { return nil }
            hidden.remove(destination)
            return hidden
        }
        guard !hidden.contains(destination) else { return nil }
        hidden.insert(destination)
        let stillVisible = CadenceSidebarLayout.primaryDestinations.filter { !hidden.contains($0) }
        return stillVisible.isEmpty ? nil : hidden
    }

    /// The sentence the Settings screen shows when the last visible row is toggled off.
    static let lastVisibleRowNotice = "Keep at least one sidebar row visible."

    /// The order after dragging `dragged` above `target`.
    ///
    /// Written as a full order — every customisable row, not just the moved one — because a stored
    /// order that names a subset only constrains that subset, and a drag the user can see has to
    /// survive the next row being added above it.
    static func order(
        in layout: Layout,
        moving dragged: CadenceFeatureDestination,
        before target: CadenceFeatureDestination
    ) -> [CadenceFeatureDestination]? {
        guard dragged != target else { return nil }
        var current = orderedCustomisableDestinations(for: layout)
        guard let fromIndex = current.firstIndex(of: dragged),
              let toIndex = current.firstIndex(of: target) else { return nil }
        let moved = current.remove(at: fromIndex)
        current.insert(moved, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        return current
    }

    // MARK: - Writing

    /// Writes a layout, creating the synced row the first time.
    ///
    /// Commits through `CadencePendingChangePersistence` rather than `try? save()`: this inserts on
    /// the first edit, and the Settings screen reports success by redrawing the row where the user
    /// dropped it — both halves of the rule that makes a swallowed save a defect.
    @MainActor
    static func write(
        _ layout: Layout,
        records: [SidebarLayoutPreference],
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let orderRaw = raw(from: layout.order)
        // Written in the sidebar's own order rather than the set's, so the same hidden rows always
        // produce the same string and a no-op write cannot look like a change to another device.
        let hiddenRaw = raw(from: CadenceSidebarLayout.navigationDestinations.filter { layout.hidden.contains($0) })

        guard let record = current(from: records) else {
            // Seeded with the **whole** layout, which is why callers pass both halves: the first
            // edit on a Mac that has been customised for months must carry the device-local order
            // and hidden set into the synced row, not replace them with one toggle.
            let created = SidebarLayoutPreference(orderRaw: orderRaw, hiddenRaw: hiddenRaw, updatedAt: now)
            modelContext.insert(created)
            try CadencePendingChangePersistence.commitInsert(of: created, in: modelContext, commit: commit)
            return
        }

        let previousOrder = record.orderRaw
        let previousHidden = record.hiddenRaw
        let previousUpdatedAt = record.updatedAt
        record.orderRaw = orderRaw
        record.hiddenRaw = hiddenRaw
        record.updatedAt = now
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            record.orderRaw = previousOrder
            record.hiddenRaw = previousHidden
            record.updatedAt = previousUpdatedAt
        }
    }
}
