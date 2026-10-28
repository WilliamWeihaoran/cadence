#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-7986 — Cmd+\ did nothing on Mac Today in the tasks-only layout.**
///
/// On Today the shortcut closed the overlay and asked `TodayTimelineFocusManager` to focus the
/// page's Timeline pane — whose only listener is `SchedulePanel`, which `TodayView` does not build
/// in `CadenceDesktopTodayLayout.tasksOnly`. The decision now asks whether that pane is mounted
/// and, when it is not, takes the overlay arm every other page takes.
@MainActor
struct MacTimelineShortcutDecisionTests {
    private typealias Support = RootCommandActionSupport

    @Test("Today in the tasks-only layout toggles the overlay instead of focusing a missing pane")
    func tasksOnlyTodayTogglesTheOverlay() {
        #expect(
            Support.timelineShortcutAction(
                selection: .today, showTimelineSidebar: false, isTodayTimelinePaneMounted: false
            ) == .setOverlay(true)
        )
        #expect(
            Support.timelineShortcutAction(
                selection: .today, showTimelineSidebar: true, isTodayTimelinePaneMounted: false
            ) == .setOverlay(false)
        )
        // `nil` selection draws Today too (`RootDetailContent`), so it decides the same way.
        #expect(
            Support.timelineShortcutAction(
                selection: nil, showTimelineSidebar: false, isTodayTimelinePaneMounted: false
            ) == .setOverlay(true)
        )
    }

    @Test("Today with its pane mounted still focuses it, closing an open overlay first")
    func mountedTodayFocusesThePane() {
        #expect(
            Support.timelineShortcutAction(
                selection: .today, showTimelineSidebar: false, isTodayTimelinePaneMounted: true
            ) == .focusTodayPane(closeOverlay: false)
        )
        #expect(
            Support.timelineShortcutAction(
                selection: .today, showTimelineSidebar: true, isTodayTimelinePaneMounted: true
            ) == .focusTodayPane(closeOverlay: true)
        )
    }

    @Test("Another page toggles the overlay whatever Today's pane last reported")
    func otherPagesToggleTheOverlay() {
        for mounted in [false, true] {
            #expect(
                Support.timelineShortcutAction(
                    selection: .calendar, showTimelineSidebar: false, isTodayTimelinePaneMounted: mounted
                ) == .setOverlay(true)
            )
        }
    }

    @Test("The pane is mounted in every layout but tasks-only, by the rule TodayView mounts it on")
    func theMountRuleMatchesTheLayouts() throws {
        #expect(!CadenceDesktopSplitLayout.todayLayoutMountsTimelinePane(.tasksOnly))
        #expect(CadenceDesktopSplitLayout.todayLayoutMountsTimelinePane(.tasksAndSchedule))
        #expect(CadenceDesktopSplitLayout.todayLayoutMountsTimelinePane(.notesTasksAndSchedule))

        // TodayView both mounts on it and publishes it, so the two cannot disagree.
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TodayView.swift")
        )
        #expect(code.components(separatedBy: "CadenceDesktopSplitLayout.todayLayoutMountsTimelinePane(").count - 1 == 2)
        #expect(code.components(separatedBy: "isTodayTimelinePaneMounted").count - 1 == 2)
    }
}
#endif
