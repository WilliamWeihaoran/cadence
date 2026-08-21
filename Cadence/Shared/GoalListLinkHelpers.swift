import Foundation
import SwiftData

/// Which list a `GoalListLink` points at.
///
/// `GoalListLink` carries an `area` **and** a `project` relationship and expects exactly one of
/// them to be set — its `title` / `icon` / `colorHex` / `context` / `tasks` all read
/// `area ?? project`. Every call site used to restate that invariant itself, as a pair of
/// `insert(GoalListLink(goal:area:))` / `insert(GoalListLink(goal:project:))` lines: four times in
/// `AttachWorkSheet` and twice in `CreateGoalSheet`. One value with two cases makes the invariant
/// unspellable-wrong, and gives iOS one function to call rather than a second copy of the pair.
enum GoalLinkTarget: Identifiable {
    case area(Area)
    case project(Project)

    var id: UUID {
        switch self {
        case .area(let area): return area.id
        case .project(let project): return project.id
        }
    }

    var name: String {
        switch self {
        case .area(let area): return area.name
        case .project(let project): return project.name
        }
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        }
    }

    var colorHex: String {
        switch self {
        case .area(let area): return area.colorHex
        case .project(let project): return project.colorHex
        }
    }

    var context: Context? {
        switch self {
        case .area(let area): return area.context
        case .project(let project): return project.context
        }
    }

    /// Open-task count, for the candidate row's subtitle. Goes through
    /// `CadenceTaskQuerySupport.openTaskCount` so an area and a project answer this the same way.
    var openTaskCount: Int {
        switch self {
        case .area(let area): return CadenceTaskQuerySupport.openTaskCount(for: area)
        case .project(let project): return CadenceTaskQuerySupport.openTaskCount(for: project)
        }
    }

    /// `"3 active tasks"`, in the app's existing spelling rather than a fifth hand-written one —
    /// `AttachWorkSheet` interpolated `"\(count) active tasks"` and so said "1 active tasks".
    var openTaskLabel: String {
        CadenceOverdueSummaryPresentation.activeTaskDetail(count: openTaskCount)
    }

    /// A display name that never comes back empty — an untitled list would otherwise render as a
    /// row with a glyph and nothing beside it.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        switch self {
        case .area: return "Untitled Area"
        case .project: return "Untitled Project"
        }
    }

    func isPointedAt(by link: GoalListLink) -> Bool {
        switch self {
        case .area(let area): return link.pointsTo(area: area)
        case .project(let project): return link.pointsTo(project: project)
        }
    }

    func makeLink(for goal: Goal) -> GoalListLink {
        switch self {
        case .area(let area): return GoalListLink(goal: goal, area: area)
        case .project(let project): return GoalListLink(goal: goal, project: project)
        }
    }
}

/// One context's worth of attachable lists — areas first, then projects, matching the order the
/// sidebar and every container picker already use.
struct GoalLinkCandidateGroup: Identifiable {
    /// `nil` is the unfiled group, rendered last.
    let context: Context?
    let targets: [GoalLinkTarget]

    var id: String { context?.id.uuidString ?? "unfiled" }

    var title: String {
        let name = context?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "No Context" : name
    }
}

/// The pure half of goal↔list linking: which links a goal shows, how each is labelled, and the
/// one sentence that says how much of a goal's counted work arrives through a link rather than
/// being assigned to the goal.
///
/// It is here, in `Shared/` and outside every platform conditional, because `Cadence/iOS/` is
/// entirely inside `#if os(iOS)` and invisible to the macOS-built `CadenceTests` target — the same
/// reason `CadenceCompactTab` and `GoalAssignmentRules` live here.
enum GoalLinkPresentation {
    /// The links a goal shows, in a stable order.
    ///
    /// Links with neither an `area` nor a `project` are dropped, matching
    /// `GoalContributionResolver`'s own count: it filters the same way, so a surviving
    /// target-less row would be a "Missing List" the percentage does not know about. The sort is
    /// **total** — `listLinks` is a SwiftData to-many with no defined order, so title alone leaves
    /// two lists of the same name swapping places between renders.
    static func links(of goal: Goal) -> [GoalListLink] {
        (goal.listLinks ?? [])
            .filter { $0.area != nil || $0.project != nil }
            .sorted { lhs, rhs in
                let byTitle = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if byTitle != .orderedSame { return byTitle == .orderedAscending }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// The link on `goal` pointing at `target`, if it already exists.
    static func existingLink(for target: GoalLinkTarget, on goal: Goal) -> GoalListLink? {
        (goal.listLinks ?? []).first { target.isPointedAt(by: $0) }
    }

    static func isAttached(_ target: GoalLinkTarget, to goal: Goal) -> Bool {
        existingLink(for: target, on: goal) != nil
    }

    /// How many of a linked list's tasks the goal actually counts. Cancelled tasks are excluded
    /// here for the same reason `GoalContributionResolver` excludes them from `totalTasks`: a row
    /// promising work the percentage ignores is the confusion this whole surface exists to remove.
    static func contributingTaskCount(for link: GoalListLink) -> Int {
        link.tasks.filter { !$0.isCancelled }.count
    }

    static func contributionLabel(for link: GoalListLink) -> String {
        contributionLabel(taskCount: contributingTaskCount(for: link))
    }

    static func contributionLabel(taskCount: Int) -> String {
        taskCount == 1 ? "1 contributing task" : "\(taskCount) contributing tasks"
    }

    /// The same figure for a **row's trailing slot** rather than a subtitle underneath the title.
    ///
    /// Two spellings of one number, and the shape is the reason: macOS's `GoalLinkedListRow` puts
    /// this on its own line under the list's name and has the width for a sentence, while iOS's
    /// `iOSEditorFieldRow` puts it beside the name in a 44pt row. Measured, not guessed — the full
    /// label truncated to "2 contributing t…" in the iPad goal inspector, which is the one place a
    /// count must not be the part that gets cut.
    static func contributionMetric(for link: GoalListLink) -> String {
        contributionMetric(taskCount: contributingTaskCount(for: link))
    }

    static func contributionMetric(taskCount: Int) -> String {
        taskCount == 1 ? "1 task" : "\(taskCount) tasks"
    }

    /// What an empty Linked Lists section says. One string, both platforms — it has to state the
    /// *other* way work reaches a goal, or the section reads as the only one.
    static let emptyExplanation =
        "Attach an area or project so its tasks count toward this goal. Tasks assigned to the goal directly count too."

    /// The sentence under the progress bar: how much of the counted work arrives through a linked
    /// list rather than being assigned to the goal.
    ///
    /// This is the whole point of T-191. `GoalContributionResolver` folds `goal.listLinks`' tasks
    /// into `totalTasks` — and recurses sub-goals while doing it — so a goal's percentage moves
    /// when a task in an attached list is completed by somebody who never opened this screen.
    /// `nil` when there is nothing to explain: a goal whose counted work is all directly assigned
    /// gets no line rather than a line reading zero.
    ///
    /// The linked figure is `totalTasks - directTaskCount`, so a task that is *both* assigned to
    /// the goal and sitting in an attached list counts as direct — `contributingTasks` dedupes by
    /// id, and attributing it to the list would make the two figures sum past the total.
    static func attributionLine(for summary: GoalContributionSummary) -> String? {
        let linkedTasks = max(0, summary.totalTasks - summary.directTaskCount)
        guard summary.linkedListCount > 0, linkedTasks > 0 else { return nil }
        let lists = summary.linkedListCount == 1 ? "1 linked list" : "\(summary.linkedListCount) linked lists"
        let counted = "\(linkedTasks) of \(summary.totalTasks) counted tasks come from \(lists)"

        switch summary.progressType {
        case .subtasks:
            return "\(counted)."
        case .hours:
            // An hours goal's bar is logged time, so the linked tasks move the task count and not
            // the percentage. Saying so is the difference between explaining the number and
            // pointing at the wrong cause for it.
            return "\(counted). Progress tracks logged hours."
        }
    }

    /// The links attached to this goal's *milestones* rather than to the goal itself.
    ///
    /// `GoalContributionResolver.linkedListCount` recurses sub-goals, so a direction's "3 lists"
    /// chip can outnumber the rows in its own section — and the two lists you cannot see are
    /// exactly the ones moving a percentage you cannot explain. `nil` when the counts agree.
    static func inheritedListNote(ownLinkCount: Int, totalLinkCount: Int) -> String? {
        let inherited = totalLinkCount - ownLinkCount
        guard inherited > 0 else { return nil }
        return inherited == 1
            ? "1 more list is attached to a milestone."
            : "\(inherited) more lists are attached to milestones."
    }

    /// Attachable lists, grouped by context and filtered by a search query.
    ///
    /// No status filter, deliberately: `GoalContributionResolver` keeps counting an archived or
    /// completed list's tasks — "archiving a finished project must not walk a goal backwards" —
    /// so hiding those lists here would leave a contributor that cannot be detached from the
    /// picker that is supposed to manage contributors.
    static func candidateGroups(
        contexts: [Context],
        areas: [Area],
        projects: [Project],
        query: String
    ) -> [GoalLinkCandidateGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func matches(_ name: String) -> Bool {
            needle.isEmpty || name.lowercased().contains(needle)
        }

        func targets(in context: Context?) -> [GoalLinkTarget] {
            let contextAreas = areas
                .filter { $0.context?.id == context?.id && matches($0.name) }
                .sorted { $0.order < $1.order }
                .map(GoalLinkTarget.area)
            let contextProjects = projects
                .filter { $0.context?.id == context?.id && matches($0.name) }
                .sorted { $0.order < $1.order }
                .map(GoalLinkTarget.project)
            return contextAreas + contextProjects
        }

        var groups = contexts.compactMap { context -> GoalLinkCandidateGroup? in
            let found = targets(in: context)
            guard !found.isEmpty else { return nil }
            return GoalLinkCandidateGroup(context: context, targets: found)
        }

        let unfiled = targets(in: nil)
        if !unfiled.isEmpty {
            groups.append(GoalLinkCandidateGroup(context: nil, targets: unfiled))
        }
        return groups
    }

    static func candidateCount(in groups: [GoalLinkCandidateGroup]) -> Int {
        groups.reduce(0) { $0 + $1.targets.count }
    }
}

/// Creating and removing a goal↔list link.
///
/// **A link is a row, not a relationship toggle.** `GoalListLink` is its own `@Model`, so
/// attaching is an `insert` and detaching is a `delete` — writing to `goal.listLinks` or
/// `area.goalLinks` directly would leave a row with no owner. Both halves live here, on
/// `ModelContext`, next to `TrackingDeleteHelpers`' `deleteGoal` / `deleteHabit` and for the same
/// reason: the sites that need them are on both platforms, and nothing in them is AppKit-shaped.
extension ModelContext {
    @discardableResult
    func attachList(_ target: GoalLinkTarget, to goal: Goal) -> GoalListLink? {
        // Idempotent, but **not** because a duplicate would double the percentage — it cannot.
        // `GoalContributionResolver.contributingTasks` ends in `dedupe(...)`, which filters by task
        // `id`, so the same task reached through two links is counted once. That claim was written
        // here and in three guides and was false; a mutation removing this early return left the
        // test named for it passing, which is the same shape as the unkillable `isDone` guard on the
        // goal Momentum count.
        // What a duplicate actually breaks is anything counting *links* rather than tasks:
        // `linkedListCount`, the "N lists" chip on both platforms, the attribution line, and two MCP
        // DTOs — plus a second identical row in both goal inspectors, so unlinking once would leave
        // one on screen.
        if let existing = GoalLinkPresentation.existingLink(for: target, on: goal) {
            return existing
        }
        let link = target.makeLink(for: goal)
        insert(link)
        saveGoalLinkChange()
        return link
    }

    /// Detaching severs the link's own references before deleting the row.
    ///
    /// Nothing on the other end of a link is orphaned by this — the goal, the list, and the list's
    /// tasks are all the user's real work and outlive it, exactly as `deleteGoal` keeps them when
    /// the goal goes. The manual nulling is the house style `TrackingDeleteHelpers` documents:
    /// this codebase does not trust inverse back-population to have happened by the time anything
    /// reads it, and the inverse arrays (`Goal.listLinks`, `Area.goalLinks`, `Project.goalLinks`)
    /// are read by `GoalContributionResolver` on the very next render.
    func detachGoalListLink(_ link: GoalListLink) {
        link.goal = nil
        link.area = nil
        link.project = nil
        delete(link)
        saveGoalLinkChange()
    }

    /// Attach if absent, detach if present. Returns whether the list is attached afterwards.
    @discardableResult
    func toggleGoalListLink(_ target: GoalLinkTarget, on goal: Goal) -> Bool {
        if let existing = GoalLinkPresentation.existingLink(for: target, on: goal) {
            detachGoalListLink(existing)
            return false
        }
        attachList(target, to: goal)
        return true
    }

    /// `processPendingChanges` before the save, so `goal.listLinks` reflects the insert or delete
    /// by the time the view that triggered it re-renders. Without it a detach leaves the row on
    /// screen until something else invalidates the query — the same reason `deleteGoal` and
    /// `deleteHabit` end this way.
    private func saveGoalLinkChange() {
        processPendingChanges()
        try? save()
    }
}
