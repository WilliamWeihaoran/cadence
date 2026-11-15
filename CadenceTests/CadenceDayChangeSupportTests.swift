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
