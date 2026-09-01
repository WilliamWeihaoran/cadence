#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

enum iOSCalendarBoardColumnItem: Identifiable {
    case event(iOSCalendarBoardEventItem)
    case bundle(TaskBundle)
    case task(AppTask)

    var id: String {
        switch self {
        case .event(let item):
            return "event-\(item.id)"
        case .bundle(let bundle):
            return "bundle-\(bundle.id.uuidString)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        }
    }

    var sortKey: CalendarBoardSortKey {
        switch self {
        case .event(let item):
            return item.sortKey
        case .bundle(let bundle):
            return CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1)
        case .task(let task):
            return CalendarBoardPlannerSupport.sortKey(for: task, kindRank: 2)
        }
    }
}

struct iOSCalendarBoardEventItem: Identifiable {
    let id: String
    let title: String
    let calendarTitle: String
    let startMin: Int
    let endMin: Int
    let isAllDay: Bool
    let isRecurring: Bool
    let color: Color
    /// The row this was derived from, kept so a surface that lets you open an event — the month
    /// agenda — does not have to rebuild the mapping from this item's id back to an `EKEvent`. That
    /// id is assembled here from an identifier, a date key and a start minute, and `items(from:for:)`
    /// drops events that do not intersect the day, so it is not a lookup a caller can reconstruct.
    let event: EKEvent

    var sortKey: CalendarBoardSortKey {
        CalendarBoardPlannerSupport.sortKeyForCalendarEvent(
            id: id,
            startMinute: startMin,
            isAllDay: isAllDay,
            kindRank: 0
        )
    }

    static func items(from events: [EKEvent], for date: Date, calendar: Calendar = .current) -> [iOSCalendarBoardEventItem] {
        events.compactMap { event in
            iOSCalendarBoardEventItem(event: event, date: date, calendar: calendar)
        }
    }

    private init?(event: EKEvent, date: Date, calendar: Calendar) {
        let dateKey = DateFormatters.dateKey(from: date)
        // **T-438.** `CadenceEventNoteSupport.rawIdentifier` is what an event's identifier
        // *is*; this used to re-spell it, and the re-spelling was wrong in a way the composed `id`
        // below could not survive. `event.eventIdentifier ?? event.calendarItemIdentifier` only
        // catches a **nil** event identifier, not an empty one, so an event carrying `""` fell
        // through to `"\(dateKey)-\(event.hash)"` — and `EKEvent.hash` is `NSObject`'s, derived
        // from the instance's address. It is not a property of the event, so the same meeting read
        // twice gets two ids, and none of them survives a relaunch. The shared rule tries the empty
        // case too and ends on a content-derived fallback instead.
        let eventIdentifier = CadenceEventNoteSupport.rawIdentifier(for: event)
        self.event = event
        title = iOSCalendarEventSupport.title(for: event)
        calendarTitle = event.calendar?.title ?? "Apple Calendar"
        isAllDay = event.isAllDay
        isRecurring = CadenceEventNoteSupport.isRecurringSeriesMember(event)
        color = iOSCalendarEventSupport.color(for: event.calendar)

        if event.isAllDay {
            startMin = CalendarBoardPlannerSupport.allDaySortMinute
            endMin = 24 * 60
        } else {
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let eventStart = event.startDate ?? dayStart
            let fallbackEnd = eventStart.addingTimeInterval(30 * 60)
            let eventEnd = max(event.endDate ?? fallbackEnd, fallbackEnd)
            let segmentStart = max(eventStart, dayStart)
            let segmentEnd = min(eventEnd, dayEnd)
            guard segmentEnd > segmentStart else { return nil }
            let startComponents = calendar.dateComponents([.hour, .minute], from: segmentStart)
            let rawStart = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
            let duration = max(5, Int(segmentEnd.timeIntervalSince(segmentStart) / 60))
            startMin = min(max(0, rawStart), 24 * 60 - 5)
            endMin = min(24 * 60, max(startMin + 5, startMin + duration))
        }

        id = "\(eventIdentifier)-\(dateKey)-\(startMin)"
    }
}

/// An event as it appears in a **board column**, next to task and bundle cards.
///
/// It used to be a solid plate of the calendar's colour — the treatment that belongs to a
/// *timeline* block, where the plate is the whole affordance. In a column of neutral washed cards
/// it read as a slab dropped in from another screen, and its metadata chips had to fight it. This
/// is now the same neutral-card-plus-tint-wash macOS's `CalendarBoardEventCard` uses, on the shared
/// `CadenceCalendarEventStyle` opacity ladder, so an event, a bundle and a task in one column read
/// as three cards rather than three designs.
struct iOSCalendarBoardEventCard: View {
    let item: iOSCalendarBoardEventItem

    private var subtitle: String {
        if item.isAllDay {
            return "All day"
        }
        return TimeFormatters.timeRange(startMin: item.startMin, endMin: item.endMin)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isAllDay ? "calendar" : "clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    CadenceBoardMetadataChip(
                        title: subtitle,
                        systemImage: item.isAllDay ? "sun.max" : "clock",
                        tint: item.color,
                        cardCornerRadius: Theme.radiusCard,
                        fillsWidth: true
                    )
                    if item.isRecurring {
                        CadenceBoardMetadataChip(
                            title: "Repeats",
                            systemImage: "repeat",
                            tint: item.color,
                            cardCornerRadius: Theme.radiusCard,
                            fillsWidth: true
                        )
                    }
                }

                if !item.calendarTitle.isEmpty {
                    Text(item.calendarTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(CadenceCalendarEventStyle.surfaceOpacity(isActive: false)))
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(item.color.opacity(CadenceCalendarEventStyle.tintOpacity()))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(item.color.opacity(CadenceCalendarEventStyle.borderOpacity()), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The width of a fixed-width board column, shared by the list kanban board and the Calendar
/// Board's regular-width day columns. It was two literals — 272 for the kanban board, 300 for the
/// Calendar Board — with nothing behind the 28pt gap; both hold `iOSBoardTaskCard` at the same
/// density, so both want the same width. Compact-width Calendar Board columns are the one genuine
/// exception and compute their own: see `CalendarBoardPlannerSupport.compactColumnWidth`, which
/// sizes a column to one screen with the next one peeking.
let iOSBoardColumnWidth: CGFloat = 300

/// The **one** task card used by every board surface: the list/section kanban board and the
/// Calendar Board's day columns. Density is fixed and identical on both — completion circle, title,
/// tags, a two-column grid of time / date / list chips, then the unfinished subtasks — so the boards
/// cannot drift apart again, which is the rule `KanbanCard` already enforces on macOS.
///
/// **Tags and subtasks arrived here under T-173**, when macOS's card had both and this one neither.
/// Neither was added because macOS had it: tags are identity the user chose and a card that omits
/// them is a card you cannot recognise your own work on, and a subtask list is the app's answer —
/// measured, on a phone — to what a dense task surface says about a checklist. Both are capped from
/// the same shared figures the task rows use, so no surface decides for itself how much of a task
/// fits. The macOS card's *uncapped* subtask list was corrected in the same change rather than
/// copied here.
///
/// The per-board knobs are `showsContainerChip` — a section column already sits inside one list, so
/// repeating the name on every card there is noise — and `dayAlreadyStatedBySurface`, for a day
/// column that has named its day in its own header. Both are macOS's knobs for macOS's reasons; a
/// board card answers "what does this card repeat?" the same way on any device.
///
/// This replaced a second card in `iOSListSupportViews` — a flat `Theme.surface` rectangle with a
/// 13.5pt title and plain icon-and-text metadata — that made the same task read as a different
/// kind of object depending on which board you opened.
/// What a surface has to supply before its task cards **or its timeline blocks** will accept "drop
/// a task on a task to make a block". The three things only make sense together — the dragged task
/// has to be resolvable from a payload, the drop has to go somewhere, and the enclosing column has
/// to hear about targeting so it can stop treating the same drop as a reschedule — so they arrive as
/// one value and a surface opts in whole.
///
/// It was `iOSBoardTaskCardBundleDrop` until T-243 gave the day timeline the same gesture, and the
/// rename is the lesson `nestedDropTargetID` already recorded one file over: **a helper named for
/// one subject is why the second one never got checked against it.** `iOSTimelineTaskBlock` takes
/// this exact value rather than a near-copy of it, which is what keeps the two surfaces' answer to
/// "may this task be dropped on" a single decision.
///
/// `onTargetedChanged` defaults to a no-op because only one of the two surfaces needs it: the
/// Calendar Board's day column carries its own `dropDestination` that fires on the same release, and
/// the timeline's day column carries none — its only gesture is the `SpatialTapGesture` that creates
/// a task at a minute, and a drag is not a tap.
struct iOSBundleFormingDrop {
    let allTasks: [AppTask]
    let onDropTask: (AppTask) -> Void
    var onTargetedChanged: (Bool) -> Void = { _ in }
}

struct iOSBoardTaskCard: View {
    @Bindable var task: AppTask
    var showsContainerChip: Bool = true
    /// The day this card's surface has already stated, if it states one. See
    /// `CadenceBoardCardMetadata.repeatsSurfaceDay`.
    var dayAlreadyStatedBySurface: String? = nil
    /// Non-`nil` only where dropping another task on this one can form a block: the card needs a day
    /// *and* a time-of-day slot, because that is what a `TaskBundle` is. A list's task list has
    /// neither, and a completed card is not something you plan around, so both leave this `nil` and
    /// the drop falls through to whatever is underneath.
    var bundleFormingDrop: iOSBundleFormingDrop? = nil

    @State private var isBundleFormingTargeted = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // T-201: presented by the page's `iOSTaskInspectorHost`, not by this card. A board column is a
    // filtered `ForEach` like any task list — moving a card's task out of the column it is in is
    // most of what the inspector is *for* — so a card-owned sheet closed itself on the same writes
    // `iOSTaskRow`'s did.
    @Environment(\.iOSTaskInspector) private var taskInspector

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var listColor: Color {
        Color(hex: task.containerColor)
    }

    /// Square on the leading edge so the list colour strip reads as a strip, rounded elsewhere.
    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: Theme.radiusCard,
            topTrailingRadius: Theme.radiusCard,
            style: .continuous
        )
    }

    var body: some View {
        if let drop = bundleFormingDrop {
            // `.dropDestination` has no erased form and `isTargeted` fires whether or not the
            // closure accepts the drop, so a card that cannot form a block must not carry the
            // modifier at all — an always-attached version returning `false` would still light up
            // under the drag. Same reasoning as `iOSBoardColumnPaging` in iOSCalendarBoardView.
            // `bundleFormingDrop` is fixed per call site, so this branch never flips at runtime.
            card.dropDestination(for: String.self) { items, _ in
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
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: toggleCompletion) {
                    iOSTaskCompletionCircle(glyph: .resolve(task: task))
                        .frame(width: 16, height: 16)
                        .frame(width: 30, height: 30)
                        .iOSExpandedHitArea()
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel(CadenceTaskQuerySupport.isFinishedTask(task) ? "Mark not done" : "Mark done")

                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: isRegularWidth ? 15 : 14, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Read-only, unlike macOS's strip, which is a button opening the tag picker: a card
            // here is opened by tapping it, so a tappable region inside it that does something
            // else is a target competing with its own container. Tags are edited in the detail
            // sheet that tap opens.
            CompactTagStrip(tags: task.sortedTags, limit: CadenceTaskPresentationSupport.rowTagLimit)

            // Guarded, because the grid is no longer guaranteed non-empty: a kanban card suppresses
            // its list chip, so an undated task on the list board has nothing to show, and an
            // unguarded `LazyVGrid` would still charge the `VStack` its 10pt of spacing.
            if !metadataChips.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(metadataChips, id: \.id) { chip in
                        CadenceBoardMetadataChip(
                            title: chip.title,
                            systemImage: chip.icon,
                            tint: chip.color,
                            cardCornerRadius: Theme.radiusCard,
                            fillsWidth: true
                        )
                    }
                }
            }

            subtaskRows
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background {
            ZStack {
                cardShape.fill(Theme.surfaceElevated.opacity(0.82))
                cardShape.fill(listColor.opacity(task.isDone ? 0.05 : 0.12))
                if isBundleFormingTargeted {
                    cardShape.fill(Theme.amber.opacity(0.16))
                }
            }
        }
        .clipShape(cardShape)
        // One layer, one radius: the targeted state re-tints the border this card already draws
        // rather than adding a second ring. Amber because that is what a block reads as on this
        // board — `iOSCalendarBoardBundleCard` is amber, at this same stroke weight and opacity, so
        // a card about to *become* one says so in the colour it is about to take.
        .overlay {
            cardShape.strokeBorder(
                isBundleFormingTargeted ? Theme.amber.opacity(0.74) : Theme.borderSubtle,
                lineWidth: isBundleFormingTargeted ? 1.5 : 1
            )
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(listColor)
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            taskInspector(task)
        }
    }

    /// The unfinished subtasks, capped, with a line saying how many are left over — the same shape
    /// `iOSTaskRow` draws beneath a task, from the same shared figures, and reusing the same
    /// `iOSTaskRowSubtaskRow` rather than a card-shaped copy of it. That row is a `Button` on
    /// purpose: it outranks the card's own tap, so ticking a subtask off a board card does not open
    /// the detail sheet instead.
    ///
    /// The overflow line opens the sheet, because that is where the rest of the checklist is. It is
    /// the card's own tap target rather than a nested `Button` — there is nothing here for a
    /// separate control to do that the card does not already do.
    @ViewBuilder
    private var subtaskRows: some View {
        let subtasks = CadenceTaskPresentationSupport.listedSubtasks(for: task)
        if !subtasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subtasks) { subtask in
                    iOSTaskRowSubtaskRow(subtask: subtask)
                }

                if let hidden = CadenceTaskPresentationSupport.unlistedSubtaskCount(for: task) {
                    Text(CadenceTaskSurfaceOptions.moreLabel(hidden: hidden))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .frame(minHeight: 30)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// **What the card states is `CadenceBoardCardMetadata`'s decision, not this file's.** This card
    /// used to build its own list and had quietly dropped the **do date** from it: the same task
    /// read as planned-for-today on a Mac board and as undated here. The do, due and list chips now
    /// come from the one descriptor macOS's `KanbanCard.metadataRows` reads.
    ///
    /// The **time** chip stays local, and it is the one genuine arrangement difference between the
    /// two cards. macOS states the slot as a start (`9am`) in a top row beside an *editable*
    /// duration badge; this card has no pointer to hover a badge with, so it states the whole range
    /// in a chip and reaches the estimate through the detail sheet. Same fact, two shapes.
    private var metadataChips: [iOSCalendarBoardMetadataItem] {
        var chips: [iOSCalendarBoardMetadataItem] = []

        if task.scheduledStartMin >= 0 {
            chips.append(
                .init(
                    id: "time",
                    icon: "clock.fill",
                    // Neutral. A card in a day column having a time is the ordinary case, not the
                    // exceptional one — blue here fired on nearly every card and left the due chip,
                    // which does go red when it means something, no louder than its neighbour.
                    title: TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin),
                    color: Theme.dim
                )
            )
        }

        // One colour per chip rather than macOS's identity/label pair: this chip is inert, and a
        // tinted glyph beside grey text on a grey pill reads as disabled — the reason
        // `CadenceBoardMetadataChip` tints both. `labelColor` is the loud half of the pair, so an
        // ordinary date stays `Theme.dim` here and an overdue one goes red exactly as it does on
        // the Mac.
        let boardChips = CadenceBoardCardMetadata.chips(
            for: task,
            showsContainer: showsContainerChip,
            dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
        )
        for chip in boardChips {
            chips.append(
                .init(
                    id: chip.id,
                    icon: chip.icon,
                    title: chip.text,
                    color: chip.kind == .list ? chip.identityColor : chip.labelColor
                )
            )
        }

        return chips
    }

    private func toggleCompletion() {
        CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)
    }
}

struct iOSCalendarBoardBundleCard: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let onDropTask: (AppTask) -> Void
    var onDropTargetedChanged: (Bool) -> Void = { _ in }

    // T-217: the panel is opened on the host, not owned here. This card lives in a
    // `ForEach(bundles)` filtered by the column's day, so a `@State showDetail` + `.sheet` was torn
    // down by the panel's own Save the moment it moved the block to another date.
    @Environment(\.iOSBundleInspector) private var bundleInspector

    @State private var isTargeted = false

    private var tasks: [AppTask] {
        bundle.sortedTasks
    }

    private var allDone: Bool {
        !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(allDone ? Theme.dim : Theme.amber)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(bundle.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(allDone ? Theme.dim : Theme.text)
                            .strikethrough(allDone, color: Theme.dim)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("×\(tasks.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.subdued)
                    }

                    CadenceBoardMetadataChip(
                        title: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                        systemImage: "clock",
                        tint: allDone ? Theme.dim : Theme.amber,
                        cardCornerRadius: Theme.radiusCard,
                        fillsWidth: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tasks.prefix(2)) { task in
                            HStack(spacing: 5) {
                                iOSTaskCompletionCircle(glyph: .resolve(task: task))
                                    .frame(width: 10, height: 10)
                                Text(task.title.isEmpty ? "Untitled" : task.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text.opacity(0.85))
                                    .strikethrough(task.isDone, color: Theme.dim)
                                    .lineLimit(1)
                            }
                        }
                        if tasks.count > 2 {
                            Text(CadenceTaskSurfaceOptions.moreLabel(hidden: tasks.count - 2))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(allDone ? Theme.doneFill.opacity(0.10) : Theme.amber.opacity(isTargeted ? 0.20 : 0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(isTargeted ? Theme.amber.opacity(0.74) : (allDone ? Theme.doneFill.opacity(0.35) : Theme.amber.opacity(0.2)), lineWidth: isTargeted ? 1.5 : 1)
        }
        .onTapGesture {
            bundleInspector(bundle)
        }
        .contextMenu {
            Button {
                bundleInspector(bundle)
            } label: {
                Label("Edit Block", systemImage: "square.and.pencil")
            }
        }
        .draggable(TaskDragPayload.bundleString(for: bundle.id))
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let taskID = TaskDragPayload.taskID(from: payload),
                  let task = allTasks.first(where: { $0.id == taskID }) else { return false }
            onDropTask(task)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
            onDropTargetedChanged(targeted)
        }
    }
}

private struct iOSCalendarBoardMetadataItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let color: Color
}

// The chip itself is `CadenceBoardMetadataChip` in
// `Shared/Components/CadenceBoardMetadataChip.swift`. `iOSCalendarBoardMetadataChip` was declared
// here and its doc comment opened "Matches macOS's `CalendarBoardMetadataChip`" — an obligation
// written down with nothing to enforce it. `iOSCalendarBoardMetadataItem` above stays: it is this
// board's display model, not a second copy of the chip.

#endif
