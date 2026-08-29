import Foundation

// Every enum in this file is `nonisolated`, for the reason `TaskOrdering` already is: the project
// sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which hands a bare value type a main-actor
// *synthesized* `Equatable` — and `Models/` compiles straight into `CadenceWidgets`, whose timeline
// providers run off the main actor, and into `CadenceMCPServer`, which is already on Swift 6 where
// that isolation is an error rather than a warning. A status enum is data; it has no business
// belonging to an actor. `CadenceTests/NonisolatedValueTypeTests` is the guard.

// MARK: - Task enums

nonisolated enum TaskPriority: String, Codable, CaseIterable, Hashable {
    case none     = "none"
    case low      = "low"
    case medium   = "medium"
    case high     = "high"

    var label: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    /// Sort weight, high to none. Every "sort by priority" in the app means this.
    ///
    /// This existed as six independent `switch` statements — in `CadenceTaskQuerySupport`, in
    /// `CadenceCalendarPlanningSupport` (private, *the same folder*), in `GoalContributionSummary`,
    /// in the Today widget, and twice under `iOS/`. They agreed, which is the state that precedes
    /// drift; every bug found in this repo's audits came from one idea implemented more than once.
    /// The ordering is a property of the enum, so it lives on the enum.
    ///
    /// `nonisolated` because widget timeline providers run off the main actor and this module
    /// defaults to `MainActor` isolation.
    nonisolated var rank: Int {
        switch self {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        case .none:   return 0
        }
    }

    var nextCycled: TaskPriority {
        switch self {
        case .none: return .low
        case .low: return .medium
        case .medium: return .high
        case .high: return .none
        }
    }
}

// MARK: - Title normalization

// `CadenceTitleNormalization` lives here, not in `Shared/`, for the same mechanical reason
// `TaskTitleShortcutParsing` below does: `CadenceWidgets` and `CadenceMCPServer` have explicit
// source lists that compile all of `Models/` and almost none of `Shared/`. It sat in
// `Shared/CadenceTitleNormalization.swift`, out of the widget's reach, so `TaskTitleShortcutParsing
// .normalized` re-spelled the trim rule and a test pinned the two copies against each other
// (T-406). Moving the declaration is what removes the copy; `Shared/CadenceEventTitleSupport.swift`
// keeps the EventKit-title wrapper that was its file-mate and still delegates here.

/// The one trim rule for every user-entered title or name, on both platforms.
///
/// macOS and iOS spelled the same intent two ways: several macOS forms trimmed `.whitespaces`
/// only (or saved the raw string), while their iOS siblings trimmed `.whitespacesAndNewlines`
/// (T-332). `"Name\n"` therefore round-tripped as `"Name\n"` on the Mac and `"Name"` on the
/// phone — a difference a paste can produce and no form can see. Route new name/title fields
/// here rather than picking whichever spelling the neighbouring file happens to use.
///
/// `.whitespacesAndNewlines` wins because it is the strictly stronger rule: a title is a
/// single-line value, so a trailing newline is never content, and the weaker spelling can only
/// ever let one through.
nonisolated enum CadenceTitleNormalization {
    /// The three placeholder labels a *shared* surface shows for an untitled thing, declared here
    /// rather than in `Shared/` for the mechanical reason at the top of this section — and, this
    /// time, because the reason had already bitten (T-499).
    ///
    /// `TaskTitleSupport.defaultDisplayTitle` and `CadenceContextPickerSupport.untitledName` are
    /// in `Shared/`, which `CadenceMCPServer` does not compile, so `CadenceReadService` and
    /// `NoteReferenceParser` — both of which that target *does* compile — could not read them and
    /// spelled `"Untitled Task"`, `"Untitled Context"` and `"Untitled"` inline at five call sites
    /// instead. That is not a style problem: the MCP `search()`/`list_*` responses and the app's
    /// own rows are the same user-visible copy, and two declarations of it can be renamed apart
    /// without anything going red.
    ///
    /// The `Shared/` names stay; they are what the app's own call sites already read, and they
    /// forward here. This is the shape `TaskTitleSupport.normalized` →
    /// `TaskTitleShortcutParsing.normalized` already has.
    static let defaultTaskTitle = "Untitled Task"

    /// The short spelling, for a row with no width for the noun — a `[[note:…|…]]` reference
    /// label, a board card.
    static let defaultCompactTitle = "Untitled"

    static let defaultContextName = "Untitled Context"

    /// The stored form of a user-entered title: trimmed at both ends, newlines included.
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the value carries no content. `" "` and `"\n"` are blank; this is the guard to
    /// write, not `raw.isEmpty`, which passes a whitespace-only string straight through.
    static func isBlank(_ raw: String) -> Bool {
        normalized(raw).isEmpty
    }

    /// The normalized title, or `fallback` when it is blank. Note that this returns the
    /// *trimmed* title, so a caller cannot accidentally store the untrimmed original after
    /// testing the trimmed one for emptiness.
    static func display(_ raw: String, fallback: String) -> String {
        let trimmed = normalized(raw)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// `display`, for a title about to be written **inside** a `[[task:UUID|Title]]` or
    /// `[[note:UUID|Title]]` reference.
    ///
    /// `]`, `|` and a newline each end the reference early, so a task renamed to "Read [ch. 3]"
    /// would otherwise turn the embed into a broken half-reference the parser no longer
    /// recognises — the card would vanish and leave raw brackets behind. Substituted rather than
    /// stripped, so the title still reads as what the user typed.
    ///
    /// **T-500.** This was two byte-identical private copies — `MarkdownTaskEmbedParser`'s and
    /// `NoteReferenceParser`'s — and it is the one of that ticket's four helpers that is *not* a
    /// re-implementation of `display`: it is `display` composed with the escape above, so
    /// collapsing it into `display` would silently drop the escaping. It lives here rather than
    /// beside either parser because `CadenceMCPServer` compiles `NoteReferenceSupport.swift` and
    /// **not** `MarkdownTaskEmbedSupport.swift`, so the two copies had no shared file to meet in
    /// outside `Models/`.
    static func referenceDisplay(_ title: String, fallback: String) -> String {
        display(
            title
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "|", with: "-")
                .replacingOccurrences(of: "[", with: "(")
                .replacingOccurrences(of: "]", with: ")"),
            fallback: fallback
        )
    }
}

/// The `!` / `!!` / `!!!` shortcut in a typed task title, parsed once for every surface that
/// captures a task.
///
/// It lives in `Models/` rather than beside `TaskTitleSupport` in `Shared/` for one mechanical
/// reason: `CadenceWidgets` has an explicit source list that compiles all of `Models/` and three
/// files of `Shared/`. `TaskTitleSupport.priorityShortcut` was therefore unreachable from
/// `CadenceWidgetIntents`, which open-coded a bare trim instead — so `review launch plan !!!`
/// became a high-priority task titled "review launch plan" when typed in the app and a
/// default-priority task still titled "review launch plan !!!" when typed in the widget (T-354).
/// `TaskTitleSupport` now delegates here and stays the name the app's own call sites use.
///
/// The mapping is bang count to priority, so like `TaskPriority.rank` it is a property of the
/// enum's own vocabulary rather than of any one screen.
nonisolated enum TaskTitleShortcutParsing {
    /// The trim rule for a typed title — the app's one rule, not a second spelling of it.
    ///
    /// This used to re-spell `trimmingCharacters(in: .whitespacesAndNewlines)` because
    /// `CadenceTitleNormalization` was in `Shared/` and out of the widget target's reach, with
    /// `WidgetSupportTests.taskTitleShortcutTrimAgreesWithTheSharedTitleTrim` pinning the two
    /// copies against each other. T-406 moved the declaration into this file instead, which is
    /// what makes the pin structural rather than a promise.
    static func normalized(_ title: String) -> String {
        CadenceTitleNormalization.normalized(title)
    }

    /// The title with its priority marks removed, plus the priority they asked for — or `nil` when
    /// the title carries no shortcut.
    ///
    /// Marks are read at both ends and the louder one wins, so `"!! ship it !!!"` is high.
    static func priorityShortcut(in title: String) -> TaskTitlePriorityShortcut? {
        var cleanedTitle = normalized(title)
        var bangCounts: [Int] = []

        if let leadingCount = leadingBangCount(in: cleanedTitle) {
            bangCounts.append(leadingCount)
            cleanedTitle = normalized(String(cleanedTitle.dropFirst(leadingCount)))
        }

        if let trailingCount = trailingBangCount(in: cleanedTitle) {
            bangCounts.append(trailingCount)
            cleanedTitle = normalized(String(cleanedTitle.dropLast(trailingCount)))
        }

        guard let bangCount = bangCounts.max() else { return nil }
        return TaskTitlePriorityShortcut(
            title: cleanedTitle,
            priority: priority(forBangCount: bangCount)
        )
    }

    /// Resolves `title` and, when it carries a shortcut, overwrites `priority` with it. A title
    /// with no shortcut leaves `priority` exactly as the caller had it — which is how a composer
    /// with a priority picker keeps the user's pick.
    static func titleApplyingPriorityShortcut(
        _ title: String,
        priority: inout TaskPriority
    ) -> String {
        guard let shortcut = priorityShortcut(in: title) else {
            return normalized(title)
        }
        priority = shortcut.priority
        return shortcut.title
    }

    static func leadingBangCount(in title: String) -> Int? {
        let count = title.prefix { $0 == "!" }.count
        return count > 0 ? count : nil
    }

    static func trailingBangCount(in title: String) -> Int? {
        let count = title.reversed().prefix { $0 == "!" }.count
        return count > 0 ? count : nil
    }

    static func priority(forBangCount count: Int) -> TaskPriority {
        switch count {
        case 1: return .low
        case 2: return .medium
        default: return .high
        }
    }
}

nonisolated struct TaskTitlePriorityShortcut: Equatable {
    let title: String
    let priority: TaskPriority
}

nonisolated enum TaskStatus: String, Codable, CaseIterable, Hashable {
    case todo        = "todo"
    case inProgress  = "inprogress"
    case done        = "done"
    case cancelled   = "cancelled"

    var label: String {
        switch self {
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

nonisolated enum TaskRecurrenceRule: String, Codable, CaseIterable, Hashable {
    case none    = "none"
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"
    case yearly  = "yearly"

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "arrow.clockwise"
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .monthly: return "calendar.badge.clock"
        case .yearly: return "calendar.circle"
        }
    }
}

/// How a recurring series stops. `.never` is the default and preserves the historical
/// behavior (a series that repeats forever). The other two cases are paired with
/// `AppTask.recurrenceEndDate` ("yyyy-MM-dd") and `AppTask.recurrenceEndCount` respectively.
nonisolated enum TaskRecurrenceEndMode: String, Codable, CaseIterable, Hashable {
    case never      = "never"
    case onDate     = "onDate"
    case afterCount = "afterCount"

    var label: String {
        switch self {
        case .never: return "Never"
        case .onDate: return "On Date"
        case .afterCount: return "After"
        }
    }

    var shortLabel: String {
        switch self {
        case .never: return "Never"
        case .onDate: return "Date"
        case .afterCount: return "Count"
        }
    }

    var systemImage: String {
        switch self {
        case .never: return "infinity"
        case .onDate: return "calendar.badge.checkmark"
        case .afterCount: return "number"
        }
    }
}

// MARK: - Project enums

nonisolated enum ProjectStatus: String, Codable, CaseIterable, Hashable {
    case active    = "active"
    case done      = "done"
    case archived  = "archived"
    case paused    = "paused"
    case cancelled = "cancelled"
}

nonisolated enum AreaStatus: String, Codable, CaseIterable, Hashable {
    case active   = "active"
    case done     = "done"
    case archived = "archived"
}

// MARK: - Goal enums

nonisolated enum GoalStatus: String, Codable, CaseIterable, Hashable {
    case active = "active"
    case done   = "done"
    case paused = "paused"

    var label: String {
        switch self {
        case .active: return "Active"
        case .done: return "Done"
        case .paused: return "Paused"
        }
    }
}

/// Shape of a goal. Top-level goals are typically `.ongoing` — a long-running direction,
/// which is what the retired `Pursuit` model used to represent — while nested goals are
/// typically `.completable`, a milestone with a finish line.
nonisolated enum GoalKind: String, Codable, CaseIterable, Hashable {
    case ongoing = "ongoing"
    case completable = "completable"
    case maintenance = "maintenance"

    var label: String {
        switch self {
        case .ongoing: return "Ongoing"
        case .completable: return "Completable"
        case .maintenance: return "Maintenance"
        }
    }

    var detail: String {
        switch self {
        case .ongoing: return "Long-running growth"
        case .completable: return "Has a finish line"
        case .maintenance: return "Keep steady"
        }
    }

    var systemImage: String {
        switch self {
        case .ongoing: return "infinity"
        case .completable: return "flag.fill"
        case .maintenance: return "repeat"
        }
    }
}

nonisolated enum GoalProgressType: String, Codable, CaseIterable, Hashable {
    case subtasks = "subtasks"
    case hours    = "hours"

    /// The `.subtasks` raw value is persisted and stays as it is; the label does not.
    /// This mode counts whole `AppTask` rows — `Subtask` is a different model that never takes
    /// part in the ratio — so "Subtasks" named something the number has nothing to do with.
    var label: String {
        switch self {
        case .subtasks: return "Tasks"
        case .hours:    return "Hours"
        }
    }
}

// MARK: - Habit enums

nonisolated enum HabitFrequency: String, Codable, CaseIterable, Hashable {
    case daily         = "daily"
    case daysOfWeek    = "daysOfWeek"
    case timesPerWeek  = "timesPerWeek"
    case monthly       = "monthly"

    var label: String {
        switch self {
        case .daily:        return "Daily"
        case .daysOfWeek:   return "Days of Week"
        case .timesPerWeek: return "Times per Week"
        case .monthly:      return "Monthly"
        }
    }

    /// Selectable weekly targets for `.timesPerWeek`.
    ///
    /// Capped at seven because a week only has seven days and completion is a per-day toggle with
    /// no counter UI on either platform — so a target above 7 can never be met, and
    /// `Habit.currentStreak` reports a permanent zero for it. The iOS editor offered `1...14`,
    /// which made that state reachable in two taps.
    static let weeklyTargetRange: ClosedRange<Int> = 1...7

    /// Pulls a stored `targetCount` back into a reachable weekly target, for editors opening a
    /// habit written before the cap existed.
    static func clampedWeeklyTarget(_ target: Int) -> Int {
        min(max(weeklyTargetRange.lowerBound, target), weeklyTargetRange.upperBound)
    }
}
