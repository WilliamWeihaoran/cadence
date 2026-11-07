import Foundation
import SwiftUI

/// **What a single-chip task surface is ordered by** — Today on all three devices, and a list's
/// Tasks tab. The three-control surfaces (the Inbox and All Tasks) speak `TaskSortField` instead;
/// `macOSSortPair` is the one-to-one correspondence between the two vocabularies.
///
/// **The declaration order is the menu order, and since the owner's 2026-11-01 decision under
/// [[T-9901]] it is the three-control order**: Custom, Do Date, Due Date, Priority, Newest, which
/// is `TaskSortField.allCases` label-for-label. It used to read List Order / Priority / Do Date /
/// Due Date / Newest, so a list's Tasks tab disagreed with the Inbox one tap away about both the
/// order a reader scans and the word for the identity option.
///
/// **Reordering the cases moved no saved preference, and could not have.** The raw values here are
/// implicit, so they are the CASE NAMES — `"listOrder"`, `"doDate"` — and not positions, and every
/// surface stores and reads one through `rawValue`: the `@AppStorage` keys in
/// `CadencePreferenceKeys`, `TasksPanel.storedSortMode`, and `CadenceLookPreferenceStore`'s record.
/// Nothing subscripts or indexes `allCases`. **This is the exact opposite of `TaskSortField`**,
/// whose raw values ARE the stored strings: there a rename orphans every saved setting and a
/// reorder is free, here a reorder is free and a rename is only a label.
/// `CadenceTaskSortGroupParityTests.reorderingTheSortMenuCannotMoveASavedPreference` is what says
/// so, and it fails on any site that learns to persist an ordinal.
enum CadenceTaskSortMode: String, CaseIterable, Hashable, Identifiable {
    case listOrder
    case doDate
    case dueDate
    case priority
    case newest

    var id: String { rawValue }

    /// **`.listOrder` is drawn as "Custom", the word the three-control surfaces already use**
    /// ([[T-9901]]). It is one arrangement under two names — `macOSSortPair` projects this case
    /// onto `TaskSortField.custom`, whose own label is "Custom" — and the finding was that two
    /// screens one tap apart spelled it differently.
    ///
    /// **Every reader is relabelled, deliberately, rather than the list tab alone.**
    /// `iOSTaskViewOptionsBar` is one control drawing Today on the iPhone and iPad *and* a list's
    /// Tasks tab, and the Mac's Today badge reads the same property through `pickerLabel`, so
    /// sparing a surface would have meant either two words for one mode inside a single view or a
    /// per-call-site label override — a new inconsistency in place of the one being removed.
    var title: String {
        switch self {
        case .listOrder: return "Custom"
        case .doDate: return "Do Date"
        case .dueDate: return "Due Date"
        case .priority: return "Priority"
        case .newest: return "Newest"
        }
    }
}

/// **How a task list is divided into sections** — the third of the three controls the Inbox and
/// All Tasks draw, on both platforms since [[T-8731]].
///
/// It was declared in `macOS/Views/TasksPanelSupport.swift`, whose comment said grouping was "a
/// macOS list-surface concern ... no other target has a grouped task list". The owner's
/// 2026-10-31 decision under [[T-8201]] made the second half false: the iPhone and iPad draw Sort
/// + Order + Group too, and `Cadence/iOS/` cannot see a file under `macOS/`. So it is here, with
/// the sort vocabulary, rather than copied.
///
/// Here rather than in `Models/` beside `TaskSortField`: grouping has no comparator behind it and
/// no other **target** needs it — `CadenceWidgets` and `CadenceMCPServer` order tasks and do not
/// section them — so `Shared/`, which both platforms compile and neither extension does, is the
/// narrowest home that reaches every surface that draws a group.
///
/// The raw values are persisted (`CadencePreferenceKeys.inboxGroupingMode`,
/// `allTasksGroupingMode`, and the `*.grouping` keys in `CadenceLookPreferenceStore`'s record).
/// Renaming a case is fine; changing a raw value silently resets every saved preference.
enum TaskGroupingMode: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case byDate = "By Date"
    case byList = "By List"
    case byPriority = "By Priority"
    var id: String { rawValue }
}

// MARK: - What the Inbox offers ([[T-7985]], [[T-10461]])

extension TaskGroupingMode {
    /// The cases the Inbox's Group menu leaves out, on both platforms. No Inbox task is in a list
    /// by definition, so By List could only draw one "Inbox" heading over every row -- a control
    /// that appears to fail, which the owner ruled worse than one that is not there ([[T-7006]]).
    static let inboxExcluded: [TaskGroupingMode] = [.byList]

    /// What a Tasks-page view's Group menu leaves out. The Mac badge and the iOS chip both ask
    /// this, so the two Inboxes cannot offer different menus ([[T-8201]]).
    static func excluded(on scope: CadenceTasksPageScope) -> [TaskGroupingMode] {
        scope == .inbox ? inboxExcluded : []
    }

    /// What that menu offers, in menu order.
    static func offered(on scope: CadenceTasksPageScope) -> [TaskGroupingMode] {
        let excluded = excluded(on: scope)
        return allCases.filter { !excluded.contains($0) }
    }

    /// The Inbox's stored grouping as the Inbox reads it: a `.byList` stored before the option
    /// left the menu reads as None, so the page never draws a grouping its menu cannot show.
    /// Writable, so a page binds `$inboxGroupingMode.inboxResolved` -- a key path, not a
    /// `Binding(get:set:)` closure pair (T-3156).
    var inboxResolved: TaskGroupingMode {
        get { Self.inboxExcluded.contains(self) ? .none : self }
        set { self = newValue }
    }
}

// MARK: - A stored raw value as a sort mode (T-3156, T-3158)

/// The stored raw value read and written as a sort mode, so a page's `sortModeBinding` can be a
/// key-path projection of its `@AppStorage` binding rather than a closure pair (T-3156, T-3158).
/// An unknown raw value reads as `fallback`, which is each surface's own default: `.listOrder` for
/// All Tasks and Inbox, `.priority` for Today, as their `sortMode` properties read it.
///
/// A subscript rather than one property per surface, because the fallback is the only thing the
/// three differ in. Its argument is `Hashable`, so the key path stays comparable — which is the
/// whole point: `$sortModeRaw[sortModeFallingBackTo: .listOrder]` is the same location on every
/// pass, and a `Binding(get:set:)` never is. Here rather than beside the iOS pages because it is
/// ordinary `String` code, which lets `CadenceIOSAllTasksSortBindingTests` run it on macOS.
extension String {
    subscript(sortModeFallingBackTo fallback: CadenceTaskSortMode) -> CadenceTaskSortMode {
        get { CadenceTaskSortMode(rawValue: self) ?? fallback }
        set { self = newValue.rawValue }
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
        case .dueDate: return .dueDate
        case .priority: return .priority
        case .newest: return .newest
        }
    }

    /// **The projection the other way** — this mode as the Sort + Order pair the Inbox and All
    /// Tasks now draw on both platforms ([[T-8731]]).
    ///
    /// It is not a new rule. `CadenceLookPreferenceStore.mirrorValue(fromRecord:codec:)` has been
    /// performing exactly this projection on exactly these preferences since the look record
    /// landed, because the Mac's three fields were the smaller vocabulary: a phone's choice
    /// arriving on a Mac was already drawn as the nearest of Custom / Date / Priority. What
    /// [[T-8731]] changes is which surfaces read it, not what it answers.
    ///
    /// Three modes round-trip exactly, and the pairs are the ones
    /// ``migratedFromMacOSTodaySortField`` documents and
    /// `TaskOrderingTests.everyMigratedMacOSTodaySortModeAgreesWithItsRetiredComparator`
    /// measures: `.listOrder` is Custom (whose comparison *is* the fallback, so the direction is
    /// inert — `TaskSortField.honorsDirection`), `.doDate` is Date + Ascending, `.priority` is
    /// Priority + Descending.
    ///
    /// **Since 2026-11-01 all five round-trip, and that is [[T-9742]].** `.dueDate` and `.newest`
    /// used to have no twin and were projected onto Date + Ascending, which is what cost the iOS
    /// Inbox and All Tasks those two modes when [[T-8731]] gave them this vocabulary. The owner's
    /// ruling was not to accept the loss: `TaskSortField` gained `.dueDate` and `.newest`, so this
    /// is now a one-to-one correspondence in both directions and
    /// `migratedFromMacOSTodaySortField(macOSSortPair.field.rawValue)` is the identity on every
    /// mode. The direction each one ships with is the one its old branch in
    /// `CadenceTaskQuerySupport.sortKeyOrder` hard-coded: Ascending is soonest-due first,
    /// Descending is most-recently-created first.
    var macOSSortPair: (field: TaskSortField, direction: TaskSortDirection) {
        switch self {
        case .listOrder: return (.custom, .ascending)
        case .priority: return (.priority, .descending)
        case .doDate: return (.date, .ascending)
        case .dueDate: return (.dueDate, .ascending)
        case .newest: return (.newest, .descending)
        }
    }
}

// MARK: - A picker value whose raw value is not its label

/// A picker enum whose raw value is a **storage key**, not a label.
///
/// `CadenceEnumPickerBadge` and `iOSEnumChoiceChip` print `rawValue`, which is right for
/// `TaskSortDirection` and `TaskGroupingMode` — enums written for those chips, whose raw values
/// read as English — and wrong for two types here. `CadenceTaskSortMode`'s raw values are
/// `listOrder` / `doDate`, because iOS persists them under `ios.today.sortMode`.
/// `TaskSortField.date`'s is `"Date"`, because every Mac has it on disk — and since the owner's
/// 2026-11-01 decision gave the Mac a Due Date field, "Date" beside "Due Date" no longer says
/// which date it means. Conforming keeps the persisted spelling and the printed one apart, so
/// neither widening the vocabulary (T-9742) nor adopting iOS's (T-606) meant resetting a saved
/// preference.
///
/// Here rather than beside either control: both platforms draw these vocabularies now, and
/// `Cadence/iOS/` cannot see a file under `macOS/`. It lived in `macOS/Views/TasksPanelSupportViews.swift`
/// while the Mac was the only one that needed it.
protocol CadenceLabelledPickerValue {
    var pickerLabel: String { get }
}

extension CadenceTaskSortMode: CadenceLabelledPickerValue {
    var pickerLabel: String { title }
}

/// `TaskSortField` declares `pickerLabel` itself, beside the raw values it has to differ from.
extension TaskSortField: CadenceLabelledPickerValue {}

/// The four date buckets Today **used** to be grouped into, kept only as the vocabulary a dropped
/// `+` speaks: `CadenceTaskDropSupport.dropKey(forGroup:)` still names them to say what each kind
/// of destination can seed. Nothing draws a heading from them any more — see
/// `CadenceTaskQuerySupport.todayListGroups`, which groups the day by list and nothing else.
///
/// **Nothing in the app constructs one of these any more.** With Today's Overdue section gone,
/// `CadenceTaskGroupDropIdentity.todayDate` has no producer outside `CadenceTaskGroupDropSupportTests`.
/// Both are left standing rather than pruned in the same change that made them unreachable — see
/// the report on this ticket.
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

/// One of Today's groups, with everything either host needs to draw its header.
///
/// Built by `CadenceTaskQuerySupport.todayListGroups` so the two platforms cannot disagree about
/// which groups exist, what they are called, in what order they come, or which of them a `+` may be
/// dropped on.
///
/// **Every group on Today is a list now**, so what used to be a two-case `CadenceTodayGroupIdentity`
/// — `.overdue` or `.list(key:)` — is the list key itself. The `.overdue` half went when the user
/// removed the Overdue section; a one-case enum wrapping a `String` is the wrapper, not the
/// decision. Three members went with it: `identity.isOverdue`, `showsContainerChip` (which was
/// exactly `isOverdue`, and is now false for every group by construction — see the two hosts, which
/// pass `false` and say why), and `dropIdentity`'s `.todayDate(.overdue)` arm.
struct CadenceTodayTaskGroup: Identifiable {
    /// The list this group **is** — an area, a project, or the Inbox — in the `inbox` / `a_<uuid>` /
    /// `p_<uuid>` spelling `CadenceTaskDropSupport.containerKey(for:)` produces and `assignTask`
    /// parses. One spelling, so the header a task is drawn under and the header it can be dropped
    /// on are the same string.
    let listKey: String
    let title: String
    /// The list's own colour. Read at build time rather than stored on the type: `Theme` accents
    /// are selectable, so a `static let` would freeze the palette (T-15).
    let accent: Color
    /// The list's glyph.
    let listIcon: String?
    /// The context an area or project belongs to, for the small glyph macOS draws beside a list
    /// name. `nil` for the Inbox, which belongs to no context.
    let contextIcon: String?
    let contextColor: Color?
    let tasks: [AppTask]

    /// Stable across renders and across the two hosts, which is what a collapse set and a `ForEach`
    /// both need. Prefixed rather than bare, so a group id can never be mistaken for a raw
    /// container key.
    var id: String { "today-list-\(listKey)" }

    /// What a dropped `+` inherits from this header: a list **on today**, and it says both —
    /// `.todayList`, not `.list`. A task dropped here that inherited only the list would be filed
    /// correctly and then disappear from the page it was dropped on. See
    /// `CadenceTaskDropSupport.dropKey(forGroup:)`.
    var dropIdentity: CadenceTaskGroupDropIdentity {
        .todayList(key: listKey, name: title)
    }
}

/// **A page's folded task groups, as one set of group ids ([[T-12191]]).** Every task group folds
/// from its heading on both platforms (decided on [[T-11214]]); the state is the host page's own
/// `@State Set<String>`, unpersisted, the shape the Mac's `TasksListView.collapsedSectionIDs`
/// already kept. Out here rather than in `iOSTaskGroupSection` so the reading of the set — absent
/// means open, so a page starts with every group unfolded — is one statement a macOS-built test
/// can exercise.
enum CadenceTaskGroupFold {
    static func isExpanded(_ groupID: String, in collapsed: Set<String>) -> Bool {
        !collapsed.contains(groupID)
    }

    static func setExpanded(_ expanded: Bool, _ groupID: String, in collapsed: inout Set<String>) {
        if expanded {
            collapsed.remove(groupID)
        } else {
            collapsed.insert(groupID)
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
    /// Planned for an earlier day, not done, and with no deadline today or before. Without this
    /// bucket such a task matched none of the other three and fell through to "Scheduled", beside
    /// work planned for next month ([[T-12323]]).
    let pastDoIDs: Set<UUID>
    let dueTodayIDs: Set<UUID>
    let doTodayIDs: Set<UUID>

    func contains(_ task: AppTask) -> Bool {
        overdueIDs.contains(task.id) || pastDoIDs.contains(task.id)
            || dueTodayIDs.contains(task.id) || doTodayIDs.contains(task.id)
    }
}

// MARK: - What the row menu's date submenus say ([[T-8107]])

/// The task row menu's Do Date and Due Date submenus state the set date the way its Priority
/// submenu states the level -- "Due Date: Fri, Oct 31" -- and check the quick row that would set the
/// date the task already has. One reader for `MacTaskRowContextMenu` and `iOSTaskRowContextMenu`,
/// so the two menus cannot say a date two ways.
nonisolated enum CadenceTaskDateMenuLabel {
    /// The three quick rows, in menu order, each the day offset its button writes
    /// (`CadenceTaskMutationSupport.scheduleTomorrow` / `scheduleNextWeek` and their due twins).
    enum QuickPick: Int, CaseIterable, Sendable {
        case today = 0
        case tomorrow = 1
        case nextWeek = 7
    }

    /// `title` alone when nothing is set, or when the stored key is not a date; otherwise
    /// `"<title>: EEE, MMM d"`.
    static func title(_ title: String, dateKey: String) -> String {
        guard let date = DateFormatters.date(from: dateKey) else { return title }
        return "\(title): \(DateFormatters.compactLongDate.string(from: date))"
    }

    /// The quick row whose button would write `dateKey` today, or `nil` when the set date is
    /// none of them (an arbitrary date, or nothing set).
    static func checkedPick(
        for dateKey: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuickPick? {
        guard !dateKey.isEmpty else { return nil }
        return QuickPick.allCases.first { pick in
            let day = calendar.date(byAdding: .day, value: pick.rawValue, to: now) ?? now
            return DateFormatters.dateKey(from: day) == dateKey
        }
    }

    /// The quick row's glyph: the checkmark the Priority and Repeat rows use when it is the set
    /// date, its own symbol otherwise.
    static func glyph(_ pick: QuickPick, dateKey: String, otherwise symbol: String) -> String {
        checkedPick(for: dateKey) == pick ? "checkmark.circle.fill" : symbol
    }
}
