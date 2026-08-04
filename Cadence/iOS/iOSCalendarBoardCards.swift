#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

enum iOSCalendarBoardColumnItem: Identifiable {
    case event(iOSCalendarBoardEventItem)
    case bundle(TaskBundle)
    case task(AppTask)

    var id: String {
        switch self {
        case .event(let item):
            return "event-\(item.id)"
        case .bundle(let bundle):
            return "bundle-\(bundle.id.uuidString)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        }
    }

    var sortKey: CalendarBoardSortKey {
        switch self {
        case .event(let item):
            return item.sortKey
        case .bundle(let bundle):
            return CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1)
        case .task(let task):
            return CalendarBoardPlannerSupport.sortKey(for: task, kindRank: 2)
        }
    }
}

struct iOSCalendarBoardEventItem: Identifiable {
    let id: String
    let title: String
    let calendarTitle: String
    let startMin: Int
    let endMin: Int
    let isAllDay: Bool
    let isRecurring: Bool
    let color: Color

    var sortKey: CalendarBoardSortKey {
        CalendarBoardPlannerSupport.sortKeyForCalendarEvent(
            id: id,
            startMinute: startMin,
            isAllDay: isAllDay,
            kindRank: 0
        )
    }

    static func items(from events: [EKEvent], for date: Date, calendar: Calendar = .current) -> [iOSCalendarBoardEventItem] {
        events.compactMap { event in
            iOSCalendarBoardEventItem(event: event, date: date, calendar: calendar)
        }
    }

    private init?(event: EKEvent, date: Date, calendar: Calendar) {
        let dateKey = DateFormatters.dateKey(from: date)
        let rawIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let eventIdentifier = rawIdentifier.isEmpty ? "\(dateKey)-\(event.hash)" : rawIdentifier
        title = iOSCalendarEventSupport.title(for: event)
        calendarTitle = event.calendar?.title ?? "Apple Calendar"
        isAllDay = event.isAllDay
        isRecurring = event.hasRecurrenceRules
        color = iOSCalendarEventSupport.color(for: event.calendar)

        if event.isAllDay {
            startMin = CalendarBoardPlannerSupport.allDaySortMinute
            endMin = 24 * 60
        } else {
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let eventStart = event.startDate ?? dayStart
            let fallbackEnd = eventStart.addingTimeInterval(30 * 60)
            let eventEnd = max(event.endDate ?? fallbackEnd, fallbackEnd)
            let segmentStart = max(eventStart, dayStart)
            let segmentEnd = min(eventEnd, dayEnd)
            guard segmentEnd > segmentStart else { return nil }
            let startComponents = calendar.dateComponents([.hour, .minute], from: segmentStart)
            let rawStart = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
            let duration = max(5, Int(segmentEnd.timeIntervalSince(segmentStart) / 60))
            startMin = min(max(0, rawStart), 24 * 60 - 5)
            endMin = min(24 * 60, max(startMin + 5, startMin + duration))
        }

        id = "\(eventIdentifier)-\(dateKey)-\(startMin)"
    }
}

struct iOSCalendarBoardEventCard: View {
    let item: iOSCalendarBoardEventItem

    private var subtitle: String {
        if item.isAllDay {
            return "All day"
        }
        return TimeFormatters.timeRange(startMin: item.startMin, endMin: item.endMin)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isAllDay ? "calendar" : "clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    iOSCalendarBoardMetadataChip(
                        item: .init(
                            id: "time",
                            icon: item.isAllDay ? "sun.max" : "clock",
                            title: subtitle,
                            color: item.color
                        )
                    )
                    if item.isRecurring {
                        iOSCalendarBoardMetadataChip(
                            item: .init(id: "repeat", icon: "repeat", title: "Repeats", color: item.color)
                        )
                    }
                }

                if !item.calendarTitle.isEmpty {
                    Text(item.calendarTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.85))
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(item.color.opacity(0.10))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 10, x: 0, y: 4)
    }
}

struct iOSCalendarBoardTaskCard: View {
    @Bindable var task: AppTask
    let dateKey: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showDetail = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.priorityColor(task.priority))
                .frame(width: 3.5)
                .padding(.leading, 10)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Button(action: toggleCompletion) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: isRegularWidth ? 17 : 15, weight: .semibold))
                            .foregroundStyle(task.isDone ? Theme.green : Theme.dim.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: isRegularWidth ? 14 : 13, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(metadataChips, id: \.id) { chip in
                        iOSCalendarBoardMetadataChip(item: chip)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
        }
        .background(Theme.surfaceElevated.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .onTapGesture {
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private var metadataChips: [iOSCalendarBoardMetadataItem] {
        var chips: [iOSCalendarBoardMetadataItem] = []

        if task.scheduledStartMin >= 0 {
            chips.append(
                .init(
                    id: "time",
                    icon: "clock.fill",
                    title: TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin),
                    color: Theme.blue
                )
            )
        }

        if !task.dueDate.isEmpty {
            chips.append(
                .init(
                    id: "due",
                    icon: "flag.fill",
                    title: CadenceTaskPresentationSupport.dueDateLabel(for: task),
                    color: task.dueDate < DateFormatters.todayKey() && !task.isDone ? Theme.red : Theme.dim
                )
            )
        }

        chips.append(
            .init(
                id: "list",
                icon: task.project?.icon ?? task.area?.icon ?? "tray.fill",
                title: task.containerName.isEmpty ? "Inbox" : task.containerName,
                color: Color(hex: task.containerColor)
            )
        )

        return chips
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
    }
}

struct iOSCalendarBoardBundleCard: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let onDropTask: (AppTask) -> Void
    var onDropTargetedChanged: (Bool) -> Void = { _ in }

    @State private var isTargeted = false
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(bundle.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        iOSCalendarBoardMetadataChip(
                            item: .init(
                                id: "time",
                                icon: "clock",
                                title: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                                color: Theme.amber
                            )
                        )
                        iOSCalendarBoardMetadataChip(
                            item: .init(
                                id: "tasks",
                                icon: "checklist",
                                title: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                                color: Theme.dim
                            )
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.82))
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.amber.opacity(isTargeted ? 0.20 : 0.09))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.amber.opacity(0.74), lineWidth: 1.5)
            }
        }
        .shadow(color: Theme.cardElevationShadow, radius: 10, x: 0, y: 4)
        .onTapGesture {
            showDetail = true
        }
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Edit Block", systemImage: "square.and.pencil")
            }
        }
        .sheet(isPresented: $showDetail) {
            iOSCalendarBundleDetailSheet(bundle: bundle)
        }
        .draggable(TaskDragPayload.bundleString(for: bundle.id))
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let taskID = TaskDragPayload.taskID(from: payload),
                  let task = allTasks.first(where: { $0.id == taskID }) else { return false }
            onDropTask(task)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
            onDropTargetedChanged(targeted)
        }
    }
}

private struct iOSCalendarBoardMetadataItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let color: Color
}

private struct iOSCalendarBoardMetadataChip: View {
    let item: iOSCalendarBoardMetadataItem

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(item.color)
                .frame(width: 10)
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}
#endif
