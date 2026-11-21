#if os(macOS)
import SwiftUI

enum SchedulePanelInteractionSupport {
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
