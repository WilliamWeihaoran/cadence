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
            query: ""
        )

        #expect(groups.map(\.context.name) == ["Work", "Personal"])
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
            query: "de"
        )

        #expect(groups.map(\.context.name) == ["Work"])
    }

    // MARK: - keyboard selection

    @Test func filteringThenArrowingDownThenEnterSelectsTheHighlightedItem() throws {
        let fixture = try makeFixture()
        let query = "de"
        let groups = ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
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
            query: ""
        )
        let selections = ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: true)

        #expect(selections.first == .inbox)
        #expect(ContainerPickerFilterSupport.highlighted(at: 0, in: selections) == .inbox)
    }
}
#endif
