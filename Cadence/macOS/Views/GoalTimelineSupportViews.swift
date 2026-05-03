#if os(macOS)
import SwiftUI

struct GoalTimelineRow: Identifiable {
    let id: String
    let kind: GoalTimelineRowKind
    let height: CGFloat

    var goal: Goal? {
        if case .goal(let goal) = kind { return goal }
        return nil
    }

    static func group(_ group: GoalMissionGroup, height: CGFloat) -> GoalTimelineRow {
        GoalTimelineRow(id: "group-\(group.id)", kind: .group(group), height: height)
    }

    static func goal(_ goal: Goal, height: CGFloat) -> GoalTimelineRow {
        GoalTimelineRow(id: "goal-\(goal.id.uuidString)", kind: .goal(goal), height: height)
    }
}

enum GoalTimelineRowKind {
    case group(GoalMissionGroup)
    case goal(Goal)
}

struct GoalTimelineRowLayout: Identifiable {
    let row: GoalTimelineRow
    let y: CGFloat

    var id: String { row.id }
}

struct GoalTimelineMonthHeader: View {
    let rangeStart: Date
    let rangeEnd: Date
    let dayWidth: CGFloat
    let width: CGFloat
    let height: CGFloat

    private var markers: [GoalTimelineMonthMarker] {
        GoalTimelineDateMath.monthMarkers(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            dayWidth: dayWidth
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.surface

            ForEach(markers, id: \.date) { marker in
                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(width: 1, height: height)
                    .offset(x: marker.x)

                Text(marker.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 70, alignment: .leading)
                    .offset(x: marker.x + 8, y: 16)
            }

            GoalTimelineTodayLine(
                rangeStart: rangeStart,
                dayWidth: dayWidth,
                width: width,
                height: height
            )
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
        }
    }
}

struct GoalTimelineGrid: View {
    let rangeStart: Date
    let rangeEnd: Date
    let dayWidth: CGFloat
    let width: CGFloat
    let height: CGFloat

    private var markers: [GoalTimelineMonthMarker] {
        GoalTimelineDateMath.monthMarkers(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            dayWidth: dayWidth
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg
            ForEach(markers, id: \.date) { marker in
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.72))
                    .frame(width: 1, height: height)
                    .offset(x: marker.x)
            }
        }
        .frame(width: width, height: height)
    }
}

struct GoalTimelineTodayLine: View {
    let rangeStart: Date
    let dayWidth: CGFloat
    let width: CGFloat
    let height: CGFloat

    private var x: CGFloat {
        GoalTimelineDateMath.xPosition(
            for: Calendar.current.startOfDay(for: Date()),
            rangeStart: rangeStart,
            dayWidth: dayWidth
        )
    }

    var body: some View {
        Rectangle()
            .fill(Theme.red)
            .frame(width: 1.5, height: height)
            .offset(x: x)
            .opacity(x >= 0 && x <= width ? 1 : 0)
    }
}

struct GoalTimelineRowBackground: View {
    let row: GoalTimelineRow
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(fill)
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.55))
                .frame(height: 1)
        }
        .frame(width: width, height: height)
    }

    private var fill: Color {
        switch row.kind {
        case .group:
            return Theme.surface.opacity(0.35)
        case .goal:
            return isSelected ? Theme.blue.opacity(0.08) : Color.clear
        }
    }
}

struct GoalTimelineGroupRow: View {
    let group: GoalMissionGroup

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: group.colorHex))
            Text(group.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            Text("\(group.goals.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceElevated.opacity(0.7))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 18)
        .background(Theme.surface.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
        }
    }
}

struct GoalTimelineGoalRailRow: View {
    let goal: Goal
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color(hex: goal.colorHex), lineWidth: 1.7)
                .background(Circle().fill(goal.status == .done ? Color(hex: goal.colorHex).opacity(0.45) : Color.clear))
                .frame(width: 15, height: 15)

            Text(goal.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(goal.status == .done ? Theme.dim : Theme.text)
                .lineLimit(1)
                .strikethrough(goal.status == .done, color: Theme.dim)

            Spacer(minLength: 8)

            GoalTimelineDeadlineChip(goal: goal)
        }
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
        .background(isSelected ? Theme.blue.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.55)).frame(height: 1)
        }
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onEdit)
    }
}

private struct GoalTimelineDeadlineChip: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var label: String {
        goal.endDateDate == nil ? "No date" : goal.daysSummary
    }

    private var icon: String {
        goal.endDateDate == nil ? "calendar.badge.exclamationmark" : "flag.fill"
    }

    private var color: Color {
        if goal.endDateDate == nil { return Theme.dim }
        if goal.isOverdue { return Theme.red }
        return Theme.dim
    }
}

struct GoalTimelineFilterPopover: View {
    @Binding var searchText: String
    @Binding var statusFilter: GoalStatusFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                TextField("Search goals", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.borderSubtle, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("STATUS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                HStack(spacing: 6) {
                    ForEach(GoalStatusFilter.allCases, id: \.self) { filter in
                        CadencePillButton(
                            title: filter.label,
                            isSelected: statusFilter == filter,
                            minWidth: 48
                        ) {
                            statusFilter = filter
                        }
                    }
                }
            }
        }
        .padding(14)
    }
}
#endif
