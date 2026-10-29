import SwiftUI

/// **How a finished task looks on the calendar, once, for both platforms** ([[T-8241]]).
///
/// macOS drew a done task with diagonal stripes over the timed block and a green check on the
/// all-day and month chips; iOS struck the timed block's title through and left its chips' check
/// grey. Nothing about touch versus pointer explains that, so under [[T-8201]] it is drift, and the
/// fix is one decision both read rather than a second copy nudged closer by hand.
///
/// The open state is the caller's: the chips draw different open glyphs on purpose (macOS's hollow
/// `circle`, iOS's month dot and its dashed "no time yet" circle), and macOS tints an open glyph by
/// due urgency. Only the two settled states are decided here.
enum CadenceCalendarTaskDoneStyle {
    /// The chip's completion glyph: settled states replace the caller's open symbol.
    static func chipGlyphSymbol(for state: CadenceTaskCompletionState, open: String) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .todo, .pendingCompletion, .pendingCancellation: return open
        }
    }

    /// The chip glyph's tint for a settled state, or `nil` to keep the caller's open tint.
    ///
    /// Done is `Theme.green`, which reads on a plate solved to `plateLuminance`. Cancelled is the
    /// plate's own tertiary tier: `Theme.dim` is a grey solved against `Theme.bg` and has no
    /// contrast budget on a saturated plate.
    static func chipGlyphTint(for state: CadenceTaskCompletionState) -> Color? {
        switch state {
        case .done: return Theme.green
        case .cancelled: return CadenceCalendarEventStyle.plateTertiaryLabelColor()
        case .todo, .pendingCompletion, .pendingCancellation: return nil
        }
    }

    /// A done task's title drops one ink tier rather than going grey; a cancelled one does not,
    /// which is macOS's long-standing rule (`task.isDone`).
    static func dimsTitle(for state: CadenceTaskCompletionState) -> Bool {
        state == .done
    }
}

/// The diagonal stripes painted over a done task's timed block, on both platforms.
///
/// 3pt `Theme.onColorBorder` lines at 10pt spacing. It used to be a `private` view inside macOS's
/// `TimelineTaskBlockSupportViews.swift`; it moved here so iOS draws the same stripes instead of a
/// strikethrough ([[T-8241]]). The contrast it costs the done title is measured in
/// `CadenceTimelineTaskPlateTests`.
struct DiagonalStripeOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 10
            let lineWidth: CGFloat = 3
            let totalLines = Int((size.width + size.height) / spacing) + 2
            for i in 0..<totalLines {
                let offset = CGFloat(i) * spacing
                var path = Path()
                path.move(to: CGPoint(x: offset - size.height, y: 0))
                path.addLine(to: CGPoint(x: offset, y: size.height))
                context.stroke(path, with: .color(Theme.onColorBorder), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}
