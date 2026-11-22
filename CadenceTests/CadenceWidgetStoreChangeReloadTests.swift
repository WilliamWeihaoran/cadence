import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// [[T-17311]]: a save in the Mac app reloads the widgets, and the last save of a burst is never
/// dropped by the reload throttle.
///
/// The defect: macOS's only reload ran when the app left active, which [[T-1176]] measured to be
/// HIDE, not blur, so the desktop Today widget kept counting a task the user had just finished
/// for up to 15 minutes. `reloadAllWidgets`' throttle would also have swallowed the second of two
/// quick completions; the reloader schedules one trailing reload instead.
@MainActor
struct CadenceWidgetStoreChangeReloadTests {
    /// A fake clock, a fake last-reload stamp and a hand-run scheduler, so nothing here touches
    /// WidgetKit or the app group.
    final class Harness {
        var now = Date(timeIntervalSince1970: 10_000)
        var lastReload: Date?
        var reloads: [Date] = []
        var scheduled: [(delay: TimeInterval, work: @MainActor () -> Void)] = []

        @MainActor
        func makeReloader() -> CadenceWidgetStoreChangeReloader {
            CadenceWidgetStoreChangeReloader(
                minimumInterval: 15,
                now: { [unowned self] in self.now },
                lastReload: { [unowned self] in self.lastReload },
                reload: { [unowned self] in
                    self.reloads.append(self.now)
                    self.lastReload = self.now
                },
                schedule: { [unowned self] delay, work in
                    self.scheduled.append((delay, work))
                }
            )
        }
    }

    @Test func aSaveWithNoRecentReloadReloadsAtOnce() {
        let harness = Harness()
        let reloader = harness.makeReloader()

        reloader.storeDidSave()
        #expect(harness.reloads.count == 1)
        #expect(harness.scheduled.isEmpty)

        harness.now = harness.now.addingTimeInterval(20)
        reloader.storeDidSave()
        #expect(harness.reloads.count == 2, "a save outside the window reloads again at once")
        #expect(harness.scheduled.isEmpty)
    }

    /// The owner's case: two tasks ticked off ten seconds apart. The first reloads; the second
    /// lands inside the throttle window and must leave exactly one reload waiting for the window's
    /// end, not be dropped -- and a third save before it fires adds nothing.
    @Test func aSaveInsideTheWindowSchedulesOneTrailingReloadInsteadOfDroppingIt() {
        let harness = Harness()
        let reloader = harness.makeReloader()

        reloader.storeDidSave()
        #expect(harness.reloads.count == 1)

        harness.now = harness.now.addingTimeInterval(10)
        reloader.storeDidSave()
        #expect(harness.reloads.count == 1, "inside the window nothing reloads yet")
        #expect(harness.scheduled.count == 1, "the second save was dropped: the widget stays one change behind")
        #expect(harness.scheduled.first?.delay == 5)
        #expect(reloader.hasPendingReload)

        harness.now = harness.now.addingTimeInterval(2)
        reloader.storeDidSave()
        #expect(harness.scheduled.count == 1, "a save while a reload is waiting rides on it")

        harness.now = harness.now.addingTimeInterval(3)
        harness.scheduled.first?.work()
        #expect(harness.reloads.count == 2, "the trailing reload ran")
        #expect(!reloader.hasPendingReload)

        harness.now = harness.now.addingTimeInterval(1)
        reloader.storeDidSave()
        #expect(harness.scheduled.count == 2, "after the trailing reload the next save in its window schedules again")
    }

    /// A last-reload stamp in the future (the clock stepped back) must not hold every reload for the
    /// size of the step.
    @Test func aReloadStampInTheFutureDoesNotStallReloads() {
        let harness = Harness()
        harness.lastReload = harness.now.addingTimeInterval(3_600)
        let reloader = harness.makeReloader()

        reloader.storeDidSave()
        #expect(harness.reloads.count == 1)
        #expect(harness.scheduled.isEmpty)
    }

    #if os(macOS)
    /// The wiring is a SwiftUI modifier no unit test can fire, so its shape is pinned here: the
    /// Mac's observer listens for `ModelContext.didSave`, outside the scene-phase handler, skips
    /// test hosts, and hands the save to the reloader.
    @Test func theMacObserverReloadsWidgetsOnEveryStoreSave() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift"))
        let start = try #require(source.range(of: "private struct NotificationReconcileObserver: View"))
        let observer = String(source[start.lowerBound...])
        let scenePhase = try #require(observer.range(of: ".onChange(of: scenePhase)"))
        let beforeScenePhase = String(observer[..<scenePhase.lowerBound])

        #expect(beforeScenePhase.contains("CadenceWidgetStoreChangeReloader()"))
        #expect(beforeScenePhase.contains(".onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave))"))
        #expect(beforeScenePhase.contains("guard !NotificationManager.isTestEnvironment else { return }"))
        #expect(beforeScenePhase.contains("widgetReloader.storeDidSave()"))
    }
    #endif

    // MARK: - [[T-18590]]: a day or zone change reloads the Mac's widgets

    /// Only a signal that moves the key or the zone reloads; a same-day activation, which is in the
    /// stream too, costs nothing.
    @Test func aDayOrZoneChangeReloadsTheWidgetsAndASameDaySignalDoesNot() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        var reloads = 0
        let reloader = CadenceWidgetDayChangeReloader(
            observedDay: CadenceObservedDay(observedKey: "2026-11-20", observedTimeZone: newYork),
            reload: { reloads += 1 }
        )

        reloader.dayMayHaveChanged(key: "2026-11-20", timeZone: newYork)
        #expect(reloads == 0, "a same-day, same-zone signal reloaded the widgets")

        reloader.dayMayHaveChanged(key: "2026-11-20", timeZone: chicago)
        #expect(reloads == 1, "a zone change on the same day left the widgets drawing the old zone")

        reloader.dayMayHaveChanged(key: "2026-11-20", timeZone: chicago)
        #expect(reloads == 1, "the zone change was not recorded, so every later signal reloads")

        reloader.dayMayHaveChanged(key: "2026-11-21", timeZone: chicago)
        #expect(reloads == 2, "the day rolling over did not reload the widgets")
    }

    #if os(macOS)
    /// The wiring is a SwiftUI modifier no unit test can fire, so its shape is pinned: the Mac's
    /// observer holds one day reloader, feeds it the shared day-change stream, and skips test hosts.
    @Test func theMacObserverReloadsWidgetsOnADayChange() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift"))
        let start = try #require(source.range(of: "private struct NotificationReconcileObserver: View"))
        let observer = String(source[start.lowerBound...])
        #expect(observer.contains("@State private var widgetDayReloader = CadenceWidgetDayChangeReloader()"))
        let handler = try #require(
            CadenceSourceScan.declarationBody(".onReceive(CadenceDayChangeStream.main.publisher)", in: observer),
            "the Mac observer no longer listens for a day change"
        )
        #expect(handler.contains("guard !NotificationManager.isTestEnvironment else { return }"))
        #expect(handler.contains("widgetDayReloader.dayMayHaveChanged()"), "a day change no longer reaches the widgets")
    }
    #endif

    // MARK: - [[T-18674]]: iOS reloads on the leaving-active edge, forced

    /// Every one of the nine (from, to) pairs. Only leaving `.active` reloads: arriving through
    /// `.inactive` must not, because that reload stamped the throttle and the departure a few
    /// seconds later was dropped, so the home-screen widget kept a task ticked in the app.
    @Test func onlyTheLeavingActiveEdgeReloadsTheWidgets() {
        let phases: [(ScenePhase, String)] = [(.active, "active"), (.inactive, "inactive"), (.background, "background")]
        var reloading: [String] = []
        var visited = 0
        for (from, fromName) in phases {
            for (to, toName) in phases {
                visited += 1
                if CadenceWidgetRefreshCenter.reloadsOnScenePhaseChange(from: from, to: to) {
                    reloading.append("\(fromName)->\(toName)")
                }
            }
        }
        #expect(visited == 9)
        #expect(reloading.sorted() == ["active->background", "active->inactive"])
        // The arrival path that caused the defect, named outright.
        #expect(!CadenceWidgetRefreshCenter.reloadsOnScenePhaseChange(from: .background, to: .inactive))
        #expect(!CadenceWidgetRefreshCenter.reloadsOnScenePhaseChange(from: .inactive, to: .background))
    }

    /// The iOS observer is a SwiftUI modifier no unit test can fire, and `Cadence/iOS/` is not
    /// compiled into this target, so its shape is pinned: the reload is gated on the edge decision
    /// and forced, and no throttled reload remains in the observer.
    @Test func theIOSObserverReloadsForcedOnTheLeavingEdgeOnly() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift"))
        let observer = try #require(CadenceSourceScan.declarationBody(".onChange(of: scenePhase)", in: source))
        let gate = "if CadenceWidgetRefreshCenter.reloadsOnScenePhaseChange(from: oldPhase, to: phase)"
        let branch = try #require(CadenceSourceScan.declarationBody(gate, in: observer), "the reload is not gated on the leaving edge")
        #expect(branch.contains("CadenceWidgetRefreshCenter.reloadAllWidgets(force: true)"), "the departure reload is throttled again")
        #expect(
            observer.components(separatedBy: "CadenceWidgetRefreshCenter.reloadAllWidgets(").count - 1 == 1,
            "the observer reloads widgets outside the leaving edge"
        )
        #expect(!observer.contains("if phase != .active {"), "the observer reloads on arriving through .inactive again")
    }
}
