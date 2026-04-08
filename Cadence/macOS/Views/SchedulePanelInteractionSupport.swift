#if os(macOS)
import SwiftUI

enum SchedulePanelInteractionSupport {
    static func persistRememberedHour(
        yOffset: CGFloat,
        geoHeight: CGFloat,
        zoomLevel: Int,
        didRestoreScroll: Bool,
        isRestoringScroll: Bool,
        persist: (Int) -> Void
    ) {
        guard didRestoreScroll, !isRestoringScroll else { return }
        persist(
            SchedulePanelStateSupport.clampedRememberedHour(
                offsetY: yOffset,
                geoHeight: geoHeight,
                zoomLevel: zoomLevel
            )
        )
    }

    static func focusTimeline(
        proxy: ScrollViewProxy,
        clearAppEditingFocus: () -> Void,
        setHighlighted: @escaping (Bool) -> Void
    ) {
        clearAppEditingFocus()
        let targetHour = SchedulePanelStateSupport.focusTargetHour()
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(targetHour, anchor: .top)
        }
        SchedulePanelStateSupport.highlightFocus { setHighlighted($0) }
    }
}
#endif
