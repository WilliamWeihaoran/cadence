#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

enum iOSCalendarBoardColumnItem: Identifiable {
    case event(iOSCalendarBoardEventItem)
    case task(AppTask)

    var id: String {
        switch self {
        case .event(let item):
            return "event-\(item.id)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        }
    }

    // The kind ranks are 0 and 2 rather than 0 and 1 because [[T-3170]] removed the Block card
    // that sat between them. They are a sort order, not a dense index, and renumbering the task
    // rank would have to agree with macOS's column — which still ranks the same three kinds —
    // for no gain.
    var sortKey: CalendarBoardSortKey {
        switch self {
        case .event(let item):
            return item.sortKey
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
        calendarTitle = event.calendar?.title ?? CadenceAppleCalendarNaming.unnamedCalendarTitle
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

/// An event as it appears in a **board column**, next to task cards.
///
/// It used to be a solid plate of the calendar's colour — the treatment that belongs to a
/// *timeline* block, where the plate is the whole affordance. In a column of neutral washed cards
/// it read as a slab dropped in from another screen, and its metadata chips had to fight it. This
/// is now the same neutral-card-plus-tint-wash macOS's `CalendarBoardEventCard` uses, on the shared
/// `CadenceCalendarEventStyle` opacity ladder, so an event and a task in one column read as two
/// cards rather than two designs.
struct iOSCalendarBoardEventCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
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
                .cadenceFont(.rowTitle, base: 13, weight: .semibold)
                .foregroundStyle(item.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .cadenceFont(.rowTitle, base: 14, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) ? nil : 2)

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
                        .cadenceFont(.metadata, base: 11, weight: .medium)
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) ? nil : 1)
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

/// The task card used by every iOS board surface: the list/section kanban board and the Calendar
/// Board's day columns.
///
/// **Its anatomy is `CadenceLedgerCard`'s, not this file's** ([[T-8181]]). The card is a fixed state
/// gutter washed in the list colour — completion ring, priority mark, recurrence glyph stacked so
/// the three states scan vertically — a title, and one dim 11pt run of the form
/// `9:00a · 45m · Tue · #deep-work`. There is no pill chrome, and a completed card collapses to a
/// struck line. The Mac board draws the same view; what this file supplies is the four things a
/// touch device forces, each argued at the call site: the ring's 44pt target, inert tokens, the
/// iOS subtask row, and no settling overlay.
///
/// This replaced a tinted 2×2 `LazyVGrid` of chips. That grid and the Mac's grey 50/50 chip split
/// were the same facts in two costumes, which is why the two boards looked unrelated.
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
struct iOSBoardTaskCard: View {
    @Bindable var task: AppTask
    var showsContainerChip: Bool = true
    /// The day this card's surface has already stated, if it states one. See
    /// `CadenceBoardCardMetadata.repeatsSurfaceDay`.
    var dayAlreadyStatedBySurface: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var completionDiameter: CGFloat {
        CadenceTypeScale.size(.rowTitle, base: CadenceLedgerCardMetrics.ringBase, at: dynamicTypeSize, scaling: scaling)
    }

    private var isSettled: Bool {
        CadenceTaskCompletionState.resolve(task: task).isSettled
    }

    private var gutterWidth: CGFloat {
        CadenceLedgerCardMetrics.gutterWidth(at: dynamicTypeSize, scaling: scaling)
    }

    @Environment(\.modelContext) private var modelContext
    // T-201: presented by the page's `iOSTaskInspectorHost`, not by this card. A board column is a
    // filtered `ForEach` like any task list — moving a card's task out of the column it is in is
    // most of what the inspector is *for* — so a card-owned sheet closed itself on the same writes
    // `iOSTaskRow`'s did.
    @Environment(\.iOSTaskInspector) private var taskInspector

    private var listColor: Color {
        Color(hex: task.containerColor)
    }

    /// One resolve for the circle and its name, so the two cannot read different states.
    private var completionGlyph: CadenceTaskCompletionGlyph {
        CadenceTaskCompletionGlyph.resolve(task: task)
    }

    /// The card's metadata run, from the shared builder.
    ///
    /// `placeholders` is left off, which is the one content difference between this card and the
    /// Mac's and is forced by input rather than chosen: every token there is a picker, so an empty
    /// field still needs something under the pointer; here the card's own tap opens the inspector,
    /// so a token standing for nothing would say nothing and do nothing.
    private var tokens: [CadenceLedgerToken] {
        CadenceLedgerCardSupport.tokens(
            startMinute: task.scheduledStartMin,
            estimatedMinutes: task.estimatedMinutes,
            chips: CadenceBoardCardMetadata.chips(
                for: task,
                showsContainer: showsContainerChip,
                dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
            ),
            tagNames: CadenceLedgerTagTokens.names(for: task)
        )
    }

    var body: some View {
        CadenceLedgerCard(
            title: TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle),
            isSettled: isSettled,
            isStruckThrough: isSettled,
            listColor: listColor,
            priority: task.priority,
            isRecurring: task.isRecurring,
            tokens: tokens,
            ring: { completionRing },
            // Inert. A tappable region inside a tappable card competes with its own container on
            // touch, which is not true under a pointer — so the Mac's tokens are pickers and these
            // are labels. Every field they state is edited in the sheet this card's tap opens.
            tokenView: { CadenceLedgerTokenLabel(token: $0) },
            subtasks: { subtaskRows },
            settlingOverlay: { EmptyView() }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            taskInspector(task)
        }
    }

    /// The gutter's completion control. Drawn at the shared ring size; the 44pt target around it is
    /// the part a fingertip forces and a pointer does not.
    ///
    /// The expansion is measured off the **gutter**, not off the circle, so the target grows into
    /// the colour strip the ring already occupies instead of out over the title beside it.
    private var completionRing: some View {
        Button(action: toggleCompletion) {
            iOSTaskCompletionCircle(glyph: completionGlyph, diameter: completionDiameter)
                .frame(width: gutterWidth, height: completionDiameter)
                .iOSExpandedHitArea(max(0, (44 - gutterWidth) / 2))
        }
        .buttonStyle(.iosPressable)
        // Named for what the tap does, off the glyph's own state — the row's rule since
        // T-611. This card kept a "Mark done" / "Mark not done" pair of its own, so a
        // task mid-completion, where the tap cancels it, was announced "Mark done".
        .accessibilityLabel(completionGlyph.state.accessibilityActionLabel)
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
                        .cadenceFont(.metadata, base: 12, weight: .medium)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: scaling == .enabled)
                        .frame(minHeight: CadenceTypeScale.height(30, holding: .metadata, at: dynamicTypeSize, scaling: scaling))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func toggleCompletion() {
        CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)
    }
}

// The event card's chip is `CadenceBoardMetadataChip` in
// `Shared/Components/CadenceBoardMetadataChip.swift`. A private copy was declared here and its doc
// comment opened "Matches macOS's `CalendarBoardMetadataChip`" — an obligation written down with
// nothing to enforce it. This board's own display model went with the task card's chip grid in
// [[T-8181]]: a Ledger run is `[CadenceLedgerToken]`, which is shared, so there is nothing left
// here for a per-board model to hold.

#endif
