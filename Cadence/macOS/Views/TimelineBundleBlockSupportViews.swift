#if os(macOS)
import SwiftUI

struct TaskBundleDetailPopover: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let onFocus: () -> Void
    let onAddTask: (AppTask) -> Void
    let onRemoveTask: (AppTask) -> Void
    let onMoveTask: (AppTask, Int) -> Void
    let onComplete: () -> Void
    let onUnbundle: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false
    @State private var isConfirmingUnbundle = false
    @State private var isConfirmingComplete = false
    @State private var isAddingTasks = false
    @State private var taskSearch = ""

    private var taskCountLabel: String {
        "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")"
    }

    private var blockLengthLabel: String {
        "\(bundle.durationMinutes)m block"
    }

    private var estimatedLengthLabel: String {
        "\(bundle.totalEstimatedMinutes)m tasks"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            Divider().background(Theme.borderSubtle.opacity(0.85))

            taskSection

            confirmationSection
            actionDeck
        }
        .padding(20)
        .frame(width: 376)
        .background(
            ZStack {
                Theme.surface
                LinearGradient(
                    colors: [Theme.amber.opacity(0.045), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 14, x: 0, y: 6)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Bundle title", text: Binding(
                    get: { bundle.title },
                    set: { bundle.title = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .onSubmit {
                    if bundle.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        bundle.title = "Task Bundle"
                    }
                }

                Text(taskCountLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.amber.opacity(0.13))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                CommitmentMetaChip(
                    label: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                    color: Theme.amber,
                    systemImage: "clock",
                    prominent: true
                )
                CommitmentMetaChip(
                    label: blockLengthLabel,
                    color: Theme.dim,
                    systemImage: "calendar.badge.clock"
                )
                if bundle.totalEstimatedMinutes > 0 {
                    CommitmentMetaChip(
                        label: estimatedLengthLabel,
                        color: Theme.dim,
                        systemImage: "checklist"
                    )
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("\(bundle.activeTasks.count) active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                Button {
                    isAddingTasks.toggle()
                    taskSearch = ""
                } label: {
                    Label(isAddingTasks ? "Done" : "Add task", systemImage: isAddingTasks ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Theme.amber.opacity(isAddingTasks ? 0.16 : 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.cadencePlain)
                .foregroundStyle(Theme.amber)
            }

            if isAddingTasks {
                TaskBundleTaskPickerPanel(
                    bundleDateKey: bundle.dateKey,
                    allTasks: allTasks,
                    areas: areas,
                    projects: projects,
                    excludedTaskIDs: Set(bundle.sortedTasks.map(\.id)),
                    searchText: $taskSearch,
                    maxHeight: 214,
                    onAdd: onAddTask
                )
            }

            if bundle.sortedTasks.isEmpty {
                BundleInspectorEmptyTasksView(isAddingTasks: isAddingTasks)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(bundle.sortedTasks.enumerated()), id: \.element.id) { index, task in
                        BundleTaskPopoverRow(
                            task: task,
                            canMoveUp: index > 0,
                            canMoveDown: index < bundle.sortedTasks.count - 1,
                            onMove: { direction in onMoveTask(task, direction) },
                            onRemove: { onRemoveTask(task) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var confirmationSection: some View {
        if isConfirmingDelete {
            BundleInspectorConfirmationCard(
                message: "Delete this bundle block and keep its tasks on the same day.",
                tint: Theme.red
            )
        } else if isConfirmingComplete {
            BundleInspectorConfirmationCard(
                message: "Mark every active task in this bundle complete and remove the bundle block.",
                tint: Theme.green
            )
        } else if isConfirmingUnbundle {
            BundleInspectorConfirmationCard(
                message: "Remove the bundle block and preserve each task's list, schedule, and metadata.",
                tint: Theme.amber
            )
        }
    }

    private var actionDeck: some View {
        VStack(spacing: 9) {
            if isConfirmingDelete {
                confirmationButtons(
                    confirmTitle: "Delete Bundle",
                    confirmImage: "trash.fill",
                    role: .destructive,
                    tint: Theme.red,
                    confirmAction: onDelete,
                    cancelAction: { isConfirmingDelete = false }
                )
            } else if isConfirmingUnbundle {
                confirmationButtons(
                    confirmTitle: "Unbundle Tasks",
                    confirmImage: "rectangle.split.3x1",
                    role: .secondary,
                    tint: Theme.amber,
                    confirmAction: onUnbundle,
                    cancelAction: { isConfirmingUnbundle = false }
                )
            } else if isConfirmingComplete {
                confirmationButtons(
                    confirmTitle: "Complete Tasks",
                    confirmImage: "checkmark.circle.fill",
                    role: .secondary,
                    tint: Theme.green,
                    confirmAction: onComplete,
                    cancelAction: { isConfirmingComplete = false }
                )
            } else {
                HStack(spacing: 9) {
                    CadenceActionButton(
                        title: "Unbundle",
                        systemImage: "rectangle.split.3x1",
                        role: .secondary,
                        size: .compact,
                        tint: Theme.amber,
                        fullWidth: true
                    ) {
                        beginConfirmation(.unbundle)
                    }

                    CadenceActionButton(
                        title: "Delete",
                        systemImage: "trash",
                        role: .destructive,
                        size: .compact,
                        fullWidth: true
                    ) {
                        beginConfirmation(.delete)
                    }
                }

                HStack(spacing: 9) {
                    CadenceActionButton(
                        title: "Complete",
                        systemImage: "checkmark.circle.fill",
                        role: .secondary,
                        size: .compact,
                        tint: Theme.green,
                        fullWidth: true,
                        isDisabled: bundle.activeTasks.isEmpty
                    ) {
                        beginConfirmation(.complete)
                    }

                    CadenceActionButton(
                        title: "Start Focus",
                        systemImage: "play.fill",
                        role: .primary,
                        size: .compact,
                        tint: Theme.amber,
                        fullWidth: true,
                        isDisabled: bundle.activeTasks.isEmpty,
                        action: onFocus
                    )
                }
            }
        }
    }

    private func confirmationButtons(
        confirmTitle: String,
        confirmImage: String,
        role: CadenceActionButtonRole,
        tint: Color,
        confirmAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            CadenceActionButton(
                title: "Cancel",
                systemImage: "xmark",
                role: .ghost,
                size: .compact,
                fullWidth: true,
                action: cancelAction
            )
            CadenceActionButton(
                title: confirmTitle,
                systemImage: confirmImage,
                role: role,
                size: .compact,
                tint: tint,
                fullWidth: true,
                action: confirmAction
            )
        }
    }

    private enum PendingConfirmation {
        case complete
        case delete
        case unbundle
    }

    private func beginConfirmation(_ confirmation: PendingConfirmation) {
        isConfirmingComplete = confirmation == .complete
        isConfirmingDelete = confirmation == .delete
        isConfirmingUnbundle = confirmation == .unbundle
    }
}

private struct BundleInspectorConfirmationCard: View {
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: tint.opacity(0.09), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }
}

private struct BundleInspectorEmptyTasksView: View {
    let isAddingTasks: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.70))
            Text(isAddingTasks ? "Choose tasks above or drop tasks here." : "Drop tasks here or add them from this inspector.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.42), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }
}

private struct BundleTaskPopoverRow: View {
    let task: AppTask
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .lineLimit(1)
                    .strikethrough(task.isDone, color: Theme.dim.opacity(0.75))

                HStack(spacing: 6) {
                    Label("\(max(task.estimatedMinutes, 5))m", systemImage: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 4) {
                rowIconButton("chevron.up", label: "Move task up", isDisabled: !canMoveUp) { onMove(-1) }
                rowIconButton("chevron.down", label: "Move task down", isDisabled: !canMoveDown) { onMove(1) }
            }
            .padding(3)
            .background(Theme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            rowIconButton("xmark", label: "Remove task", isDisabled: false, tint: Theme.red, action: onRemove)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.62), cornerRadius: Theme.radiusCard, shadowRadius: 6, shadowY: 2)
    }

    private func rowIconButton(
        _ systemName: String,
        label: String,
        isDisabled: Bool,
        tint: Color = Theme.dim,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isDisabled ? Theme.dim.opacity(0.32) : tint)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
        .disabled(isDisabled)
        .help(label)
    }
}
#endif
