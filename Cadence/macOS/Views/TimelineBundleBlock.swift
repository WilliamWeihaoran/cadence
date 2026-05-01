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
    @Environment(FocusManager.self) private var focusManager
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
            .onHover { isHovered = $0 }
            .onTapGesture {
                onSelect()
                activeDragBundleID = nil
                selectedBundleID = bundle.id
            }
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
                    onFocus: {
                        focusManager.startFocus(bundle: bundle)
                        selectedBundleID = nil
                    },
                    onRemoveTask: { task in
                        SchedulingActions.removeTaskFromBundle(task)
                    },
                    onMoveTask: { task, direction in
                        SchedulingActions.moveTaskInBundle(task, direction: direction)
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
                    RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.blue.opacity(0.05))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(
                    selectedBundleID == bundle.id || isDropTargeted ? Theme.amber.opacity(0.62) : .white.opacity(isHovered ? 0.14 : 0.06),
                    lineWidth: isHovered || isDropTargeted ? 1.2 : 1
                )
        )
        .shadow(
            color: isHovered || selectedBundleID == bundle.id ? CalendarVisualStyle.selectedCardShadow : CalendarVisualStyle.cardShadow,
            radius: isHovered || selectedBundleID == bundle.id ? 11 : 7,
            y: isHovered || selectedBundleID == bundle.id ? 4 : 2
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

private struct TaskBundleDetailPopover: View {
    let bundle: TaskBundle
    let onFocus: () -> Void
    let onRemoveTask: (AppTask) -> Void
    let onMoveTask: (AppTask, Int) -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Bundle title", text: Binding(
                get: { bundle.title },
                set: { bundle.title = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .onSubmit {
                if bundle.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bundle.title = "Task Bundle"
                }
            }

            HStack(spacing: 7) {
                Text(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("/")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim.opacity(0.42))
                Text("\(bundle.durationMinutes)m block")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                if bundle.totalEstimatedMinutes > 0 {
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim.opacity(0.42))
                    Text("\(bundle.totalEstimatedMinutes)m tasks")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }

            Divider().background(Theme.borderSubtle)

            if bundle.sortedTasks.isEmpty {
                Text("Drop tasks here to fill this block.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            } else {
                VStack(alignment: .leading, spacing: 7) {
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

            HStack(spacing: 8) {
                if isConfirmingDelete {
                    CadenceActionButton(title: "Cancel", role: .ghost, size: .compact) {
                        isConfirmingDelete = false
                    }
                    CadenceActionButton(title: "Delete", role: .destructive, size: .compact, action: onDelete)
                } else {
                    CadenceActionButton(title: "Delete", role: .ghost, size: .compact) {
                        isConfirmingDelete = true
                    }
                }
                Spacer()
                CadenceActionButton(
                    title: "Focus",
                    systemImage: "play.fill",
                    role: .secondary,
                    size: .compact,
                    tint: Theme.amber,
                    isDisabled: bundle.sortedTasks.isEmpty,
                    action: onFocus
                )
            }
        }
        .padding(14)
        .frame(width: 306)
        .background(Theme.surface)
    }
}

private struct BundleTaskPopoverRow: View {
    let task: AppTask
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 12))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(max(task.estimatedMinutes, 5))m")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
            rowIconButton("chevron.up", isDisabled: !canMoveUp) { onMove(-1) }
            rowIconButton("chevron.down", isDisabled: !canMoveDown) { onMove(1) }
            rowIconButton("xmark", isDisabled: false, action: onRemove)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Theme.surfaceElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func rowIconButton(_ systemName: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isDisabled ? Theme.dim.opacity(0.35) : Theme.dim)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .disabled(isDisabled)
    }
}
#endif
