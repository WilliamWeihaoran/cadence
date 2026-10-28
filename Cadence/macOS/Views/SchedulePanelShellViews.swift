#if os(macOS)
import SwiftUI
import EventKit

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

/// **The day's all-day events, in a band above the hour ladder** ([[T-7982]]).
///
/// The pane drew timed events only, so a holiday, a trip or an offsite was on no part of Mac
/// Today while the Calendar page's Day view showed it across the top. This is that page's band
/// cut down for one day: the same `AllDayEventChip` (calendar hue, click opens the editor, drag
/// onto the ladder converts it), the same lowercase `all-day` label in the rail column the
/// Calendar corner draws, and no unscheduled tasks — the task column across the divider already
/// lists those in full, the rule iOS Today's strip keeps for the same reason ([[T-3163]]).
///
/// Drawn only when the day has one, so an ordinary day leaves the ladder exactly where it was.
/// Pinned outside the ladder's `ScrollView`, as the Calendar page's band is, so it stays on screen
/// while the hours scroll. Three chips show before the band scrolls itself.
struct SchedulePanelAllDayBand: View {
    let events: [EKEvent]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .frame(width: timeLabelWidth, alignment: .trailing)
                .padding(.trailing, timeLabelPad)
                .padding(.top, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: SchedulePanelAllDayBandLayout.chipSpacing) {
                    ForEach(events.map { CalendarAllDayEventItem(event: $0) }) { item in
                        AllDayEventChip(event: item.event)
                    }
                }
                .padding(.vertical, SchedulePanelAllDayBandLayout.verticalPadding)
            }
            .frame(height: SchedulePanelAllDayBandLayout.height(eventCount: events.count))
        }
        // The ladder's own right margin (`SchedulePanelTimelineViewport` pads 8 and draws 8
        // short of the pane), so a chip ends where a block does.
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            CadenceCalendarDayAccessibility.allDayStripLabel(allDayEventCount: events.count)
        )
    }
}

enum SchedulePanelAllDayBandLayout {
    /// Chips shown before the band scrolls rather than grows: a conference week of five all-day
    /// entries must not push the hour ladder off a short pane.
    static let visibleChipLimit = 3
    /// One `AllDayEventChip`: a 10pt line plus its 2pt vertical padding either side.
    static let chipHeight: CGFloat = 17
    static let chipSpacing: CGFloat = 2
    static let verticalPadding: CGFloat = 4

    /// Zero for a day with nothing all-day, so the band costs nothing on an ordinary day.
    static func height(eventCount: Int) -> CGFloat {
        let rows = min(max(eventCount, 0), visibleChipLimit)
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * chipHeight + CGFloat(rows - 1) * chipSpacing + verticalPadding * 2
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
    /// The all-day band's chips drag onto this ladder ([[T-8091]]). Required, not defaulted: the
    /// canvas's own parameter is optional, and leaving it unset here is what made the drop land and
    /// do nothing.
    let onDropAllDayEventAtMinute: (CalendarAllDayEventDropPayload, Int) -> Void
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
                onCreateEvent: onCreateEvent,
                onDropAllDayEventAtMinute: onDropAllDayEventAtMinute
            )
        }
        .frame(width: totalWidth, alignment: .leading)
        .padding(.trailing, 8)
    }
}
#endif
