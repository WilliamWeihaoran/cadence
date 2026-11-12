import Foundation
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
}
