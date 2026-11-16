import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The Lists eyebrow used to be the constant "WORKSPACE" — a word naming the app you were already
/// in, over a title that already said "Lists". These pin the replacement's two rules: say something
/// the title does not, and do not print zeros.
struct CadenceListsSummaryTests {
    @Test
    func itNamesBothShapesWhenBothArePresent() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 3, projectCount: 3, hasInactive: false) == "3 areas · 3 projects")
    }

    @Test
    func itOmitsAShapeWithNothingInIt() {
        // The calendar and Today summaries omit zeros rather than printing them; this follows.
        #expect(CadenceListsSummary.eyebrow(areaCount: 3, projectCount: 0, hasInactive: false) == "3 areas")
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 2, hasInactive: false) == "2 projects")
    }

    @Test
    func itSingularisesACountOfOne() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 1, projectCount: 1, hasInactive: false) == "1 area · 1 project")
    }

    @Test
    func anEmptyWorkspaceSaysSoInWordsRatherThanTwoNoughts() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0, hasInactive: false) == "No lists yet")
    }

    /// [[T-17786]]: with every list archived the Lists page draws its Archived section, so the
    /// eyebrow over it must not claim nothing has been made yet. Active lists still win: a count
    /// of what is there says more than the fact that something else is archived.
    @Test
    func archivedListsAreNotNoListsYet() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0, hasInactive: true) == "No active lists")
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0, hasInactive: true)
            == CadenceEmptyStateCopy.activeListsTitle)
        #expect(CadenceListsSummary.eyebrow(areaCount: 2, projectCount: 0, hasInactive: true) == "2 areas")
    }

    /// [[T-18072]]: the eyebrow asks [[T-17789]]'s inactive predicate, not the archived-only one.
    /// A store whose only list is done -- or whose only project is paused -- has nothing archived,
    /// so the old `hasArchivedLists` answer put "No lists yet" over the page's "No active lists".
    /// Built from real models through the same two calls the page makes, so a caller handing the
    /// eyebrow the archived question again reads as this test going red rather than a renamed bool.
    @Test
    func completedOrPausedListsAreNotNoListsYetEither() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let doneArea = Area(name: "Done")
        doneArea.status = .done
        context.insert(doneArea)
        let paused = Project(name: "Paused")
        paused.status = .paused
        context.insert(paused)
        try context.save()

        for (areas, projects) in [([doneArea], [Project]()), ([Area](), [paused])] {
            #expect(areas.allSatisfy { !$0.isActive && !$0.isArchived }, "non-vacuity: fixture is archived or active")
            #expect(projects.allSatisfy { !$0.isActive && !$0.isArchived }, "non-vacuity: fixture is archived or active")
            let eyebrow = CadenceListsSummary.eyebrow(
                areaCount: areas.filter(\.isActive).count,
                projectCount: projects.filter(\.isActive).count,
                hasInactive: CadenceSidebarLists.hasInactiveLists(areas: areas, projects: projects)
            )
            #expect(eyebrow == CadenceEmptyStateCopy.activeListsTitle)
            #expect(eyebrow == "No active lists")
        }
    }

    /// The subtitle under the panel stays archived-only ([[T-18072]] widened the eyebrow, not
    /// this): "restore one from Archived" points at a section only an archived list draws.
    @Test
    func theEmptyPanelOffersArchivedOnlyWhenSomethingIsArchived() {
        #expect(CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false) == "Create an area or project here.")
        #expect(CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true).contains("restore one from Archived"))
    }

    /// The wiring: both Lists shells hand the header the inactive predicate over the unfiltered
    /// query, and keep `hasArchivedLists` for the panel's subtitle.
    @Test
    func bothListsShellsFeedTheEyebrowTheInactivePredicate() throws {
        let compact = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListViews.swift"))
        #expect(compact.contains("iOSListsPageHeader("), "non-vacuity: the iPhone shell stopped drawing the header")
        #expect(compact.contains("CadenceSidebarLists.hasInactiveLists(areas: areas, projects: projects)"))
        #expect(compact.contains("hasInactive: hasInactiveLists,"))
        #expect(compact.contains("hasInactiveLists: hasInactiveLists,"), "the iPad pane is not handed the predicate")
        #expect(compact.contains("CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: hasArchivedLists)"))

        let pane = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListsRegularPane.swift"))
        #expect(pane.contains("iOSListsPageHeader("), "non-vacuity: the iPad pane stopped drawing the header")
        #expect(pane.contains("hasInactive: hasInactiveLists"))
        #expect(pane.contains("CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: hasArchivedLists)"))
    }

    @Test
    func negativeCountsCannotProduceNonsense() {
        // Counts come from `.count`, so this is defensive rather than reachable — but a header
        // reading "-1 areas" would be worse than the constant it replaced.
        #expect(CadenceListsSummary.eyebrow(areaCount: -1, projectCount: -4, hasInactive: false) == "No lists yet")
    }
}
