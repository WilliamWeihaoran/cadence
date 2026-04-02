#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

let schedStartHour = 0
let schedEndHour   = 24
let timeLabelWidth: CGFloat = 36
let timeLabelPad:   CGFloat = 6
let blockInset:     CGFloat = timeLabelWidth + timeLabelPad  // 42

struct SchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TodayTimelineFocusManager.self) private var todayTimelineFocusManager
    @Query private var allTasks: [AppTask]

    @AppStorage("scheduleZoomLevel") private var zoomLevel: Int = 1
    @AppStorage("scheduleRememberedScrollHour") private var rememberedScrollHour: Int = -1
    @State private var isRestoringScroll = true
    @State private var didRestoreScroll = false
    @State private var isFocusHighlighted = false

    private var todayKey: String { DateFormatters.todayKey() }

    private var scheduledTasks: [AppTask] {
        allTasks.filter {
            $0.scheduledDate == todayKey && $0.scheduledStartMin >= 0 && !$0.isCancelled
        }
    }

    /// iCal events for today that aren't already represented by a Cadence task.
    private var externalEventItems: [CalendarEventItem] {
        let _ = calendarManager.storeVersion  // subscribe to store change refreshes
        let linkedIDs = Set(allTasks.compactMap { $0.calendarEventID.isEmpty ? nil : $0.calendarEventID })
        return calendarManager.fetchEvents(for: Date())
            .filter { event in
                guard let id = event.eventIdentifier else { return true }
                return !linkedIDs.contains(id)
            }
            .map { CalendarEventItem(event: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header + zoom controls
            HStack(spacing: 0) {
                PanelHeader(eyebrow: "Schedule", title: "Timeline")
                Spacer()
                TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)
                    .padding(.trailing, 12)
            }

            Divider().background(Theme.borderSubtle)

            GeometryReader { geo in
                let targetHours: CGFloat = zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4
                let hourHeight = geo.size.height / targetHours
                let metrics = TimelineMetrics(
                    startHour: schedStartHour,
                    endHour: schedEndHour,
                    hourHeight: hourHeight
                )
                let totalWidth = max(240, geo.size.width - 8)
                let canvasWidth = max(0, totalWidth - blockInset)

                ScrollViewReader { proxy in
                    ScrollView {
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
                                onCreateTask: { title, startMin, endMin in
                                    SchedulingActions.createTask(title: title, dateKey: todayKey, startMin: startMin, endMin: endMin, in: modelContext)
                                },
                                onDropTaskAtMinute: { task, startMin in
                                    SchedulingActions.dropTask(task, to: todayKey, startMin: startMin)
                                },
                                externalEvents: externalEventItems,
                                onCreateEvent: { title, startMin, endMin, calendarID, notes in
                                    calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: Date(), notes: notes)
                                }
                            )
                        }
                        .frame(width: totalWidth, alignment: .leading)
                        .padding(.trailing, 8)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                        guard didRestoreScroll, !isRestoringScroll else { return }
                        let rawHour = schedStartHour + Int(y / max(hourHeight, 1))
                        rememberedScrollHour = min(max(rawHour, schedStartHour), schedEndHour - 1)
                    }
                    .onAppear {
                        let currentHour = Calendar.current.component(.hour, from: Date())
                        let fallbackHour = max(schedStartHour, currentHour - 1)
                        let scrollHour = rememberedScrollHour >= schedStartHour ? rememberedScrollHour : fallbackHour
                        isRestoringScroll = true
                        DispatchQueue.main.async {
                            proxy.scrollTo(scrollHour, anchor: .top)
                            DispatchQueue.main.async {
                                didRestoreScroll = true
                                isRestoringScroll = false
                            }
                        }
                    }
                    .onChange(of: todayTimelineFocusManager.focusRequestID) { _, _ in
                        focusTimeline(using: proxy)
                    }
                }
            }
        }
        .background(Theme.bg)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.blue.opacity(isFocusHighlighted ? 0.95 : 0), lineWidth: 2)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .onChange(of: calendarManager.storeVersion) {
            // Sync task times when iCal events are moved or deleted externally
            for task in allTasks where !task.calendarEventID.isEmpty {
                calendarManager.syncTaskFromLinkedEvent(task)
            }
            try? modelContext.save()
        }
    }

    private func focusTimeline(using proxy: ScrollViewProxy) {
        clearAppEditingFocus()
        let currentHour = Calendar.current.component(.hour, from: Date())
        let targetHour = max(schedStartHour, min(currentHour - 1, schedEndHour - 1))
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(targetHour, anchor: .top)
        }
        withAnimation(.easeOut(duration: 0.16)) {
            isFocusHighlighted = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.24)) {
                isFocusHighlighted = false
            }
        }
    }
}
#endif
