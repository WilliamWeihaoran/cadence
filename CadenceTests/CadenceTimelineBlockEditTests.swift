#if os(macOS)
import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-1475]]: an existing iOS timeline block moves and edge-resizes its own time.**
///
/// The arithmetic and the commit are shared (`CadenceTimelineBlockEdit`), so they are asked here
/// directly; the iOS surface that drives them cannot compile in this macOS target, so its wiring
/// is read from source. Every figure below is a relation — minutes out for a drag offset in, one
/// end pinned while the other moves, the stored fields before and after a refusal — never a
/// layout constant.
@MainActor
struct CadenceTimelineBlockEditTests {

    /// Points per hour for the arithmetic. Any positive value gives the same relations; one hour
    /// of travel is `hourHeight` points by definition.
    private let hourHeight: CGFloat = 58

    private func points(forMinutes minutes: Int) -> CGFloat {
        CGFloat(minutes) / 60 * hourHeight
    }

    // MARK: - Drag offset -> minutes

    @Test func aDragOffsetBecomesTheMinutesItSpansOnTheTouchGrid() {
        let grid = CadenceTimelineBlockEdit.gridMinutes
        #expect(grid == CadenceScheduleSupport.touchTimeGridMinutes)
        for steps in [-3, -1, 1, 2, 4] {
            let delta = CadenceTimelineBlockEdit.snappedMinuteDelta(
                translationY: points(forMinutes: steps * grid),
                hourHeight: hourHeight
            )
            #expect(delta == steps * grid)
        }
        // Under half a step either way is no step; over half is the nearer line.
        let justUnderHalf = points(forMinutes: grid) * 0.45
        let justOverHalf = points(forMinutes: grid) * 0.55
        #expect(CadenceTimelineBlockEdit.snappedMinuteDelta(translationY: justUnderHalf, hourHeight: hourHeight) == 0)
        #expect(CadenceTimelineBlockEdit.snappedMinuteDelta(translationY: -justUnderHalf, hourHeight: hourHeight) == 0)
        #expect(CadenceTimelineBlockEdit.snappedMinuteDelta(translationY: justOverHalf, hourHeight: hourHeight) == grid)
        #expect(CadenceTimelineBlockEdit.snappedMinuteDelta(translationY: -justOverHalf, hourHeight: hourHeight) == -grid)
    }

    @Test func aMoveSlidesBothEndsByTheDragAndKeepsTheDuration() {
        let start = 9 * 60 + 7
        let end = start + 50
        let moved = CadenceTimelineBlockEdit.editedRange(
            kind: .move, start: start, end: end,
            translationY: points(forMinutes: 90), hourHeight: hourHeight
        )
        #expect(moved.start - start == 90)
        #expect(moved.end - moved.start == end - start)

        let earlier = CadenceTimelineBlockEdit.editedRange(
            kind: .move, start: start, end: end,
            translationY: points(forMinutes: -30), hourHeight: hourHeight
        )
        #expect(start - earlier.start == 30)
        #expect(earlier.end - earlier.start == end - start)
    }

    @Test func aPressThatNeverTravelsAStepLeavesTheRangeAlone() {
        for kind in [CadenceTimelineBlockEdit.Kind.move, .resizeStart, .resizeEnd] {
            let range = CadenceTimelineBlockEdit.editedRange(
                kind: kind, start: 600, end: 660,
                translationY: points(forMinutes: 3), hourHeight: hourHeight
            )
            #expect(range.start == 600 && range.end == 660, "kind \(kind) moved on a sub-step press")
        }
    }

    @Test func aMoveStopsAtTheEdgesOfTheDrawnDay() {
        let dayStart = 0
        let dayEnd = 24 * 60
        let late = CadenceTimelineBlockEdit.editedRange(
            kind: .move, start: 22 * 60, end: 23 * 60,
            translationY: points(forMinutes: 6 * 60), hourHeight: hourHeight,
            dayStartMinute: dayStart, dayEndMinute: dayEnd
        )
        #expect(late.end == dayEnd)
        #expect(late.end - late.start == 60)

        let early = CadenceTimelineBlockEdit.editedRange(
            kind: .move, start: 60, end: 90,
            translationY: points(forMinutes: -6 * 60), hourHeight: hourHeight,
            dayStartMinute: dayStart, dayEndMinute: dayEnd
        )
        #expect(early.start == dayStart)
        #expect(early.end - early.start == 30)
    }

    @Test func eachEdgeMovesItselfAndPinsTheOther() {
        let start = 600
        let end = 660
        let laterEnd = CadenceTimelineBlockEdit.editedRange(
            kind: .resizeEnd, start: start, end: end,
            translationY: points(forMinutes: 45), hourHeight: hourHeight
        )
        #expect(laterEnd.start == start)
        #expect(laterEnd.end - end == 45)

        let earlierStart = CadenceTimelineBlockEdit.editedRange(
            kind: .resizeStart, start: start, end: end,
            translationY: points(forMinutes: -30), hourHeight: hourHeight
        )
        #expect(earlierStart.end == end)
        #expect(start - earlierStart.start == 30)
    }

    @Test func noEdgeCanPullTheBlockBelowItsMinimumDuration() {
        let minimum = CadenceTimelineBlockEdit.minimumDurationMinutes
        let squeezedFromBelow = CadenceTimelineBlockEdit.editedRange(
            kind: .resizeEnd, start: 600, end: 660,
            translationY: points(forMinutes: -5 * 60), hourHeight: hourHeight
        )
        #expect(squeezedFromBelow.start == 600)
        #expect(squeezedFromBelow.end - squeezedFromBelow.start == minimum)

        let squeezedFromAbove = CadenceTimelineBlockEdit.editedRange(
            kind: .resizeStart, start: 600, end: 660,
            translationY: points(forMinutes: 5 * 60), hourHeight: hourHeight
        )
        #expect(squeezedFromAbove.end == 660)
        #expect(squeezedFromAbove.end - squeezedFromAbove.start == minimum)
    }

    // MARK: - Handle geometry

    @Test func theHandleBandIsAFullTouchTargetThatNeverSwallowsTheMoveCore() {
        #expect(CadenceTimelineBlockEdit.handleTouchTarget >= 44)
        let band = CadenceTimelineBlockEdit.handleTouchTarget
        let core = CadenceTimelineBlockEdit.minimumMoveCoreHeight
        // From a sliver to a tall block: the two inside reaches together never leave less than the
        // core to press, and a reach is never more than half the band.
        for height in stride(from: CGFloat(0), through: 400, by: 7) {
            let reach = CadenceTimelineBlockEdit.handleInsideReach(blockHeight: height)
            #expect(reach >= 0)
            #expect(reach <= band / 2)
            if height >= core {
                #expect(height - 2 * reach >= core - 0.0001, "height \(height) kept less than the core")
            }
        }
    }

    // MARK: - The commit

    private final class CountingCommit {
        var refuses = false
        private(set) var commitCount = 0
        struct Refused: Error {}

        func commit(_ modelContext: ModelContext) throws {
            commitCount += 1
            if refuses { throw Refused() }
            try modelContext.save()
        }
    }

    private func scheduledTask(in modelContext: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Moved on the timeline")
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = 600
        task.estimatedMinutes = 60
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    @Test func aLandedMoveWritesTheStartOnceAndLeavesTheEstimate() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try scheduledTask(in: modelContext)
        let seam = CountingCommit()

        let landed = CadenceTimelineBlockEdit.commit(
            task, kind: .move, range: (start: 690, end: 735),
            in: modelContext, reconciler: .inert, commit: seam.commit
        )

        #expect(landed)
        #expect(seam.commitCount == 1)
        #expect(task.scheduledStartMin == 690)
        #expect(task.estimatedMinutes == 60, "a move invented or changed a duration")
        #expect(task.scheduledDate == "2026-06-01")
        #expect(task.bundle == nil)
    }

    @Test func aLandedResizeWritesBothEnds() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try scheduledTask(in: modelContext)
        let seam = CountingCommit()

        let landed = CadenceTimelineBlockEdit.commit(
            task, kind: .resizeStart, range: (start: 570, end: 660),
            in: modelContext, reconciler: .inert, commit: seam.commit
        )

        #expect(landed)
        #expect(seam.commitCount == 1)
        #expect(task.scheduledStartMin == 570)
        #expect(task.scheduledStartMin + task.estimatedMinutes == 660)
    }

    @Test func aRefusedEditAnswersFalseAndPutsTheBlockBackWhereItStarted() throws {
        for kind in [CadenceTimelineBlockEdit.Kind.move, .resizeStart, .resizeEnd] {
            let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
            let task = try scheduledTask(in: modelContext)
            let seam = CountingCommit()
            seam.refuses = true

            let landed = CadenceTimelineBlockEdit.commit(
                task, kind: kind, range: (start: 720, end: 750),
                in: modelContext, reconciler: .inert, commit: seam.commit
            )

            #expect(!landed, "kind \(kind) reported a refused save as landed")
            #expect(seam.commitCount == 1)
            #expect(task.scheduledStartMin == 600, "kind \(kind) left the refused start in place")
            #expect(task.estimatedMinutes == 60, "kind \(kind) left the refused duration in place")
        }
    }

    // MARK: - A move onto another day ([[T-8301]])

    /// Column width for the arithmetic; any positive value gives the same relations.
    private let columnWidth: CGFloat = 120

    @Test func theFingerIsOverTheColumnItIsInFromEdgeToEdge() {
        let wide = -5...5
        // Grabbed a third of the way across its own column: it stays there until the finger
        // crosses the trailing edge, then it is the next day for the whole of that column.
        let grab = columnWidth / 3
        let toTrailingEdge = columnWidth - grab
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: 0, columnWidth: columnWidth, allowed: wide) == 0)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: toTrailingEdge - 1, columnWidth: columnWidth, allowed: wide) == 0)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: toTrailingEdge + 1, columnWidth: columnWidth, allowed: wide) == 1)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: toTrailingEdge + columnWidth - 1, columnWidth: columnWidth, allowed: wide) == 1)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: toTrailingEdge + columnWidth + 1, columnWidth: columnWidth, allowed: wide) == 2)
        // Leftward: one point past the leading edge is the day before, not "half a column away".
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: -grab + 1, columnWidth: columnWidth, allowed: wide) == 0)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: -grab - 1, columnWidth: columnWidth, allowed: wide) == -1)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: -grab - columnWidth - 1, columnWidth: columnWidth, allowed: wide) == -2)
    }

    @Test func aMoveLandsOnlyOnADayInViewAndASingleDayPaneNeverLeavesItsDay() {
        let grab = columnWidth / 2
        let farRight = columnWidth * 10
        // Clamped to the run in view, both ways.
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: farRight, columnWidth: columnWidth, allowed: -1...2) == 2)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: -farRight, columnWidth: columnWidth, allowed: -1...2) == -1)
        // The single-day pane's range.
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: farRight, columnWidth: columnWidth, allowed: 0...0) == 0)
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: -farRight, columnWidth: columnWidth, allowed: 0...0) == 0)
        // No width, no crossing.
        #expect(CadenceTimelineBlockEdit.dayDelta(grabX: grab, translationX: farRight, columnWidth: 0, allowed: -5...5) == 0)
    }

    @Test func theDaysInViewAreTheLeadingColumnThroughTheLastOneOnScreen() {
        let count = 7
        let leading = 20
        for column in leading..<(leading + count) {
            let range = CadenceTimelineBlockEdit.visibleDayDeltaRange(columnIndex: column, leadingIndex: leading, visibleDayCount: count)
            #expect(column + range.lowerBound == leading, "column \(column)")
            #expect(column + range.upperBound == leading + count - 1, "column \(column)")
            #expect(range.upperBound - range.lowerBound == count - 1, "column \(column)")
        }
        // A column only half on screen can still move within its own day.
        let offLeading = CadenceTimelineBlockEdit.visibleDayDeltaRange(columnIndex: leading - 1, leadingIndex: leading, visibleDayCount: count)
        let offTrailing = CadenceTimelineBlockEdit.visibleDayDeltaRange(columnIndex: leading + count, leadingIndex: leading, visibleDayCount: count)
        #expect(offLeading.contains(0) && offTrailing.contains(0))
    }

    @Test func aMoveThatStaysOnItsColumnNamesNoDayAndOneThatLeavesNamesTheDayItReached() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let monthEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        #expect(CadenceTimelineBlockEdit.movedDateKey(from: monthEnd, dayDelta: 0, calendar: calendar) == nil)
        #expect(CadenceTimelineBlockEdit.movedDateKey(from: monthEnd, dayDelta: 1, calendar: calendar) == "2026-07-01")
        #expect(CadenceTimelineBlockEdit.movedDateKey(from: monthEnd, dayDelta: -1, calendar: calendar) == "2026-06-29")
    }

    @Test func aMoveOntoAnotherDayWritesTheDayAndTheMinuteInOneCommit() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try scheduledTask(in: modelContext)
        let seam = CountingCommit()

        let landed = CadenceTimelineBlockEdit.commit(
            task, kind: .move, range: (start: 690, end: 750), onDay: "2026-06-02",
            in: modelContext, reconciler: .inert, commit: seam.commit
        )

        #expect(landed)
        #expect(seam.commitCount == 1, "the day and the minute were written by separate saves")
        #expect(task.scheduledDate == "2026-06-02")
        #expect(task.scheduledStartMin == 690)
        #expect(task.estimatedMinutes == 60, "a cross-day move changed the duration")
    }

    @Test func aResizeNeverChangesTheDayEvenIfOneIsNamed() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try scheduledTask(in: modelContext)

        let landed = CadenceTimelineBlockEdit.commit(
            task, kind: .resizeEnd, range: (start: 600, end: 690), onDay: "2026-06-02",
            in: modelContext, reconciler: .inert, commit: CountingCommit().commit
        )

        #expect(landed)
        #expect(task.scheduledDate == "2026-06-01")
        #expect(task.scheduledStartMin + task.estimatedMinutes == 690)
    }

    @Test func aRefusedCrossDayMovePutsTheBlockBackOnItsOwnDayAndMinute() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try scheduledTask(in: modelContext)
        let seam = CountingCommit()
        seam.refuses = true

        let landed = CadenceTimelineBlockEdit.commit(
            task, kind: .move, range: (start: 690, end: 750), onDay: "2026-06-02",
            in: modelContext, reconciler: .inert, commit: seam.commit
        )

        #expect(!landed)
        #expect(task.scheduledDate == "2026-06-01", "a refused move left the block on the new day")
        #expect(task.scheduledStartMin == 600)
    }

    /// The iOS grid's wiring of the cross-day move, read from source ([[T-8301]]): the scrolling
    /// grid hands each column the days in view, the single-day pane hands it none, the block
    /// reports its whole travel for a move, and the one commit names the day.
    @Test func theScrollingGridCarriesABlockAcrossTheDaysInViewAndTheSingleDayPaneDoesNot() throws {
        let source = try CadenceSourceScan.sourceFile(timelineFile)
        let grid = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarTimelineGrid: View", in: source))
        let block = try #require(CadenceSourceScan.declarationBody("struct iOSTimelineTaskBlock: View", in: source))
        let column = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: source))
        #expect(column.count > 1_000, "non-vacuity: the day column read as \(column.count) characters")

        // The one column builder hands every column its range, and the range is the visible
        // window on a scrolling grid and `0...0` on the single-day pane.
        let ranges = try #require(CadenceSourceScan.declarationBody("private func dayDeltaRange(for date: Date)", in: grid))
        #expect(CadenceSourceScan.matchCount(#"dayDeltaRange: dayDeltaRange\(for: date\)"#, in: grid) == 1)
        #expect(CadenceSourceScan.matchCount(#"guard !isSingleDay else \{ return 0\.\.\.0 \}"#, in: ranges) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.visibleDayDeltaRange\("#, in: ranges) == 1)
        #expect(CadenceSourceScan.matchCount(#"visibleDayCount: visibleDayCount"#, in: ranges) == 1)
        // The commit names the day the move reached.
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.commit\(task, kind: kind, range: range, onDay: dateKey,"#, in: grid) == 1)
        #expect(CadenceSourceScan.matchCount(#"onDay: CadenceTimelineBlockEdit\.movedDateKey\(from: date, dayDelta: dayDelta"#, in: grid) == 1)
        // The move reports the whole travel, not its height alone.
        #expect(CadenceSourceScan.matchCount(#"editing\?\.onChanged\(\.move, translation\)"#, in: block) == 1)
        #expect(CadenceSourceScan.matchCount(#"editing\?\.onEnded\(\.move, translation\)"#, in: block) == 1)
        #expect(CadenceSourceScan.matchCount(#"editing\?\.onMovePressed\(point\)"#, in: block) == 1)
        // The column resolves the day through the shared rule and draws the carried block there.
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.dayDelta\("#, in: column) == 1)
        #expect(CadenceSourceScan.matchCount(#"allowed: dayDeltaRange"#, in: column) == 1)
        #expect(CadenceSourceScan.matchCount(#"slot\.x \+ CGFloat\(carriedDays\(for: task\)\) \* colWidth"#, in: column) == 1)
        // A move that only changed day still commits.
        #expect(CadenceSourceScan.matchCount(#"\|\| edit\.dayDelta != 0 else \{ return \}"#, in: column) == 1)
    }

    // MARK: - The iOS surface's wiring, read from source

    private let timelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"

    @Test func theIOSBlockLiftsOnAHoldAndCarriesNoDragPayloadOrDropTarget() throws {
        let source = try CadenceSourceScan.sourceFile(timelineFile)
        let block = try #require(CadenceSourceScan.declarationBody("struct iOSTimelineTaskBlock: View", in: source))
        #expect(block.count > 1_000, "non-vacuity: iOSTimelineTaskBlock read as \(block.count) characters")

        // The hold comes first: a finger that moves before it is a scroll. **Through the UIKit
        // recognizer, which is the half that makes that sentence true** ([[T-7550]]) — a SwiftUI
        // `LongPressGesture.sequenced(before: DragGesture)` claims the touch from the enclosing
        // `ScrollView` whether or not the hold ever completes, and a swipe begun on a block
        // scrolled the day zero points for as long as this block spelled it that way.
        #expect(CadenceSourceScan.matchCount(#"iOSTimelinePressDrag\(\s*(//[^\n]*\n\s*)*isEnabled: editing != nil,\s*minimumPressDuration: CadenceTimelineBlockEdit\.liftPressDuration,"#, in: block) == 1)
        // The negative is about the LONG PRESS. `resizeHandle`'s own hold is asked in
        // `CadenceTimelinePressDragRecognizerTests` ([[T-7601]]).
        #expect(
            CadenceSourceScan.matchCount(#"LongPressGesture|\.sequenced\(before:"#, in: CadenceSourceScan.strippingComments(block)) == 0,
            "the block's move press is a SwiftUI long-press-then-drag again, which cannot give the touch back"
        )
        // Both edges, each fitted to the 44pt band.
        #expect(CadenceSourceScan.matchCount(#"resizeHandle\(\.resize(Start|End)\)"#, in: block) == 2)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.handleTouchTarget"#, in: block) == 1)
        // A tap still opens the inspector, from one place.
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture \{ handleTap\(\) \}"#, in: block) == 1)
        #expect(CadenceSourceScan.matchCount(#"taskInspector\(task\)"#, in: block) == 1)
        // Not T-3170's gesture: nothing to lift onto another block, nothing to drop on this one.
        #expect(CadenceSourceScan.matchCount(#"\.draggable\(|\.dropDestination\(|\.onDrag\b|NSItemProvider|TaskDragPayload|insertBundle"#, in: block) == 0)
    }

    @Test func theGridCommitsOnceThroughTheSharedEditAndNamesARefusal() throws {
        let source = try CadenceSourceScan.sourceFile(timelineFile)
        let grid = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarTimelineGrid: View", in: source))

        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.commit\("#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineBlockEdit\.commit\("#, in: grid) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"blockEditFailureNotice = landed \? nil : CadencePendingChangePersistence\.editFailureNotice"#,
            in: grid
        ) == 1)
        // Drawn, not merely set.
        #expect(CadenceSourceScan.matchCount(#"CadenceInlineFailureNotice\(text: blockEditFailureNotice\)"#, in: grid) == 1)
        // The block's raw fields are never written on the view side; only the shared commit does.
        #expect(CadenceSourceScan.matchCount(#"\.scheduledStartMin\s*=[^=]|\.estimatedMinutes\s*=[^=]"#, in: source) == 0)
    }
}
#endif
