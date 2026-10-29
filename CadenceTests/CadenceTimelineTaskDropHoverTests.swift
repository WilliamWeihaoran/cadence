#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// **[[T-8142]]: a task dragged over an iOS day column shows where it will land before the
/// release, in the plate the Mac canvas has always drawn** -- and **[[T-8143]]: the Calendar page
/// that column sits on can start such a drag, from its own unscheduled chips.**
///
/// The rule half (`CadenceTimelineTaskDropHover`) is Shared and asked directly. The iOS wiring
/// cannot compile in this macOS-built target, so it is read from source.
@MainActor
struct CadenceTimelineTaskDropHoverTests {
    private let hourHeight: CGFloat = 60
    private let timelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"

    private func y(forMinute minute: Int) -> CGFloat {
        CGFloat(minute - CadenceScheduleSupport.calendarStartHour * 60) / 60 * hourHeight
    }

    // MARK: - The rule

    /// Away from the edges the plate starts on exactly the quarter-hour the column's own tap would
    /// name, whatever the task's length -- the hover adds a clamp, never a second arithmetic.
    @Test func awayFromTheEdgesTheHoverStartsOnTheColumnsOwnTapMinute() {
        var checked = 0
        for minute in stride(from: 8 * 60, through: 18 * 60, by: 7) {
            let point = y(forMinute: minute) + 3
            let tap = CadenceScheduleSupport.timelineMinute(atY: point, hourHeight: hourHeight)
            for duration in [nil, 5, 30, 90] as [Int?] {
                let hover = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: duration)
                #expect(hover.startMinute == tap, "a \(String(describing: duration))-minute hover at \(minute) left the tap's minute")
                checked += 1
            }
        }
        #expect(checked > 100, "non-vacuity: \(checked) points checked")
    }

    /// Until the payload names a task, the plate claims the start and one touch-grid step, not an
    /// invented length; once it does, the plate is the task's own length.
    @Test func thePlateIsOneGridStepUntilTheTaskIsKnownAndItsOwnLengthAfter() {
        let point = y(forMinute: 10 * 60 + 30)
        let unknown = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: nil)
        #expect(unknown.durationMinutes == nil)
        #expect(unknown.drawnRange.end - unknown.drawnRange.start == CadenceScheduleSupport.touchTimeGridMinutes)

        let known = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: 90)
        #expect(known.startMinute == unknown.startMinute)
        #expect(known.drawnRange.start == known.startMinute)
        #expect(known.drawnRange.end - known.drawnRange.start == 90)
    }

    /// The Mac's [[T-5370]] clamp, read for touch: a known task hovered at the bottom of the day
    /// lands where the whole block still fits, not where it would run past the last hour. A
    /// relation, not a pinned minute.
    @Test func aKnownTaskAtTheBottomOfTheDayIsHeldWhereTheWholeBlockFits() {
        let dayEnd = CadenceScheduleSupport.calendarEndHour * 60
        let point = y(forMinute: dayEnd - 10)
        let tap = CadenceScheduleSupport.timelineMinute(atY: point, hourHeight: hourHeight)
        for duration in [30, 60, 120] {
            let hover = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: duration)
            #expect(hover.startMinute + duration <= dayEnd, "a \(duration)-minute hover runs past the drawn day")
            #expect(hover.startMinute < tap, "non-vacuity: the \(duration)-minute clamp moved nothing")
            #expect(hover.drawnRange.end <= dayEnd)
        }
        // An unknown length keeps the start-only clamp the tap already has.
        let unknown = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: nil)
        #expect(unknown.startMinute == tap)
    }

    // MARK: - The wiring

    /// The column answers a hovering task, through a delegate that computes the hover and the
    /// release with the same call, and puts the plate away when the finger leaves or lets go.
    @Test func theIOSColumnDrawsTheHoverPlateAndClearsItOnExitAndRelease() throws {
        let source = try CadenceSourceScan.sourceFile(timelineFile)
        let code = CadenceSourceScan.strippingComments(source)
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code)
        )
        #expect(column.count > 1_000, "non-vacuity: the day column read as \(column.count) characters")
        #expect(CadenceSourceScan.matchCount(#"\n\s*taskDropHoverLayer\s*\n\s*\.zIndex\("#, in: column) == 1,
                "the column no longer draws the hovering task's plate")
        #expect(CadenceSourceScan.matchCount(#"hover: \$taskDropHover,"#, in: column) == 1)
        let layer = try #require(column.range(of: "private var taskDropHoverLayer: some View").map { String(column[$0.lowerBound...]) })
        #expect(CadenceSourceScan.matchCount(#"if let taskDropHover \{"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.fillOpacity"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.strokeOpacity"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.allowsHitTesting\(false\)"#, in: layer) >= 1,
                "the plate takes the hit and swallows the drop it is previewing")

        let delegate = try #require(
            CadenceSourceScan.declarationBody("private struct iOSTimelineTaskDropDelegate: DropDelegate", in: code)
        )
        let exited = try #require(CadenceSourceScan.declarationBody("func dropExited(info: DropInfo)", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"hover = nil"#, in: exited) == 1, "the plate outlives the finger leaving")
        let perform = try #require(CadenceSourceScan.declarationBody("func performDrop(info: DropInfo) -> Bool", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"hover = nil"#, in: perform) == 1, "the plate outlives the release")
        #expect(CadenceSourceScan.matchCount(#"_ = onDrop\(id, minute\)"#, in: perform) == 1)
        // The release measures with the task's own length, as the hover did, so the minute the
        // plate showed is the minute written.
        #expect(CadenceSourceScan.matchCount(#"durationMinutes: resolveTask\(id\)\?\.timelineDurationMinutes"#, in: perform) == 1,
                "the release resolves its minute without the task's length, so it can land off the plate")
        let updated = try #require(CadenceSourceScan.declarationBody("func dropUpdated(info: DropInfo) -> DropProposal?", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"updateHover\(with: info\)"#, in: updated) == 1,
                "the plate no longer follows the finger")
    }

    /// One plate on both platforms: the Mac preview reads its two figures from the same place.
    @Test func theMacPreviewReadsTheSamePlateFigures() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift")
        )
        let preview = try #require(CadenceSourceScan.declarationBody("struct TimelineDraggedTaskPreview: View", in: mac))
        #expect(CadenceSourceScan.matchCount(#"Theme\.blue\.opacity\(CadenceTimelineTaskDropHover\.fillOpacity\)"#, in: preview) == 1)
        #expect(CadenceSourceScan.matchCount(#"Theme\.blue\.opacity\(CadenceTimelineTaskDropHover\.strokeOpacity\)"#, in: preview) == 1)
    }

    /// Both hosts resolve the hovering task through the lookup their commit makes.
    @Test func bothHostsResolveTheHoveringTaskThroughTheCommitsLookup() throws {
        for file in ["Cadence/iOS/iOSTodaySchedulePanel.swift", "Cadence/iOS/iOSCalendarView.swift"] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
            #expect(
                CadenceSourceScan.matchCount(#"resolveDroppedTask: \{ CadenceTimelineBlockEdit\.droppedTask\(\$0, among: allTasks\) \}"#, in: source) == 1,
                "\(file) resolves a hovering task some other way than its commit does"
            )
        }
        let shared = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTimelineBlockEditSupport.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"guard let task = droppedTask\(taskID, among: tasks\)"#, in: shared) == 1)
    }

    /// [[T-8143]]: the Calendar page's unscheduled chips drag as their task, and a tap on one still
    /// selects the day, as it did when the chip let the tap fall through.
    @Test func theUnscheduledBandChipDragsAsItsTaskAndStillSelectsTheDay() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(timelineFile))
        let chips = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarAllDayBandChips: View", in: code)
        )
        let tasks = try #require(chips.range(of: "ForEach(unscheduledTasks.prefix(split.tasks))"))
        let overflow = try #require(chips.range(of: "if split.hidden > 0"))
        let taskStack = String(chips[tasks.lowerBound..<overflow.lowerBound])
        #expect(CadenceSourceScan.matchCount(#"\.draggable\(TaskDragPayload\.string\(for: task\.id\)\)"#, in: taskStack) == 1,
                "the unscheduled chip no longer offers its task to the grid")
        #expect(CadenceSourceScan.matchCount(#"\.allowsHitTesting\(false\)"#, in: taskStack) == 0,
                "the unscheduled chip takes no hit again, so it cannot start a drag")
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture \{ onSelectDay\?\(\) \}"#, in: taskStack) == 1,
                "a tap on the chip no longer selects the day")

        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader: View", in: code)
        )
        #expect(CadenceSourceScan.matchCount(#"onSelectDay: action"#, in: header) == 1,
                "the week header no longer hands its select-the-day action to the chips it draws over")
    }
}
#endif
