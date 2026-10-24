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

    /// `"3 active tasks"` / `"1 active task"` — `AttachWorkSheet` interpolated
    /// `"\(count) active tasks"` and so said "1 active tasks".
    var openTaskLabel: String {
        Self.openTaskLabel(count: openTaskCount)
    }

    /// The count-only half of `openTaskLabel`, so the singular rule is testable without a model.
    /// It lived beside Today's past-due summary line until that line lost its last caller and was
    /// deleted ([[T-3335]]); this type is now its only reader.
    static func openTaskLabel(count: Int) -> String {
        "\(count) active task\(count == 1 ? "" : "s")"
    }

    /// A display name that never comes back empty — an untitled list would otherwise render as a
    /// row with a glyph and nothing beside it.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        switch self {
        case .area: return CadenceTitleNormalization.defaultAreaName
        case .project: return CadenceTitleNormalization.defaultProjectName
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
        return name.isEmpty ? CadenceSidebarLists.ungroupedTitle : name
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
    /// **`isDeleted` is filtered for the same reason the target-less rows are, and it is the half
    /// that does not depend on a toolchain** ([[T-1306]]). A refused attach — when the retired
    /// `attachList` still existed — had already had `commitInsert` call `delete(link)` by the time
    /// it rethrew, so between the refusal and the next processed pending change `goal.listLinks`
    /// held a row the store would never have. Measured on this Mac (Xcode 27, 2026-09-20):
    /// `count == 1`, `isDeleted == true`, and both inspectors drew it. Nothing writes a link now
    /// ([[T-2079]]), but a deleted-and-unprocessed row is still a state this reading must answer
    /// correctly, and this filter is right whether or not the array has caught up ([[T-1296]]).
    ///
    /// **The one reader that never comes through here asks the same question itself**
    /// ([[T-1321]]). `GoalContributionResolver` walks `goal.listLinks` raw, once for the counted
    /// tasks and once for the "N lists" chip, and filters `isDeleted` the same way, so a deleted
    /// link is kept out of the goal's *progress bar* as well as out of this list.
    /// `aDeletedLinkIsNotALinkedList` and
    /// `aDeletedLinkIsNotCountedByTheProgressBarEither` exercise both filters against a
    /// deleted-and-unprocessed link directly, so neither is a guard no mutation can reach.
    static func links(of goal: Goal) -> [GoalListLink] {
        (goal.listLinks ?? [])
            .filter { !$0.isDeleted && ($0.area != nil || $0.project != nil) }
            .sorted { lhs, rhs in
                let byTitle = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if byTitle != .orderedSame { return byTitle == .orderedAscending }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
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

    /// A goal's linked-list chip, both platforms. **T-4980:** macOS's goal card typed
    /// `"\(summary.linkedListCount) lists"` and said "1 lists"; iOS had its own correct ternary.
    /// Callers keep their own zero case ("No lists" on macOS, no chip on iOS).
    static func linkedListCountLabel(_ count: Int) -> String {
        CadencePluralization.phrase(count, singular: "list", plural: "lists")
    }

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

        let offered = Set(contexts.map(\.id))

        /// `nil` asks for the leftovers, and **it is not the same question as `context == nil`**
        /// (T-558). This used to be one `$0.context?.id == context?.id`, which reads well and
        /// answers "unfiled" as "has no context at all" — so a list whose context exists but was
        /// not handed in, the ordinary state of an archived one, matched no offered group *and*
        /// failed the `nil` test, and was offered by this sheet nowhere. Every caller currently
        /// passes an unfiltered context query, so that was latent rather than live; it is the
        /// fifth-instance shape either way and it is keyed on the offered set now, the way
        /// `CadenceSidebarLists.isOffered` keys it everywhere else.
        func targets(in context: Context?) -> [GoalLinkTarget] {
            func owns(_ owner: Context?) -> Bool {
                guard let context else {
                    return !CadenceSidebarLists.isOffered(owner?.id, among: offered)
                }
                return owner?.id == context.id
            }
            let contextAreas = areas
                .filter { owns($0.context) && matches($0.name) }
                .sorted { $0.order < $1.order }
                .map(GoalLinkTarget.area)
            let contextProjects = projects
                .filter { owns($0.context) && matches($0.name) }
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

// MARK: - Retired writers

/// **The three `GoalListLink` writers that lived here were removed by [[T-2079]].**
///
/// `attachList`, `detachGoalListLink` and `toggleGoalListLink` were the only code in the app that
/// inserted or deleted a `GoalListLink` row — the join between a goal and a list. The owner retired
/// goals at the depth *"remove the UI and stop writing, keep the schema"*, so the model, its
/// CloudKit record type and every row already in the store stay, and nothing mints or removes one
/// again. The two attach sheets that called them (`GoalAttachWorkSheet` on macOS,
/// `iOSGoalAttachListsSheet` on iOS) are deleted with them, and so is `GoalLinkTarget`'s
/// `makeLink`, which existed only to feed `attachList`.
///
/// **Everything above this line is a read and is deliberately untouched.** `GoalLinkPresentation`
/// still resolves a link to its list, counts its contributing tasks and builds the attribution
/// line, because the goal surfaces that *draw* existing links are a later increment's to remove and
/// an existing link has to keep rendering correctly until they are.
