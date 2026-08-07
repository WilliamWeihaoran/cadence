#if os(macOS)
import SwiftData
import SwiftUI

enum GoalsViewMode: String, CaseIterable {
    case mission
    case timeline

    var title: String {
        switch self {
        case .mission: return "Mission"
        case .timeline: return "Timeline"
        }
    }

    var icon: String {
        switch self {
        case .mission: return "rectangle.grid.1x2"
        case .timeline: return "chart.bar.xaxis"
        }
    }
}

struct GoalsViewModeToggle: View {
    @Binding var selection: GoalsViewMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GoalsViewMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == mode ? Theme.text : Theme.dim)
                        .frame(width: 30, height: 28)
                        .background(selection == mode ? Theme.surfaceElevated : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.cadencePlain)
                .help(mode.title)
            }
        }
        .padding(3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

struct GoalTimelineView: View {
    let groups: [GoalMissionGroup]
    @Binding var selectedGoalID: UUID?
    @Binding var viewMode: GoalsViewMode
    @Binding var scale: TimeScale
    @Binding var searchText: String
    @Binding var statusFilter: GoalStatusFilter
    let onCreateGoal: () -> Void
    let onEditGoal: (Goal) -> Void

    @State private var referenceDate = Date()
    @State private var showsFilter = false

    private let leftRailWidth: CGFloat = 300
    private let headerHeight: CGFloat = 42
    private let groupRowHeight: CGFloat = 48
    private let goalRowHeight: CGFloat = 42

    private var rangeStart: Date {
        GoalTimelineDateMath.renderStartDate(scale: scale, referenceDate: referenceDate)
    }

    private var rangeEnd: Date {
        GoalTimelineDateMath.renderEndDate(startDate: rangeStart, scale: scale) ?? rangeStart
    }

    private var timelineWidth: CGFloat {
        CGFloat(scale.renderDays) * scale.dayWidth
    }

    private var rows: [GoalTimelineRow] {
        groups.flatMap { group in
            [GoalTimelineRow.group(group, height: groupRowHeight)] +
            group.goals.map { GoalTimelineRow.goal($0, height: goalRowHeight) }
        }
    }

    private var rowLayouts: [GoalTimelineRowLayout] {
        var y: CGFloat = 0
        return rows.map { row in
            defer { y += row.height }
            return GoalTimelineRowLayout(row: row, y: y)
        }
    }

    private var contentHeight: CGFloat {
        rows.reduce(0) { $0 + $1.height }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Theme.borderSubtle)

            if rows.isEmpty {
                EmptyStateView(
                    message: searchText.isEmpty ? "No goals yet" : "No matching goals",
                    subtitle: searchText.isEmpty ? "Create a goal, then set its date range." : "Try a different filter.",
                    icon: "chart.bar.xaxis"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        leftRail

                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: 0) {
                                GoalTimelineMonthHeader(
                                    rangeStart: rangeStart,
                                    rangeEnd: rangeEnd,
                                    dayWidth: scale.dayWidth,
                                    width: timelineWidth,
                                    height: headerHeight
                                )
                                timelineBody
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Goals")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)

            Spacer()

            GoalsViewModeToggle(selection: $viewMode)

            HStack(spacing: 4) {
                ForEach(GoalTimelineDateMath.roadmapScales, id: \.self) { option in
                    CadencePillButton(
                        title: option.rawValue,
                        isSelected: scale == option,
                        minWidth: 34
                    ) {
                        scale = option
                    }
                }
            }
            .padding(3)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))

            HStack(spacing: 4) {
                timelineNavButton(systemImage: "chevron.left") {
                    shiftReference(by: -rangeStepDays)
                }
                timelineNavButton(systemImage: "smallcircle.filled.circle") {
                    referenceDate = Date()
                }
                timelineNavButton(systemImage: "chevron.right") {
                    shiftReference(by: rangeStepDays)
                }
            }
            .padding(3)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))

            Button {
                showsFilter.toggle()
            } label: {
                HStack(spacing: 7) {
                    Text("Filter")
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.cadencePlain)
            .popover(isPresented: $showsFilter, arrowEdge: .bottom) {
                GoalTimelineFilterPopover(
                    searchText: $searchText,
                    statusFilter: $statusFilter
                )
                .frame(width: 280)
                .background(Theme.surface)
            }

            CadenceActionButton(
                title: "New Goal",
                systemImage: "plus",
                role: .primary,
                size: .compact,
                action: onCreateGoal
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private var leftRail: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Goals")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
            }
            .frame(height: headerHeight)
            .padding(.horizontal, 18)
            .background(Theme.surface)

            ForEach(rows) { row in
                switch row.kind {
                case .group(let group):
                    GoalTimelineGroupRow(group: group)
                        .frame(height: row.height)
                case .goal(let goal):
                    GoalTimelineGoalRailRow(
                        goal: goal,
                        isSelected: selectedGoalID == goal.id,
                        onSelect: { selectedGoalID = goal.id },
                        onEdit: { onEditGoal(goal) }
                    )
                    .frame(height: row.height)
                }
            }
        }
        .frame(width: leftRailWidth)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
        }
    }

    private var timelineBody: some View {
        ZStack(alignment: .topLeading) {
            GoalTimelineGrid(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                dayWidth: scale.dayWidth,
                width: timelineWidth,
                height: contentHeight
            )

            ForEach(rowLayouts) { layout in
                GoalTimelineRowBackground(
                    row: layout.row,
                    isSelected: selectedGoalID == layout.row.goal?.id,
                    width: timelineWidth,
                    height: layout.row.height
                )
                .offset(y: layout.y)

                if let goal = layout.row.goal,
                   goal.startDateDate != nil,
                   goal.endDateDate != nil {
                    GoalTimelineBarView(
                        goal: goal,
                        rangeStart: rangeStart,
                        dayWidth: scale.dayWidth,
                        isSelected: selectedGoalID == goal.id,
                        onSelect: { selectedGoalID = goal.id },
                        onEdit: { onEditGoal(goal) }
                    )
                    .offset(y: layout.y + 7)
                }
            }

            GoalTimelineTodayLine(
                rangeStart: rangeStart,
                dayWidth: scale.dayWidth,
                width: timelineWidth,
                height: contentHeight
            )
        }
        .frame(width: timelineWidth, height: contentHeight)
        .background(Theme.bg)
    }

    private var rangeStepDays: Int {
        switch scale {
        case .twoWeeks: return 14
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .fiveYears: return 365
        }
    }

    private func timelineNavButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 26, height: 26)
                .background(Theme.surfaceElevated.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
    }

    private func shiftReference(by days: Int) {
        referenceDate = Calendar.current.date(byAdding: .day, value: days, to: referenceDate) ?? referenceDate
    }
}
#endif
