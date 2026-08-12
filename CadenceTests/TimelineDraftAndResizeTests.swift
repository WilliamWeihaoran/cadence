import Foundation
import Testing
#if os(macOS)
import SwiftUI
#endif
@testable import Cadence

#if os(macOS)
/// Coordinate math for the two timeline interactions that own their own rect: the drag-to-create
/// draft (ghost + popover anchor) and the edge-resize handles. Both used to derive geometry inline
/// in view bodies, where nothing could assert it.
@Suite(.serialized)
@MainActor
struct TimelineDraftAndResizeTests {

    private let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)

    // MARK: - Draft rect (ghost and popover anchor)

    @Test func draftFrameIsTheSameRectAsTheBlockThatWillBeCreatedFromIt() {
        // The ghost the user drags out and the popover anchored to it both read this rect; a
        // block created from the same range must land exactly on top of it.
        let draft = TimelineMetricsSupport.computeDraftFrame(
            startMinute: 600,
            endMinute: 690,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        let created = computeTimelineBlockFrame(
            startMinute: 600,
            durationMinutes: 90,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )

        #expect(draft.x == created.x)
        #expect(draft.y == created.y)
        #expect(draft.width == created.width)
        #expect(draft.height == created.height)
    }

    @Test func draftFrameWidthHonoursTheDragToCreateStripReservedByBlockWidthFraction() {
        let style = TimelineBlockStyle.schedule
        let totalWidth: CGFloat = 300
        let frame = TimelineMetricsSupport.computeDraftFrame(
            startMinute: 540,
            endMinute: 600,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )

        let insetWidth = totalWidth - style.leadingInset - style.trailingInset
        // The old draft rect was exactly `totalWidth - insets`, ignoring `blockWidthFraction`,
        // so it drew wider than any block it could create.
        #expect(frame.width < insetWidth)
        #expect(abs(frame.width - (insetWidth * style.blockWidthFraction - style.columnSpacing)) < 0.0001)
        #expect(frame.x == style.leadingInset)
    }

    @Test func draftFrameNeverCollapsesBelowTheFiveMinuteFloor() {
        // A degenerate (zero-length) drag must still produce the 5-minute block the commit step
        // clamps to, not the 60-minute one `computeBlockFrame`'s zero-duration fallback would give.
        let frame = TimelineMetricsSupport.computeDraftFrame(
            startMinute: 600,
            endMinute: 600,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        #expect(frame.height == metrics.height(for: 5, minHeight: TimelineBlockStyle.schedule.minHeight))
    }

    // MARK: - Draft selection state

    @Test func draftSelectionNormalisesAnUpwardDragIntoAnOrderedRange() {
        var draft: TimelineDraftSelection? = nil
        var showPopover = false
        var selectedTaskID: UUID? = UUID()

        // Gesture anchor (mouse-down) is at minute 600; the live pointer has moved upward to 540.
        TimelineDayCanvasStateSupport.beginDraftSelection(
            startMin: 600,
            endMin: 540,
            draft: &draft,
            showNewTaskPopover: &showPopover,
            selectedTaskID: &selectedTaskID
        )

        #expect(draft == .live(start: 540, end: 600))
        #expect(selectedTaskID == nil)
        #expect(showPopover == false)
    }

    @Test func committingADraftKeepsTheSameRangeTheGhostWasShowing() {
        var draft: TimelineDraftSelection? = nil
        var showPopover = false
        var selectedTaskID: UUID? = nil

        TimelineDayCanvasStateSupport.beginDraftSelection(
            startMin: 600,
            endMin: 660,
            draft: &draft,
            showNewTaskPopover: &showPopover,
            selectedTaskID: &selectedTaskID
        )
        let shownWhileDragging = draft?.range
        TimelineDayCanvasStateSupport.commitDraftSelection(
            startMin: 600,
            endMin: 660,
            draft: &draft,
            showNewTaskPopover: &showPopover
        )

        // The popover displays this range *and* creates it — they are now one value, so they
        // cannot disagree the way a separate `pendingStartMin`/`pendingEndMin` pair could.
        #expect(draft == .pending(start: 600, end: 660))
        #expect(draft?.range.start == shownWhileDragging?.start)
        #expect(draft?.range.end == shownWhileDragging?.end)
        #expect(showPopover)
    }

    @Test func committingADegenerateDragStillProducesAFiveMinuteRange() {
        var draft: TimelineDraftSelection? = nil
        var showPopover = false

        TimelineDayCanvasStateSupport.commitDraftSelection(
            startMin: 300,
            endMin: 300,
            draft: &draft,
            showNewTaskPopover: &showPopover
        )

        #expect(draft == .pending(start: 300, end: 305))
    }

    @Test func startingANewDragReplacesACommittedDraftWholeRatherThanFieldByField() {
        var draft: TimelineDraftSelection? = nil
        var showPopover = false
        var selectedTaskID: UUID? = nil

        TimelineDayCanvasStateSupport.commitDraftSelection(
            startMin: 600,
            endMin: 660,
            draft: &draft,
            showNewTaskPopover: &showPopover
        )
        TimelineDayCanvasStateSupport.beginDraftSelection(
            startMin: 900,
            endMin: 930,
            draft: &draft,
            showNewTaskPopover: &showPopover,
            selectedTaskID: &selectedTaskID
        )

        // Four independent optionals allowed a hybrid here: a live drag's start with a committed
        // draft's end. One value makes that unrepresentable.
        #expect(draft == .live(start: 900, end: 930))
        #expect(showPopover == false)
    }

    @Test func clearingTheDraftRemovesBothTheGhostAndThePopover() {
        var draft: TimelineDraftSelection? = .pending(start: 600, end: 660)
        var showPopover = true
        var selectedEventID: String? = "event"

        TimelineDayCanvasStateSupport.clearDraftCreation(
            draft: &draft,
            showNewTaskPopover: &showPopover,
            selectedEventID: &selectedEventID
        )

        #expect(draft == nil)
        #expect(showPopover == false)
        #expect(selectedEventID == nil)
    }

    // MARK: - Bundle-drop shelf geometry

    @Test func theBundleShelfRectIsTheRegionTheShelfActuallyDraws() {
        // The canvas drop delegate defers to the shelf on exactly this rect. Both read it from
        // here, so "where the shelf is drawn" and "where the canvas stands aside" are one answer
        // rather than a 750 ms window arbitrating two async callbacks.
        let block = computeTimelineBlockFrame(
            startMinute: 540,
            durationMinutes: 120,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        let shelf = TimelineMetricsSupport.bundleDropShelfFrame(blockFrame: block)

        #expect(shelf.x == block.x)
        #expect(shelf.y == block.y)
        #expect(shelf.width == block.width)
        #expect(shelf.height == TimelineMetricsSupport.bundleDropShelfHeight(blockHeight: block.height)
                + TimelineMetricsSupport.bundleDropShelfPadding * 2)
        // It is a shelf, not the whole block: a drop lower down is still a move-to-minute.
        #expect(shelf.height < block.height)
    }

    @Test func aDropOnTheShelfIsInsideItAndADropBelowTheShelfIsNot() {
        let block = computeTimelineBlockFrame(
            startMinute: 540,
            durationMinutes: 120,
            column: 0,
            totalColumns: 1,
            totalWidth: 300,
            metrics: metrics,
            style: .schedule
        )
        let shelf = TimelineMetricsSupport.bundleDropShelfFrame(blockFrame: block)

        let onShelf = CGPoint(x: block.x + block.width / 2, y: shelf.y + shelf.height / 2)
        let belowShelf = CGPoint(x: block.x + block.width / 2, y: shelf.y + shelf.height + 20)
        let besideBlock = CGPoint(x: block.x + block.width + 20, y: shelf.y + 2)

        #expect(TimelineMetricsSupport.isInsideBlockedBlock(point: onShelf, blockedFrames: [shelf]))
        #expect(!TimelineMetricsSupport.isInsideBlockedBlock(point: belowShelf, blockedFrames: [shelf]))
        #expect(!TimelineMetricsSupport.isInsideBlockedBlock(point: besideBlock, blockedFrames: [shelf]))
    }

    // MARK: - Clamping

    @Test func theVisibleClampAndTheDayClampAgreeOnAFullDayCanvas() {
        // Four spellings of this clamp existed, with three different bounds — one of them the
        // bare literal 1425, which is 1440 - 15 where everything else used 1440 - 5.
        #expect(metrics.clampStart(2_000) == TimelineDayRange.endMin - TimelineDayRange.minimumDuration)
        #expect(metrics.clampStart(-50) == TimelineDayRange.startMin)
        #expect(TimelineDayRange.clampStart(2_000) == 1_435)
        #expect(TimelineDayRange.clampStart(-50) == 0)
        #expect(TimelineDayRange.clampStart(600) == 600)
    }

    @Test func aCanvasThatStartsAtEightAmNeverResolvesToAMinuteItCannotDraw() {
        let workday = TimelineMetrics(startHour: 8, endHour: 18, hourHeight: 60)
        #expect(workday.clampStart(0) == 8 * 60)
        #expect(workday.clampStart(2_000) == 18 * 60 - 5)
        #expect(workday.yToMins(-500) == 8 * 60)
        #expect(workday.yToMins(10_000) == 18 * 60 - 5)
    }

    @Test func aLongerBlockIsClampedFurtherBackSoItStillEndsInsideTheDay() {
        #expect(TimelineDayRange.clampStart(1_430, duration: 60) == TimelineDayRange.endMin - 60)
        #expect(metrics.clampStart(1_430, duration: 60) == 24 * 60 - 60)
    }

    // MARK: - Zoom

    @Test func everyZoomLevelTheControlOffersHasItsOwnHourHeight() {
        // The render path and the remembered-scroll path used to carry this table separately, and
        // widening the control's range past the table would have collapsed the new level into the
        // last one in silence. The control's range comes from the same place now.
        let heights = TimelineZoom.levels.map { TimelineZoom.hourHeight(viewportHeight: 600, level: $0) }
        #expect(Set(heights).count == TimelineZoom.levels.count)
        #expect(TimelineZoom.targetHours(1) == 12)
        #expect(TimelineZoom.targetHours(2) == 8)
        #expect(TimelineZoom.targetHours(3) == 4)
        #expect(TimelineZoom.hourHeight(viewportHeight: 600, level: 1) == 50)
    }

    // MARK: - Edge resize

    @Test func grabbingTheEndHandleWithoutMovingLeavesTheBlockLengthAlone() {
        // A 90-minute block at hourHeight 60 is taller than `minHeight`, so the drawn bottom edge
        // and the true end minute coincide.
        let session = TimelineResizeSession.begin(
            edge: .end,
            localY: 4,
            blockTopY: metrics.yOffset(for: 540),
            blockDrawnHeight: metrics.height(for: 90, minHeight: TimelineBlockStyle.schedule.minHeight),
            originStartMin: 540,
            originEndMin: 630,
            metrics: metrics
        )
        let range = metrics.resizedRange(
            session: session,
            localY: 4,
            blockTopY: metrics.yOffset(for: 540),
            blockDrawnHeight: metrics.height(for: 90, minHeight: TimelineBlockStyle.schedule.minHeight)
        )

        #expect(range.start == 540)
        #expect(range.end == 630)
    }

    @Test func grabbingTheEndHandleOfAClampedShortBlockDoesNotJumpItsLength() {
        // The regression this exists for: `height(for:minHeight:)` floors a short block at
        // `style.minHeight`, so its drawn bottom edge — and therefore its resize handle — sits
        // *below* the minute the block actually ends at. Reading the handle's position as the new
        // end minute made grabbing a 10-minute block instantly stretch it to ~20 minutes.
        let style = TimelineBlockStyle.schedule
        let shortMetrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 50)
        let topY = shortMetrics.yOffset(for: 540)
        let drawnHeight = shortMetrics.height(for: 10, minHeight: style.minHeight)
        #expect(drawnHeight == style.minHeight)   // the clamp is engaged

        let session = TimelineResizeSession.begin(
            edge: .end,
            localY: 4,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight,
            originStartMin: 540,
            originEndMin: 550,
            metrics: shortMetrics
        )
        let range = shortMetrics.resizedRange(
            session: session,
            localY: 4,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight
        )

        #expect(range.start == 540)
        #expect(range.end == 550)
    }

    @Test func draggingTheEndHandleDownExtendsTheBlockByThePointerDistance() {
        let style = TimelineBlockStyle.schedule
        let topY = metrics.yOffset(for: 540)
        let drawnHeight = metrics.height(for: 60, minHeight: style.minHeight)
        let session = TimelineResizeSession.begin(
            edge: .end,
            localY: 4,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight,
            originStartMin: 540,
            originEndMin: 600,
            metrics: metrics
        )

        // The pointer moves 30 pt further down — half an hour at hourHeight 60.
        let range = metrics.resizedRange(
            session: session,
            localY: 34,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight
        )

        #expect(range.start == 540)
        #expect(range.end == 630)
    }

    @Test func draggingTheStartHandleUpMovesTheStartAndKeepsTheEndPinned() {
        let style = TimelineBlockStyle.schedule
        let topY = metrics.yOffset(for: 540)
        let drawnHeight = metrics.height(for: 60, minHeight: style.minHeight)
        let session = TimelineResizeSession.begin(
            edge: .start,
            localY: 4,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight,
            originStartMin: 540,
            originEndMin: 600,
            metrics: metrics
        )

        // 20 pt above the grab point at hourHeight 60 is 20 minutes earlier.
        let range = metrics.resizedRange(
            session: session,
            localY: -16,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight
        )

        #expect(range.start == 520)
        #expect(range.end == 600)
    }

    @Test func neitherEdgeCanBeDraggedPastTheOtherIntoAZeroOrNegativeLength() {
        let style = TimelineBlockStyle.schedule
        let topY = metrics.yOffset(for: 540)
        let drawnHeight = metrics.height(for: 60, minHeight: style.minHeight)

        let endSession = TimelineResizeSession.begin(
            edge: .end,
            localY: 4,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight,
            originStartMin: 540,
            originEndMin: 600,
            metrics: metrics
        )
        // Dragged far above the block's own start.
        let collapsedEnd = metrics.resizedRange(
            session: endSession,
            localY: -500,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight
        )
        #expect(collapsedEnd.start == 540)
        #expect(collapsedEnd.end == 545)

        let startSession = TimelineResizeSession.begin(
            edge: .start,
            localY: 4,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight,
            originStartMin: 540,
            originEndMin: 600,
            metrics: metrics
        )
        let collapsedStart = metrics.resizedRange(
            session: startSession,
            localY: 500,
            blockTopY: topY,
            blockDrawnHeight: drawnHeight
        )
        #expect(collapsedStart.start == 595)
        #expect(collapsedStart.end == 600)
    }
}
#endif
