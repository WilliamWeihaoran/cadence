#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TimelineTaskBlock: View {
    let task: AppTask
    let allTasks: [AppTask]
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager
    @Binding var selectedTaskID: UUID?
    @Binding var activeDragTaskID: UUID?
    let onCreateBundleWithTask: (AppTask, AppTask) -> Void
    let onSelect: () -> Void

    @State private var resizeSession: TimelineResizeSession? = nil
    @State private var isHovered = false
    @State private var isBundleDropTargeted = false

    private var timeRangeLabel: String {
        TimelineTaskBlockInteractionSupport.timeRangeLabel(for: task)
    }

    private var frame: TimelineBlockFrame {
        TimelineTaskBlockInteractionSupport.frame(
            task: task,
            column: column,
            totalColumns: totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var isPendingCompletion: Bool {
        taskCompletionAnimationManager.isPending(task)
    }

    @ViewBuilder
    private var coreBlock: some View {
        if isPendingCompletion {
            TimelineView(.animation) { context in
                blockContent(now: context.date)
            }
        } else {
            blockContent(now: nil)
        }
    }

    private func blockContent(now: Date?) -> some View {
        timelineBlockBody(
            task: task,
            durationMinutes: task.timelineDurationMinutes,
            timeRangeLabel: timeRangeLabel,
            frame: frame,
            style: style,
            showSelection: selectedTaskID == task.id,
            showHover: isHovered,
            isPendingCompletion: isPendingCompletion,
            completionProgress: now.map { taskCompletionAnimationManager.progress(for: task, now: $0) } ?? 0,
            onToggleDone: { taskCompletionAnimationManager.toggleCompletion(for: task) }
        )
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
    }

    var body: some View {
        coreBlock
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                TimelineTaskBlockInteractionSupport.beginHover(
                    task: task,
                    selectedTaskID: $selectedTaskID,
                    activeDragTaskID: $activeDragTaskID,
                    hoveredTaskManager: hoveredTaskManager,
                    hoveredEditableManager: hoveredEditableManager,
                    deleteConfirmationManager: deleteConfirmationManager,
                    modelContext: modelContext,
                    onSelect: onSelect
                )
            } else {
                TimelineTaskBlockInteractionSupport.endHover(
                    task: task,
                    hoveredTaskManager: hoveredTaskManager,
                    hoveredEditableManager: hoveredEditableManager
                )
            }
        }
        .onTapGesture {
            handleBlockTap()
        }
        .overlay {
            RightClickActionTrigger {
                activeDragTaskID = nil
                selectedTaskID = task.id
                onSelect()
            }
        }
        .onDrag {
            guard resizeSession == nil else {
                return NSItemProvider()
            }
            selectedTaskID = nil
            activeDragTaskID = task.id
            return NSItemProvider(object: TaskDragPayload.string(for: task.id) as NSString)
        } preview: {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .overlay(alignment: .top) {
            resizeHandle(edge: .start)
        }
        .overlay(alignment: .bottom) {
            resizeHandle(edge: .end)
        }
        .overlay(alignment: .top) {
            bundleDropShelf
        }
        .popover(
            isPresented: TimelineTaskBlockStateSupport.selectionBinding(
                taskID: task.id,
                selectedTaskID: $selectedTaskID
            )
        ) {
            TaskDetailPopover(task: task)
        }
        .position(x: frame.centerX, y: frame.centerY)
    }

    @ViewBuilder
    private var bundleDropShelf: some View {
        if activeDragTaskID != nil && activeDragTaskID != task.id {
            TimelineTaskBundleDropShelf(
                targetTask: task,
                allTasks: allTasks,
                height: TimelineMetricsSupport.bundleDropShelfHeight(blockHeight: frame.height),
                activeDragTaskID: $activeDragTaskID,
                isTargeted: $isBundleDropTargeted,
                onCreateBundle: onCreateBundleWithTask
            )
        }
    }

    @ViewBuilder
    private func resizeHandle(edge: TimelineResizeEdge) -> some View {
        let handleHeight = TimelineBlockGeometry.resizeHandleHeight(blockHeight: frame.height)
        if handleHeight > 0 {
            Rectangle()
                .fill(Color.clear)
                .frame(height: handleHeight)
                .contentShape(Rectangle())
                .overlay {
                    let isEmphasized = resizeSession?.edge == edge || isHovered || selectedTaskID == task.id
                    Capsule()
                        .fill(isEmphasized ? Theme.onColorHandleActive : Theme.onColorHandle)
                        .frame(width: TimelineBlockGeometry.handleCapsuleWidth(blockWidth: frame.width), height: 2)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            // Mouse-down alone is not a resize. The strip outranks the tap gesture
                            // under it, so arming on the first `onChanged` meant every press here
                            // cleared `selectedTaskID` — the very binding the inspector popover is
                            // presented from — before the pointer had moved at all.
                            guard TimelineBlockGeometry.isResizeDrag(translation: value.translation) else { return }
                            beginResizeIfNeeded(edge: edge, localY: value.startLocation.y)
                            updateResize(localY: value.location.y)
                        }
                        .onEnded { value in
                            guard resizeSession != nil else {
                                // Never became a drag: hand the press back to the block as the
                                // click it was, so the strips are transparent to clicks instead of
                                // swallowing them.
                                handleBlockTap()
                                return
                            }
                            updateResize(localY: value.location.y)
                            endResize()
                        }
                )
        }
    }

    private func handleBlockTap() {
        TimelineTaskBlockStateSupport.handleTap(
            taskID: task.id,
            selectedTaskID: $selectedTaskID,
            activeDragTaskID: $activeDragTaskID,
            onSelect: onSelect
        )
    }

    private func beginResizeIfNeeded(edge: TimelineResizeEdge, localY: CGFloat) {
        TimelineTaskBlockInteractionSupport.beginResize(
            task: task,
            selectedTaskID: $selectedTaskID,
            activeDragTaskID: $activeDragTaskID,
            resizeSession: &resizeSession,
            edge: edge,
            localY: localY,
            frame: frame,
            metrics: metrics,
            onSelect: onSelect
        )
    }

    private func updateResize(localY: CGFloat) {
        TimelineTaskBlockInteractionSupport.updateResize(
            task: task,
            session: resizeSession,
            localY: localY,
            frame: frame,
            metrics: metrics
        )
    }

    private func endResize() {
        TimelineTaskBlockStateSupport.endResize(resizeSession: &resizeSession)
    }
}

private struct TimelineTaskBundleDropShelf: View {
    let targetTask: AppTask
    let allTasks: [AppTask]
    let height: CGFloat
    @Binding var activeDragTaskID: UUID?
    @Binding var isTargeted: Bool
    let onCreateBundle: (AppTask, AppTask) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 10, weight: .semibold))
            Text("Drop here to bundle")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.amber.opacity(isTargeted ? 0.28 : 0.18))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.amber.opacity(isTargeted ? 0.72 : 0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .padding(TimelineMetricsSupport.bundleDropShelfPadding)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text.identifier],
            delegate: TimelineTaskBundleDropDelegate(
                targetTask: targetTask,
                allTasks: allTasks,
                onCreateBundle: onCreateBundle,
                activeDragTaskID: $activeDragTaskID,
                isTargeted: $isTargeted
            )
        )
    }
}

private struct TimelineTaskBundleDropDelegate: DropDelegate {
    let targetTask: AppTask
    let allTasks: [AppTask]
    let onCreateBundle: (AppTask, AppTask) -> Void
    @Binding var activeDragTaskID: UUID?
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
        activeDragTaskID = nil
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString,
                  let taskID = TaskDragPayload.taskID(from: payload as String) else { return }
            Task { @MainActor in
                guard targetTask.id != taskID,
                      let draggedTask = allTasks.first(where: { $0.id == taskID }) else { return }
                onCreateBundle(targetTask, draggedTask)
            }
        }
        return true
    }
}
#endif
