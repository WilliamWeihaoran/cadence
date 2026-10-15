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

    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// Minute the live edge drag started from. `@State` rather than `@GestureState` because the
    /// value has to survive the frame in which the gesture ends.
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
    @ViewBuilder
    private func edgeHandle(isTop: Bool) -> some View {
        if !draft.isAllDay && !draft.spansMultipleDays {
            Capsule()
                .fill(CadenceCalendarEventStyle.railColor(for: tint))
                .frame(width: 30, height: 4)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
                .offset(y: isTop ? -14 : 14)
                .gesture(edgeDrag(isTop: isTop))
                .accessibilityLabel(isTop ? "Drag to move start" : "Drag to move end")
        }
    }

    private func edgeDrag(isTop: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let anchor = resizeAnchor ?? (isTop ? draft.startMin : draft.endMin)
                if resizeAnchor == nil { resizeAnchor = anchor }
                let minutes = Int(((value.translation.height / max(hourHeight, 1)) * 60).rounded())
                if isTop {
                    draft.moveStartEdge(toMinute: anchor + minutes)
                } else {
                    draft.moveEndEdge(toMinute: anchor + minutes)
                }
            }
            .onEnded { _ in resizeAnchor = nil }
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
/// The choices the panel lists and the two writes it ends in. Each host keeps only what is its own
/// — its framing, its calendar-access wording, and what it does once a write lands — so a change to
/// what a created task *gets* (a due date, a series, a list) is one edit here rather than two that
/// drift, which is how the docked bar ended up able to make only a 30-minute task ([[T-3169]]).
///
/// Every write returns `String?`: `nil` when it landed, the sentence the panel shows when it did not.
@MainActor
enum iOSScheduleDraftCreation {
    /// Inbox, then the lists a new task may be put in — **narrowed by the shared picker rule**
    /// (`pickableAreas` / `pickableProjects`: active lists, sorted, plus the one the draft names), as
    /// `iOSContainerChoicePopover` narrows them for the quick-create sheet it replaced. Built from
    /// the raw queries, which is what the iPad popover did, it offered archived and completed lists.
    static func listChoices(for draft: CadenceScheduleDraft, areas: [Area], projects: [Project]) -> [CadenceSchedulePanelChoice] {
        let choice = CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
        var rows = [
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .inbox),
                name: "Inbox",
                color: Theme.blue,
                systemImage: "tray.fill"
            )
        ]
        rows += CadenceTaskComposerSupport.pickableAreas(
            areas,
            selectedID: CadenceTaskComposerSupport.selectedAreaID(choice)
        ).map {
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .area($0.id)),
                name: $0.name,
                color: Color(hex: $0.colorHex),
                systemImage: "folder.fill"
            )
        }
        rows += CadenceTaskComposerSupport.pickableProjects(
            projects,
            selectedID: CadenceTaskComposerSupport.selectedProjectID(choice)
        ).map {
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .project($0.id)),
                name: $0.name,
                color: Color(hex: $0.colorHex),
                systemImage: "square.stack.3d.up.fill"
            )
        }
        return rows
    }

    static func area(for draft: CadenceScheduleDraft, in areas: [Area]) -> Area? {
        let choice = CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
        guard let id = CadenceTaskComposerSupport.selectedAreaID(choice) else { return nil }
        return areas.first { $0.id == id }
    }

    static func project(for draft: CadenceScheduleDraft, in projects: [Project]) -> Project? {
        let choice = CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
        guard let id = CadenceTaskComposerSupport.selectedProjectID(choice) else { return nil }
        return projects.first { $0.id == id }
    }

    /// **Empty for the Inbox**, so the panel greys its Section row out there. The Inbox has no
    /// sections to choose between — `sectionNames` answers the lone default for it — and the
    /// quick-create sheet has always disabled the row rather than offer a one-row picker.
    static func sectionChoices(for draft: CadenceScheduleDraft, areas: [Area], projects: [Project]) -> [String] {
        let area = area(for: draft, in: areas)
        let project = project(for: draft, in: projects)
        guard area != nil || project != nil else { return [] }
        return CadenceTaskMutationSupport.sectionNames(forArea: area, project: project)
    }

    /// The section name a list change leaves behind: the chosen one where the new list has it,
    /// that list's first otherwise.
    static func normalizedSectionName(for draft: CadenceScheduleDraft, areas: [Area], projects: [Project]) -> String {
        CadenceTaskMutationSupport.normalizedSectionName(
            draft.sectionName,
            area: area(for: draft, in: areas),
            project: project(for: draft, in: projects)
        )
    }

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
        let area = area(for: draft, in: areas)
        let project = project(for: draft, in: projects)
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
            repeatRule: draft.repeatRule
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

    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: iOSScheduleDraftCreation.listChoices(for: draft, areas: areas, projects: projects),
                sectionChoices: iOSScheduleDraftCreation.sectionChoices(for: draft, areas: areas, projects: projects),
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
