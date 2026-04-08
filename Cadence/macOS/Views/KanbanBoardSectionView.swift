#if os(macOS)
import SwiftUI

struct TaskListBoardSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let taskCount: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TaskListBoardSectionHeader(
                title: title,
                icon: icon,
                color: color,
                taskCount: taskCount
            )

            content()
        }
    }
}
#endif
