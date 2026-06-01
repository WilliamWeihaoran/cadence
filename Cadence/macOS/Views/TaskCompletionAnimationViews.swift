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
                    .opacity(clampedProgress > 0.7 ? 1 : 0)
                    .scaleEffect(clampedProgress > 0.7 ? 1 : 0.65)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: clampedProgress > 0.7)
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
            let progressWidth = max(12, width * CGFloat(clampedProgress))
            let glowWidth = min(86, max(34, width * 0.18))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint.opacity(0.075))

                Capsule()
                    .fill(tint.opacity(0.18))
                    .frame(width: glowWidth, height: proxy.size.height * 1.35)
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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .allowsHitTesting(false)
    }
}
#endif
