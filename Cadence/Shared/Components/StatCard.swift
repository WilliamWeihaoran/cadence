import SwiftUI

struct StatCard: View {
    let label: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color.opacity(0.85))

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .tracking(0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cadenceCard(background: color.opacity(0.08), cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }
}
