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

private struct GoalTimelineRow: Identifiable {
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

private enum GoalTimelineRowKind {
    case group(GoalMissionGroup)
    case goal(Goal)
}

private struct GoalTimelineRowLayout: Identifiable {
    let row: GoalTimelineRow
    let y: CGFloat

    var id: String { row.id }
}

private struct GoalTimelineMonthHeader: View {
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

private struct GoalTimelineGrid: View {
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

private struct GoalTimelineTodayLine: View {
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

private struct GoalTimelineRowBackground: View {
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

private struct GoalTimelineGroupRow: View {
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

private struct GoalTimelineGoalRailRow: View {
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

private enum GoalTimelineBarDragMode {
    case move
    case leading
    case trailing
}

private struct GoalTimelineBarView: View {
    @Environment(\.modelContext) private var modelContext

    let goal: Goal
    let rangeStart: Date
    let dayWidth: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    @State private var activeDragMode: GoalTimelineBarDragMode?
    @State private var activeDeltaDays = 0

    private var goalRange: (start: Date, end: Date)? {
        guard let start = goal.startDateDate,
              let end = goal.endDateDate else {
            return nil
        }
        return (start, end)
    }

    private var displayedRange: (start: Date, end: Date)? {
        guard let goalRange else { return nil }
        guard let activeDragMode else { return goalRange }

        switch activeDragMode {
        case .move:
            return GoalTimelineDateMath.movedRange(
                start: goalRange.start,
                end: goalRange.end,
                dayDelta: activeDeltaDays
            )
        case .leading:
            return GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .leading,
                dayDelta: activeDeltaDays
            )
        case .trailing:
            return GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .trailing,
                dayDelta: activeDeltaDays
            )
        }
    }

    private var displayedFrame: GoalTimelineBarFrame? {
        guard let displayedRange else { return nil }
        return GoalTimelineDateMath.barFrame(
            start: displayedRange.start,
            end: displayedRange.end,
            rangeStart: rangeStart,
            dayWidth: dayWidth
        )
    }

    var body: some View {
        if let frame = displayedFrame {
            barContent
                .frame(width: max(40, frame.width), height: 28)
                .offset(x: frame.x)
                .onTapGesture(perform: onSelect)
                .onTapGesture(count: 2, perform: onEdit)
        }
    }

    private var barContent: some View {
        let color = Color(hex: goal.colorHex)

        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(goal.status == .done ? 0.10 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? color.opacity(0.95) : color.opacity(0.55), lineWidth: isSelected ? 1.5 : 1)
                )

            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(color, lineWidth: 1.5)
                    .background(Circle().fill(color.opacity(goal.status == .done ? 0.5 : 0.12)))
                    .frame(width: 15, height: 15)
                Text(goal.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)

            HStack(spacing: 0) {
                resizeHandle(edge: .leading)
                Spacer(minLength: 0)
                resizeHandle(edge: .trailing)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .gesture(dragGesture(mode: .move))
        .shadow(color: isSelected ? color.opacity(0.18) : Color.clear, radius: 8, y: 2)
    }

    private func resizeHandle(edge: GoalTimelineBarDragMode) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .gesture(dragGesture(mode: edge))
    }

    private func dragGesture(mode: GoalTimelineBarDragMode) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                activeDragMode = mode
                activeDeltaDays = GoalTimelineDateMath.dayDelta(
                    for: value.translation.width,
                    dayWidth: dayWidth
                )
            }
            .onEnded { value in
                let delta = GoalTimelineDateMath.dayDelta(
                    for: value.translation.width,
                    dayWidth: dayWidth
                )
                commit(mode: mode, deltaDays: delta)
                activeDragMode = nil
                activeDeltaDays = 0
            }
    }

    private func commit(mode: GoalTimelineBarDragMode, deltaDays: Int) {
        guard deltaDays != 0, let goalRange else { return }

        let newRange: (start: Date, end: Date)?
        switch mode {
        case .move:
            newRange = GoalTimelineDateMath.movedRange(
                start: goalRange.start,
                end: goalRange.end,
                dayDelta: deltaDays
            )
        case .leading:
            newRange = GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .leading,
                dayDelta: deltaDays
            )
        case .trailing:
            newRange = GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .trailing,
                dayDelta: deltaDays
            )
        }

        guard let newRange else { return }
        goal.startDate = DateFormatters.dateKey(from: newRange.start)
        goal.endDate = DateFormatters.dateKey(from: newRange.end)
        try? modelContext.save()
    }
}

private struct GoalTimelineFilterPopover: View {
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
