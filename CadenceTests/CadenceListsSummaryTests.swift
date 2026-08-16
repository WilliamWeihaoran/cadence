import Foundation
import Testing
@testable import Cadence

/// The Lists eyebrow used to be the constant "WORKSPACE" — a word naming the app you were already
/// in, over a title that already said "Lists". These pin the replacement's two rules: say something
/// the title does not, and do not print zeros.
struct CadenceListsSummaryTests {
    @Test
    func itNamesBothShapesWhenBothArePresent() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 3, projectCount: 3) == "3 areas · 3 projects")
    }

    @Test
    func itOmitsAShapeWithNothingInIt() {
        // The calendar and Today summaries omit zeros rather than printing them; this follows.
        #expect(CadenceListsSummary.eyebrow(areaCount: 3, projectCount: 0) == "3 areas")
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 2) == "2 projects")
    }

    @Test
    func itSingularisesACountOfOne() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 1, projectCount: 1) == "1 area · 1 project")
    }

    @Test
    func anEmptyWorkspaceSaysSoInWordsRatherThanTwoNoughts() {
        #expect(CadenceListsSummary.eyebrow(areaCount: 0, projectCount: 0) == "No lists yet")
    }

    @Test
    func negativeCountsCannotProduceNonsense() {
        // Counts come from `.count`, so this is defensive rather than reachable — but a header
        // reading "-1 areas" would be worse than the constant it replaced.
        #expect(CadenceListsSummary.eyebrow(areaCount: -1, projectCount: -4) == "No lists yet")
    }
}
