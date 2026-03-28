#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Shared scheduling mutations

enum SchedulingActions {
    /// Create and insert a new task scheduled to a specific date/time slot.
    static func createTask(title: String, dateKey: String, startMin: Int, endMin: Int, in context: ModelContext) {
        let task = AppTask(title: title)
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        task.estimatedMinutes = max(5, endMin - startMin)
        context.insert(task)
    }

    /// Move an existing task to a new date/time. Assigns a 60-min default if the task has no estimate.
    static func dropTask(_ task: AppTask, to dateKey: String, startMin: Int) {
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        if task.estimatedMinutes <= 0 { task.estimatedMinutes = 60 }
    }
}

// MARK: - Shared zoom control view

struct TimelineZoomControl: View {
    @Binding var zoomLevel: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            Button { if zoomLevel > range.lowerBound { zoomLevel -= 1 } } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(zoomLevel > range.lowerBound ? Theme.dim : Theme.dim.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            Text("\(zoomLevel)×")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 22)
            Button { if zoomLevel < range.upperBound { zoomLevel += 1 } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(zoomLevel < range.upperBound ? Theme.dim : Theme.dim.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
