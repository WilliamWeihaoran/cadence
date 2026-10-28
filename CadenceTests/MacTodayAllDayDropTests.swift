#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// **T-8091 — an all-day chip dropped on Mac Today's ladder was accepted and did nothing.**
///
/// `SchedulePanelTimelineViewport` built its `TimelineDayCanvas` without
/// `onDropAllDayEventAtMinute`, whose default is `nil`, and `TimelineDropDelegate.performDrop`
/// calls that optional and still answers `true`. The fix routes both hosts through
/// `CalendarAllDayEventDropSupport`; the first three tests pin its resolution by behaviour, the
/// last two pin that every macOS host of the canvas hands it a handler. Counts and relations only.
struct MacTodayAllDayDropTests {
    private static let store = EKEventStore()

    private static func allDayEvent(_ title: String) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = true
        return event
    }

    @Test("A payload the source day cannot name is asked of the store by its lookup form")
    func anUnlistedPayloadFallsBackToTheStoreLookup() {
        let offsite = Self.allDayEvent("Offsite")
        var lookedUp: [String] = []
        let payload = CalendarAllDayEventDropPayload(sourceDateKey: "2026-11-26", eventIdentifier: "evt-1")

        let resolved = CalendarAllDayEventDropSupport.resolveEditableEvent(
            payload,
            fallbackDate: Date(),
            allDayEvents: { _ in [] },
            lookup: { lookedUp.append($0); return offsite },
            isEditable: { _ in true }
        )

        #expect(resolved === offsite)
        #expect(lookedUp == [CalendarEventIdentity.lookupIdentifier(from: "evt-1")])
    }

    @Test("A read-only event resolves to nothing, so no conversion is attempted")
    func aReadOnlyEventIsRefused() {
        let holiday = Self.allDayEvent("Holiday")
        let payload = CalendarAllDayEventDropPayload(sourceDateKey: "2026-11-26", eventIdentifier: "evt-2")

        let refused = CalendarAllDayEventDropSupport.resolveEditableEvent(
            payload, fallbackDate: Date(), allDayEvents: { _ in [] },
            lookup: { _ in holiday }, isEditable: { _ in false }
        )
        let accepted = CalendarAllDayEventDropSupport.resolveEditableEvent(
            payload, fallbackDate: Date(), allDayEvents: { _ in [] },
            lookup: { _ in holiday }, isEditable: { _ in true }
        )

        #expect(refused == nil)
        #expect(accepted === holiday)
        // The production default is the editor's gate: an event with no calendar is read-only.
        #expect(CalendarAllDayEventDropSupport.resolveEditableEvent(
            payload, fallbackDate: Date(), allDayEvents: { _ in [] }, lookup: { _ in holiday }
        ) == nil)
    }

    @Test("The source day is read from the payload, and the host's day stands in for a bad key")
    func theSourceDayComesFromThePayload() throws {
        var asked: [String] = []
        let fallback = try #require(DateFormatters.date(from: "2026-01-05"))
        let record: (Date) -> [EKEvent] = { asked.append(DateFormatters.dateKey(from: $0)); return [] }

        _ = CalendarAllDayEventDropSupport.resolveEditableEvent(
            CalendarAllDayEventDropPayload(sourceDateKey: "2026-11-26", eventIdentifier: "a"),
            fallbackDate: fallback, allDayEvents: record, lookup: { _ in nil }
        )
        _ = CalendarAllDayEventDropSupport.resolveEditableEvent(
            CalendarAllDayEventDropPayload(sourceDateKey: "not-a-day", eventIdentifier: "b"),
            fallbackDate: fallback, allDayEvents: record, lookup: { _ in nil }
        )

        #expect(asked == ["2026-11-26", "2026-01-05"])
    }

    /// The bug itself: the Today ladder must hand the canvas a handler, and SchedulePanel (which
    /// Today, the Cmd+\ overlay and both Focus hosts all build) must route it through the shared rule.
    @Test("Mac Today's ladder wires the all-day drop through the shared conversion")
    func theTodayLadderWiresTheAllDayDrop() throws {
        let viewport = try #require(CadenceSourceScan.declarationBody(
            "struct SchedulePanelTimelineViewport: View",
            in: CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelShellViews.swift")
            )
        ))
        #expect(viewport.contains("TimelineDayCanvas("))
        #expect(CadenceSourceScan.matchCount(
            #"onDropAllDayEventAtMinute:\s*onDropAllDayEventAtMinute\b"#, in: viewport
        ) == 1, "the Today ladder's canvas takes an all-day chip and has no handler for it")

        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanel.swift")
        )
        #expect(CadenceSourceScan.matchCount(
            #"onDropAllDayEventAtMinute:\s*\{\s*payload,\s*startMin\s+in\s*CalendarAllDayEventDropSupport\.convert\("#,
            in: panel
        ) == 1)
        #expect(CadenceSourceScan.matchCount(#"dateKey:\s*todayKey,\s*fallbackDate:"#, in: panel) == 1)
    }

    /// The canvas's parameter is optional and the delegate answers `true` either way (the payload's
    /// kind is known only after the provider loads, after the drop has been accepted), so a host
    /// that forgets it swallows the drop. Every macOS host must pass one.
    @Test("Every macOS host of TimelineDayCanvas passes an all-day drop handler")
    func everyCanvasHostPassesTheHandler() throws {
        let hosts = [
            "Cadence/macOS/Views/SchedulePanelShellViews.swift",
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
        ]
        var canvases = 0
        var handlers = 0
        for path in hosts {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            canvases += code.components(separatedBy: "TimelineDayCanvas(").count - 1
            handlers += CadenceSourceScan.matchCount(#"onDropAllDayEventAtMinute:"#, in: code)
                - CadenceSourceScan.matchCount(#"let onDropAllDayEventAtMinute:"#, in: code)
        }
        #expect(canvases == hosts.count)
        #expect(handlers == canvases)

        // The host set is the whole set: no other macOS file builds the canvas.
        let others = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS").filter { path in
            !hosts.contains(path) && !path.hasSuffix("TimelineDayCanvas.swift")
        }
        #expect(others.count > 50)
        let stray = try others.filter { path in
            CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                .contains("TimelineDayCanvas(")
        }
        #expect(stray.isEmpty, "\(stray) builds a TimelineDayCanvas this test does not check")
    }
}
#endif
