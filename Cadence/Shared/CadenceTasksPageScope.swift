import Foundation

/// The two views the **Tasks** destination switches between.
///
/// All Tasks and Inbox were two sidebar rows and two pages for one universe of work: Inbox is
/// All Tasks with a single predicate (`area == nil && project == nil`), and the All Tasks *board*
/// had already merged them — Inbox is one of its list columns. They are one destination now, with
/// this enum as the switch inside it. `.today` is deliberately absent: Today is a three-pane
/// dashboard, not a filter over the same rows.
///
/// It lives in `Shared/` because both sidebar shells route into the merged page, and because the
/// mapping to `CadenceFeatureDestination` is what keeps the command palette's two entries and the
/// widgets' deep links landing on the right view — a mapping that has to be testable.
///
/// **Its labels are `CadenceTasksSection`'s**, not a second set. The iPhone's Tasks tab has been
/// this design in tab-bar form for a while, with three segments rather than two; borrowing its
/// words is what stops the phone saying "All" while the Mac says "All Tasks" in the same control.
nonisolated enum CadenceTasksPageScope: String, CaseIterable, Identifiable, Hashable {
    case all
    case inbox

    var id: String { rawValue }

    static let defaultScope: CadenceTasksPageScope = .all

    /// Persisted values are read back through here so an unknown or empty string lands on the
    /// default instead of leaving the page with no view selected.
    static func resolved(_ rawValue: String) -> CadenceTasksPageScope {
        CadenceTasksPageScope(rawValue: rawValue) ?? defaultScope
    }

    /// Which task surface this scope is, for `CadenceTaskSurfaceOptions` — the desktop twin of
    /// `CadenceTaskCollection.surface`, which iOS's one page for both scopes already reads. macOS
    /// re-answered all four of that value's questions inline until T-290.
    var surface: CadenceTaskSurface {
        switch self {
        case .all: return .allTasks
        case .inbox: return .inbox
        }
    }

    /// The iPhone segment this scope is the desktop spelling of. The single source for both the
    /// switcher's label and the destination it opens.
    var section: CadenceTasksSection {
        switch self {
        case .all: return .all
        case .inbox: return .inbox
        }
    }

    /// The switcher's label — "All" / "Inbox". Short, because the page header one row up already
    /// says Tasks.
    var title: String { section.title }

    /// The page header's title, which is the full name: the header is the one place with room to
    /// say "All Tasks" rather than "All".
    var pageTitle: String { destination.title }

    var destination: CadenceFeatureDestination { section.destination }

    /// The scope a destination opens, or `nil` for the destinations this page does not host.
    init?(destination: CadenceFeatureDestination) {
        switch destination {
        case .allTasks: self = .all
        case .inbox: self = .inbox
        case .today, .focus, .calendar, .notes, .lists, .goals, .habits, .search, .settings:
            return nil
        }
    }
}

extension CadenceTasksPageScope {
    /// The scope an iOS task collection is the mobile spelling of.
    ///
    /// `CadenceTaskCollection` is the same two-case choice this enum is — every task, or the
    /// unfiled ones — arrived at independently on the iOS side, and both are deliberately outside
    /// every platform guard so the macOS-built test target can see them. They are mapped rather
    /// than merged because they answer different questions: this one names a *view of the merged
    /// Tasks page*, and that one carries the words, the glyph and the drop identity a collection is
    /// drawn with.
    ///
    /// The mapping exists so `showsRemindersStrip` has exactly one caller per platform. Spelling
    /// `collection == .inbox` at the iOS call site instead would be a second gate beside the tested
    /// one, which is the shape of the bug the gate was written to prevent.
    init(collection: CadenceTaskCollection) {
        switch collection {
        case .allTasks: self = .all
        case .inbox: self = .inbox
        }
    }

    /// Whether the Apple Reminders strip belongs on this view of the Tasks page.
    ///
    /// **This is the highest-risk line in the All Tasks / Inbox merge.** The strip is what makes
    /// the Inbox an *inbox* rather than a filter — unprocessed things, including ones captured
    /// outside Cadence. Merging two pages into one is exactly the change that deletes something
    /// like it by omission, so the rule is a function with a test rather than a `guard` inside a
    /// view body nothing can observe.
    ///
    /// **Two callers, one per platform**, and that is the whole point of it being a function:
    /// `macOS/Views/TasksListView.swift` and `iOS/iOSTaskCollectionPage.swift`. It used to have
    /// one, and this comment used to call the strip "the only place in the app that shows Apple
    /// Reminders" — true, and the reason the shipped
    /// `NSRemindersFullAccessUsageDescription` ("…show your active reminders in Inbox and mark them
    /// complete when you check them off") was a false statement on iOS, where no reminders surface
    /// existed outside Settings and `RemindersManager.completeReminder(id:)` had no caller at all.
    /// T-163 built the iOS half against this gate rather than beside it; T-167 is the string it
    /// makes true.
    ///
    /// Inbox and only Inbox: `.all` answers `false` for every combination of the other three
    /// arguments. The rest is the gate the Inbox page already had — the strip appears when there
    /// are reminders to show, *or* when there is something to say about there not being any:
    /// access has not been granted (so the row is a Connect button) or the fetch is still running.
    static func showsRemindersStrip(
        scope: CadenceTasksPageScope,
        isAuthorized: Bool,
        isLoading: Bool,
        hasReminders: Bool
    ) -> Bool {
        guard scope == .inbox else { return false }
        return !isAuthorized || isLoading || hasReminders
    }
}
