import SwiftUI

nonisolated enum CadenceEmptyStateMetrics {
    static func iconSide(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        CadenceTypeScale.height(72, holding: .bodyText, textBase: 26, at: size, scaling: scaling)
    }
}

struct EmptyStateView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let message: String
    var subtitle: String = ""
    let icon: String

    var body: some View {
        let side = CadenceEmptyStateMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.dim.opacity(0.07))
                    .frame(width: side, height: side)
                Circle()
                    .strokeBorder(Theme.dim.opacity(0.12), lineWidth: 1)
                    .frame(width: side, height: side)
                Image(systemName: icon)
                    .cadenceFont(.bodyText, base: 26, weight: .regular)
                    .foregroundStyle(Theme.dim.opacity(0.6))
            }

            VStack(spacing: 5) {
                Text(message)
                    .cadenceFont(.bodyText, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: scaling == .enabled)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .cadenceFont(.fieldLabel, weight: .regular)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: scaling == .enabled)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}
