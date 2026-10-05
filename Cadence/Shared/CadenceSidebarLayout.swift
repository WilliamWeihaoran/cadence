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

    /// Four rows. Goals and Habits were the fifth and sixth from T-1274 until **T-2076**, which
    /// removed both features from the navigation at the owner's request — *"we should just remove
    /// habits and milestones cuz i just wont need them that often"*. Their models and CloudKit
    /// record types are untouched; what went is every way to reach them.
    ///
    /// A synced `SidebarLayoutPreference` written before that still names `goals` and `habits` in
    /// its order or hidden set. Those raw values no longer decode and are dropped on read, which
    /// is the behaviour `CadenceSidebarLayoutPreferenceStore.destinations(fromRaw:)` has always
    /// had for an unrecognised token; the rows that do decode keep their relative order.
    ///
    /// `.inbox` is still not here. It was never a separate universe — Inbox is All Tasks with one
    /// predicate, and the All Tasks *board* had already merged the two by rendering Inbox as one of
    /// its list columns. The two are one destination now (`CadenceTasksPageScope`), reached through
    /// this one row. Today stays its own row: it is a three-pane dashboard, not a filter over the
    /// same rows.
    static let primaryDestinations: [CadenceFeatureDestination] = [
        .today, .allTasks, .calendar, .notes
    ]

    /// What is left below the lists: the two footer glyphs and nothing else. Both members are in
    /// `footerGlyphDestinations`, so `secondaryRowDestinations` is empty and neither column draws
    /// a labelled row down there any more.
    static let secondaryDestinations: [CadenceFeatureDestination] = [
        .focus, .settings
    ]

    /// The rows Settings → Sidebar offers controls for: a visibility toggle and a colour override
    /// for all of them, and a place in the stored order for the ones `isOrderable(_:)` admits.
    ///
    /// The nav group plus Focus. Settings itself is deliberately absent — it is the only door to
    /// the screen that would hide it — and `.lists`, `.search` and `.inbox` are absent because they
    /// are not rows (see `navigationDestinations`).
    ///
    /// Focus is in the set for the two halves of it that bite: hiding Focus drops its footer glyph,
    /// and the colour picker tints it. What it is **not** offered is a place in the order — see
    /// `isOrderable(_:)`, which is the T-1287 half. Taking the whole row out of Settings would have
    /// taken the two working controls with it, so the row stays and the handle goes.
    ///
    /// Spelled here rather than derived from macOS's `SidebarStaticDestination`, which is not
    /// visible to iOS; `CadenceSidebarLayoutTests` pins the two against each other.
    static let customisableDestinations: Set<CadenceFeatureDestination> = [
        .today, .allTasks, .calendar, .notes, .focus
    ]

    /// The two **both** sidebars render as glyphs in one footer row rather than as labelled rows —
    /// Settings leading, Focus trailing.
    ///
    /// This used to say it was deliberately a *view* of `secondaryDestinations` rather than a
    /// change to it because "macOS reads that list too, and its sidebar still wants four labelled
    /// rows". That is no longer true and the reason is not a refactor: the user compared the two
    /// columns and said the Mac keeping Settings and Focus as separate labelled buttons was wrong
    /// and should match iOS. `SidebarView` honours this list now, exactly as `iOSSidebar` does.
    ///
    /// It stays a *view* of `secondaryDestinations` for the half of the original reasoning that
    /// still holds: both platforms have to agree about which destinations exist and in what order,
    /// and the footer split is a rendering decision on top of that, not a second list. Since
    /// T-1274 the two lists have the same members — Goals and Habits moved up into the nav group,
    /// and T-2076 removed both — so `secondaryRowDestinations` is empty and both columns draw
    /// nothing between the lists and the footer. That is a coincidence of the current membership,
    /// not a licence to delete either list: a future destination placed below the lists goes in
    /// `secondaryDestinations` alone.
    static let footerGlyphDestinations: [CadenceFeatureDestination] = [.settings, .focus]

    /// Whether Settings may offer this destination a **place in the order**, as distinct from the
    /// visibility toggle and the colour picker, which every `customisableDestinations` member gets.
    ///
    /// A footer glyph has none. The footer draws `footerGlyphDestinations` in that list's own
    /// order — Settings leading, Focus trailing — so a Focus row dragged to the top of the Settings
    /// list redrew in exactly the same place and moved nothing, for as long as the footer row has
    /// existed (T-1287). The handle was the untrue part, not the row.
    ///
    /// **Derived from the two lists that decide the rendering rather than spelled as a third**, so
    /// the handle cannot go on claiming an order the footer does not read: a destination promoted
    /// out of the footer into a labelled row gets its handle back by moving between those lists,
    /// and one demoted into the footer loses it the same way.
    ///
    /// The other direction was considered and rejected: teaching the footer to sort by the stored
    /// order. `.settings` is deliberately absent from `customisableDestinations` — it is the only
    /// door to the screen that would hide it — so it never appears in the stored order at all, and
    /// there is nothing in the Settings list to drag Focus above or below to say where it goes in
    /// the footer. Any rule mapping a nav-row drag onto a two-glyph footer would be invented rather
    /// than expressed, and it would re-seat the shipped `[.settings, .focus]` for every user who
    /// has ever dragged anything, to swap two icons nobody asked to swap.
    static func isOrderable(_ destination: CadenceFeatureDestination) -> Bool {
        customisableDestinations.contains(destination) && !footerGlyphDestinations.contains(destination)
    }

    /// `secondaryDestinations` minus the ones that become footer glyphs, in the original order.
    /// Empty today; see `footerGlyphDestinations`.
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
    /// between the two groups rather than a row, `.search` is the header's button, and `.inbox` is
    /// a view inside the Tasks row rather than a row of its own — see `navRow(for:)`.
    ///
    /// A destination removed from here silently turns its Settings → Sidebar entry into a dead
    /// control: the toggle and the colour picker keep drawing and change nothing. So anything
    /// taken out of this list has to come out of `SidebarStaticDestination` too, which is what
    /// `everyRowSettingsLetsYouCustomiseIsActuallyRendered` pins.
    static var navigationDestinations: [CadenceFeatureDestination] {
        primaryDestinations + secondaryDestinations
    }

    static func group(for destination: CadenceFeatureDestination) -> NavGroup? {
        if primaryDestinations.contains(destination) { return .primary }
        if secondaryDestinations.contains(destination) { return .secondary }
        return nil
    }

    /// The nav row a destination is reached through.
    ///
    /// `.inbox` has no row of its own — it is one of the two views inside the Tasks destination —
    /// so a selection of Inbox lights the **Tasks** row rather than lighting nothing at all. That
    /// happens for real: the command palette still offers "Inbox" as its own entry, and it should,
    /// because it is still its own view.
    ///
    /// Every other destination is its own row, including the two that have none: `.lists` and
    /// `.search` answer themselves here and are simply absent from `navigationDestinations`.
    static func navRow(for destination: CadenceFeatureDestination) -> CadenceFeatureDestination {
        destination == .inbox ? .allTasks : destination
    }

    /// The label a nav row carries, which is not always the destination's own `title`.
    ///
    /// The row that opens `.allTasks` reads **Tasks**, because half of what it opens is the Inbox
    /// — a row labelled "All Tasks" would be naming one of its own two views. That string is
    /// `compactTitle`, which already said exactly this for the iPad column and the iPhone tab;
    /// reading it from here rather than re-spelling it is what keeps the two sidebars agreeing.
    static func rowTitle(for destination: CadenceFeatureDestination) -> String {
        destination.compactTitle
    }

    /// Where the selection goes when the row it was on has just been hidden (T-1274), or `nil`
    /// when it has nowhere to go and nothing to do.
    ///
    /// **`nil` is the common answer and it means "leave the selection alone".** A destination whose
    /// row is still drawn is untouched; so is one that never had a row — `.lists` is the scrolling
    /// region and `.search` is the header button, and no hidden set can take either away.
    ///
    /// Otherwise the selection lands on the **first visible row**, top of the column, rather than
    /// on a fixed destination: Today itself can be hidden, so a constant fallback would be a
    /// selection the sidebar does not draw. `visibleRows` is what the sidebar just resolved, so the
    /// row it moves to is the one the user is looking at.
    static func selectionFallback(
        for destination: CadenceFeatureDestination,
        visibleRows: [CadenceFeatureDestination]
    ) -> CadenceFeatureDestination? {
        let row = navRow(for: destination)
        guard navigationDestinations.contains(row) else { return nil }
        guard !visibleRows.contains(row) else { return nil }
        return visibleRows.first
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
    /// **What the number counts, in words** — "2 overdue", "7 open tasks" (T-1445).
    ///
    /// The sidebar's Today badge and the Today page's header badge are two different tallies of
    /// the same day: this one is `overdueTaskCount`, the header's is
    /// `TasksPanelDerivedState.todayEligibleTasks.count`. Both are right and they legitimately
    /// disagree — 2 beside 7 on the screen that reported this — so the pair is only honest if the
    /// reader can find out which is which. Colour and shape already differ (a bare `Theme.red`
    /// digit here, an amber-filled capsule there) and say nothing about *what*; this is the half
    /// that does, and it is carried on the value rather than derived at the row, because
    /// `count(for:counts:)` is the only thing that knows what each tally means.
    ///
    /// Not a second rendering: the digits stay the whole of the visible badge. This is the row's
    /// tooltip and its VoiceOver label — where, before this, the number was announced as nothing
    /// at all (`CadenceSidebarCountLabel` is `accessibilityHidden` and the rows label themselves
    /// with the bare destination name).
    let description: String
}

/// The tallies a sidebar needs to decide its counts, as plain numbers so the rule is testable
/// without a model container.
struct CadenceSidebarCountInputs: Equatable {
    var todayOverdueCount: Int = 0
    var openTaskCount: Int = 0
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
            // "overdue" is an adjective and does not take a plural, which is why the phrase
            // helper takes both forms rather than appending an "s".
            return badge(counts.todayOverdueCount, emphasis: .urgent, singular: "overdue", plural: "overdue")
        case .allTasks:
            return badge(counts.openTaskCount, singular: "open task", plural: "open tasks")
        case .calendar, .notes, .focus, .inbox, .lists, .search, .settings:
            return nil
        }
    }

    /// The row's own label with its count named after it — "Today, 2 overdue".
    ///
    /// One function for the tooltip and the VoiceOver label, on both platforms, so a row cannot
    /// say one thing on hover and another to a screen reader. `label` alone when the row carries
    /// no count, because ", 0" is the chrome `badge` already refuses to draw.
    static func rowAccessibilityLabel(_ label: String, count: CadenceSidebarCount?) -> String {
        guard let count else { return label }
        return "\(label), \(count.description)"
    }

    /// The count for one area/project row. Always neutral — a list is a place, not a deadline.
    static func listCount(openTaskCount: Int) -> CadenceSidebarCount? {
        badge(openTaskCount, singular: "open task", plural: "open tasks")
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
        emphasis: CadenceSidebarCountEmphasis = .neutral,
        singular: String,
        plural: String
    ) -> CadenceSidebarCount? {
        guard value > 0 else { return nil }
        return CadenceSidebarCount(
            value: value,
            emphasis: emphasis,
            description: "\(value) \(value == 1 ? singular : plural)"
        )
    }
}
