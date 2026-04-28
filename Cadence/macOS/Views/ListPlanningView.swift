#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - ListPlanningView

struct ListPlanningView: View {
    let tasks: [AppTask]
    let area: Area?
    let project: Project?

    @Query(sort: \AppTask.createdAt, order: .reverse) private var allTasks: [AppTask]

    @State private var scale: PlanningScale = .twoWeeks
    @State private var draggingTaskID: UUID? = nil
    @State private var dragDayOffset: Int = 0

    private let rowHeight: CGFloat = 56
    private let barHeight: CGFloat = 34
    private let headerHeight: CGFloat = 52
    private let leftRailWidth: CGFloat = 260

    private var planningTitle: String {
        project?.name ?? area?.name ?? "Planning"
    }

    private var planner: ListPlanningPlanner {
        ListPlanningPlanner(tasks: tasks, allTasks: allTasks, scale: scale)
    }

    var body: some View {
        let snapshot = planner.makeSnapshot()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PlanningHeaderCard(
                    title: planningTitle,
                    windowLabel: snapshot.windowLabel,
                    openCount: snapshot.openTasks.count,
                    readyCount: snapshot.readyTasks.count,
                    blockedCount: snapshot.blockedTasks.count,
                    recurringCount: snapshot.recurringTasks.count,
                    backlogCount: snapshot.unscheduledTasks.count,
                    scale: scale,
                    onScaleChange: { scale = $0 }
                )

                PlanningTimelineSurfaceCard(
                    snapshot: snapshot,
                    dayWidth: scale.dayWidth,
                    rowHeight: rowHeight,
                    barHeight: barHeight,
                    headerHeight: headerHeight,
                    leftRailWidth: leftRailWidth,
                    draggingTaskID: draggingTaskID,
                    dragDayOffset: dragDayOffset,
                    onDragChanged: { id, offset in
                        draggingTaskID = id
                        dragDayOffset = offset
                    },
                    onDragEnded: { id, offset in
                        if let task = snapshot.openTasks.first(where: { $0.id == id }) {
                            planner.commitDrag(task: task, dayOffset: offset)
                        }
                        draggingTaskID = nil
                        dragDayOffset = 0
                    }
                )
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
    }
}

// MARK: - Header Card

private struct PlanningHeaderCard: View {
    let title: String
    let windowLabel: String
    let openCount: Int
    let readyCount: Int
    let blockedCount: Int
    let recurringCount: Int
    let backlogCount: Int
    let scale: PlanningScale
    let onScaleChange: (PlanningScale) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Timeline view  •  \(windowLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                PlanningSummaryPill(title: "Open",    value: "\(openCount)",    tint: Theme.blue)
                PlanningSummaryPill(title: "Ready",   value: "\(readyCount)",   tint: Theme.green)
                PlanningSummaryPill(title: "Blocked", value: "\(blockedCount)", tint: Theme.amber)
                if recurringCount > 0 {
                    PlanningSummaryPill(title: "Repeats", value: "\(recurringCount)", tint: Theme.purple)
                }
                if backlogCount > 0 {
                    PlanningSummaryPill(title: "Backlog", value: "\(backlogCount)", tint: Theme.dim)
                }
            }

            // Scale picker
            HStack(spacing: 2) {
                ForEach(PlanningScale.allCases, id: \.self) { s in
                    Button(s.rawValue) { onScaleChange(s) }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 11, weight: scale == s ? .semibold : .regular))
                        .foregroundStyle(scale == s ? Theme.blue : Theme.dim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(scale == s ? Theme.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(4)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
        }
        .padding(.horizontal, 4)
    }
}

private struct PlanningSummaryPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surfaceElevated.opacity(0.78))
        .clipShape(Capsule())
    }
}

// MARK: - Timeline Surface Card

private struct PlanningTimelineSurfaceCard: View {
    let snapshot: PlanningTimelineSnapshot
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    let barHeight: CGFloat
    let headerHeight: CGFloat
    let leftRailWidth: CGFloat
    let draggingTaskID: UUID?
    let dragDayOffset: Int
    let onDragChanged: (UUID, Int) -> Void
    let onDragEnded: (UUID, Int) -> Void

    private var dates: [Date] { snapshot.dates }
    private var tasks: [AppTask] { snapshot.timelineTasks }
    private var totalGridWidth: CGFloat { CGFloat(dates.count) * dayWidth }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left rail
            VStack(spacing: 0) {
                PlanningRailHeader()
                    .frame(height: headerHeight)
                Divider().background(Theme.borderSubtle)
                ForEach(tasks) { task in
                    PlanningRailRow(
                        task: task,
                        dependentCount: snapshot.dependentCount(for: task)
                    )
                    .frame(height: rowHeight)
                    Divider().background(Theme.borderSubtle.opacity(0.4))
                }
                if tasks.isEmpty {
                    PlanningRailEmpty()
                        .frame(height: 160)
                }
            }
            .frame(width: leftRailWidth)
            .background(Theme.surface.opacity(0.85))

            Divider().background(Theme.borderSubtle)

            // Right timeline
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Grid rows + bars
                    VStack(spacing: 0) {
                        PlanningTimelineHeader(dates: dates, dayWidth: dayWidth, height: headerHeight)
                        Divider().background(Theme.borderSubtle)

                        ForEach(tasks) { task in
                            let activeDrag = draggingTaskID == task.id ? dragDayOffset : 0
                            PlanningTimelineRow(
                                task: task,
                                dates: dates,
                                dayWidth: dayWidth,
                                rowHeight: rowHeight,
                                barHeight: barHeight,
                                span: snapshot.span(for: task),
                                dragDayOffset: activeDrag,
                                onDragChanged: { offset in onDragChanged(task.id, offset) },
                                onDragEnded:   { offset in onDragEnded(task.id, offset) }
                            )
                            Divider().background(Theme.borderSubtle.opacity(0.4))
                        }

                        if tasks.isEmpty {
                            PlanningEmptyGrid(dates: dates, dayWidth: dayWidth)
                                .frame(height: 160)
                        }
                    }
                    .frame(width: totalGridWidth)

                    // Dependency arrows
                    if !snapshot.connectors.isEmpty {
                        PlanningArrowOverlay(
                            connectors: snapshot.connectors,
                            dayWidth: dayWidth,
                            rowHeight: rowHeight,
                            headerHeight: headerHeight + 1
                        )
                        .frame(width: totalGridWidth)
                        .allowsHitTesting(false)
                    }

                    // Today line
                    Rectangle()
                        .fill(Theme.red.opacity(0.65))
                        .frame(width: 1.5)
                        .offset(x: dayWidth / 2 - 0.75, y: 0)
                        .allowsHitTesting(false)
                }
                .frame(width: totalGridWidth)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.surface.opacity(0.98), Theme.surfaceElevated.opacity(0.96)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Timeline Header

private struct PlanningTimelineHeader: View {
    let dates: [Date]
    let dayWidth: CGFloat
    let height: CGFloat

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                let isToday = DateFormatters.dateKey(from: date) == DateFormatters.todayKey()
                let isWeekend = { let wd = cal.component(.weekday, from: date); return wd == 1 || wd == 7 }()
                VStack(spacing: 2) {
                    Text(DateFormatters.dayOfWeek.string(from: date).prefix(dayWidth > 50 ? 3 : 1).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: dayWidth > 50 ? 17 : 12, weight: .bold))
                        .foregroundStyle(isToday ? Theme.blue : Theme.text)
                }
                .frame(width: dayWidth, height: height)
                .background(
                    isToday ? Theme.blue.opacity(0.09)
                    : isWeekend ? Color(hex: "#1a1d27").opacity(0.5)
                    : Color.clear
                )
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(width: 0.5)
                }
            }
        }
        .background(Theme.surfaceElevated.opacity(0.92))
    }
}

// MARK: - Timeline Row (draggable bar)

private struct PlanningTimelineRow: View {
    let task: AppTask
    let dates: [Date]
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    let barHeight: CGFloat
    let span: PlanningTimelineSpan?
    let dragDayOffset: Int
    let onDragChanged: (Int) -> Void
    let onDragEnded: (Int) -> Void

    @State private var hovered = false
    private let cal = Calendar.current
    private var totalWidth: CGFloat { CGFloat(dates.count) * dayWidth }

    var body: some View {
        ZStack(alignment: .leading) {
            // Canvas grid background
            Canvas { ctx, size in
                for (i, date) in dates.enumerated() {
                    let x = CGFloat(i) * dayWidth
                    let isToday = DateFormatters.dateKey(from: date) == DateFormatters.todayKey()
                    let isWeekend = { let wd = Calendar.current.component(.weekday, from: date); return wd == 1 || wd == 7 }()
                    // Alternating column fill
                    let bg: Color = isToday ? Color(hex: "#4a9eff").opacity(0.07)
                                            : isWeekend ? Color(hex: "#1a1d27").opacity(0.6)
                                            : Color.clear
                    if isToday || isWeekend {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)), with: .color(bg))
                    }
                    // Column separator
                    var line = Path()
                    line.move(to: CGPoint(x: x + dayWidth, y: 0))
                    line.addLine(to: CGPoint(x: x + dayWidth, y: size.height))
                    ctx.stroke(line, with: .color(Color(hex: "#252a3d").opacity(0.6)), lineWidth: 0.5)
                }
            }
            .frame(width: totalWidth, height: rowHeight)

            // The bar
            if let span {
                planningBar(adjustedSpan(span, offset: dragDayOffset))
            }
        }
        .frame(width: totalWidth, height: rowHeight)
        .contentShape(Rectangle())
    }

    private func adjustedSpan(_ span: PlanningTimelineSpan, offset: Int) -> PlanningTimelineSpan {
        span.shifted(by: offset, clampedTo: dates.count)
    }

    @ViewBuilder
    private func planningBar(_ span: PlanningTimelineSpan) -> some View {
        // Always at least 160px so labels are readable; grows with multi-day spans
        let spanDays = span.endIndex - span.startIndex + 1
        let naturalWidth = CGFloat(spanDays) * dayWidth - 10
        let barWidth = max(160, naturalWidth)
        let barX = CGFloat(span.startIndex) * dayWidth + 5
        let tint = barTint(span)
        let isWide = barWidth > 220

        ZStack {
            // Tinted background
            RoundedRectangle(cornerRadius: 9)
                .fill(tint.opacity(0.22))

            // Solid bar fill
            RoundedRectangle(cornerRadius: 9)
                .fill(tint.opacity(span.isBlocked ? 0.42 : 0.58))

            // Border
            RoundedRectangle(cornerRadius: 9)
                .stroke(tint.opacity(0.8), lineWidth: 1)

            // Label — icon + title always; subtitle only when there's room
            HStack(spacing: 6) {
                if span.isBlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                } else if !task.dependencyTaskIDs.isEmpty {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if isWide {
                    Spacer(minLength: 4)
                    Text(barSubtitle(span))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)

            // Drag handles on hover
            if hovered {
                HStack {
                    dragHandle
                    Spacer()
                    dragHandle
                }
                .padding(.horizontal, 5)
            }
        }
        .frame(width: barWidth, height: barHeight)
        .shadow(color: tint.opacity(dragDayOffset != 0 ? 0.45 : 0.15),
                radius: dragDayOffset != 0 ? 14 : 8, y: dragDayOffset != 0 ? 5 : 3)
        .scaleEffect(dragDayOffset != 0 ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: dragDayOffset != 0)
        .position(x: barX + barWidth / 2, y: rowHeight / 2)
        .onHover { hovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { val in
                    onDragChanged(Int(round(val.translation.width / dayWidth)))
                }
                .onEnded { val in
                    onDragEnded(Int(round(val.translation.width / dayWidth)))
                }
        )
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white.opacity(0.4))
            .frame(width: 3, height: 14)
    }

    private func barTint(_ span: PlanningTimelineSpan) -> Color {
        if span.isBlocked { return Theme.amber }
        if span.hasScheduledDate && span.hasDueDate { return Theme.blue }
        if span.hasScheduledDate { return Theme.green }
        return Theme.amber
    }

    private func barSubtitle(_ span: PlanningTimelineSpan) -> String {
        if span.hasScheduledDate && span.hasDueDate && task.scheduledDate != task.dueDate {
            return "Do → Due"
        }
        if span.hasScheduledDate {
            return task.scheduledStartMin >= 0
                ? TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)
                : "Scheduled"
        }
        return "Due"
    }
}

// MARK: - Dependency Arrow Overlay

private struct PlanningArrowOverlay: View {
    let connectors: [PlanningConnector]
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            for c in connectors {
                drawArrow(ctx: ctx, connector: c)
            }
        }
    }

    private func drawArrow(ctx: GraphicsContext, connector c: PlanningConnector) {
        let startX = CGFloat(c.fromSpan.endIndex + 1) * dayWidth - 6
        let startY = headerHeight + CGFloat(c.fromRow) * rowHeight + rowHeight / 2
        let endX   = CGFloat(c.toSpan.startIndex) * dayWidth + 6
        let endY   = headerHeight + CGFloat(c.toRow) * rowHeight + rowHeight / 2

        let start = CGPoint(x: startX, y: startY)
        let end   = CGPoint(x: endX, y: endY)
        let dx    = abs(endX - startX)
        let cp1   = CGPoint(x: startX + min(dx * 0.5, 44), y: startY)
        let cp2   = CGPoint(x: endX   - min(dx * 0.5, 44), y: endY)

        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: cp1, control2: cp2)

        let arrowColor = c.toSpan.isBlocked
            ? Color(hex: "#ffa94d").opacity(0.82)
            : Color(hex: "#4a9eff").opacity(0.72)

        ctx.stroke(path, with: .color(arrowColor),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

        // Arrowhead
        let dir = CGPoint(x: endX - cp2.x, y: endY - cp2.y)
        let len = sqrt(dir.x * dir.x + dir.y * dir.y)
        guard len > 0 else { return }
        let norm  = CGPoint(x: dir.x / len, y: dir.y / len)
        let angle: CGFloat = 26 * .pi / 180
        let aLen: CGFloat = 7
        let t1 = CGPoint(
            x: endX - aLen * (norm.x * cos(angle)  - norm.y * sin(angle)),
            y: endY - aLen * (norm.x * sin(angle)  + norm.y * cos(angle))
        )
        let t2 = CGPoint(
            x: endX - aLen * (norm.x * cos(-angle) - norm.y * sin(-angle)),
            y: endY - aLen * (norm.x * sin(-angle) + norm.y * cos(-angle))
        )
        var head = Path()
        head.move(to: t1)
        head.addLine(to: end)
        head.addLine(to: t2)
        ctx.stroke(head, with: .color(arrowColor),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Rail Views

private struct PlanningRailHeader: View {
    var body: some View {
        HStack {
            Text("TASK")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .background(Theme.surfaceElevated.opacity(0.92))
    }
}

private struct PlanningRailRow: View {
    let task: AppTask
    let dependentCount: Int

    private var statusText: String {
        if !task.scheduledDate.isEmpty && !task.dueDate.isEmpty {
            return "Do \(DateFormatters.relativeDate(from: task.scheduledDate)) · Due \(DateFormatters.relativeDate(from: task.dueDate))"
        }
        if !task.scheduledDate.isEmpty { return "Do \(DateFormatters.relativeDate(from: task.scheduledDate))" }
        if !task.dueDate.isEmpty       { return "Due \(DateFormatters.relativeDate(from: task.dueDate))" }
        return "No date"
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: task.containerColor))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if !task.dependencyTaskIDs.isEmpty {
                        PlanningMiniTag(title: "Depends \(task.dependencyTaskIDs.count)", tint: Theme.amber)
                    }
                    if dependentCount > 0 {
                        PlanningMiniTag(title: "Unlocks \(dependentCount)", tint: Theme.green)
                    } else if task.isRecurring {
                        PlanningMiniTag(title: task.recurrenceRule.shortLabel, tint: Theme.purple)
                    }
                }
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct PlanningRailEmpty: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No upcoming work")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Tasks with a do or due date will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PlanningEmptyGrid: View {
    let dates: [Date]
    let dayWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            for (i, date) in dates.enumerated() {
                let x = CGFloat(i) * dayWidth
                if DateFormatters.dateKey(from: date) == DateFormatters.todayKey() {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                             with: .color(Color(hex: "#4a9eff").opacity(0.05)))
                }
                var line = Path()
                line.move(to: CGPoint(x: x + dayWidth, y: 0))
                line.addLine(to: CGPoint(x: x + dayWidth, y: size.height))
                ctx.stroke(line, with: .color(Color(hex: "#252a3d").opacity(0.55)), lineWidth: 0.5)
            }
        }
        .overlay {
            Text("No dated tasks yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceElevated.opacity(0.9))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Shared Sub-views

private struct PlanningMiniTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct PlanningDependencyRowModel: Identifiable {
    let source: AppTask
    let blockers: [AppTask]
    let dependents: [AppTask]
    var id: UUID { source.id }
}
#endif
