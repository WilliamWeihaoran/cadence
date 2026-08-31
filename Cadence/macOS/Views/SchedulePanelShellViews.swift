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
            // "Timeline", once. The `SCHEDULE` eyebrow over it named this column a second time
            // in a second word — and in `RootTimelineSidebarPane`, which titles itself
            // "Today Timeline", a third. `Timeline` is the word the rest of the app already uses:
            // the zoom control, the close button's label, and iPad's pane switcher. (T-602)
            PanelHeader(title: "Timeline")
            Spacer()
            exportButton
                .padding(.trailing, 8)
            TimelineZoomControl(zoomLevel: $zoomLevel, range: TimelineZoom.levels)
                .padding(.trailing, 12)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                SectionEyebrowLabel(text: "Today")
                Text("Timeline")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer(minLength: 8)
            exportButton
            TimelineZoomControl(zoomLevel: $zoomLevel, range: TimelineZoom.levels)
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
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let scheduledTasks: [AppTask]
    let bundles: [TaskBundle]
    let todayKey: String
    let externalEventItems: [CalendarEventItem]
    let onCreateTask: (String, Int, Int, TaskContainerSelection, String, String, [String]) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onCreateBundle: (String, Int, Int, [AppTask]) -> Void
    let onDropBundleAtMinute: (TaskBundle, Int) -> Void
    let onDropTaskOnBundle: (AppTask, TaskBundle) -> Void
    let onCreateEvent: (String, Int, Int, String, String) -> Void

    var body: some View {
        let hourHeight = TimelineZoom.hourHeight(viewportHeight: geoSize.height, level: zoomLevel)
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
                bundles: bundles,
                allTasks: allTasks,
                allBundles: allBundles,
                areas: areas,
                projects: projects,
                metrics: metrics,
                width: canvasWidth,
                style: .schedule,
                showCurrentTimeDot: true,
                showHalfHourMarks: zoomLevel == 3,
                showWorkHoursHighlight: true,
                onCreateTask: onCreateTask,
                onCreateBundle: onCreateBundle,
                onDropTaskAtMinute: onDropTaskAtMinute,
                onDropBundleAtMinute: onDropBundleAtMinute,
                onDropTaskOnBundle: onDropTaskOnBundle,
                externalEvents: externalEventItems,
                onCreateEvent: onCreateEvent
            )
        }
        .frame(width: totalWidth, alignment: .leading)
        .padding(.trailing, 8)
    }
}
#endif
