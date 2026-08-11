import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
@MainActor
struct GoalTimelineDateMathTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    @Test func convertsDatesToTimelineXPositions() {
        let rangeStart = date("2026-03-01")
        let target = date("2026-03-06")

        let x = GoalTimelineDateMath.xPosition(
            for: target,
            rangeStart: rangeStart,
            dayWidth: 12,
            calendar: calendar
        )

        #expect(x == 60)
    }

    @Test func createsInclusiveBarFrames() {
        let rangeStart = date("2026-03-01")

        let frame = GoalTimelineDateMath.barFrame(
            start: date("2026-03-03"),
            end: date("2026-03-05"),
            rangeStart: rangeStart,
            dayWidth: 10,
            calendar: calendar
        )

        #expect(frame.x == 20)
        #expect(frame.width == 30)
    }

    @Test func generatesMonthMarkersInsideVisibleRange() {
        let markers = GoalTimelineDateMath.monthMarkers(
            rangeStart: date("2026-02-15"),
            rangeEnd: date("2026-05-05"),
            dayWidth: 10,
            calendar: calendar
        )

        #expect(markers.map(\.label) == ["Mar", "Apr", "May"])
        #expect(markers.first?.x == CGFloat(14 * 10))
    }

    @Test func movingRangeShiftsStartAndEndTogether() throws {
        let moved = try #require(
            GoalTimelineDateMath.movedRange(
                start: date("2026-03-03"),
                end: date("2026-03-05"),
                dayDelta: 4,
                calendar: calendar
            )
        )

        #expect(DateFormatters.dateKey(from: moved.start) == "2026-03-07")
        #expect(DateFormatters.dateKey(from: moved.end) == "2026-03-09")
    }

    @Test func resizingRangeClampsToValidDates() throws {
        let leading = try #require(
            GoalTimelineDateMath.resizedRange(
                start: date("2026-03-10"),
                end: date("2026-03-15"),
                edge: .leading,
                dayDelta: 10,
                calendar: calendar
            )
        )
        let trailing = try #require(
            GoalTimelineDateMath.resizedRange(
                start: date("2026-03-10"),
                end: date("2026-03-15"),
                edge: .trailing,
                dayDelta: -10,
                calendar: calendar
            )
        )

        #expect(DateFormatters.dateKey(from: leading.start) == "2026-03-15")
        #expect(DateFormatters.dateKey(from: leading.end) == "2026-03-15")
        #expect(DateFormatters.dateKey(from: trailing.start) == "2026-03-10")
        #expect(DateFormatters.dateKey(from: trailing.end) == "2026-03-10")
    }

    @Test func missingDateKeysDoNotProduceBarFrames() {
        let frame = GoalTimelineDateMath.barFrame(
            startKey: "",
            endKey: "2026-03-05",
            rangeStart: date("2026-03-01"),
            dayWidth: 10,
            calendar: calendar
        )

        #expect(frame == nil)
    }

    private func date(_ key: String) -> Date {
        DateFormatters.date(from: key) ?? Date()
    }
}

/// Row/bar resolution and the direction header's count, both of which decide what the Goals page
/// claims exists. Kept beside the date math because they are the other half of "what the Gantt
/// draws" — the math says where a bar goes, these say whether there is a bar at all.
@MainActor
struct GoalTimelineRowResolutionTests {
    /// A direction is *only* ever a `.group` row. When `GoalTimelineRow.goal` returned nil for
    /// those, `GoalTimelineView` skipped the bar and drew a permanently blank track next to the
    /// direction's own left-rail label.
    @Test func groupRowResolvesToItsOwnDirectionSoTheGanttCanDrawItsBar() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let direction = Goal(title: "Ship Cadence")
        direction.kind = .ongoing
        direction.startDate = "2026-03-01"
        direction.endDate = "2026-06-30"
        modelContext.insert(direction)

        let group = GoalMissionGroup(
            id: direction.id.uuidString,
            title: direction.title,
            icon: direction.icon,
            colorHex: direction.colorHex,
            parentGoal: direction,
            goals: []
        )

        let row = GoalTimelineRow.group(group, height: 48)

        #expect(row.goal?.id == direction.id)
        #expect(row.goal?.startDateDate != nil)
        #expect(row.goal?.endDateDate != nil)
    }

    /// A group with no backing goal is a synthetic bucket; it has no date range of its own and
    /// must not resolve to some other row's goal.
    @Test func syntheticGroupRowResolvesToNoGoal() {
        let group = GoalMissionGroup(
            id: "synthetic",
            title: "Unassigned",
            icon: "flag",
            colorHex: Theme.blueHex,
            goals: []
        )

        #expect(GoalTimelineRow.group(group, height: 48).goal == nil)
    }
}

/// The direction header used to count only the milestones that survived the page filter while the
/// percentage beside it was resolved from every milestone the direction owns — "0 milestones · 50%"
/// over "No milestones under this goal yet". These pin the count, the empty state, and the
/// progress arithmetic to the same set of milestones.
@MainActor
struct GoalMissionGroupingTests {
    @Test func filteredOutMilestonesAreRepresentedInTheCountAndEmptyState() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let direction = Goal(title: "Ship Cadence")
        direction.kind = .ongoing
        let doneMilestone = Goal(title: "Beta")
        doneMilestone.status = .done
        doneMilestone.order = 0
        doneMilestone.parentGoal = direction
        let pausedMilestone = Goal(title: "Docs")
        pausedMilestone.status = .paused
        pausedMilestone.order = 1
        pausedMilestone.parentGoal = direction
        direction.subGoals = [doneMilestone, pausedMilestone]

        for goal in [direction, doneMilestone, pausedMilestone] {
            modelContext.insert(goal)
        }

        let groups = GoalMissionGrouping.groups(from: [direction, doneMilestone, pausedMilestone]) {
            GoalStatusFilter.active.matches($0.status)
        }

        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.goals.isEmpty)
        #expect(group.hiddenMilestoneCount == 2)
        #expect(group.ownedMilestoneCount == 2)
        // The header no longer says "0 milestones" next to a percentage those two milestones move.
        #expect(group.milestoneCountLabel == "0 of 2 milestones")
        #expect(group.emptyMilestonesText == "2 milestones are hidden by the current filter.")
    }

    @Test func aDirectionThatOwnsNoMilestonesStillReadsAsEmpty() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let direction = Goal(title: "Ship Cadence")
        direction.kind = .ongoing
        modelContext.insert(direction)

        let group = try #require(GoalMissionGrouping.groups(from: [direction]) { _ in true }.first)

        #expect(group.hiddenMilestoneCount == 0)
        #expect(group.milestoneCountLabel == "0 milestones")
        #expect(group.emptyMilestonesText == "No milestones under this goal yet.")
    }

    @Test func partiallyFilteredDirectionCountsBothHalves() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let direction = Goal(title: "Ship Cadence")
        let active = Goal(title: "Beta")
        active.order = 0
        active.parentGoal = direction
        let done = Goal(title: "Docs")
        done.status = .done
        done.order = 1
        done.parentGoal = direction
        // Nested one level deeper: the flattening is depth-first, so a grandchild is a milestone
        // of the direction too and has to be counted on whichever side of the filter it lands.
        let nested = Goal(title: "API docs")
        nested.status = .done
        nested.parentGoal = done
        done.subGoals = [nested]
        direction.subGoals = [active, done]

        for goal in [direction, active, done, nested] {
            modelContext.insert(goal)
        }

        let group = try #require(
            GoalMissionGrouping.groups(from: [direction, active, done, nested]) {
                GoalStatusFilter.active.matches($0.status)
            }.first
        )

        #expect(group.goals.map(\.title) == ["Beta"])
        #expect(group.hiddenMilestoneCount == 2)
        #expect(group.milestoneCountLabel == "1 of 3 milestones")
    }

    @Test func unfilteredDirectionKeepsThePlainMilestoneCount() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let direction = Goal(title: "Ship Cadence")
        let onlyMilestone = Goal(title: "Beta")
        onlyMilestone.parentGoal = direction
        direction.subGoals = [onlyMilestone]
        modelContext.insert(direction)
        modelContext.insert(onlyMilestone)

        let group = try #require(
            GoalMissionGrouping.groups(from: [direction, onlyMilestone]) { _ in true }.first
        )

        #expect(group.hiddenMilestoneCount == 0)
        #expect(group.milestoneCountLabel == "1 milestone")
    }
}
#endif
