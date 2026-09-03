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
    var isDone: Bool = false
    var calendar: Calendar = .current

    private var urgency: CadenceDueUrgency? {
        guard !dueDateKey.isEmpty, dueDateKey != dayKey else { return nil }
        return CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone)
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
/// Tasks get a faint neutral plate so each row stays its own click target; events keep the
/// saturated filled plate they already had. Keeping the two fills different is deliberate —
/// with the completion circle removed from events, fill is the only thing left distinguishing
/// a calendar event from a task at a glance.
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

/// A task inside a month cell. Renders the same hollow completion circle the task rows use
/// everywhere else in the app, tinted by deadline urgency rather than by list colour — the
/// chip's own wash already carries the list.
struct MonthTaskChip: View {
    let task: AppTask
    /// `yyyy-MM-dd` of the cell this chip is drawn in.
    let dayKey: String

    private var glyph: String {
        if task.isCancelled { return "xmark.circle.fill" }
        if task.isDone { return "checkmark.circle.fill" }
        return "circle"
    }

    private var glyphTint: Color {
        if task.isCancelled { return Theme.dim }
        if task.isDone { return Theme.green }
        // No due date is not urgency-free noise: it collapses to the same neutral `.later`
        // tint, so only a real deadline ever colours the circle.
        return CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone)?.tint ?? Theme.dim
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.system(size: CalendarMonthCellLayout.completionGlyphSize, weight: .semibold))
                .foregroundStyle(glyphTint)
            Text(task.title)
                .font(.system(size: 10))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 2)
            CalendarChipDueMarker(dueDateKey: task.dueDate, dayKey: dayKey, isDone: task.isDone)
        }
        .monthChipPlate(
            fill: Theme.surfaceHover,
            wash: Color(hex: task.containerColor).opacity(task.isDone ? 0.05 : 0.10),
            border: Theme.borderSubtle
        )
    }
}

struct MonthBundleChip: View {
    let bundle: TaskBundle

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tray.full")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(bundle.displayTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .monthChipPlate(
            fill: Theme.surfaceHover,
            wash: Theme.amber.opacity(0.14),
            border: Theme.borderSubtle
        )
    }
}

struct MonthEventChip: View {
    let event: CalendarEventItem
    var calendar: Calendar = .current

    var body: some View {
        HStack(spacing: 4) {
            Text(event.title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.onColor)
                .lineLimit(1)
            if let time = event.chipTimeLabel(calendar: calendar) {
                Spacer(minLength: 2)
                Text(time)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.onColorSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    // Same rule as the due marker: the chip is one non-wrapping line in a column
                    // a seventh of the grid wide, so the title is what gives up room.
                    .layoutPriority(1)
            }
        }
        .monthChipPlate(
            fill: CalendarEventVisualStyle.chipFill(for: event.calendarColor),
            wash: Theme.subtleWash,
            border: event.calendarColor.opacity(CalendarEventVisualStyle.chipBorderOpacity())
        )
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

struct MonthDayCell: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
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

    @Environment(CalendarManager.self) private var calendarManager

    private let cal = Calendar.current

    private var dateKey: String { DateFormatters.dateKey(from: date) }

    private var calendarEvents: [CalendarEventItem] {
        CalendarEventItem.timedSegments(from: eventCache.timedEvents(for: date, calendarManager: calendarManager), for: date)
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
            today: Date(),
            calendar: cal
        )
        let layout = CalendarMonthCellLayout.chipLayout(
            totalItems: bundles.count + tasks.count + events.count,
            rowHeight: rowHeight
        )
        let bundleChips = Array(bundles.prefix(layout.visible))
        let taskChips = Array(tasks.prefix(max(0, layout.visible - bundleChips.count)))
        let eventChips = Array(events.prefix(max(0, layout.visible - bundleChips.count - taskChips.count)))

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
                ForEach(bundleChips) { bundle in
                    MonthBundleChip(bundle: bundle)
                }
                ForEach(taskChips) { task in
                    MonthTaskChip(task: task, dayKey: dateKey)
                }
                ForEach(eventChips) { event in
                    MonthEventChip(event: event)
                }
                if layout.overflow > 0 {
                    Text(CadenceTaskSurfaceOptions.moreLabel(hidden: layout.overflow))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5)
                        .frame(height: CalendarMonthCellLayout.chipHeight, alignment: .center)
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
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.majorGridOpacity))
                .frame(height: 0.5)
        }
    }
}

struct CalDayHeaderView: View {
    let date: Date
    var allDayEvents: [EKEvent] = []
    var unscheduledTasks: [AppTask] = []

    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(date) }
    private var allDayEventItems: [CalendarAllDayEventItem] {
        allDayEvents.map { CalendarAllDayEventItem(event: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: CadenceCalendarWeekdayHeaderMetrics.labelSpacing) {
                Text(DateFormatters.dayOfWeek.string(from: date).uppercased())
                    .font(.system(size: CadenceCalendarWeekdayHeaderMetrics.labelSize, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    .kerning(CadenceCalendarWeekdayHeaderMetrics.labelKerning)
                Text(DateFormatters.dayNumber.string(from: date))
                    .font(.system(size: CadenceCalendarWeekdayHeaderMetrics.dayNumberSize, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Theme.onColor : Theme.text)
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
    }

    private var allDayBannerContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(unscheduledTasks) { task in
                    AllDayTaskChip(task: task, dayKey: DateFormatters.dateKey(from: date))
                }
                ForEach(allDayEventItems) { item in
                    AllDayEventChip(event: item.event)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}

struct AllDayTaskChip: View {
    let task: AppTask
    /// Day column this chip is parked in. A task reaches the all-day lane by either its
    /// scheduled date or its due date, so the chip cannot let its column stand in for a deadline.
    let dayKey: String
    @State private var showInspector = false

    private var allDayGlyphTint: Color {
        if task.isCancelled { return Theme.dim }
        if task.isDone { return Theme.green }
        return CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone)?.tint ?? Theme.dim
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: task.isCancelled ? "xmark.circle.fill" : (task.isDone ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: CalendarMonthCellLayout.completionGlyphSize, weight: .semibold))
                .foregroundStyle(allDayGlyphTint)
            Text(task.title)
                .font(.system(size: 10))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 2)
            CalendarChipDueMarker(dueDateKey: task.dueDate, dayKey: dayKey, isDone: task.isDone)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(Color(hex: task.containerColor).opacity(showInspector ? 0.18 : 0.12))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Theme.chipShadow, radius: 4, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { showInspector = true }
        .overlay {
            RightClickActionTrigger {
                showInspector = true
            }
        }
        .popover(isPresented: $showInspector, arrowEdge: .bottom) {
            TaskDetailPopover(task: task)
        }
        .draggable(task.id.uuidString)
    }
}

struct AllDayEventChip: View {
    let event: EKEvent

    private var eventColor: Color {
        Color(cgColor: event.calendar?.cgColor ?? Theme.nsDim.cgColor)
    }

    var body: some View {
        Text(CadenceEventTitleSupport.displayTitle(event.title))
            .font(.system(size: 10))
            .foregroundStyle(Theme.onColor)
            .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(CalendarEventVisualStyle.chipFill(for: eventColor))
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(Theme.subtleWash)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .strokeBorder(eventColor.opacity(CalendarEventVisualStyle.chipBorderOpacity()), lineWidth: 1)
        )
        .shadow(color: Theme.chipShadow, radius: 3, y: 1)
        .draggable(CalendarEventDragPayload.string(for: event))
    }
}

struct CalDayColumn: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let eventCache: CalendarEventDayCache
    let colWidth: CGFloat
    let hourHeight: CGFloat
    let showHalfHourMarks: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    /// The two refusals this column can produce. Separate flags because they are separate units of
    /// work with separate sentences — a task the store would not take and a block the store would
    /// not take are not the same message ([[T-655]]).
    @State private var taskCreateFailed = false
    @State private var bundleCreateFailed = false

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
            tasks: tasks,
            bundles: bundles,
            allTasks: allTasks,
            allBundles: allBundles,
            areas: areas,
            projects: projects,
            metrics: TimelineMetrics(startHour: calStartHour, endHour: calEndHour, hourHeight: hourHeight),
            width: colWidth,
            style: .calendar,
            showCurrentTimeDot: true,
            showHalfHourMarks: showHalfHourMarks,
            showWorkHoursHighlight: true,
            usesTaskPanelForTaskCreation: false,
            onCreateTask: { title, startMin, endMin, containerSelection, sectionName, notes, subtaskTitles in
                createTask(
                    title: title,
                    startMin: startMin,
                    endMin: endMin,
                    containerSelection: containerSelection,
                    sectionName: sectionName,
                    notes: notes,
                    subtaskTitles: subtaskTitles
                )
            },
            onCreateBundle: { title, startMin, endMin, selectedTasks in
                createBundle(title: title, startMin: startMin, endMin: endMin, adding: selectedTasks)
            },
            onDropTaskAtMinute: { task, startMin in
                SchedulingActions.dropTask(task, to: dateKey, startMin: startMin)
            },
            onDropBundleAtMinute: { bundle, startMin in
                SchedulingActions.dropBundle(bundle, to: dateKey, startMin: startMin)
            },
            onDropTaskOnBundle: { task, bundle in
                SchedulingActions.addTask(task, to: bundle)
            },
            externalEvents: externalEventItems,
            onCreateEvent: { title, startMin, endMin, calendarID, notes in
                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: date, notes: notes)
            },
            prefersCalendarEventCreation: true,
            onDropAllDayEventAtMinute: { payload, startMin in
                let sourceDate = DateFormatters.date(from: payload.sourceDateKey) ?? date
                let event = eventCache.allDayEvents(for: sourceDate, calendarManager: calendarManager)
                    .first { CalendarEventIdentity.matches($0, identifier: payload.eventIdentifier) }
                    ?? calendarManager.event(withIdentifier: CalendarEventIdentity.lookupIdentifier(from: payload.eventIdentifier))
                guard let event else { return }
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
        .alert(CadenceTaskMutationSupport.bundleCreateFailureAlertTitle, isPresented: $bundleCreateFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CadenceTaskMutationSupport.bundleSaveFailureNotice)
        }
    }

    /// **The drag-created task is committed here, and a refusal is named here ([[T-655]]).**
    ///
    /// The closure this replaces called `SchedulingActions.createTask`, which is handed this
    /// column's `ModelContext` and so — correctly — leaves the commit to whoever owns the unit of
    /// work. Nobody did: the task, its subtasks and its container assignment sat pending in the
    /// app's one context while the quick-create popover closed as though they had landed.
    private func createTask(
        title: String,
        startMin: Int,
        endMin: Int,
        containerSelection: TaskContainerSelection,
        sectionName: String,
        notes: String,
        subtaskTitles: [String]
    ) {
        do {
            try SchedulingActions.insertTask(
                title: title,
                dateKey: dateKey,
                startMin: startMin,
                endMin: endMin,
                containerSelection: containerSelection,
                sectionName: sectionName,
                notes: notes,
                subtaskTitles: subtaskTitles,
                areas: areas,
                projects: projects,
                in: modelContext
            )
        } catch {
            taskCreateFailed = true
        }
    }

    /// **The block and the tasks ticked into it are one commit ([[T-655]]).**
    ///
    /// The same fix [[T-636]](e) made on `SchedulePanel`, through the same unit: `insertBundle`
    /// creates the block, moves the ticked tasks into it, and either commits both or puts both
    /// back. Committing the block first and adding its members afterwards would leave an empty
    /// block in the store and the memberships pending, which is the same defect with a smaller
    /// blast radius.
    private func createBundle(title: String, startMin: Int, endMin: Int, adding tasks: [AppTask]) {
        do {
            try SchedulingActions.insertBundle(
                title: title,
                dateKey: dateKey,
                startMin: startMin,
                endMin: endMin,
                adding: tasks,
                in: modelContext
            )
        } catch {
            bundleCreateFailed = true
        }
    }
}
#endif
