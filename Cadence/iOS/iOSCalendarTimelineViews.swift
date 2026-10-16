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

/// What `iOSCalendarTimelineGrid` draws across its horizontal axis.
///
/// **This is the whole of the difference between the app's two timed iOS surfaces**, and it is
/// stated as one value rather than left to two views because the previous arrangement was a fork:
/// Today's pane had its own hour grid — `iOSScheduleHourRow`, a flow of 24 rows — which drew tasks
/// and bundles and **no EventKit events at all**, offered no create-drag drop target and carried no
/// pinch. Three of the owner's reports in one place, every one of them a thing the Calendar's grid
/// had already solved. See [[T-3081]].
///
/// A span is not a *date*: the day a single-day grid shows is `leadingDate`, exactly as it is for
/// a scrolling one. What the span decides is whether there is anywhere else to go.
enum iOSCalendarTimelineSpan: Equatable {
    /// A scrolling run of day columns through `CadenceCalendarTimelineWindow`, `visibleDayCount` of
    /// them on screen at once. The Calendar page's Week and 2 Weeks.
    case scrollingDays(visibleDayCount: Int)
    /// Exactly one column, fixed to `leadingDate`. Today's timeline pane.
    ///
    /// **No horizontal scroll view is built**, which is how `DayBoundaryScrollTargetBehavior` is
    /// kept off a surface with nothing to settle between: the behaviour is attached inside
    /// `gridScroller`, and a single-day grid never builds one. The day window, the leading-column
    /// report and the recentring go with it, so a single-day grid never writes `leadingDate` back
    /// and its caller may hand in a constant.
    case singleDay
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
///
/// ## Two call sites, one grid
///
/// The Calendar page draws it as a scrolling run of days; Today's timeline pane draws it as one
/// fixed column — see `iOSCalendarTimelineSpan`. Nothing about a *day* differs between them: the
/// column, its blocks, its create gesture, its drop target, its now line, the hour rail and the
/// pinch are the same code reached through `dayColumn(for:colWidth:)`. What the span selects is
/// only the chrome around the column — whether there is a horizontal scroller to page days with,
/// and whether a day header band stands over it.
struct iOSCalendarTimelineGrid: View {
    /// The column at the leading edge — read as "which day am I looking at", written to jump.
    ///
    /// Both directions, like the Board's `scrolledDayIndex`: scrolling reports the leading day back
    /// up so the toolbar's date button can name it, and setting it scrolls that day to the leading
    /// edge.
    @Binding var leadingDate: Date
    @Binding var selectedDate: Date
    /// A scrolling run of days, or the one day `leadingDate` names. See `iOSCalendarTimelineSpan`.
    let span: iOSCalendarTimelineSpan
    let scheduledTasksByDate: [String: [AppTask]]
    let unscheduledTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]
    /// A multiplier on the base hour height, 1…3. Written once per pinch, not per frame — see
    /// `pinchZoom`.
    @Binding var zoom: Double
    let onCreateAt: (String, Int) -> Void
    /// Press-and-hold draws a DRAFT BLOCK on the column and hangs the shared schedule panel off it
    /// as a popover, instead of calling `onCreateAt` ([[T-3169]]).
    ///
    /// **A flag rather than a second grid.** The Calendar page and Today's pane build the same
    /// column through `dayColumn(for:colWidth:)` — a second spelling of that call is how Today came
    /// to have a timeline that drew neither events nor a drop target — so the draft layer is a
    /// property of the column, switched on by whoever wants it. Defaulted `false`, so the Calendar
    /// page's call site is byte-for-byte unchanged and keeps its tap-opens-a-sheet behaviour until
    /// [[T-3171]] takes the panel there too.
    var drawsDraftBlocks: Bool = false

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
    private var isSingleDay: Bool { span == .singleDay }
    /// How many columns should be on screen — `CadenceCalendarWeekGridLayout.visibleDayCount(for:)`
    /// on the Calendar page. It no longer decides how many days *exist*; see
    /// `CadenceCalendarTimelineWindow`. A single-day grid is one by definition, which is also what
    /// makes `placeInitialScroll` open it on today's own hour rather than on a week's first block.
    private var visibleDayCount: Int {
        switch span {
        case .scrollingDays(let count): count
        case .singleDay: 1
        }
    }
    private var baseHourHeight: CGFloat { iOSCalendarTimelineMetrics.hourHeight }
    private var effectiveZoom: Double { CadenceCalendarZoom.clamp(pinchZoom ?? zoom) }
    private var hourHeight: CGFloat {
        CadenceCalendarZoom.hourHeight(base: baseHourHeight, zoom: effectiveZoom)
    }
    /// Zero on a single-day grid, and the rail reads the same number, so the two cannot disagree
    /// about where hour zero starts.
    ///
    /// **A band there would be the page's own title said twice.** The header names a weekday and a
    /// day number and lists the day's unscheduled tasks; Today's pane stands beside a task column
    /// headed `iPadTodayTaskHeader` — the same date, and those same untimed tasks listed in full —
    /// so it would restate both in 76pt of a pane that is 320pt wide. That is the page-header rule
    /// (`AGENTS.md`, "Non-Negotiable Patterns"), and it is also what T-1273 removed the pane's
    /// "Ready to Schedule" stack for, on exactly the argument that the column across the divider is
    /// already showing them.
    private var dayHeaderHeight: CGFloat {
        isSingleDay ? 0 : iOSCalendarTimelineMetrics.dayHeaderHeight
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

                if isSingleDay {
                    singleDayCanvas(colWidth: colWidth, canvasHeight: canvasHeight)
                } else {
                    gridScroller(colWidth: colWidth, contentWidth: contentWidth, canvasHeight: canvasHeight)
                }
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
                // different day. Nothing to correct on a single-day grid: its one column *is* the
                // viewport, so a width change re-lays it out and no offset is carrying a date.
                guard !isSingleDay else { return }
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

    /// One day's column, wherever it is being drawn.
    ///
    /// **Both spans build the column through here, and that is the point of the span existing at
    /// all.** The three behaviours the owner reported missing from Today — the create-drag drop
    /// target, the EventKit blocks and the pinch's `hourHeight` reaching every block — are
    /// properties of this column and of the container the pinch is attached to, not of the
    /// scroller around them. A second spelling of this call is how Today came to have a timeline
    /// that drew neither events nor a drop target in the first place.
    private func dayColumn(for date: Date, colWidth: CGFloat) -> some View {
        let key = DateFormatters.dateKey(from: date)
        return iOSCalendarTimelineDayColumn(
            date: date,
            tasks: CadenceScheduleSupport.items(on: key, in: scheduledTasksByDate),
            bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
            events: CadenceScheduleSupport.items(on: key, in: eventsByDate),
            colWidth: colWidth,
            hourHeight: hourHeight,
            isCompactWidth: !isRegularWidth,
            workHoursStartMinute: workHoursStartMinute,
            workHoursEndMinute: workHoursEndMinute,
            onCreateAt: onCreateAt,
            drawsDraftBlocks: drawsDraftBlocks,
            onClearTime: clearsTime
        )
    }

    /// The block's "put this back with the untimed work" corner, on the span that has somewhere to
    /// put it back *to*.
    ///
    /// `iOSTimelineTaskBlock.onClearTime`'s own doc has always stated this condition, and it used
    /// to be enforced by which of two *views* built the block: Today's pane passed a closure and
    /// the Calendar grid passed `nil`. One grid draws both now, so the condition is asked of the
    /// span instead — and it is the same condition word for word. A single-day grid is Today's
    /// pane, which is only ever built at the two-pane width, so the task column the cleared task
    /// lands in is on screen one divider to the left. A scrolling grid is the Calendar page, which
    /// shows whichever day you scrolled to and has no task column beside it, so the control is
    /// absent rather than disabled.
    private var clearsTime: ((AppTask) -> Void)? {
        guard isSingleDay else { return nil }
        return { task in
            CadenceTaskDateEditing.clearScheduledTime(task, in: modelContext)
        }
    }

    /// The one-column canvas: a vertical scroll view and nothing else.
    ///
    /// **Three gestures live on this pane and none of them is the one that was missing.** Reading
    /// them from the outside in: the pinch is a `simultaneousGesture` on the `HStack` two frames up
    /// — two fingers, so it can never claim the one-finger pan this scroll view needs, and it never
    /// has to be handed *through* a scroll view, which is the note on `body` and the reason it is
    /// placed there rather than here. The vertical drag is this scroll view's own. The long-press
    /// -then-drag that opens the creation panel belongs to the page's floating `+`
    /// (`iOSFloatingCreateTaskButton`, which Today already installs): the finger starts on the
    /// button, not on this canvas, so what this pane has to supply is a *landing place*, and that
    /// is `iOSNewTaskDropTarget` on the column — a drop destination, not a recognizer. So there is
    /// no three-way conflict to arbitrate: one pan, one two-finger gesture, and a drop whose touch
    /// was claimed somewhere else entirely. The column's own `SpatialTapGesture` is the fourth and
    /// it is a tap, which a scroll view yields on anyway.
    ///
    /// **No `contentMargins` here, unlike `gridScroller`.** That restatement exists because the
    /// grid's vertical canvas is nested inside a *horizontal* scroller that eats the page-level
    /// value (T-2066). There is no outer scroller here, so Today's page-level write — the one
    /// `iOSFloatingCreateTaskLayer` makes for the same corner `+` — reaches this scroll view
    /// directly, and restating it would inset the canvas by the button's footprint twice.
    private func singleDayCanvas(colWidth: CGFloat, canvasHeight: CGFloat) -> some View {
        ScrollView(.vertical) {
            dayColumn(for: leadingDate, colWidth: colWidth)
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
                            allDayEvents: items(eventsByDate, on: date).filter(\.isAllDay),
                            unscheduledTasks: items(unscheduledTasksByDate, on: date)
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
                            dayColumn(for: date(at: index), colWidth: colWidth)
                                .offset(x: CGFloat(index) * colWidth)
                        }
                    }
                    .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
                }
                .frame(height: canvasHeight)
                .scrollIndicators(.hidden)
                // **The corner `+`'s clearance, restated here because the page's copy cannot reach
                // this far (T-2066).** `iOSFloatingCreateTaskLayer` writes
                // `contentMargins(.bottom, iOSCircularAddButton.scrollClearance, for: .scrollContent)`
                // once, on the page, and that is enough everywhere else: a page's bottom-reaching
                // list is the first scroll view the value meets. Here it is not. The canvas is a
                // vertical scroll view **nested inside** the horizontal one above, and the outer
                // scroller consumes the inherited value — measured on `Cadence-iPadPro11` with the
                // page-level write alone in place, the grid still stopped dead on midnight and the
                // button sat over Saturday 22:37–23:35 with nothing able to bring it out.
                //
                // So the clearance is applied where it was aimed. It is the layer's own constant,
                // not a second number, and the gate is the layer's own: at compact width the tab
                // bar's centre `+` is the capture affordance, no page floats one, and a canvas that
                // ran past midnight there would be clearance for a button that is not on the page.
                //
                // This is `D-104`'s mirror image. `iOSListSupportViews` and the markdown accessory
                // strips *cancel* an inherited clearance that landed on a scroll view too short to
                // need it; this restores one that never arrived at the scroll view that does.
                .contentMargins(.bottom, isRegularWidth ? iOSCircularAddButton.scrollClearance : 0, for: .scrollContent)
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
        // **A sideways scroll settles on a day edge, never between two of them (T-3075).** This
        // grid had no scroll target behaviour at all, so deceleration stopped it wherever it
        // happened to run out and left the user parked across two columns with a sliver of each —
        // on the one surface in the app whose columns *are* the days. The Mac's Calendar page has
        // settled on a day edge since it was written, through this same
        // `DayBoundaryScrollTargetBehavior`; the type was declared behind that page's
        // `#if os(macOS)` and is in `Shared/` now, so the two grids share one rule rather than each
        // owning a copy of it. `CadenceCalendarDaySnap` holds the arithmetic.
        //
        // The column index below is **not** that rule and never was: it rounds the offset it is
        // *reported*, which is what makes the toolbar name the right day, and leaves the scroll
        // view resting wherever it rested. Rounding a report is not settling a scroll.
        //
        // No `scrollTargetLayout()`, unlike the Board's `.viewAligned`: this behaviour reads the
        // proposed offset and the column width, not the frames of the content's subviews — which is
        // what lets it work over the offset-positioned `ZStack` this grid windows its columns with
        // (see `CadenceCalendarTimelineWindow.renderedIndexRange`) instead of a lazy stack.
        .scrollTargetBehavior(DayBoundaryScrollTargetBehavior(dayWidth: colWidth))
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
        // A single-day grid has no window: its one column is `leadingDate`, read straight out of
        // the binding by `singleDayCanvas`. Building one would leave `windowStart`/`leadingIndex`
        // carrying a position for a scroll view that is not in the tree.
        guard !isSingleDay else { return }
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

    /// Opens the timeline on its **first timed item** instead of at the top of the canvas — which
    /// is midnight now that the grid draws the whole day. See
    /// `CadenceScheduleSupport.initialTimelineHour` for the three-rung rule; this is where the
    /// span it applies to is decided.
    ///
    /// **Which days.** The earliest item across every column *on screen*, not just the leading
    /// one. A week is one span to a reader, and opening at Monday's work-hours default because
    /// Monday is empty would put Tuesday's 07:00 standup above the fold in the same picture. The
    /// same span now answers `showsToday`, which used to ask `eventWindowDates` — a 28-day
    /// EventKit *fetch* window — and so said yes for any week within a fortnight of today. That is
    /// what opened a scrolled-away week at the current hour, and at 1 AM the current hour is the
    /// top of the canvas: the owner's report, and not a coincidence of timing.
    ///
    /// **Once per appearance, not once per day scrolled to.** `didPlaceInitialScroll` is `@State`,
    /// so this runs on the first laid-out canvas of each visit to the grid and never again while
    /// that grid lives. Re-deriving on every horizontal scroll would yank the canvas vertically
    /// under a finger that was moving it horizontally, and re-deriving when the data changed would
    /// move it under a task the user had just dragged. A user who scrolls away from the opening
    /// hour has said where they want to be; nothing here overrules that until they leave and come
    /// back.
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

        let visibleDates = CadenceCalendarTimelineWindow.visibleDates(
            leadingDate: leadingDate,
            visibleDayCount: visibleDayCount,
            calendar: calendar
        )
        let hour = CadenceScheduleSupport.initialTimelineHour(
            firstTimedMinute: CadenceScheduleSupport.earliestTimedStartMinute(
                timedStartMinutes(on: visibleDates)
            ),
            showsToday: visibleDates.contains { calendar.isDateInToday($0) },
            workHoursStartMinute: workHoursStartMinute,
            calendar: calendar
        )
        verticalScrollPosition.scrollTo(
            y: CadenceScheduleSupport.timelineScrollOffset(forHour: hour, hourHeight: hourHeight)
        )
    }

    /// Start minutes of everything `iOSCalendarTimelineDayColumn` draws as a block on `dates`.
    ///
    /// The three sources the removed "N timed" chip counted, read the same way the column reads
    /// them so the hour this opens at cannot describe a different set from the one on screen. An
    /// event is measured **on its column's day**, so one running through midnight contributes the
    /// 00:00 its block actually starts at there rather than yesterday's start time; all-day events
    /// are not blocks at all and are dropped, exactly as the column drops them.
    private func timedStartMinutes(on dates: [Date]) -> [Int] {
        dates.flatMap { date -> [Int] in
            let key = DateFormatters.dateKey(from: date)
            let taskMinutes = CadenceScheduleSupport.items(on: key, in: scheduledTasksByDate)
                .map(\.scheduledStartMin)
            let bundleMinutes = CadenceScheduleSupport.items(on: key, in: bundlesByDate)
                .map(\.startMin)
            let eventMinutes = CadenceScheduleSupport.items(on: key, in: eventsByDate)
                .filter { !$0.isAllDay }
                .map { iOSCalendarEventSupport.minuteRange(for: $0, on: date).start }
            return taskMinutes + bundleMinutes + eventMinutes
        }
    }
}

/// The band over one day column: the weekday, the day number, the day's **all-day events**, and its
/// **unscheduled** tasks.
///
/// **Those two are different ideas, and since T-3185 the strip says which is which.** T-3160's
/// rail-vs-plate answers "event or task"; it does not answer "spans the whole day" against "has no
/// time yet", so an ordinary "Buy milk" beside "Company offsite" read as an all-day commitment.
/// The unscheduled chips wear `circle.dashed` and a dashed rim — see
/// `iOSCalendarMiniChip.isUnscheduled`. The seeded fixture hid this for a while by naming its task
/// "All-day task: pack for trip", which is a coherent screenshot of an incoherent rule.
///
/// **All-day events live here since T-3163.** The column below has never drawn one — they are not
/// blocks, so `iOSCalendarTimelineDayColumn.timedEvents` drops them — and until then nothing else
/// did either, so on the week timeline a holiday or a trip did not exist. They take the band's
/// slots ahead of the unscheduled tasks, by `CadenceCalendarAllDayBandPriority` (the month cell's
/// events-before-tasks rule), and wear the same rail-plate `iOSCalendarMiniChip` the iOS month cell
/// draws an event with, which is the treatment macOS's `AllDayEventChip` wears.
///
/// Nothing timed is named here. It used to end in an "N timed" chip counting the day's tasks,
/// bundles and events, and that chip hid nothing — `iOSCalendarTimelineDayColumn` draws every one
/// of those three as a block in the grid below, so the count restated the picture rather than
/// adding to it. The unscheduled chips stay because those items genuinely have no block: they have
/// no time, which is what puts them in the band at all. Apple Calendar's top band carries all-day
/// items and nothing else, for the same reason. **T-1271.**
///
/// It carries **no selection state**. Tapping a header still sets the calendar's selected day — the
/// day inspector beside a wide-enough Week pane is what reads it — but nothing on the grid lights up
/// for it any more. A grid of seven columns is a span you are looking at, not a list you pick from,
/// and the blue-on-blue "selected" tint sat a shade away from the "today" tint next to it, so the
/// two were told apart mostly by knowing which was which.
private struct iOSCalendarTimelineDayHeader: View {
    let date: Date
    let allDayEvents: [EKEvent]
    let unscheduledTasks: [AppTask]
    let action: () -> Void

    /// Who gets the band's two rows, and how many items the "+N more" line stands for.
    private var split: CadenceCalendarMonthCellPriority.Split {
        CadenceCalendarAllDayBandPriority.split(
            allDayEvents: allDayEvents.count,
            unscheduledTasks: unscheduledTasks.count
        )
    }

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
                        .cadenceUppercaseLabel(
                            reading: DateFormatters.dayOfWeek.string(from: date),
                            size: iOSCalendarTimelineMetrics.weekdaySize,
                            kerning: CadenceCalendarWeekdayHeaderMetrics.labelKerning
                        )
                        .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: iOSCalendarTimelineMetrics.dayNumberSize, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Theme.onColor(for: Theme.blue) : Theme.text)
                        .frame(
                            width: iOSCalendarTimelineMetrics.dayCircleSize,
                            height: iOSCalendarTimelineMetrics.dayCircleSize
                        )
                        .background(isToday ? Theme.blue : Color.clear)
                        .clipShape(Circle())
                }
                .frame(height: iOSCalendarTimelineMetrics.dateBlockHeight)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(allDayEvents.prefix(split.events), id: \.calendarItemIdentifier) { event in
                        iOSCalendarMiniChip(
                            title: iOSCalendarEventSupport.title(for: event),
                            icon: "calendar",
                            color: iOSCalendarEventSupport.color(for: event.calendar),
                            isEvent: true
                        )
                    }

                    // **An unscheduled task is not an all-day commitment, and now says so**
                    // (T-3185): a dashed glyph and a dashed rim, two channels, neither of them the
                    // rail that already means "event". `iOSCalendarMiniChip.isUnscheduled` carries
                    // the reasoning and the 17pt measurement the rail fails at.
                    ForEach(unscheduledTasks.prefix(split.tasks)) { task in
                        iOSCalendarMiniChip(
                            title: TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle),
                            icon: "circle.dashed",
                            color: Color(hex: task.containerColor),
                            isUnscheduled: true
                        )
                    }

                    if split.hidden > 0 {
                        Text(CadenceTaskSurfaceOptions.moreLabel(hidden: split.hidden))
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
                    .fill(Theme.borderSubtle.opacity(iOSCalendarHairlineMetrics.pinnedEdgeOpacity))
                    .frame(width: iOSCalendarHairlineMetrics.width)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(iOSCalendarHairlineMetrics.pinnedEdgeOpacity))
                    .frame(height: iOSCalendarHairlineMetrics.width)
            }
        }
        .buttonStyle(.iosPressable)
        // The two stacks the band draws — all-day events (T-3163) and unscheduled tasks — where it
        // used to announce the long date and nothing else (T-573), and where it briefly announced
        // an "N timed" count as well (T-1271 took that chip off the band).
        //
        // **No `.isSelected` trait here**, unlike the two month cells. This header carries no
        // selection state by design (see the doc above): tapping it still sets the calendar's
        // selected day for the inspector to read, but nothing on the grid lights up for it, so a
        // trait would announce a state the screen deliberately does not show.
        .accessibilityLabel(
            CadenceCalendarDayAccessibility.timelineDayLabel(
                date: date,
                allDayEventCount: allDayEvents.count,
                unscheduledCount: unscheduledTasks.count
            )
        )
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
                    Text(TimeFormatters.timeString(from: hour * 60))
                        .font(.system(size: iOSCalendarTimelineMetrics.hourLabelSize, weight: .medium))
                        .foregroundStyle(
                            Theme.dim.opacity(CadenceCalendarHourLadderMetrics.labelOpacity(hour: hour))
                        )
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
                .fill(Theme.borderSubtle.opacity(iOSCalendarHairlineMetrics.pinnedEdgeOpacity))
                .frame(width: iOSCalendarHairlineMetrics.width)
        }
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
                // The rung is a fact about the *hour*, not about the row's index: this canvas
                // starts at `calendarStartHour` and the weight is asked for in those terms, so a
                // canvas that one day starts elsewhere cannot slide the rung off the clock.
                let hour = CadenceScheduleSupport.calendarStartHour + index
                Rectangle()
                    .fill(
                        Theme.borderSubtle.opacity(
                            CadenceCalendarHourLadderMetrics.ruleOpacity(hour: hour)
                        )
                    )
                    .frame(width: colWidth, height: iOSCalendarHairlineMetrics.width)
                    .offset(y: CGFloat(index) * hourHeight)
            }
        }
        .frame(width: colWidth, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(iOSCalendarHairlineMetrics.dayEdgeOpacity))
                .frame(width: iOSCalendarHairlineMetrics.width)
        }
        .allowsHitTesting(false)
    }
}

private struct iOSCalendarTimelineDayColumn: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]
    let colWidth: CGFloat
    let hourHeight: CGFloat
    /// **What "compact" means on this grid: the horizontal size class, nothing measured** (T-3184).
    ///
    /// The owner left the definition to the implementer and named the size class as the idiomatic
    /// answer; it is taken, and the reason is that it is the only spelling that survives a narrow
    /// iPad Split View, where a pane can be phone-width on a device whose screen is not. A raw
    /// point threshold would need a constant nobody has measured *and* would have to be re-measured
    /// for every pane the calendar can appear in. The grid already resolves the same environment
    /// value one view up for the hour rail and the column width, so this is the width question the
    /// surface already asks, answered once and handed down rather than read again here.
    let isCompactWidth: Bool
    let workHoursStartMinute: Int
    let workHoursEndMinute: Int
    let onCreateAt: (String, Int) -> Void
    /// See `iOSCalendarTimelineGrid.drawsDraftBlocks`.
    var drawsDraftBlocks: Bool = false
    /// Non-`nil` only where a cleared task has a visible place to land — see
    /// `iOSCalendarTimelineGrid.clearsTime`, which is the one decision of it in the app.
    let onClearTime: ((AppTask) -> Void)?

    /// The in-place draft, owned by the column that drew it. One column, one draft: a press lands
    /// on exactly one day, and a grid that windows a scrolling range would otherwise need a rule
    /// for which of fourteen columns holds the pending one.
    @State private var draft: CadenceScheduleDraft?
    @State private var isDraftEditorPresented = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            createSurface

            iOSCalendarTimelineColumnGridLines(colWidth: colWidth, hourHeight: hourHeight)

            workHoursBand

            dayWash

            // **One overlap layout for every timed block in the column** (T-3161 for events,
            // T-3165 for the rest). Tasks, bundles and events go through the same shared solver
            // macOS's `computeUnifiedLayouts` reads, in one pass, so each reserves a column against
            // the other two: a task that overlaps an event now sits *beside* it instead of being
            // painted full width across its title. At regular width only events cascade; at
            // compact width every kind does, with the later start in front (T-3184). A day with no
            // overlaps keeps the exact width and inset every block had.
            //
            // **Draw order is the solver's order now, not the order of the three `ForEach`es**
            // (T-3184). Each block carries the `zIndex` `iOSCalendarTimelineBlockLayout.zIndexes`
            // gives it, so the later-starting block is painted on top whichever kind it is — which
            // is what makes "later start in front" true of a task over an event and not only of an
            // event over an event. See that function for what went wrong without it.
            let solved = blockPlacements
            let placements = solved.placements

            ForEach(bundles) { bundle in
                let key = BlockKey.bundle(bundle.persistentModelID)
                let slot = horizontalFrame(placements[.bundle(bundle.persistentModelID)], kind: .bundle)
                iOSTimelineBundleBlock(bundle: bundle)
                    .frame(width: slot.width, height: blockHeight(start: bundle.startMin, end: bundle.endMin))
                    .offset(x: slot.x, y: yOffset(for: bundle.startMin))
                    .zIndex(solved.zIndexes[key] ?? 1)
            }

            ForEach(timedEvents, id: \.calendarItemIdentifier) { event in
                // The column's own day, so an event that crosses midnight draws the part that
                // belongs here. `frame` uses the range clamped into the drawn hours; the block
                // still labels itself with the true one.
                let range = iOSCalendarEventSupport.minuteRange(for: event, on: date)
                let drawn = CadenceScheduleSupport.timelineVisibleRange(start: range.start, end: range.end)
                let key = BlockKey.event(event.calendarItemIdentifier)
                let slot = horizontalFrame(placements[.event(event.calendarItemIdentifier)], kind: .event)
                iOSCalendarEventBlock(event: event, startMin: range.start, endMin: range.end)
                    .frame(width: slot.width, height: blockHeight(start: drawn.start, end: drawn.end))
                    .offset(x: slot.x, y: yOffset(for: drawn.start))
                    .zIndex(solved.zIndexes[key] ?? 1)
            }

            ForEach(tasks) { task in
                let range = taskRange(task)
                let key = BlockKey.task(task.persistentModelID)
                let slot = horizontalFrame(placements[.task(task.persistentModelID)], kind: .task)
                iOSTimelineTaskBlock(
                    task: task,
                    startMin: range.start,
                    endMin: range.end,
                    onClearTime: onClearTime.map { clear in { clear(task) } }
                )
                .frame(width: slot.width, height: blockHeight(start: range.start, end: range.end))
                .offset(x: slot.x, y: yOffset(for: range.start))
                .zIndex(solved.zIndexes[key] ?? 1)
            }

            // Above every block, which is where these two were by declaration order until the
            // blocks were given a `zIndex` of their own.
            draftLayer
                .zIndex(iOSCalendarTimelineBlockLayout.overlayZIndex)

            nowLine
                .zIndex(iOSCalendarTimelineBlockLayout.overlayZIndex)
        }
        .frame(width: colWidth, height: timelineHeight, alignment: .topLeading)
        // **The column is a drop target, and the minute is part of what it hands over** (T-1276).
        // The owner asked for a `+` dropped "onto the calendar timeline" to inherit what it landed
        // on, and what a day column has to give is a day *and* a time — the same two the column's
        // own tap already resolves, through the same `CadenceScheduleSupport.timelineMinute`, so
        // the tap and the drop cannot name different quarter-hours for one pixel.
        //
        // It names **no list**: a timeline draws work from every list at once, so there is nothing
        // here that is true of every block in the column. It names no priority either — see
        // `dropKey(forGroup:)`, which withholds that from every container.
        //
        // Blocks inside the column stay the more specific answer by area alone; nothing here has to
        // be ordered against them.
        .iOSNewTaskDropTarget(
            horizontalInset: 9,
            ghost: .slot(
                CadenceCaptureDropSlotRule(
                    hourHeight: hourHeight,
                    startHour: CadenceScheduleSupport.calendarStartHour,
                    endHour: CadenceScheduleSupport.calendarEndHour
                )
            ),
            dropKey: { dropKey }
        )
    }

    /// The empty-space gesture surface.
    ///
    /// **Two arms rather than one gesture with an `if` in it.** A column that does not draw drafts
    /// installs exactly the recognizer it had before — this canvas already carries a horizontal
    /// scroller, a vertical scroller, a pinch and a drop target, and gesture collisions are this
    /// app's most repeated bug, so a recognizer is not installed where its gesture is not offered.
    /// `drawsDraftBlocks` is fixed per call site, so the branch never flips at runtime.
    ///
    /// On the drafting arm the long press and the tap coexist: a `LongPressGesture` sequenced
    /// before a zero-distance `DragGesture` is the only way SwiftUI reports **where** a press
    /// happened — the press itself carries no location, and the drag that follows it does — and
    /// continuing to drag sizes the block in the same gesture, which is Apple Calendar's own
    /// behaviour. The tap is kept, and now opens the same draft rather than the docked bar: it is
    /// what this canvas has always done, and removing it would be a behaviour the owner did not ask
    /// to lose. `beginDraft` is idempotent, so a tap arriving at the end of a long press finds the
    /// draft already there and does nothing.
    @ViewBuilder
    private var createSurface: some View {
        if drawsDraftBlocks {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(draftPressGesture)
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in beginDraft(atY: value.location.y) }
                )
        } else {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            onCreateAt(DateFormatters.dateKey(from: date), minute(for: value.location.y))
                        }
                )
        }
    }

    private var draftPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if draft == nil {
                    beginDraft(atY: drag.startLocation.y)
                    return
                }
                // Still the same press: dragging away from the start sizes the block rather than
                // moving it, which is what a user who presses and then pulls means by it. A drag
                // that has not travelled a row is left alone so a press-and-release keeps the
                // default hour.
                guard abs(drag.translation.height) > 2 else { return }
                draft?.moveEndEdge(toMinute: minute(for: drag.location.y) + CadenceScheduleSupport.touchTimeGridMinutes)
            }
            .onEnded { _ in
                guard draft != nil else { return }
                isDraftEditorPresented = true
            }
    }

    /// Opens a draft at a pressed point, or leaves the one already there alone.
    private func beginDraft(atY yPosition: CGFloat) {
        guard drawsDraftBlocks, draft == nil else { return }
        draft = CadenceScheduleDraft(
            dateKey: DateFormatters.dateKey(from: date),
            startMin: minute(for: yPosition)
        )
        isDraftEditorPresented = true
    }

    /// The draft block, drawn where every other block on this column is drawn — same inset, same
    /// `yOffset`, same `blockHeight` — so what the user sees before committing is the rectangle the
    /// committed thing will occupy.
    @ViewBuilder
    private var draftLayer: some View {
        if drawsDraftBlocks, let current = draft, current.startDateKey == DateFormatters.dateKey(from: date) {
            iOSTimelineDraftBlock(
                draft: Binding(
                    get: { draft ?? current },
                    set: { draft = $0 }
                ),
                hourHeight: hourHeight
            )
            .frame(
                width: colWidth - 18,
                height: blockHeight(start: current.startMin, end: current.isAllDay ? current.startMin + 60 : current.endMin)
            )
            .offset(x: 9, y: yOffset(for: current.isAllDay ? CadenceScheduleSupport.calendarStartHour * 60 : current.startMin))
            .popover(isPresented: $isDraftEditorPresented, arrowEdge: .trailing) {
                iOSTimelineDraftPanelHost(
                    draft: Binding(
                        get: { draft ?? current },
                        set: { draft = $0 }
                    ),
                    onCancel: { isDraftEditorPresented = false },
                    onCommitted: {
                        isDraftEditorPresented = false
                        draft = nil
                    }
                )
            }
            // Dismissing the popover by tapping outside it abandons the draft: there is no half-made
            // block to leave on the canvas, and a rectangle outliving the editor that owned it is
            // the shape of a leak the next tap cannot clear.
            .onChange(of: isDraftEditorPresented) { _, isPresented in
                if !isPresented { draft = nil }
            }
        }
    }

    /// What this column offers a dropped `+`, or `""` — no target — on a day that has already gone
    /// by.
    ///
    /// **A past column must not light up.** `CadenceTaskDropSupport.dateValue` drops a day earlier
    /// than today, exactly as it does for a row in an Overdue group, so the key would resolve to an
    /// empty seed and the ghost would print an empty caption: a region that accepts and then hands
    /// over nothing, which is the one thing the group-header rule says a container may never be.
    /// The grid can be scrolled to any week, so this is a reachable state and not a defensive
    /// branch. An empty key registers no target at all — see `iOSNewTaskDropTargetModifier`.
    private var dropKey: String {
        let key = DateFormatters.dateKey(from: date)
        guard key >= DateFormatters.todayKey() else { return "" }
        return CadenceTaskDropSupport.dropKey(forGroup: .timelineDay(dateKey: key)) ?? ""
    }

    /// The red rule at the current minute, the same one macOS has always drawn ([[T-1131]]).
    ///
    /// `CadenceTimelineNowLine` rather than a second copy of the Mac's overlay: the mark, the
    /// colour, the 1pt weight and the 15-second tick are all that component's, and the only thing
    /// this column supplies is its own minute-to-Y — the `yOffset` every block above already uses,
    /// so the rule cannot drift away from the blocks it crosses or fall behind the `1×`–`3×` pinch
    /// that `hourHeight` carries.
    ///
    /// **Built only on today's column, which is what keeps this grid to one timer.** The component
    /// would decline to draw on any other day anyway — `isVisible` asks the same question — but the
    /// gate is here as well because this grid windows a scrolling range of days, so without it
    /// every column on screen would run a `TimelineView(.periodic)` schedule to draw nothing. The
    /// predicate is a *day* boundary rather than an hour, so the once-a-day staleness it can carry
    /// is the midnight rollover, which this surface already redraws for `dayWash` on the same test.
    ///
    /// No dot: the Mac's Calendar page has none either, and one dot per visible column would be a
    /// row of them across a week.
    @ViewBuilder
    private var nowLine: some View {
        if Calendar.current.isDateInToday(date) {
            CadenceTimelineNowLine(
                day: date,
                totalWidth: colWidth,
                startHour: CadenceScheduleSupport.calendarStartHour,
                endHour: CadenceScheduleSupport.calendarEndHour,
                leadingInset: iOSCalendarTimelineMetrics.nowLineInset,
                trailingInset: iOSCalendarTimelineMetrics.nowLineInset,
                showDot: false,
                yOffset: { yOffset(for: $0) }
            )
        }
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

    /// The day's timed events **in start order**, ties broken by their order in `events`.
    ///
    /// The order is load-bearing rather than tidy: a `ZStack` draws its children in order and
    /// hit-tests the last one first, so start order is what makes the later-starting block of a
    /// cascade the one painted on top *and* the one that answers a tap where the two overlap.
    private var timedEvents: [EKEvent] {
        events.filter { !$0.isAllDay }
            .enumerated()
            .sorted { lhs, rhs in
                let left = CadenceScheduleSupport.timelineVisibleRange(
                    start: iOSCalendarEventSupport.minuteRange(for: lhs.element, on: date).start,
                    end: iOSCalendarEventSupport.minuteRange(for: lhs.element, on: date).end
                ).start
                let right = CadenceScheduleSupport.timelineVisibleRange(
                    start: iOSCalendarEventSupport.minuteRange(for: rhs.element, on: date).start,
                    end: iOSCalendarEventSupport.minuteRange(for: rhs.element, on: date).end
                ).start
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// What a block in this column is drawn by, across its three `ForEach`es.
    private enum BlockKey: Hashable {
        case task(PersistentIdentifier)
        case bundle(PersistentIdentifier)
        case event(String)
    }

    /// The minutes a task block is drawn over — read by both the block and the layout, so the
    /// rectangle that is columned is the rectangle that is drawn.
    private func taskRange(_ task: AppTask) -> (start: Int, end: Int) {
        CadenceScheduleSupport.blockRange(
            startMinute: task.scheduledStartMin,
            fallbackDuration: task.estimatedMinutes
        )
    }

    /// Column + cascade depth for **every** timed block in the column — tasks, bundles and events
    /// in one pass of the shared solver (T-3165), the way macOS's `computeUnifiedLayouts` does.
    ///
    /// Events are solved over their **drawn** minute range, not the true one, because overlap here
    /// is a question about rectangles on this column: an event that began yesterday is clamped to
    /// the top of the grid and overlaps whatever is drawn there. Tasks and bundles are solved over
    /// the same range their blocks are drawn at.
    ///
    /// It returns the **z order** off the same array as well (T-3184). One build of the block list,
    /// two answers from it: the order a tie is broken in has to be the same in both, or a cascade
    /// can be indented one way and painted the other.
    private var blockPlacements: (
        placements: [BlockKey: CadenceCalendarOverlapPlacement],
        zIndexes: [BlockKey: Double]
    ) {
        var blocks: [iOSCalendarTimelineBlockLayout.Block<BlockKey>] = []
        for bundle in bundles {
            blocks.append(.init(
                key: .bundle(bundle.persistentModelID),
                kind: .bundle,
                startMin: bundle.startMin,
                endMin: bundle.endMin
            ))
        }
        for event in timedEvents {
            let range = iOSCalendarEventSupport.minuteRange(for: event, on: date)
            let drawn = CadenceScheduleSupport.timelineVisibleRange(start: range.start, end: range.end)
            blocks.append(.init(
                key: .event(event.calendarItemIdentifier),
                kind: .event,
                startMin: drawn.start,
                endMin: drawn.end
            ))
        }
        for task in tasks {
            let range = taskRange(task)
            blocks.append(.init(
                key: .task(task.persistentModelID),
                kind: .task,
                startMin: range.start,
                endMin: range.end
            ))
        }
        // One line, deliberately: `CadenceCalendarOverlapLayoutTests` pins this call by the
        // spelling `placements(for:`, so wrapping the first argument onto its own line silently
        // takes the pin off the thing it guards.
        let columned = iOSCalendarTimelineBlockLayout.placements(for: blocks, hourHeight: hourHeight, isCompactWidth: isCompactWidth)
        return (columned, iOSCalendarTimelineBlockLayout.zIndexes(for: blocks))
    }

    /// Leading offset and width for one placed block. A block the solver did not see draws as a
    /// lone block, which is what it was before it had a placement at all.
    private func horizontalFrame(
        _ placement: CadenceCalendarOverlapPlacement?,
        kind: iOSCalendarTimelineBlockLayout.Kind
    ) -> (x: CGFloat, width: CGFloat) {
        iOSCalendarTimelineBlockLayout.horizontalFrame(
            for: placement ?? .single,
            kind: kind,
            columnWidth: colWidth
        )
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

    /// Read, not re-typed: `CadenceCaptureDropSlotRule` resolves a *dropped* `+` against the same
    /// arithmetic, from outside every view, and two copies of it is how the tap and the drop come
    /// to place the same pixel in different quarter-hours. See
    /// `CadenceScheduleSupport.timelineMinute(atY:…)`.
    private func minute(for yPosition: CGFloat) -> Int {
        CadenceScheduleSupport.timelineMinute(atY: yPosition, hourHeight: hourHeight)
    }
}

/// A timeline event block: **Apple Calendar's rail treatment**, exactly as on macOS — a leading
/// vertical rail at the calendar's own chroma, a dark tinted plate, and the title drawn *in that
/// hue* rather than in white (T-3160).
///
/// The label colours are `CadenceCalendarEventStyle`'s `rail*` tiers rather than `Theme.text` at
/// hand-picked alphas. That matters here more than anywhere else on the surface: each tier's
/// luminance is **derived** from `railFillLuminance` — the very plate drawn below it — so the
/// title, the time range and the glyph land on 5.1 / 4.6 / 3.2:1 whatever colour the account gave
/// the calendar, and `Theme.text.opacity(0.7)` was quietly opting out of that guarantee.
///
/// This block carries no interaction state, so every tier is read at rest. The Mac's copy passes
/// hover and selection through to the same functions.
private struct iOSCalendarEventBlock: View {
    let event: EKEvent
    let startMin: Int
    let endMin: Int

    private var calendarColor: Color {
        iOSCalendarEventSupport.color(for: event.calendar)
    }

    private var fill: Color {
        iOSCalendarEventSupport.fillColor(for: event.calendar)
    }

    /// The rail and the block's edge resolve from one call so the two cannot drift. Stateless by
    /// design — see `CadenceCalendarEventStyle.railColor(for:)`.
    private var railColor: Color {
        CadenceCalendarEventStyle.railColor(for: calendarColor)
    }

    private var blockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // The identity marker: a plain strip, shaped by the block's `.clipShape(blockShape)`
            // below rather than by corners of its own (T-3167) — a 3pt strip cannot carry the
            // plate's corner radius, so only the clip makes it end where the plate does. The same
            // construction the macOS event block uses. Opaque rather than a wash: this column has
            // an overlap layout (T-3161), so an indented block's rail is drawn over the body of the
            // block beneath it, and a translucent marker would show the neighbour's hue through it.
            //
            // `CadenceCalendarEventStyle.railWidth`, not a hand-typed `3`.
            Rectangle()
                .fill(railColor)
                .frame(width: CadenceCalendarEventStyle.railWidth)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CadenceCalendarEventStyle.railTertiaryLabelColor(for: calendarColor))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(iOSCalendarEventSupport.title(for: event))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CadenceCalendarEventStyle.railTitleColor(for: calendarColor))
                        .lineLimit(2)

                    Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CadenceCalendarEventStyle.railSecondaryLabelColor(for: calendarColor))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(fill)
        .clipShape(blockShape)
        .overlay {
            // The rail's colour, not the raw calendar colour: the rim and the rail are the same
            // marker seen at two weights, and `railBorderOpacity` is the ladder solved for this
            // plate rather than the brighter one the chip opacity was picked against.
            blockShape.strokeBorder(
                railColor.opacity(CadenceCalendarEventStyle.railBorderOpacity()),
                lineWidth: 1
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// The **one** task block on a timed grid: the Calendar screen's day columns and Today's schedule
/// pane. Since T-3160 it wears the **solved plate** the event block used to wear — an opaque fill
/// in the list's hue, solved to a fixed luminance so that `Theme.onColor`-family ink clears AA on
/// top of it, with no leading rail. The rail went to the event side with the rest of Apple
/// Calendar's look.
///
/// **This is now the one place the timeline's vocabulary parts from `iOSBoardTaskCard`'s**, which
/// still draws the neutral surface plus a colour wash this block used to copy. That is a
/// consequence of the swap being scoped to the calendar's timed grids, not an oversight: the
/// boards were not in the owner's instruction, and nothing shows a board card and a timeline block
/// side by side. Say so here rather than letting the next reader find the divergence and assume it
/// was an accident.
///
/// It replaced a second block in `iOSTodaySchedulePanel` that was a tint-washed, fully-rounded,
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
    /// Today's pane keeps a "back to Today's tasks" control on the block, because the column it
    /// would go back to is one divider to the left, on screen whenever this control is — that pane
    /// is only ever built at the two-pane width. The Calendar grid draws whichever day you are
    /// looking at and has no task column beside it, so it passes `nil` — an absent control, not a
    /// disabled one.
    ///
    /// **It used to say "back to Ready to Schedule" (T-1286).** T-1273 deleted that stack; what it
    /// did not change is that clearing a block's time still lands the task somewhere you can see.
    /// The destination moved one divider left; only its name was stale.
    var onClearTime: (() -> Void)? = nil
    // T-201: the page's `iOSTaskInspectorHost` presents, not this block. Both hosts of this block
    // rebuild their grid from a query keyed on the day and the slot, so completing or cancelling a
    // task from inside the panel dropped the block and the panel with it.
    @Environment(\.iOSTaskInspector) private var taskInspector

    private var listColor: Color {
        Color(hex: task.containerColor)
    }

    /// Rounded on every corner since T-3160. It was square on the leading edge so that the list
    /// colour strip read as a strip; there is no strip any more, and a block squared off against
    /// nothing is the visible residue of a half-finished swap.
    private var blockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    /// Both ink tiers, resolved against the plate they are actually drawn on. This block carries
    /// no hover or selection state — the press is `.iosPressable` — so both are read at rest.
    private var primaryInk: Color {
        CadenceCalendarEventStyle.platePrimaryLabelColor
    }

    private var secondaryInk: Color {
        CadenceCalendarEventStyle.plateSecondaryLabelColor()
    }

    /// [[T-3170]]: the block is neither draggable nor a drop target any more. Its only drag was the
    /// drop-a-block-on-a-block gesture that formed a Block, and this grid's day column has no
    /// `dropDestination` of its own, so there is no reschedule drop for a lift to feed. A task
    /// released over a block is simply not accepted; the time is moved from the task inspector.
    var body: some View {
        block
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
                    // A finished task drops one ink tier rather than going grey. `Theme.dim` was
                    // chosen for a near-black surface and this surface is no longer near-black —
                    // it reads about 2:1 on the plate. The strikethrough is what still says done.
                    Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(task.isDone ? secondaryInk : primaryInk)
                        .strikethrough(task.isDone, color: secondaryInk)
                        .lineLimit(2)
                    Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            // Clears the trailing control when there is one, so a two-line title cannot run under it.
            .padding(.trailing, onClearTime == nil ? 0 : 26)
            .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
            // The solved plate, in the list's own hue. The neutral surface and the wash over it
            // are gone: a wash says the hue with luminance it has to borrow from the surface, and
            // the ink above is solved against `plateLuminance` rather than against whatever that
            // borrowing happened to composite to. The done state is carried by the ink tier and
            // the strikethrough, not by a second fill at a second opacity.
            .background {
                blockShape.fill(CadenceCalendarEventStyle.plateFill(for: listColor))
            }
            .clipShape(blockShape)
            // The resting edge is the list colour's own lit rim at `chipBorderOpacity`, which is
            // the edge a solved plate asks for. `Theme.borderSubtle` is a near-black hairline; it
            // was the right edge for the near-black surface this plate replaced and is invisible
            // on the plate itself.
            .overlay {
                blockShape.strokeBorder(
                    listColor.opacity(CadenceCalendarEventStyle.chipBorderOpacity()),
                    lineWidth: 1
                )
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
                // Plate ink, not the list colour. This control sits *on* a plate solved from that
                // same colour, so a glyph in it was hue-on-hue the moment the fill stopped being a
                // neutral surface; `Theme.onColorBorder` is the well the `onColor` family already
                // ships for a control standing on a coloured fill.
                Image(systemName: "arrow.uturn.left.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CadenceCalendarEventStyle.platePrimaryLabelColor)
                    .frame(width: 22, height: 22)
                    .background(Theme.onColorBorder)
                    .clipShape(Circle())
                    .iOSExpandedHitArea(8)
            }
            .buttonStyle(.iosPressable)
            .padding(.top, 4)
            .padding(.trailing, 5)
            // The shared display title, not a second fallback. T-590 named the schedule panel's
            // chip; this is the same `task.title.isEmpty ? "task" : task.title` one file over, and
            // the block it sits on already draws `TaskTitleSupport.displayTitle`.
            //
            // The *full* fallback, where the block beside it draws the compact one. That is the
            // compact spelling's own stated reason — "a row with no width for the noun" — and a
            // spoken label has no width, so "Untitled Task" is the right form of the same name.
            .accessibilityLabel("Move \(TaskTitleSupport.displayTitle(task.title)) back to Today's tasks")
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
                        Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.text.opacity(0.85))
                            .strikethrough(task.isDone, color: Theme.dim)
                            .lineLimit(1)
                    }
                }

                if tasks.count > 2 {
                    Text(CadenceTaskSurfaceOptions.moreLabel(hidden: tasks.count - 2))
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
                    .strokeBorder(allDone ? Theme.doneFill.opacity(0.4) : Theme.amber.opacity(0.2), lineWidth: 1)
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
