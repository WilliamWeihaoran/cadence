import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// **T-287: the `~` list-search panel, once.**
///
/// It was written out twice on macOS — `TaskTitleEntryField` and `QuickCreateChoicePopover`, five
/// members each under the same five names — and the copies had drifted where duplicates always do:
/// the popover's had no Escape and no backspace-out, so the only way out of it was to pick a list.
/// The behavioural tests below pin the extracted halves; the source scans pin that the hosts read
/// them, because a behavioural test of a shared helper stays green while a call site quietly keeps
/// its own copy — which is the defect shape T-374 exists for.
@MainActor
struct CadenceTildeContainerPickerTests {

    private static let titleFieldPath = "Cadence/macOS/Views/TaskTitleEntryField.swift"
    private static let quickCreatePath = "Cadence/macOS/Views/QuickCreateChoicePopover.swift"
    private static let sharedPanelPath = "Cadence/macOS/Views/TildeContainerPicker.swift"

    // MARK: - Fixture

    private struct ListFixture {
        let contexts: [Context]
        let areas: [Area]
        let projects: [Project]
        let modelContext: ModelContext
        let sectionedProject: Project
        /// `contexts` minus Home, for the tests that ask what happens to a list whose context is
        /// real but was not handed to the panel.
        let workOnly: [Context]
    }

    /// Two contexts so the per-context grouping is observable, and one archived list of each kind
    /// so "active only" is observable. Orders are inserted counter to the array order so a result
    /// in `order` cannot be confused for a result in insertion order.
    ///
    /// **Three of the lists have no context at all (T-558)**, one of them archived, because the
    /// panel used to drop every one of them: the body iterated contexts, so `context == nil`
    /// matched no iteration and was appended nowhere. Garage is ordered 5 rather than 0 so the
    /// unfiled bucket's own ordering is distinguishable from the per-context one — with Garage at
    /// 0 the "offer every context" and "offer only Work" results happen to coincide, and a test
    /// that cannot tell them apart is green against the bug it exists for.
    private func makeListFixture() throws -> ListFixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        work.order = 0
        let home = Context(name: "Home")
        home.order = 1

        let operations = Area(name: "Operations", context: work)
        operations.order = 2
        let admin = Area(name: "Admin", context: work)
        admin.order = 1
        let retired = Area(name: "Archive Me", context: work)
        retired.order = 0
        retired.status = .archived

        let cadence = Project(name: "Cadence", context: work)
        cadence.order = 1
        cadence.sectionNames = ["Build", "Ship"]
        let shelved = Project(name: "Shelved", context: work)
        shelved.order = 0
        shelved.status = .archived

        let garage = Area(name: "Garage", context: home)
        garage.order = 5

        // No context at all — the state iOS's list editor writes from its "None" row, in new and
        // edit mode alike, and the one the Mac now makes too.
        let looseEnds = Area(name: "Loose Ends")
        looseEnds.order = 3
        let lost = Area(name: "Lost")
        lost.order = 4
        lost.status = .archived
        let stray = Project(name: "Stray")
        stray.order = 2

        for model in [work, home] { modelContext.insert(model) }
        for model in [operations, admin, retired, garage, looseEnds, lost] { modelContext.insert(model) }
        for model in [cadence, shelved, stray] { modelContext.insert(model) }
        try modelContext.save()

        return ListFixture(
            contexts: [work, home],
            areas: [operations, admin, retired, garage, looseEnds, lost],
            projects: [cadence, shelved, stray],
            modelContext: modelContext,
            sectionedProject: cadence,
            workOnly: [work]
        )
    }

    private func names(query: String, _ fixture: ListFixture) -> [String] {
        names(query: query, offering: fixture.contexts, fixture)
    }

    private func names(
        query: String,
        offering contexts: [Context],
        holding selection: TaskContainerSelection? = nil,
        _ fixture: ListFixture
    ) -> [String] {
        TildeContainerPickerSupport.flatContainers(
            query: query,
            contexts: contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: selection
        )
        .map(\.name)
    }

    private func names(holding selection: TaskContainerSelection?, _ fixture: ListFixture) -> [String] {
        names(query: "", offering: fixture.contexts, holding: selection, fixture)
    }

    // MARK: - The list both panels show

    /// Inbox first, then each context's active areas in `order`, then its active projects in
    /// `order`, then the next context. Archived lists of either kind are absent.
    @Test func theTildeListIsInboxThenEachContextsActiveAreasThenItsActiveProjects() throws {
        let fixture = try makeListFixture()

        #expect(
            names(query: "", fixture)
                == ["Inbox", "Admin", "Operations", "Cadence", "Garage", "Loose Ends", "Stray"]
        )
    }

    /// **T-558.** A list with no context is offered, after every context's, areas before projects
    /// and each in `order` — and the archived one of them is still absent, so the trailing bucket
    /// is the same filter as the rest of the panel rather than an unguarded `append`.
    @Test func theTildeListEndsWithTheListsThatBelongToNoOfferedContext() throws {
        let fixture = try makeListFixture()

        let offered = names(query: "", fixture)
        #expect(offered.suffix(2) == ["Loose Ends", "Stray"])
        #expect(offered.contains("Lost") == false)
    }

    /// Keyed on the **offered** contexts, not on `context == nil`. Home's list is filed and active;
    /// a panel that was not handed Home has no heading for it either way, and dropping it would be
    /// the same defect with a different cause. Garage sorts after Loose Ends here and before it in
    /// the test above, which is what makes the two results distinguishable.
    @Test func aListWhoseContextWasNotOfferedJoinsTheSameTrailingBucket() throws {
        let fixture = try makeListFixture()

        #expect(
            names(query: "", offering: fixture.workOnly, fixture)
                == ["Inbox", "Admin", "Operations", "Cadence", "Loose Ends", "Garage", "Stray"]
        )
    }

    /// The query narrows the trailing bucket exactly as it narrows the rest — "lo" reaches the
    /// active unfiled area and not the archived one beside it.
    @Test func theTildeQueryPrefixMatchesInsideTheTrailingBucketToo() throws {
        let fixture = try makeListFixture()

        #expect(names(query: "lo", fixture) == ["Loose Ends"])
        #expect(names(query: "st", fixture) == ["Stray"])
        #expect(names(query: "loose e", fixture) == ["Loose Ends"])
    }

    /// **Prefix, not `contains`.** "ad" finds Admin; "min", which is inside it, finds nothing —
    /// and the empty query is the only thing that shows everything.
    @Test func theTildeListPrefixMatchesTheQueryCaseInsensitively() throws {
        let fixture = try makeListFixture()

        #expect(names(query: "ad", fixture) == ["Admin"])
        #expect(names(query: "AD", fixture) == ["Admin"])
        #expect(names(query: "min", fixture).isEmpty)
        #expect(names(query: "in", fixture) == ["Inbox"])
        #expect(names(query: "zzz", fixture).isEmpty)
    }

    // MARK: - T-684: the list the draft is already in

    /// **T-534's first defect, on the last list-offering surface that had not learned it.**
    ///
    /// `flatContainers` filtered on `isActive` alone and took no selection at all, while the panel
    /// it feeds *is* handed one for the checkmark — so a draft already filed in an archived list
    /// got a panel that could highlight a row it would not draw, and the one correction the user
    /// needed was the one row missing. Each archived list is named rather than counted: an
    /// assertion that some archived row came back cannot tell which.
    @Test func theTildeListKeepsTheArchivedListTheDraftIsAlreadyIn() throws {
        let fixture = try makeListFixture()
        let archivedArea = try #require(fixture.areas.first { $0.name == "Archive Me" })
        let archivedProject = try #require(fixture.projects.first { $0.name == "Shelved" })

        // Nothing assigned: the retirement rule stands, exactly as before.
        #expect(names(holding: nil, fixture).contains("Archive Me") == false)
        #expect(names(holding: nil, fixture).contains("Shelved") == false)
        #expect(names(holding: .inbox, fixture).contains("Archive Me") == false)

        // Assigned: that one row is drawn, in its own context's run, and no other retired list
        // comes back with it.
        let holdingArea = names(holding: .area(archivedArea.id), fixture)
        #expect(
            holdingArea
                == ["Inbox", "Archive Me", "Admin", "Operations", "Cadence", "Garage", "Loose Ends", "Stray"]
        )

        let holdingProject = names(holding: .project(archivedProject.id), fixture)
        #expect(
            holdingProject
                == ["Inbox", "Admin", "Operations", "Shelved", "Cadence", "Garage", "Loose Ends", "Stray"]
        )
    }

    /// The same rule inside the trailing bucket, which is where T-558 put the context-less lists.
    /// "Lost" is archived *and* has no context, so a panel that applied the selection only to the
    /// per-context runs would still refuse to draw it.
    @Test func theTildeListKeepsAnArchivedContextLessListTheDraftIsAlreadyIn() throws {
        let fixture = try makeListFixture()
        let lost = try #require(fixture.areas.first { $0.name == "Lost" })

        #expect(names(holding: nil, fixture).contains("Lost") == false)
        #expect(
            names(holding: .area(lost.id), fixture)
                == ["Inbox", "Admin", "Operations", "Cadence", "Garage", "Loose Ends", "Lost", "Stray"]
        )
    }

    /// **The panel cannot highlight a row it will not draw.** The checkmark and the rows are one
    /// question asked twice, so they are answered from the same value — the assertion the
    /// selection-less signature made unprovable.
    @Test func everySelectionTheTildePanelWouldCheckIsARowTheTildeListOffers() throws {
        let fixture = try makeListFixture()

        var selections: [TaskContainerSelection] = [.inbox]
        selections += fixture.areas.map { .area($0.id) }
        selections += fixture.projects.map { .project($0.id) }
        #expect(selections.count == 10)

        for selection in selections {
            let items = TildeContainerPickerSupport.flatContainers(
                query: "",
                contexts: fixture.contexts,
                areas: fixture.areas,
                projects: fixture.projects,
                selection: selection
            )
            #expect(
                items.contains { $0.tag == selection },
                "the panel would check \(selection) and draw no row for it"
            )
        }
    }

    /// And the query still narrows it: a selection re-admits one list, it does not defeat search.
    @Test func theTildeQueryStillNarrowsTheListTheDraftIsAlreadyIn() throws {
        let fixture = try makeListFixture()
        let archivedArea = try #require(fixture.areas.first { $0.name == "Archive Me" })

        #expect(
            names(query: "arch", offering: fixture.contexts, holding: .area(archivedArea.id), fixture)
                == ["Archive Me"]
        )
        #expect(
            names(query: "ad", offering: fixture.contexts, holding: .area(archivedArea.id), fixture)
                == ["Admin"]
        )
    }

    /// Both hosts hand the panel's list the same selection they hand the panel, so the two halves
    /// cannot disagree at the call site either.
    @Test func bothMacOSTildeHostsHandTheSameSelectionToTheRowsAndToTheCheckmark() throws {
        for (path, expression) in [
            (Self.titleFieldPath, "containerSelection?.wrappedValue"),
            (Self.quickCreatePath, "selectedContainer")
        ] {
            let raw = try cadenceTestSource(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(code != raw, "\(path): the comment stripper removed nothing")
            // A computed property, so the brace matcher is reached directly — `functionBody`
            // needs a `(` it does not have.
            let declaration = try #require(
                code.range(of: "var tildeListSearchView"),
                "no tildeListSearchView in \(path)"
            )
            let body = try #require(
                CadenceSourceScan.matchedBody(
                    after: declaration.upperBound,
                    in: code,
                    open: "{",
                    close: "}"
                ),
                "tildeListSearchView never balances in \(path)"
            )
            #expect(CadenceSourceScan.matchCount("selection: \(NSRegularExpression.escapedPattern(for: expression))", in: body) == 2,
                    "\(path) does not pass \(expression) to both halves")
        }
    }

    // MARK: - What committing a choice means

    /// The half the ticket calls "the silent `normalizeSelectedSection()` that both must perform" —
    /// section names belong to a container, so moving the draft has to move the section too.
    @Test func committingATildeChoiceCarriesTheSectionNameIntoTheChosenContainer() throws {
        let fixture = try makeListFixture()
        var container: TaskContainerSelection = .project(fixture.sectionedProject.id)
        var sectionName = "Ship"

        // Into a project that has the section: the name survives.
        TildeContainerPickerSupport.applySelection(
            .project(fixture.sectionedProject.id),
            container: Binding(get: { container }, set: { container = $0 }),
            sectionName: Binding(get: { sectionName }, set: { sectionName = $0 }),
            areas: fixture.areas,
            projects: fixture.projects
        )
        #expect(sectionName == "Ship")

        // Into the Inbox, which has only the default column: the stale name is replaced.
        TildeContainerPickerSupport.applySelection(
            .inbox,
            container: Binding(get: { container }, set: { container = $0 }),
            sectionName: Binding(get: { sectionName }, set: { sectionName = $0 }),
            areas: fixture.areas,
            projects: fixture.projects
        )
        #expect(container == .inbox)
        #expect(sectionName == TaskSectionDefaults.defaultName)
    }

    /// A composer with no section picker passes `nil`, and must not be handed one.
    @Test func committingATildeChoiceWithoutASectionBindingOnlyMovesTheContainer() throws {
        let fixture = try makeListFixture()
        var container: TaskContainerSelection = .inbox

        TildeContainerPickerSupport.applySelection(
            .project(fixture.sectionedProject.id),
            container: Binding(get: { container }, set: { container = $0 }),
            sectionName: nil,
            areas: fixture.areas,
            projects: fixture.projects
        )

        #expect(container == .project(fixture.sectionedProject.id))
    }

    // MARK: - That the hosts actually read it

    /// The instrument for "this file builds its own `~` container list".
    private func ownListInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "own tilde container list",
            fires: """
            private var tildeFlatContainers: [TildeContainerItem] {
                var result: [TildeContainerItem] = []
                return result
            }
            """,
            // The nearest miss: a file that *reads* the shared list mentions the same word stem in
            // the same expression position. A detector matching the bare name fires on both.
            andNotOn: """
            items: TildeContainerPickerSupport.flatContainers(
                query: tildeSearchQuery,
                contexts: contexts,
                areas: areas,
                projects: projects
            )
            """,
            by: { source in
                CadenceSourceScan.matchCount(
                    "(?:var|func)\\s+tildeFlatContainers\\b",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )
    }

    /// **The consolidation, stated as an absence over the whole app.**
    ///
    /// Scoped to the app rather than to the two known files, because "there are two of these" is a
    /// shape and a third would be filed the same way the second was.
    @Test func noAppSourceBuildsItsOwnTildeContainerList() throws {
        let offenders = try ownListInstrument().sweep(
            try cadenceAppSwiftFiles(),
            atLeast: 300,
            including: Self.titleFieldPath,
            read: cadenceTestSource
        )

        #expect(offenders.isEmpty, "a second `~` container list has appeared: \(offenders)")
    }

    /// The item type, once. An absence test alone is happy with two panels that each declare their
    /// own item struct and never say `tildeFlatContainers`.
    @Test func theTildeContainerItemTypeIsDeclaredInExactlyOnePlace() throws {
        let instrument = try CadenceScanInstrument(
            "tilde container item declaration",
            fires: "struct TildeContainerItem: Identifiable {\n    let tag: TaskContainerSelection\n}",
            andNotOn: "let items: [TildeContainerItem] = TildeContainerPickerSupport.flatContainers()",
            by: { source in
                CadenceSourceScan.matchCount(
                    "struct\\s+\\w*TildeContainerItem\\b",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )

        let declarations = try instrument.sweep(
            try cadenceAppSwiftFiles(),
            atLeast: 300,
            including: Self.sharedPanelPath,
            read: cadenceTestSource
        )

        #expect(declarations == [Self.sharedPanelPath])
    }

    /// **The other direction, and the one that makes reverting a call site fail.**
    ///
    /// The two absence tests above stay green on a host that deleted its panel and shows nothing at
    /// all. This one names the hosts and requires each to construct `TildeContainerPicker` — so
    /// putting either file's own panel back fails `noAppSourceBuildsItsOwnTildeContainerList`, and
    /// pointing either host at anything else fails this.
    @Test func bothMacOSTildeHostsRenderTheSharedContainerPicker() throws {
        let instrument = try CadenceScanInstrument(
            "renders TildeContainerPicker",
            fires: "        TildeContainerPicker(\n            query: $tildeSearchQuery,\n        )",
            // The nearest miss by a wide margin: three other symbols share the prefix, and two of
            // them are things a host legitimately says.
            andNotOn: """
            TildeContainerPickerRow(icon: item.icon, name: item.name)
            TildeContainerPickerSupport.flatContainers(query: query)
            let item = TildeContainerItem(tag: .inbox)
            """,
            by: { source in
                CadenceSourceScan.matchCount(
                    "\\bTildeContainerPicker\\s*\\(",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )

        let hosts = try instrument.sweep(
            try cadenceAppSwiftFiles(),
            atLeast: 300,
            including: Self.quickCreatePath,
            read: cadenceTestSource
        )

        #expect(hosts == [Self.quickCreatePath, Self.titleFieldPath].sorted())
    }

    /// Both hosts commit through the shared helper, so the section renormalisation cannot be
    /// fixed in one copy only — which is the half the ticket singles out.
    @Test func bothMacOSTildeHostsCommitThroughTheSharedSelectionHelper() throws {
        for path in [Self.titleFieldPath, Self.quickCreatePath] {
            let raw = try cadenceTestSource(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(code != raw)
            let body = try #require(
                CadenceSourceScan.functionBody(named: "selectTildeContainerItem", in: code),
                "no selectTildeContainerItem in \(path)"
            )
            #expect(body.contains("TildeContainerPickerSupport.applySelection"))
            // The four open-coded lines it replaced.
            #expect(!body.contains("caseInsensitiveCompare"))
        }
    }
}
