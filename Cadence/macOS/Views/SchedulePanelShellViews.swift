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
            SchedulePanelHeaderControls(zoomLevel: $zoomLevel, onExport: onExport)
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
            SchedulePanelHeaderControls(zoomLevel: $zoomLevel, onExport: onExport, spacing: 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// **The timeline's Export and zoom controls, one view for every host that draws them**
/// ([[T-10052]]).
///
/// They were spelled inside `SchedulePanelHeader`, so they existed only where that header did --
/// and [[T-615]] took the header away from `RootTimelineSidebarPane` (the Cmd+\ "Today Timeline"
/// pane) to stop the pane naming itself twice. Export and zoom went with the title, though nothing
/// in that ticket asked for them to: the pane was the one place the timeline could not be zoomed
/// or exported. The pane now draws this same view in its own title row, beside its close button.
struct SchedulePanelHeaderControls: View {
    @Binding var zoomLevel: Int
    let onExport: () -> Void
    /// The gap between Export and the zoom pair. The standard header's 8, the compact header's 10.
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            exportButton
            TimelineZoomControl(zoomLevel: $zoomLevel, range: TimelineZoom.levels)
        }
    }

    /// [[T-9982]]: the zoom pair's own button, so the header's three are one size and one radius.
    private var exportButton: some View {
        TimelineHeaderIconButton(
            systemImage: "square.and.arrow.up",
            accessibilityLabel: "Export schedule",
            action: onExport
        )
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
    /// The all-day draft the ladder below is composing ([[T-8851]]), or `nil`. The ladder is
    /// inside this panel's `ScrollView` and this band is pinned outside it, so the draft is
    /// published rather than drawn across the boundary; see `CadenceCalendarAllDayDraftSession`.
    var draftTitle: String? = nil

    var body: some View {
        let bandHeight = SchedulePanelAllDayBandLayout.height(
            eventCount: events.count,
            draftCount: draftTitle == nil ? 0 : 1
        )
        // The band follows the blocks ([[T-8001]] owner call, [[T-10440]]): its chips take the
        // ladder's own block column, read off the same width the viewport below lays out in.
        GeometryReader { geo in
            let span = SchedulePanelTimelineColumn.chipSpan(ladderWidth: geo.size.width)
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .frame(width: timeLabelWidth, alignment: .trailing)
                    .padding(.trailing, max(0, span.leading - timeLabelWidth))
                    .padding(.top, 4)

                chipColumn
                    .frame(width: span.width, height: bandHeight)

                Spacer(minLength: 0)
            }
        }
        .frame(height: bandHeight)
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

    private var chipColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SchedulePanelAllDayBandLayout.chipSpacing) {
                // First, so the row the user is typing is the row they can see.
                if let draftTitle {
                    CadenceAllDayDraftChip(title: draftTitle)
                }
                ForEach(events.map { CalendarAllDayEventItem(event: $0) }) { item in
                    AllDayEventChip(event: item.event)
                }
            }
            .padding(.vertical, SchedulePanelAllDayBandLayout.verticalPadding)
        }
    }
}

/// The Today ladder's horizontal geometry, stated once for the viewport that draws the blocks and
/// the all-day band that must line up with them ([[T-10440]]). The band used to pad itself 16pt
/// from the trailing edge on the belief that a block ended there; measured on screen under
/// [[T-8001]], blocks start 8pt further in and stop 22.5pt short of that, because they honour
/// `TimelineBlockStyle.schedule`'s leading inset and `blockWidthFraction`.
enum SchedulePanelTimelineColumn {
    /// The viewport draws this far short of the pane's trailing edge.
    static let trailingMargin: CGFloat = 8

    /// The rail plus canvas width the viewport lays out in.
    static func totalWidth(ladderWidth: CGFloat) -> CGFloat {
        max(240, ladderWidth - trailingMargin)
    }

    /// The canvas the blocks are drawn on, right of the hour rail.
    static func canvasWidth(ladderWidth: CGFloat) -> CGFloat {
        max(0, totalWidth(ladderWidth: ladderWidth) - blockInset)
    }

    /// A lone (single-lane) block's leading edge and width in pane coordinates -- the span an
    /// all-day chip takes so it starts and ends where a block does.
    static func chipSpan(ladderWidth: CGFloat) -> (leading: CGFloat, width: CGFloat) {
        let style = TimelineBlockStyle.schedule
        let column = TimelineMetricsSupport.blockColumnSpan(
            totalWidth: canvasWidth(ladderWidth: ladderWidth),
            style: style
        )
        return (blockInset + column.x, max(0, column.columnWidth - style.columnSpacing))
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
    ///
    /// `draftCount` is the all-day draft being composed on this day, which is one chip or none
    /// ([[T-8851]]). It counts toward `visibleChipLimit` like any other row — a conference week
    /// plus a draft still must not push the hour ladder off a short pane — but it is drawn first,
    /// so it is never the row that scrolls out of sight.
    static func height(eventCount: Int, draftCount: Int = 0) -> CGFloat {
        let rows = min(max(eventCount, 0) + max(draftCount, 0), visibleChipLimit)
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
        let totalWidth = SchedulePanelTimelineColumn.totalWidth(ladderWidth: geoSize.width)
        let canvasWidth = SchedulePanelTimelineColumn.canvasWidth(ladderWidth: geoSize.width)

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
        .padding(.trailing, SchedulePanelTimelineColumn.trailingMargin)
    }
}
#endif
