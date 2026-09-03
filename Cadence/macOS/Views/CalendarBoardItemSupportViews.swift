#if os(macOS)
import SwiftData
import SwiftUI

struct CalendarBoardBundleCard: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let onDropTask: (AppTask) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(FocusManager.self) private var focusManager
    @State private var showPopover = false
    @State private var isHovered = false
    @State private var isTargeted = false
    @State private var bundleActionFailureNotice: String?

    var body: some View {
        Button {
            bundleActionFailureNotice = nil
            showPopover = true
        } label: {
            label
        }
        .buttonStyle(.cadencePlain)
        .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
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
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? Theme.amber.opacity(0.74) : Theme.amber.opacity(isHovered ? 0.48 : 0.22),
                    lineWidth: isTargeted ? 1.25 : 1
                )
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            CadenceBoardMetadataChip(
                title: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                systemImage: "clock",
                tint: Theme.amber,
                cardCornerRadius: kanbanCardCornerRadius
            )
            CadenceBoardMetadataChip(
                title: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                systemImage: "checklist",
                tint: Theme.dim,
                cardCornerRadius: kanbanCardCornerRadius
            )
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(0.86))
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(Theme.amber.opacity(isTargeted ? 0.18 : (isHovered ? 0.12 : 0.07)))
        }
    }

    /// Runs one of the block's three end actions and **closes only if it committed** (T-628).
    ///
    /// The popover closing is the whole of the success report here — there is no other signal that
    /// Complete or Delete did anything — so a refused commit has to leave it open and say so.
    /// `deleteBundle`'s `commitDelete` rolls back, which is what makes both sentences true.
    private func endBlock(_ notice: String, _ attempt: () throws -> Void) {
        do {
            try attempt()
            bundleActionFailureNotice = nil
            showPopover = false
        } catch {
            bundleActionFailureNotice = notice
        }
    }

    private var bundleDetailPopover: some View {
        TaskBundleDetailPopover(
            bundle: bundle,
            allTasks: allTasks,
            areas: areas,
            projects: projects,
            onFocus: {
                focusManager.startFocus(bundle: bundle, in: modelContext)
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
                endBlock(CadencePendingChangePersistence.editFailureNotice) {
                    try SchedulingActions.completeBundle(bundle, in: modelContext)
                }
            },
            onUnbundle: {
                endBlock(CadencePendingChangePersistence.editFailureNotice) {
                    try SchedulingActions.unbundle(bundle, in: modelContext)
                }
            },
            onDelete: {
                endBlock(CadenceTaskMutationSupport.bundleDeleteFailureNotice) {
                    try SchedulingActions.deleteBundle(bundle, in: modelContext)
                }
            },
            actionFailureNotice: $bundleActionFailureNotice
        )
    }
}

struct CalendarBoardEventCard: View {
    let item: CalendarBoardEventDisplayItem

    @Environment(CalendarManager.self) private var calendarManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var showPopover = false
    @State private var isHovered = false
    @State private var actionFailureNotice: String?

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
        .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            let editItem = item.editItem
            CalendarEventEditPopover(
                item: editItem,
                onSave: { title, startMin, duration, calendarID, scope in
                    // Both refusals used to close the popover: the unformable range silently, and
                    // the rejected write behind a global alert with nothing to retype into. The
                    // range branch has no cause to name — EventKit was never asked — so it passes
                    // `nil`, the way `iOSCalendarQuickCreateSheet` does for an unparseable date key.
                    guard let range = editItem.eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: duration) else {
                        calendarManager.report(
                            .refused(notice: CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)),
                            into: $actionFailureNotice
                        )
                        return
                    }
                    let failure = calendarManager.updateEvent(
                        item.ekEvent,
                        title: title,
                        startDate: range.start,
                        endDate: range.end,
                        calendarID: calendarID,
                        scope: scope
                    )
                    calendarManager.report(
                        CadenceCalendarEventEditingSupport.saveOutcome(for: failure),
                        into: $actionFailureNotice
                    ) { showPopover = false }
                },
                onDelete: { scope in
                    deleteConfirmationManager.present(
                        title: "Delete Calendar Event?",
                        message: scope == .futureOccurrences
                            ? "This will permanently delete \"\(item.title)\" and future events from your calendar."
                            : "This will permanently delete \"\(item.title)\" from your calendar."
                    ) {
                        // Delete deliberately stays on `.calendarWriteFailureAlert()`. The
                        // confirmation overlay is a full-window layer, so pressing its Delete
                        // button is a click outside this transient popover and closes it before
                        // the store has answered — an inline notice would have nowhere to draw.
                        // There is also no draft to keep here: nothing was typed.
                        calendarManager.deleteEvent(item.ekEvent, scope: scope)
                        showPopover = false
                    }
                },
                actionFailureNotice: $actionFailureNotice
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
                    CadenceBoardMetadataChip(
                        title: subtitle,
                        systemImage: item.isAllDay ? "sun.max" : "clock",
                        tint: tint,
                        cardCornerRadius: kanbanCardCornerRadius
                    )
                    if item.isRecurringSeriesMember {
                        CadenceBoardMetadataChip(
                            title: "Repeats",
                            systemImage: "repeat",
                            tint: tint,
                            cardCornerRadius: kanbanCardCornerRadius
                        )
                    }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .strokeBorder(
                    tint.opacity(CalendarEventVisualStyle.borderOpacity(isSelected: showPopover, isHovered: isHovered)),
                    lineWidth: isHovered || showPopover ? 1.25 : 1
                )
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(CalendarEventVisualStyle.surfaceOpacity(isActive: isHovered || showPopover)))
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(tint.opacity(CalendarEventVisualStyle.tintOpacity(isSelected: showPopover, isHovered: isHovered)))
        }
    }

    private var subtitle: String {
        if item.isAllDay { return "All day" }
        return TimeFormatters.timeRange(startMin: item.startMin, endMin: item.startMin + max(item.durationMinutes, 5))
    }
}

// The event/bundle chip is `CadenceBoardMetadataChip` in
// `Shared/Components/CadenceBoardMetadataChip.swift`. `CalendarBoardMetadataChip` was declared
// here beside a `private iOSCalendarBoardMetadataChip` in `Cadence/iOS/iOSBoardCards.swift` that
// said "Matches macOS's `CalendarBoardMetadataChip`" and had no way to keep matching it.

#endif
