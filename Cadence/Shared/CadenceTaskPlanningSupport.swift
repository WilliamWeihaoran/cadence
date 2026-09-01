import Foundation
import SwiftUI

enum CadenceTaskSortMode: String, CaseIterable, Hashable, Identifiable {
    case listOrder
    case priority
    case doDate
    case dueDate
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listOrder: return "List Order"
        case .priority: return "Priority"
        case .doDate: return "Do Date"
        case .dueDate: return "Due Date"
        case .newest: return "Newest"
        }
    }
}

// MARK: - The retired macOS vocabulary (T-606)

extension CadenceTaskSortMode {
    /// What macOS Today falls back to: its shipped default, and where an unrecognised stored value
    /// lands.
    ///
    /// Deliberately **not** iOS Today's default (`.priority`). macOS Today's retiring default was
    /// `Date` + `Ascending`, and `TaskOrdering.precedes` sorts `.date` by `AppTask.scheduledDate`
    /// — the *do* date. So `.doDate` is the one mode that leaves an untouched macOS Today looking
    /// exactly as it did; adopting iOS's default would silently re-sort every user who never
    /// opened the chip. Adopting iOS's *named set* was the decision; adopting its default was not.
    static let macOSTodayDefault: CadenceTaskSortMode = .doDate

    /// macOS Today's retired `TaskSortField` preference, mapped onto this vocabulary.
    ///
    /// Each mapping is read off the two comparators, not off the two labels:
    ///
    /// - `.custom` is `TaskOrdering.fallbackPrecedes` and its branch never reads the direction.
    ///   `.listOrder` with no `sectionNames` — which is how Today calls it — is the same call.
    ///   **Exact, from either direction.**
    /// - `.date` is `TaskOrdering.dateSortKey(scheduledDate)`, then timed-before-untimed, then
    ///   `scheduledStartMin`, then the fallback. `.doDate` is those four steps in that order, and
    ///   it calls `TaskOrdering.dateSortKey` too. It did not when this was written: it had a
    ///   private `sortDateKey` that was character-identical, which made this mapping proof rest on
    ///   two texts agreeing rather than on one function. T-640 deleted the twin, and
    ///   `TaskOrderingTests.everyMigratedMacOSTodaySortModeAgreesWithItsRetiredComparator` now
    ///   asserts all three mappings pair-by-pair, so a divergence fails a test instead of quietly
    ///   splitting the two Todays.
    ///   **Exact from `Ascending`**, which was macOS's default. It is the *do* date on both sides:
    ///   the label said only "Date", on a page whose whole vocabulary is do-date vs due-date, which
    ///   is the reason this ticket exists.
    /// - `.priority` is `TaskPriority.rank` then the fallback; `.priority` here is
    ///   `priorityRank` **descending** then the same fallback. **Exact from `Descending`.**
    ///
    /// **The direction is discarded, and that is the decision**: the Order chip goes and direction
    /// folds into the named modes. iOS has no reversed do-date and no low-priority-first, so the
    /// two settings on the far side — `Date` + `Descending` and `Priority` + `Ascending` — have no
    /// equivalent and land on the ascending-side mode. Both are reachable but neither is a
    /// default, so this re-sorts only a user who chose one.
    ///
    /// Anything that decodes as neither vocabulary — nil, empty, or a value written by some other
    /// build — lands on ``macOSTodayDefault`` rather than crashing or resetting to iOS's default.
    static func migratedFromMacOSTodaySortField(_ storedRawValue: String?) -> CadenceTaskSortMode {
        guard let storedRawValue, let field = TaskSortField(rawValue: storedRawValue) else {
            return macOSTodayDefault
        }
        switch field {
        case .custom: return .listOrder
        case .date: return .doDate
        case .priority: return .priority
        }
    }
}

/// The four date buckets Today **used** to be grouped into, kept only as the vocabulary a dropped
/// `+` speaks: `CadenceTaskDropSupport.dropKey(forGroup:)` still names them to say what each kind
/// of destination can seed. Nothing draws a heading from them any more — see
/// `CadenceTaskQuerySupport.todayGroups`, which groups the day by list (T-305).
///
/// It carries no `title` for that reason. The strings it used to hand out were the headings, and
/// one of them — "Planned Today" — was the heading the user removed: on the Today page, "today" is
/// the page, so a section restating it is the standing page-header rule one level down.
enum CadenceTodayTaskGroupKind: String, CaseIterable, Hashable {
    case overdue
    case pastDo
    case dueToday
    case plannedToday
}

/// What one of Today's groups **is**.
///
/// Two cases, and the asymmetry is the decision: Overdue is the only group on the page that is not
/// a list, because a missed deadline is a fact about the *day* and outranks where the work lives.
/// Everything else on Today is grouped the way the rest of the app groups tasks — by list — so the
/// page stops mixing two grouping axes against each other. The `PAST DUE LISTS` cards above the
/// groups were already list-shaped.
nonisolated enum CadenceTodayGroupIdentity: Hashable {
    case overdue
    /// A list — an area, a project, or the Inbox — in the `inbox` / `a_<uuid>` / `p_<uuid>`
    /// spelling `CadenceTaskDropSupport.containerKey(for:)` produces and `assignTask` parses. One
    /// spelling, so the header a task is drawn under and the header it can be dropped on are the
    /// same string.
    case list(key: String)

    /// Stable across renders and across the two hosts, which is what a collapse set and a
    /// `ForEach` both need. Prefixed rather than bare so a list key can never collide with a
    /// non-list group's id.
    var id: String {
        switch self {
        case .overdue: return "today-overdue"
        case .list(let key): return "today-list-\(key)"
        }
    }

    var isOverdue: Bool { self == .overdue }
}

/// One of Today's groups, with everything either host needs to draw its header.
///
/// Built by `CadenceTaskQuerySupport.todayGroups` so the two platforms cannot disagree about which
/// groups exist, what they are called, in what order they come, or which of them a `+` may be
/// dropped on.
struct CadenceTodayTaskGroup: Identifiable {
    let identity: CadenceTodayGroupIdentity
    let title: String
    /// The list's own colour, or Overdue's red. Read at build time rather than stored on the type:
    /// `Theme` accents are selectable, so a `static let` would freeze the palette (T-15).
    let accent: Color
    /// The list's glyph, and `nil` for Overdue — which spans every list and so has no one icon.
    let listIcon: String?
    /// The context an area or project belongs to, for the small glyph macOS draws beside a list
    /// name. `nil` for Overdue and for the Inbox, which belongs to no context.
    let contextIcon: String?
    let contextColor: Color?
    let tasks: [AppTask]

    var id: String { identity.id }

    /// Whether a row in this group still names the list it is in.
    ///
    /// **Off inside a list group, on inside Overdue.** A chip repeating the header it sits under is
    /// the same duplication `CadenceTaskSurfaceOptions` turns the chip off for on a list's own
    /// page; Overdue is drawn from every list at once, so there the chip is the only thing that
    /// says where the work lives.
    var showsContainerChip: Bool { identity.isOverdue }

    /// What a dropped `+` inherits from this header.
    ///
    /// Overdue is defined by a day that has gone by, so it resolves to nothing and does not light
    /// up. A list group is a list **on today**, and says both — `.todayList`, not `.list`: a task
    /// dropped here that inherited only the list would be filed correctly and then disappear from
    /// the page it was dropped on. See `CadenceTaskDropSupport.dropKey(forGroup:)`.
    var dropIdentity: CadenceTaskGroupDropIdentity {
        switch identity {
        case .overdue:
            return .todayDate(.overdue)
        case .list(let key):
            return .todayList(key: key, name: title)
        }
    }
}

struct CadenceTaskDisplayGroup: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let tasks: [AppTask]
    let dropKey: String?

    init(
        id: String,
        title: String,
        accent: Color,
        tasks: [AppTask],
        dropKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.accent = accent
        self.tasks = tasks
        self.dropKey = dropKey
    }
}

struct CadenceTaskDateBuckets {
    let overdueIDs: Set<UUID>
    let dueTodayIDs: Set<UUID>
    let doTodayIDs: Set<UUID>

    func contains(_ task: AppTask) -> Bool {
        overdueIDs.contains(task.id) || dueTodayIDs.contains(task.id) || doTodayIDs.contains(task.id)
    }
}
