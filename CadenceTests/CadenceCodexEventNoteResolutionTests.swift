import EventKit
import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexEventNoteResolutionTests {
    @Test func codexScopedNoteResolutionNeverUsesTheSeriesBaseLookup() throws {
        let base = try recurringEvent(on: "2026-10-05")
        let occurrence = try recurringEvent(on: "2026-10-12")
        let identifier = CadenceEventNoteSupport.identifier(for: occurrence)
        #expect(CadenceEventNoteSupport.occurrenceDateKey(from: identifier) == "2026-10-12")
        var baseLookups = 0
        var fetchedDays: [String] = []
        let resolved = CadenceEventNoteSupport.resolveEvent(
            calendarEventID: identifier,
            eventDateKey: "2026-10-12",
            lookupBaseEvent: { _ in baseLookups += 1; return base },
            eventsForDay: { day in
                fetchedDays.append(DateFormatters.dateKey(from: day))
                return [base, occurrence]
            }
        )
        #expect(resolved === occurrence)
        #expect(baseLookups == 0)
        #expect(fetchedDays == ["2026-10-12"])
    }

    @Test func codexMissingOccurrenceIsNotReplacedByAnAvailableBaseEvent() throws {
        let base = try recurringEvent(on: "2026-10-05")
        let absent = try recurringEvent(on: "2026-10-12")
        var baseLookups = 0
        let resolved = CadenceEventNoteSupport.resolveEvent(
            calendarEventID: CadenceEventNoteSupport.identifier(for: absent),
            eventDateKey: "2026-10-12",
            lookupBaseEvent: { _ in baseLookups += 1; return base },
            eventsForDay: { _ in [base] }
        )
        #expect(resolved == nil)
        #expect(baseLookups == 0)
    }

    @Test func codexNoteResolutionAlsoSearchesItsStoredEventDay() throws {
        let occurrence = try recurringEvent(on: "2026-10-12")
        var fetchedDays: [String] = []
        // The provider seam models an occurrence returned only on its new day; no native event is moved.
        let resolved = CadenceEventNoteSupport.resolveEvent(
            calendarEventID: CadenceEventNoteSupport.identifier(for: occurrence),
            eventDateKey: "2026-10-13",
            lookupBaseEvent: { _ in Issue.record("a scoped note used base lookup"); return nil },
            eventsForDay: { day in
                let key = DateFormatters.dateKey(from: day)
                fetchedDays.append(key)
                return key == "2026-10-13" ? [occurrence] : []
            }
        )
        #expect(resolved === occurrence)
        #expect(fetchedDays == ["2026-10-12", "2026-10-13"])
    }

    @Test(arguments: [
        "event#occurrence=", "event#occurrence=2026-10-12", "event#occurrence=2026-10-12:-1",
        "event#occurrence=2026-10-12:1440", "event#occurrence=2026-10-12:noon",
        "event#occurrence=2026-10-99:540", "event#occurrence=2026-1-2:540",
        "#occurrence=2026-10-12:540", "event#occurrence=2026-10-12:540#occurrence=2026-10-19:540"
    ])
    func codexMalformedOccurrenceIdentityCannotFallBackToBase(_ identifier: String) {
        var calls = 0
        let resolved = CadenceEventNoteSupport.resolveEvent(
            calendarEventID: identifier,
            eventDateKey: "2026-10-12",
            lookupBaseEvent: { _ in calls += 1; return nil },
            eventsForDay: { _ in calls += 1; return [] }
        )
        #expect(resolved == nil)
        #expect(calls == 0)
    }

    @Test func codexUnscopedNoteKeepsItsDirectEventLookup() throws {
        let event = EKEvent(eventStore: EKEventStore())
        var lookedUp: [String] = []
        let resolved = CadenceEventNoteSupport.resolveEvent(
            calendarEventID: "one-off",
            eventDateKey: "2026-10-12",
            lookupBaseEvent: { lookedUp.append($0); return event },
            eventsForDay: { _ in Issue.record("a one-off note fetched occurrences"); return [] }
        )
        #expect(resolved === event)
        #expect(lookedUp == ["one-off"])
        #expect(CadenceEventNoteSupport.resolveEvent(
            calendarEventID: "", eventDateKey: "", lookupBaseEvent: { _ in event }, eventsForDay: { _ in [event] }
        ) == nil)
    }

    @Test func codexEventNoteCallersUseTheOccurrenceAwareResolver() throws {
        let rule = try CadenceScanInstrument(
            "meeting-note occurrence resolution",
            fires: "let event = calendarManager.event(for: note)",
            andNotOn: "// calendarManager.event(for: note)\nlet event = calendarManager.event(withIdentifier: id)",
            by: { CadenceSourceScan.codeOnly($0).contains("calendarManager.event(for: note)") }
        )
        let notesPath = "Cadence/iOS/iOSNotesView.swift"
        let paths = [notesPath, "Cadence/iOS/iOSSearchView.swift", "Cadence/iOS/iOSEventNoteEditorSheet.swift",
                     "Cadence/macOS/Views/EventNoteSupportViews.swift"]
        #expect(try rule.sweep(paths, atLeast: 4, including: notesPath, read: CadenceSourceScan.strippedSourceReader()) == paths.sorted())
        let managerRule = try CadenceScanInstrument(
            "platform note resolver forwarding",
            fires: "CadenceEventNoteSupport.resolveEvent(calendarEventID: id)",
            andNotOn: "// CadenceEventNoteSupport.resolveEvent(calendarEventID: id)\nlookupIdentifier(from: id)",
            by: { CadenceSourceScan.codeOnly($0).contains("CadenceEventNoteSupport.resolveEvent(") }
        )
        let managerPath = "Cadence/macOS/Services/CalendarManager.swift"
        let managers = [managerPath, "Cadence/iOS/iOSCalendarManager.swift"]
        #expect(try managerRule.sweep(managers, atLeast: 2, including: managerPath, read: CadenceSourceScan.strippedSourceReader()) == managers.sorted())
        for path in ["Cadence/iOS/iOSEventNoteEditorSheet.swift", "Cadence/macOS/Views/EventNoteSupportViews.swift"] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("CadenceEventNoteSupport.matches("), "\(path) accepts an unrelated live event")
        }
    }

    private func recurringEvent(on day: String) throws -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Weekly meeting"
        event.startDate = try #require(DateFormatters.date(from: day)).addingTimeInterval(9 * 3600)
        event.endDate = event.startDate.addingTimeInterval(1800)
        event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        return event
    }
}
