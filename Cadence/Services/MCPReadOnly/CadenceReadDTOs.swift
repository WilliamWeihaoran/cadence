import Foundation

/// The one envelope every MCP list and search response is wrapped in.
///
/// A bare array cannot say whether it is the whole answer. Every list tool here caps at
/// `CadenceMCPServiceSupport.cappedLimit` and hands back a plain array, so a caller receiving 200
/// rows cannot tell a complete result from the first page of a much longer one. That is a worse
/// failure at a machine boundary than at a human one: a person notices a suspiciously round
/// number and scrolls; an agent reasons on the array as if it were the population.
///
/// One envelope rather than per-tool fields, for two reasons. A caller learns the shape once and
/// reads it on eleven tools. And `hasMore` is only actionable beside an `offset` that is defined
/// against **one** totally ordered candidate list — which is why `listContainers` had to stop
/// concatenating two independently ordered kinds (T-383) before this could mean anything.
///
/// `limit: 0` is a legitimate request: it returns no rows and a truthful `totalCount`, which is
/// the cheapest way to ask "how many are there?".
nonisolated struct CadencePage<Item: Codable & Sendable>: Codable, Sendable {
    /// The rows on this page, in the response's total order.
    let items: [Item]
    /// Zero-based index of `items.first` in the ordered candidate list, clamped to `totalCount`.
    let offset: Int
    /// `items.count`, restated so a caller need not trust its own array length after transport.
    let returnedCount: Int
    /// How many rows matched the filters, **before** `offset` and `limit` were applied.
    let totalCount: Int
    /// `true` when ordered rows remain after this page.
    let hasMore: Bool
    /// The `offset` that fetches the next page, or `nil` when there is no next page.
    let nextOffset: Int?

    static func empty(offset: Int = 0) -> CadencePage<Item> {
        CadencePage(items: [], offset: offset, returnedCount: 0, totalCount: 0, hasMore: false, nextOffset: nil)
    }

    /// Slice `candidates` — already filtered and already in the response's total order.
    ///
    /// `transform` runs only on the rows that survive the slice, so paging stays cheaper than the
    /// map it replaces. It does not make the *fetch* cheaper; that is T-384 and is not this.
    ///
    /// **This slice is in memory and stays that way. Settled, not deferred** (T-415).
    ///
    /// `fetchOffset`/`fetchLimit` on a `FetchDescriptor` would move it into the store, and the
    /// obvious blocker — `UUID` is not `Comparable`, so the identity leg of the sort cannot go into
    /// a `SortDescriptor` — turned out to be false when it was finally checked: Foundation gives
    /// `UUID` a `Comparable` conformance and `UUID() < UUID()` compiles at this deployment target.
    /// Three real ones remain, and each is independently sufficient:
    ///
    /// - **The comparators lead on computed properties.** `CadenceReadService.taskSort` sorts on
    ///   `isDone`, which is `status == .done` derived from `statusRaw`;
    ///   `CadenceMCPOrdering.sortKey(_: Note)` sorts on `displayTitle`. Neither is stored, so
    ///   neither is expressible in a sort descriptor. Storing them means a schema change and a
    ///   CloudKit migration to buy an optimisation.
    /// - **The title leg is `localizedCaseInsensitiveCompare`.** `SortDescriptor`'s nearest
    ///   equivalent is `.localizedStandard`, which is numeric-aware — it orders `item2` before
    ///   `item10` where this comparator does the reverse. Pushing the sort down would silently
    ///   change the order the envelope's `offset` is defined against.
    /// - **Half these candidate lists are not fetches at all.** T-384 deliberately moved
    ///   container-scoped reads onto relationship edges (`area.tasks`, `context.notes`), and
    ///   `listContainers` merges two entity types into one order (T-383). An array walked off a
    ///   model and a merge across kinds have no descriptor to attach an offset to.
    ///
    /// What is bounded is the *fetch*, which is what actually cost: `CadenceReadService`
    /// `fetchedRowCount` is asserted against bounded numbers, and status, kind, archived and date
    /// filters are in the predicate. Materialising the survivors and slicing them is the last hop,
    /// and closing it needs a stored sort key, not a smaller change.
    static func paging<Element>(
        _ candidates: [Element],
        offset: Int,
        limit: Int,
        transform: (Element) throws -> Item
    ) rethrows -> CadencePage<Item> {
        let totalCount = candidates.count
        let start = min(max(offset, 0), totalCount)
        let end = min(start + CadenceMCPServiceSupport.cappedLimit(limit), totalCount)
        let items = try candidates[start..<end].map(transform)
        let hasMore = end < totalCount
        return CadencePage(
            items: items,
            offset: start,
            returnedCount: items.count,
            totalCount: totalCount,
            hasMore: hasMore,
            nextOffset: hasMore ? end : nil
        )
    }
}

nonisolated struct CadenceContextRef: Codable, Sendable {
    let id: String
    let name: String
    let colorHex: String
    let icon: String
    let order: Int
    let isArchived: Bool
    let areaCount: Int
    let projectCount: Int
    let activeTaskCount: Int
    let goalCount: Int
    let habitCount: Int
}

nonisolated struct CadenceContainerRef: Codable, Sendable {
    let kind: String
    let id: String
    let name: String
    let contextId: String?
    let contextName: String?
    let status: String
    let colorHex: String
    let icon: String
}

nonisolated struct CadenceGoalRef: Codable, Sendable {
    let id: String
    let title: String
    let status: String
    let progress: Double
}

nonisolated struct CadenceSubtaskSummary: Codable, Sendable {
    let id: String
    let title: String
    let isDone: Bool
    let order: Int
}

nonisolated struct CadenceTagSummary: Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let colorHex: String
    let description: String
    let isArchived: Bool
}

nonisolated struct CadenceTaskSummary: Codable, Sendable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let dueDate: String
    let scheduledDate: String
    let scheduledStartMin: Int
    let estimatedMinutes: Int
    let container: CadenceContainerRef?
    let goal: CadenceGoalRef?
    let sectionName: String
    let tags: [CadenceTagSummary]
    let isDone: Bool
    let isCancelled: Bool
}

nonisolated struct CadenceTaskBundleSummary: Codable, Sendable {
    let id: String
    let title: String
    let dateKey: String
    let startMin: Int
    let durationMinutes: Int
    let endMin: Int
    let totalEstimatedMinutes: Int
    let taskCount: Int
    let activeTaskCount: Int
    let createdAt: String
}

nonisolated struct CadenceTaskBundleDetail: Codable, Sendable {
    let summary: CadenceTaskBundleSummary
    let tasks: [CadenceTaskSummary]
}

nonisolated struct CadenceTaskDetail: Codable, Sendable {
    let summary: CadenceTaskSummary
    let notes: String
    let actualMinutes: Int
    let subtasks: [CadenceSubtaskSummary]
    let createdAt: String
    let completedAt: String?
}

nonisolated struct CadenceDocumentSummary: Codable, Sendable {
    let id: String
    let title: String
    let container: CadenceContainerRef?
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceTagDetail: Codable, Sendable {
    let summary: CadenceTagSummary
    let taskCount: Int
    let noteCount: Int
    let createdAt: String
    let updatedAt: String
}

nonisolated struct CadenceNoteSummary: Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let key: String?
    let container: CadenceContainerRef?
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceNoteDetail: Codable, Sendable {
    let summary: CadenceNoteSummary
    let content: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let linkedNotes: [CadenceNoteSummary]
    let backlinks: [CadenceNoteSummary]
    let linkedTasks: [CadenceTaskSummary]
}

nonisolated struct CadenceNotePayload: Codable, Sendable {
    let id: String
    let kind: String
    let key: String?
    let content: String
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceCoreNotesSnapshot: Codable, Sendable {
    let dateKey: String
    let weekKey: String
    let dailyNote: CadenceNotePayload?
    let weeklyNote: CadenceNotePayload?
    let permanentNote: CadenceNotePayload?
}

nonisolated struct CadenceSearchHit: Codable, Sendable {
    let entityType: String
    let entityId: String
    let title: String
    let subtitle: String
    let excerpt: String
    let score: Int
}

/// The dashboard summary, with every task section as a page rather than a bare array.
///
/// **The brief used to cap `inbox` at 50 and say nothing (T-385).** Three of its four task sections
/// were unbounded, the fourth was silently truncated, none of them carried a count, and the tool
/// schema took only `date` — so a caller could neither raise the cap nor detect it, and 51 active
/// inbox tasks became 50 with no signal at all. That is the exact failure `CadencePage` exists for
/// (T-382), so the sections are pages: `totalCount` is the size of the section *before* the cut,
/// and `hasMore`/`nextOffset` say whether one happened.
///
/// `limit` and `offset` apply **uniformly to all four sections**, which is what keeps one pair of
/// numbers meaningful across a response holding four ordered lists: page 2 of the brief is rows
/// 50–99 of each section, and each section's own `totalCount` and `hasMore` stay true of that
/// section alone. A caller walking one section to its end is better served by `list_tasks`, which
/// pages a single candidate list.
///
/// `noteSnippets` is not a page. It is the three core notes for the date, bounded by construction
/// rather than by a cap, so an envelope would only add fields whose answer is always the same.
nonisolated struct CadenceTodayBrief: Codable, Sendable {
    let dateKey: String
    let scheduledTasks: CadencePage<CadenceTaskSummary>
    let dueToday: CadencePage<CadenceTaskSummary>
    let overdue: CadencePage<CadenceTaskSummary>
    let inbox: CadencePage<CadenceTaskSummary>
    let noteSnippets: [CadenceNotePayload]
}

nonisolated struct CadenceSectionSummary: Codable, Sendable {
    let name: String
    let colorHex: String
    let dueDate: String
    let isCompleted: Bool
    let isArchived: Bool
    let taskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
}

nonisolated struct CadenceContainerSummary: Codable, Sendable {
    let container: CadenceContainerRef
    let activeTaskCount: Int
    let completedTaskCount: Int
    let overdueTaskCount: Int
    let sections: [CadenceSectionSummary]
    let documents: [CadenceDocumentSummary]
    let links: [CadenceSavedLinkSummary]
}

nonisolated struct CadenceContextSummary: Codable, Sendable {
    let context: CadenceContextRef
    let inboxTaskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
    let scheduledTaskCount: Int
    let overdueTaskCount: Int
    let activeGoalCount: Int
    let documentCount: Int
    let linkCount: Int
    let areas: [CadenceContainerRef]
    let projects: [CadenceContainerRef]
}

nonisolated struct CadenceDocumentDetail: Codable, Sendable {
    let id: String
    let title: String
    let container: CadenceContainerRef?
    let content: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceGoalContributionSnapshot: Codable, Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let directTaskCount: Int
    let linkedListCount: Int
    let focusMinutes: Int
    let overdueTaskCount: Int
    let recentCompletedCount: Int
    let nextActionTitle: String?
    let progress: Double
}

nonisolated struct CadenceGoalHabitMomentumSnapshot: Codable, Sendable {
    let linkedHabitCount: Int
    let dueTodayCount: Int
    let doneTodayCount: Int
    let thisWeekCount: Int
    let last7DayCount: Int
}

nonisolated struct CadenceGoalSummary: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let startDate: String
    let endDate: String
    let progressType: String
    let targetHours: Double
    let loggedHours: Double
    let colorHex: String
    let icon: String
    /// `ongoing` / `completable` / `maintenance` — top-level ongoing goals are what used to be pursuits.
    let kind: String
    let status: String
    let progress: Double
    let contextId: String?
    let contextName: String?
    let parentGoalId: String?
    let parentGoalTitle: String?
    let isTopLevel: Bool
    /// **`own`, not a total, and the prefix is the whole point (T-388).**
    ///
    /// These two were `linkedListCount` and `taskCount`, computed flat from `goal.listLinks` and
    /// `goal.tasks`, while `getGoal`'s `contribution` block reported `GoalContributionResolver`'s
    /// numbers for the same goal — which walk sub-goals, and linked lists too. Both figures are
    /// defensible. A direction whose milestone owns the work reporting `taskCount: 0` beside
    /// `contribution.totalTasks: 12` is not, because nothing in the name said which question was
    /// being answered.
    ///
    /// The names moved rather than the arithmetic, for two reasons. This struct is also every row
    /// of `getGoal.subGoals`, where the *own* count is the right number — a milestone row carrying
    /// a recursively rolled-up figure would double-count against the parent's `contribution` block
    /// printed directly above it. And the recursive answers are not missing from the surface:
    /// `getGoal.contribution` already carries `totalTasks`, `directTaskCount` and
    /// `linkedListCount`. What `listGoals` gains is a cheap, honest row —
    /// `GoalContributionResolver.summary` dedupes a recursive task walk per goal, which is exactly
    /// the "cap the response, not the work" shape T-384 is removing elsewhere in this same file.
    ///
    /// **All four carry the prefix (T-414).** `subGoalCount` and `habitCount` kept their generic
    /// names through T-388 so the breaking wire change stayed one rename rather than three, and
    /// that is the state this ticket closes: they count `goal.subGoals` and `goal.habits` flat,
    /// exactly as the other two counted their edges, so a milestone two levels down is no more
    /// present in `subGoalCount` than its tasks were in `taskCount`. A half-applied convention is
    /// worse than either end state — a reader who has learned that `own` marks "not rolled up"
    /// reads the two unprefixed names as the totals the other two stopped claiming to be. The
    /// arithmetic is unchanged again; only the names moved.
    let ownLinkedListCount: Int
    let ownTaskCount: Int
    let ownSubGoalCount: Int
    let ownHabitCount: Int
    let createdAt: String
}

nonisolated struct CadenceGoalDetail: Codable, Sendable {
    let summary: CadenceGoalSummary
    let contribution: CadenceGoalContributionSnapshot
    let habitMomentum: CadenceGoalHabitMomentumSnapshot
    let linkedContainers: [CadenceContainerRef]
    let directTasks: [CadenceTaskSummary]
    let subGoals: [CadenceGoalSummary]
    let habits: [CadenceHabitSummary]
}

nonisolated struct CadenceHabitSummary: Codable, Sendable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let frequencyType: String
    let frequencyDays: [Int]
    let targetCount: Int
    let order: Int
    let contextId: String?
    let contextName: String?
    let goal: CadenceGoalRef?
    let currentStreak: Int
    let completionCount: Int
    let completedToday: Bool
    let createdAt: String
}

nonisolated struct CadenceSavedLinkSummary: Codable, Sendable {
    let id: String
    let title: String
    let url: String
    let container: CadenceContainerRef?
    let order: Int
    let createdAt: String
}

nonisolated struct CadenceCompleteTaskResult: Codable, Sendable {
    let task: CadenceTaskDetail
    let spawnedRecurringTask: CadenceTaskDetail?
}

nonisolated struct CadenceBulkCancelResult: Codable, Sendable {
    let cancelledTasks: [CadenceTaskSummary]
}
