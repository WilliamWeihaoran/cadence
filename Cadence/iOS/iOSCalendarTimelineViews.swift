#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// The live vertical scroll offset of the hour canvas, so the time rail can follow it.
///
/// A reference type rather than `@State` on the grid, and read by nothing except the rail. The
/// offset changes on every frame of a vertical scroll; if the grid's own body read it, every one of
/// those frames would re-evaluate the whole column window. Here only `iOSCalendarTimeRail`
/// observes it, so only the rail redraws.
@Observable
final class iOSCalendarTimelineScrollState {
    var verticalOffset: CGFloat = 0
}

/// The timed calendar grid: an hour rail down the left, a pinned row of day headers across the top,
/// and a day canvas that scrolls in both directions under both of them.
///
/// ## Why the day headers are not `pinnedViews`
///
/// Two things have to stay put on **opposite** axes. The header row must track the columns
/// horizontally and ignore the vertical scroll; the hour rail must track the canvas vertically and
/// ignore the horizontal scroll. `LazyVStack(pinnedViews: .sectionHeaders)` pins along the scroll
/// axis of one scroll view, which answers neither half.
///
/// Nesting two scroll views cannot express it either, and it is worth writing down why, because
/// "just put the header outside the vertical one" is the obvious first move and it is only half a
/// fix. Whichever way round the nesting goes, the inner scroll view's content is *also* inside the
/// outer one:
///
/// - vertical outside, horizontal inside (what this file used to be): the rail is naturally in
///   vertical sync, and the header row scrolls away vertically — the bug.
/// - horizontal outside, vertical inside: the header row is pinned vertically and tracks its
///   columns exactly, and now the rail is stuck inside the horizontal scroller with them.
///
/// There is no arrangement where both are in the scroll view they need and out of the one they do
/// not, so **one of the two has to be a follower**. This takes the second nesting and makes the
/// rail the follower, because the relationship that has to be pixel-exact is a day header sitting
/// over its own column — a header one column out is the wrong date — and that one is exact by
/// construction here: the headers and the canvas are in the same horizontal scroll view. The rail
/// only has to agree about *hours*, it is a fixed 24-row ladder, and it follows a single number.
///
/// The rail is a plain `.offset(y:)` inside a clip rather than a scroll-disabled `ScrollView`,
/// which matters for more than tidiness: this canvas already carries a horizontal scroller, a
/// vertical scroller, a per-column tap and now a pinch, and gesture collisions are this app's most
/// repeated bug. A follower that is not a scroll view adds no fifth recognizer.
struct iOSCalendarTimelineGrid: View {
    /// The column at the leading edge — read as "which day am I looking at", written to jump.
    ///
    /// Both directions, like the Board's `scrolledDayIndex`: scrolling reports the leading day back
    /// up so the toolbar's date button can name it, and setting it scrolls that day to the leading
    /// edge.
    @Binding var leadingDate: Date
    @Binding var selectedDate: Date
    /// How many columns should be on screen — `CadenceCalendarWeekGridLayout.visibleDayCount(for:)`.
    /// It no longer decides how many days *exist*; see `CadenceCalendarTimelineWindow`.
    let visibleDayCount: Int
    let scheduledTasksByDate: [String: [AppTask]]
    let unscheduledTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]
    /// Flat, for resolving a drag payload — the same argument `iOSCalendarBoardPlanner` takes and for
    /// the same reason. The by-day dictionaries above are what the grid *draws*; a drag can cross
    /// columns, so what it *resolves* against has to be the whole set (T-243).
    let allTasks: [AppTask]
    /// A multiplier on the base hour height, 1…3. Written once per pinch, not per frame — see
    /// `pinchZoom`.
    @Binding var zoom: Double
    let onCreateAt: (String, Int) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    // The same two `calendar.workHours.*.v1` keys macOS's `TimelineDayCanvas` reads. Read once
    // here rather than per day column, so a fourteen-day span installs one observer, not fourteen.
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey)
    private var workHoursStartMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey)
    private var workHoursEndMinute = CalendarWorkHoursPreferences.defaultEndMinute
    /// Vertical placement of the day canvas. See `placeInitialScroll(contentHeight:)`.
    @State private var verticalScrollPosition = ScrollPosition(edge: .top)
    @State private var horizontalScrollPosition = ScrollPosition(edge: .leading)
    @State private var didPlaceInitialScroll = false
    @State private var didPlaceInitialColumn = false
    /// Set by the first report that agrees with the placement — see `adoptLeadingColumn`. Separate
    /// from `didPlaceInitialColumn`, which says the scroll was *requested*: that one gates the
    /// programmatic jumps, this one gates believing what comes back.
    @State private var didConfirmInitialColumn = false
    @State private var scrollState = iOSCalendarTimelineScrollState()
    /// The rendered run of day columns. Rebuilt only when a scroll approaches an end of it.
    @State private var windowStart: Date?
    @State private var leadingIndex = 0
    /// Latches a `leadingDate` write this view made itself, so the change coming back does not
    /// re-scroll the grid under the finger that caused it. The Board carries the same latch.
    @State private var isReportingLeadingDate = false
    /// The zoom *during* a pinch. `zoom` is `@AppStorage`-backed two views up, and writing a
    /// defaults key sixty times a second is not a thing to do to a gesture — so the live value
    /// lives here and is committed once, on `onEnded`.
    @State private var pinchZoom: Double?
    @State private var pinchStartZoom: Double = CadenceCalendarZoom.defaultZoom
    @State private var pinchStartOffset: CGFloat = 0

    private let calendar = Calendar.current
    /// Read for the two figures that are still about the pane — the hour rail's width and how wide a
    /// day column would like to be — and for nothing the grid draws itself. Everything else comes
    /// from `iOSCalendarTimelineMetrics`, which takes no width.
    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var baseHourHeight: CGFloat { iOSCalendarTimelineMetrics.hourHeight }
    private var effectiveZoom: Double { CadenceCalendarZoom.clamp(pinchZoom ?? zoom) }
    private var hourHeight: CGFloat {
        CadenceCalendarZoom.hourHeight(base: baseHourHeight, zoom: effectiveZoom)
    }
    private var dayHeaderHeight: CGFloat {
        iOSCalendarTimelineMetrics.dayHeaderHeight
    }
    private var timelineHeight: CGFloat {
        CGFloat(CadenceScheduleSupport.calendarHourCount) * hourHeight
    }
    private var activeWindowStart: Date {
        windowStart ?? CadenceCalendarTimelineWindow.windowStart(for: leadingDate, calendar: calendar)
    }
    /// The index `leadingDate` sits at in the window as it currently stands. Re-read every pass, so
    /// the one-shot placement below uses the date at first layout rather than one from `init`.
    private var targetIndex: Int {
        CadenceCalendarTimelineWindow.index(for: leadingDate, windowStart: activeWindowStart, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geo in
            // Seven columns on screen is the guarantee; 112pt is the wish. See
            // `CadenceCalendarWeekGridLayout` — this used to be a `max(…, 112)` that made the wish
            // the guarantee and put the last day or two behind a horizontal scroller. The count
            // divided into is the *visible* one now, which is what makes the width fixed and the
            // grid scrollable past it.
            let railWidth = CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: isRegularWidth)
            let availableWidth = max(geo.size.width - railWidth, 1)
            let colWidth = CadenceCalendarWeekGridLayout.dayColumnWidth(
                availableWidth: availableWidth,
                dayCount: visibleDayCount,
                isRegularWidth: isRegularWidth
            )
            let contentWidth = colWidth * CGFloat(CadenceCalendarTimelineWindow.renderDayCount)
            let canvasHeight = max(geo.size.height - dayHeaderHeight, 1)

            HStack(alignment: .top, spacing: 0) {
                iOSCalendarTimeRail(
                    hourHeight: hourHeight,
                    headerHeight: dayHeaderHeight,
                    viewportHeight: canvasHeight,
                    scrollState: scrollState
                )
                .frame(width: railWidth)

                gridScroller(colWidth: colWidth, contentWidth: contentWidth, canvasHeight: canvasHeight)
            }
            // On the container, not on the scroll views, and `simultaneousGesture` rather than
            // `highPriorityGesture`. A magnification gesture needs two fingers, so it can never
            // claim a one-finger pan or a tap; attaching it here means it also never has to be
            // handed *through* a scroll view, which is where the app's previous gesture bugs came
            // from — a recognizer that begins where it has nothing to do
            // (`renderedBlockTap`, 64218d1) or delays the touches of everything under it
            // (`.draggable` on the sidebar).
            .simultaneousGesture(
                pinch(viewportHeight: canvasHeight, headerHeight: dayHeaderHeight)
            )
            .onChange(of: colWidth) { _, newWidth in
                // A rotation or a sidebar fold changes the column width under a scroll offset that
                // was measured in the old one. Without this the leading column silently becomes a
                // different day.
                horizontalScrollPosition.scrollTo(
                    x: CadenceCalendarTimelineWindow.scrollOffsetX(forIndex: leadingIndex, columnWidth: newWidth)
                )
            }
        }
        .background(Theme.bg)
        .onAppear { alignWindow(to: leadingDate) }
        .onChange(of: leadingDate) { _, newDate in
            if isReportingLeadingDate {
                isReportingLeadingDate = false
                return
            }
            alignWindow(to: newDate, animated: true)
        }
    }

    /// Drop a block on a block and the two become one — the gesture macOS's `TimelineDayCanvas` has
    /// had all along, and which T-190 could only give iOS's Calendar *Board* because this file had
    /// no drag mesh at all (T-243).
    ///
    /// **One line, and it must stay one line.** `CadenceTaskMutationSupport.insertBundle(from:adding:)`
    /// is the single implementation of "two tasks become a block"; `SchedulingActions.createBundle`
    /// is a delegation to it and `iOSCalendarBoardPlanner.formBundle` is this same call. A second
    /// body here would be the fourth spelling of the thing T-190 existed to unify.
    private func formBundle(from target: AppTask, adding dragged: AppTask) {
        _ = CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: modelContext)
    }

    private func gridScroller(colWidth: CGFloat, contentWidth: CGFloat, canvasHeight: CGFloat) -> some View {
        let range = CadenceCalendarTimelineWindow.renderedIndexRange(
            leadingIndex: leadingIndex,
            visibleDayCount: visibleDayCount
        )

        return ScrollView(.horizontal) {
            VStack(spacing: 0) {
                // The pinned row. It is inside this scroll view — which is what makes it track its
                // columns exactly — and outside the vertical one below, which is what makes it stay.
                ZStack(alignment: .topLeading) {
                    ForEach(range, id: \.self) { index in
                        let date = date(at: index)
                        iOSCalendarTimelineDayHeader(
                            date: date,
                            unscheduledTasks: items(unscheduledTasksByDate, on: date),
                            eventCount: items(eventsByDate, on: date).count,
                            bundleCount: items(bundlesByDate, on: date).count,
                            taskCount: items(scheduledTasksByDate, on: date).count
                        ) {
                            selectedDate = date
                        }
                        .frame(width: colWidth)
                        .offset(x: CGFloat(index) * colWidth)
                    }
                }
                // No background on this row and none on the canvas below: the frame is
                // `contentWidth` wide — 47,000pt at a week's column width — and a filled view that
                // wide is one CALayer past every sane texture bound. Each day header paints its
                // own `Theme.surface`, and the window always covers the viewport with margin to
                // spare, so nothing unpainted is ever on screen.
                .frame(width: contentWidth, height: dayHeaderHeight, alignment: .topLeading)

                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        ForEach(range, id: \.self) { index in
                            let date = date(at: index)
                            let key = DateFormatters.dateKey(from: date)
                            iOSCalendarTimelineDayColumn(
                                date: date,
                                tasks: CadenceScheduleSupport.items(on: key, in: scheduledTasksByDate),
                                bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
                                events: CadenceScheduleSupport.items(on: key, in: eventsByDate),
                                allTasks: allTasks,
                                colWidth: colWidth,
                                hourHeight: hourHeight,
                                workHoursStartMinute: workHoursStartMinute,
                                workHoursEndMinute: workHoursEndMinute,
                                onCreateAt: onCreateAt,
                                onFormBundleFromTasks: formBundle(from:adding:)
                            )
                            .offset(x: CGFloat(index) * colWidth)
                        }
                    }
                    .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
                }
                .frame(height: canvasHeight)
                .scrollIndicators(.hidden)
                .scrollPosition($verticalScrollPosition)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    scrollState.verticalOffset = offset
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height
                } action: { _, contentHeight in
                    placeInitialScroll(contentHeight: contentHeight)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($horizontalScrollPosition)
        // `Int`, deliberately, not the raw offset: `onScrollGeometryChange` only runs its action
        // when the transformed value *changes*, so reducing the offset to a column index here means
        // the state below is written once per column crossed rather than once per frame.
        .onScrollGeometryChange(for: Int.self) { geometry in
            CadenceCalendarTimelineWindow.leadingIndex(
                scrollOffsetX: geometry.contentOffset.x,
                columnWidth: colWidth
            )
        } action: { _, index in
            adoptLeadingColumn(index)
        }
        // The same rule `CadenceLazyScrollAnchor` states for lazy stacks, applied to an offset
        // rather than an id: a scroll asserted before the content has a width lands nowhere, and
        // nothing reports it, because nothing failed. `ecaf80f` is what that costs.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.width
        } action: { _, extent in
            placeInitialColumn(contentWidth: extent, colWidth: colWidth)
        }
    }

    // MARK: - Pinch

    /// Continuous 1×–3× on the time axis.
    ///
    /// Anchored to the fingers: `startAnchor` is a unit point in this container, so the content
    /// point held at the start of the gesture is put back under the same place on screen after the
    /// scale — otherwise pinching near the bottom of a 24-hour canvas walks the visible hour away
    /// from the one being pinched. The arithmetic is `CadenceCalendarZoom.anchoredVerticalOffset`,
    /// and it is computed from the state captured at gesture start rather than from the previous
    /// frame, so a slow pinch cannot accumulate rounding into a drift.
    private func pinch(viewportHeight: CGFloat, headerHeight: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchZoom == nil {
                    pinchStartZoom = CadenceCalendarZoom.clamp(zoom)
                    pinchStartOffset = scrollState.verticalOffset
                }
                let startHeight = CadenceCalendarZoom.hourHeight(base: baseHourHeight, zoom: pinchStartZoom)
                let newZoom = CadenceCalendarZoom.zoom(startingFrom: pinchStartZoom, magnification: value.magnification)
                let newHeight = CadenceCalendarZoom.hourHeight(base: baseHourHeight, zoom: newZoom)
                pinchZoom = newZoom

                let focusY = max(0, value.startAnchor.y * (viewportHeight + headerHeight) - headerHeight)
                verticalScrollPosition.scrollTo(
                    y: CadenceCalendarZoom.anchoredVerticalOffset(
                        currentOffset: pinchStartOffset,
                        focusY: focusY,
                        scale: newHeight / max(startHeight, 1),
                        contentHeight: CGFloat(CadenceScheduleSupport.calendarHourCount) * newHeight,
                        viewportHeight: viewportHeight
                    )
                )
            }
            .onEnded { _ in
                if let pinchZoom { zoom = pinchZoom }
                pinchZoom = nil
            }
    }

    // MARK: - Window and scroll placement

    private func date(at index: Int) -> Date {
        CadenceCalendarTimelineWindow.date(at: index, windowStart: activeWindowStart, calendar: calendar)
    }

    private func items<Item>(_ source: [String: [Item]], on date: Date) -> [Item] {
        CadenceScheduleSupport.items(on: DateFormatters.dateKey(from: date), in: source)
    }

    /// Rebuilds the rendered run around `date` and puts that day at the leading edge.
    ///
    /// It does **not** scroll before `placeInitialColumn` has run, and that is the whole of what
    /// keeps this surface out of `ecaf80f`. The column width is only known inside `GeometryReader`,
    /// so before first layout `lastColumnWidth` is a placeholder; a jump computed from it lands at
    /// an arbitrary offset, the geometry reader reports *that* offset as a leading column, and the
    /// reading gets written back into `leadingDate` as though the user had scrolled there. It did
    /// exactly that on the first build of this change: Week opened on the window's first day —
    /// seven months behind the anchor, the same distance and the same cause as the Board's bug.
    private func alignWindow(to date: Date, animated: Bool = false) {
        let start = CadenceCalendarTimelineWindow.windowStart(for: date, calendar: calendar)
        let target = CadenceCalendarTimelineWindow.index(for: date, windowStart: start, calendar: calendar)
        windowStart = start
        leadingIndex = target
        guard didPlaceInitialColumn else { return }
        scrollToLeadingIndex(animated: animated)
    }

    private func scrollToLeadingIndex(animated: Bool) {
        // The jump is an offset rather than an id: there is no lazy stack to resolve an id against
        // — the columns are windowed by hand — so index × width *is* the position.
        let apply = {
            horizontalScrollPosition.scrollTo(
                x: CadenceCalendarTimelineWindow.scrollOffsetX(
                    forIndex: leadingIndex,
                    columnWidth: lastColumnWidth
                )
            )
        }
        if animated {
            withAnimation(.snappy(duration: 0.22), apply)
        } else {
            apply()
        }
    }

    /// The most recent column width, captured so a programmatic jump outside `GeometryReader` can
    /// convert an index into an offset. Written from the geometry pass below.
    @State private var lastColumnWidth: CGFloat = 1

    private func adoptLeadingColumn(_ index: Int) {
        // Nothing the scroll view says about its position is trustworthy until this view has
        // asserted one *and seen that assertion come back*. Before the assertion the offset is
        // whatever the layout happened to start at; between the assertion and its arrival the
        // reports still in flight say the same thing, and `didPlaceInitialColumn` alone let those
        // through. That is T-70: the stale reading is column 0 — the window's first day,
        // `plannerLeadingDayCount` behind the anchor — so Week opened on Jan 18 against a real date
        // of Aug 17. Worse than a wrong frame, because `recenterWindowIfNeeded` then rebuilt the
        // window around the bogus day and scrolled to it, which is how a race became a resting
        // place. See `CadenceLazyScrollAnchor.report`; Month's grid carries the same gate.
        guard didPlaceInitialColumn else { return }
        switch CadenceLazyScrollAnchor.report(
            index,
            target: leadingIndex,
            hasConfirmedPlacement: didConfirmInitialColumn
        ) {
        case .ignore:
            return
        case .confirmsPlacement:
            didConfirmInitialColumn = true
            return
        case .adopt:
            break
        }

        guard index != leadingIndex else { return }
        leadingIndex = index
        let date = date(at: index)
        if !calendar.isDate(date, inSameDayAs: leadingDate) {
            isReportingLeadingDate = true
            leadingDate = date
        }
        recenterWindowIfNeeded(leadingIndex: index, leadingDate: date)
    }

    /// Slides the rendered run along when a scroll approaches either end of it, which is what makes
    /// "infinite" true rather than merely large. Same threshold and no-op guard as the Board.
    private func recenterWindowIfNeeded(leadingIndex index: Int, leadingDate date: Date) {
        guard let start = CadenceCalendarTimelineWindow.recenteredWindowStart(
            leadingIndex: index,
            leadingDate: date,
            currentWindowStart: activeWindowStart,
            calendar: calendar
        ) else { return }

        let recenteredIndex = CadenceCalendarTimelineWindow.index(
            for: date,
            windowStart: start,
            calendar: calendar
        )
        windowStart = start
        leadingIndex = recenteredIndex
        scrollToLeadingIndex(animated: false)
    }

    private func placeInitialColumn(contentWidth: CGFloat, colWidth: CGFloat) {
        lastColumnWidth = colWidth
        guard CadenceLazyScrollAnchor.shouldAssert(
            hasAsserted: didPlaceInitialColumn,
            hasTarget: true,
            contentExtent: contentWidth
        ) else { return }
        didPlaceInitialColumn = true
        leadingIndex = targetIndex
        horizontalScrollPosition.scrollTo(
            x: CadenceCalendarTimelineWindow.scrollOffsetX(forIndex: targetIndex, columnWidth: colWidth)
        )
    }

    /// Opens the timeline near the hour that matters instead of at the top of the canvas — which is
    /// midnight now that the grid draws the whole day. See
    /// `CadenceScheduleSupport.initialTimelineHour` for the rule; this is only where it is applied.
    ///
    /// It runs off the scroll view's own reported content height rather than `onAppear` because
    /// `onAppear` can fire before the canvas has a content size, and a `scrollTo(y:)` against a
    /// zero-height content silently clamps back to the top — which is exactly the placement this
    /// removes. Nothing here is written anywhere: the hour is recomputed on every open, so a bad
    /// placement can only ever be one screen, never a saved anchor that compounds.
    ///
    /// The header no longer scrolls past, so there is no `topInset` to skip either.
    private func placeInitialScroll(contentHeight: CGFloat) {
        guard !didPlaceInitialScroll, contentHeight >= timelineHeight else { return }
        didPlaceInitialScroll = true

        let showsToday = CadenceCalendarTimelineWindow.eventWindowDates(
            leadingDate: leadingDate,
            calendar: calendar
        ).contains { calendar.isDateInToday($0) }

        let hour = CadenceScheduleSupport.initialTimelineHour(
            showsToday: showsToday,
            workHoursStartMinute: workHoursStartMinute,
            calendar: calendar
        )
        verticalScrollPosition.scrollTo(
            y: CadenceScheduleSupport.timelineScrollOffset(forHour: hour, hourHeight: hourHeight)
        )
    }
}

/// The band over one day column.
///
/// It carries **no selection state**. Tapping a header still sets the calendar's selected day — the
/// day inspector beside a wide-enough Week pane is what reads it — but nothing on the grid lights up
/// for it any more. A grid of seven columns is a span you are looking at, not a list you pick from,
/// and the blue-on-blue "selected" tint sat a shade away from the "today" tint next to it, so the
/// two were told apart mostly by knowing which was which.
private struct iOSCalendarTimelineDayHeader: View {
    let date: Date
    let unscheduledTasks: [AppTask]
    let eventCount: Int
    let bundleCount: Int
    let taskCount: Int
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VStack(spacing: iOSCalendarTimelineMetrics.dayLabelSpacing) {
                    // `MON`, at the band's shared figures. The size arrives through
                    // `iOSCalendarTimelineMetrics`, which forwards it; the kerning is named here
                    // because there was never an iOS metric for it to forward — the modifier was
                    // simply absent, which is the half of the fork macOS had right and this side
                    // did not. Every uppercased short label in Cadence is kerned. T-277.
                    Text(DateFormatters.dayOfWeek.string(from: date).uppercased())
                        .font(.system(size: iOSCalendarTimelineMetrics.weekdaySize, weight: .semibold))
                        .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                        .kerning(CadenceCalendarWeekdayHeaderMetrics.labelKerning)
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: iOSCalendarTimelineMetrics.dayNumberSize, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Theme.onColor : Theme.text)
                        .frame(
                            width: iOSCalendarTimelineMetrics.dayCircleSize,
                            height: iOSCalendarTimelineMetrics.dayCircleSize
                        )
                        .background(isToday ? Theme.blue : Color.clear)
                        .clipShape(Circle())
                }
                .frame(height: iOSCalendarTimelineMetrics.dateBlockHeight)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(unscheduledTasks.prefix(2)) { task in
                        iOSCalendarMiniChip(
                            title: task.title.isEmpty ? "Untitled" : task.title,
                            icon: "circle.fill",
                            color: Color(hex: task.containerColor)
                        )
                    }

                    if taskCount + bundleCount + eventCount > 0 {
                        iOSCalendarMiniChip(
                            title: "\(taskCount + bundleCount + eventCount) timed",
                            icon: "clock.fill",
                            color: Theme.blue
                        )
                    }

                    if unscheduledTasks.count > 2 {
                        Text("+ \(unscheduledTasks.count - 2) more")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.subdued)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: iOSCalendarTimelineMetrics.previewMinHeight,
                    alignment: .topLeading
                )
                .padding(.horizontal, iOSCalendarTimelineMetrics.previewInset)
                .padding(.bottom, iOSCalendarTimelineMetrics.previewInset)
            }
            .frame(height: iOSCalendarTimelineMetrics.dayHeaderHeight)
            .background(isToday ? Theme.blue.opacity(0.035) : Theme.surface)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(DateFormatters.longDate.string(from: date))
    }
}

/// The hour ladder down the left: horizontally pinned by living outside the horizontal scroller,
/// vertically a follower of the hour canvas.
///
/// The `.offset(y:)` is driven by `iOSCalendarTimelineScrollState`, which only this view reads —
/// so a vertical scroll redraws the rail and nothing else. See the note on `iOSCalendarTimelineGrid`
/// for why one of the two pinned things has to be a follower and why it is this one.
private struct iOSCalendarTimeRail: View {
    let hourHeight: CGFloat
    let headerHeight: CGFloat
    let viewportHeight: CGFloat
    let scrollState: iOSCalendarTimelineScrollState

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerHeight)

            VStack(spacing: 0) {
                ForEach(CadenceScheduleSupport.calendarHours, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.system(size: iOSCalendarTimelineMetrics.hourLabelSize, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(hour % 3 == 0 ? 0.9 : 0.45))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: hourHeight, alignment: .top)
                        .padding(.trailing, iOSCalendarTimelineMetrics.hourLabelTrailingInset)
                }
            }
            .frame(height: CGFloat(CadenceScheduleSupport.calendarHourCount) * hourHeight, alignment: .top)
            .offset(y: -scrollState.verticalOffset)
            .frame(height: viewportHeight, alignment: .top)
            .clipped()
        }
        .background(Theme.bg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.75))
                .frame(width: 0.5)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

/// One day column's own hour lines and trailing rule.
///
/// These used to be drawn once across the whole canvas — one rectangle per hour, spanning every
/// column. That was fine for a seven-day canvas and is not for a scrolling one: at a week's column
/// width the content is over 47,000pt wide, and a single rectangle that wide is a layer past any
/// texture bound. Each column drawing its own lines also means the lines are windowed with the
/// column, so nothing is built for a day that is nowhere near the screen.
private struct iOSCalendarTimelineColumnGridLines: View {
    let colWidth: CGFloat
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...CadenceScheduleSupport.calendarHourCount, id: \.self) { index in
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(index % 3 == 0 ? 0.46 : 0.20))
                    .frame(width: colWidth, height: 0.5)
                    .offset(y: CGFloat(index) * hourHeight)
            }
        }
        .frame(width: colWidth, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.34))
                .frame(width: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct iOSCalendarTimelineDayColumn: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]
    /// Every task in the store, for resolving a drag payload. Not `tasks`: the grid renders a window
    /// of days side by side, so a block can legitimately be dragged from one column onto another,
    /// and a lookup confined to this column's own day would drop exactly those releases.
    let allTasks: [AppTask]
    let colWidth: CGFloat
    let hourHeight: CGFloat
    let workHoursStartMinute: Int
    let workHoursEndMinute: Int
    let onCreateAt: (String, Int) -> Void
    /// `(target, dragged)` — the argument order `CadenceTaskMutationSupport.insertBundle(from:adding:)`
    /// takes, so the block that was dropped *on* stays the one that supplies the slot. Same spelling
    /// as `iOSCalendarBoardDayColumn`'s.
    let onFormBundleFromTasks: (AppTask, AppTask) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            onCreateAt(DateFormatters.dateKey(from: date), minute(for: value.location.y))
                        }
                )

            iOSCalendarTimelineColumnGridLines(colWidth: colWidth, hourHeight: hourHeight)

            workHoursBand

            dayWash

            ForEach(bundles) { bundle in
                iOSTimelineBundleBlock(bundle: bundle)
                    .frame(width: colWidth - 14, height: blockHeight(start: bundle.startMin, end: bundle.endMin))
                    .offset(x: 7, y: yOffset(for: bundle.startMin))
            }

            ForEach(timedEvents, id: \.calendarItemIdentifier) { event in
                // The column's own day, so an event that crosses midnight draws the part that
                // belongs here. `frame` uses the range clamped into the drawn hours; the block
                // still labels itself with the true one.
                let range = iOSCalendarEventSupport.minuteRange(for: event, on: date)
                let drawn = CadenceScheduleSupport.timelineVisibleRange(start: range.start, end: range.end)
                iOSCalendarEventBlock(event: event, startMin: range.start, endMin: range.end)
                    .frame(width: colWidth - 18, height: blockHeight(start: drawn.start, end: drawn.end))
                    .offset(x: 9, y: yOffset(for: drawn.start))
            }

            ForEach(tasks) { task in
                let range = CadenceScheduleSupport.blockRange(
                    startMinute: task.scheduledStartMin,
                    fallbackDuration: task.estimatedMinutes
                )
                iOSTimelineTaskBlock(
                    task: task,
                    startMin: range.start,
                    endMin: range.end,
                    bundleFormingDrop: bundleFormingDrop(onto: task)
                )
                .frame(width: colWidth - 18, height: blockHeight(start: range.start, end: range.end))
                .offset(x: 9, y: yOffset(for: range.start))
            }
        }
        .frame(width: colWidth, height: timelineHeight, alignment: .topLeading)
    }

    /// The same guard the Calendar Board's card makes, for the same reason and against the same
    /// shared mutation: a block is `dateKey` **plus** `startMin`, and
    /// `CadenceTaskMutationSupport.insertBundle(from:adding:)` returns `nil` for a target with
    /// neither — so a block that cannot supply a slot declines rather than lighting up amber and
    /// then silently doing nothing.
    ///
    /// On this surface the guard is very nearly a tautology, and that is the point of writing it
    /// anyway: every block drawn here comes from `CadenceScheduleSupport.tasksByScheduledDate`, so it
    /// has a slot by construction. The guard states the requirement locally instead of resting on a
    /// query two files away that could reasonably be widened — the "do-dated-only card" the Board
    /// declines is exactly what a widened query would send here.
    ///
    /// It does **not** pass `onTargetedChanged`. This column has no `dropDestination` of its own for
    /// a nested block to shadow, so there is no second reading of the release to suppress, and none
    /// of the Board's `nestedDropTargetID` / `recentlyBundledTaskID` machinery is needed here.
    private func bundleFormingDrop(onto task: AppTask) -> iOSBundleFormingDrop? {
        guard task.scheduledStartMin >= 0 else { return nil }
        return iOSBundleFormingDrop(
            allTasks: allTasks,
            onDropTask: { dragged in onFormBundleFromTasks(task, dragged) }
        )
    }

    /// The today tint, drawn over the whole column.
    ///
    /// Today only. There used to be a second, near-identical wash for the *selected* day; the
    /// selection no longer shows on this grid at all — see `iOSCalendarTimelineDayHeader`.
    ///
    /// `.allowsHitTesting(false)` is load-bearing, not decoration. This wash sits above the clear
    /// `Rectangle` that carries the drag-to-create `SpatialTapGesture`, and a filled `Shape` is
    /// hit-testable across its whole path however low its opacity — so without this, tapping an
    /// empty slot on *today's* column did nothing at all, on the one column a user is most likely
    /// to tap. Every other day worked, which made it read as a flaky control rather than a missing
    /// one. `workHoursBand` below has always opted out for the same reason.
    @ViewBuilder
    private var dayWash: some View {
        if Calendar.current.isDateInToday(date) {
            Rectangle()
                .fill(Theme.blue.opacity(0.025))
                .frame(width: colWidth, height: timelineHeight)
                .allowsHitTesting(false)
        }
    }

    /// The work-hours emphasis macOS's `TimelineWorkHoursHighlightLayer` draws, on the same shared
    /// preference and the same weekend rule. The band's extent comes from
    /// `CalendarWorkHoursPreferences`; only the minute → Y conversion is local, and it is this
    /// view's own `yOffset` — the one every block on this column already uses — so the band cannot
    /// drift away from the blocks it sits behind.
    @ViewBuilder
    private var workHoursBand: some View {
        if CalendarWorkHoursPreferences.shouldShowHighlight(on: date),
           let frame = CalendarWorkHoursPreferences.highlightFrame(
               startMinute: workHoursStartMinute,
               endMinute: workHoursEndMinute,
               timelineStartHour: CadenceScheduleSupport.calendarStartHour,
               timelineEndHour: CadenceScheduleSupport.calendarEndHour,
               yOffset: { yOffset(for: $0) }
           ) {
            Rectangle()
                .fill(Theme.amber.opacity(0.026))
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.amber.opacity(0.055)).frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.amber.opacity(0.045)).frame(height: 1)
                }
                .frame(width: colWidth, height: frame.height)
                .offset(y: frame.y)
                .allowsHitTesting(false)
        }
    }

    private var timelineHeight: CGFloat {
        CGFloat(CadenceScheduleSupport.calendarHourCount) * hourHeight
    }

    private var timedEvents: [EKEvent] {
        events.filter { !$0.isAllDay }
    }

    private func yOffset(for minute: Int) -> CGFloat {
        yOffset(for: CGFloat(minute))
    }

    private func yOffset(for minute: CGFloat) -> CGFloat {
        (minute - CGFloat(CadenceScheduleSupport.calendarStartHour * 60)) / 60.0 * hourHeight
    }

    private func blockHeight(start: Int, end: Int) -> CGFloat {
        max(24, CGFloat(end - start) / 60.0 * hourHeight - 4)
    }

    private func minute(for yPosition: CGFloat) -> Int {
        let rawMinute = CadenceScheduleSupport.calendarStartHour * 60 + Int((max(0, yPosition) / hourHeight) * 60)
        let snapped = (rawMinute / 15) * 15
        let minimum = CadenceScheduleSupport.calendarStartHour * 60
        let maximum = CadenceScheduleSupport.calendarEndHour * 60 - 15
        return min(max(snapped, minimum), maximum)
    }
}

/// A timeline event block: a solid plate of the calendar's own colour, exactly as on macOS.
///
/// The label colours are `CadenceCalendarEventStyle`'s tiers rather than `Theme.text` at hand-picked
/// alphas. That matters here more than anywhere else on the surface: the plate is solved to a fixed
/// luminance *so that* `Theme.onColor` and `onColorSecondary` clear AA on top of it, and
/// `Theme.text.opacity(0.7)` was quietly opting out of that guarantee.
private struct iOSCalendarEventBlock: View {
    let event: EKEvent
    let startMin: Int
    let endMin: Int

    private var fill: Color {
        iOSCalendarEventSupport.fillColor(for: event.calendar)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CadenceCalendarEventStyle.tertiaryLabelColor())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(iOSCalendarEventSupport.title(for: event))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CadenceCalendarEventStyle.primaryLabelColor)
                    .lineLimit(2)

                Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CadenceCalendarEventStyle.secondaryLabelColor())
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .strokeBorder(
                    iOSCalendarEventSupport.color(for: event.calendar)
                        .opacity(CadenceCalendarEventStyle.chipBorderOpacity()),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}

/// The **one** task block on a timed grid: the Calendar screen's day columns and Today's schedule
/// pane. Neutral plate, a wash of the list's colour, and a square-edged strip of that colour on the
/// leading edge — the same vocabulary `iOSBoardTaskCard` speaks on the boards.
///
/// It replaced a second block in `iPadTodayScheduleViews` that was a tint-washed, fully-rounded,
/// shadowed card with a pill strip and no completion circle, so the same scheduled task changed
/// species between two screens that both exist to show its schedule.
struct iOSTimelineTaskBlock: View {
    @Bindable var task: AppTask
    let startMin: Int
    let endMin: Int
    /// The Calendar grid positions every block and hands it an exact height, so the block must fill
    /// what it is given. Today's pane stacks blocks inside an hour row that sizes to its content,
    /// where an infinite max height lets one block swallow the row.
    var fillsAvailableHeight: Bool = true
    /// Today's pane keeps a "back to Ready to Schedule" control on the block, because the stack it
    /// would go back to is a few points above it on the same pane. The Calendar grid has no such
    /// stack, so it passes `nil` — an absent control, not a disabled one.
    var onClearTime: (() -> Void)? = nil
    /// Non-`nil` only on a surface that can turn two blocks into one: the Calendar screen's day
    /// columns. Today's schedule pane passes `nil` and is byte-for-byte unchanged — it stacks its
    /// blocks inside hour rows rather than positioning them on a canvas, and it already spends the
    /// block's trailing corner on `onClearTime`.
    ///
    /// **It gates the drag as well as the drop**, which is why one optional covers both halves of a
    /// gesture: a lift that no sibling can accept is an affordance that does nothing, and this block
    /// sits inside two nested scroll views and under a `simultaneousGesture` pinch — the last place
    /// to install a recognizer speculatively. See T-243.
    var bundleFormingDrop: iOSBundleFormingDrop? = nil
    // T-201: the page's `iOSTaskInspectorHost` presents, not this block. Both hosts of this block
    // rebuild their grid from a query keyed on the day and the slot, so completing or cancelling a
    // task from inside the panel dropped the block and the panel with it.
    @Environment(\.iOSTaskInspector) private var taskInspector
    @State private var isBundleFormingTargeted = false

    private var listColor: Color {
        Color(hex: task.containerColor)
    }

    /// Square on the leading edge so the list colour strip reads as a strip, rounded elsewhere.
    private var blockShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: Theme.radiusControl,
            topTrailingRadius: Theme.radiusControl,
            style: .continuous
        )
    }

    /// T-243. `.draggable` and `.dropDestination` are attached in an `if let` branch rather than
    /// always-on-returning-`false`, for the two reasons `iOSBoardTaskCard` already documents and one
    /// that is specific to this surface:
    ///
    /// - `isTargeted` fires whether or not the closure accepts the drop, so an always-attached
    ///   version would light up blocks on Today's pane, which has nothing to bundle them with;
    /// - `.dropDestination` has no erased form, so the choice cannot be a ternary at the call site;
    /// - and the file's own note about `.draggable` "delaying the touches of everything under it"
    ///   is about *installing recognizers*, so the honest response is to install none where the
    ///   gesture is not offered. `bundleFormingDrop` is fixed per call site, so this branch never
    ///   flips at runtime.
    ///
    /// **The pinch and the lift coexist, and it is worth saying why rather than only that they do.**
    /// `iOSCalendarTimelineGrid` carries `MagnifyGesture` as a `simultaneousGesture` on the
    /// container. A magnification needs two fingers; a `UIDragInteraction` lift needs one finger held
    /// still for ~350ms. Neither can begin in the other's territory, and a one-finger pan that moves
    /// immediately is still a scroll, because the lift recognizer's slop is broken by the first
    /// movement. What the sidebar bug was actually about — `.draggable` delaying *taps* — does not
    /// arise either: the block's tap is a `Button`, and the drag interaction defers a touch only
    /// until its long-press threshold fails.
    var body: some View {
        if let drop = bundleFormingDrop {
            block
                .draggable(TaskDragPayload.string(for: task.id))
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first,
                          let taskID = TaskDragPayload.taskID(from: payload),
                          taskID != task.id,
                          let dragged = drop.allTasks.first(where: { $0.id == taskID }) else { return false }
                    drop.onDropTask(dragged)
                    return true
                } isTargeted: { targeted in
                    isBundleFormingTargeted = targeted
                    drop.onTargetedChanged(targeted)
                }
        } else {
            block
        }
    }

    private var block: some View {
        Button {
            taskInspector(task)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                iOSTaskCompletionCircle(glyph: .resolve(task: task))
                    .frame(width: 11, height: 11)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                    Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            // Clears the trailing control when there is one, so a two-line title cannot run under it.
            .padding(.trailing, onClearTime == nil ? 0 : 26)
            .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
            .background {
                ZStack {
                    blockShape.fill(Theme.surfaceElevated.opacity(0.82))
                    blockShape.fill(listColor.opacity(task.isDone ? 0.05 : 0.12))
                    if isBundleFormingTargeted {
                        blockShape.fill(Theme.amber.opacity(0.16))
                    }
                }
            }
            .clipShape(blockShape)
            // One layer, one radius: the targeted state re-tints the border this block already
            // draws rather than adding a second ring. Amber for the reason `iOSBoardTaskCard` gives
            // — `iOSTimelineBundleBlock` is amber at this same weight, so a block about to *become*
            // one says so in the colour it is about to take.
            .overlay {
                blockShape.strokeBorder(
                    isBundleFormingTargeted ? Theme.amber.opacity(0.74) : Theme.borderSubtle,
                    lineWidth: isBundleFormingTargeted ? 1.5 : 1
                )
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(listColor)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.iosPressable)
        .overlay(alignment: .topTrailing) { clearTimeControl }
    }

    /// A sibling of the block's own button rather than a child of it: nesting a `Button` inside
    /// another `Button`'s label gives the inner one no reliable hit test on iOS.
    @ViewBuilder
    private var clearTimeControl: some View {
        if let onClearTime {
            Button(action: onClearTime) {
                Image(systemName: "arrow.uturn.left.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(listColor.opacity(0.92))
                    .frame(width: 22, height: 22)
                    .background(listColor.opacity(0.12))
                    .clipShape(Circle())
                    .iOSExpandedHitArea(8)
            }
            .buttonStyle(.iosPressable)
            .padding(.top, 4)
            .padding(.trailing, 5)
            .accessibilityLabel("Move \(task.title.isEmpty ? "task" : task.title) back to ready to schedule")
        }
    }
}

/// The **one** bundle block on a timed grid, shared by the Calendar screen's day columns and
/// Today's schedule pane, for the reason `iOSTimelineTaskBlock` documents. Today's pane used to
/// draw a generic title/subtitle card that named the bundle and its hours but never said what was
/// in it.
struct iOSTimelineBundleBlock: View {
    let bundle: TaskBundle
    /// See `iOSTimelineTaskBlock.fillsAvailableHeight`.
    var fillsAvailableHeight: Bool = true
    // T-217, and the sharper half of it: this block is drawn from a `ForEach(bundles)` filtered by
    // day on the Calendar screen and by *hour* on Today's schedule pane, so a card-owned sheet was
    // torn down by a start-time edit as well as a date one.
    @Environment(\.iOSBundleInspector) private var bundleInspector

    private var tasks: [AppTask] {
        bundle.sortedTasks
    }

    private var allDone: Bool {
        !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    var body: some View {
        Button {
            bundleInspector(bundle)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(bundle.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("×\(tasks.count)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(allDone ? Theme.dim : Theme.text)
                .strikethrough(allDone, color: Theme.dim)

                ForEach(tasks.prefix(2)) { task in
                    HStack(spacing: 4) {
                        iOSTaskCompletionCircle(glyph: .resolve(task: task))
                            .frame(width: 9, height: 9)
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.text.opacity(0.85))
                            .strikethrough(task.isDone, color: Theme.dim)
                            .lineLimit(1)
                    }
                }

                if tasks.count > 2 {
                    Text("+\(tasks.count - 2) more")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                Text(CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
            .background(allDone ? Theme.doneFill.opacity(0.12) : Theme.amber.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .stroke(allDone ? Theme.doneFill.opacity(0.4) : Theme.amber.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.iosPressable)
        .contextMenu {
            Button {
                bundleInspector(bundle)
            } label: {
                Label("Edit Block", systemImage: "square.and.pencil")
            }
        }
    }
}
#endif
