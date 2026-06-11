#if os(macOS)
import SwiftData
import SwiftUI

struct CalendarBoardBundleCard: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let onDropTask: (AppTask) -> Void
    var onDropTargetedChanged: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(FocusManager.self) private var focusManager
    @State private var showPopover = false
    @State private var isHovered = false
    @State private var isTargeted = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            label
        }
        .buttonStyle(.cadencePlain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
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
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            bundleDetailPopover
        }
    }

    private var label: some View {
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

                metadata
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isTargeted ? Theme.amber.opacity(0.74) : Theme.amber.opacity(isHovered ? 0.48 : 0.22),
                    lineWidth: isTargeted ? 1.25 : 1
                )
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            CalendarBoardMetadataChip(
                title: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                systemImage: "clock",
                tint: Theme.amber
            )
            CalendarBoardMetadataChip(
                title: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                systemImage: "checklist",
                tint: Theme.dim
            )
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(0.86))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.amber.opacity(isTargeted ? 0.18 : (isHovered ? 0.12 : 0.07)))
        }
    }

    private var bundleDetailPopover: some View {
        TaskBundleDetailPopover(
            bundle: bundle,
            allTasks: allTasks,
            areas: areas,
            projects: projects,
            onFocus: {
                focusManager.startFocus(bundle: bundle)
                showPopover = false
            },
            onAddTask: { task in
                SchedulingActions.addTask(task, to: bundle)
                try? modelContext.save()
            },
            onRemoveTask: { task in
                SchedulingActions.removeTaskFromBundle(task)
                try? modelContext.save()
            },
            onMoveTask: { task, direction in
                SchedulingActions.moveTaskInBundle(task, direction: direction)
                try? modelContext.save()
            },
            onComplete: {
                if focusManager.activeBundle?.id == bundle.id {
                    focusManager.reset()
                    focusManager.activeSession = nil
                }
                SchedulingActions.completeBundle(bundle, in: modelContext)
                showPopover = false
            },
            onUnbundle: {
                SchedulingActions.unbundle(bundle, in: modelContext)
                showPopover = false
            },
            onDelete: {
                SchedulingActions.deleteBundle(bundle, in: modelContext)
                showPopover = false
            }
        )
    }
}

struct CalendarBoardEventCard: View {
    let item: CalendarBoardEventDisplayItem

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var showPopover = false
    @State private var isHovered = false

    private var tint: Color {
        item.calendarColor
    }

    var body: some View {
        Button {
            showPopover = true
        } label: {
            label
        }
        .buttonStyle(.cadencePlain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            let editItem = item.editItem
            CalendarEventEditPopover(
                item: editItem,
                onSave: { title, startMin, duration, calendarID, scope in
                    if let range = editItem.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: duration) {
                        calendarManager.updateEvent(
                            item.ekEvent,
                            title: title,
                            startDate: range.start,
                            endDate: range.end,
                            calendarID: calendarID,
                            scope: scope
                        )
                    }
                    showPopover = false
                },
                onDelete: { scope in
                    deleteConfirmationManager.present(
                        title: "Delete Calendar Event?",
                        message: scope == .futureOccurrences
                            ? "This will permanently delete \"\(item.title)\" and future events from your calendar."
                            : "This will permanently delete \"\(item.title)\" from your calendar."
                    ) {
                        calendarManager.deleteEvent(item.ekEvent, scope: scope)
                        showPopover = false
                    }
                }
            )
        }
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isAllDay ? "calendar" : "clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    CalendarBoardMetadataChip(title: subtitle, systemImage: item.isAllDay ? "sun.max" : "clock", tint: tint)
                    if item.isRecurringSeriesMember {
                        CalendarBoardMetadataChip(title: "Repeats", systemImage: "repeat", tint: tint)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    tint.opacity(CalendarEventVisualStyle.borderOpacity(isSelected: showPopover, isHovered: isHovered)),
                    lineWidth: isHovered || showPopover ? 1.25 : 1
                )
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(CalendarEventVisualStyle.surfaceOpacity(isActive: isHovered || showPopover)))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(CalendarEventVisualStyle.tintOpacity(isSelected: showPopover, isHovered: isHovered)))
        }
    }

    private var subtitle: String {
        if item.isAllDay { return "All day" }
        return TimeFormatters.timeRange(startMin: item.startMin, endMin: item.startMin + max(item.durationMinutes, 5))
    }
}

struct CalendarBoardMetadataChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(tint.opacity(CalendarEventVisualStyle.chipTintOpacity()))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#endif
