import SwiftUI

struct FilterPill: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? color : Theme.dim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? color.opacity(0.2) : Theme.dim.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .foregroundStyle(isSelected ? color : Theme.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? color.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                isSelected ? color.opacity(0.3) : Theme.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.cadencePlain)
    }
}
