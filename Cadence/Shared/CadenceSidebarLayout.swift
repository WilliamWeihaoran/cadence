import Foundation

/// Where each destination sits in the sidebar, and which counts a sidebar row may carry.
///
/// This lives in `Shared/` rather than next to `SidebarView` because the iPad sidebar is being
/// brought to the same layout. Grouping, the ordering rule, and the count rule are exactly the
/// parts that would otherwise be written twice and drift — the repo's most productive bug.
enum CadenceSidebarLayout {
    /// The sidebar's two fixed nav groups. Structure, not user data: the group a destination
    /// belongs to is decided here, and the user's stored order sorts *within* a group.
    enum NavGroup: String, CaseIterable, Identifiable {
        /// Above the lists — where the day's work happens.
        case primary
        /// Below the lists — everything else you navigate to.
        case secondary

        var id: String { rawValue }
    }

    static let primaryDestinations: [CadenceFeatureDestination] = [
        .today, .allTasks, .calendar, .notes, .inbox
    ]

    static let secondaryDestinations: [CadenceFeatureDestination] = [
        .goals, .habits, .focus, .settings
    ]

    /// The two the iPad sidebar renders as glyphs in one footer row rather than as labelled rows —
    /// Settings leading, Focus trailing.
    ///
    /// Deliberately a *view* of `secondaryDestinations` rather than a change to it: macOS reads
    /// that list too, and its sidebar still wants four labelled rows. Splitting here keeps the two
    /// platforms agreeing about which destinations exist and in what order, while letting one of
    /// them spend less height on the last two.
    static let footerGlyphDestinations: [CadenceFeatureDestination] = [.settings, .focus]

    /// `secondaryDestinations` minus the two that become footer glyphs, in the original order.
    static var secondaryRowDestinations: [CadenceFeatureDestination] {
        secondaryDestinations.filter { !footerGlyphDestinations.contains($0) }
    }

    static func destinations(in group: NavGroup) -> [CadenceFeatureDestination] {
        switch group {
        case .primary: return primaryDestinations
        case .secondary: return secondaryDestinations
        }
    }

    /// Every destination the sidebar renders a nav row for, in top-to-bottom order.
    ///
    /// Deliberately not all of `CadenceFeatureDestination`: `.lists` is the scrolling region
    /// between the two groups rather than a row, and `.search` is the header's button.
    ///
    /// `.inbox` **is** a row, in the primary group. It was briefly dropped from this layout, which
    /// also left Settings → Sidebar offering it a visibility toggle and a colour picker that
    /// changed nothing — a destination removed from here silently turns its Settings entry into a
    /// dead control, so anything taken out of this list has to come out of that screen too.
    static var navigationDestinations: [CadenceFeatureDestination] {
        primaryDestinations + secondaryDestinations
    }

    static func group(for destination: CadenceFeatureDestination) -> NavGroup? {
        if primaryDestinations.contains(destination) { return .primary }
        if secondaryDestinations.contains(destination) { return .secondary }
        return nil
    }

    /// One group's rows, with the user's Settings → Sidebar order and hidden set applied.
    ///
    /// - `customisable` is the set of rows Settings offers a handle for. The rows outside it
    ///   (Notes, Settings) hold their declared slot in the group rather than being swept to the
    ///   front or the back, and they cannot be hidden: a `hidden` entry only counts for a
    ///   customisable destination, so a stray value can never take Settings off the screen.
    /// - `storedOrder` is what the user actually dragged, **not** a defaults-filled list. A
    ///   destination the string never named keeps its declared position, so an untouched
    ///   preference renders the layout as declared instead of as whatever sequence the stored
    ///   default happened to have.
    static func resolvedDestinations(
        in group: NavGroup,
        customisable: Set<CadenceFeatureDestination>,
        storedOrder: [CadenceFeatureDestination] = [],
        hidden: Set<CadenceFeatureDestination> = []
    ) -> [CadenceFeatureDestination] {
        let visible = destinations(in: group).filter { destination in
            !(customisable.contains(destination) && hidden.contains(destination))
        }

        let rank = storedOrder.enumerated().reduce(into: [CadenceFeatureDestination: Int]()) { partial, pair in
            if partial[pair.element] == nil { partial[pair.element] = pair.offset }
        }
        // Declared position is the tie-break, so rows the stored order never named stay in the
        // sequence this file declares rather than in whatever order `sorted` happens to produce.
        var movable = visible.enumerated()
            .filter { customisable.contains($0.element) }
            .sorted { lhs, rhs in
                let lhsRank = rank[lhs.element] ?? .max
                let rhsRank = rank[rhs.element] ?? .max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        // Walk the group's own slots: a fixed row keeps its position, a customisable slot takes
        // the next row in the user's order. Both arrays are built from `visible`, so the counts
        // agree and the `removeFirst` below cannot run dry.
        return visible.map { destination in
            guard customisable.contains(destination) else { return destination }
            return movable.removeFirst()
        }
    }
}

// MARK: - Counts

/// How much weight a sidebar count carries.
///
/// There is exactly **one** urgent count in the sidebar — Today's overdue tally — and
/// `CadenceSidebarLayout.count(for:counts:)` is the only thing that hands one out. Every other
/// count is neutral, the same rule the task rows and the calendar already follow.
enum CadenceSidebarCountEmphasis: Equatable {
    case neutral
    case urgent
}

/// A count a sidebar row may render. Never constructed for zero: a badge reading "0" is chrome
/// that says nothing, so the absence of a badge is the zero state.
struct CadenceSidebarCount: Equatable {
    let value: Int
    let emphasis: CadenceSidebarCountEmphasis
}

/// The tallies a sidebar needs to decide its counts, as plain numbers so the rule is testable
/// without a model container.
struct CadenceSidebarCountInputs: Equatable {
    var todayOverdueCount: Int = 0
    var openTaskCount: Int = 0
    var activeGoalCount: Int = 0
    var habitCount: Int = 0
}

extension CadenceSidebarLayout {
    /// The count for a nav row, or `nil` when the row carries none.
    ///
    /// Today's number is its **overdue** tally rather than "things happening today": it is the one
    /// number in this column that is about being late, which is what earns it the only red in the
    /// sidebar. Calendar, Notes and Focus carry no count — a number there would be volume rather
    /// than a call to act.
    static func count(
        for destination: CadenceFeatureDestination,
        counts: CadenceSidebarCountInputs
    ) -> CadenceSidebarCount? {
        switch destination {
        case .today:
            return badge(counts.todayOverdueCount, emphasis: .urgent)
        case .allTasks:
            return badge(counts.openTaskCount)
        case .goals:
            return badge(counts.activeGoalCount)
        case .habits:
            return badge(counts.habitCount)
        case .calendar, .notes, .focus, .inbox, .lists, .search, .settings:
            return nil
        }
    }

    /// The count for one area/project row. Always neutral — a list is a place, not a deadline.
    static func listCount(openTaskCount: Int) -> CadenceSidebarCount? {
        badge(openTaskCount)
    }

    /// Open work whose deadline has already passed.
    ///
    /// `AppTask.isOverdue(todayKey:)` is the repo's one overdue predicate and answers the `isDone`
    /// half itself; the extra guard here is the same "open work" filter
    /// `CadenceTaskQuerySupport.openTaskCount` applies, because a cancelled task is not work you
    /// are late on.
    static func overdueTaskCount(from tasks: [AppTask], todayKey: String) -> Int {
        tasks.reduce(into: 0) { count, task in
            if !task.isCancelled && task.isOverdue(todayKey: todayKey) { count += 1 }
        }
    }

    private static func badge(
        _ value: Int,
        emphasis: CadenceSidebarCountEmphasis = .neutral
    ) -> CadenceSidebarCount? {
        value > 0 ? CadenceSidebarCount(value: value, emphasis: emphasis) : nil
    }
}
