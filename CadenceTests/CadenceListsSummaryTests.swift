import Foundation
import Testing
@testable import Cadence

/// The Lists eyebrow used to be the constant "WORKSPACE" — a word naming the app you were already
/// in, over a title that already said "Lists". These pin the replacement's two rules: say something
/// the title does not, and do not print zeros.
struct CadenceListsSummaryTests {
    @Test
    func itNamesBothShapesWhenBothArePresent() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 3, projectCount: 3, hasArchived: false) == "3 areas · 3 projects")
    }

    @Test
    func itOmitsAShapeWithNothingInIt() {
        // The calendar and Today summaries omit zeros rather than printing them; this follows.
        #expect(CadenceListsSummary.eyebrow(areaCount: 3, projectCount: 0, hasArchived: false) == "3 areas")
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 2, hasArchived: false) == "2 projects")
    }

    @Test
    func itSingularisesACountOfOne() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 1, projectCount: 1, hasArchived: false) == "1 area · 1 project")
    }

    @Test
    func anEmptyWorkspaceSaysSoInWordsRatherThanTwoNoughts() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0, hasArchived: false) == "No lists yet")
    }

    /// [[T-17786]]: with every list archived the Lists page draws its Archived section, so the
    /// eyebrow over it must not claim nothing has been made yet. Active lists still win: a count
    /// of what is there says more than the fact that something else is archived.
    @Test
    func archivedListsAreNotNoListsYet() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0, hasArchived: true) == "No active lists")
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0, hasArchived: true)
            == CadenceEmptyStateCopy.activeListsTitle)
        #expect(CadenceListsSummary.eyebrow(areaCount: 2, projectCount: 0, hasArchived: true) == "2 areas")
    }

    @Test
    func negativeCountsCannotProduceNonsense() {
        // Counts come from `.count`, so this is defensive rather than reachable — but a header
        // reading "-1 areas" would be worse than the constant it replaced.
        #expect(CadenceListsSummary.eyebrow(areaCount: -1, projectCount: -4, hasArchived: false) == "No lists yet")
    }
}
