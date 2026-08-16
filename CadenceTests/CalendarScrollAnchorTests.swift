import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The rule behind "a `@State` seeded in `init` is not a scroll position".
///
/// Three surfaces in this repo have shipped the same defect: a value handed to `.scrollPosition(id:)`
/// before the lazy stack under it has laid out a row, resolved against nothing, and silently
/// dropped. `ecaf80f` put the Board seven months in the past; `8a316c4` built the month agenda this
/// way; `42de745` found what it costs — Month → Agenda opening on a blank pane at iPad regular
/// width, curable only by stepping a month, which is the one gesture that re-assigns the binding
/// after layout.
///
/// `CadenceLazyScrollAnchor` is that step, made unconditional and shared. These pin the decision it
/// makes; the two-turn write it performs is view machinery and is verified on device.
@MainActor
struct CalendarScrollAnchorTests {

    // MARK: - When the assertion fires

    /// Zero content extent *is* the broken state: a lazy stack that has not built a row has no id to
    /// resolve, which is the whole reason the seeded position lands nowhere. Asserting into it would
    /// be the same scroll dropped a second time.
    @Test
    func nothingIsAssertedBeforeTheStackHasLaidOut() {
        #expect(
            !CadenceLazyScrollAnchor.shouldAssert(hasAsserted: false, hasTarget: true, contentExtent: 0)
        )
    }

    @Test
    func theAssertionFiresOnTheFirstRealContentExtent() {
        #expect(
            CadenceLazyScrollAnchor.shouldAssert(hasAsserted: false, hasTarget: true, contentExtent: 1)
        )
        #expect(
            CadenceLazyScrollAnchor.shouldAssert(hasAsserted: false, hasTarget: true, contentExtent: 1_850)
        )
    }

    /// Once, and once only. After the first assertion the scroll position belongs to the finger, and
    /// re-asserting an opening target the user has scrolled away from would drag them back to it on
    /// every content change — a month agenda grows and shrinks as tasks are completed.
    @Test
    func theAssertionNeverFiresTwice() {
        for extent in [CGFloat(1), 400, 1_850] {
            #expect(
                !CadenceLazyScrollAnchor.shouldAssert(hasAsserted: true, hasTarget: true, contentExtent: extent)
            )
        }
    }

    /// No target is not "scroll to the top" — it is "leave this scroll view alone". Releasing the
    /// binding and driving it to `nil` would be a scroll to nowhere, issued on purpose.
    @Test
    func noTargetMeansNoAssertion() {
        #expect(
            !CadenceLazyScrollAnchor.shouldAssert(hasAsserted: false, hasTarget: false, contentExtent: 900)
        )
    }

    /// A scroll view can report a negative or absurd extent mid-transition; only a positive one says
    /// there is laid-out content to resolve an id against.
    @Test
    func aNegativeExtentIsNotLayout() {
        #expect(
            !CadenceLazyScrollAnchor.shouldAssert(hasAsserted: false, hasTarget: true, contentExtent: -12)
        )
    }

    // MARK: - What the agenda opens on

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private func agendaKeys(_ key: String) -> [String] {
        CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: DateFormatters.date(from: key, in: calendar) ?? Date(),
            calendar: calendar
        )
    }

    @Test
    func theAgendaOpensOnTheSelectedDay() {
        let keys = agendaKeys("2026-08-15")
        #expect(
            CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                selectedKey: "2026-08-17",
                agendaDayKeys: keys
            ) == "2026-08-17"
        )
    }

    /// The opening position had no equivalent of `scrollTarget`'s containment guard, so a selection
    /// outside the displayed month was seeded straight into `.scrollPosition(id:)` as an id the
    /// stack does not contain — a scroll dropped on the floor, leaving the grid lit on one day and
    /// the agenda parked on another with no gesture that reconciles them.
    @Test
    func aSelectionThisMonthDoesNotListOpensOnTheMonthInstead() {
        let keys = agendaKeys("2026-08-15")
        #expect(!keys.contains("2026-12-25"))
        #expect(
            CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                selectedKey: "2026-12-25",
                agendaDayKeys: keys
            ) == keys.first
        )
    }

    /// The grid's leading and trailing padding days are listed, so a selection in one of them is a
    /// real section to open on — not a near miss to be rounded away to the first of the month.
    @Test
    func aPaddingDayIsAValidOpeningPosition() {
        let keys = agendaKeys("2026-08-15")
        #expect(keys.first == "2026-07-26")
        #expect(
            CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                selectedKey: "2026-09-02",
                agendaDayKeys: keys
            ) == "2026-09-02"
        )
    }

    @Test
    func amonthWithNoDaysHasNothingToOpenOn() {
        #expect(
            CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                selectedKey: "2026-08-17",
                agendaDayKeys: []
            ) == nil
        )
    }

    /// The opening target and the later scroll target must agree about which days exist, or the
    /// first frame and the first tap disagree about the same month.
    @Test
    func theOpeningTargetAgreesWithTheSelectionScrollTarget() {
        let keys = agendaKeys("2026-02-10")
        for key in keys {
            let opening = CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                selectedKey: key,
                agendaDayKeys: keys
            )
            #expect(opening == key)
            // Same day, arrived at by a tap rather than by opening: still a legal scroll.
            #expect(
                CadenceCalendarMonthAgendaSupport.scrollTarget(
                    selectedKey: key,
                    scrolledKey: keys.first,
                    agendaDayKeys: keys
                ) == (key == keys.first ? nil : key)
            )
        }
    }
}
