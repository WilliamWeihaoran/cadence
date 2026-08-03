#if os(macOS)
import Foundation
import SwiftUI

enum PlanningWindow: String, CaseIterable, Identifiable {
    case week = "1W"
    case twoWeeks = "2W"
    case month = "M"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .week:
            return 7
        case .twoWeeks:
            return 14
        case .month:
            return 30
        }
    }

    var dayWidth: CGFloat {
        switch self {
        case .week:
            return 218
        case .twoWeeks:
            return 190
        case .month:
            return 162
        }
    }
}

struct PlanningWindowControl: View {
    @Binding var selection: PlanningWindow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PlanningWindow.allCases) { item in
                Button {
                    selection = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: selection == item ? .semibold : .medium))
                        .foregroundStyle(selection == item ? Theme.blue : Theme.dim)
                        .frame(minWidth: 34, minHeight: 26)
                        .contentShape(Rectangle())
                        .background(selection == item ? Theme.blue.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(4)
        .background(Theme.surfaceElevated.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
    }
}

struct PlanningMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surfaceElevated.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.borderSubtle.opacity(0.58), lineWidth: 1)
        }
    }
}

struct PlanningSectionHeader: View {
    let icon: String
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.surfaceElevated.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
    }
}

struct PlanningDayColumn: View {
    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let isTargeted: Bool
    let onClearSchedule: (AppTask) -> Void

    private var isToday: Bool {
        dateKey == DateFormatters.todayKey()
    }

    private var isWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateFormatters.dayOfWeek.string(from: date).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    Text(DateFormatters.shortDate.string(from: date))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isToday ? Theme.blue : Theme.text)
                }

                Spacer(minLength: 6)

                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    .frame(minWidth: 24, minHeight: 24)
                    .background((isToday ? Theme.blue : Theme.surfaceElevated).opacity(isToday ? 0.16 : 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 8) {
                if tasks.isEmpty {
                    PlanningEmptyColumn()
                } else {
                    ForEach(tasks) { task in
                        PlanningTaskCard(
                            task: task,
                            dateKey: dateKey,
                            onClearSchedule: onClearSchedule
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(minHeight: 250, alignment: .top)
        .background(columnBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(columnBorder, lineWidth: isTargeted || isToday ? 1.2 : 1)
        }
    }

    private var columnBackground: Color {
        if isTargeted { return Theme.blue.opacity(0.13) }
        if isToday { return Theme.blue.opacity(0.08) }
        if isWeekend { return Theme.surface.opacity(0.7) }
        return Theme.surface.opacity(0.9)
    }

    private var columnBorder: Color {
        if isTargeted { return Theme.blue.opacity(0.72) }
        if isToday { return Theme.blue.opacity(0.45) }
        return Theme.borderSubtle.opacity(0.8)
    }
}

struct PlanningBacklogPanel: View {
    let tasks: [AppTask]
    let isTargeted: Bool
    let onClearSchedule: (AppTask) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 10, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            if tasks.isEmpty {
                PlanningBacklogEmpty()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(tasks) { task in
                    PlanningTaskCard(
                        task: task,
                        dateKey: nil,
                        onClearSchedule: onClearSchedule
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTargeted ? Theme.amber.opacity(0.13) : Theme.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Theme.amber.opacity(0.72) : Theme.borderSubtle.opacity(0.8), lineWidth: isTargeted ? 1.2 : 1)
        }
    }
}

struct PlanningTaskCard: View {
    @Bindable var task: AppTask
    let dateKey: String?
    let onClearSchedule: (AppTask) -> Void

    @State private var isHovered = false
    @State private var showTaskInspector = false

    private var isDueOnlyCard: Bool {
        task.scheduledDate.isEmpty && dateKey != nil && task.dueDate == dateKey
    }

    private var tint: Color {
        if isDueOnlyCard { return Theme.red }
        return TaskHoverVisuals.accentColor(for: task)
    }

    var body: some View {
        Button {
            showTaskInspector = true
        } label: {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 4)

                        if isHovered && !task.scheduledDate.isEmpty {
                            Button {
                                onClearSchedule(task)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: 20, height: 20)
                                    .background(Theme.surfaceElevated.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.cadencePlain)
                            .help("Unschedule")
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach(metadataChips, id: \.title) { chip in
                            CommitmentMetaChip(label: chip.title, color: chip.tint, systemImage: chip.icon)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CompactTagStrip(tags: task.sortedTags, limit: 3)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated.opacity(0.72))
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.08))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isHovered ? tint.opacity(0.44) : Theme.borderSubtle.opacity(0.56), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
        .onHover { isHovered = $0 }
        .overlay {
            RightClickActionTrigger {
                showTaskInspector = true
            }
        }
        .draggable(TasksPanelSupport.taskDragPayload(for: task))
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
    }

    private var metadataChips: [PlanningChipModel] {
        var chips: [PlanningChipModel] = []

        if task.scheduledStartMin >= 0 {
            chips.append(
                PlanningChipModel(
                    title: TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin),
                    icon: "clock",
                    tint: Theme.blue
                )
            )
        } else if !task.scheduledDate.isEmpty {
            chips.append(
                PlanningChipModel(
                    title: DateFormatters.relativeDate(from: task.scheduledDate),
                    icon: "sun.max",
                    tint: Theme.blue
                )
            )
        }

        if !task.dueDate.isEmpty {
            chips.append(
                PlanningChipModel(
                    title: "Due \(DateFormatters.relativeDate(from: task.dueDate))",
                    icon: "flag",
                    tint: task.dueDate < DateFormatters.todayKey() ? Theme.red : Theme.red.opacity(0.86)
                )
            )
        }

        if task.estimatedMinutes > 0 {
            chips.append(
                PlanningChipModel(
                    title: planningDurationLabel(task.estimatedMinutes),
                    icon: "timer",
                    tint: Theme.amber
                )
            )
        }

        if task.isRecurring {
            chips.append(
                PlanningChipModel(
                    title: task.recurrenceRule.shortLabel,
                    icon: "repeat",
                    tint: Theme.purple
                )
            )
        }

        if !task.resolvedSectionName.isEmpty && task.resolvedSectionName != TaskSectionDefaults.defaultName {
            chips.append(
                PlanningChipModel(
                    title: task.resolvedSectionName,
                    icon: "rectangle.split.2x1",
                    tint: Theme.dim
                )
            )
        }

        return Array(chips.prefix(3))
    }
}

struct PlanningChipModel {
    let title: String
    let icon: String
    let tint: Color
}

struct PlanningEmptyColumn: View {
    var body: some View {
        Text("No work")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.dim.opacity(0.74))
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Theme.bg.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.borderSubtle.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
    }
}

struct PlanningBacklogEmpty: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.green)
            Text("No unscheduled work")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Spacer()
        }
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

func planningDurationLabel(_ minutes: Int) -> String {
    guard minutes > 0 else { return "-" }
    if minutes < 60 { return "\(minutes)m" }
    if minutes % 60 == 0 { return "\(minutes / 60)h" }
    return String(format: "%.1fh", Double(minutes) / 60.0)
}
#endif
