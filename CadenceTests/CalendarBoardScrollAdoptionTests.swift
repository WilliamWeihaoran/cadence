import Foundation
import Testing
@testable import Cadence

/// What a **reported** scroll position is allowed to write, on the two surfaces that were taking
/// `cadenceLazyScrollAnchor`'s assertion without its gate.
///
/// `CalendarScrollAnchorTests` pins `CadenceLazyScrollAnchor.report`'s decision in isolation. These
/// pin the consequence: that the decision, wired the way the Calendar Board and the Month agenda
/// wire it, cannot let a report older than the placement reach the write. The Board's write is the
/// one that matters — `adoptVisibleDay` sets `anchorDate`, and the Calendar page persists it, so a
/// spurious adoption does not merely look wrong for a frame, it is saved and survives relaunch.
/// That is `ecaf80f`, which cost seven months of offset and had only the toolbar's Today button as
/// a way out.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to the macOS-built test target, so the
/// views themselves cannot be instantiated here. What is testable is the pipeline they are built
/// from, and it is the whole of the defect: both views hold exactly `didConfirm…` plus a switch
/// over `report`, and every arithmetic step below is the shipping function.
@MainActor
struct CalendarBoardScrollAdoptionTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    /// The Board's `onChange(of: scrolledDayIndex)`, transcribed: gate, latch, adopt. `adopted` is
    /// what `adoptVisibleDay` would have written into `anchorDate`.
    private func boardAdoptions(
        reports: [Int?],
        target: Int,
        bufferStart: Date
    ) -> (adopted: [String], confirmed: Bool) {
        var hasConfirmed = false
        var adopted: [String] = []
        for report in reports {
            guard let report else { continue }
            switch CadenceLazyScrollAnchor.report(
                report,
                target: target,
                hasConfirmedPlacement: hasConfirmed
            ) {
            case .ignore:
                continue
            case .confirmsPlacement:
                hasConfirmed = true
            case .adopt:
                let date = CalendarBoardPlannerSupport.date(
                    at: report,
                    bufferStart: bufferStart,
                    calendar: calendar
                )
                adopted.append(DateFormatters.dateKey(from: date, calendar: calendar))
            }
        }
        return (adopted, hasConfirmed)
    }

    private func bufferStart(anchorKey: String) -> Date {
        CalendarBoardPlannerSupport.plannerWindowStart(
            for: DateFormatters.date(from: anchorKey, in: calendar) ?? Date(),
            calendar: calendar
        )
    }

    // MARK: - The write the gate exists to prevent

    /// The report that shipped the bug, with the number that made it expensive: column 0 of a
    /// 420-column board is `plannerLeadingDayCount` — 210 days, near enough seven months — behind
    /// the anchor. Ungated, that index is what got saved.
    @Test
    func aPrePlacementReportOfColumnZeroWouldHaveWrittenAnchorSevenMonthsBack() {
        let anchorKey = "2026-08-17"
        let start = bufferStart(anchorKey: anchorKey)
        let strayDate = CalendarBoardPlannerSupport.date(at: 0, bufferStart: start, calendar: calendar)

        #expect(DateFormatters.dateKey(from: strayDate, calendar: calendar) == "2026-01-19")
    }

    /// …and with the gate in place, that same report writes nothing at all.
    @Test
    func aPrePlacementReportCannotWriteAnchorDate() {
        let anchorKey = "2026-08-17"
        let start = bufferStart(anchorKey: anchorKey)
        let target = CalendarBoardPlannerSupport.plannerLeadingDayCount

        let result = boardAdoptions(reports: [0], target: target, bufferStart: start)

        #expect(result.adopted.isEmpty)
        #expect(!result.confirmed)
    }

    /// The realistic opening sequence: a stray settle report, the `nil` that
    /// `cadenceLazyScrollAnchor` writes to force a change, the assertion arriving back, and only
    /// then a real scroll. Exactly one date is written, and it is the one the finger produced.
    @Test
    func onlyReportsAfterTheConfirmationReachTheAnchor() {
        let anchorKey = "2026-08-17"
        let start = bufferStart(anchorKey: anchorKey)
        let target = CalendarBoardPlannerSupport.plannerLeadingDayCount

        let result = boardAdoptions(
            reports: [0, 3, nil, target, target + 2],
            target: target,
            bufferStart: start
        )

        #expect(result.confirmed)
        #expect(result.adopted == ["2026-08-19"])
    }

    /// The confirmation itself is not an adoption. It lands on the anchor the board was already
    /// showing, so writing it back would be a persisted write caused by nothing the user did — the
    /// same class of write, just with a value that happens to be right today.
    @Test
    func theConfirmingReportIsNotItselfAdopted() {
        let anchorKey = "2026-08-17"
        let start = bufferStart(anchorKey: anchorKey)
        let target = CalendarBoardPlannerSupport.plannerLeadingDayCount

        let result = boardAdoptions(reports: [target], target: target, bufferStart: start)

        #expect(result.confirmed)
        #expect(result.adopted.isEmpty)
    }

    /// The gate must not become a permanent mute. Once the placement is confirmed, a scroll back
    /// onto the opening column is a real scroll and has to be believed — otherwise the toolbar's
    /// date title freezes on whatever the board opened at.
    @Test
    func scrollingBackOntoTheOpeningColumnStillCounts() {
        let anchorKey = "2026-08-17"
        let start = bufferStart(anchorKey: anchorKey)
        let target = CalendarBoardPlannerSupport.plannerLeadingDayCount

        let result = boardAdoptions(
            reports: [target, target + 5, target],
            target: target,
            bufferStart: start
        )

        #expect(result.adopted == ["2026-08-22", "2026-08-17"])
    }

    // MARK: - The Month agenda, same shape over day keys

    /// The agenda's positions are `"yyyy-MM-dd"` section ids rather than column indices, which is
    /// the reason `report` is generic rather than each surface writing its own gate. Its write is
    /// `selectedDate`, which is not persisted — but it drives the lit cell in the grid above it, so
    /// an adopted stale report still moves the selection to a day nobody touched.
    private func agendaAdoptions(reports: [String?], target: String?) -> [String] {
        var hasConfirmed = false
        var adopted: [String] = []
        for report in reports {
            switch CadenceLazyScrollAnchor.report(
                report,
                target: target,
                hasConfirmedPlacement: hasConfirmed
            ) {
            case .ignore:
                continue
            case .confirmsPlacement:
                hasConfirmed = true
            case .adopt:
                guard let selection = CadenceCalendarMonthAgendaSupport.selectionTarget(
                    scrolledKey: report,
                    selectedKey: target ?? ""
                ) else { continue }
                adopted.append(selection)
            }
        }
        return adopted
    }

    @Test
    func theAgendaIgnoresSectionReportsOlderThanItsPlacement() {
        let keys = CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: DateFormatters.date(from: "2026-08-17", in: calendar) ?? Date(),
            calendar: calendar
        )
        // The section a not-yet-laid-out `LazyVStack` reports: the top of its content.
        #expect(keys.first == "2026-07-26")

        #expect(agendaAdoptions(reports: [keys.first], target: "2026-08-17").isEmpty)
        #expect(
            agendaAdoptions(reports: [keys.first, "2026-08-17", "2026-08-21"], target: "2026-08-17")
                == ["2026-08-21"]
        )
    }
}
