#if os(iOS)
import SwiftData
import SwiftUI

struct iOSSchedulePanel: View {
    /// Off in Today's two-pane inspector, where `iPadTodayInspectorSwitcher` is the pane's header
    /// and already has "Timeline" lit up in it. On in the three-pane layout, where this pane sits
    /// beside two others and its header is the only thing naming it.
    var showsHeader = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack(spacing: 0) {
                    iOSPanelHeader(eyebrow: "Schedule", title: "Timeline")
                    Spacer()
                }
                .frame(height: iOSPanelHeaderHeight, alignment: .top)

                Divider().background(Theme.borderSubtle)
            }

            if !untimedTodayTasks.isEmpty {
                iOSScheduleReadyStack(tasks: untimedTodayTasks)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                Divider().background(Theme.borderSubtle.opacity(0.72))
            }

            if let quickCreateStartMin {
                iOSScheduleQuickCreateBar(
                    startMin: quickCreateStartMin,
                    title: $quickCreateTitle,
                    errorMessage: quickCreateError,
                    create: createScheduledTask,
                    cancel: cancelQuickCreate
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

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
                            Text(CadenceTodayPresentationSupport.emptyScheduleHint)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 14)
                        }

                        ForEach(CadenceScheduleSupport.calendarHours, id: \.self) { hour in
                            iOSScheduleHourRow(
                                hour: hour,
                                tasks: tasks(in: hour),
                                bundles: bundles(in: hour),
                                rowHeight: rowHeight,
                                selectedStartMin: quickCreateStartMin,
                                onSelectStart: selectQuickCreateStart
                            )
                            .id(hour)
                        }
                    }
                    .padding(.trailing, horizontalSizeClass == .regular ? 12 : 8)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height
                } action: { _, contentHeight in
                    placeInitialScroll(contentHeight: contentHeight, proxy: proxy)
                }
            }
        }
        .background(Theme.bg)
    }

    private var rowHeight: CGFloat {
        horizontalSizeClass == .regular ? 58 : 48
    }

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
            Text(hourLabel)
                .font(.system(size: rowHeight > 50 ? 11 : 10, weight: .medium))
                .foregroundStyle(isSelectedForCreate ? Theme.blue : Theme.dim.opacity(hour % 3 == 0 ? 0.9 : 0.45))
                .frame(width: rowHeight > 50 ? 50 : 42, alignment: .trailing)
                .padding(.trailing, rowHeight > 50 ? 9 : 7)
                .padding(.top, -6)

            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(isSelectedForCreate ? Theme.blue.opacity(0.58) : Theme.borderSubtle.opacity(hour % 3 == 0 ? 0.55 : 0.25))
                    .frame(height: 1)

                if hasItems {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(bundles) { bundle in
                            iOSScheduleBlock(
                                title: bundle.displayTitle,
                                subtitle: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                                tint: Theme.purple
                            )
                        }

                        ForEach(tasks) { task in
                            iOSScheduleTaskBlock(task: task)
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

private struct iOSScheduleBlock: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint.opacity(0.9))
                .frame(width: 3)
        }
        .cadenceCard(background: tint.opacity(0.18), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }
}

private struct iOSScheduleTaskBlock: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                showDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Untitled Task" : task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                clearTime()
            } label: {
                Image(systemName: "arrow.uturn.left.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.92))
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move \(task.title.isEmpty ? "task" : task.title) back to ready to schedule")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint.opacity(0.9))
                .frame(width: 3)
        }
        .cadenceCard(background: tint.opacity(0.18), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private var tint: Color {
        Color(hex: task.containerColor)
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(
            startMin: task.scheduledStartMin,
            endMin: task.scheduledEndMin
        )
    }

    private func clearTime() {
        CadenceTaskMutationSupport.clearScheduledTime(task, modelContext: modelContext)
    }
}

private struct iOSScheduleReadyStack: View {
    let tasks: [AppTask]

    private var visibleTasks: [AppTask] {
        Array(tasks.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)

                Text("Ready to Schedule")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.7)

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
                    iOSScheduleReadyTaskRow(task: task)
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
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                iOSTaskCompletionCircle(isDone: false, tint: rowTint)
                    .frame(width: 13, height: 13)
                    .padding(.top, 3)

                Button {
                    showDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title.isEmpty ? "Untitled Task" : task.title)
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
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim.opacity(0.85))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open task details")
            }

            HStack(spacing: 5) {
                ForEach(iOSReadyScheduleSlot.defaults) { slot in
                    Button {
                        schedule(at: slot.startMin)
                    } label: {
                        Text(slot.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Theme.blue.opacity(0.11))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schedule \(task.title.isEmpty ? "task" : task.title) at \(slot.accessibilityTime)")
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
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private func schedule(at startMin: Int) {
        CadenceTaskMutationSupport.setScheduledDate(DateFormatters.todayKey(), for: task, modelContext: modelContext)
        CadenceTaskMutationSupport.setScheduledTime(startMin, for: task, modelContext: modelContext)
    }

    private var rowTint: Color {
        switch task.priority {
        case .high:
            return Theme.red
        case .medium:
            return Theme.amber
        case .low:
            return Theme.blue
        case .none:
            return Theme.dim.opacity(0.76)
        }
    }

    private var estimateLabel: String {
        "\(CadenceTaskPresentationSupport.estimateLabel(for: task)) estimate"
    }
}

private struct iOSReadyScheduleSlot: Identifiable {
    let title: String
    let startMin: Int

    var id: Int { startMin }

    var accessibilityTime: String {
        TimeFormatters.timeString(from: startMin)
    }

    static let defaults = [
        iOSReadyScheduleSlot(title: "9 AM", startMin: 9 * 60),
        iOSReadyScheduleSlot(title: "1 PM", startMin: 13 * 60),
        iOSReadyScheduleSlot(title: "4 PM", startMin: 16 * 60)
    ]
}
#endif
