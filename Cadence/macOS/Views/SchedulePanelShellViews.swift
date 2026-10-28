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
        case .hosted:
            // Never reached: `SchedulePanel` builds no header at all when its host has already
            // named the column (T-615). Stated rather than defaulted, so a genuinely new
            // presentation still has to come here and decide.
            EmptyView()
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
        .cadenceControlLabel("Export schedule")
    }
}

struct SchedulePanelTimelineViewport: View {
    let geoSize: CGSize
    let zoomLevel: Int
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let scheduledTasks: [AppTask]
    let todayKey: String
    let externalEventItems: [CalendarEventItem]
    let onCreateTask: (QuickCreateTaskDraft) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onCreateEvent: (QuickCreateEventDraft) -> CalendarWriteFailure?

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

            // **[[T-3170]]: this timeline has no Block arm left.** The canvas used to take four
            // block parameters, starved here with an empty bundle array and two refusing drop
            // closures while the Calendar page still drew Blocks. T-3170's later passes deleted the
            // Block from both timelines and the parameters with it, so the canvas below is handed
            // tasks and events only: nothing on it can draw, select, open or accept a Block.
            TimelineDayCanvas(
                date: Date(),
                dateKey: todayKey,
                tasks: scheduledTasks,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                metrics: metrics,
                width: canvasWidth,
                style: .schedule,
                showCurrentTimeDot: true,
                showHalfHourMarks: zoomLevel == 3,
                showWorkHoursHighlight: true,
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
