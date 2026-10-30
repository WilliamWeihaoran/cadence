#if os(macOS)
import SwiftUI
import SwiftData

struct TimelineTaskBlock: View {
    let task: AppTask
    var todayKey: String = DateFormatters.todayKey()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTaskID: UUID?
    @Binding var activeDragTaskID: UUID?
    let onSelect: () -> Void

    @State private var resizeSession: TimelineResizeSession? = nil
    /// The task as the current resize drag found it — the undo `commitResize` restores when the
    /// store refuses the new length ([[T-4970]]).
    @State private var resizeOrigin: CadenceTaskFieldSnapshot? = nil
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

    /// Either deferral is running, so the circle has a fill to animate ([[T-8393]]). Gating on the
    /// completion alone left a cancellation started on the row frozen on the block.
    private var hasPendingFill: Bool {
        isPendingCompletion || taskCompletionAnimationManager.isPendingCancel(task)
    }

    /// The display-link redraw's one gate ([[T-8412]]): a deferral is running and Reduce Motion is
    /// off. Under Reduce Motion the block draws the pending state still, as the task row, the
    /// Kanban card and every iOS surface do: the body is handed no running fill, so its circle
    /// stamps the manager's pending glyph (`circle.inset.filled` green, or the grey cross) and no
    /// sweep is laid. The undo window is unchanged; only the motion goes.
    private var animatesPendingFill: Bool {
        !reduceMotion && hasPendingFill
    }

    @ViewBuilder
    private var coreBlock: some View {
        if animatesPendingFill {
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
            todayKey: todayKey,
            durationMinutes: task.timelineDurationMinutes,
            timeRangeLabel: timeRangeLabel,
            frame: frame,
            style: style,
            showSelection: selectedTaskID == task.id,
            showHover: isHovered,
            // [[T-8412]]: these two say whether the body draws a running fill and sweep, so they are
            // false under Reduce Motion even mid-deferral; the glyph below still names the pending
            // state, which is what the still circle draws.
            isPendingCompletion: animatesPendingFill && isPendingCompletion,
            // [[T-8393]]: the same pending states, fill, glyph and three-tap walk the task row and
            // the Kanban card ask the manager for, so the block cannot disagree with them.
            isPendingCancellation: animatesPendingFill && taskCompletionAnimationManager.isPendingCancel(task),
            completionProgress: now.flatMap { taskCompletionAnimationManager.pendingProgress(for: task, now: $0) } ?? 0,
            completionGlyph: taskCompletionAnimationManager.glyph(for: task),
            onToggleDone: { taskCompletionAnimationManager.advanceCompletionControl(for: task) }
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
        // [[T-8721]]: iOS's `iOSTimelineTaskBlock` shape ([[T-7072]]) -- one element named by the
        // shared `timedTaskLabel`, a button whose default action is the click's own
        // `handleBlockTap()`, and "Open task" listed as the Mac's other task surfaces list it
        // ([[T-7092]]). `.combine` folds the nested completion button into this element as its
        // own named action (it is labelled in `timelineBlockBody`), so it stays reachable.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            CadenceCalendarDayAccessibility.timedTaskLabel(
                title: TaskTitleSupport.displayTitle(task.title),
                timeRange: timeRangeLabel,
                isDone: task.isDone
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { handleBlockTap() }
        .accessibilityAction(named: CadenceTaskControlAccessibility.openTaskActionName, handleBlockTap)
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
        // [[T-3170]]: no "drop here to bundle" shelf any more. The block has no drop target of its
        // own, so a task released over it falls through to the canvas's `TimelineDropDelegate`
        // and is rescheduled to the minute under the pointer, exactly as a release over empty
        // canvas is.
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
    private func resizeHandle(edge: TimelineResizeEdge) -> some View {
        let handleHeight = TimelineBlockGeometry.resizeHandleHeight(blockHeight: frame.height)
        if handleHeight > 0 {
            Rectangle()
                .fill(Color.clear)
                .frame(height: handleHeight)
                .contentShape(Rectangle())
                .overlay {
                    let isEmphasized = resizeSession?.edge == edge || isHovered || selectedTaskID == task.id
                    // **The emphasized handle had to be re-solved for the plate (T-3160).**
                    // `Theme.onColorHandleActive` is white at 0.42, and it was chosen against the
                    // near-black `Theme.surfaceElevated` this block used to sit on, where it read
                    // 3.61:1 at worst and cleared the 3:1 bar a non-text affordance owes. Over a
                    // fill solved to Y = 0.124–0.150 the same alpha lands at **2.17:1** — a resize
                    // grip the user cannot find is a lost affordance, not a lost decoration. The
                    // plate's own incidental-glyph tier is the thing that is already solved
                    // against this fill: it is 3.69:1 at worst across the twelve list colours,
                    // measured in `CadenceTimelineTaskPlateTests`. The idle handle keeps
                    // `Theme.onColorHandle`; it is deliberately almost invisible until the pointer
                    // is on the block, and it was that before (1.66:1) as much as it is now
                    // (1.35:1).
                    Capsule()
                        .fill(isEmphasized ? CadenceCalendarEventStyle.plateTertiaryLabelColor(isActive: true) : Theme.onColorHandle)
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
        if resizeSession == nil {
            resizeOrigin = CadenceTaskFieldSnapshot(task)
        }
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
        if let resizeOrigin {
            TimelineTaskBlockInteractionSupport.commitResize(task, restoring: resizeOrigin, in: modelContext)
        }
        resizeOrigin = nil
        TimelineTaskBlockStateSupport.endResize(resizeSession: &resizeSession)
    }
}
#endif
