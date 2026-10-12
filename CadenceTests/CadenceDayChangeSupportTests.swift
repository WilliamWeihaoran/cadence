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
