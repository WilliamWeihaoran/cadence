#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TimelineBundleBlock: View {
    enum ResizeEdge {
        case start
        case end
    }

    let bundle: TaskBundle
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedBundleID: UUID?
    @Binding var activeDragBundleID: UUID?
    let onTaskDropped: (AppTask, TaskBundle) -> Void
    let onSelect: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(FocusManager.self) private var focusManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var activeResizeEdge: ResizeEdge? = nil
    @State private var resizeOriginStartMin: Int? = nil
    @State private var resizeOriginEndMin: Int? = nil
    @State private var isHovered = false
    @State private var isDropTargeted = false

    private var frame: TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: bundle.startMin,
            durationMinutes: bundle.durationMinutes,
            column: column,
            totalColumns: totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin)
    }

    var body: some View {
        bundleBlockBody
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    hoveredEditableManager.beginHovering(id: "timeline-bundle-\(bundle.id.uuidString)") {
                        onSelect()
                        activeDragBundleID = nil
                        selectedBundleID = bundle.id
                    } onDelete: {
                        deleteConfirmationManager.present(
                            title: "Delete Bundle?",
                            message: "This will delete \"\(bundle.displayTitle)\" and keep its tasks on the same day."
                        ) {
                            if selectedBundleID == bundle.id {
                                selectedBundleID = nil
                            }
                            if activeDragBundleID == bundle.id {
                                activeDragBundleID = nil
                            }
                            SchedulingActions.deleteBundle(bundle, in: modelContext)
                        }
                    }
                } else {
                    hoveredEditableManager.endHovering(id: "timeline-bundle-\(bundle.id.uuidString)")
                }
            }
            .onTapGesture {
                onSelect()
                activeDragBundleID = nil
                selectedBundleID = bundle.id
            }
            .suppressWindowBackgroundDrag()
            .onDrag {
                selectedBundleID = nil
                activeDragBundleID = bundle.id
                return NSItemProvider(object: TaskDragPayload.bundleString(for: bundle.id) as NSString)
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(
                of: [UTType.text.identifier],
                delegate: TimelineBundleDropDelegate(
                    bundle: bundle,
                    allTasks: allTasks,
                    onTaskDropped: onTaskDropped,
                    isTargeted: $isDropTargeted
                )
            )
            .overlay(alignment: .top) {
                resizeHandle(edge: .start)
            }
            .overlay(alignment: .bottom) {
                resizeHandle(edge: .end)
            }
            .popover(
                isPresented: Binding(
                    get: { selectedBundleID == bundle.id },
                    set: { if !$0 && selectedBundleID == bundle.id { selectedBundleID = nil } }
                )
            ) {
                TaskBundleDetailPopover(
                    bundle: bundle,
                    allTasks: allTasks,
                    areas: areas,
                    projects: projects,
                    onFocus: {
                        focusManager.startFocus(bundle: bundle)
                        selectedBundleID = nil
                    },
                    onAddTask: { task in
                        SchedulingActions.addTask(task, to: bundle)
                    },
                    onRemoveTask: { task in
                        SchedulingActions.removeTaskFromBundle(task)
                    },
                    onMoveTask: { task, direction in
                        SchedulingActions.moveTaskInBundle(task, direction: direction)
                    },
                    onComplete: {
                        if focusManager.activeBundle?.id == bundle.id {
                            focusManager.reset()
                            focusManager.activeSession = nil
                        }
                        SchedulingActions.completeBundle(bundle, in: modelContext)
                        selectedBundleID = nil
                    },
                    onUnbundle: {
                        SchedulingActions.unbundle(bundle, in: modelContext)
                        selectedBundleID = nil
                    },
                    onDelete: {
                        SchedulingActions.deleteBundle(bundle, in: modelContext)
                        selectedBundleID = nil
                    }
                )
            }
            .position(x: frame.centerX, y: frame.centerY)
    }

    private var bundleBlockBody: some View {
        let memberCount = bundle.sortedTasks.count
        return HStack(alignment: .top, spacing: 0) {
            Theme.amber
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: style.cornerRadius,
                    bottomLeadingRadius: style.cornerRadius
                ))

            VStack(alignment: .leading, spacing: 3) {
                if frame.height >= 54 {
                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text(bundle.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(frame.height >= 42 ? 2 : 1)
                }

                if frame.height >= 42 {
                    Text("\(memberCount) task\(memberCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)

            Spacer(minLength: 0)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.amber.opacity(0.16))
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.amber.opacity(0.16))
                }
                if isHovered {
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .fill(TimelineHoverVisuals.hoverFill(tint: Theme.amber, isHovered: isHovered, opacity: 0.08))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(
                    selectedBundleID == bundle.id || isDropTargeted
                        ? Theme.amber.opacity(0.62)
                        : TimelineHoverVisuals.borderColor(
                            tint: Theme.amber,
                            isSelected: false,
                            isHovered: isHovered,
                            selectedOpacity: 0.62,
                            hoverOpacity: 0.34
                        ),
                    lineWidth: isHovered || isDropTargeted ? 1.2 : 1
                )
        )
        .shadow(
            color: TimelineHoverVisuals.shadowColor(isActive: isHovered || selectedBundleID == bundle.id),
            radius: TimelineHoverVisuals.shadowRadius(isActive: isHovered || selectedBundleID == bundle.id),
            y: TimelineHoverVisuals.shadowY(isActive: isHovered || selectedBundleID == bundle.id)
        )
    }

    private func resizeHandle(edge: ResizeEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: TimelineTaskBlockInteractionSupport.resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay {
                let emphasized = activeResizeEdge == edge || isHovered || selectedBundleID == bundle.id
                Capsule()
                    .fill(.white.opacity(emphasized ? 0.38 : 0.14))
                    .frame(width: min(18, max(10, frame.width - 18)), height: 2)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        beginResizeIfNeeded(edge: edge)
                        updateResize(edge: edge, localY: value.location.y)
                    }
                    .onEnded { value in
                        updateResize(edge: edge, localY: value.location.y)
                        activeResizeEdge = nil
                        resizeOriginStartMin = nil
                        resizeOriginEndMin = nil
                    }
            )
    }

    private func beginResizeIfNeeded(edge: ResizeEdge) {
        guard activeResizeEdge == nil else { return }
        onSelect()
        selectedBundleID = nil
        activeDragBundleID = nil
        activeResizeEdge = edge
        resizeOriginStartMin = bundle.startMin
        resizeOriginEndMin = bundle.endMin
    }

    private func updateResize(edge: ResizeEdge, localY: CGFloat) {
        guard let originStart = resizeOriginStartMin,
              let originEnd = resizeOriginEndMin else { return }
        let localYOffset: CGFloat
        switch edge {
        case .start:
            localYOffset = localY
        case .end:
            localYOffset = max(0, frame.height - TimelineTaskBlockInteractionSupport.resizeHandleHeight) + localY
        }
        let snappedMinute = metrics.snappedMinute(fromY: frame.y + localYOffset)
        switch edge {
        case .start:
            let nextStart = min(snappedMinute, originEnd - 5)
            SchedulingActions.updateBundleTime(bundle, startMin: nextStart, endMin: originEnd)
        case .end:
            let nextEnd = max(snappedMinute, originStart + 5)
            SchedulingActions.updateBundleTime(bundle, startMin: originStart, endMin: nextEnd)
        }
    }
}

private struct TimelineBundleDropDelegate: DropDelegate {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let onTaskDropped: (AppTask, TaskBundle) -> Void
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.text]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString,
                  let taskID = TaskDragPayload.taskID(from: payload as String) else { return }
            Task { @MainActor in
                guard let task = allTasks.first(where: { $0.id == taskID }) else { return }
                guard task.bundle?.id != bundle.id else {
                    SchedulingActions.addTask(task, to: bundle)
                    return
                }
                onTaskDropped(task, bundle)
            }
        }
        return true
    }
}

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
        .padding(18)
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
                BundleInspectorMetricPill(
                    title: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                    systemImage: "clock",
                    tint: Theme.amber,
                    isProminent: true
                )
                BundleInspectorMetricPill(
                    title: blockLengthLabel,
                    systemImage: "calendar.badge.clock",
                    tint: Theme.dim
                )
                if bundle.totalEstimatedMinutes > 0 {
                    BundleInspectorMetricPill(
                        title: estimatedLengthLabel,
                        systemImage: "checklist",
                        tint: Theme.dim
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

private struct BundleInspectorMetricPill: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isProminent = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: isProminent ? .bold : .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background((isProminent ? tint : Theme.surfaceElevated).opacity(isProminent ? 0.12 : 0.58))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(tint.opacity(isProminent ? 0.20 : 0.10), lineWidth: 1)
        }
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.15), lineWidth: 1)
        }
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
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.38), lineWidth: 1)
        }
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
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Theme.surfaceElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.28), lineWidth: 1)
        }
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
