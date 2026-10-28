#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

/// Label text for `CalendarChipDueMarker`, split out so the wording is testable without a view.
enum CalendarChipDueMarkerSupport {
    /// `nil` when the chip already sits on its due date — the grid position states that itself.
    static func label(dueDateKey: String, dayKey: String, calendar: Calendar = .current) -> String? {
        guard !dueDateKey.isEmpty, dueDateKey != dayKey else { return nil }
        guard let due = DateFormatters.date(from: dueDateKey, in: calendar) else { return dueDateKey }
        let dueParts = calendar.dateComponents([.month, .day], from: due)
        guard let dueMonth = dueParts.month, let dueDay = dueParts.day else { return dueDateKey }

        // Ordinal day while the deadline stays inside the chip's own month, where the surrounding
        // grid supplies the month; "MMM d" once it crosses into another month, where a bare day
        // would be ambiguous. Both forms read as a date — a bare number next to a task title
        // reads as a count of items, which is the mistake this replaces.
        if let day = DateFormatters.date(from: dayKey, in: calendar),
           calendar.isDate(due, equalTo: day, toGranularity: .month) {
            return ordinal(dueDay)
        }

        // Month name taken from the same calendar the key was parsed in. A shared
        // `DateFormatter` carries the *system* zone, so formatting a date parsed in some other
        // calendar there is the parse-in-one-zone/measure-in-another mistake all over again.
        let symbols = calendar.shortMonthSymbols
        guard dueMonth >= 1, dueMonth <= symbols.count else { return dueDateKey }
        return "\(symbols[dueMonth - 1]) \(dueDay)"
    }

    static func ordinal(_ day: Int) -> String {
        switch day % 100 {
        case 11, 12, 13: return "\(day)th"
        default:
            switch day % 10 {
            case 1: return "\(day)st"
            case 2: return "\(day)nd"
            case 3: return "\(day)rd"
            default: return "\(day)th"
            }
        }
    }
}

/// Compact deadline marker for calendar chips.
///
/// A chip is bucketed onto its scheduled day first (`CadenceScheduleSupport.monthTasksByDate`),
/// so a chip's position asserts a date that is frequently NOT the deadline. The marker therefore
/// carries the real due day: a bare "this has a deadline somewhere" dot would repeat the omission
/// it exists to fix. Nothing is drawn when the chip already sits on its due date — the grid
/// position states that itself.
///
/// It is plain tinted text rather than a filled pill: a badge-shaped `7` beside a task title
/// reads as "7 items", and the whole point of the marker is to name a date.
struct CalendarChipDueMarker: View {
    let dueDateKey: String
    /// `yyyy-MM-dd` of the day cell / column this chip is drawn in.
    let dayKey: String
    var todayKey: String = DateFormatters.todayKey()
    var isDone: Bool = false
    var calendar: Calendar = .current

    private var urgency: CadenceDueUrgency? {
        guard !dueDateKey.isEmpty, dueDateKey != dayKey else { return nil }
        return CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone, todayKey: todayKey)
    }

    var body: some View {
        if let urgency,
           let label = CalendarChipDueMarkerSupport.label(dueDateKey: dueDateKey, dayKey: dayKey, calendar: calendar) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(urgency.tint)
                .lineLimit(1)
                .fixedSize()
                // The chip is single-line and non-wrapping, so in a narrow month column the title
                // must be what truncates — never the date this marker exists to show.
                .layoutPriority(1)
        }
    }
}

/// Shared chip chrome for the month grid.
///
/// Keeping a task's fill and an event's fill different is still the rule; T-3160 swapped **which**
/// one each wears. A task now takes `CadenceCalendarEventStyle.plate*` — the bright
/// luminance-solved fill with `Theme.onColor` ink — and an event takes `rail*`, the far darker
/// tinted plate with its title in the calendar's own hue. Both are opaque solved plates in their
/// own object's colour, so neither needs the neutral surface underneath it any more.
///
/// `wash` survives for `MonthBundleChip`, which is an amber tint over the neutral surface rather
/// than a solved plate. **Neither solved plate may take one.** `Theme.subtleWash` is white at
/// 0.035, and composited over the rail plate — solved to Y = 0.030 — it lifts the plate to about
/// Y = 0.039, which drops the title from the 5.1:1 it was solved to to roughly 4.6:1. That is
/// still AA on paper, and it is the whole of the rounding margin `railTitleContrastTarget` exists
/// to provide, spent on a decorative fill. Pinned by `CadenceCalendarChipTreatmentTests`.
private struct MonthChipPlate: ViewModifier {
    let fill: AnyShapeStyle
    var wash: AnyShapeStyle?
    let border: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CalendarMonthCellLayout.chipHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius).fill(fill)
                    if let wash {
                        RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius).fill(wash)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: Theme.chipShadow, radius: 3, y: 1)
    }
}

private extension View {
    func monthChipPlate(fill: some ShapeStyle, wash: (any ShapeStyle)? = nil, border: Color) -> some View {
        modifier(MonthChipPlate(
            fill: AnyShapeStyle(fill),
            wash: wash.map { AnyShapeStyle($0) },
            border: border
        ))
    }
}

/// A task inside a month cell, wearing the **plate** treatment since T-3160: its list colour
/// solved to `plateLuminance`, with `Theme.onColor` ink. That is the fill a calendar event used to
/// wear here, and the completion circle did not move with the paint — it is the affordance, and it
/// is still the same hollow circle the task rows draw everywhere else in the app.
struct MonthTaskChip: View {
    let task: AppTask
    /// `yyyy-MM-dd` of the cell this chip is drawn in.
    let dayKey: String
    var todayKey: String = DateFormatters.todayKey()
    @State private var showInspector = false

    private var glyph: String {
        if task.isCancelled { return "xmark.circle.fill" }
        if task.isDone { return "checkmark.circle.fill" }
        return "circle"
    }

    /// The urgency tints and `Theme.green` stay — they are information, and they are bright enough
    /// to read on a plate solved to `plateLuminance`. The **neutral** fallback does not: `Theme.dim`
    /// is a grey solved against `Theme.bg`, and on a saturated plate it is the one tint here that
    /// has no contrast budget at all. It becomes the plate's own tertiary tier, which is solved
    /// against the fill the glyph actually lands on.
    private var glyphTint: Color {
        if task.isCancelled { return CadenceCalendarEventStyle.plateTertiaryLabelColor() }
        if task.isDone { return Theme.green }
        // No due date is not urgency-free noise: it collapses to the same neutral `.later`
        // tint, so only a real deadline ever colours the circle.
        return CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone, todayKey: todayKey)?.tint
            ?? CadenceCalendarEventStyle.plateTertiaryLabelColor()
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.system(size: CalendarMonthCellLayout.completionGlyphSize, weight: .semibold))
                .foregroundStyle(glyphTint)
            Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                .font(.system(size: 10))
                .foregroundStyle(
                    task.isDone
                        ? CadenceCalendarEventStyle.plateSecondaryLabelColor()
                        : CadenceCalendarEventStyle.platePrimaryLabelColor
                )
                .lineLimit(1)
            Spacer(minLength: 2)
            CalendarChipDueMarker(dueDateKey: task.dueDate, dayKey: dayKey, todayKey: todayKey, isDone: task.isDone)
        }
        // No `wash`: the fill is already this task's list colour solved to its own luminance, so a
        // second tint of the same hue over it would only move the plate off the target the ink is
        // solved against. A done task dims the *ink* one tier instead, which is the move the plate
        // treatment's own ladder makes everywhere else.
        .monthChipPlate(
            fill: CadenceCalendarEventStyle.plateChipFill(for: Color(hex: task.containerColor)),
            border: Color(hex: task.containerColor)
                .opacity(CadenceCalendarEventStyle.chipBorderOpacity())
        )
        // The all-day lane chip's own click, right-click, inspector and drag ([[T-5351]]). What a
        // click on the day cell around it, or on its "+N more", does is the owner's call and is
        // deliberately not wired here.
        .calendarTaskChipInteractions(task: task, showInspector: $showInspector)
    }
}

// `MonthBundleChip` was declared here: a `tray.full` glyph in `Theme.amber` over the neutral
// plate, the last thing on macOS that drew a Block. [[T-3170]] removed it, and with it the only
// caller of `CadenceCalendarMonthCellPriority.split`'s `bundles:` leg on either platform — so
// that parameter is gone from the shared helper too, rather than left taking a literal `0`.

/// An event inside a month cell, wearing the **rail** treatment's colours since T-3160: the dark
/// tinted plate and the title in the calendar's own hue.
///
/// **No rail, and that is a measurement rather than an omission.** `railWidth` is 3pt and this chip
/// is `CalendarMonthCellLayout.chipHeight` — 15pt — clipped to `CalendarVisualStyle.chipRadius`,
/// which is 6. A 3pt bar laid down the leading edge of a 15pt rounded rectangle is cut away by both
/// corners for 12 of those 15 points, leaving a 3x3 nub in the middle: that reads as a smudge of
/// paint, not as the identity marker a rail is. Apple draws the same conclusion in its own month
/// grid, where an event is a tinted chip or a dot and the rail appears only on the day and week
/// canvases, where a block is tens of points tall. So the treatment arrives here as colour.
///
/// The rail's *colour* does not vanish with the rail: it becomes the chip's edge. The border is
/// `railColor(for:)` rather than the raw calendar colour because `railColor` carries the
/// `railMinimumLuminance` floor, so a near-black calendar still gets a visible rim — and it is
/// drawn on the `chipBorderOpacity` ladder rather than the quieter `railBorderOpacity` one, which
/// is quiet precisely because a rail is marking the leading edge for it. Here nothing is.
struct MonthEventChip: View {
    let event: CalendarEventItem
    var calendar: Calendar = .current
    /// A click opens the event's editor, as the task chip beside it opens its inspector
    /// ([[T-5240]]).
    @State private var showEditor = false

    var body: some View {
        // Every tier below is solved against `railChipFill`'s own plate, so none of them is a
        // constant any more: the title clears `railTitleContrastTarget` and the time range
        // `railSecondaryContrastTarget` against the exact fill they land on. Pinned by
        // `CadenceContrastFloorTests.everyRailTreatmentTierLandsOnItsDeclaredRatioAgainstItsOwnPlate`
        // and, for which chip reads which family, by `CadenceCalendarChipTreatmentTests`.
        HStack(spacing: 4) {
            Text(event.title)
                .font(.system(size: 10))
                .foregroundStyle(CadenceCalendarEventStyle.railTitleColor(for: event.calendarColor))
                .lineLimit(1)
            if let time = event.chipTimeLabel(calendar: calendar) {
                Spacer(minLength: 2)
                Text(time)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        CadenceCalendarEventStyle.railSecondaryLabelColor(for: event.calendarColor)
                    )
                    .lineLimit(1)
                    .fixedSize()
                    // Same rule as the due marker: the chip is one non-wrapping line in a column
                    // a seventh of the grid wide, so the title is what gives up room.
                    .layoutPriority(1)
            }
        }
        .monthChipPlate(
            fill: CadenceCalendarEventStyle.railChipFill(for: event.calendarColor),
            border: CadenceCalendarEventStyle.railColor(for: event.calendarColor)
                .opacity(CadenceCalendarEventStyle.chipBorderOpacity())
        )
        .calendarEventChipEditor(isPresented: $showEditor) { event }
    }
}

/// The date line at the top of a month cell: an optional month abbreviation, then the day number
/// with today's marker.
///
/// Split out because the four `CalendarMonthDayEmphasis` states each want a different combination
/// of colour, weight and marker shape, and reading that as one small view is what makes it
/// obvious that a carried today gets *both* the marker and the month name.
private struct MonthDayNumberLabel: View {
    let dayNumber: String
    /// `nil` when the page the cell sits on already names its month.
    let monthAbbreviation: String?
    let emphasis: CalendarMonthDayEmphasis

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if let monthAbbreviation {
                Text(monthAbbreviation)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(emphasis.dateLabelColor)
            }
            Text(dayNumber)
                .font(.system(size: 12, weight: emphasis.dateLabelWeight))
                .foregroundStyle(emphasis.dateLabelColor)
                .frame(width: 24, height: 24)
                .background {
                    if let fill = emphasis.todayDiscFill {
                        Circle().fill(fill)
                    }
                }
                .overlay {
                    if let stroke = emphasis.todayRingStroke {
                        Circle().strokeBorder(stroke, lineWidth: CalendarMonthDayEmphasis.todayRingWidth)
                    }
                }
        }
    }
}

/// What a month cell's event chips are drawn from: the day's **all-day** events, then its timed
/// segments. **T-3163.**
///
/// The cell used to ask `timedEvents(for:)` alone, so a holiday, a trip or an offsite was drawn in
/// the week view's all-day lane and simply did not exist on the month grid. All-day items lead,
/// as they do in Apple Calendar's month cell: they describe the whole day, so they read before the
/// day's appointments. They take the same `MonthEventChip` as a timed event — the rail plate and
/// the calendar-hued title `AllDayEventChip` wears — and `chipTimeLabel` already answers `nil` for
/// an all-day event, so the chip draws no time it does not have. Both kinds then compete for the
/// cell's rows as one "events" count through `CadenceCalendarMonthCellPriority`, unchanged.
///
/// Both halves go through the shared `CalendarEventDayCache`, so the grid still runs at most one
/// fetch of each half per day rather than one per cell per pass.
enum CalendarMonthCellEventSupport {
    static func items(
        for date: Date,
        eventCache: CalendarEventDayCache,
        source: any CalendarEventDaySource,
        calendar: Calendar = .current
    ) -> [CalendarEventItem] {
        let allDay = eventCache.allDayEvents(for: date, calendarManager: source)
            .map { CalendarEventItem(event: $0) }
        let timed = CalendarEventItem.timedSegments(
            from: eventCache.timedEvents(for: date, calendarManager: source),
            for: date,
            calendar: calendar
        )
        return allDay + timed
    }
}

struct MonthDayCell: View {
    let date: Date
    var todayKey: String = DateFormatters.todayKey()
    let tasks: [AppTask]
    let allTasks: [AppTask]
    /// The month the **grid** is reading as, from the scroll position. What decides whether this
    /// cell is lit or dropped back onto the carried plate.
    let displayMonth: Date
    /// The month of the block that **draws** this cell — a fact about the tiling, and independent
    /// of the tint above.
    ///
    /// Only the month abbreviation reads it, and that is the point of keeping it separate. The
    /// abbreviation exists because a block carries the 0–6 days before its successor's first Sunday
    /// as trailing fill, so the 1st is not a reliable landmark and a carried day has to name itself.
    /// That is still true of exactly those days, whatever month the viewport happens to be reading
    /// — tying it to `displayMonth` instead would print "Aug" on all thirty-one August cells the
    /// moment the grid tipped over into September.
    let blockMonth: Date
    /// Shared with the timeline day columns. Without it every cell ran its own synchronous
    /// `EKEventStore.events(matching:)` — 42 cells per realized month block, re-run on every
    /// task edit and every month boundary crossed. The cache is keyed by
    /// `CalendarManager.storeVersion` and dropped wholesale when that changes, so it cannot
    /// disagree with EventKit.
    let eventCache: CalendarEventDayCache
    /// Height the week row was given. Every cell in a row is pinned to it, so the offset table
    /// the header is derived from stays an exact model of the layout.
    var rowHeight: CGFloat = CalendarMonthGridMetrics.cellHeight
    /// [[T-6211]]. The grid's one notice slot, owned by `MonthGridView` — the board's
    /// `dropFailureNotice`, so a refused drop says why instead of only springing back.
    @Binding var dropFailureNotice: String?

    @Environment(CalendarManager.self) private var calendarManager
    /// T-5351. What "open this day" is on the Mac. There is **no Day view mode** here —
    /// `CadenceCalendarViewMode` has `week`, `twoWeeks` and `month`, and the toolbar picker offers
    /// only Week and Month — so the ticket's "opens that day in Day view" resolves to the one thing
    /// this app means by opening a day: leave the grid for the timeline and scroll that day's
    /// column under the cursor, which is exactly what a calendar deep link and the widget already
    /// do. `CalendarPageView.applyExternalCalendarJump` takes the request.
    @Environment(CalendarNavigationManager.self) private var calendarNavigationManager
    @Environment(\.modelContext) private var modelContext

    /// A card released over this cell, for the dashed ring. Chips drag since this entry's own
    /// first half; before this one there was nothing on the grid that would take the drop, so a
    /// user could pick a task up with nowhere to put it down.
    @State private var isDropTargeted = false

    private let cal = Calendar.current

    private var dateKey: String { DateFormatters.dateKey(from: date) }

    /// All-day events first, then the timed segments — see `CalendarMonthCellEventSupport`.
    private var calendarEvents: [CalendarEventItem] {
        CalendarMonthCellEventSupport.items(for: date, eventCache: eventCache, source: calendarManager)
    }

    private var visibleEvents: [CalendarEventItem] {
        guard calendarManager.isAuthorized else { return [] }
        return calendarEvents
    }

    var body: some View {
        // Resolved once per body pass: `visibleEvents` reaches into EventKit, and the chip
        // lists, the cap and the overflow count all need the same answer.
        let events = visibleEvents
        // Also once per pass. The old computed properties re-ran `isDateInToday` and a four-
        // component month comparison on every access, several times per cell, across hundreds
        // of cells.
        let emphasis = CalendarMonthDayLabelSupport.emphasis(
            for: date,
            displayMonth: displayMonth,
            today: DateFormatters.date(from: todayKey) ?? Date(),
            calendar: cal
        )
        let layout = CalendarMonthCellLayout.chipLayout(
            totalItems: tasks.count + events.count,
            rowHeight: rowHeight
        )
        // `chipLayout` says how many slots there are; `CadenceCalendarMonthCellPriority` says who
        // gets them. This cell used to fill them bundles → tasks → events, so a crowded day hid
        // its events and kept its tasks — see that type for why the owner reversed it, and why
        // both platforms now ask the same function.
        let split = CadenceCalendarMonthCellPriority.split(
            events: events.count,
            tasks: tasks.count,
            capacity: layout.visible
        )
        let eventChips = Array(events.prefix(split.events))
        let taskChips = Array(tasks.prefix(split.tasks))

        return VStack(alignment: .leading, spacing: CalendarMonthCellLayout.headerChipSpacing) {
            MonthDayNumberLabel(
                dayNumber: DateFormatters.dayNumber.string(from: date),
                monthAbbreviation: CalendarMonthDayLabelSupport.monthAbbreviation(
                    for: date,
                    isCarriedOntoAnotherBlock: CalendarMonthDayLabelSupport.isCarried(
                        date,
                        ontoBlock: blockMonth,
                        calendar: cal
                    ),
                    calendar: cal
                ),
                emphasis: emphasis
            )
            .padding(.top, 6)
            .padding(.horizontal, 8)
            .frame(height: CalendarMonthCellLayout.headerHeight, alignment: .top)

            VStack(alignment: .leading, spacing: CalendarMonthCellLayout.chipSpacing) {
                // Drawn in the same order they were ranked, and in the same order the iOS cell
                // draws them: what survives the cut reads top-down as what matters most.
                ForEach(eventChips) { event in
                    MonthEventChip(event: event)
                }
                ForEach(taskChips) { task in
                    MonthTaskChip(task: task, dayKey: dateKey, todayKey: todayKey)
                }
                if split.hidden > 0 {
                    Text(CadenceTaskSurfaceOptions.moreLabel(hidden: split.hidden))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5)
                        .frame(height: CalendarMonthCellLayout.chipHeight, alignment: .center)
                        // Its own target rather than only the cell's, so the one row that exists
                        // *because* the day has more than it can show is the row that takes you to
                        // the day. Same action; stated here so it cannot be lost to a future
                        // layout change that stops the cell's own tap reaching this strip.
                        .contentShape(Rectangle())
                        .onTapGesture { openDay() }
                }
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Top-aligned: if a very short window ever leaves the chip stack taller than its row,
        // the clip has to eat the last chip, never the day number.
        .frame(height: rowHeight, alignment: .top)
        .clipped()
        // Plate first, then today's wash on top of it. Two layers rather than one colour because
        // the in-month plate is opaque and the wash is not: today's cell is a washed *in-month*
        // cell, not a wash floating over whatever is behind the grid.
        .background {
            ZStack {
                emphasis.cellBackground
                if let wash = emphasis.cellWash {
                    wash
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.columnGridOpacity))
                .frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.gridRuleOpacity))
                .frame(height: 0.5)
        }
        // After the plate and the rules, so the whole cell is hit-testable including its empty
        // lower half. The chips keep their own taps: an inner gesture wins over this one, so a
        // click on a task chip still opens its inspector rather than leaving the grid.
        .contentShape(Rectangle())
        .onTapGesture { openDay() }
        // [[T-7067]]. The cell published a loose "26", an optional "Aug" and its chips, and the
        // click above had no accessibility path. `.contain` keeps every chip its own element under
        // a cell that names its day; the action is the click's own `openDay()`, so a pointer and
        // an assistive client leave the grid for the same timeline column. No `.isSelected`: the
        // Mac grid has no selected day.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityLabel(date: date, taskCount: tasks.count, visibleEventCount: events.count))
        .accessibilityAction { openDay() }
        .accessibilityAction(named: Self.openDayActionName, openDay)
        .dropDestination(for: String.self) { items, _ in
            handleTaskDrop(items)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.72), style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .padding(2)
            }
        }
    }

    /// [[T-7067]]. What VoiceOver calls this cell: iOS's month-cell wording ([[T-573]]'s
    /// `countedDayLabel`) for parity, over the same sum iOS counts — every task plus every event
    /// the cell would draw (`visibleEvents`, empty while calendar access is off). The Mac draws no
    /// capsule, but every one of those items is on screen as a chip or inside the "+N more" line,
    /// so the figure is one the cell shows, in pieces.
    nonisolated static func accessibilityLabel(date: Date, taskCount: Int, visibleEventCount: Int) -> String {
        CadenceCalendarDayAccessibility.countedDayLabel(date: date, itemCount: taskCount + visibleEventCount)
    }

    /// The named action beside the default one, so "Open day" is listed in VoiceOver's actions menu.
    nonisolated static let openDayActionName = "Open day"

    /// T-5351. See `calendarNavigationManager` above for why this is a timeline jump rather than a
    /// Day mode: the Mac has no Day mode to switch to.
    private func openDay() {
        // `open(dateKey:)` and not `open(date:)`: a month cell's `date` is a start of day, so
        // passing it would hand the jump hour 0 and land every click on the top of the column.
        // The default `now` is the user's clock, which is the row they are already thinking in.
        calendarNavigationManager.open(dateKey: dateKey)
    }

    private func handleTaskDrop(_ items: [String]) -> Bool {
        let outcome = CalendarMonthDayDropSupport.drop(
            items,
            on: dateKey,
            in: allTasks,
            modelContext: modelContext
        )
        dropFailureNotice = CalendarMonthDayDropSupport.failureNotice(after: outcome)
        return outcome == .applied
    }
}

/// T-5351. **A task card released on a Month day cell, rescheduled onto that day.**
///
/// The Month chips have clicked and dragged since this entry's first half landed, and no day on
/// the grid took the drop — so the user could pick a task up with nowhere to put it down. That
/// asymmetry is what the owner chose option (a) to close.
///
/// It resolves the payload and then hands off to `CalendarPageBoardDropSupport.schedule`, the
/// Calendar Board day column's own handler, rather than writing a date here: one definition of what
/// dropping a task on a day means, so the grid cannot drift from the board on the
/// `CalendarBoardPlannerSupport` action, the detach from a bundle, the materialised
/// `estimatedMinutes`, or the undo on a refused commit ([[T-1980]]).
///
/// Resolution happens before anything is written, for `CalendarPageBoardDropSupport`'s reason: a
/// payload this grid cannot place must not reach `commit` at all, or a drop that moved no field
/// would commit whatever unrelated pending work the app's single `ModelContext` is holding.
///
/// A refusal answers `.refused`, which the cell reports as `false`, so the card springs back to
/// where it was picked up instead of being drawn somewhere the store never accepted ([[T-566]],
/// [[T-1952]]). [[T-6211]]: and it says why, in the grid's notice slot above the weeks, with the
/// board's own sentence and the board's own mapping — see `failureNotice(after:)`.
@MainActor
enum CalendarMonthDayDropSupport {
    static func drop(
        _ items: [String],
        on dateKey: String,
        in allTasks: [AppTask],
        modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        guard let payload = items.first,
              let taskID = TaskDragPayload.taskID(from: payload),
              let task = allTasks.first(where: { $0.id == taskID }) else { return .resolvedNothing }
        return CalendarPageBoardDropSupport.schedule(
            task,
            on: dateKey,
            modelContext: modelContext,
            reconciler: reconciler,
            commit: commit
        )
    }

    /// [[T-6211]]. The Calendar Board's mapping (`handleDayColumnDrop`), so the grid and the board
    /// answer a refusal with one sentence: `.refused` is "Nothing was changed", and any other
    /// outcome clears a sentence an earlier drop left standing. `.resolvedNothing` stays silent,
    /// as it does on the board ([[T-1952]]).
    static func failureNotice(after outcome: TasksPanelDropOutcome) -> String? {
        outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil
    }
}

struct CalDayHeaderView: View {
    let date: Date
    var todayKey: String = DateFormatters.todayKey()
    var allDayEvents: [EKEvent] = []
    var unscheduledTasks: [AppTask] = []

    private let cal = Calendar.current
    private var isToday: Bool { DateFormatters.dateKey(from: date) == todayKey }
    private var allDayEventItems: [CalendarAllDayEventItem] {
        allDayEvents.map { CalendarAllDayEventItem(event: $0) }
    }

    /// The band's row budget. The Mac band is a fixed `calAllDayBannerHeight` frame around a
    /// vertical `ScrollView`, so every chip stays reachable and nothing is capped: `.max` asks the
    /// shared rule for its order (events first) without rationing anything. T-1474.
    private static let bandCapacity = Int.max

    /// Who goes first in the band, by the same `CadenceCalendarAllDayBandPriority` iOS uses.
    private var split: CadenceCalendarMonthCellPriority.Split {
        CadenceCalendarAllDayBandPriority.split(
            allDayEvents: allDayEventItems.count,
            unscheduledTasks: unscheduledTasks.count,
            capacity: Self.bandCapacity
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: CadenceCalendarWeekdayHeaderMetrics.labelSpacing) {
                Text(DateFormatters.dayOfWeek.string(from: date).uppercased())
                    .cadenceUppercaseLabel(
                        reading: DateFormatters.dayOfWeek.string(from: date),
                        size: CadenceCalendarWeekdayHeaderMetrics.labelSize,
                        kerning: CadenceCalendarWeekdayHeaderMetrics.labelKerning
                    )
                    .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                Text(DateFormatters.dayNumber.string(from: date))
                    .font(.system(size: CadenceCalendarWeekdayHeaderMetrics.dayNumberSize, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Theme.onColor(for: Theme.blue) : Theme.text)
                    .frame(
                        width: CadenceCalendarWeekdayHeaderMetrics.dayCircleSize,
                        height: CadenceCalendarWeekdayHeaderMetrics.dayCircleSize
                    )
                    .background(isToday ? Theme.blue : Color.clear)
                    .clipShape(Circle())
            }
            .frame(height: calDayHeaderHeight)
            .frame(maxWidth: .infinity)
            .background(isToday ? Theme.blue.opacity(0.05) : Theme.bg)

            allDayBannerContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: calAllDayBannerHeight, alignment: .top)
                .background(isToday ? Theme.blue.opacity(0.03) : Theme.bg)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.timelineDaySeparatorOpacity))
                .frame(width: CalendarVisualStyle.timelineDaySeparatorLineWidth)
        }
        // T-7064: the label iOS's `iOSCalendarTimelineDayHeader` has carried since T-573, from the
        // same shared builder, so the Mac header says the day and what its band holds rather than
        // "Mon" and "26" as two loose words. The band draws every chip (`bandCapacity` is `.max`),
        // so both counts are exactly what is on screen. `.contain` first, so each chip stays its
        // own openable element instead of inheriting the day's name (T-7034's rule). No
        // `.isSelected`: like iOS's, this header has no selected state to announce.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            CadenceCalendarDayAccessibility.timelineDayLabel(
                date: date,
                allDayEventCount: allDayEventItems.count,
                unscheduledCount: unscheduledTasks.count
            )
        )
    }

    private var allDayBannerContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(allDayEventItems.prefix(split.events)) { item in
                    AllDayEventChip(event: item.event)
                }
                ForEach(unscheduledTasks.prefix(split.tasks)) { task in
                    AllDayTaskChip(task: task, dayKey: DateFormatters.dateKey(from: date), todayKey: todayKey)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}

struct AllDayTaskChip: View {
    let task: AppTask
    /// Day column this chip is parked in. A task reaches the all-day lane by its do date
    /// (`CadenceScheduleSupport.unscheduledTasksByDate`), never its due date, so the column is not
    /// the deadline and the chip still marks a due date of its own.
    let dayKey: String
    var todayKey: String = DateFormatters.todayKey()
    @State private var showInspector = false

    /// Same rule as `MonthTaskChip.glyphTint`, and for the same reason: urgency and done-green are
    /// information that survives the plate, `Theme.dim` is a grey solved against `Theme.bg` that
    /// does not.
    private var allDayGlyphTint: Color {
        if task.isCancelled { return CadenceCalendarEventStyle.plateTertiaryLabelColor() }
        if task.isDone { return Theme.green }
        return CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone, todayKey: todayKey)?.tint
            ?? CadenceCalendarEventStyle.plateTertiaryLabelColor()
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: task.isCancelled ? "xmark.circle.fill" : (task.isDone ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: CalendarMonthCellLayout.completionGlyphSize, weight: .semibold))
                .foregroundStyle(allDayGlyphTint)
            Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                .font(.system(size: 10))
                .foregroundStyle(
                    task.isDone
                        ? CadenceCalendarEventStyle.plateSecondaryLabelColor(isActive: showInspector)
                        : CadenceCalendarEventStyle.platePrimaryLabelColor
                )
                .lineLimit(1)
            Spacer(minLength: 2)
            CalendarChipDueMarker(dueDateKey: task.dueDate, dayKey: dayKey, todayKey: todayKey, isDone: task.isDone)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One solved plate rather than a neutral surface plus a tint of the list colour over it.
        // The open-inspector state is what the two-layer form was spending its second fill on, and
        // the plate treatment already has a state for it: `isActive` is the ladder's middle rung.
        .background(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .fill(
                    CadenceCalendarEventStyle.plateChipFill(
                        for: Color(hex: task.containerColor),
                        isActive: showInspector
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .strokeBorder(
                    Color(hex: task.containerColor)
                        .opacity(CadenceCalendarEventStyle.chipBorderOpacity(isActive: showInspector)),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.chipShadow, radius: 4, y: 1)
        .calendarTaskChipInteractions(task: task, showInspector: $showInspector)
    }
}

extension View {
    /// What a calendar task chip does when touched: a click or right-click opens the task's
    /// inspector anchored on the chip, and the chip drags as the task's id. One definition for the
    /// Week/Day all-day lane's `AllDayTaskChip` and the Month grid's `MonthTaskChip` ([[T-5351]]):
    /// the Month chip used to be a plain plate, so the same task opened from one view and did
    /// nothing in the other.
    func calendarTaskChipInteractions(task: AppTask, showInspector: Binding<Bool>) -> some View {
        contentShape(Rectangle())
            .onTapGesture { showInspector.wrappedValue = true }
            .overlay {
                RightClickActionTrigger {
                    showInspector.wrappedValue = true
                }
            }
            .popover(isPresented: showInspector, arrowEdge: .bottom) {
                TaskDetailPopover(task: task)
            }
            .draggable(task.id.uuidString)
    }
}

/// An all-day event, wearing the **rail** treatment's colours since T-3160.
///
/// **The all-day lane was asked the rail question separately from the month grid, and answered the
/// same way — but not because the two are the same size.** This chip is a 10pt line, so about 12pt
/// of text, plus 2pt of padding top and bottom: roughly 16pt against the month chip's fixed 15.
/// That is not the "taller row" a rail would need. Both are clipped to the same
/// `CalendarVisualStyle.chipRadius` of 6, so 12 of those 16 points of the leading edge are corner
/// and a 3pt `railWidth` bar would survive as a ~4pt nub — marginally longer than the month grid's
/// 3pt and just as unreadable as an identity marker. The lane that *is* tall enough is the timed
/// canvas, which is T-3161's. If the all-day banner ever grows a two-line chip this is worth
/// re-asking; at 16pt it is not close.
struct AllDayEventChip: View {
    let event: EKEvent
    /// A click opens the event's editor ([[T-5240]]); the drag onto the timeline stays.
    @State private var showEditor = false

    private var eventColor: Color {
        Color(cgColor: event.calendar?.cgColor ?? Theme.nsDim.cgColor)
    }

    var body: some View {
        // Title in the calendar's own hue, solved against the plate below it — same family and
        // same reasoning as `MonthEventChip`, including why the border is `railColor` rather than
        // the raw calendar colour.
        Text(CadenceEventTitleSupport.displayTitle(event.title))
            .font(.system(size: 10))
            .foregroundStyle(CadenceCalendarEventStyle.railTitleColor(for: eventColor))
            .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .fill(CadenceCalendarEventStyle.railChipFill(for: eventColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .strokeBorder(
                    CadenceCalendarEventStyle.railColor(for: eventColor)
                        .opacity(CadenceCalendarEventStyle.chipBorderOpacity()),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.chipShadow, radius: 3, y: 1)
        // The all-day form of the item, as `CalendarBoardEventDisplayItem.editItem` builds it.
        .calendarEventChipEditor(isPresented: $showEditor) { CalendarEventItem(event: event) }
        // A read-only calendar cannot take the all-day → timed conversion the drop asks for
        // ([[T-5241]]), so its chip does not offer the drag.
        .calendarEventDraggable(
            CalendarEventDragPayload.string(for: event),
            isEditable: CalendarEventEditPopover.isEditable(event)
        )
    }
}

struct CalDayColumn: View {
    let date: Date
    let todayKey: String
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let eventCache: CalendarEventDayCache
    let colWidth: CGFloat
    let hourHeight: CGFloat
    let showHalfHourMarks: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    /// The refusal this column can produce: a drag-created task the store would not take
    /// ([[T-655]]). Its block sibling went with the Block feature's creation paths ([[T-3170]]).
    @State private var taskCreateFailed = false

    private var dateKey: String {
        DateFormatters.dateKey(from: date)
    }

    private var externalEventItems: [CalendarEventItem] {
        return CalendarEventItem.timedSegments(from: eventCache.timedEvents(for: date, calendarManager: calendarManager), for: date)
    }

    var body: some View {
        TimelineDayCanvas(
            date: date,
            dateKey: dateKey,
            todayKey: todayKey,
            tasks: tasks,
            allTasks: allTasks,
            areas: areas,
            projects: projects,
            metrics: TimelineMetrics(startHour: calStartHour, endHour: calEndHour, hourHeight: hourHeight),
            width: colWidth,
            style: .calendar,
            showCurrentTimeDot: true,
            showHalfHourMarks: showHalfHourMarks,
            showWorkHoursHighlight: true,
            // The draft is written whole, **on its own day** ([[T-3171]] (iv)): the panel's Do row
            // can move it off this column, and this host used to overwrite that with the column's
            // own `dateKey`, so the popover had to refuse the move. Due and Repeat ride in the
            // same value ([[T-3171]] (iii)).
            onCreateTask: createTask,
            onDropTaskAtMinute: { task, startMin in
                SchedulingActions.commitDropTask(task, to: dateKey, startMin: startMin, in: modelContext)
            },
            externalEvents: externalEventItems,
            onCreateEvent: { draft in
                calendarManager.createStandaloneEvent(draft, hostDay: date)
            },
            prefersCalendarEventCreation: true,
            onDropAllDayEventAtMinute: { payload, startMin in
                let sourceDate = DateFormatters.date(from: payload.sourceDateKey) ?? date
                let event = eventCache.allDayEvents(for: sourceDate, calendarManager: calendarManager)
                    .first { CalendarEventIdentity.matches($0, identifier: payload.eventIdentifier) }
                    ?? calendarManager.event(withIdentifier: CalendarEventIdentity.lookupIdentifier(from: payload.eventIdentifier))
                // The chip offers no drag for a read-only event; a payload from anywhere else is
                // refused here rather than by EventKit after the fact ([[T-5241]]).
                guard let event, CalendarEventEditPopover.isEditable(event) else { return }
                calendarManager.convertAllDayEventToTimed(event, startMin: startMin, dateKey: dateKey)
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.timelineDaySeparatorOpacity))
                .frame(width: CalendarVisualStyle.timelineDaySeparatorLineWidth)
        }
        // Both refusals are alerts rather than inline notices for the reason `SchedulePanel`'s is:
        // the draft popover the user typed into has already dismissed itself by the time the store
        // answers, so there is nothing left on screen to write under.
        .alert(TaskCreationService.createFailureAlertTitle, isPresented: $taskCreateFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(TaskCreationService.saveFailureNotice)
        }
    }

    /// **The drag-created task is committed here, and a refusal is named here ([[T-655]]).**
    ///
    /// The closure this replaces called `SchedulingActions.createTask`, which is handed this
    /// column's `ModelContext` and so — correctly — leaves the commit to whoever owns the unit of
    /// work. Nobody did: the task, its subtasks and its container assignment sat pending in the
    /// app's one context while the quick-create popover closed as though they had landed.
    ///
    /// The same write the Today timeline makes (`SchedulePanelDataSupport.insertDragCreatedTask`),
    /// so the two hosts cannot disagree about which day, due date or series a draft is stored with.
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
}
#endif
