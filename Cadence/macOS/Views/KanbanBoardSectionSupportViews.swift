#if os(macOS)
import SwiftUI

struct TaskListBoardSectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    let taskCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("\(taskCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceElevated.opacity(0.95))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface.opacity(0.78))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.borderSubtle.opacity(0.8))
        }
    }
}
#endif
