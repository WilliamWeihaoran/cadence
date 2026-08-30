#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Covers the container picker's search-and-highlight contract — the part `ContainerPickerBadge`
/// and the kanban card's list chip now share through `ContainerPickerPopoverContent`. The keyboard
/// path (type a prefix, arrow down, Enter) has been the historical source of bugs here, so it is
/// exercised end to end against the same helpers the view calls.
@MainActor
struct ContainerPickerFilterSupportTests {

    private struct Fixture {
        let contexts: [Context]
        let areas: [Area]
        let projects: [Project]
    }

    private func makeFixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        work.order = 0
        let personal = Context(name: "Personal")
        personal.order = 1
        modelContext.insert(work)
        modelContext.insert(personal)

        let design = Area(name: "Design", context: work)
        design.order = 0
        let deployment = Area(name: "Deployment", context: work)
        deployment.order = 1
        let errands = Area(name: "Errands", context: personal)
        errands.order = 0
        let archived = Area(name: "Defunct", context: work)
        archived.status = .archived
        archived.order = 2
        let delta = Project(name: "Delta Launch", context: work)
        delta.order = 0
        for area in [design, deployment, errands, archived] { modelContext.insert(area) }
        modelContext.insert(delta)

        return Fixture(
            contexts: [work, personal],
            areas: [design, deployment, errands, archived],
            projects: [delta]
        )
    }

    // MARK: - matching

    @Test func matchingIsCaseInsensitivePrefixOnly() {
        #expect(ContainerPickerFilterSupport.matches("Design", query: "DES"))
        #expect(ContainerPickerFilterSupport.matches("Design", query: ""))
        #expect(!ContainerPickerFilterSupport.matches("Design", query: "sign"))
    }

    @Test func inboxParticipatesInTheSameSearch() {
        #expect(ContainerPickerFilterSupport.matchesInbox(query: "in"))
        #expect(ContainerPickerFilterSupport.matchesInbox(query: ""))
        #expect(!ContainerPickerFilterSupport.matchesInbox(query: "de"))
    }

    // MARK: - grouping

    @Test func groupingKeepsContextOrderAndDropsInactiveLists() throws {
        let fixture = try makeFixture()
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )

        #expect(groups.map(\.title) == ["Work", "Personal"])
        #expect(groups[0].areas.map(\.name) == ["Design", "Deployment"])
        #expect(groups[0].projects.map(\.name) == ["Delta Launch"])
        #expect(groups[1].areas.map(\.name) == ["Errands"])
    }

    @Test func groupsWithNoMatchesDropOut() throws {
        let fixture = try makeFixture()
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: "de"
        )

        #expect(groups.map(\.title) == ["Work"])
    }

    // MARK: - keyboard selection

    @Test func filteringThenArrowingDownThenEnterSelectsTheHighlightedItem() throws {
        let fixture = try makeFixture()
        let query = "de"
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: query
        )
        let selections = ContainerPickerFilterSupport.flatSelections(
            inGroups: groups,
            includingInbox: ContainerPickerFilterSupport.matchesInbox(query: query)
        )

        let design = try #require(fixture.areas.first { $0.name == "Design" })
        let deployment = try #require(fixture.areas.first { $0.name == "Deployment" })
        let delta = try #require(fixture.projects.first { $0.name == "Delta Launch" })
        // "Inbox" does not start with "de", so the first row is a real list.
        #expect(selections == [.area(design.id), .area(deployment.id), .project(delta.id)])

        // A fresh query starts the highlight at the first row.
        var highlightIdx = 0
        #expect(ContainerPickerFilterSupport.highlighted(at: highlightIdx, in: selections) == .area(design.id))

        // Enter commits whatever the highlight names — the checkmark and the commit read the same
        // value, which is why the rows carry no separate "selected" state.
        highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: 1, count: selections.count)
        let committed = ContainerPickerFilterSupport.highlighted(at: highlightIdx, in: selections)
        #expect(committed == .area(deployment.id))
    }

    @Test func arrowingPastTheEndStopsOnTheLastRow() throws {
        let fixture = try makeFixture()
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: "de"
        )
        let selections = ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: false)
        let delta = try #require(fixture.projects.first { $0.name == "Delta Launch" })

        var highlightIdx = 0
        for _ in 0..<10 {
            highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: 1, count: selections.count)
        }
        #expect(ContainerPickerFilterSupport.highlighted(at: highlightIdx, in: selections) == .project(delta.id))
    }

    @Test func aQueryThatMatchesNothingHasNoHighlight() throws {
        let fixture = try makeFixture()
        let query = "zzz"
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: query
        )
        let selections = ContainerPickerFilterSupport.flatSelections(
            inGroups: groups,
            includingInbox: ContainerPickerFilterSupport.matchesInbox(query: query)
        )

        #expect(selections.isEmpty)
        #expect(ContainerPickerFilterSupport.highlighted(at: 0, in: selections) == nil)
    }

    @Test func inboxLeadsTheFlatOrderWhenItMatches() throws {
        let fixture = try makeFixture()
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        let selections = ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: true)

        #expect(selections.first == .inbox)
        #expect(ContainerPickerFilterSupport.highlighted(at: 0, in: selections) == .inbox)
    }

    // MARK: - lists that belong to no offered context

    /// **T-534, second defect.** The grouping is `contexts.compactMap { … }`, so a list whose
    /// `context` is `nil` is reached by no iteration and appears under no heading — not hidden,
    /// *absent*. `Area.context` and `Project.context` both default to `nil` and iOS's list editor
    /// offers a "None" context row in every mode, so this is a list a shipping surface can make,
    /// syncing to a Mac that then cannot file anything into it.
    @Test func aListWithNoContextIsStillOfferedByTheContainerPicker() throws {
        let fixture = try makeFixture()
        let loose = Area(name: "Reading")
        let looseProject = Project(name: "Rewrite")

        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas + [loose],
            projects: fixture.projects + [looseProject],
            selection: .inbox,
            query: ""
        )
        let selections = ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: false)

        #expect(selections.contains(.area(loose.id)))
        #expect(selections.contains(.project(looseProject.id)))
    }

    /// The same hole reached the other way: a list whose context exists but is not among the ones
    /// the picker was handed. `CadenceSidebarLists.sections` already treats both as one case, which
    /// is why the catch-all is keyed on the offered set rather than on `context == nil`.
    @Test func aListWhoseContextIsNotAmongTheOfferedOnesIsStillOffered() throws {
        let fixture = try makeFixture()
        let unlisted = Context(name: "Retired")
        let stranded = Area(name: "Stranded", context: unlisted)

        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas + [stranded],
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        let selections = ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: false)

        #expect(selections.contains(.area(stranded.id)))
    }

    // MARK: - the list a task is already in

    /// **T-534's headline.** The filter was `$0.isActive`, so a task filed in an archived list got
    /// a popover with no row for where it is — the one row it needs in order to be moved out.
    /// `ContainerPickerBadge.label` resolved unfiltered all along, so the chip named the list
    /// correctly and then opened a picker that did not list it.
    ///
    /// The two halves are asserted against each other on purpose: the archived list stays out of a
    /// picker opened on something else, and appears in one opened on itself. A fix that simply
    /// stopped filtering would pass the second and fail the first.
    @Test func theContainerPickerKeepsARowForTheArchivedListATaskIsAlreadyIn() throws {
        let fixture = try makeFixture()
        let defunct = try #require(fixture.areas.first { $0.name == "Defunct" })
        #expect(defunct.status == .archived)

        let elsewhere = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        #expect(!ContainerPickerFilterSupport
            .flatSelections(inGroups: elsewhere, includingInbox: false)
            .contains(.area(defunct.id)))

        let onIt = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .area(defunct.id),
            query: ""
        )
        #expect(ContainerPickerFilterSupport
            .flatSelections(inGroups: onIt, includingInbox: false)
            .contains(.area(defunct.id)))
        // Under its own context, not swept into the catch-all: it has a context, it is just retired.
        #expect(onIt.first { group in group.areas.contains { $0.id == defunct.id } }?.title == "Work")
    }

    /// The other array, and the state a `Context`-shaped rule would have got wrong: `Project` is
    /// offerable only while `active`, so a **completed** project is as retired as an archived one
    /// and equally still shown when it is where the task is.
    @Test func theContainerPickerKeepsARowForTheCompletedProjectATaskIsAlreadyIn() throws {
        let fixture = try makeFixture()
        let work = try #require(fixture.contexts.first { $0.name == "Work" })
        let wrapUp = Project(name: "Delta Wrapup", context: work)
        wrapUp.status = .done
        wrapUp.order = 1
        let projects = fixture.projects + [wrapUp]

        let elsewhere = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: projects,
            selection: .inbox,
            query: ""
        )
        #expect(!ContainerPickerFilterSupport
            .flatSelections(inGroups: elsewhere, includingInbox: false)
            .contains(.project(wrapUp.id)))

        let onIt = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: projects,
            selection: .project(wrapUp.id),
            query: ""
        )
        #expect(ContainerPickerFilterSupport
            .flatSelections(inGroups: onIt, includingInbox: false)
            .contains(.project(wrapUp.id)))
    }

    /// A selection naming a list that is no longer in the store adds no row: `selectable` answers
    /// "is this one already assigned", not "does this id mean anything", and `normalizedContainer`
    /// owns the second question.
    @Test func anIdentifierForADeletedListAddsNoRowToTheContainerPicker() throws {
        let fixture = try makeFixture()
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .area(UUID()),
            query: ""
        )

        #expect(groups.map(\.title) == ["Work", "Personal"])
        #expect(groups[0].areas.map(\.name) == ["Design", "Deployment"])
    }

    /// The catch-all is a heading the app already draws, with the wording it already uses on the
    /// iPad sidebar — and it is drawn only when something is in it, because the header carries no
    /// control of its own and an empty one would be a word over nothing.
    @Test func theCatchAllHeadingIsTheOneTheSidebarAlreadyUsesAndOnlyAppearsWhenItHolds() throws {
        let fixture = try makeFixture()
        let loose = Area(name: "Reading")

        let withALooseList = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas + [loose],
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        #expect(withALooseList.map(\.title) == ["Work", "Personal", CadenceSidebarLists.ungroupedTitle])
        #expect(withALooseList.last?.contextID == nil)
        #expect(withALooseList.last?.id == CadenceSidebarLists.Section.ungroupedID)

        let tidy = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        #expect(tidy.map(\.title) == ["Work", "Personal"])
    }

    /// The catch-all obeys the same two rules as every other heading: it offers only what may be
    /// newly picked, plus the one already assigned.
    @Test func theCatchAllHeadingNarrowsByTheSameRuleTheOtherHeadingsDo() throws {
        let fixture = try makeFixture()
        let retiredLoose = Area(name: "Reading")
        retiredLoose.status = .done
        let areas = fixture.areas + [retiredLoose]

        let elsewhere = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: areas,
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        #expect(elsewhere.map(\.title) == ["Work", "Personal"])

        let onIt = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: areas,
            projects: fixture.projects,
            selection: .area(retiredLoose.id),
            query: ""
        )
        #expect(onIt.last?.title == CadenceSidebarLists.ungroupedTitle)
        #expect(onIt.last?.areas.map(\.name) == ["Reading"])
    }

    /// The keyboard walks the catch-all's rows like any others: the flat order is what the arrow
    /// keys and Enter read, so a group the rows draw but the flat order omits would be a heading
    /// the cursor skips.
    @Test func theFlatOrderWalksTheCatchAllRowsLastRatherThanSkippingThem() throws {
        let fixture = try makeFixture()
        let loose = Area(name: "Reading")
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas + [loose],
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        let selections = ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: true)

        #expect(selections.first == .inbox)
        #expect(selections.last == .area(loose.id))
    }

    // MARK: - the accessor the presentations read the selection through

    /// `container(of:)` is the inverse of `selectedAreaID` / `selectedProjectID`, and it is what a
    /// picker opened on an existing task rather than on a draft is told.
    @Test func theSharedContainerAccessorNamesWhereATaskActuallyIs() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let area = Area(name: "Design")
        let project = Project(name: "Delta Launch")
        let unfiled = AppTask(title: "Unfiled")
        let inArea = AppTask(title: "Filed in an area")
        let inProject = AppTask(title: "Filed in a project")
        modelContext.insert(area)
        modelContext.insert(project)
        for task in [unfiled, inArea, inProject] { modelContext.insert(task) }
        inArea.area = area
        inProject.project = project
        try modelContext.save()

        #expect(CadenceTaskComposerSupport.container(of: unfiled) == .inbox)
        #expect(CadenceTaskComposerSupport.container(of: inArea) == .area(area.id))
        #expect(CadenceTaskComposerSupport.container(of: inProject) == .project(project.id))
    }

    // MARK: - the two presentations, which no behavioural test can reach

    /// **Absence of a filter is not presence of the rule, and the rule lives in a parameter.** The
    /// popover is a SwiftUI view, so nothing here can open one; what a test can check is that both
    /// presentations tell it where the task is. A call site passing `.inbox` would compile, would
    /// pass every behavioural test above, and would restore T-534 exactly.
    @Test func everyPresentationOfTheContainerPickerTellsItWhereTheTaskAlreadyIs() throws {
        let badgeRaw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift")
        let cardRaw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanCardMetaSupportViews.swift")
        let badge = CadenceSourceScan.strippingComments(badgeRaw)
        let card = CadenceSourceScan.strippingComments(cardRaw)

        // Non-vacuity: both files were read, and both had comments blanked rather than returned raw.
        #expect(badge.contains("struct ContainerPickerBadge: View"))
        #expect(card.contains("struct KanbanContainerPickerPopover: View"))
        #expect(badge != badgeRaw)
        #expect(card != cardRaw)

        // The chip owns a binding, so the selection is the binding's value.
        #expect(badge.contains("selection: selection"))
        // The card owns the task, so it reads the placement off it through the shared accessor.
        #expect(card.contains("selection: CadenceTaskComposerSupport.container(of: task)"))

        for source in [badge, card] {
            #expect(CadenceSourceScan.matchCount("ContainerPickerPopoverContent\\(", in: source) == 1)
            #expect(CadenceSourceScan.matchCount("selection:\\s*\\.inbox", in: source) == 0)
        }
    }
}
#endif
