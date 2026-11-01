import SwiftUI

/// The chip a day's all-day strip draws for a draft that is still being composed ([[T-8851]]).
///
/// **It is the draft ghost's clothes on the strip's shape.** The hour ladder's ghost — macOS's
/// `TimelineDraftGhostLayer`, iOS's `iOSTimelineDraftBlock` — says "not committed yet" with a blue
/// wash and a blue rim, and this says the same thing with the same two channels so that a draft
/// that moves from the ladder to the strip, which is exactly what toggling All day does, is
/// recognisably the same object in a different lane. The rim is **dashed** on top of that, the
/// vocabulary `iOSCalendarMiniChip.isUnscheduled` already uses on this strip for "no time yet".
///
/// One view for both platforms: the strips differ in their chip metrics, which the caller sets
/// through `fontSize`, and in nothing else.
struct CadenceAllDayDraftChip: View {
    /// What the chip says — `CadenceCalendarAllDayDraftSession.chipTitle`, so the blank-draft word
    /// is decided in one place rather than by whichever strip drew it.
    let title: String
    /// The strip's own title size. macOS's all-day chips draw at 10; the iOS band's mini chip
    /// draws at 10 too and grows with the reader's text size through `cadenceFont`.
    var fontSize: CGFloat = 10

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        Text(title)
            .cadenceFont(.metadata, base: fontSize, weight: .medium)
            .foregroundStyle(Theme.blue)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.blue.opacity(0.18)))
            .overlay(
                shape.strokeBorder(
                    Theme.blue.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
            )
            // Nothing to open and nothing to drag: the thing this stands for does not exist yet,
            // and the editor that will create it is already on screen, anchored to the range the
            // user pressed. Letting the touch through keeps the strip underneath reachable.
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(CadenceAllDayDraftChip.accessibilityLabel(title: title))
    }

    /// Said rather than shown: on screen the blue dashed rim is what marks this as a draft, and a
    /// rim is not something VoiceOver reads.
    static func accessibilityLabel(title: String) -> String {
        "\(title), new all-day item, not saved yet"
    }
}
