#if os(macOS)
import SwiftUI

struct SchedulePanelHeader: View {
    var presentation: SchedulePanelPresentation = .standard
    @Binding var zoomLevel: Int
    let onExport: () -> Void

    var body: some View {
        switch presentation {
        case .standard:
            standardHeader
        case .compact:
            compactHeader
        }
    }

    private var standardHeader: some View {
        HStack(spacing: 0) {
            PanelHeader(eyebrow: "Schedule", title: "Timeline")
            Spacer()
            exportButton
                .padding(.trailing, 8)
            TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)
                .padding(.trailing, 12)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                Text("Timeline")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer(minLength: 8)
            exportButton
            TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var exportButton: some View {
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
        .help("Export schedule")
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
                showHalfHourMarks: zoomLevel == 3,
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
