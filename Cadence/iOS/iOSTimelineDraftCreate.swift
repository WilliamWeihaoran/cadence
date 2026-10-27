#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// The rectangle a press-and-hold leaves on the timed canvas, drawn **at the time it will occupy**,
/// in **the paint the thing it will become actually wears** ([[T-3169]]).
///
/// **This is the whole of the owner's complaint, stated as a view.** The docked
/// `iOSScheduleQuickCreateBar` it replaces sat under the canvas and said `Create at 4:00 PM` in
/// words, so the user read a sentence about a time instead of seeing a block at it; and it could
/// only ever make a 30-minute task, so there was nothing for the paint to be ambiguous about.
///
/// The treatments are `CadenceCalendarEventStyle`'s own, not an approximation of them: `rail*` while
/// Event is selected and `plate*` while Task is, exactly as `iOSCalendarEventBlock` and
/// `iOSTimelineTaskBlock` draw a committed one. A preview painted "like" a block is a second
/// implementation of the look that drifts the moment either treatment is re-solved — and T-3160
/// moved this assignment once already. Reading the same four functions means the draft repaints
/// with the real thing whenever the real thing changes.
///
/// It is read at `isSelected: true` throughout: a draft is the one block on the canvas being acted
/// on, and the selected rung of both ladders is the brightest — so it stands off the committed
/// blocks around it without a fifth fill invented for it.
struct iOSTimelineDraftBlock: View {
    @Binding var draft: CadenceScheduleDraft
    /// Points per hour on the canvas, so an edge drag becomes minutes without the block knowing
    /// anything else about the grid.
    let hourHeight: CGFloat
    /// An edge handle finished a drag that actually moved its edge ([[T-7551]]).
    ///
    /// The column puts the draft's editor back on this, and on nothing else. It used to infer the
    /// same fact from the outside, with a `DragGesture` over the whole block that captured the
    /// range on touch-down and compared it on release — which could not watch a touch without
    /// taking it from the scroll view. The handle is the one thing that knows, so the handle says.
    let onAdjusted: () -> Void

    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// Minute the edge had when the hold completed, held for as long as the adjustment is down.
    /// Every step is measured from it, a cancelled adjustment is put back to it, and it is `nil`
    /// whenever no adjustment is in progress — which is what makes a stray callback a no-op.
    @State private var resizeAnchor: Int?

    private var tint: Color {
        iOSTimelineDraftTint.color(
            for: draft,
            areas: areas,
            projects: projects,
            calendar: calendarManager.writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
        )
    }

    private var blockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        content
            .background {
                blockShape.fill(
                    draft.kind == .event
                        ? CadenceCalendarEventStyle.railFill(for: tint, isSelected: true)
                        : CadenceCalendarEventStyle.plateFill(for: tint, isSelected: true)
                )
            }
            .clipShape(blockShape)
            .overlay { blockShape.strokeBorder(rimColor, lineWidth: 1.5) }
            .overlay(alignment: .top) { edgeHandle(isTop: true) }
            .overlay(alignment: .bottom) { edgeHandle(isTop: false) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Draft \(draft.kind.title): \(draft.displayTitle), \(draft.scheduleLabel)")
    }

    /// The rail for an event, nothing for a task — the one structural difference between the two
    /// committed blocks, kept so the preview differs from itself in the same place the real pair
    /// differ from each other.
    private var content: some View {
        HStack(alignment: .top, spacing: 0) {
            if draft.kind == .event {
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.radiusControl,
                    bottomLeadingRadius: Theme.radiusControl,
                    style: .continuous
                )
                .fill(CadenceCalendarEventStyle.railColor(for: tint))
                .frame(width: CadenceCalendarEventStyle.railWidth)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: draft.kind == .event ? "calendar" : "circle.dashed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tertiaryInk)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(primaryInk)
                        .lineLimit(2)

                    Text(draft.scheduleLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var primaryInk: Color {
        draft.kind == .event
            ? CadenceCalendarEventStyle.railTitleColor(for: tint, isSelected: true)
            : CadenceCalendarEventStyle.platePrimaryLabelColor
    }

    private var secondaryInk: Color {
        draft.kind == .event
            ? CadenceCalendarEventStyle.railSecondaryLabelColor(for: tint, isSelected: true)
            : CadenceCalendarEventStyle.plateSecondaryLabelColor(isSelected: true)
    }

    private var tertiaryInk: Color {
        draft.kind == .event
            ? CadenceCalendarEventStyle.railTertiaryLabelColor(for: tint, isSelected: true)
            : CadenceCalendarEventStyle.plateTertiaryLabelColor(isSelected: true)
    }

    /// The draft's edge, brighter than a committed block's. An event reads its own
    /// `railBorderOpacity` ladder at the selected rung; a task has no rim ladder of its own, so it
    /// borrows the rail colour at the same weight rather than inventing a second one.
    private var rimColor: Color {
        CadenceCalendarEventStyle.railColor(for: tint)
            .opacity(CadenceCalendarEventStyle.railBorderOpacity(isSelected: true))
    }

    /// A grab handle at one end of the block.
    ///
    /// **A 32pt touch band over 4pt of paint.** A draft can be one snap step tall, well under a
    /// finger, so the hit area is hung *outside* the block with a negative offset — the same trade
    /// `iOSExpandedHitArea` makes for a 26pt control, done by hand because this target has to
    /// straddle the block's edge rather than surround its centre.
    ///
    /// **The band is why the hold is here** ([[T-7551]]). This was a
    /// `DragGesture(minimumDistance: 1)`, and a SwiftUI drag takes the touch from the enclosing
    /// `ScrollView` the moment it has it — so the band, which is most of a one-hour draft and
    /// 14pt of plain canvas past each end, answered every finger that landed on it. Measured on
    /// `Cadence-iPadPro11`: a 300pt upward swipe over a 4:45–5:45 PM draft scrolled the timeline
    /// **zero points** and left the draft at **4:45–5:00 PM**, collapsed to the fifteen-minute
    /// floor with its editor dismissed. The owner's verdict was that the collapse is the worse
    /// half: *"the draft collapsing is worse than the scrolling."*
    ///
    /// **The hold, and not a direction test.** The usual way to separate a drag from a pan on this
    /// canvas is the axis — `iOSRowHorizontalPanRecognizer` does exactly that for a task row — and
    /// it cannot work here, because an edge adjustment is a *vertical* drag and so is the scroll
    /// it is competing with. They are not separable by direction at all. They are separable in
    /// TIME, which is how every other time edit on this canvas is already spelled:
    /// `CadenceTimelineBlockEdit.liftPressDuration`, the same figure the press that drew this
    /// draft used and the same figure a committed block is held for before it may be moved.
    /// `minimumDistance` is not an option; [[T-2059]] measured it dead for this exact collision.
    ///
    /// **What it costs, stated rather than hidden.** An adjustment no longer begins the instant
    /// the finger lands: the handle waits out the hold first. That is a real loss of immediacy on
    /// a small target, and it is the price of the band never again eating a scroll or collapsing
    /// a block the user just drew. The failure it replaces destroyed 45 minutes silently; the one
    /// it introduces is that a flick aimed at the handle scrolls instead, which costs a second try.
    @ViewBuilder
    private func edgeHandle(isTop: Bool) -> some View {
        if !draft.isAllDay && !draft.spansMultipleDays {
            Capsule()
                .fill(CadenceCalendarEventStyle.railColor(for: tint))
                .frame(width: 30, height: 4)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
                .offset(y: isTop ? -14 : 14)
                .gesture(edgePressDrag(isTop: isTop))
                .accessibilityLabel(isTop ? "Drag to move start" : "Drag to move end")
        }
    }

    private func edgePressDrag(isTop: Bool) -> some UIGestureRecognizerRepresentable {
        iOSTimelinePressDrag(
            minimumPressDuration: CadenceTimelineBlockEdit.liftPressDuration,
            onPressed: { _ in resizeAnchor = isTop ? draft.startMin : draft.endMin },
            onChanged: { translation in moveEdge(isTop: isTop, translationY: translation.height) },
            onEnded: { _ in finishEdgeAdjustment(isTop: isTop, reverting: false) },
            onCancelled: { finishEdgeAdjustment(isTop: isTop, reverting: true) }
        )
    }

    /// Measured from the minute the edge had when the hold completed, never from the previous
    /// frame, so a slow drag cannot accumulate rounding.
    private func moveEdge(isTop: Bool, translationY: CGFloat) {
        guard let anchor = resizeAnchor else { return }
        let minutes = Int(((translationY / max(hourHeight, 1)) * 60).rounded())
        if isTop {
            draft.moveStartEdge(toMinute: anchor + minutes)
        } else {
            draft.moveEndEdge(toMinute: anchor + minutes)
        }
    }

    /// The finger is off the glass, or the system took the gesture away.
    ///
    /// **A cancelled adjustment puts the edge back**, which the `DragGesture` this replaces could
    /// not do: a SwiftUI gesture the system cancels never reaches `onEnded`, so it left the edge
    /// wherever the last callback had dragged it and the anchor standing for the next touch. A
    /// half-finished resize nobody asked for is the small version of the defect this whole handle
    /// was rewritten over.
    ///
    /// Only a touch that actually moved the edge reports an adjustment, so a hold that goes
    /// nowhere raises no editor — the invariant [[T-3246]]'s range comparison existed for, now
    /// stated by the one thing that knows it for certain rather than inferred from the outside.
    private func finishEdgeAdjustment(isTop: Bool, reverting: Bool) {
        guard let anchor = resizeAnchor else { return }
        resizeAnchor = nil
        let landed = isTop ? draft.startMin : draft.endMin
        guard landed != anchor else { return }
        if reverting {
            if isTop {
                draft.moveStartEdge(toMinute: anchor)
            } else {
                draft.moveEndEdge(toMinute: anchor)
            }
            return
        }
        onAdjusted()
    }
}

/// Which hue a draft is painted in, as a function rather than a computed property on a view.
///
/// Pulled out so the rule — list colour for a task, calendar colour for an event, `Theme.blue` when
/// neither has an owner yet — is one statement with one reader. `Theme.blue` on both arms rather
/// than a literal: an Inbox task has no list colour and a draft event has no calendar colour until
/// one is resolved, and both are "no owner yet" rather than a colour of their own.
enum iOSTimelineDraftTint {
    static func color(
        for draft: CadenceScheduleDraft,
        areas: [Area],
        projects: [Project],
        calendar: EKCalendar?
    ) -> Color {
        switch draft.kind {
        case .event:
            guard let calendar else { return Theme.blue }
            return iOSCalendarEventSupport.color(for: calendar)
        case .task:
            switch CadenceTaskComposerSupport.selection(fromToken: draft.listToken) {
            case .inbox:
                return Theme.blue
            case .area(let id):
                guard let area = areas.first(where: { $0.id == id }) else { return Theme.blue }
                return Color(hex: area.colorHex)
            case .project(let id):
                guard let project = projects.first(where: { $0.id == id }) else { return Theme.blue }
                return Color(hex: project.colorHex)
            }
        }
    }
}

/// What the two iOS hosts that **create** through the shared panel both need, stated once
/// ([[T-3171]]): the iPad timeline's popover (`iOSTimelineDraftPanelHost`) and the calendar's
/// quick-create sheet (`iOSCalendarQuickCreateSheet`).
///
/// The calendar rows the panel lists and the two writes it ends in. The list and section rows are
/// `CadenceScheduleDraftChoices`', the one rule the Mac's quick-create popover reads too. Each host
/// keeps only what is its own — its framing, its calendar-access wording, and what it does once a write lands — so a change to
/// what a created task *gets* (a due date, a series, a list) is one edit here rather than two that
/// drift, which is how the docked bar ended up able to make only a 30-minute task ([[T-3169]]).
///
/// Every write returns `String?`: `nil` when it landed, the sentence the panel shows when it did not.
@MainActor
enum iOSScheduleDraftCreation {
    static func calendarChoices(_ calendarManager: iOSCalendarManager) -> [CadenceSchedulePanelChoice] {
        calendarManager.writableCalendars.map {
            CadenceSchedulePanelChoice(
                id: $0.calendarIdentifier,
                name: $0.title,
                color: iOSCalendarEventSupport.color(for: $0),
                systemImage: "calendar"
            )
        }
    }

    /// An event draft names a calendar the user can write to, the first one when it names none.
    static func resolveCalendarSelection(_ draft: inout CadenceScheduleDraft, calendarManager: iOSCalendarManager) {
        guard draft.kind == .event else { return }
        if !calendarManager.writableCalendars.contains(where: { $0.calendarIdentifier == draft.calendarID }) {
            draft.calendarID = calendarManager.writableCalendars.first?.calendarIdentifier ?? ""
        }
    }

    /// An all-day task is an **untimed** task (`scheduledStartMin == -1`), not a 24-hour one — see
    /// `CadenceScheduleDraft.scheduledStartMin`.
    ///
    /// T-470's shape: the store refusing the write is caught and named, and returned *before*
    /// anything that reports success; the habit reconcile runs only after a task really landed.
    static func createTask(
        from draft: CadenceScheduleDraft,
        allTasks: [AppTask],
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) -> String? {
        let area = CadenceScheduleDraftChoices.area(for: draft, in: areas)
        let project = CadenceScheduleDraftChoices.project(for: draft, in: projects)
        let created: AppTask?
        do {
            created = try CadenceTaskMutationSupport.insertScheduledTask(
                title: draft.title,
                allTasks: allTasks,
                modelContext: modelContext,
                scheduledDate: draft.startDateKey,
                scheduledStartMin: draft.scheduledStartMin,
                estimatedMinutes: draft.estimateMinutes,
                configure: { task in
                    configure(task, from: draft, area: area, project: project, allTasks: allTasks)
                }
            )
        } catch {
            return TaskCreationService.saveFailureNotice
        }
        guard created != nil else { return "Add a title first." }
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
        return nil
    }

    private static func configure(
        _ task: AppTask,
        from draft: CadenceScheduleDraft,
        area: Area?,
        project: Project?,
        allTasks: [AppTask]
    ) {
        task.notes = draft.notes
        task.estimatedMinutes = draft.estimateMinutes
        task.dueDate = draft.dueDateKey
        if draft.priority != .none {
            task.priority = draft.priority
        }
        CadenceTaskMutationSupport.assignContainer(
            task,
            area: area,
            project: project,
            sectionName: draft.sectionName,
            allTasks: allTasks
        )
        if draft.repeatRule != .none {
            // Through the workflow support, not a bare `task.recurrenceRule =`: the series id has
            // to exist before the rule does, and that is the half a direct write leaves out.
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                draft.repeatRule,
                to: task,
                allTasks: allTasks,
                scope: .thisTask
            )
        }
    }

    /// Every exit that is not a created event says so and says why — the rule T-324/T-339 settled.
    /// A range the draft cannot spell was never offered to EventKit, so it names no cause (`nil`)
    /// rather than one that would read as EventKit's answer.
    static func createEvent(from draft: CadenceScheduleDraft, calendarManager: iOSCalendarManager) -> String? {
        guard let range = draft.eventDateRange() else {
            return CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)
        }
        if let failure = calendarManager.createEvent(
            title: draft.title,
            startDate: range.start,
            endDate: range.end,
            calendarID: draft.calendarID,
            notes: draft.notes,
            isAllDay: draft.isAllDay,
            location: draft.location,
            repeatRule: draft.repeatRule,
            // The EFFECTIVE mode, not the stored one ([[T-3229]]). `.onDate` with no day and
            // `.afterCount` with no count both mean "never", and the draft already owns that
            // degrade for every control that reads it; passing the raw mode would ask EventKit to
            // bound a series by a value the card never captured. Forwarded here rather than
            // resolved inside the manager, so the event write and the task write agree about what
            // the user's answer WAS before either of them acts on it.
            seriesEndMode: draft.effectiveSeriesEndMode,
            seriesEndDateKey: draft.seriesEndDateKey,
            seriesEndCount: draft.seriesEndCount
        ) {
            return CadenceCalendarEventEditingSupport.saveFailureNotice(for: failure)
        }
        return nil
    }
}

/// The iOS half of [[T-3171]]'s shared panel on the iPad timeline: it supplies the choices and
/// performs the writes, and draws nothing of its own.
///
/// Everything visible is `CadenceSchedulePanel`, which is in `Shared/Components` and holds no
/// `iOS*` type — that is what lets macOS adopt the same form. What cannot be shared is exactly what
/// is here and in `iOSScheduleDraftCreation`: SwiftData queries, `iOSCalendarManager`, and the two
/// mutations. The seam is `CadenceSchedulePanelChoice` (a token, a name and a colour) and
/// `CadenceSchedulePanelActions` (closures returning `String?` — `nil` when the write landed, the
/// sentence to show when it did not, which is the shape `CadenceChoicePopoverList`'s committing
/// form already uses).
struct iOSTimelineDraftPanelHost: View {
    @Binding var draft: CadenceScheduleDraft
    let onCancel: () -> Void
    let onCommitted: () -> Void
    /// `.returnedAfterAdjustment` when the column is putting the editor back after an edge drag
    /// ([[T-3252]]), so the keyboard does not come back with it. See `CadenceSchedulePanelTitleFocus`.
    var titleFocusAppearance: CadenceSchedulePanelTitleFocus.Appearance = .opened

    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: CadenceScheduleDraftChoices.listChoices(for: draft, areas: areas, projects: projects),
                sectionChoices: CadenceScheduleDraftChoices.sectionChoices(for: draft, areas: areas, projects: projects),
                calendarChoices: iOSScheduleDraftCreation.calendarChoices(calendarManager),
                calendarUnavailableNotice: calendarUnavailableNotice,
                actions: CadenceSchedulePanelActions(
                    commit: commit,
                    cancel: onCancel,
                    // Nothing exists yet on this path, so there is nothing to delete. The control
                    // is absent rather than disabled — see `CadenceSchedulePanelActions.delete`.
                    delete: nil
                )
            )
            .appearing(titleFocusAppearance)
        }
        .frame(width: CadenceSchedulePanelMetrics.preferredWidth)
        .frame(maxHeight: 620)
        .background(Theme.surfaceElevated)
        .presentationCompactAdaptation(.popover)
        .onAppear(perform: resolveCalendarSelection)
        .onChange(of: draft.kind) { _, _ in resolveCalendarSelection() }
    }

    /// Said instead of the picker when there is nothing to pick.
    ///
    /// **It never offers to request access.** `iOSCalendarQuickCreateSheet` does, because it is a
    /// full sheet with room to explain itself; a popover hanging off a block is not the place to
    /// raise a system permission prompt, so this names what is missing and leaves the request to
    /// the surface that owns it.
    private var calendarUnavailableNotice: String? {
        if !calendarManager.isAuthorized {
            return "Calendar access is needed to create events. Turn it on in Settings, then try again."
        }
        if calendarManager.writableCalendars.isEmpty {
            return "No writable calendars are available."
        }
        return nil
    }

    private func resolveCalendarSelection() {
        iOSScheduleDraftCreation.resolveCalendarSelection(&draft, calendarManager: calendarManager)
    }

    private func commit() -> String? {
        let failure: String?
        switch draft.kind {
        case .task:
            failure = iOSScheduleDraftCreation.createTask(
                from: draft,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                modelContext: modelContext
            )
        case .event:
            failure = iOSScheduleDraftCreation.createEvent(from: draft, calendarManager: calendarManager)
        }
        if failure == nil { onCommitted() }
        return failure
    }
}

#endif
