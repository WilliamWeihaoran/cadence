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

struct TaskCompletionPendingOverlay: View {
    let progress: Double
    let tint: Color
    var cornerRadius: CGFloat = 8

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let progressWidth = max(12, width * CGFloat(clampedProgress))
            let glowWidth = min(86, max(34, width * 0.18))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint.opacity(0.075))

                Capsule()
                    .fill(tint.opacity(0.18))
                    .frame(width: glowWidth, height: height * 1.35)
                    .blur(radius: 16)
                    .offset(x: (width + glowWidth) * CGFloat(clampedProgress) - glowWidth)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(tint.opacity(0.62))
                        .frame(width: progressWidth, height: 2.5)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint.opacity(0.12), lineWidth: 1)
            }
            // The sweeping glow capsule is deliberately TALLER than the host view
            // (height * 1.35) and blurred, so the ZStack's own layout size grows past
            // the geometry proposal. `.clipShape` clips to the view's own bounds, so
            // clipping the raw ZStack clips to that oversized box — and since
            // GeometryReader never clips its content, the green sweep painted outside
            // the host block. Pin back to the proposed size FIRST, then clip, so the
            // fill/border sit exactly on the block's rounded rect and nothing can
            // escape it in any direction.
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}
#endif
