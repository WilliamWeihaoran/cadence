#if os(macOS)
import SwiftUI

// MARK: - Goal dependency helpers on model

extension Goal {
    var dependsOnGoalIDs: [UUID] {
        get {
            guard !dependsOnGoalIDsJSON.isEmpty,
                  let data = dependsOnGoalIDsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings.compactMap { UUID(uuidString: $0) }
        }
        set {
            let strings = newValue.map(\.uuidString)
            dependsOnGoalIDsJSON = (try? String(data: JSONEncoder().encode(strings), encoding: .utf8)) ?? ""
        }
    }
}

// MARK: - GoalStatusFilter

enum GoalStatusFilter: CaseIterable {
    case active, paused, done, all

    var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .done:   return "Done"
        case .all:    return "All"
        }
    }

    func matches(_ status: GoalStatus) -> Bool {
        switch self {
        case .all:    return true
        case .active: return status == .active
        case .paused: return status == .paused
        case .done:   return status == .done
        }
    }
}

// MARK: - Timeline Grid Background

struct TimelineGridBackground: View {
    let scale: TimeScale
    let renderStartDate: Date
    let height: CGFloat
    let totalWidth: CGFloat

    private let cal = Calendar.current

    var body: some View {
        Canvas { ctx, size in
            for dayIdx in 0..<scale.renderDays {
                guard let date = cal.date(byAdding: .day, value: dayIdx, to: renderStartDate) else { continue }
                guard isBoundaryDay(dayIdx: dayIdx, date: date) else { continue }

                let x = CGFloat(dayIdx) * scale.dayWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(Color(hex: "#252a3d").opacity(0.5)), lineWidth: 0.5)
            }
        }
        .frame(width: totalWidth, height: height)
    }

    private func isBoundaryDay(dayIdx: Int, date: Date) -> Bool {
        switch scale {
        case .twoWeeks:  return cal.component(.weekday, from: date) == cal.firstWeekday
        case .month:     return cal.component(.weekday, from: date) == cal.firstWeekday
        case .quarter:   return cal.component(.weekday, from: date) == cal.firstWeekday
        case .year:      return cal.component(.day, from: date) == 1
        case .fiveYears: return cal.component(.month, from: date) == 1 && cal.component(.day, from: date) == 1
        }
    }
}

// MARK: - Date Header Row

struct DateHeaderRow: View {
    let startDate: Date
    let scale: TimeScale
    let dayWidth: CGFloat
    let height: CGFloat
    let todayDayIdx: Int

    private let cal = Calendar.current

    var body: some View {
        Canvas { ctx, size in
            for dayIdx in 0..<scale.renderDays {
                guard let date = cal.date(byAdding: .day, value: dayIdx, to: startDate) else { continue }
                if shouldShowLabel(dayIdx: dayIdx, date: date) {
                    let x = CGFloat(dayIdx) * dayWidth
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(Color(hex: "#252a3d").opacity(0.5)), lineWidth: 0.5)
                }
            }

            let todayX = CGFloat(todayDayIdx) * dayWidth
            let todayRect = CGRect(x: todayX, y: 0, width: dayWidth, height: size.height)
            ctx.fill(Path(todayRect), with: .color(Color(hex: "#4a9eff").opacity(0.06)))
        }
        .overlay {
            HStack(spacing: 0) {
                ForEach(0..<scale.renderDays, id: \.self) { dayIdx in
                    let date = cal.date(byAdding: .day, value: dayIdx, to: startDate) ?? startDate
                    let isToday = cal.isDateInToday(date)
                    ZStack {
                        if shouldShowLabel(dayIdx: dayIdx, date: date) {
                            Text(dayLabel(date: date))
                                .font(.system(size: dayWidth > 20 ? 10 : 8))
                                .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: dayWidth, height: height)
                    .id(dayIdx)
                }
            }
        }
        .frame(height: height)
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

// MARK: - Goal Timeline Bar

struct GoalTimelineBar: View {
    let goal: Goal
    let viewStartDate: Date
    let scale: TimeScale
    let rowHeight: CGFloat
    let barHeight: CGFloat
    let totalWidth: CGFloat
    let isLinkMode: Bool
    let isLinkSource: Bool
    let onBarTapped: () -> Void
    let onDragChanged: (Int) -> Void
    let onDragEnded: (Int) -> Void
    let dragDayOffset: Int

    @State private var hovered = false
    private let cal = Calendar.current

    var body: some View {
        ZStack(alignment: .leading) {
            TimelineGridBackground(
                scale: scale,
                renderStartDate: viewStartDate,
                height: rowHeight,
                totalWidth: totalWidth
            )
            .background(Color.clear)

            if let todayX = todayHighlightX {
                Rectangle()
                    .fill(Theme.blue.opacity(0.03))
                    .frame(width: scale.dayWidth, height: rowHeight)
                    .position(x: todayX + scale.dayWidth / 2, y: rowHeight / 2)
                    .allowsHitTesting(false)
            }

            if let bar = barParams(dayOffset: dragDayOffset) {
                goalBar(bar: bar)
                    .position(x: bar.x + bar.width / 2, y: rowHeight / 2)
            }
        }
        .frame(width: totalWidth, height: rowHeight)
        .contentShape(Rectangle())
    }

    private var todayHighlightX: CGFloat? {
        let days = cal.dateComponents([.day], from: viewStartDate, to: cal.startOfDay(for: Date())).day ?? 0
        let x = CGFloat(days) * scale.dayWidth
        return x >= 0 ? x : nil
    }

    @ViewBuilder
    private func goalBar(bar: BarParams) -> some View {
        let color = Color(hex: goal.colorHex)
        let isSource = isLinkSource

        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(isSource ? 0.35 : 0.18))

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(isSource ? 0.7 : 0.5))
                    .frame(width: max(0, geo.size.width * goal.progress))
            }

            RoundedRectangle(cornerRadius: 10)
                .stroke(isSource ? color : color.opacity(0.65), lineWidth: isSource ? 2 : 1)

            HStack(spacing: 6) {
                if goal.status == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(goal.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 9)

            if hovered && !isLinkMode {
                HStack {
                    dragHandle
                    Spacer()
                    dragHandle
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(width: bar.width, height: barHeight)
        .shadow(color: color.opacity(dragDayOffset != 0 ? 0.4 : 0.12), radius: dragDayOffset != 0 ? 12 : 6, y: dragDayOffset != 0 ? 4 : 2)
        .scaleEffect(dragDayOffset != 0 ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: dragDayOffset != 0)
        .onHover { hovered = $0 }
        .onTapGesture { onBarTapped() }
        .gesture(
            isLinkMode ? nil : DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let days = Int(round(value.translation.width / scale.dayWidth))
                    onDragChanged(days)
                }
                .onEnded { value in
                    let days = Int(round(value.translation.width / scale.dayWidth))
                    onDragEnded(days)
                }
        )
        .overlay(alignment: .trailing) {
            if let end = goal.endDateDate {
                Text(DateFormatters.shortDate.string(from: end))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.trailing, 8)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white.opacity(0.4))
            .frame(width: 3, height: 14)
    }

    private struct BarParams {
        let x: CGFloat
        let width: CGFloat
    }

    private func barParams(dayOffset: Int = 0) -> BarParams? {
        guard !goal.startDate.isEmpty, !goal.endDate.isEmpty,
              let start = DateFormatters.ymd.date(from: goal.startDate),
              let end = DateFormatters.ymd.date(from: goal.endDate) else { return nil }

        guard let shifted = GoalTimelineDateMath.shiftedRange(start: start, end: end, dayOffset: dayOffset, calendar: cal),
              let viewEnd = GoalTimelineDateMath.renderEndDate(startDate: viewStartDate, scale: scale, calendar: cal) else {
            return nil
        }
        let adjStart = shifted.start
        let adjEnd = shifted.end

        let clampedStart = max(adjStart, viewStartDate)
        let clampedEnd = min(adjEnd, viewEnd)
        guard clampedStart < clampedEnd else { return nil }

        let startOffset = cal.dateComponents([.day], from: viewStartDate, to: clampedStart).day ?? 0
        let endOffset = cal.dateComponents([.day], from: viewStartDate, to: clampedEnd).day ?? 0

        let x = CGFloat(startOffset) * scale.dayWidth
        let width = max(scale.dayWidth, CGFloat(endOffset - startOffset) * scale.dayWidth)
        return BarParams(x: x, width: width)
    }
}

// MARK: - Dependency Arrow Canvas

struct DependencyArrowCanvas: View {
    let goals: [Goal]
    let goalGroups: [GoalsView.GoalGroup]
    let scale: TimeScale
    let renderStartDate: Date
    let rowHeight: CGFloat
    let sectionHeaderHeight: CGFloat
    let dateRowHeight: CGFloat
    let barHeight: CGFloat
    let totalTimelineWidth: CGFloat
    let totalHeight: CGFloat
    let linkSourceID: UUID?
    let onDeleteDependency: (UUID, UUID) -> Void

    private let cal = Calendar.current

    var body: some View {
        Canvas { ctx, _ in
            for (targetGoal, sourceGoal) in allDependencyPairs() {
                drawArrow(ctx: ctx, from: sourceGoal, to: targetGoal)
            }
        }
        .allowsHitTesting(false)
    }

    private func allDependencyPairs() -> [(Goal, Goal)] {
        let goalByID = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        var pairs: [(Goal, Goal)] = []
        for goal in goals {
            for sourceID in goal.dependsOnGoalIDs {
                if let source = goalByID[sourceID] {
                    pairs.append((goal, source))
                }
            }
        }
        return pairs
    }

    private func drawArrow(ctx: GraphicsContext, from sourceGoal: Goal, to targetGoal: Goal) {
        guard let sourceBar = barX(for: sourceGoal),
              let targetBar = barX(for: targetGoal),
              let sourceY = goalCenterY(for: sourceGoal),
              let targetY = goalCenterY(for: targetGoal) else { return }

        let startPt = CGPoint(x: sourceBar.endX, y: sourceY)
        let endPt = CGPoint(x: targetBar.startX, y: targetY)

        let dx = abs(endPt.x - startPt.x)
        let cp1 = CGPoint(x: startPt.x + min(dx * 0.5, 40), y: startPt.y)
        let cp2 = CGPoint(x: endPt.x - min(dx * 0.5, 40), y: endPt.y)

        var path = Path()
        path.move(to: startPt)
        path.addCurve(to: endPt, control1: cp1, control2: cp2)

        let arrowColor = Color(hex: "#4a9eff").opacity(0.65)
        ctx.stroke(path, with: .color(arrowColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        let angle: CGFloat = 25 * .pi / 180
        let arrowLen: CGFloat = 7
        let dir = CGPoint(x: endPt.x - cp2.x, y: endPt.y - cp2.y)
        let len = sqrt(dir.x * dir.x + dir.y * dir.y)
        guard len > 0 else { return }
        let norm = CGPoint(x: dir.x / len, y: dir.y / len)

        let tip1 = CGPoint(
            x: endPt.x - arrowLen * (norm.x * cos(angle) - norm.y * sin(angle)),
            y: endPt.y - arrowLen * (norm.x * sin(angle) + norm.y * cos(angle))
        )
        let tip2 = CGPoint(
            x: endPt.x - arrowLen * (norm.x * cos(-angle) - norm.y * sin(-angle)),
            y: endPt.y - arrowLen * (norm.x * sin(-angle) + norm.y * cos(-angle))
        )

        var arrowHead = Path()
        arrowHead.move(to: tip1)
        arrowHead.addLine(to: endPt)
        arrowHead.addLine(to: tip2)
        ctx.stroke(arrowHead, with: .color(arrowColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private struct BarXInfo {
        let startX: CGFloat
        let endX: CGFloat
    }

    private func barX(for goal: Goal) -> BarXInfo? {
        guard !goal.startDate.isEmpty, !goal.endDate.isEmpty,
              let start = DateFormatters.ymd.date(from: goal.startDate),
              let end = DateFormatters.ymd.date(from: goal.endDate) else { return nil }

        guard let viewEnd = GoalTimelineDateMath.renderEndDate(startDate: renderStartDate, scale: scale, calendar: cal) else {
            return nil
        }
        let cStart = max(start, renderStartDate)
        let cEnd = min(end, viewEnd)
        guard cStart < cEnd else { return nil }

        let so = cal.dateComponents([.day], from: renderStartDate, to: cStart).day ?? 0
        let eo = cal.dateComponents([.day], from: renderStartDate, to: cEnd).day ?? 0
        let x = CGFloat(so) * scale.dayWidth
        let w = max(scale.dayWidth, CGFloat(eo - so) * scale.dayWidth)
        return BarXInfo(startX: x, endX: x + w)
    }

    private func goalCenterY(for goal: Goal) -> CGFloat? {
        var y = dateRowHeight + 1
        for group in goalGroups {
            y += sectionHeaderHeight + 1
            for g in group.goals {
                if g.id == goal.id {
                    return y + rowHeight / 2
                }
                y += rowHeight + 0.5
            }
        }
        return nil
    }
}

// MARK: - Goal Left Row

struct GoalLeftRow: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 12) {
            GoalProgressRing(goal: goal)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(goal.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    GoalStatusBadge(status: goal.status)
                }
                Text(goal.desc.isEmpty ? goal.rangeLabel : goal.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.borderSubtle.opacity(0.9))
                        Capsule()
                            .fill(Color(hex: goal.colorHex))
                            .frame(width: max(10, geo.size.width * goal.progress))
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(goal.progressSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(goal.daysSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(goal.isOverdue ? Theme.red : Theme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Supporting Views

struct GoalListHeader: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Progress, status, and timing")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: height, alignment: .leading)
        .background(Theme.surface)
    }
}

struct GoalGroupHeader: View {
    let group: GoalsView.GoalGroup
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.contextIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: group.contextColor))
            Text(group.contextName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            Text("\(group.goals.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.text.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(Theme.surface)
    }
}

struct GoalsSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

struct GoalsEmptyState: View {
    let hasSearch: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "line.3.horizontal.decrease.circle" : "target")
                .font(.system(size: 30))
                .foregroundStyle(Theme.dim)
            Text(hasSearch ? "No matching goals" : "No goals yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(hasSearch ? "Try a different search or filter." : "Add a goal to start tracking longer-term work.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
    }
}

struct GoalProgressRing: View {
    let goal: Goal

    var body: some View {
        ZStack {
            Circle().fill(Theme.borderSubtle).frame(width: 28, height: 28)
            Circle()
                .trim(from: 0, to: max(0.02, goal.progress))
                .stroke(Color(hex: goal.colorHex), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(-90))
        }
    }
}

struct GoalStatusBadge: View {
    let status: GoalStatus

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .active: return "ACTIVE"
        case .paused: return "PAUSED"
        case .done:   return "DONE"
        }
    }

    private var color: Color {
        switch status {
        case .active: return Theme.blue
        case .paused: return Theme.amber
        case .done:   return Theme.green
        }
    }
}

// MARK: - Today Line

struct TodayLine: View {
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

// MARK: - Goal Extension

extension Goal {
    var startDateDate: Date? { DateFormatters.ymd.date(from: startDate) }
    var endDateDate: Date? { DateFormatters.ymd.date(from: endDate) }

    var rangeLabel: String {
        guard let s = startDateDate, let e = endDateDate else { return "No timeline set" }
        return "\(DateFormatters.shortDate.string(from: s)) – \(DateFormatters.shortDate.string(from: e))"
    }

    var progressSummary: String {
        switch progressType {
        case .hours:
            return targetHours > 0 ? "\(Int(loggedHours))/\(Int(targetHours))h" : "\(Int(loggedHours))h"
        case .subtasks:
            let items = (tasks ?? []).filter { !$0.isCancelled }
            return "\(items.filter(\.isDone).count)/\(items.count) tasks"
        }
    }

    var daysSummary: String {
        guard let end = endDateDate else { return "No target date" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: end).day ?? 0
        if status == .done { return "Completed" }
        if days < 0 { return "\(-days)d late" }
        if days == 0 { return "Due today" }
        return "\(days)d left"
    }

    var isOverdue: Bool {
        guard status != .done, let end = endDateDate else { return false }
        return end < Calendar.current.startOfDay(for: Date())
    }
}
#endif
