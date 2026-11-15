#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-17788]] — an empty Mac Today timeline said nothing about how to fill it.**
///
/// iOS's Today timeline has drawn "No timed blocks yet — press and hold an hour to add one." while
/// its grid is empty; the Mac's `SchedulePanel` drew no line at all, so a fresh install showed a
/// blank task column beside a blank hour grid. Both hosts now build the line from
/// `CadenceTodayPresentationSupport.emptyTimelineHint(_:)`, and only the gesture differs.
@MainActor
struct MacTodayTimelineEmptyHintTests {
    @Test func bothHostsSayOneSentenceWithTheirOwnVerb() {
        let mac = CadenceTodayPresentationSupport.emptyTimelineHint(.drag)
        #expect(mac == "No timed blocks yet — drag across the hours to add one.")
        // iOS's value is unchanged by moving it onto the builder.
        #expect(iOSSchedulePanelCopy.emptyScheduleHint == "No timed blocks yet — press and hold an hour to add one.")
        #expect(iOSSchedulePanelCopy.emptyScheduleHint == CadenceTodayPresentationSupport.emptyTimelineHint(.pressAndHold))
        #expect(mac != iOSSchedulePanelCopy.emptyScheduleHint, "the verb is supposed to differ")
    }

    /// A scheduled task or a timed event is a block; all-day events are not counted, because the
    /// caller hands in the timed half only.
    @Test func theHintIsForAnEmptyLadderOnly() {
        #expect(SchedulePanelDataSupport.isTimelineEmpty(scheduledTaskCount: 0, timedEventCount: 0))
        #expect(SchedulePanelDataSupport.isTimelineEmpty(scheduledTaskCount: 1, timedEventCount: 0) == false)
        #expect(SchedulePanelDataSupport.isTimelineEmpty(scheduledTaskCount: 0, timedEventCount: 1) == false)
        #expect(SchedulePanelDataSupport.isTimelineEmpty(scheduledTaskCount: 2, timedEventCount: 3) == false)
    }

    /// The panel draws the Mac sentence, gated on the predicate, and reads the timed events only.
    @Test func theMacPanelDrawsTheDragSentence() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let panel = try read("Cadence/macOS/Views/SchedulePanel.swift")
        #expect(panel.components(separatedBy: "CadenceTodayPresentationSupport.emptyTimelineHint(.drag)").count == 2)
        #expect(panel.components(separatedBy: "SchedulePanelDataSupport.isTimelineEmpty(").count == 2)
        #expect(panel.contains("timedEventCount: externalEventItems.count"))
        #expect(panel.contains("pressAndHold") == false, "the Mac grid is not pressed and held")
    }

    /// The verb is the grid's real gesture: creation is a `DragGesture`, and a plain click on the
    /// background clears the selection. If either changes, the sentence has to be re-read.
    @Test func theVerbIsTheGridsOwnGesture() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let layer = try read("Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift")
        #expect(layer.contains("DragGesture(minimumDistance:"))
        #expect(layer.contains(".onTapGesture(perform: onTapBackground)"))
    }
}
#endif
