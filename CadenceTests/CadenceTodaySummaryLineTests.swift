import Foundation
import Testing
@testable import Cadence

/// Pins the shape `CadenceTodaySummary.line` carries — inherited from the calendar day summary
/// that has since been deleted with the band it fed:
/// zeros are absent rather than printed, and an empty day produces no line at all.
///
/// The regression it replaced: iPad Today rendered the same count in three places at once — a
/// header badge reading "0", a two-chip mini summary reading "0" and "0", and a three-chip strip
/// reading "0 Active · 0 Timed · 0 Done", the chips in three different accent colours encoding
/// nothing. Exactly the duplication `ecaf80f` deleted from the calendar's four zero-chips.
struct CadenceTodaySummaryLineTests {
    private func summary(active: Int, timed: Int, done: Int) -> CadenceTodaySummary {
        CadenceTodaySummary(activeCount: active, timedCount: timed, completedCount: done)
    }

    @Test func anEmptyDayHasNoLineAtAll() {
        #expect(summary(active: 0, timed: 0, done: 0).line == nil)
    }

    @Test func activeCountAloneStillProducesNoLine() {
        // The header badge beside this line *is* the active count. Repeating it here is the
        // duplication the line replaced, so a day of untimed, unfinished work says it once.
        #expect(summary(active: 7, timed: 0, done: 0).line == nil)
    }

    @Test func zeroesAreOmittedRatherThanPrinted() {
        #expect(summary(active: 4, timed: 2, done: 0).line == "2 timed")
        #expect(summary(active: 4, timed: 0, done: 3).line == "3 done")
    }

    @Test func bothCountsJoinWithTheSharedSeparator() {
        #expect(summary(active: 5, timed: 2, done: 3).line == "2 timed · 3 done")
    }

    @Test func timedLeadsDoneSoTheLineReadsForwardInTime() {
        let line = summary(active: 1, timed: 1, done: 1).line
        #expect(line == "1 timed · 1 done")
    }
}
