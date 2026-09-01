import Foundation
import SwiftData
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
    /// number would be arbitrary, so the kinds are kept apart — the rule both sidebars now reach
    /// through `sections(...)`, macOS included since T-538.
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

    // MARK: - Grouping for a caller that keeps its own element type (T-538)

    /// macOS's rows drag and their drop delegate writes `order` back, so its section holds live
    /// `Area` / `Project` objects and cannot render a flattened `Item`. This stands in for one.
    private struct Row: Equatable {
        let handle: String
        let item: CadenceSidebarLists.Item
    }

    private func row(
        _ name: String,
        kind: CadenceSidebarLists.Kind = .area,
        order: Int = 0,
        context: CadenceSidebarLists.ContextRef? = nil,
        contextID: UUID? = nil
    ) -> Row {
        Row(
            handle: name,
            item: item(name, kind: kind, order: order, context: context, contextID: contextID)
        )
    }

    /// **The whole of T-538.** Before this overload existed, macOS could not call `sections` at all
    /// — it renders model objects — so it grouped by iterating each `Context`'s own relationship,
    /// and a list with no context was reached by no iteration. Not un-grouped: *absent*.
    @Test func aSectionCallerHoldingModelObjectsStillGetsTheCatchAllForItsContextLessRows() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work],
            elements: [
                row("Clients", context: work),
                row("Loose", contextID: nil),
                row("Orphan", contextID: UUID())   // context archived, or never offered
            ],
            keepingEmptyContexts: true,
            item: \.item
        )

        #expect(sections.map(\.title) == ["Work", CadenceSidebarLists.ungroupedTitle])
        #expect(sections.last?.contextID == nil)
        #expect(Set(sections.last?.elements.map(\.handle) ?? []) == ["Loose", "Orphan"])
        // Nothing the caller handed in is drawn twice, and nothing is dropped.
        #expect(sections.flatMap(\.elements).map(\.handle).sorted() == ["Clients", "Loose", "Orphan"])
    }

    /// The one thing the two columns legitimately differ on. The macOS header carries the "+" that
    /// opens `CreateListSheet` — the only way to make a list in a given context there — so a
    /// context with no lists yet must keep its section or it becomes unusable. iPad's header
    /// carries no control, so an empty one there is a word over nothing.
    @Test func anEmptyContextKeepsItsSectionOnlyForACallerThatAsksToKeepIt() {
        let kept = CadenceSidebarLists.sections(
            contexts: [work, home],
            elements: [row("Clients", context: work)],
            keepingEmptyContexts: true,
            item: \.item
        )
        #expect(kept.map(\.title) == ["Work", "Home"])
        #expect(kept.last?.elements.isEmpty == true)

        let dropped = CadenceSidebarLists.sections(
            contexts: [work, home],
            elements: [row("Clients", context: work)],
            keepingEmptyContexts: false,
            item: \.item
        )
        #expect(dropped.map(\.title) == ["Work"])
    }

    /// `keepingEmptyContexts` is about *contexts*. The catch-all draws a "+" on macOS since T-559,
    /// but it only pre-selects "No context" in a sheet every other header reaches too, so an empty
    /// one is still a word over nothing.
    @Test func theCatchAllIsNeverKeptEmptyEvenWhereEmptyContextsAre() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work, home],
            elements: [row("Clients", context: work)],
            keepingEmptyContexts: true,
            item: \.item
        )

        #expect(sections.allSatisfy { $0.contextID != nil })
        #expect(sections.map(\.id).contains(CadenceSidebarLists.Section.ungroupedID) == false)
    }

    /// The flattened overload is not a second implementation — it is this one with `Element` filled
    /// in. A drift between the two is the T-333/T-538 defect re-committed, so it is pinned.
    @Test func theFlattenedSectionsAreTheGenericOnesWithNothingChanged() {
        let items = [
            item("Clients", kind: .project, order: 1, context: work),
            item("Admin", kind: .area, order: 1, context: work),
            item("Chores", context: home),
            item("Loose", contextID: nil)
        ]

        let flattened = CadenceSidebarLists.sections(contexts: [work, home], items: items)
        let generic = CadenceSidebarLists.sections(
            contexts: [work, home],
            elements: items,
            keepingEmptyContexts: false,
            item: { $0 }
        )

        #expect(flattened.map(\.title) == generic.map(\.title))
        #expect(flattened.map(\.contextID) == generic.map(\.contextID))
        #expect(flattened.map(\.id) == generic.map(\.id))
        #expect(flattened.map { $0.items } == generic.map { $0.elements })
        #expect(flattened.count == 3)
    }

    /// Rows arrive ordered, so the caller does not sort again — a second rule in front of the
    /// shared one is exactly what T-333 removed from `ContextSection`.
    @Test func rowsInsideAGenericSectionCarryTheSharedOrderingAlready() {
        let sections = CadenceSidebarLists.sections(
            contexts: [work],
            elements: [
                row("Project A", kind: .project, order: 0, context: work),
                row("Area B", kind: .area, order: 1, context: work),
                row("Project B", kind: .project, order: 1, context: work),
                row("Area A", kind: .area, order: 0, context: work)
            ],
            keepingEmptyContexts: true,
            item: \.item
        )

        #expect(sections.first?.elements.map(\.handle) == ["Area A", "Area B", "Project A", "Project B"])
    }

    /// `item` walks a SwiftData relationship on macOS — the open-task tally — so calling it in the
    /// bucketing loop and again inside the sort would double that walk for every row on every
    /// render. It is evaluated exactly once per element.
    @Test func theFlatteningClosureIsEvaluatedOncePerRowNotOncePerPhase() {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let rows = [
            row("Clients", order: 1, context: work),
            row("Admin", order: 0, context: work),
            row("Chores", context: home),
            row("Loose", contextID: nil)
        ]

        let sections = CadenceSidebarLists.sections(
            contexts: [work, home],
            elements: rows,
            keepingEmptyContexts: true
        ) { element in
            counter.calls += 1
            return element.item
        }

        #expect(sections.flatMap(\.elements).count == rows.count)
        #expect(counter.calls == rows.count)
    }

    // MARK: - The model bridge (T-538)

    private func makeModelContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    /// **The narrowing that made the state undrawable.** macOS's flattener took the context id as a
    /// non-optional parameter, which the caller filled in from whichever `Context` it was
    /// iterating; `Area.context` is optional and iOS writes `nil` there from its "None" row. There
    /// is no parameter to fill in now — the one bridge reads the optional the model declares.
    @Test func theSidebarBridgeCarriesAnAbsentContextThroughAsAbsent() throws {
        let modelContext = try makeModelContext()
        let filed = Area(name: "Filed")
        let loose = Area(name: "Loose")
        let context = Context(name: "Work")
        filed.context = context
        for model in [filed, loose] { modelContext.insert(model) }
        modelContext.insert(context)
        try modelContext.save()

        #expect(CadenceSidebarLists.Item(filed).contextID == context.id)
        #expect(CadenceSidebarLists.Item(loose).contextID == nil)
        #expect(loose.context == nil)
    }

    /// The same for a project, and its due date, which is the field the two platforms' copies of
    /// this bridge could most easily have disagreed about.
    @Test func theSidebarBridgeCarriesAProjectsAbsentContextAndAbsentDueDateThroughAsAbsent() throws {
        let modelContext = try makeModelContext()
        let loose = Project(name: "Loose")
        let dated = Project(name: "Dated")
        dated.dueDate = "2026-08-31"
        for model in [loose, dated] { modelContext.insert(model) }
        try modelContext.save()

        #expect(CadenceSidebarLists.Item(loose).contextID == nil)
        #expect(CadenceSidebarLists.Item(loose).dueDateKey == nil)
        #expect(CadenceSidebarLists.Item(dated).dueDateKey == "2026-08-31")
        #expect(CadenceSidebarLists.Item(loose).kind == .project)
    }

    /// Bridge and grouping together, on live models, which is exactly the call `SidebarView` makes:
    /// the context-less area and the area inside an archived context both reach a section, and the
    /// section they reach is the catch-all.
    @Test func aContextLessListAndAnArchivedContextsListBothReachTheCatchAllFromLiveModels() throws {
        let modelContext = try makeModelContext()
        let live = Context(name: "Work")
        let retired = Context(name: "Old")
        retired.isArchived = true
        let filed = Area(name: "Clients")
        filed.context = live
        let stranded = Area(name: "Stranded")
        stranded.context = retired
        let loose = Project(name: "Loose")
        for model in [live, retired] { modelContext.insert(model) }
        for model in [filed, stranded] { modelContext.insert(model) }
        modelContext.insert(loose)
        try modelContext.save()

        let sections = CadenceSidebarLists.sections(
            contexts: [live].map { CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name) },
            elements: [CadenceSidebarLists.Item(filed), CadenceSidebarLists.Item(stranded),
                       CadenceSidebarLists.Item(loose)],
            keepingEmptyContexts: true,
            item: { $0 }
        )

        #expect(sections.map(\.title) == ["Work", CadenceSidebarLists.ungroupedTitle])
        #expect(sections.first?.elements.map(\.name) == ["Clients"])
        #expect(Set(sections.last?.elements.map(\.name) ?? []) == ["Loose", "Stranded"])
    }

    // MARK: - The macOS column reads the shared rule (T-538)

    /// `SidebarView.listSections` is private to a SwiftUI view, so this is a scan. What it pins is
    /// the *mechanism*: the region is derived from flat queries through the shared bucketer, not by
    /// iterating contexts — which is the shape that could not reach a context-less list at all.
    @Test func theMacSidebarDerivesItsListRegionThroughTheSharedBucketerRatherThanByIteratingContexts() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarView.swift")
        let column = CadenceSourceScan.strippingComments(raw)

        // Non-vacuity: the file was read, and it is still the file this test is about.
        #expect(column != raw)
        #expect(column.contains("struct SidebarView: View {"))

        #expect(column.contains("CadenceSidebarLists.sections("))
        #expect(column.contains("keepingEmptyContexts: true"))
        #expect(column.contains("@Query private var areas: [Area]"))
        #expect(column.contains("@Query private var projects: [Project]"))

        // The pre-T-538 spelling: a region built by walking the context list.
        #expect(CadenceSourceScan.matchCount("ForEach\\(\\s*contexts", in: column) == 0)
    }

    /// And the section itself no longer derives rows. Absence of the iteration upstream is not
    /// presence of the rule: a section handed a `Context` could re-read the relationship and put
    /// the old behaviour straight back underneath a correct-looking caller.
    @Test func theMacContextSectionIsHandedItsRowsRatherThanReadingThemOffAContext() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarComponents.swift")
        let components = CadenceSourceScan.strippingComments(raw)

        #expect(components != raw)
        #expect(components.contains("struct ContextSection: View {"))

        #expect(components.contains("let entries: [SidebarListEntry]"))
        // Non-optional since T-559: the catch-all header carries a "+" too, now that
        // `CreateListSheet` can be opened on no context at all.
        #expect(components.contains("let onAddList: () -> Void"))
        #expect(components.contains("var sidebarListItem: CadenceSidebarLists.Item"))

        // The three pre-T-538 spellings, each of which reintroduces the defect on its own.
        #expect(CadenceSourceScan.matchCount("context\\.(areas|projects)", in: components) == 0)
        #expect(CadenceSourceScan.matchCount("sidebarListItem\\(contextID:", in: components) == 0)
        #expect(CadenceSourceScan.matchCount("var context: Context\\b", in: components) == 0)
    }
}
