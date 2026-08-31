#if os(iOS)
import SwiftData
import SwiftUI

/// Today's timeline, hosted in the two-pane inspector. It draws no header of its own:
/// `iPadTodayInspectorSwitcher` sits directly above it with "Timeline" lit up in it. The
/// `showsHeader` flag that used to switch one on existed for the three-pane Today layout, where
/// this pane stood beside two others; that layout is gone.
///
/// **It had a compact ramp, and the compact half of it could not be reached.** `rowHeight` was
/// `regular ? 58 : 48` and the grid's trailing gutter `regular ? 12 : 8`, but this pane is only ever
/// built by `iOSTodayView.inspectorPanelContent`, which only `twoPaneTodayLayout` reaches, which
/// `CadenceTodayLayoutSupport.layout` only returns at regular width. Two dead branches carrying two
/// numbers nobody had ever seen — the same defect `iOSTodayView`'s deleted `todayRowDensity`
/// had, in the same file family. The regular figures are the only ones that ever drew, so they are
/// the ones that stay.
struct iOSSchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey)
    private var workHoursStartMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey)
    private var workHoursEndMinute = CalendarWorkHoursPreferences.defaultEndMinute
    @State private var quickCreateStartMin: Int?
    @State private var quickCreateTitle = ""
    @State private var quickCreateError: String?
    /// See `placeInitialScroll(contentHeight:proxy:)`. Not persisted anywhere, deliberately.
    @State private var didPlaceInitialScroll = false

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var scheduledTasks: [AppTask] {
        CadenceScheduleSupport.scheduledTasks(on: todayKey, from: allTasks, includeCompleted: false, excludeBundled: false)
    }

    private var todayBundles: [TaskBundle] {
        CadenceScheduleSupport.bundles(on: todayKey, from: allBundles, includeCompleted: false)
    }

    private var untimedTodayTasks: [AppTask] {
        CadenceScheduleSupport.unscheduledTasksByDate(allTasks)[todayKey] ?? []
    }

    /// Drives the one-line hint, and it is about the *grid*, not the day: the hint's job is to say
    /// that tapping an hour is what fills the grid, so it stays for as long as the grid is empty —
    /// which is also the only time there is room for it. It goes the moment the first block lands,
    /// by which point the gesture has been used.
    private var hasNoBlocks: Bool {
        scheduledTasks.isEmpty && todayBundles.isEmpty
    }

    /// The day the ready-to-schedule chips are offered against: the clock, the work-hours window
    /// and what is already on the day. Each row derives its own start times from it, because the
    /// block a chip writes is as long as the task — see
    /// `CadenceScheduleSupport.ReadyScheduleContext`.
    ///
    /// Derived on every draw and deliberately not seeded into `@State`: the answer goes stale as
    /// the day moves and as tasks are placed, and a snapshot taken in `onAppear` would keep
    /// offering an hour that has just been filled.
    private var readyScheduleContext: CadenceScheduleSupport.ReadyScheduleContext {
        CadenceScheduleSupport.ReadyScheduleContext(
            workStartMinute: workHoursStartMinute,
            workEndMinute: workHoursEndMinute,
            busyRanges: CadenceScheduleSupport.busyMinuteRanges(
                tasks: scheduledTasks,
                bundles: todayBundles
            )
        )
    }

    /// The scroll target for the inline composer. See `quickCreateComposer(for:)`.
    private static let quickCreateAnchorID = "schedule.quickCreate"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !untimedTodayTasks.isEmpty {
                iOSScheduleReadyStack(tasks: untimedTodayTasks, context: readyScheduleContext)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                Divider().background(Theme.borderSubtle.opacity(0.72))
            }

            // A plain scroll view, not a `ZStack` with the empty hint floated over it. The hint was
            // a card laid across the middle of the grid, hiding two hours of rows and their
            // controls outright — `.allowsHitTesting(false)` kept them tappable but left them
            // invisible, which is worse than an empty state that is simply not there. It is one
            // line at the top of the scrolled content now, so it can never cover a row.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if hasNoBlocks {
                            Text(iOSSchedulePanelCopy.emptyScheduleHint)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 14)
                        }

                        ForEach(CadenceScheduleSupport.calendarHours, id: \.self) { hour in
                            VStack(alignment: .leading, spacing: 0) {
                                iOSScheduleHourRow(
                                    hour: hour,
                                    tasks: tasks(in: hour),
                                    bundles: bundles(in: hour),
                                    rowHeight: rowHeight,
                                    selectedStartMin: quickCreateStartMin,
                                    onSelectStart: selectQuickCreateStart
                                )

                                quickCreateComposer(for: hour)
                            }
                            .id(hour)
                        }
                    }
                    .padding(.trailing, 12)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height
                } action: { _, contentHeight in
                    placeInitialScroll(contentHeight: contentHeight, proxy: proxy)
                }
                .onChange(of: quickCreateStartMin) { _, newValue in
                    revealQuickCreate(startMin: newValue, proxy: proxy)
                }
            }
        }
        // **T-586.** `Theme.surface`, and it ignores the safe area, because this pane and
        // `iOSNotesView` are the two halves of one rail: the switcher above them selects between
        // them, and a background that changed with the selection made the selection look like a
        // change of page. This half drew `Theme.bg` inside the safe area and the other
        // `Theme.surface` beyond it. Surface is the side that wins — it is what the task column
        // beside the rail draws, what `iOSNotesView` draws everywhere it is hosted, and the one of
        // the two this pane could change without changing a page that also stands alone.
        .background(Theme.surface.ignoresSafeArea())
    }

    /// The composer, drawn under the hour lane that was tapped rather than above the whole grid.
    ///
    /// It used to be a sibling of the `ScrollView` in the outer `VStack`, so opening it inserted
    /// ~130pt *above* the grid: every hour row slid down by a composer's height, and the 11 PM lane
    /// you had just aimed at was somewhere near 8 PM by the time the composer appeared — at the top
    /// of the pane, nowhere near the tap. That was survivable when the grid ran 6 AM to 11 PM and
    /// mostly visible at once; with 24 rows it is the whole interaction. Inline, the row you tapped
    /// does not move at all, and the composer opens directly beneath it saying which hour it is for.
    @ViewBuilder
    private func quickCreateComposer(for hour: Int) -> some View {
        if let quickCreateStartMin, quickCreateStartMin == hour * 60 {
            iOSScheduleQuickCreateBar(
                startMin: quickCreateStartMin,
                title: $quickCreateTitle,
                errorMessage: quickCreateError,
                create: createScheduledTask,
                cancel: cancelQuickCreate
            )
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.bottom, 12)
            .id(Self.quickCreateAnchorID)
            // **T-589.** "Add a title first." used to stay red under the field while you typed the
            // title it was asking for. `selectQuickCreateStart` and `cancelQuickCreate` were the
            // only two clears, so the one edit that answers the complaint — typing — did not.
            // The notice is about the field's *current* contents; the moment they change it is
            // stating something that is no longer true, whichever of the two messages it is
            // carrying. Attached to the composer rather than to the pane because the title can
            // only change while the composer is up, and a clear that outlives its own field is the
            // shape this is fixing.
            .onChange(of: quickCreateTitle) { _, _ in
                quickCreateError = nil
            }
        }
    }

    /// Scrolls the minimum amount that makes the composer visible, and only when it is not — that
    /// is what `anchor: nil` means. Tapping a lane in the middle of the pane therefore moves
    /// nothing; tapping the last lane at the bottom edge lifts the composer into view instead of
    /// opening it below the fold. Deferred a runloop turn because the composer is not in the
    /// layout at the instant the selection changes.
    private func revealQuickCreate(startMin: Int?, proxy: ScrollViewProxy) {
        guard startMin != nil else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(Self.quickCreateAnchorID, anchor: nil)
        }
    }

    /// **Read, not re-typed (T-588).** `iOSCalendarTimelineMetrics.hourHeight`'s own doc already
    /// claimed this: *"58 is `iOSSchedulePanel.rowHeight` — the app's one answer to how tall an
    /// hour on an iOS timeline is."* It was a second hand-typed 58, and prose is not a reference —
    /// the Calendar grid and this pane draw the same `iOSTimelineTaskBlock`, so a change to one 58
    /// would have silently made the same scheduled task a different number of points tall on the
    /// two timed surfaces of one iPad. `iOSCalendarMetricsTests` holds it to the read.
    private var rowHeight: CGFloat { iOSCalendarTimelineMetrics.hourHeight }

    /// Opens the pane near the hour that matters. The grid is the whole day now, and a scroll view
    /// opens at the top of its content — so left alone this pane would open at midnight, which is
    /// a worse place to land than the 06:00 it replaced. The rule is
    /// `CadenceScheduleSupport.initialTimelineHour`; this pane always shows today, so it always
    /// takes the "current hour, one hour of context above it" branch.
    ///
    /// Driven by the scroll view's own reported content height rather than `onAppear`, for the
    /// reason `ecaf80f` records: `onAppear` can run before the content has a size, and a scroll
    /// against nothing silently does nothing while looking like it worked. Nothing here is written
    /// to defaults — the hour is recomputed on every open, so a bad placement costs one screen and
    /// can never compound into a saved anchor.
    private func placeInitialScroll(contentHeight: CGFloat, proxy: ScrollViewProxy) {
        guard !didPlaceInitialScroll,
              contentHeight >= CGFloat(CadenceScheduleSupport.calendarHourCount) * rowHeight
        else { return }
        didPlaceInitialScroll = true

        proxy.scrollTo(CadenceScheduleSupport.initialTimelineHour(showsToday: true), anchor: .top)
    }

    /// Every real minute-of-day now has a row of its own, so nothing is clamped in practice; see
    /// `CadenceScheduleSupport.timelineHourRow` for why the clamp is still there.
    private func tasks(in hour: Int) -> [AppTask] {
        CadenceScheduleSupport.tasks(inHourRow: hour, from: scheduledTasks)
    }

    private func bundles(in hour: Int) -> [TaskBundle] {
        CadenceScheduleSupport.bundles(inHourRow: hour, from: todayBundles)
    }

    private func selectQuickCreateStart(_ startMin: Int) {
        quickCreateStartMin = startMin
        quickCreateError = nil
    }

    private func cancelQuickCreate() {
        quickCreateStartMin = nil
        quickCreateTitle = ""
        quickCreateError = nil
    }

    private func createScheduledTask() {
        guard let startMin = quickCreateStartMin else { return }
        let pendingTitle = quickCreateTitle
        do {
            guard (try CadenceTaskMutationSupport.insertScheduledTask(
                title: pendingTitle,
                allTasks: allTasks,
                modelContext: modelContext,
                scheduledDate: todayKey,
                scheduledStartMin: startMin,
                estimatedMinutes: 30
            )) != nil else {
                quickCreateError = "Add a title first."
                return
            }
            cancelQuickCreate()
        } catch {
            quickCreateTitle = pendingTitle
            quickCreateError = "Couldn't save this timed task."
        }
    }
}

private struct iOSScheduleQuickCreateBar: View {
    let startMin: Int
    @Binding var title: String
    let errorMessage: String?
    let create: () -> Void
    let cancel: () -> Void
    @FocusState private var isFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                iOSIconTile(systemImage: "clock.badge.plus", color: Theme.blue, size: 28, iconSize: 12, bordered: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create at \(TimeFormatters.timeString(from: startMin))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text("Adds a 30 minute task to Today.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                // 26pt of plate, 44pt of hit area — the same trick `iOSIconButton` uses, rather
                // than a 26pt tap target on the control that gets you out of the composer.
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 26, height: 26)
                        .background(Theme.surfaceElevated.opacity(0.38))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .contentShape(Rectangle())
                        .iOSExpandedHitArea(9)
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel("Cancel timed task")
            }

            HStack(spacing: 7) {
                TextField("Timed task title...", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .focused($isFocused)
                    .submitLabel(.done)
                    // **Deliberately not guarded the way the `+` beside it is disabled** (T-589).
                    // The button can refuse in a way you can see: it greys out, so an empty title
                    // has already been answered before you reach for it. Return has no such
                    // affordance, so guarding it would make the key do nothing at all and look
                    // broken — the "inert control, no word on it" failure T-470/T-471 went through
                    // this app removing. `create` reports instead, and the notice now clears on
                    // the next keystroke.
                    .onSubmit(create)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Theme.surface.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.52), lineWidth: 1)
                    }

                Button(action: create) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(trimmedTitle.isEmpty ? Theme.dim : Theme.onColor)
                        .frame(width: 44, height: 44)
                        .background(trimmedTitle.isEmpty ? Theme.surfaceElevated.opacity(0.42) : Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.iosPressable)
                .disabled(trimmedTitle.isEmpty)
                .accessibilityLabel("Create timed task")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.36), cornerRadius: Theme.radiusCard)
        .onAppear {
            isFocused = true
        }
    }
}

private struct iOSScheduleHourRow: View {
    let hour: Int
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let rowHeight: CGFloat
    let selectedStartMin: Int?
    let onSelectStart: (Int) -> Void

    @Environment(\.modelContext) private var modelContext

    private var hasItems: Bool {
        !tasks.isEmpty || !bundles.isEmpty
    }

    private var startMin: Int {
        hour * 60
    }

    private var isSelectedForCreate: Bool {
        selectedStartMin == startMin
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // The hour rail, at the Calendar grid's own figures rather than a second copy of them
            // (T-588). Both were `rowHeight > 50 ? … : …` ramps, and neither had a reachable lower
            // branch: `rowHeight` is `iOSCalendarTimelineMetrics.hourHeight`, 58, on every pane
            // this view is ever built on — the same dead compact ramp this file's own header
            // records deleting from `rowHeight` itself, three lines further down the same row.
            //
            // **The trailing inset was 9 here against the rail's 8**, which is the drift a stated
            // invariant with nothing enforcing it produces. 8 is the figure that stays: it is what
            // `iOSCalendarTimelineMetrics.hourLabelTrailingInset` documents (the narrow rail is
            // the one with no slack in it, and `theHourLabelFitsTheNarrowRail` measures the label
            // against it), it is what the Calendar's rail already draws on both platforms' widths,
            // and taking 9 instead would mean moving the surface with the measurement to match the
            // surface without one. The label shifts 1pt right on Today's timeline.
            Text(hourLabel)
                .font(.system(size: iOSCalendarTimelineMetrics.hourLabelSize, weight: .medium))
                .foregroundStyle(
                    isSelectedForCreate
                        ? Theme.blue
                        : Theme.dim.opacity(
                            hour % iOSCalendarTimelineMetrics.hourEmphasisInterval == 0
                                ? iOSCalendarTimelineMetrics.hourLabelOpacity
                                : iOSCalendarTimelineMetrics.hourLabelMutedOpacity
                        )
                )
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, iOSCalendarTimelineMetrics.hourLabelTrailingInset)
                .padding(.top, -6)

            VStack(alignment: .leading, spacing: 5) {
                // **The rule was copied and the weights were not (T-596).** This drew a 1pt line at
                // 0.55/0.25 while the Calendar grid drew a 0.5pt one at 0.46/0.20 — the identical
                // `% 3` cadence on both, and the identical 0.9/0.45 on the labels beside them, which
                // is what made the line the accident rather than the decision.
                //
                // The Calendar's figures are the ones that stay, on T-588's grounds: that ticket
                // already settled three figures of this exact pair (`hourHeight`, `hourLabelSize`,
                // `hourLabelTrailingInset`) in the Calendar's favour, and 0.5pt is a hairline where
                // 1pt is two device pixels at 2x — twice the weight for a line whose whole job is to
                // be underneath the schedule rather than in it.
                Rectangle()
                    .fill(
                        isSelectedForCreate
                            ? Theme.blue.opacity(0.58)
                            : Theme.borderSubtle.opacity(
                                hour % iOSCalendarTimelineMetrics.hourEmphasisInterval == 0
                                    ? iOSCalendarHairlineMetrics.hourMajorOpacity
                                    : iOSCalendarHairlineMetrics.hourMinorOpacity
                            )
                    )
                    .frame(height: iOSCalendarHairlineMetrics.width)

                if hasItems {
                    VStack(alignment: .leading, spacing: 5) {
                        // The same two blocks the Calendar screen's day columns draw. `false` because
                        // an hour row sizes to its content rather than handing each block an exact
                        // height — see `iOSTimelineTaskBlock.fillsAvailableHeight`.
                        ForEach(bundles) { bundle in
                            iOSTimelineBundleBlock(bundle: bundle, fillsAvailableHeight: false)
                        }

                        ForEach(tasks) { task in
                            iOSTimelineTaskBlock(
                                task: task,
                                startMin: task.scheduledStartMin,
                                endMin: task.scheduledEndMin,
                                fillsAvailableHeight: false,
                                // Only this pane offers it: the "Ready to Schedule" stack a cleared
                                // task falls back into is directly above the grid here.
                                onClearTime: {
                                    CadenceTaskDateEditing.clearScheduledTime(task, in: modelContext)
                                }
                            )
                        }
                    }
                    .padding(.top, 5)
                } else {
                    // The empty hour *is* the control. This used to be a visible "+ Add" chip, and
                    // because every hour of an unplanned day is empty, one identical chip per hour
                    // stacked down the pane was the loudest thing in it — a column of controls
                    // shouting over the schedule they were meant to frame. The lane takes the whole
                    // row as its tap target and draws nothing until it is the hour being created
                    // in, which is the only one with something to say.
                    Button {
                        onSelectStart(startMin)
                    } label: {
                        // `Color.clear`, not the marker with a `.frame` on it: an unselected lane's
                        // marker is an `EmptyView`, which SwiftUI elides from the view tree along
                        // with the frame and `contentShape` hung off it — the lane laid out at the
                        // right height and swallowed every tap. A `Color` is a real, hit-testable
                        // layer at zero visual cost.
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: laneHeight)
                            .overlay(alignment: .topLeading) { creatingMarker }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create timed task at \(hourLabel)")
                }
            }
        }
        .frame(minHeight: rowHeight, alignment: .top)
        .padding(.leading, 4)
    }

    /// The lane fills the row: rule, the `VStack`'s own 5pt gap, then everything left. Floored at
    /// the 44pt touch minimum so a shorter row still gives a finger somewhere to land.
    private var laneHeight: CGFloat {
        max(44, rowHeight - 6)
    }

    @ViewBuilder
    private var creatingMarker: some View {
        if isSelectedForCreate {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Creating here")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.blue)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl - 3, style: .continuous))
        }
    }

    private var hourLabel: String {
        TimeFormatters.timeString(from: hour * 60)
    }
}

private struct iOSScheduleReadyStack: View {
    let tasks: [AppTask]
    /// The day, computed once for the pane, so a slot that has just been filled disappears from
    /// every row at once and no two rows drawn in one pass disagree about the clock. The start
    /// *times* are per row, because the block a chip writes is as long as that row's task — see
    /// `CadenceScheduleSupport.ReadyScheduleContext`.
    let context: CadenceScheduleSupport.ReadyScheduleContext

    private var visibleTasks: [AppTask] {
        Array(tasks.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)

                SectionEyebrowLabel(text: "Ready to Schedule")

                Spacer(minLength: 0)

                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(visibleTasks) { task in
                    iOSScheduleReadyTaskRow(task: task, context: context)
                }
            }

            if tasks.count > visibleTasks.count {
                Text("+\(tasks.count - visibleTasks.count) more in Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
            }
        }
    }
}

private struct iOSScheduleReadyTaskRow: View {
    @Bindable var task: AppTask
    let context: CadenceScheduleSupport.ReadyScheduleContext
    @Environment(\.modelContext) private var modelContext
    // T-201: Today's page hosts the inspector (`iOSTaskInspectorHost`), not this row. "Ready to
    // schedule" is by definition a filtered stack — scheduling, completing or cancelling the task
    // takes it out of the stack, which is exactly what this row's own sheet could not survive.
    @Environment(\.iOSTaskInspector) private var taskInspector

    /// The chips this row may actually offer. `setScheduledSlot` writes only the start, so the
    /// block that lands is `task.timelineDurationMinutes` tall — the length the free-time check has
    /// to be made against, and the length the row's own subtitle already advertises.
    private var slots: [Int] {
        context.slots(forDurationMinutes: task.timelineDurationMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                iOSTaskCompletionCircle(isDone: false, tint: rowTint)
                    .frame(width: 13, height: 13)
                    .padding(.top, 3)

                Button {
                    taskInspector(task)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TaskTitleSupport.displayTitle(task.title))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        Text(task.estimatedMinutes > 0 ? estimateLabel : "No estimate")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    taskInspector(task)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim.opacity(0.85))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open task details")
            }

            // 26pt of plate inside a 44pt hit area, the trick `iOSIconButton` and the composer's
            // cancel control already use — the chips are the row's whole point, so they get a
            // finger-sized target without a band of 44pt plates dominating the stack. Expanded
            // vertically only: the chips sit 5pt apart, so a symmetric inset would have made
            // neighbouring targets overlap and the wrong hour win the tap.
            HStack(spacing: 5) {
                ForEach(slots, id: \.self) { startMin in
                    Button {
                        schedule(at: startMin)
                    } label: {
                        Text(TimeFormatters.timeString(from: startMin))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Theme.blue.opacity(0.11))
                            .clipShape(
                                RoundedRectangle(cornerRadius: Theme.radiusControl - 3, style: .continuous)
                            )
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                            .padding(.vertical, -9)
                    }
                    .buttonStyle(.plain)
                    // The same name the row above it draws. This chip had its own fallback —
                    // `task.title.isEmpty ? "task" : task.title` — so an untitled task was
                    // "Untitled Task" on screen and "task" to VoiceOver, two names for one row,
                    // and the fallback also missed a whitespace-only title that `displayTitle`
                    // treats as blank (T-590).
                    .accessibilityLabel("Schedule \(TaskTitleSupport.displayTitle(task.title)) at \(TimeFormatters.timeString(from: startMin))")
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func schedule(at startMin: Int) {
        CadenceTaskDateEditing.setScheduledSlot(
            dateKey: DateFormatters.todayKey(),
            startMin: startMin,
            for: task,
            in: modelContext
        )
    }

    /// **T-601(c). This was `Theme.priorityColor` re-typed, with one case changed.**
    ///
    /// Three of the four arms were the shared function's, and `.none` returned
    /// `Theme.dim.opacity(0.76)` where the shared one returns `Theme.dim`. It reads as taste, so
    /// the history was checked before it was removed rather than after:
    ///
    /// - It arrives whole in `19fbf8b` (2026-06-12), a bulk "refactor macOS task and timeline
    ///   views" commit that says nothing about it, in a row whose `rowTint` fed **two** things —
    ///   this circle and a `strokeBorder(rowTint.opacity(0.22))` around the card.
    /// - `fcc8300` (2026-08-04) deleted that border along with every other hard card border in the
    ///   app. The second consumer went in a sweep about elevation; the 0.76 stayed because nothing
    ///   in that sweep was looking at it.
    /// - Nothing names it. No comment, no test, no sibling: the only other `0.76` in the tree is
    ///   `Theme.surface.opacity(0.76)` on an unrelated macOS popover.
    /// - The same `iOSTaskCompletionCircle` on the board card, the calendar chip and the block
    ///   sheet resolves an unprioritised task through `CadenceTaskCompletionGlyph`, which is
    ///   `Theme.priorityColor(.none)` — full-strength `Theme.dim`. So this row was the only place
    ///   in the app where "no priority" was a *fainter* grey than "no priority" everywhere else.
    ///
    /// A value that outlived its second reader, that nothing explains, and that one surface holds
    /// against nine is drift, not taste. `Theme.dim` is already the muted token; dimming it again
    /// by an unnamed fraction is a second opinion about the same decision.
    private var rowTint: Color {
        Theme.priorityColor(task.priority)
    }

    private var estimateLabel: String {
        "\(CadenceTaskPresentationSupport.estimateLabel(for: task)) estimate"
    }
}

#endif
