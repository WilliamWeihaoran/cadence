#if os(macOS)
import Foundation
import Testing
@testable import Cadence

struct CadenceCodexTimelineBlockRemovalTests {
    @Test func timelineDropHasOnlyTaskAndEventArmsAfterBlockRetirement() throws {
        for file in ["TimelineDropInteractionSupport", "TimelineDayCanvas", "TimelineDayCanvasStateSupport"] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/\(file).swift"))
            #expect(!source.isEmpty)
            for symbol in ["TaskBundle", "allBundles", "onDropBundleAtMinute", "activeDragBundleID", "selectedBundleID"] {
                #expect(CadenceSourceScan.matchCount("\\b\(symbol)\\b", in: source) == 0, "\(file): retired \(symbol)")
            }
        }
        let drop = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDropInteractionSupport.swift"))
        #expect(drop.contains("CalendarEventDragPayload.allDayEventPayload(from: payloadString)"))
        #expect(drop.contains("onDropTaskAtMinute(task, startMin)"))
        #expect(drop.contains("onDropAllDayEventAtMinute?(eventPayload, startMin)"))
        #expect(drop.contains("dragYOffset = info.location.y - taskTopY"))
    }

    @Test func clearingRetiredTimelineSelectionStillClearsTasksEventsAndDrafts() {
        var taskID: UUID? = UUID()
        var eventID: String? = "event"
        var dragID: UUID? = UUID()
        var draft: TimelineDraftSelection? = .pending(start: 540, end: 570)
        var showing = true
        TimelineDayCanvasStateSupport.resetCanvasSelection(
            selectedTaskID: &taskID, selectedEventID: &eventID, activeDragTaskID: &dragID,
            draft: &draft, showNewTaskPopover: &showing
        )
        #expect(taskID == nil)
        #expect(eventID == nil)
        #expect(dragID == nil)
        #expect(draft == nil)
        #expect(!showing)
    }
}
#endif
