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

    // Days to render in the scrollable buffer
    var renderDays: Int {
        switch self {
        case .twoWeeks:  return 120
        case .month:     return 180
        case .quarter:   return 365
        case .year:      return 730
        case .fiveYears: return 1825
        }
    }

    // How many days before today to start the buffer
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

// MARK: - GoalsView

struct GoalsView: View {
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Environment(\.modelContext) private var modelContext

    @State private var scale: TimeScale = .twoWeeks
    @State private var showCreateGoal = false
    @State private var scrollProxy: ScrollViewProxy? = nil

    private let leftColWidth: CGFloat = 220
    private let rowHeight: CGFloat = 44
    private let dateRowHeight: CGFloat = 32
    private let sectionHeaderHeight: CGFloat = 28

    private var renderStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -scale.leadDays, to: Calendar.current.startOfDay(for: Date()))!
    }

    private var todayDayIdx: Int { scale.leadDays }

    private var goalGroups: [GoalGroup] {
        var groups: [GoalGroup] = []
        for ctx in allContexts {
            let ctxGoals = allGoals.filter { $0.context?.id == ctx.id }
            if !ctxGoals.isEmpty {
                groups.append(GoalGroup(id: ctx.id.uuidString, contextName: ctx.name,
                                        contextColor: ctx.colorHex, contextIcon: ctx.icon, goals: ctxGoals))
            }
        }
        let noCtxGoals = allGoals.filter { $0.context == nil }
        if !noCtxGoals.isEmpty {
            groups.append(GoalGroup(id: "no-context", contextName: "No Context",
                                    contextColor: "#6b7a99", contextIcon: "circle", goals: noCtxGoals))
        }
        return groups
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(scale.renderDays) * scale.dayWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("Goals")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)

                Spacer()

                Button("Today") {
                    scrollToToday()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Scale picker
                HStack(spacing: 2) {
                    ForEach(TimeScale.allCases, id: \.self) { s in
                        Button(s.rawValue) {
                            scale = s
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                scrollToToday()
                            }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 11, weight: scale == s ? .semibold : .regular))
                        .foregroundStyle(scale == s ? Theme.blue : Theme.dim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(scale == s ? Theme.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                Button {
                    showCreateGoal = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("Add Goal").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            // Main layout
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    // Left column (fixed)
                    VStack(spacing: 0) {
                        Color.clear.frame(width: leftColWidth, height: dateRowHeight)
                        Divider().background(Theme.borderSubtle)

                        ForEach(goalGroups) { group in
                            HStack(spacing: 6) {
                                Image(systemName: group.contextIcon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(hex: group.contextColor))
                                Text(group.contextName.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                                    .kerning(0.8)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: sectionHeaderHeight)
                            .background(Theme.surface)

                            Divider().background(Theme.borderSubtle)

                            ForEach(group.goals) { goal in
                                GoalLeftRow(goal: goal)
                                    .frame(height: rowHeight)
                                Divider().background(Theme.borderSubtle.opacity(0.5))
                            }
                        }

                        if allGoals.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "target")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.dim)
                                Text("No goals yet")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.dim)
                                Text("Add a goal to get started")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.dim.opacity(0.7))
                            }
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: leftColWidth)
                    .background(Theme.surface)

                    Divider().background(Theme.borderSubtle)

                    // Right timeline (horizontally scrollable)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: true) {
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    // Date header row
                                    DateHeaderRow(
                                        startDate: renderStartDate,
                                        scale: scale,
                                        dayWidth: scale.dayWidth,
                                        height: dateRowHeight,
                                        todayDayIdx: todayDayIdx
                                    )
                                    Divider().background(Theme.borderSubtle)

                                    ForEach(goalGroups) { group in
                                        // Section header spacer
                                        HStack(spacing: 0) {
                                            ForEach(0..<scale.renderDays, id: \.self) { dayIdx in
                                                Rectangle()
                                                    .fill(Color.clear)
                                                    .frame(width: scale.dayWidth, height: sectionHeaderHeight)
                                                    .overlay(alignment: .trailing) {
                                                        Rectangle()
                                                            .fill(Theme.borderSubtle.opacity(0.3))
                                                            .frame(width: 0.5)
                                                    }
                                            }
                                        }
                                        .background(Theme.surface)

                                        Divider().background(Theme.borderSubtle)

                                        ForEach(group.goals) { goal in
                                            GoalTimelineRow(
                                                goal: goal,
                                                viewStartDate: renderStartDate,
                                                scale: scale,
                                                rowHeight: rowHeight
                                            )
                                            Divider().background(Theme.borderSubtle.opacity(0.5))
                                        }
                                    }
                                }
                                .frame(width: totalTimelineWidth)

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
                            DispatchQueue.main.async {
                                let x = CGFloat(todayDayIdx) * scale.dayWidth
                                proxy.scrollTo(todayDayIdx, anchor: .leading)
                                _ = x
                            }
                        }
                        .onChange(of: scale) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo(todayDayIdx, anchor: .leading)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreateGoal) {
            CreateGoalSheet()
        }
    }

    private var totalContentHeight: CGFloat {
        let groupCount = goalGroups.count
        let totalGoals = allGoals.count
        return dateRowHeight + CGFloat(groupCount) * sectionHeaderHeight + CGFloat(totalGoals) * rowHeight
    }

    private func scrollToToday() {
        // Handled inside ScrollViewReader via onChange/onAppear
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

// MARK: - Date Header Row

private struct DateHeaderRow: View {
    let startDate: Date
    let scale: TimeScale
    let dayWidth: CGFloat
    let height: CGFloat
    let todayDayIdx: Int

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<scale.renderDays, id: \.self) { dayIdx in
                let date = cal.date(byAdding: .day, value: dayIdx, to: startDate) ?? startDate
                let isToday = cal.isDateInToday(date)
                let showLabel = shouldShowLabel(dayIdx: dayIdx, date: date)

                ZStack {
                    if showLabel {
                        Text(dayLabel(date: date))
                            .font(.system(size: dayWidth > 20 ? 10 : 8))
                            .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: dayWidth, height: height)
                .background(isToday ? Theme.blue.opacity(0.05) : Color.clear)
                .overlay(alignment: .trailing) {
                    if showLabel {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(0.5))
                            .frame(width: 0.5)
                    }
                }
                .id(dayIdx)
            }
        }
        .background(Theme.surface)
    }

    private func shouldShowLabel(dayIdx: Int, date: Date) -> Bool {
        switch scale {
        case .twoWeeks:  return true
        case .month:     return dayIdx % 3 == 0
        case .quarter:   return dayIdx % 7 == 0
        case .year:      return dayIdx % 30 == 0
        case .fiveYears: return dayIdx % 90 == 0
        }
    }

    private func dayLabel(date: Date) -> String {
        switch scale {
        case .twoWeeks:
            return "\(DateFormatters.dayOfWeek.string(from: date))\n\(DateFormatters.dayNumber.string(from: date))"
        case .month:
            return DateFormatters.shortDate.string(from: date)
        case .quarter, .year, .fiveYears:
            return DateFormatters.monthAbbrev.string(from: date)
        }
    }
}

// MARK: - Goal Left Row

private struct GoalLeftRow: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.borderSubtle)
                    .frame(width: 24, height: 24)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(Color(hex: goal.colorHex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
            }
            Text(goal.title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Goal Timeline Row

private struct GoalTimelineRow: View {
    let goal: Goal
    let viewStartDate: Date
    let scale: TimeScale
    let rowHeight: CGFloat

    private let cal = Calendar.current
    private var fmt: DateFormatter { DateFormatters.ymd }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<scale.renderDays, id: \.self) { dayIdx in
                    let date = cal.date(byAdding: .day, value: dayIdx, to: viewStartDate) ?? viewStartDate
                    let isToday = cal.isDateInToday(date)
                    Rectangle()
                        .fill(isToday ? Theme.blue.opacity(0.04) : Color.clear)
                        .frame(width: scale.dayWidth, height: rowHeight)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Theme.borderSubtle.opacity(0.2))
                                .frame(width: 0.5)
                        }
                }
            }

            if let barParams = barParams() {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: goal.colorHex).opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: goal.colorHex).opacity(0.6), lineWidth: 1))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: goal.colorHex).opacity(0.5))
                                .frame(width: geo.size.width * goal.progress)
                        }
                    }
                    .overlay(alignment: .leading) {
                        Text(goal.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                    }
                    .frame(width: barParams.width, height: 26)
                    .offset(x: barParams.x, y: (rowHeight - 26) / 2)
            }
        }
        .frame(width: CGFloat(scale.renderDays) * scale.dayWidth, height: rowHeight)
        .clipped()
    }

    private struct BarParams { let x: CGFloat; let width: CGFloat }

    private func barParams() -> BarParams? {
        guard !goal.startDate.isEmpty, !goal.endDate.isEmpty,
              let start = fmt.date(from: goal.startDate),
              let end = fmt.date(from: goal.endDate) else { return nil }

        let viewEnd = cal.date(byAdding: .day, value: scale.renderDays, to: viewStartDate)!
        let clampedStart = max(start, viewStartDate)
        let clampedEnd   = min(end, viewEnd)
        guard clampedStart < clampedEnd else { return nil }

        let startOffset = cal.dateComponents([.day], from: viewStartDate, to: clampedStart).day ?? 0
        let endOffset   = cal.dateComponents([.day], from: viewStartDate, to: clampedEnd).day ?? 0

        let x = CGFloat(startOffset) * scale.dayWidth
        let width = max(scale.dayWidth, CGFloat(endOffset - startOffset) * scale.dayWidth)
        return BarParams(x: x, width: width)
    }
}

// MARK: - Today Line

private struct TodayLine: View {
    let viewStartDate: Date
    let dayWidth: CGFloat
    let totalHeight: CGFloat

    private let cal = Calendar.current

    var body: some View {
        let days = cal.dateComponents([.day], from: viewStartDate, to: cal.startOfDay(for: Date())).day ?? 0
        let x = CGFloat(days) * dayWidth + dayWidth / 2
        if x >= 0 {
            Rectangle()
                .fill(Theme.red.opacity(0.7))
                .frame(width: 1.5, height: totalHeight)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }
}
#endif
