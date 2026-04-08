#if os(macOS)
import SwiftUI

enum SchedulePanelStateSupport {
    static func clampedRememberedHour(offsetY: CGFloat, geoHeight: CGFloat, zoomLevel: Int) -> Int {
        let targetHours: CGFloat = zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4
        let hourHeight = geoHeight / targetHours
        let rawHour = schedStartHour + Int(offsetY / max(hourHeight, 1))
        return min(max(rawHour, schedStartHour), schedEndHour - 1)
    }

    static func restoreScrollHour(rememberedScrollHour: Int) -> Int {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let fallbackHour = max(schedStartHour, currentHour - 1)
        return rememberedScrollHour >= schedStartHour ? rememberedScrollHour : fallbackHour
    }

    static func focusTargetHour() -> Int {
        let currentHour = Calendar.current.component(.hour, from: Date())
        return max(schedStartHour, min(currentHour - 1, schedEndHour - 1))
    }

    static func highlightFocus(setHighlighted: @escaping (Bool) -> Void) {
        withAnimation(.easeOut(duration: 0.16)) {
            setHighlighted(true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.24)) {
                setHighlighted(false)
            }
        }
    }
}
#endif
