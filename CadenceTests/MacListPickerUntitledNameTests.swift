#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-8102.** Both macOS list pickers — the badge's grouped popover (`ContainerPickerFilterSupport`)
/// and the `~` panel (`TildeContainerPickerSupport.flatContainers`) — titled their rows with the raw
/// `name`, so a list renamed to spaces drew a bare glyph and a blank context an empty heading, while
/// the badge over them read "Untitled Area". The search matched the raw name too, so typing what the
/// row now says found nothing.
@MainActor
struct MacListPickerUntitledNameTests {

    private struct Fixture {
        let contexts: [Context]
        let areas: [Area]
        let projects: [Project]
    }

    private func makeFixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let blankContext = Context(name: "  ")
        blankContext.order = 0
        let blankArea = Area(name: "   ", context: blankContext)
        blankArea.order = 0
        let namedArea = Area(name: "Errands", context: blankContext)
        namedArea.order = 1
        let blankProject = Project(name: "\n", context: blankContext)
        blankProject.order = 0
        modelContext.insert(blankContext)
        for model in [blankArea, namedArea] { modelContext.insert(model) }
        modelContext.insert(blankProject)
        try modelContext.save()
        return Fixture(contexts: [blankContext], areas: [blankArea, namedArea], projects: [blankProject])
    }

    private func groups(_ fixture: Fixture, query: String) -> [ContainerPickerFilterSupport.Group] {
        ContainerPickerFilterSupport.groups(
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: query
        )
    }

    private func tildeNames(_ fixture: Fixture, query: String) -> [String] {
        TildeContainerPickerSupport.flatContainers(
            query: query,
            contexts: fixture.contexts,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: nil
        )
        .map(\.name)
    }

    @Test func badgePickerRowsAndHeadingNameBlankListsUntitled() throws {
        let fixture = try makeFixture()
        let groups = groups(fixture, query: "")
        #expect(groups.map(\.title) == [CadenceTitleNormalization.defaultContextName])
        let group = try #require(groups.first)
        #expect(group.areas.map(ContainerPickerFilterSupport.rowName(for:)) == ["Untitled Area", "Errands"])
        #expect(group.projects.map(ContainerPickerFilterSupport.rowName(for:)) == ["Untitled Project"])
    }

    @Test func badgePickerSearchMatchesTheUntitledNameItDraws() throws {
        let fixture = try makeFixture()
        let group = try #require(groups(fixture, query: "untitled").first)
        #expect(group.areas.map(ContainerPickerFilterSupport.rowName(for:)) == ["Untitled Area"])
        #expect(group.projects.map(ContainerPickerFilterSupport.rowName(for:)) == ["Untitled Project"])
    }

    @Test func tildePanelNamesBlankListsUntitled() throws {
        let fixture = try makeFixture()
        #expect(tildeNames(fixture, query: "") == ["Inbox", "Untitled Area", "Errands", "Untitled Project"])
    }

    @Test func tildeSearchMatchesTheUntitledNameItDraws() throws {
        let fixture = try makeFixture()
        #expect(tildeNames(fixture, query: "untitled p") == ["Untitled Project"])
    }

    @Test func aNamedListKeepsItsTrimmedName() throws {
        let fixture = try makeFixture()
        fixture.areas[1].name = "  Errands  "
        #expect(ContainerPickerFilterSupport.rowName(for: fixture.areas[1]) == "Errands")
    }
}
#endif
