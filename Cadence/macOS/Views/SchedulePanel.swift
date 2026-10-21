#if os(macOS)
import SwiftUI
import SwiftData
import EventKit
import AppKit
import UniformTypeIdentifiers

private struct PlainTextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// The hours this panel draws. Aliases, not literals: this was one of three independent spellings
// of the same range, and the iOS one had drifted to `6..<23`.
let schedStartHour = CadenceScheduleSupport.calendarStartHour
let schedEndHour   = CadenceScheduleSupport.calendarEndHour
let timeLabelWidth: CGFloat = 36
let timeLabelPad:   CGFloat = 6
let blockInset:     CGFloat = timeLabelWidth + timeLabelPad  // 42

enum SchedulePanelPresentation {
    /// Today's schedule column: the panel is the page's own third column and nothing above it says
    /// what it is, so it draws its own "Timeline" header.
    case standard
    /// The focus screen and the focus sidebar: same job, tighter header.
    case compact
    /// Hosted inside a pane that has **already** named it — today only `RootTimelineSidebarPane`,
    /// which titles itself "Today Timeline" and draws its own rule underneath that title.
    ///
    /// **T-615.** The pane said "timeline" twice, one line apart, and before T-602 three times. A
    /// page header does not describe the page the user is already on, and that rule does not stop
    /// at the outermost header: the second one is the one to drop, because the first is the one the
    /// user read. The divider goes with the header — the host draws that rule itself, so keeping
    /// the panel's would leave two hairlines with nothing between them.
    ///
    /// Opt-in, not a default, and that is the load-bearing half: the other three hosts have nothing
    /// above them naming the column, so a panel that dropped its heading unconditionally would
    /// leave three unnamed columns to fix one named twice.
    case hosted

    /// Whether the panel draws its own heading and the rule under it.
    var drawsOwnHeader: Bool { self != .hosted }
}

struct SchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TodayTimelineFocusManager.self) private var todayTimelineFocusManager
    var presentation: SchedulePanelPresentation = .standard
    var useStandardHeaderHeight = false
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @AppStorage("scheduleZoomLevel") private var zoomLevel: Int = 1
    @AppStorage("scheduleRememberedScrollHour") private var rememberedScrollHour: Int = -1
    @State private var isRestoringScroll = true
    @State private var didRestoreScroll = false
    /// The hour the last adopted scroll report named, and the debounced write it scheduled
    /// (T-1498). A reference box rather than two `@State` values, for the reason
    /// `SchedulePanelScrollPersistence` states: a `@State` write from a scroll report is the very
    /// per-frame render this is here to stop.
    @State private var scrollPersistence = SchedulePanelScrollPersistence()
    /// Today's events, memoised for the panel's lifetime (T-1499). The same type, held the same
    /// way, as `CalendarPageView.calendarEventDayCache` — one day's key rather than a window's,
    /// because this panel draws exactly one day.
    @State private var eventCache = CalendarEventDayCache()
    @State private var isFocusHighlighted = false
    /// The refusal this timeline can produce: a drag-created task the store would not take
    /// ([[T-655]], [[T-3171]]). Its sibling on the Calendar page's `CalDayColumn` is the same flag
    /// drawn the same way, for the reason stated beside that alert.
    @State private var taskCreateFailed = false
    @State private var exportDocument: PlainTextExportDocument?
    @State private var isExportingTimeline = false

    /// The invalidation token for the day this timeline draws (T-3120, after [[T-3104]]). Every
    /// host builds this panel with constant arguments, so a host's own body pass at midnight does
    /// not reach this one; the panel has to observe the day itself.
    @State private var observedDay = CadenceObservedDay()

    private var todayKey: String { observedDay.todayKey }

    private var scheduledTasks: [AppTask] {
        SchedulePanelDataSupport.scheduledTasks(from: allTasks, todayKey: todayKey)
    }

    // [[T-3170]] removed `todayBundles` and the `@Query private var allBundles` behind it. This
    // panel neither draws a Block nor edits one, so it no longer reads the table at all; see
    // `SchedulePanelTimelineViewport` for what the canvas is handed instead.

    /// iCal events for today. Raw tasks are never treated as event attachments.
    ///
    /// **T-1499.** Served from `eventCache`, keyed by today's `yyyy-MM-dd`, so the body evaluations
    /// this panel does on every task change and every zoom step no longer each run an
    /// `EKEventStore` query. The `storeVersion` read below is still the subscription — and it is
    /// also what invalidates the cache, since `CalendarEventDayCache` drops everything when that
    /// number moves.
    private var externalEventItems: [CalendarEventItem] {
        let _ = calendarManager.storeVersion  // subscribe to store change refreshes
        return SchedulePanelDataSupport.externalEventItems(
            calendarManager: calendarManager,
            date: Date(),
            cache: eventCache
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation.drawsOwnHeader {
                SchedulePanelHeader(
                    presentation: presentation,
                    zoomLevel: $zoomLevel,
                    onExport: exportTodayPlan
                )
                .frame(height: headerHeight, alignment: .top)

                Divider().background(Theme.borderSubtle)
            }

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        SchedulePanelTimelineViewport(
                            geoSize: geo.size,
                            zoomLevel: zoomLevel,
                            allTasks: allTasks,
                            areas: areas,
                            projects: projects,
                            scheduledTasks: scheduledTasks,
                            todayKey: todayKey,
                            externalEventItems: externalEventItems,
                            // **[[T-3171]]: this composes in place, it does not open a second
                            // surface.** It used to call `taskCreationManager.present(…)`, which
                            // raises `CreateTaskPanelSurface` — the old create-task sheet — over
                            // the window with the draft as its seed, so pressing Add in the shared
                            // panel re-asked for everything the user had just typed and stored
                            // nothing until they confirmed a second time. `draft.dateKey` is still
                            // honoured (T-1433 gave the popover a date field, and
                            // `QuickCreateChoicePopover.hostWritesDraftDay` is true for this host
                            // because of this line), it is now the day the task is written on
                            // rather than the day a second sheet opens on.
                            onCreateTask: createTask,
                            onDropTaskAtMinute: { task, startMin in
                                SchedulingActions.dropTask(task, to: todayKey, startMin: startMin)
                            },
                            onCreateEvent: { title, startMin, endMin, calendarID, notes in
                                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: Date(), notes: notes)
                            }
                        )
                    }
                    // **T-1498.** The action below runs on every frame of a live scroll, because a
                    // raw `contentOffset.y` changes on every frame, and it used to write
                    // `rememberedScrollHour` from every one of them — 60 `UserDefaults` writes per
                    // fling, where a settled gesture now lands exactly one.
                    //
                    // It was **not** 60 renders: a `UserDefaults` key does not notify when written
                    // the value it already holds, measured at 1 notification for 60 identical
                    // writes against 60 for 60 distinct ones, so the invalidations were already one
                    // per hour crossed. Those are the expensive ones — each re-runs a body that
                    // passes over every task in the store and fetches the day's events from
                    // `EKEventStore` uncached — which is why the debounce matters more than the
                    // guard and why both are here. The calendar page's host of the same
                    // `TimelineDayCanvas` has had both since before this ticket.
                    //
                    // Keyed off a reference box, so the guard itself costs no render.
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                        SchedulePanelInteractionSupport.persistRememberedHour(
                            yOffset: y,
                            geoHeight: geo.size.height,
                            zoomLevel: zoomLevel,
                            didRestoreScroll: didRestoreScroll,
                            isRestoringScroll: isRestoringScroll,
                            state: scrollPersistence
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
        .fileExporter(
            isPresented: $isExportingTimeline,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "Cadence Schedule \(todayKey)"
        ) { _ in
            exportDocument = nil
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.blue.opacity(isFocusHighlighted ? 0.95 : 0), lineWidth: 2)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .calendarWriteFailureAlert()
        // An alert rather than an inline notice, for the reason `CalDayColumn`'s says: the draft
        // popover the user typed into has already dismissed itself by the time the store answers,
        // so there is nothing left on screen to write under.
        .alert(TaskCreationService.createFailureAlertTitle, isPresented: $taskCreateFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(TaskCreationService.saveFailureNotice)
        }
        .cadenceTracksDayChanges($observedDay)
        .onChange(of: calendarManager.storeVersion) {
            SchedulePanelDataSupport.syncLinkedTasks(
                allTasks: allTasks,
                modelContext: modelContext,
                calendarManager: calendarManager
            )
        }
    }

    /// Only asked when `presentation.drawsOwnHeader`; `.hosted` draws no header to size.
    private var headerHeight: CGFloat? {
        if presentation == .compact { return 58 }
        return useStandardHeaderHeight ? todayPanelHeaderHeight : nil
    }

    /// **The drag-created task is committed here, and a refusal is named here** ([[T-3171]]).
    ///
    /// See `SchedulePanelDataSupport.insertDragCreatedTask` for why this host writes the draft's
    /// own day and for what it replaced.
    private func createTask(_ draft: QuickCreateTaskDraft) {
        do {
            try SchedulePanelDataSupport.insertDragCreatedTask(
                draft,
                areas: areas,
                projects: projects,
                in: modelContext
            )
        } catch {
            taskCreateFailed = true
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

    private func exportTodayPlan() {
        let taskLines = scheduledTasks
            .sorted { $0.scheduledStartMin < $1.scheduledStartMin }
            .map { task in
                "- \(TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)) • \(TaskTitleSupport.displayTitle(task.title))"
            }

        let eventLines = externalEventItems
            .sorted { $0.startMin < $1.startMin }
            .map { event in
                "- \(TimeFormatters.timeRange(startMin: event.startMin, endMin: event.startMin + max(event.durationMinutes, 5))) • \(event.title)"
            }

        let markdown = """
        # Schedule for \(todayKey)

        ## Tasks
        \(taskLines.isEmpty ? "- None" : taskLines.joined(separator: "\n"))

        ## Calendar Events
        \(eventLines.isEmpty ? "- None" : eventLines.joined(separator: "\n"))
        """
        exportDocument = PlainTextExportDocument(text: markdown)
        isExportingTimeline = true
    }
}
#endif
