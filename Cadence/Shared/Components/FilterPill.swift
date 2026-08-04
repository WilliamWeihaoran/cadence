import SwiftUI

struct FilterPill: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? color : Theme.dim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isSelected ? color.opacity(0.24) : Theme.dim.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? color : Theme.dim)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .background(isSelected ? color.opacity(0.16) : Theme.surface)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
    }
}
