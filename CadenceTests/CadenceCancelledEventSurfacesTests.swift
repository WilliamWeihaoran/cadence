import Foundation
import Testing
@testable import Cadence

/// Pins [[T-18014]]: an organizer-cancelled event is drawn as cancelled on every surface, not only
/// the timed grid [[T-18007]] reached -- the all-day and month chips, the Board cards, both
/// platforms' Search rows and the iOS event summary row -- and neither event editor offers Save on
/// one. One predicate (`CadenceCalendarEventVisibility.isCancelled`), one treatment
/// (`CadenceCancelledEventTreatment.swift`), both platforms ([[T-8201]]).
struct CadenceCancelledEventSurfacesTests {
    // MARK: - What is spoken

    @Test func aCancelledEventsTitleSaysSoAndAnOrdinaryOneDoesNot() {
        #expect(CadenceCalendarDayAccessibility.eventTitleLabel(title: "Standup", isCancelled: true) == "Standup, canceled")
        #expect(CadenceCalendarDayAccessibility.eventTitleLabel(title: "Standup", isCancelled: false) == "Standup")
    }

    // MARK: - The editors offer no Save

    @Test func aCancelledEventCannotBeSavedHoweverCompleteTheFormIs() {
        let writable = ["work"]
        #expect(
            CadenceCalendarEventEditingSupport.canSave(
                title: "Team sync",
                isEventEditable: true,
                isEventCancelled: true,
                selectedCalendarID: "work",
                writableCalendarIDs: writable
            ) == false
        )
        #expect(
            CadenceCalendarEventEditingSupport.canSave(
                title: "Team sync",
                isEventEditable: true,
                isEventCancelled: false,
                selectedCalendarID: "work",
                writableCalendarIDs: writable
            ) == true
        )
    }

    /// A non-nil notice is what makes the shared panel draw no Save and no Delete.
    @Test func theViewOnlyNoticeNamesTheCancellationFirst() {
        let editable = CadenceCalendarEventEditingSupport.viewOnlyNotice(
            calendarName: "Work", isEventEditable: true, isEventCancelled: false
        )
        #expect(editable == nil)
        #expect(
            CadenceCalendarEventEditingSupport.viewOnlyNotice(
                calendarName: "Work", isEventEditable: true, isEventCancelled: true
            ) == CadenceCalendarEventEditingSupport.cancelledNotice
        )
        #expect(
            CadenceCalendarEventEditingSupport.viewOnlyNotice(
                calendarName: "Holidays", isEventEditable: false, isEventCancelled: true
            ) == CadenceCalendarEventEditingSupport.cancelledNotice
        )
        #expect(
            CadenceCalendarEventEditingSupport.viewOnlyNotice(
                calendarName: "Holidays", isEventEditable: false, isEventCancelled: false
            ) == CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: "Holidays")
        )
    }

    // MARK: - Every surface reads the one predicate and draws the one treatment

    private struct Pin {
        let path: String
        let predicate: Int
        let title: Int
        let dim: Int
    }

    /// Exact counts, so a surface that loses its read -- or a new event surface that copies the
    /// title without the treatment -- shows here rather than on screen.
    private static let pins: [Pin] = [
        // MonthEventChip, AllDayEventChip (the all-day lane and the Mac Today panel's band).
        Pin(path: "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift", predicate: 2, title: 2, dim: 2),
        Pin(path: "Cadence/macOS/Views/CalendarBoardItemSupportViews.swift", predicate: 1, title: 1, dim: 1),
        Pin(path: "Cadence/macOS/Views/GlobalSearchIndexSupport.swift", predicate: 1, title: 0, dim: 0),
        Pin(path: "Cadence/macOS/Views/GlobalSearchSupportViews.swift", predicate: 0, title: 1, dim: 1),
        // The month cell's chips; `iOSCalendarMiniChip` draws the treatment.
        Pin(path: "Cadence/iOS/iOSCalendarMonthViews.swift", predicate: 1, title: 1, dim: 1),
        // `iOSCalendarEventBlock` ([[T-18007]]) and the all-day band (the Today pane's too).
        Pin(path: "Cadence/iOS/iOSCalendarTimelineViews.swift", predicate: 2, title: 0, dim: 0),
        Pin(path: "Cadence/iOS/iOSBoardCards.swift", predicate: 1, title: 1, dim: 1),
        Pin(path: "Cadence/iOS/iOSSearchView.swift", predicate: 1, title: 0, dim: 0),
        Pin(path: "Cadence/iOS/iOSSearchSupportViews.swift", predicate: 0, title: 1, dim: 1),
        // `iOSCalendarEventSummaryRow`: the compact month agenda and the inspector list.
        Pin(path: "Cadence/iOS/iOSCalendarInspectorView.swift", predicate: 1, title: 0, dim: 0),
        Pin(path: "Cadence/iOS/iOSFeatureComponents.swift", predicate: 0, title: 1, dim: 1),
    ]

    @Test func everyEventSurfaceReadsThePredicateAndDrawsTheTreatment() throws {
        for pin in Self.pins {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(pin.path))
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarEventVisibility\.isCancelled\("#, in: code) == pin.predicate,
                "\(pin.path) predicate reads"
            )
            #expect(CadenceSourceScan.matchCount(#"\.cadenceCancelledEventTitle\("#, in: code) == pin.title, "\(pin.path) struck titles")
            #expect(CadenceSourceScan.matchCount(#"\.cadenceCancelledEventDim\("#, in: code) == pin.dim, "\(pin.path) dims")
        }
    }

    @Test func bothEditorsGateSaveAndTheReadOnlySlotOnTheCancellation() throws {
        for path in [
            "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
        ] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(CadenceSourceScan.matchCount(#"CadenceCalendarEventVisibility\.isCancelled\("#, in: code) == 1, "\(path)")
            // canSave and viewOnlyNotice.
            #expect(CadenceSourceScan.matchCount(#"isEventCancelled: isCancelled"#, in: code) == 2, "\(path)")
            #expect(code.contains("readOnlyNotice: CadenceCalendarEventEditingSupport.viewOnlyNotice("), "\(path)")
        }
    }
}
