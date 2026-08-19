import SwiftUI

/// The figures behind `CadenceSidebarCountLabel`, in a value type so a macOS-built test can pin
/// them without drawing anything.
///
/// There was one figure here and there were two copies of it: `SidebarMetrics.countFontSize` at
/// 11 and `iOSSidebarMetrics.countFontSize` at 12, under two 24-line view structs that were
/// character-for-character identical once the names were normalised. 12 wins. The count is the
/// only number in the sidebar and it has to stay legible against a 13–14pt label without becoming
/// a second heading; 11 was small enough that a three-digit tally read as a smudge, and the point
/// it gave back bought nothing — the label truncates against `badgeLeadingGap` either way, so a
/// wider count costs no name.
nonisolated enum CadenceSidebarCountMetrics {
    static let fontSize: CGFloat = 12

    /// Counts above this clamp rather than widen. A four-digit tally in a 188–200pt column would
    /// eat the name it belongs to, and "how many over a thousand" is not a number anyone acts on.
    static let overflowThreshold: Int = 999

    static func displayText(for count: CadenceSidebarCount) -> String {
        count.value > overflowThreshold ? "\(overflowThreshold)+" : "\(count.value)"
    }
}

/// The trailing count on **every** sidebar row, on **both** platforms — nav rows and list rows,
/// macOS and iPad.
///
/// Bare digits, no capsule: a pill drew a border, a fill and a radius around a number that says
/// everything it has to say in `Theme.dim`. Which count is allowed to be red is not this view's
/// call — `CadenceSidebarLayout.count(for:counts:)` hands out the single urgent emphasis in the
/// column (Today's overdue tally), and this reads it.
///
/// Fixed-size on purpose: three digits must never be squeezed or clipped by a long label.
struct CadenceSidebarCountLabel: View {
    let count: CadenceSidebarCount

    private var tint: Color {
        switch count.emphasis {
        case .urgent: return Theme.red
        case .neutral: return Theme.dim
        }
    }

    var body: some View {
        Text(CadenceSidebarCountMetrics.displayText(for: count))
            .font(.system(size: CadenceSidebarCountMetrics.fontSize, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
