import Combine
import Foundation
import Testing
@testable import Cadence

#if os(macOS)
/// T-3104: Today must be re-drawn when the day changes, not whenever something else happens to.
@MainActor
struct CadenceDayChangeSupportTests {
    @Test func everyDayChangeSignalReachesTheStreamOnceAndAnUnrelatedPostDoesNot() {
        let names = CadenceDayChangeSupport.notificationNames
        #expect(names.contains(.NSCalendarDayChanged))
        #expect(names.contains(.NSSystemTimeZoneDidChange))
        #expect(names.contains(.NSSystemClockDidChange))
        #expect(Set(names).count == names.count)

        // A private centre, so nothing the host posts can reach the count.
        let center = NotificationCenter()
        var received = 0
        let subscription = CadenceDayChangeSupport.dayMayHaveChanged(on: center).sink { received += 1 }

        center.post(name: Notification.Name("CadenceDayChangeSupportTests.unrelated"), object: nil)
        #expect(received == 0)

        for name in names {
            center.post(name: name, object: nil)
        }
        #expect(received == names.count)
        subscription.cancel()
    }

    @Test func observingTheSameDayIsNotAChangeButANewDayIs() {
        var day = CadenceObservedDay(observedKey: "2026-10-11")

        #expect(day.observe("2026-10-11") == false)
        #expect(day.observedKey == "2026-10-11")

        #expect(day.observe("2026-10-12") == true)
        #expect(day.observedKey == "2026-10-12")
    }

    /// [[T-17442]]: a time zone change that keeps the day still re-runs the adopters' bodies.
    ///
    /// The observer used to compare only the day key, so flying New York -> Chicago at 10:00 left
    /// the key alone, cost no body pass, and every timed surface kept laying its events out in the
    /// old zone -- a 10:00 meeting drawn on the 10 AM row and labelled "10:00 AM" while the
    /// now-line, which ticks on its own schedule, had moved to 9:00. Zones are stated, never read
    /// from the host.
    @Test func aZoneChangeOnTheSameDayIsAChangeAndTheSameZoneIsNot() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        var day = CadenceObservedDay(observedKey: "2026-10-11", observedTimeZone: newYork)

        #expect(day.observe("2026-10-11", timeZone: newYork) == false)
        #expect(day.observe("2026-10-11", timeZone: chicago) == true)
        #expect(day.observedTimeZoneIdentifier == "America/Chicago")
        #expect(day.observe("2026-10-11", timeZone: chicago) == false)
        // A key-only observation still answers on the key alone.
        #expect(day.observe("2026-10-11") == false)
        #expect(day.observe("2026-10-12") == true)
    }

    /// The modifier hands the zone over, or the comparison above is never asked.
    @Test func theModifierObservesTheZoneAsWellAsTheKey() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/Shared/CadenceDayChangeSupport.swift")
        #expect(source.contains("next.observe(DateFormatters.todayKey(), timeZone: Calendar.current.timeZone)"))
    }

    /// **[[T-18186]]: a day held as an instant keeps its day across a zone change.** Nov 16
    /// midnight in New York is Nov 15 21:00 in Los Angeles, so a page that held it and re-read it
    /// in the new zone slid to Sunday. Re-snapped, it keys Monday in the new zone -- and eastward,
    /// where the stale instant happened to read the right day, it still lands on that day's
    /// midnight rather than 05:00.
    @Test func aHeldDayIsResnappedToTheSameDayInTheNewZone() throws {
        let newYork = try CadenceTestTimeZones.calendar("America/New_York")
        let losAngeles = try CadenceTestTimeZones.calendar("America/Los_Angeles")
        let london = try CadenceTestTimeZones.calendar("Europe/London")
        let held = try #require(DateFormatters.date(from: "2026-11-16", in: newYork))

        // The defect, measured: read in Los Angeles, the held instant is the day before.
        #expect(DateFormatters.dateKey(from: held, calendar: losAngeles) == "2026-11-15")

        let west = CadenceTimeZoneChangeSupport.resnappedDay(held, from: newYork.timeZone, to: losAngeles.timeZone)
        #expect(DateFormatters.dateKey(from: west, calendar: losAngeles) == "2026-11-16")
        #expect(west == losAngeles.startOfDay(for: west))

        let east = CadenceTimeZoneChangeSupport.resnappedDay(held, from: newYork.timeZone, to: london.timeZone)
        #expect(DateFormatters.dateKey(from: east, calendar: london) == "2026-11-16")
        #expect(east == london.startOfDay(for: east))

        // Same zone is identity, so a midnight-only signal moves nothing.
        #expect(CadenceTimeZoneChangeSupport.resnappedDay(held, from: newYork.timeZone, to: newYork.timeZone) == held)

        // The observed-day form reads the two zones off the transition.
        let before = CadenceObservedDay(observedKey: "2026-11-16", observedTimeZone: newYork.timeZone)
        let after = CadenceObservedDay(observedKey: "2026-11-16", observedTimeZone: losAngeles.timeZone)
        #expect(CadenceTimeZoneChangeSupport.resnappedDay(held, from: before, to: after) == west)
        #expect(CadenceTimeZoneChangeSupport.resnappedDay(held, from: before, to: before) == held)
    }

    /// **[[T-18187]]: a cache identity names its zone.** Same key, different zone, different
    /// identity -- which is what makes iOS's window and Today fetches re-run on a same-day change.
    @Test func aZoneScopedKeyMovesWithTheZoneAndNotWithoutIt() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let key = "timeline:2026-11-16"
        #expect(CadenceTimeZoneChangeSupport.zoneScopedKey(key, timeZone: newYork)
                == CadenceTimeZoneChangeSupport.zoneScopedKey(key, timeZone: newYork))
        #expect(CadenceTimeZoneChangeSupport.zoneScopedKey(key, timeZone: newYork)
                != CadenceTimeZoneChangeSupport.zoneScopedKey(key, timeZone: losAngeles))
        #expect(CadenceTimeZoneChangeSupport.zoneScopedKey(key, timeZone: newYork).hasPrefix(key))
    }

    /// Every page that holds a day as an instant re-snaps it on the zone transition, and every iOS
    /// EventKit fetch key names the zone. Read from source: the iOS views never compile here.
    @Test func bothCalendarPagesResnapTheirHeldDaysAndKeyTheirFetchesByZone() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/CalendarPageView.swift")
        #expect(mac.contains("calendarAnchorDay = CadenceTimeZoneChangeSupport.resnappedDay(calendarAnchorDay, from: old, to: new)"))
        #expect(mac.contains("selectedBoardDate = CadenceTimeZoneChangeSupport.resnappedDay(selectedBoardDate, from: old, to: new)"))
        #expect(mac.contains("private var cal: Calendar { Calendar.current }"))

        let iOS = try read("Cadence/iOS/iOSCalendarView.swift")
        #expect(iOS.contains("selectedDate = CadenceTimeZoneChangeSupport.resnappedDay(selectedDate, from: old, to: new)"))
        #expect(iOS.contains("anchorDate = CadenceTimeZoneChangeSupport.resnappedDay(anchorDate, from: old, to: new)"))
        #expect(iOS.contains("private var calendar: Calendar { Calendar.current }"))
        #expect(iOS.contains("CadenceTimeZoneChangeSupport.zoneScopedKey(eventWindowDayKey)"))

        let today = try read("Cadence/iOS/iOSTodaySchedulePanel.swift")
        #expect(today.contains("CadenceTimeZoneChangeSupport.zoneScopedKey(todayKey)"))
        #expect(today.contains(".onChange(of: todayFetchKey)"))
    }

    /// Both views are behind their platform's `#if`, and the iOS one never compiles in this
    /// target, so the wiring is read from source: the key goes through the observed day, and the
    /// body installs the observer on that same state exactly once.
    @Test func bothTodaySurfacesReadTheirDayThroughTheObserverTheyInstall() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        for path in ["Cadence/macOS/Views/TasksPanel.swift", "Cadence/iOS/iOSTodayView.swift"] {
            let source = try read(path)
            #expect(source.contains("@State private var observedDay = CadenceObservedDay()"), "\(path)")
            #expect(source.contains("private var todayKey: String { observedDay.todayKey }"), "\(path)")
            // A second clock read would be a key the observer does not invalidate.
            #expect(source.contains("DateFormatters.todayKey()") == false, "\(path)")

            let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
            #expect(body.components(separatedBy: ".cadenceTracksDayChanges($observedDay)").count - 1 == 1, "\(path)")
        }
    }
}
#endif
