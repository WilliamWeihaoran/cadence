#if os(macOS)
import SwiftUI

struct TaskCompletionProgressGlyph: View {
    let icon: String
    let color: Color
    var progress: Double?
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2

    private var clampedProgress: Double {
        min(max(progress ?? 0, 0), 1)
    }

    /// **The confirmation mark lands at the halfway point, not at 70% ([[T-8202]]).**
    ///
    /// This threshold is what the owner was actually complaining about when the window felt long:
    /// at 0.7 of a 2.5s fill the ring ran for 1.75s saying nothing, so the control looked like it
    /// was waiting rather than like it had understood the tap. The number is
    /// `CadenceTaskCompletionTiming`'s rather than this view's because the window it is a fraction
    /// of is, and the two have to be retuned together.
    private var showsConfirmation: Bool {
        CadenceTaskCompletionTiming.showsConfirmation(at: clampedProgress)
    }

    var body: some View {
        ZStack {
            if progress == nil {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: completionSymbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(color)
                    .opacity(showsConfirmation ? 1 : 0)
                    .scaleEffect(showsConfirmation ? 1 : 0.65)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: showsConfirmation)
            }
        }
        .frame(width: size, height: size)
    }

    private var completionSymbol: String {
        icon.contains("xmark") ? "xmark" : "checkmark"
    }
}

// `TaskCompletionPendingOverlay`, the row-wide sweep, lives in
// `Shared/Components/TaskCompletionPendingOverlay.swift` since [[T-8354]] so iOS draws the same one.
#endif
