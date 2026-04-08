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
        SchedulePanelDataSupport.scheduledTasks(from: allTasks, todayKey: todayKey)
    }

    /// iCal events for today that aren't already represented by a Cadence task.
    private var externalEventItems: [CalendarEventItem] {
        let _ = calendarManager.storeVersion  // subscribe to store change refreshes
        return SchedulePanelDataSupport.externalEventItems(
            from: allTasks,
            calendarManager: calendarManager,
            date: Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SchedulePanelHeader(zoomLevel: $zoomLevel)

            Divider().background(Theme.borderSubtle)

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        SchedulePanelTimelineViewport(
                            geoSize: geo.size,
                            zoomLevel: zoomLevel,
                            allTasks: allTasks,
                            scheduledTasks: scheduledTasks,
                            todayKey: todayKey,
                            externalEventItems: externalEventItems,
                            onCreateTask: { title, startMin, endMin in
                                SchedulingActions.createTask(title: title, dateKey: todayKey, startMin: startMin, endMin: endMin, in: modelContext)
                            },
                            onDropTaskAtMinute: { task, startMin in
                                SchedulingActions.dropTask(task, to: todayKey, startMin: startMin)
                            },
                            onCreateEvent: { title, startMin, endMin, calendarID, notes in
                                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: Date(), notes: notes)
                            }
                        )
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                        SchedulePanelInteractionSupport.persistRememberedHour(
                            yOffset: y,
                            geoHeight: geo.size.height,
                            zoomLevel: zoomLevel,
                            didRestoreScroll: didRestoreScroll,
                            isRestoringScroll: isRestoringScroll
                        ) {
                            rememberedScrollHour = $0
                        }
                    }
                    .onAppear {
                        SchedulePanelDataSupport.restoreScroll(
                            proxy: proxy,
                            rememberedScrollHour: rememberedScrollHour,
                            setRestoring: { isRestoringScroll = $0 },
                            setDidRestore: { didRestoreScroll = $0 }
                        )
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
            SchedulePanelDataSupport.syncLinkedTasks(
                allTasks: allTasks,
                modelContext: modelContext,
                calendarManager: calendarManager
            )
        }
    }

    private func focusTimeline(using proxy: ScrollViewProxy) {
        SchedulePanelInteractionSupport.focusTimeline(
            proxy: proxy,
            clearAppEditingFocus: clearAppEditingFocus
        ) {
            isFocusHighlighted = $0
        }
    }
}
#endif
