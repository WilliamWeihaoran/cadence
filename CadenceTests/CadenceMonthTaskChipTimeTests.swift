import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-8044]], owner call: a timed task's Month chip shows its start in the event chip's time
/// slot and spelling, and timed tasks sort by start before untimed ones -- on both platforms,
/// through one shared helper ([[T-8201]]).
@Suite struct CadenceMonthTaskChipTimeTests {
    private static let dayKey = "2026-08-12"

    @Test func aTaskChipIsTimedOnlyOnTheDayItIsScheduledAtARealMinute() {
        // Scheduled on this day at 3 PM: the event chip's own clock, both faces.
        #expect(CalendarEventChipTimeSupport.taskLabel(
            scheduledDate: Self.dayKey, scheduledStartMin: 15 * 60, dayKey: Self.dayKey
        ) == TimeFormatters.timeString(from: 15 * 60))
        #expect(CalendarEventChipTimeSupport.taskLabel(
            scheduledDate: Self.dayKey, scheduledStartMin: 15 * 60, dayKey: Self.dayKey, compact: true
        ) == TimeFormatters.compactTimeString(from: 15 * 60))
        // Midnight is a real minute, not "untimed".
        #expect(CalendarEventChipTimeSupport.taskStartMinute(
            scheduledDate: Self.dayKey, scheduledStartMin: 0, dayKey: Self.dayKey
        ) == 0)

        // Untimed (`-1`), filed under a due date with no do date, or drawn on another day: no time.
        #expect(CalendarEventChipTimeSupport.taskLabel(
            scheduledDate: Self.dayKey, scheduledStartMin: -1, dayKey: Self.dayKey
        ) == nil)
        #expect(CalendarEventChipTimeSupport.taskLabel(
            scheduledDate: "", scheduledStartMin: 9 * 60, dayKey: Self.dayKey
        ) == nil)
        #expect(CalendarEventChipTimeSupport.taskLabel(
            scheduledDate: "2026-08-13", scheduledStartMin: 9 * 60, dayKey: Self.dayKey
        ) == nil)
    }

    /// The ticket's own scenario, plus the two rules that keep priority doing its job: untimed
    /// tasks keep priority order behind the timed ones, and an equal start keeps priority order.
    @Test func aMonthCellListsTimedTasksByStartBeforeUntimedOnesInPriorityOrder() throws {
        let context = ModelContext(try CadenceTestStore.container())
        func add(_ title: String, start: Int, priority: TaskPriority, order: Int, scheduled: Bool = true) -> AppTask {
            let task = AppTask(title: title)
            if scheduled {
                task.scheduledDate = Self.dayKey
            } else {
                task.dueDate = Self.dayKey
            }
            task.scheduledStartMin = start
            task.priority = priority
            task.order = order
            context.insert(task)
            return task
        }
        let tasks = [
            add("Call bank", start: 15 * 60, priority: .medium, order: 0),
            add("Urgent untimed", start: -1, priority: .high, order: 1),
            add("Gym", start: 7 * 60, priority: .medium, order: 2),
            add("Low untimed", start: -1, priority: .low, order: 3),
            // Due-filed: carries a minute but is not scheduled on this day, so it is untimed here.
            add("Due only", start: 8 * 60, priority: .none, order: 4, scheduled: false),
            add("Gym twin, low", start: 7 * 60, priority: .low, order: 5),
        ]

        let cell = CadenceScheduleSupport.monthTasksByDate(tasks)[Self.dayKey]?.map(\.title)
        #expect(cell == ["Gym", "Gym twin, low", "Call bank", "Urgent untimed", "Low untimed", "Due only"])
        // The Mac page reads the same order. `CalendarPageDataSupport` is Mac-only and this suite
        // also compiles into the iOS test target ([[T-10863]]).
        #if os(macOS)
        #expect(CalendarPageDataSupport.monthTasksByDate(tasks)[Self.dayKey]?.map(\.title) == cell)
        #endif
    }

    /// Both chips read the one helper, and iOS counts a timed task's second line toward the cell's
    /// capacity the way it already counts a timed event's.
    @Test func bothPlatformsDrawTheTaskTimeThroughTheSharedHelper() throws {
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        )
        let chip = try #require(CadenceSourceScan.declarationBody("struct MonthTaskChip: View", in: mac))
        #expect(chip.contains("CalendarEventChipTimeSupport.taskLabel("))

        let ios = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthViews.swift")
        )
        #expect(ios.contains("CalendarEventChipTimeSupport.taskLabel("))
        #expect(ios.contains("timeLabel: taskTimeLabel(for: task)"))
        #expect(ios.contains("iOSCalendarMiniChip.height(hasTime: taskTimeLabel(for: $0) != nil, at: dynamicTypeSize, scaling: scaling)"))
        #expect(!ios.contains("tasks.prefix(Self.maximumChipCount).map { _ in iOSCalendarMiniChip.height(hasTime: false"))
    }
}

#if os(macOS)
/// [[T-8001]] / [[T-10440]], owner call "band follows the blocks": the Mac Today all-day band's
/// chips span exactly what a lone timeline block spans, at every pane width.
@Suite struct MacTodayAllDayBandAlignmentTests {
    @Test(arguments: [240.0, 343.0, 520.0, 900.0])
    func theBandChipSpansALoneBlock(ladderWidth: Double) {
        let pane = CGFloat(ladderWidth)
        let span = SchedulePanelTimelineColumn.chipSpan(ladderWidth: pane)
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        let block = TimelineMetricsSupport.computeBlockFrame(
            startMinute: 9 * 60,
            durationMinutes: 60,
            column: 0,
            totalColumns: 1,
            totalWidth: SchedulePanelTimelineColumn.canvasWidth(ladderWidth: pane),
            metrics: metrics,
            style: .schedule
        )
        // The canvas sits right of the hour rail, so a block's pane x is `blockInset` further in.
        #expect(abs(span.leading - (blockInset + block.x)) < 0.0001)
        #expect(abs(span.width - block.width) < 0.0001)
    }

    /// The non-parameterised sibling: the measured 343pt pane from [[T-8001]]'s sighting, as a
    /// relation -- the chip no longer starts left of a block or runs past one.
    @Test func theMeasuredPaneNoLongerOverhangs() {
        let pane: CGFloat = 343
        let span = SchedulePanelTimelineColumn.chipSpan(ladderWidth: pane)
        // The old band started at the rail's edge and ran to 16pt short of the pane.
        #expect(span.leading > blockInset)
        #expect(span.leading + span.width < pane - 16)
    }

    @Test func theBandAndTheViewportReadTheOneGeometry() throws {
        let code = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelShellViews.swift")
        )
        let band = try #require(CadenceSourceScan.declarationBody("struct SchedulePanelAllDayBand: View", in: code))
        #expect(band.contains("SchedulePanelTimelineColumn.chipSpan(ladderWidth:"))
        #expect(!band.contains(".padding(.trailing, 16)"))
        let viewport = try #require(CadenceSourceScan.declarationBody("struct SchedulePanelTimelineViewport: View", in: code))
        #expect(viewport.contains("SchedulePanelTimelineColumn.canvasWidth(ladderWidth: geoSize.width)"))
    }
}
#endif
