#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - TimeScale

enum TimeScale: String, CaseIterable {
    case twoWeeks  = "2W"
    case month     = "M"
    case quarter   = "Q"
    case year      = "Y"
    case fiveYears = "5Y"

    var dayWidth: CGFloat {
        switch self {
        case .twoWeeks:  return 48
        case .month:     return 26
        case .quarter:   return 12
        case .year:      return 3.5
        case .fiveYears: return 1.5
        }
    }

    var renderDays: Int {
        switch self {
        case .twoWeeks:  return 120
        case .month:     return 180
        case .quarter:   return 365
        case .year:      return 730
        case .fiveYears: return 1825
        }
    }

    var leadDays: Int {
        switch self {
        case .twoWeeks:  return 14
        case .month:     return 30
        case .quarter:   return 60
        case .year:      return 90
        case .fiveYears: return 180
        }
    }
}

// MARK: - Goal Bar Layout (for arrow drawing)

struct GoalBarLayout {
    let goalID: UUID
    let centerY: CGFloat
    let barStartX: CGFloat
    let barEndX: CGFloat
}

// MARK: - GoalsView

struct GoalsView: View {
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Environment(\.modelContext) private var modelContext

    @State private var scale: TimeScale = .twoWeeks
    @State private var showCreateGoal = false
    @State private var searchText = ""
    @State private var statusFilter: GoalStatusFilter = .active
    @State private var todayJumpNonce = 0

    // Dependency link mode
    @State private var isLinkMode = false
    @State private var linkSourceGoalID: UUID? = nil

    // Drag state (shared across rows via binding)
    @State private var draggingGoalID: UUID? = nil
    @State private var dragDayOffset: Int = 0

    private let leftColWidth: CGFloat = 280
    private let rowHeight: CGFloat = 58
    private let dateRowHeight: CGFloat = 40
    private let sectionHeaderHeight: CGFloat = 32
    private let barHeight: CGFloat = 32

    private var cal: Calendar { Calendar.current }

    private var renderStartDate: Date {
        cal.date(byAdding: .day, value: -scale.leadDays, to: cal.startOfDay(for: Date()))!
    }

    private var todayDayIdx: Int { scale.leadDays }

    private var filteredGoals: [Goal] {
        allGoals.filter { goal in
            let matchesStatus = statusFilter.matches(goal.status)
            guard matchesStatus else { return false }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            return goal.title.lowercased().contains(q)
                || goal.desc.lowercased().contains(q)
                || (goal.context?.name.lowercased().contains(q) ?? false)
        }
    }

    private var goalGroups: [GoalGroup] {
        var groups: [GoalGroup] = []
        for ctx in allContexts {
            let ctxGoals = filteredGoals.filter { $0.context?.id == ctx.id }
            if !ctxGoals.isEmpty {
                groups.append(GoalGroup(id: ctx.id.uuidString, contextName: ctx.name,
                                        contextColor: ctx.colorHex, contextIcon: ctx.icon,
                                        goals: ctxGoals))
            }
        }
        let noCtxGoals = filteredGoals.filter { $0.context == nil }
        if !noCtxGoals.isEmpty {
            groups.append(GoalGroup(id: "no-context", contextName: "No Context",
                                    contextColor: "#6b7a99", contextIcon: "circle",
                                    goals: noCtxGoals))
        }
        return groups
    }

    // Flat ordered list matching render order (for Y position math)
    private var flatGoals: [Goal] {
        goalGroups.flatMap(\.goals)
    }

    private var activeGoalsCount: Int { allGoals.filter { $0.status == .active }.count }
    private var doneGoalsCount: Int { allGoals.filter { $0.status == .done }.count }
    private var pausedGoalsCount: Int { allGoals.filter { $0.status == .paused }.count }

    private var overdueGoalsCount: Int {
        let today = cal.startOfDay(for: Date())
        return allGoals.filter {
            $0.status != .done && (($0.endDateDate.map { $0 < today }) ?? false)
        }.count
    }

    private var averageProgress: Double {
        guard !filteredGoals.isEmpty else { return 0 }
        return filteredGoals.reduce(0) { $0 + $1.progress } / Double(filteredGoals.count)
    }

    private var nearestDueGoal: Goal? {
        filteredGoals
            .filter { $0.status != .done }
            .compactMap { goal in goal.endDateDate.map { (goal, $0) } }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(scale.renderDays) * scale.dayWidth
    }

    var body: some View {
        VStack(spacing: 16) {
            goalsHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)

            summaryCards
                .padding(.horizontal, 20)

            timelineToolbar
                .padding(.horizontal, 20)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    leftColumn
                    Divider().background(Theme.borderSubtle)
                    rightTimeline
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.borderSubtle, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreateGoal) { CreateGoalSheet() }
        .onChange(of: isLinkMode) { _, on in
            if !on { linkSourceGoalID = nil }
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            GoalListHeader(width: leftColWidth, height: dateRowHeight)
            Divider().background(Theme.borderSubtle)

            ForEach(goalGroups) { group in
                GoalGroupHeader(group: group, height: sectionHeaderHeight)
                Divider().background(Theme.borderSubtle)
                ForEach(group.goals) { goal in
                    GoalLeftRow(goal: goal)
                        .frame(height: rowHeight)
                    Divider().background(Theme.borderSubtle.opacity(0.4))
                }
            }

            if goalGroups.isEmpty {
                GoalsEmptyState(hasSearch: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || statusFilter != .active)
                    .padding(.top, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: leftColWidth)
        .background(Theme.surface)
    }

    // MARK: - Right Timeline

    private var rightTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Grid + rows
                    VStack(spacing: 0) {
                        DateHeaderRow(
                            startDate: renderStartDate,
                            scale: scale,
                            dayWidth: scale.dayWidth,
                            height: dateRowHeight,
                            todayDayIdx: todayDayIdx
                        )
                        Divider().background(Theme.borderSubtle)

                        ForEach(goalGroups) { group in
                            // Section spacer row
                            TimelineGridBackground(
                                scale: scale,
                                renderStartDate: renderStartDate,
                                height: sectionHeaderHeight,
                                totalWidth: totalTimelineWidth
                            )
                            .background(Theme.surface)
                            Divider().background(Theme.borderSubtle)

                            ForEach(group.goals) { goal in
                                GoalTimelineBar(
                                    goal: goal,
                                    viewStartDate: renderStartDate,
                                    scale: scale,
                                    rowHeight: rowHeight,
                                    barHeight: barHeight,
                                    totalWidth: totalTimelineWidth,
                                    isLinkMode: isLinkMode,
                                    isLinkSource: linkSourceGoalID == goal.id,
                                    onBarTapped: { handleBarTap(goal) },
                                    onDragChanged: { offset in
                                        draggingGoalID = goal.id
                                        dragDayOffset = offset
                                    },
                                    onDragEnded: { offset in
                                        commitDrag(goal: goal, dayOffset: offset)
                                        draggingGoalID = nil
                                        dragDayOffset = 0
                                    },
                                    dragDayOffset: draggingGoalID == goal.id ? dragDayOffset : 0
                                )
                                Divider().background(Theme.borderSubtle.opacity(0.4))
                            }
                        }
                    }
                    .frame(width: totalTimelineWidth)

                    // Dependency arrow overlay
                    DependencyArrowCanvas(
                        goals: flatGoals,
                        goalGroups: goalGroups,
                        scale: scale,
                        renderStartDate: renderStartDate,
                        rowHeight: rowHeight,
                        sectionHeaderHeight: sectionHeaderHeight,
                        dateRowHeight: dateRowHeight,
                        barHeight: barHeight,
                        totalTimelineWidth: totalTimelineWidth,
                        totalHeight: totalContentHeight,
                        linkSourceID: linkSourceGoalID,
                        onDeleteDependency: removeDependency
                    )
                    .frame(width: totalTimelineWidth, height: totalContentHeight)

                    // Today line
                    TodayLine(
                        viewStartDate: renderStartDate,
                        dayWidth: scale.dayWidth,
                        totalHeight: totalContentHeight
                    )
                }
                .frame(width: totalTimelineWidth)
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(todayDayIdx, anchor: .leading) }
            }
            .onChange(of: scale) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(todayDayIdx, anchor: .leading)
                }
            }
            .onChange(of: todayJumpNonce) {
                DispatchQueue.main.async { proxy.scrollTo(todayDayIdx, anchor: .leading) }
            }
        }
    }

    private var totalContentHeight: CGFloat {
        dateRowHeight + 1
        + CGFloat(goalGroups.count) * (sectionHeaderHeight + 1)
        + CGFloat(flatGoals.count) * (rowHeight + 0.5)
    }

    // MARK: - Link Mode Interaction

    private func handleBarTap(_ goal: Goal) {
        guard isLinkMode else { return }
        if let source = linkSourceGoalID {
            if source == goal.id {
                linkSourceGoalID = nil
                return
            }
            // Create dependency: goal depends on source
            addDependency(from: source, to: goal.id)
            linkSourceGoalID = nil
            isLinkMode = false
        } else {
            linkSourceGoalID = goal.id
        }
    }

    private func addDependency(from sourceID: UUID, to targetID: UUID) {
        guard let target = allGoals.first(where: { $0.id == targetID }) else { return }
        var ids = target.dependsOnGoalIDs
        guard !ids.contains(sourceID) else { return }
        ids.append(sourceID)
        target.dependsOnGoalIDs = ids
    }

    private func removeDependency(sourceID: UUID, targetID: UUID) {
        guard let target = allGoals.first(where: { $0.id == targetID }) else { return }
        target.dependsOnGoalIDs = target.dependsOnGoalIDs.filter { $0 != sourceID }
    }

    // MARK: - Drag commit

    private func commitDrag(goal: Goal, dayOffset: Int) {
        guard dayOffset != 0 else { return }
        guard let start = DateFormatters.ymd.date(from: goal.startDate),
              let end = DateFormatters.ymd.date(from: goal.endDate) else { return }
        let newStart = cal.date(byAdding: .day, value: dayOffset, to: start)!
        let newEnd   = cal.date(byAdding: .day, value: dayOffset, to: end)!
        goal.startDate = DateFormatters.ymd.string(from: newStart)
        goal.endDate   = DateFormatters.ymd.string(from: newEnd)
    }

    private func scrollToToday() { todayJumpNonce += 1 }

    // MARK: - Header / Summary / Toolbar

    private var goalsHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goals")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Long-range work, organized by context and timeline.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 20)
                CadenceActionButton(
                    title: "New Goal",
                    systemImage: "plus",
                    role: .primary,
                    size: .regular
                ) {
                    showCreateGoal = true
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    TextField("Search goals, outcome, or context", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))

                HStack(spacing: 8) {
                    ForEach(GoalStatusFilter.allCases, id: \.self) { filter in
                        CadencePillButton(
                            title: filter.label,
                            isSelected: statusFilter == filter,
                            minWidth: 58
                        ) {
                            statusFilter = filter
                        }
                    }
                }
                .padding(4)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle, lineWidth: 1))
            }
        }
        .padding(20)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            GoalsSummaryCard(title: "Active", value: "\(activeGoalsCount)",
                subtitle: overdueGoalsCount == 0 ? "No slipping deadlines" : "\(overdueGoalsCount) overdue",
                color: Theme.blue, icon: "target")
            GoalsSummaryCard(title: "Average Progress", value: "\(Int(averageProgress * 100))%",
                subtitle: "\(filteredGoals.count) visible goals",
                color: Theme.green, icon: "chart.line.uptrend.xyaxis")
            GoalsSummaryCard(title: "Closest Deadline",
                value: nearestDueGoal?.daysSummary ?? "None",
                subtitle: nearestDueGoal?.title ?? "No active goals in view",
                color: nearestDueGoal?.isOverdue == true ? Theme.red : Theme.amber, icon: "flag.fill")
            GoalsSummaryCard(title: "Done / Paused", value: "\(doneGoalsCount) / \(pausedGoalsCount)",
                subtitle: "Resolved and parked goals", color: Theme.purple, icon: "checkmark.circle")
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text("\(DateFormatters.shortDate.string(from: renderStartDate)) – \(DateFormatters.shortDate.string(from: cal.date(byAdding: .day, value: scale.renderDays - 1, to: renderStartDate) ?? renderStartDate))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            // Link mode toggle
            CadenceActionButton(
                title: isLinkMode ? (linkSourceGoalID == nil ? "Select a goal..." : "Select target...") : "Add Dependency",
                systemImage: isLinkMode ? "link.badge.minus" : "link",
                role: .secondary,
                size: .compact,
                tint: isLinkMode ? Theme.amber : Theme.blue
            ) {
                isLinkMode.toggle()
            }

            CadenceActionButton(
                title: "Jump to Today",
                role: .secondary,
                size: .compact
            ) {
                scrollToToday()
            }

            HStack(spacing: 2) {
                ForEach(TimeScale.allCases, id: \.self) { s in
                    CadencePillButton(
                        title: s.rawValue,
                        isSelected: scale == s,
                        minWidth: 40
                    ) {
                        scale = s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { scrollToToday() }
                    }
                }
            }
            .padding(4)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
        }
    }

    // MARK: - Goal Group

    struct GoalGroup: Identifiable {
        let id: String
        let contextName: String
        let contextColor: String
        let contextIcon: String
        let goals: [Goal]
    }
}

#endif
