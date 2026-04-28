#if os(macOS)
import SwiftUI

struct SchedulePanelHeader: View {
    @Binding var zoomLevel: Int
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PanelHeader(eyebrow: "Schedule", title: "Timeline")
            Spacer()
            Button {
                onExport()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
            .padding(.trailing, 8)
            TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)
                .padding(.trailing, 12)
        }
    }
}

struct SchedulePanelTimelineViewport: View {
    let geoSize: CGSize
    let zoomLevel: Int
    let allTasks: [AppTask]
    let scheduledTasks: [AppTask]
    let todayKey: String
    let externalEventItems: [CalendarEventItem]
    let onCreateTask: (String, Int, Int, TaskContainerSelection, String) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onCreateEvent: (String, Int, Int, String, String) -> Void

    var body: some View {
        let targetHours: CGFloat = zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4
        let hourHeight = geoSize.height / targetHours
        let metrics = TimelineMetrics(
            startHour: schedStartHour,
            endHour: schedEndHour,
            hourHeight: hourHeight
        )
        let totalWidth = max(240, geoSize.width - 8)
        let canvasWidth = max(0, totalWidth - blockInset)

        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(schedStartHour..<schedEndHour, id: \.self) { hour in
                    ScheduleTimeRailRow(hour: hour, hourHeight: hourHeight)
                        .id(hour)
                }
            }
            .frame(width: blockInset)

            TimelineDayCanvas(
                date: Date(),
                dateKey: todayKey,
                tasks: scheduledTasks,
                allTasks: allTasks,
                metrics: metrics,
                width: canvasWidth,
                style: .schedule,
                showCurrentTimeDot: true,
                dropBehavior: .perHour,
                onCreateTask: onCreateTask,
                onDropTaskAtMinute: onDropTaskAtMinute,
                externalEvents: externalEventItems,
                onCreateEvent: onCreateEvent
            )
        }
        .frame(width: totalWidth, alignment: .leading)
        .padding(.trailing, 8)
    }
}
#endif
