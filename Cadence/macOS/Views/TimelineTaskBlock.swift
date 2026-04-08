#if os(macOS)
import SwiftUI
import SwiftData

struct TimelineTaskBlock: View {
    enum ResizeEdge {
        case start
        case end
    }

    let task: AppTask
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
    let onSelect: () -> Void

    @State private var activeResizeEdge: ResizeEdge? = nil
    @State private var resizeOriginStartMin: Int? = nil
    @State private var resizeOriginEndMin: Int? = nil
    @State private var isHovered = false

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

    var body: some View {
        TimelineView(.animation) { context in
            timelineBlockBody(
                task: task,
                durationMinutes: task.estimatedMinutes,
                timeRangeLabel: timeRangeLabel,
                frame: frame,
                style: style,
                showSelection: selectedTaskID == task.id,
                showHover: isHovered,
                isPendingCompletion: isPendingCompletion,
                completionProgress: taskCompletionAnimationManager.progress(for: task, now: context.date),
                onToggleDone: { taskCompletionAnimationManager.toggleCompletion(for: task) }
            )
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
        }
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
            TimelineTaskBlockStateSupport.handleTap(
                taskID: task.id,
                selectedTaskID: $selectedTaskID,
                activeDragTaskID: $activeDragTaskID,
                onSelect: onSelect
            )
        }
        .onDrag {
            guard activeResizeEdge == nil else {
                return NSItemProvider()
            }
            selectedTaskID = nil
            activeDragTaskID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
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
    private func resizeHandle(edge: ResizeEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: TimelineTaskBlockInteractionSupport.resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay {
                let isEmphasized = activeResizeEdge == edge || isHovered || selectedTaskID == task.id
                Capsule()
                    .fill(.white.opacity(isEmphasized ? 0.4 : 0.16))
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
                        endResize()
                    }
            )
    }

    private func beginResizeIfNeeded(edge: ResizeEdge) {
        TimelineTaskBlockInteractionSupport.beginResize(
            task: task,
            selectedTaskID: $selectedTaskID,
            activeDragTaskID: $activeDragTaskID,
            activeResizeEdge: &activeResizeEdge,
            resizeOriginStartMin: &resizeOriginStartMin,
            resizeOriginEndMin: &resizeOriginEndMin,
            edge: edge,
            onSelect: onSelect
        )
    }

    private func updateResize(edge: ResizeEdge, localY: CGFloat) {
        TimelineTaskBlockInteractionSupport.updateResize(
            task: task,
            edge: edge,
            localY: localY,
            frame: frame,
            metrics: metrics,
            resizeHandleHeight: TimelineTaskBlockInteractionSupport.resizeHandleHeight,
            resizeOriginStartMin: resizeOriginStartMin,
            resizeOriginEndMin: resizeOriginEndMin
        )
    }

    private func endResize() {
        TimelineTaskBlockStateSupport.endResize(
            activeResizeEdge: &activeResizeEdge,
            resizeOriginStartMin: &resizeOriginStartMin,
            resizeOriginEndMin: &resizeOriginEndMin
        )
    }
}
#endif
