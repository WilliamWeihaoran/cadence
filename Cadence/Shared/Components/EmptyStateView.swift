import SwiftUI

struct EmptyStateView: View {
    let message: String
    var subtitle: String = ""
    let icon: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.dim.opacity(0.07))
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(Theme.dim.opacity(0.12), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.dim.opacity(0.6))
            }

            VStack(spacing: 5) {
                Text(message)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}
