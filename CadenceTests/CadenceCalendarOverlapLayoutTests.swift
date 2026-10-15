import Foundation
import Testing
#if os(macOS)
import AppKit
import EventKit
import SwiftUI
#endif
@testable import Cadence

/// T-3161. Overlapping calendar **events** lay out the way Apple Calendar lays them out: events
/// that start close together split into equal columns, and an event that starts far enough after an
/// event it overlaps cascades — indented from the leading edge, running to the trailing edge, drawn
/// on top.
///
/// The acceptance test is the owner's reference screenshot, and it is in here literally: the two
/// clusters below are the times measured off that image, not invented fixtures.
@Suite
struct CadenceCalendarOverlapLayoutTests {

    // MARK: - Fixtures

    private static func event(_ start: Int, _ end: Int) -> CadenceCalendarOverlapLayout.Slot {
        CadenceCalendarOverlapLayout.Slot(startMin: start, endMin: end, mayCascade: true)
    }

    private static func task(_ start: Int, _ end: Int) -> CadenceCalendarOverlapLayout.Slot {
        CadenceCalendarOverlapLayout.Slot(startMin: start, endMin: end, mayCascade: false)
    }

    private static func minutes(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

    /// The threshold at the screenshot's zoom: a 29pt header over a 75pt hour.
    private static let screenshotGap = CadenceCalendarOverlapLayout.cascadeGapMinutes(
        headerHeight: CadenceCalendarOverlapLayout.macCalendarEventHeaderHeight,
        hourHeight: 75
    )

    // MARK: - 1. The header the threshold is derived from

    /// The line heights the header is built out of are AppKit's, not a guess.
    ///
    /// This is the half that makes "read the real header height out of the block view" checkable:
    /// if a toolchain changes the system font's metrics, the cascade threshold moves, and it moves
    /// here first.
    @Test func theLineHeightTableMatchesWhatAppKitReports() {
        #if os(macOS)
        let layoutManager = NSLayoutManager()
        var checked = 0
        for size in stride(from: CGFloat(7), through: CGFloat(17), by: 1) {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            #expect(
                CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize: size)
                    == layoutManager.defaultLineHeight(for: font),
                "the line-height table disagrees with AppKit at \(size)pt"
            )
            checked += 1
        }
        #expect(checked == 11, "non-vacuity: the sweep checked \(checked) sizes")
        #endif
    }

    /// 29pt on the Mac, 32pt on iOS, each the sum of its own block's padding, spacing and two rows.
    @Test func theEventHeaderHeightsAreTheSumsOfTheRowsTheBlocksActuallyDraw() {
        // 3pt padding + an 11pt time row + 2pt of spacing + a 13pt title row.
        #expect(CadenceCalendarOverlapLayout.macCalendarEventHeaderHeight == CGFloat(29))
        // The Schedule panel pads one point more.
        #expect(CadenceCalendarOverlapLayout.macEventHeaderHeight(verticalPadding: 4) == CGFloat(30))
        // 5pt padding + a 13pt title row + 3pt of spacing + an 11pt time row.
        #expect(CadenceCalendarOverlapLayout.iOSEventHeaderHeight == CGFloat(32))
    }

    /// The constants above are mirrored from two view files; this is what stops them drifting.
    @Test func theMirroredRowMetricsStillMatchTheTwoEventBlockBodies() throws {
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift")
        )
        #expect(mac.count > 2_000, "non-vacuity: read \(mac.count) characters of the Mac event block")
        #expect(mac.contains("VStack(alignment: .leading, spacing: 2)"))
        #expect(mac.contains("Text(timeRangeLabel)"))
        #expect(mac.contains(".font(.system(size: 9, weight: .semibold))"))
        #expect(mac.contains("Text(item.title)"))
        #expect(mac.contains(".font(.system(size: 11, weight: .semibold))"))

        let style = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineMetrics.swift")
        )
        #expect(style.count > 2_000, "non-vacuity: read \(style.count) characters of the metrics file")
        #expect(style.contains("verticalPadding: 3"), "TimelineBlockStyle.calendar no longer pads 3pt")

        let phone = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(phone.count > 20_000, "non-vacuity: read \(phone.count) characters of the iOS grid")
        #expect(phone.contains("VStack(alignment: .leading, spacing: 3)"))
        #expect(phone.contains(".padding(.vertical, 5)"))
    }

    // MARK: - 2. The threshold

    /// Minutes of header, not a tuned constant — and it follows the zoom, because what is being
    /// protected is text whose height in points does not change when an hour does.
    @Test func theThresholdIsTheHeaderHeightDividedByPointsPerMinuteAndFollowsTheZoom() {
        // 29pt / (75/60 pt per minute) = 23.2 → 24.
        #expect(Self.screenshotGap == 24)
        // Zoom out (a shorter hour) and the same text costs more minutes.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 50) == 35)
        // Zoom in and it costs fewer.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 150) == 12)
        // Rounded up: a gap that clears the header by a fraction of a point does not clear it.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 60) == 29)
        // A canvas that has not been laid out is not a zoom level; nothing may cascade there.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 0) == Int.max)
    }

    /// The owner's stated acceptance band: the derived threshold must separate the screenshot's
    /// 15-minute gap from its 45-minute one.
    @Test func theDerivedThresholdFallsBetweenTheScreenshotsFifteenAndFortyFiveMinuteGaps() {
        #expect(Self.screenshotGap > 15)
        #expect(Self.screenshotGap <= 45)
    }

    // MARK: - 3. The owner's screenshot, by its literal times

    /// THREE events — 2:15–6:15, 3:00–5:45, 4:00–6:00 — cascade. Gaps of 45 and 60 minutes.
    @Test func theScreenshotsThreeEventClusterCascades() {
        let slots = [
            Self.event(Self.minutes(2, 15), Self.minutes(6, 15)),
            Self.event(Self.minutes(3, 0), Self.minutes(5, 45)),
            Self.event(Self.minutes(4, 0), Self.minutes(6, 0))
        ]
        let placed = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: Self.screenshotGap)

        // One column: every block runs to the trailing edge, exactly as the screenshot shows.
        #expect(placed.map(\.totalColumns) == [1, 1, 1])
        #expect(placed.map(\.column) == [0, 0, 0])
        // And each later start is laid one step deeper over the one before it.
        #expect(placed.map(\.cascadeDepth) == [0, 1, 2])
    }

    /// TWO events — 7:00–10:55 and 7:15–10:00 — split into equal halves. Gap of 15 minutes.
    @Test func theScreenshotsTwoEventClusterSplitsIntoEqualHalves() {
        let slots = [
            Self.event(Self.minutes(7, 0), Self.minutes(10, 55)),
            Self.event(Self.minutes(7, 15), Self.minutes(10, 0))
        ]
        let placed = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: Self.screenshotGap)

        #expect(placed.map(\.column) == [0, 1])
        #expect(placed.map(\.totalColumns) == [2, 2])
        #expect(placed.map(\.cascadeDepth) == [0, 0], "a 15-minute gap must not cascade")
    }

    /// The indent rule against the edges measured off that screenshot: a column about 345pt wide,
    /// left edges at roughly 0%, ~23% and ~36%.
    @Test func theCascadeIndentLandsOnTheScreenshotsMeasuredLeftEdges() {
        let column: CGFloat = 345
        let first = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 1)
        let second = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 2)

        // 20% of the column, against a rough measurement of ~23%.
        #expect(abs(first / column - 0.20) < 0.001)
        // 36% of the column — the owner's second measurement, exactly.
        #expect(abs(second / column - 0.36) < 0.001)
        // Depth 0 is the old behaviour, untouched.
        #expect(CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 0) == 0)
        // The steps shrink, which is what a rule fitted to ~79pt then ~45pt has to do.
        #expect(second - first < first)
        // And the decay never runs the block out of width.
        let deep = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 12)
        #expect(deep < column)
        #expect(column - deep >= CadenceCalendarOverlapLayout.minimumCascadedWidth)
    }

    // MARK: - 4. Degenerate cases

    @Test func identicalStartTimesNeverCascadeAndAlwaysTakeSeparateColumns() {
        let slots = [Self.event(540, 600), Self.event(540, 660), Self.event(540, 570)]
        let placed = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: 24)

        #expect(placed.map(\.column) == [0, 1, 2])
        #expect(placed.map(\.cascadeDepth) == [0, 0, 0])
        #expect(placed.map(\.totalColumns) == [3, 3, 3])
    }

    @Test func anEventWhollyContainedInAnotherCascadesWhenItStartsLateEnough() {
        // 9:00–13:00 contains 11:00–12:00; the inner one starts 120 minutes later.
        let placed = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 780), Self.event(660, 720)],
            cascadeGapMinutes: 24
        )
        #expect(placed.map(\.column) == [0, 0])
        #expect(placed.map(\.cascadeDepth) == [0, 1])
        #expect(placed.map(\.totalColumns) == [1, 1])

        // The same containment with a 10-minute gap has to split instead.
        let tight = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 780), Self.event(550, 720)],
            cascadeGapMinutes: 24
        )
        #expect(tight.map(\.column) == [0, 1])
        #expect(tight.map(\.cascadeDepth) == [0, 0])
    }

    /// A overlaps B and B overlaps C, but A does not overlap C.
    @Test func aChainWhereTheEndsDoNotOverlapDoesNotStackCDeeperThanItOverlaps() {
        // A 9:00–10:00, B 9:40–11:00, C 10:30–12:00. A∩C is empty.
        let placed = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 600), Self.event(580, 660), Self.event(630, 720)],
            cascadeGapMinutes: 24
        )
        // B clears A by 40 minutes and stacks on it; C clears B by 50 and stacks on B.
        #expect(placed.map(\.column) == [0, 0, 0])
        #expect(placed.map(\.cascadeDepth) == [0, 1, 2])
        // A sees only B, C sees only B — but the column count is per block, and all are column 0.
        #expect(placed.map(\.totalColumns) == [1, 1, 1])
    }

    @Test func zeroAndFiveMinuteDurationsAreLaidOutWithoutOverlappingAnything() {
        // A zero-length slot has no area, so under half-open overlap it collides with nothing.
        let zero = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 540), Self.event(540, 600)],
            cascadeGapMinutes: 24
        )
        #expect(zero.map(\.column) == [0, 0])
        #expect(zero.map(\.totalColumns) == [1, 1])
        #expect(zero.map(\.cascadeDepth) == [0, 0])

        // Five minutes is the real floor, and a 5-minute event inside a long one still cascades.
        let short = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 720), Self.event(600, 605)],
            cascadeGapMinutes: 24
        )
        #expect(short.map(\.column) == [0, 0])
        #expect(short.map(\.cascadeDepth) == [0, 1])

        // Back-to-back blocks do not overlap at all.
        let abutting = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 545), Self.event(545, 550)],
            cascadeGapMinutes: 1
        )
        #expect(abutting.map(\.totalColumns) == [1, 1])
        #expect(abutting.map(\.cascadeDepth) == [0, 0])
    }

    @Test func anEmptyDayAndASingleEventAreUnchanged() {
        #expect(CadenceCalendarOverlapLayout.solve(slots: [], cascadeGapMinutes: 24).isEmpty)
        #expect(
            CadenceCalendarOverlapLayout.solve(slots: [Self.event(540, 600)], cascadeGapMinutes: 24)
                == [CadenceCalendarOverlapPlacement.single]
        )
    }

    // MARK: - 5. Tasks and bundles keep equal columns

    /// The owner ruled on events. A task never cascades, and an event never cascades over a task —
    /// so a task always keeps a column of its own and stays visible.
    @Test func tasksNeitherCascadeNorAreCascadedOver() {
        // Two tasks 120 minutes apart: far past any threshold, still two columns.
        let tasks = CadenceCalendarOverlapLayout.solve(
            slots: [Self.task(540, 780), Self.task(660, 720)],
            cascadeGapMinutes: 24
        )
        #expect(tasks.map(\.column) == [0, 1])
        #expect(tasks.map(\.cascadeDepth) == [0, 0])

        // A task first, then an event that clears it by two hours: the event takes its own column.
        let mixed = CadenceCalendarOverlapLayout.solve(
            slots: [Self.task(540, 780), Self.event(660, 720)],
            cascadeGapMinutes: 24
        )
        #expect(mixed.map(\.column) == [0, 1])
        #expect(mixed.map(\.cascadeDepth) == [0, 0])
    }

    /// The mixed cluster the ticket asked to be reasoned about: a task holds a column, and the two
    /// events cascade inside the one that is left.
    @Test func eventsCascadeWithinTheirOwnColumnWhileATaskKeepsItsOwn() {
        let placed = CadenceCalendarOverlapLayout.solve(
            slots: [
                Self.event(540, 780),   // 9:00–13:00
                Self.task(555, 600),    // 9:15–10:00 — too close to the event to be stacked on
                Self.event(660, 720)    // 11:00–12:00 — clears the first event by two hours
            ],
            cascadeGapMinutes: 24
        )
        #expect(placed.map(\.column) == [0, 1, 0])
        #expect(placed.map(\.cascadeDepth) == [0, 0, 1])
        #expect(placed[0].totalColumns == 2, "the first event must still reserve width for the task")
    }

    // MARK: - 6. The geometry the solver feeds

    #if os(macOS)
    /// A cascaded block keeps its column's trailing edge, so the stack reads as a stack.
    @Test func aCascadedFrameIsIndentedAndStillEndsAtItsColumnsTrailingEdge() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 75)
        func frame(depth: Int, columns: Int = 1, column: Int = 0) -> TimelineBlockFrame {
            computeTimelineBlockFrame(
                startMinute: 540,
                durationMinutes: 60,
                column: column,
                totalColumns: columns,
                cascadeDepth: depth,
                totalWidth: 400,
                metrics: metrics,
                style: .calendar
            )
        }

        let base = frame(depth: 0)
        let first = frame(depth: 1)
        let second = frame(depth: 2)

        #expect(first.x > base.x)
        #expect(second.x > first.x)
        // All three end on the same trailing edge.
        #expect(abs((base.x + base.width) - (first.x + first.width)) < 0.001)
        #expect(abs((base.x + base.width) - (second.x + second.width)) < 0.001)
        // And the indent is the shared rule's, not a second copy of it.
        #expect(
            abs(first.x - base.x
                - CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: base.width, depth: 1)) < 0.001
        )

        // In a two-column cluster the cascade stays inside its own column — it does not run over
        // the column beside it, which is where a task would be.
        let rightColumn = frame(depth: 0, columns: 2, column: 1)
        let cascadedLeft = frame(depth: 1, columns: 2, column: 0)
        #expect(cascadedLeft.x + cascadedLeft.width <= rightColumn.x + 0.001)
    }

    /// Depth 0 is byte-for-byte the frame this function produced before T-3161.
    @Test func depthZeroFramesAreUnchangedByTheCascade() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        let style = TimelineBlockStyle.calendar
        for columns in 1...4 {
            for column in 0..<columns {
                let frame = computeTimelineBlockFrame(
                    startMinute: 600,
                    durationMinutes: 45,
                    column: column,
                    totalColumns: columns,
                    cascadeDepth: 0,
                    totalWidth: 500,
                    metrics: metrics,
                    style: style
                )
                let available = (500 - style.leadingInset - style.trailingInset) * style.blockWidthFraction
                let columnWidth = available / CGFloat(columns)
                #expect(abs(frame.width - (columnWidth - style.columnSpacing)) < 0.001)
                #expect(abs(frame.x - (style.leadingInset + CGFloat(column) * columnWidth)) < 0.001)
            }
        }
    }

    /// Draw order is start order, which is what makes the later block the one on top and the one
    /// that answers a click where the cascade covers its predecessor.
    @Test func eventLayoutsComeBackInStartOrderSoTheLaterBlockIsDrawnOnTop() throws {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        func item(hour: Int, minute: Int, durationMinutes: Int) throws -> CalendarEventItem {
            let event = EKEvent(eventStore: EKEventStore())
            event.title = "\(hour):\(minute)"
            let start = try #require(calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day))
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            return CalendarEventItem(event: event)
        }

        // The screenshot's three-event cluster, handed over in the wrong order on purpose.
        let middle = try item(hour: 3, minute: 0, durationMinutes: 165)
        let late = try item(hour: 4, minute: 0, durationMinutes: 120)
        let early = try item(hour: 2, minute: 15, durationMinutes: 240)

        let result = TimelineMetricsSupport.computeUnifiedLayouts(
            tasks: [],
            bundles: [],
            events: [middle, late, early],
            cascadeGapMinutes: 24
        )
        #expect(result.events.map(\.item.startMin) == [135, 180, 240])
        #expect(result.events.map(\.cascadeDepth) == [0, 1, 2])
        #expect(result.events.map(\.totalColumns) == [1, 1, 1])
    }

    #endif

    // MARK: - T-3165: the iOS day column lays tasks, bundles and events out together

    private typealias IOSLayout = iOSCalendarTimelineBlockLayout

    /// The iPad week column at its narrowest preferred width, which is where a split costs most.
    private static let iosColumnWidth: CGFloat = CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: true)
    private static let iosHourHeight: CGFloat = iOSCalendarTimelineMetrics.hourHeight

    /// Lays `blocks` out exactly as the day column does and returns each one's x range.
    private static func iosRanges(
        _ blocks: [IOSLayout.Block<String>]
    ) -> [String: (placement: CadenceCalendarOverlapPlacement, minX: CGFloat, maxX: CGFloat)] {
        let placements = IOSLayout.placements(for: blocks, hourHeight: iosHourHeight)
        var ranges: [String: (placement: CadenceCalendarOverlapPlacement, minX: CGFloat, maxX: CGFloat)] = [:]
        for block in blocks {
            let placement = placements[block.key] ?? .single
            let frame = IOSLayout.horizontalFrame(for: placement, kind: block.kind, columnWidth: iosColumnWidth)
            ranges[block.key] = (placement, frame.x, frame.x + frame.width)
        }
        return ranges
    }

    private static func disjoint(_ lhs: (minX: CGFloat, maxX: CGFloat), _ rhs: (minX: CGFloat, maxX: CGFloat)) -> Bool {
        lhs.maxX <= rhs.minX || rhs.maxX <= lhs.minX
    }

    /// The ticket's first fixture pair, by its literal times: "Prep slides" (task, 12:45-1:30) was
    /// painted full width across "Lunch with Sam" (event, 12:30-1:30). They must take two columns
    /// whose x ranges do not overlap, both inside the day column.
    @Test func theIOSDayColumnPutsAnOverlappingTaskBesideTheEventInsteadOfOverIt() throws {
        let ranges = Self.iosRanges([
            .init(key: "lunch", kind: .event, startMin: Self.minutes(12, 30), endMin: Self.minutes(13, 30)),
            .init(key: "prep", kind: .task, startMin: Self.minutes(12, 45), endMin: Self.minutes(13, 30)),
        ])
        let lunch = try #require(ranges["lunch"])
        let prep = try #require(ranges["prep"])
        #expect(lunch.placement.column != prep.placement.column, "the task and the event share a column")
        #expect(lunch.placement.totalColumns == 2 && prep.placement.totalColumns == 2)
        #expect(Self.disjoint((lunch.minX, lunch.maxX), (prep.minX, prep.maxX)), "the task block is drawn over the event block")
        for block in [lunch, prep] {
            #expect(block.minX >= 0 && block.maxX <= Self.iosColumnWidth, "a block runs outside its day column")
            #expect(block.maxX > block.minX, "a block was squeezed to nothing")
        }
    }

    /// The second pair: a 6 PM event over a bundle, which sliced "Post office" in half.
    @Test func theIOSDayColumnPutsAnEventBesideTheBundleItOverlaps() throws {
        let ranges = Self.iosRanges([
            .init(key: "bundle", kind: .bundle, startMin: Self.minutes(17, 30), endMin: Self.minutes(18, 30)),
            .init(key: "event", kind: .event, startMin: Self.minutes(18, 0), endMin: Self.minutes(19, 0)),
        ])
        let bundle = try #require(ranges["bundle"])
        let event = try #require(ranges["event"])
        #expect(bundle.placement.column != event.placement.column, "the bundle and the event share a column")
        #expect(Self.disjoint((bundle.minX, bundle.maxX), (event.minX, event.maxX)), "the event block is drawn over the bundle block")
    }

    /// A start gap that is plenty for one event to cascade over another is still not licence for
    /// an event to lay itself over a task — on iOS exactly as on the Mac. The two-event control
    /// proves the gap really is a cascading one, so the task half is not passing by accident.
    @Test func anIOSEventStartingWellAfterATaskStillTakesAColumnBesideIt() throws {
        let gap = CadenceCalendarOverlapLayout.cascadeGapMinutes(
            headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
            hourHeight: Self.iosHourHeight
        )
        let start = Self.minutes(9, 0)
        let late = start + gap + 15

        let control = Self.iosRanges([
            .init(key: "first", kind: .event, startMin: start, endMin: start + 180),
            .init(key: "second", kind: .event, startMin: late, endMin: late + 60),
        ])
        #expect(try #require(control["second"]).placement.cascadeDepth == 1, "non-vacuity: this gap no longer cascades two events")

        for kind in [IOSLayout.Kind.task, .bundle] {
            let ranges = Self.iosRanges([
                .init(key: "work", kind: kind, startMin: start, endMin: start + 180),
                .init(key: "event", kind: .event, startMin: late, endMin: late + 60),
            ])
            let work = try #require(ranges["work"])
            let event = try #require(ranges["event"])
            #expect(event.placement.cascadeDepth == 0, "an event cascaded over a \(kind)")
            #expect(Self.disjoint((work.minX, work.maxX), (event.minX, event.maxX)), "an event is drawn over a \(kind)")
        }
    }

    /// Three kinds at one hour take three columns, in draw order, and none of the three covers
    /// another — the property macOS's `computeUnifiedLayouts` already had.
    @Test func threeIOSBlocksOfThreeKindsAtOneHourTakeThreeDisjointColumns() throws {
        let ranges = Self.iosRanges([
            .init(key: "bundle", kind: .bundle, startMin: Self.minutes(14, 0), endMin: Self.minutes(15, 0)),
            .init(key: "event", kind: .event, startMin: Self.minutes(14, 0), endMin: Self.minutes(15, 0)),
            .init(key: "task", kind: .task, startMin: Self.minutes(14, 0), endMin: Self.minutes(15, 0)),
        ])
        let keys = ["bundle", "event", "task"]
        let placed = try keys.map { try #require(ranges[$0]) }
        #expect(Set(placed.map(\.placement.column)).count == 3, "three overlapping blocks share columns")
        #expect(placed.allSatisfy { $0.placement.totalColumns == 3 })
        for (index, lhs) in placed.enumerated() {
            for rhs in placed[(index + 1)...] {
                #expect(Self.disjoint((lhs.minX, lhs.maxX), (rhs.minX, rhs.maxX)), "two of the three blocks overlap")
            }
        }
    }

    /// Blocks that do not overlap keep the whole of their strip, so a day with no overlaps draws
    /// what it drew before T-3165 — a task as wide as a lone event, a bundle wider than both.
    @Test func iOSBlocksThatDoNotOverlapEachKeepTheirWholeStrip() throws {
        let ranges = Self.iosRanges([
            .init(key: "task", kind: .task, startMin: Self.minutes(8, 0), endMin: Self.minutes(9, 0)),
            .init(key: "event", kind: .event, startMin: Self.minutes(9, 0), endMin: Self.minutes(10, 0)),
            .init(key: "bundle", kind: .bundle, startMin: Self.minutes(10, 0), endMin: Self.minutes(11, 0)),
        ])
        let task = try #require(ranges["task"])
        let event = try #require(ranges["event"])
        let bundle = try #require(ranges["bundle"])
        for block in [task, event, bundle] {
            #expect(block.placement == .single, "a block that overlaps nothing was split")
        }
        #expect(task.minX == event.minX && task.maxX == event.maxX, "a lone task and a lone event are drawn at different widths")
        #expect(bundle.minX < task.minX && bundle.maxX > task.maxX, "a lone bundle lost its wider strip")
    }

    /// **The view really feeds all three kinds in.** `Cadence/iOS/` is invisible to this target,
    /// so the arithmetic above is only half the claim; the other half is that the day column hands
    /// every task, bundle and event to one `placements` call and draws each block at the frame it
    /// gets back, rather than at a hand-written full width.
    @Test func theIOSDayColumnSolvesEveryTimedBlockInOnePassAndDrawsEachAtItsSolvedFrame() throws {
        let path = "Cadence/iOS/iOSCalendarTimelineViews.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.count == raw.count && code != raw, "non-vacuity: the comment stripper did not run over \(path)")
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code),
            "iOSCalendarTimelineDayColumn was not found in \(path)"
        )
        #expect(column.count > 4_000, "non-vacuity: the day column read as \(column.count) characters")

        #expect(
            CadenceSourceScan.matchCount(#"iOSCalendarTimelineBlockLayout\.placements\(for:"#, in: column) == 1,
            "the day column does not solve its blocks in exactly one pass"
        )
        for kind in ["task", "bundle", "event"] {
            #expect(
                CadenceSourceScan.matchCount(#"key: \.\#(kind)\("#, in: column) == 1,
                "the day column does not hand its \(kind) blocks to the solver"
            )
            #expect(
                CadenceSourceScan.matchCount(#"horizontalFrame\(placements\[\.\#(kind)\("#, in: column) == 1,
                "the day column does not draw its \(kind) blocks at their solved frame"
            )
        }
        // The two full-width spellings the tasks and bundles were drawn at before T-3165.
        #expect(
            CadenceSourceScan.matchCount(#"\.frame\(width: colWidth - [0-9]+, height:"#, in: column) == 0,
            "a timed block is still drawn at a hand-written full column width"
        )
    }
}
