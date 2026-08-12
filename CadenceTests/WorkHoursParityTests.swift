import Foundation
import Testing
@testable import Cadence

/// `CalendarWorkHoursPreferences` moved out of `macOS/Services/` and lost its `#if os(macOS)`
/// fence: its keys were always `calendar.workHours.*.v1`, not `macos.*`, so a window set on the
/// Mac synced to the iPad and then had nothing to read it. iOS now draws the same band and offers
/// the same control.
///
/// The band's extent is shared; only the minute → Y conversion is per-surface, because macOS has
/// `TimelineMetrics` and the iOS day column has its own linear `yOffset`. These pin that the two
/// entry points into the extent calculation cannot disagree.
@MainActor
struct WorkHoursParityTests {
    #if os(macOS)
    @Test func theMetricsOverloadIsTheClosureOverloadWithTheMetricsPluggedIn() {
        let metrics = TimelineMetrics(startHour: 6, endHour: 23, hourHeight: 60)

        for (start, end) in [(9 * 60, 17 * 60), (0, 24 * 60), (7 * 60, 15 * 60), (22 * 60, 24 * 60)] {
            let viaMetrics = CalendarWorkHoursPreferences.highlightFrame(
                startMinute: start,
                endMinute: end,
                metrics: metrics
            )
            let viaClosure = CalendarWorkHoursPreferences.highlightFrame(
                startMinute: start,
                endMinute: end,
                timelineStartHour: metrics.startHour,
                timelineEndHour: metrics.endHour,
                yOffset: metrics.yOffset(forFractionalMinute:)
            )

            #expect(viaMetrics == viaClosure, "overloads diverged for \(start)…\(end)")
        }
    }
    #endif

    /// A window entirely outside the timeline's own hours draws no band rather than a zero-height
    /// or negative one.
    @Test func aWindowOutsideTheVisibleHoursProducesNoBand() {
        let frame = CalendarWorkHoursPreferences.highlightFrame(
            startMinute: 0,
            endMinute: 5 * 60,
            timelineStartHour: 6,
            timelineEndHour: 23,
            yOffset: { ($0 - 360) / 60 * 58 }
        )

        #expect(frame == nil)
    }

    /// The band is clipped to the visible hours, and it is measured with the caller's own
    /// conversion — the property that keeps it aligned with the blocks drawn beside it.
    @Test func theBandIsClippedToTheVisibleHoursAndMeasuredByTheCallersConversion() throws {
        let hourHeight: CGFloat = 58
        let yOffset: (CGFloat) -> CGFloat = { ($0 - 360) / 60 * hourHeight }

        let frame = try #require(
            CalendarWorkHoursPreferences.highlightFrame(
                startMinute: 5 * 60,
                endMinute: 9 * 60,
                timelineStartHour: 6,
                timelineEndHour: 23,
                yOffset: yOffset
            )
        )

        #expect(frame.y == 0)
        #expect(frame.height == 3 * hourHeight)
    }

    /// Weekends are excluded on both platforms; the iOS column asks the same question macOS's
    /// highlight layer does.
    @Test func theBandIsSuppressedOnWeekends() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))

        #expect(CalendarWorkHoursPreferences.shouldShowHighlight(on: tuesday, calendar: calendar))
        #expect(!CalendarWorkHoursPreferences.shouldShowHighlight(on: saturday, calendar: calendar))
    }
}
