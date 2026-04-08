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
                    freezeState.captureIfNeeded(
                        naturalTasks: naturalTasks,
                        sourcePrimarySnapshot: groupSnapshot,
                        sourceSecondarySnapshot: []
                    )
                    frozenOrder = freezeState.frozenOrder
                    frozenGroups = freezeState.primarySnapshot
                } else if !isPointerInsideSurface, frozenOrder != nil || frozenGroups != nil {
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
            .onHover { isPointerInsideSurface = $0 }
    }
}
#endif
