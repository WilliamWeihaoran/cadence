import Foundation
import Testing
@testable import Cadence

/// Today's past-due cards used to draw their whole caption in `Theme.red` — the count and the
/// parent list name were as red as the date that had actually passed. These pin the split: the
/// deadline is the only fragment that can carry red, and it only carries it when it is really late.
struct CadenceOverdueSummaryPresentationTests {
    private let today = "2026-08-16"

    @Test
    func itMarksAPassedDeadlineAsLate() {
        let line = CadenceOverdueSummaryPresentation.line(
            dueDateKey: "2026-07-01",
            trailingDetail: CadenceOverdueSummaryPresentation.activeTaskDetail(count: 3),
            todayKey: today
        )
        #expect(line.isLate)
        #expect(line.dateTint == Theme.red)
    }

    @Test
    func itLeavesTheNonDeadlineFragmentsOutOfTheDateFragment() {
        // The whole point of the split: "3 active tasks" must not be inside `dateText`, or the
        // view has no way to tint one and not the other.
        let line = CadenceOverdueSummaryPresentation.line(
            dueDateKey: "2026-07-01",
            leadingDetail: "Documents",
            trailingDetail: CadenceOverdueSummaryPresentation.activeTaskDetail(count: 3),
            todayKey: today
        )
        #expect(line.leadingDetail == "Documents")
        #expect(line.trailingDetail == "3 active tasks")
        #expect(!line.dateText.contains("active"))
        #expect(!line.dateText.contains("Documents"))
        #expect(line.plainText == "Documents • 46 days ago • 3 active tasks")
    }

    @Test
    func aDeadlineThatHasNotPassedIsNotRed() {
        // Today and future keys are not "late". A card that somehow renders one stays neutral
        // rather than inheriting the red of the section it sits under.
        for key in [today, "2026-08-20"] {
            let line = CadenceOverdueSummaryPresentation.line(dueDateKey: key, todayKey: today)
            #expect(!line.isLate)
            #expect(line.dateTint == Theme.dim)
        }
    }

    @Test
    func anEmptyOrUnparseableKeyIsNeverLate() {
        // Degrades through `DateFormatters.relativeDate`, which returns the raw string. A bad
        // value must not be able to light up red.
        for key in ["", "not-a-date"] {
            let line = CadenceOverdueSummaryPresentation.line(dueDateKey: key, todayKey: today)
            #expect(!line.isLate)
            #expect(line.dateTint == Theme.dim)
        }
    }

    @Test
    func itAgreesWithCadenceDueUrgencyRatherThanReimplementingIt() {
        // The classifier is shared with iOS and the timeline blocks; this is the guard against a
        // second hand-rolled `<` comparison drifting away from it.
        for key in ["2026-07-01", today, "2026-08-20", ""] {
            // Pattern match rather than `==`: the enum's synthesised `Equatable` conformance is
            // main-actor isolated, and comparing it from a nonisolated test warns under Swift 6.
            var expected = false
            if case .overdue = CadenceDueUrgency.evaluate(dueDateKey: key, todayKey: today) {
                expected = true
            }
            #expect(CadenceOverdueSummaryPresentation.line(dueDateKey: key, todayKey: today).isLate == expected)
        }
    }

    @Test
    func itOmitsBlankDetailsFromTheLine() {
        let line = CadenceOverdueSummaryPresentation.line(
            dueDateKey: "2026-07-01",
            leadingDetail: "   ",
            trailingDetail: nil,
            todayKey: today
        )
        #expect(line.leadingDetail == nil)
        #expect(line.plainText == "46 days ago")
    }

    @Test
    func itCountsOneActiveTaskInTheSingular() {
        #expect(CadenceOverdueSummaryPresentation.activeTaskDetail(count: 1) == "1 active task")
        #expect(CadenceOverdueSummaryPresentation.activeTaskDetail(count: 0) == "0 active tasks")
        #expect(CadenceOverdueSummaryPresentation.activeTaskDetail(count: 12) == "12 active tasks")
    }
}
