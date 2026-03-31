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
        // No calendar sync here — task has no area/project container yet when created from timeline drag
    }

    /// Move an existing task to a new date/time. Assigns a 60-min default if the task has no estimate.
    static func dropTask(_ task: AppTask, to dateKey: String, startMin: Int) {
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        if task.estimatedMinutes <= 0 { task.estimatedMinutes = 60 }
        syncToCalendarIfLinked(task)
    }

    /// Sync a scheduled task to Apple Calendar if its area/project has a linked calendar.
    static func syncToCalendarIfLinked(_ task: AppTask) {
        guard CalendarManager.shared.isAuthorized, task.scheduledStartMin >= 0 else { return }
        let calendarID = task.project?.linkedCalendarID ?? task.area?.linkedCalendarID ?? ""
        guard !calendarID.isEmpty else { return }
        CalendarManager.shared.createOrUpdateEvent(for: task, calendarID: calendarID)
    }

    /// Remove the Apple Calendar event associated with a task, then clear its stored event ID.
    static func removeFromCalendar(_ task: AppTask) {
        guard !task.calendarEventID.isEmpty else { return }
        CalendarManager.shared.deleteEvent(calendarEventID: task.calendarEventID)
        task.calendarEventID = ""
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
            .buttonStyle(.cadencePlain)
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
            .buttonStyle(.cadencePlain)
        }
    }
}
#endif
