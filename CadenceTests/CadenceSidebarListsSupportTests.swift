import Foundation
import Testing
@testable import Cadence

/// The sidebar's scrolling lists region: which context owns which list, and in what order.
///
/// In `Shared/` with `CadenceSidebarLayout` for the same reason — macOS and iPad draw the same
/// region, and a second copy of this rule is the repo's most productive bug.
struct CadenceSidebarListsSupportTests {
    private let work = CadenceSidebarLists.ContextRef(id: UUID(), name: "Work")
    private let home = CadenceSidebarLists.ContextRef(id: UUID(), name: "Home")

    private func item(
        _ name: String,
        kind: CadenceSidebarLists.Kind = .area,
        order: Int = 0,
        context: CadenceSidebarLists.ContextRef? = nil,
        contextID: UUID? = nil,
        openTaskCount: Int = 0
    ) -> CadenceSidebarLists.Item {
        CadenceSidebarLists.Item(
            id: UUID(),
            kind: kind,
            name: name,
            colorHex: "#4a9eff",
            order: order,
            contextID: contextID ?? context?.id,
            openTaskCount: openTaskCount
        )
    }

    // MARK: - Grouping

    @Test func sectionsFollowTheContextOrderTheyAreGivenNotTheOrderTheItemsArrivedIn() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work, home],
            items: [
                item("Chores", order: 0, context: home),
                item("Clients", order: 0, context: work)
            ]
        )

        #expect(sections.map(\.title) == ["Work", "Home"])
        #expect(sections[0].items.map(\.name) == ["Clients"])
        #expect(sections[1].items.map(\.name) == ["Chores"])
        #expect(sections[0].contextID == work.id)
    }

    /// The header carries no control of its own, so an empty one is a word over nothing.
    @Test func aContextWithNoListsGetsNoSection() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work, home],
            items: [item("Clients", context: work)]
        )

        #expect(sections.map(\.title) == ["Work"])
        #expect(CadenceSidebarLists.sections(contexts: [work, home], items: []).isEmpty)
    }

    /// macOS iterates contexts and never looks at the leftovers, so a list with no context is
    /// simply absent from that column. The iPad picker this replaces showed everything, so these
    /// rows get a trailing section rather than disappearing.
    @Test func listsWithNoContextLandInATrailingSectionRatherThanVanishing() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work],
            items: [
                item("Clients", context: work),
                item("Loose", contextID: nil),
                item("Orphan", contextID: UUID())   // context archived, or gone
            ]
        )

        #expect(sections.map(\.title) == ["Work", CadenceSidebarLists.ungroupedTitle])
        #expect(sections.last?.contextID == nil)
        #expect(Set(sections.last?.items.map(\.name) ?? []) == ["Loose", "Orphan"])
    }

    @Test func theTrailingSectionIsAbsentWhenEveryListHasALivingContext() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work],
            items: [item("Clients", context: work)]
        )

        #expect(sections.count == 1)
        #expect(sections.allSatisfy { $0.contextID != nil })
    }

    @Test func everySectionHasAStableDistinctIdentity() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work, home],
            items: [
                item("Clients", context: work),
                item("Chores", context: home),
                item("Loose", contextID: nil)
            ]
        )

        #expect(Set(sections.map(\.id)).count == sections.count)
        #expect(sections.last?.id == CadenceSidebarLists.Section.ungroupedID)
    }

    // MARK: - Ordering

    @Test func aSectionWhoseRowsAllHoldDistinctOrdersInterleavesAreasAndProjects() {
        let sorted = CadenceSidebarLists.sorted([
            item("Third", kind: .area, order: 2),
            item("First", kind: .project, order: 0),
            item("Second", kind: .area, order: 1)
        ])

        #expect(sorted.map(\.name) == ["First", "Second", "Third"])
    }

    /// The usual case: `Area.order` and `Project.order` are two sequences both numbered from zero,
    /// so a context holding one of each has two rows claiming slot 0. Interleaving them on a shared
    /// number would be arbitrary, so the kinds are kept apart — the rule
    /// `ContextSection.listEntries` already applies on macOS.
    @Test func aSectionWithCollidingOrdersPutsEveryAreaAheadOfEveryProject() {
        let sorted = CadenceSidebarLists.sorted([
            item("Project A", kind: .project, order: 0),
            item("Area B", kind: .area, order: 1),
            item("Project B", kind: .project, order: 1),
            item("Area A", kind: .area, order: 0)
        ])

        #expect(sorted.map(\.name) == ["Area A", "Area B", "Project A", "Project B"])
    }

    /// A partial order here is an unstable sort, which is a navigation column that reshuffles
    /// itself between renders — the failure `TaskOrdering.fallbackPrecedes` exists to prevent on
    /// task lists. Two rows that agree on order, kind *and* name must still have a winner.
    @Test func theOrderIsTotalSoEqualRowsStillHaveAWinner() {
        let a = CadenceSidebarLists.Item(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            kind: .area, name: "Same", colorHex: "#4a9eff", order: 0, contextID: nil
        )
        let b = CadenceSidebarLists.Item(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
            kind: .area, name: "Same", colorHex: "#4a9eff", order: 0, contextID: nil
        )

        #expect(CadenceSidebarLists.sorted([b, a]).map(\.id) == [a.id, b.id])
        #expect(CadenceSidebarLists.sorted([a, b]).map(\.id) == [a.id, b.id])
    }

    @Test func nameIsTheTieBreakBeforeIdentityAndIgnoresCase() {
        let sorted = CadenceSidebarLists.sorted([
            item("beta", kind: .area, order: 0),
            item("Alpha", kind: .area, order: 0)
        ])

        // Both hold order 0, so `hasGlobalOrder` is false and the name decides within the kind.
        #expect(sorted.map(\.name) == ["Alpha", "beta"])
    }

    @Test func sortingIsIdempotentAndPreservesEveryRow() {
        let items = [
            item("Clients", kind: .project, order: 3),
            item("Chores", kind: .area, order: 1),
            item("Admin", kind: .area, order: 1),
            item("Reading", kind: .project, order: 0)
        ]

        let once = CadenceSidebarLists.sorted(items)
        #expect(CadenceSidebarLists.sorted(once) == once)
        #expect(Set(once.map(\.id)) == Set(items.map(\.id)))
        #expect(CadenceSidebarLists.sorted([]).isEmpty)
    }
}
