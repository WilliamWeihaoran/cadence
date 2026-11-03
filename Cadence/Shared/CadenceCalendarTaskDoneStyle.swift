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

    /// **The whole of a calendar task chip's glyph tint, settled state or open** ([[T-8243]]).
    ///
    /// The two settled tints are `chipGlyphTint(for:)` above. An OPEN task's circle is tinted by
    /// `CadenceDueUrgency`, which is how a chip says "overdue" or "due soon" at a glance — macOS's
    /// `MonthTaskChip` and `AllDayTaskChip` have done that since the urgency classifier existed,
    /// and `iOSCalendarMiniChip` drew every open glyph in one flat tertiary tier, so on iPhone and
    /// iPad the channel did not exist at all. Nothing about a finger explains a missing colour, so
    /// under [[T-8201]] that was drift; this is the one decision both platforms now read, which is
    /// what [[T-8243]] asked for rather than a second copy of the rule on the iOS side.
    ///
    /// `open` is the caller's own no-deadline tier, and it has to be the caller's: the Mac's month
    /// chip and the iOS mini chip are solved against different plates, so a shared literal here
    /// would land one of them on a fill it has no contrast budget against.
    ///
    /// A task with **no** due date is not urgency-free noise — `evaluate` answers `nil` and the
    /// glyph falls back to `open`, so only a real deadline ever colours the circle.
    static func chipGlyphTint(
        for state: CadenceTaskCompletionState,
        dueDateKey: String,
        todayKey: String = DateFormatters.todayKey(),
        open: Color
    ) -> Color {
        if let settled = chipGlyphTint(for: state) { return settled }
        // False by construction at this point — every settled state returned above — and passed
        // anyway so the two guards cannot disagree if the settled set ever grows a member that
        // keeps the caller's open tint. `evaluate` collapses a finished task to `.later`.
        return CadenceDueUrgency.evaluate(
            dueDateKey: dueDateKey,
            isDone: state.isSettled,
            todayKey: todayKey
        )?.tint ?? open
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
