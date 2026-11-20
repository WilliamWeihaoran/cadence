#if os(macOS)
import SwiftUI

struct TaskGroupFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [AppTask]?
    @Binding var frozenGroups: [FrozenTaskGroupSnapshot]?
    let naturalTasks: [AppTask]
    let groupSnapshot: [FrozenTaskGroupSnapshot]
    @State private var isPointerInsideSurface = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    var freezeState = TaskSurfaceFreezeState<FrozenTaskGroupSnapshot, Never>(
                        frozenOrder: frozenOrder,
                        primarySnapshot: frozenGroups,
                        secondarySnapshot: nil
                    )
                    // See `TaskSurfaceFreezeCoordinator.capture`: writing an unchanged value back
                    // into a `@State` binding still invalidates the host surface, and this runs
                    // every time the hovered row changes.
                    guard freezeState.captureIfNeeded(
                        naturalTasks: naturalTasks,
                        sourcePrimarySnapshot: groupSnapshot,
                        sourceSecondarySnapshot: []
                    ) else { return }
                    frozenOrder = freezeState.frozenOrder
                    frozenGroups = freezeState.primarySnapshot
                } else if !isPointerInsideSurface {
                    releaseFreeze()
                }
            }
            .onHover { inside in
                isPointerInsideSurface = inside
                // [[T-18629]]: also asked on the way out of the surface -- see `HoverFreezeObserver`.
                // A pointer that reached the surface's own gap first raised its only hovered-id
                // change while still inside, and nothing asked again.
                if !inside, hoveredTaskManager.hoveredTask == nil { releaseFreeze() }
            }
    }

    private func releaseFreeze() {
        guard frozenOrder != nil || frozenGroups != nil else { return }
        withAnimation(TaskSurfaceFreezeSupport.releaseAnimation) {
            var freezeState = TaskSurfaceFreezeState<FrozenTaskGroupSnapshot, Never>(
                frozenOrder: frozenOrder,
                primarySnapshot: frozenGroups,
                secondarySnapshot: nil
            )
            freezeState.release()
            frozenOrder = freezeState.frozenOrder
            frozenGroups = freezeState.primarySnapshot
        }
    }
}
#endif
