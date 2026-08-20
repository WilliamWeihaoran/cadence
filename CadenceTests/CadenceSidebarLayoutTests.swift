import Foundation
import Testing
@testable import Cadence

/// The sidebar's structure, ordering rule, and count rule.
///
/// These live in `Shared/` because the iPad sidebar is being brought to the same layout, so the
/// answers to "which group is this in", "what does the user's stored order move", and "which count
/// is allowed to be red" have to be one set of answers rather than two that drift.
@MainActor
struct CadenceSidebarLayoutTests {
    // MARK: - Structure

    @Test func theTwoGroupsAreTheChosenSevenRowsInOrder() {
        #expect(CadenceSidebarLayout.primaryDestinations == [.today, .allTasks, .calendar, .notes])
        #expect(CadenceSidebarLayout.secondaryDestinations == [.goals, .habits, .focus, .settings])
    }

    /// **The merge, pinned.** All Tasks and Inbox are one destination reached through one row, so
    /// the primary group is four rows and Inbox is not among them. Spelled as a count *and* as a
    /// membership check because the two fail differently: a fifth row of any kind trips the first,
    /// and Inbox specifically coming back trips the second even if something else left at the same
    /// time.
    ///
    /// A verifier recently reverted a committed fix with the whole suite green, because the tests
    /// pinned a helper while nothing observed the call site. This is the call site.
    @Test func theTasksRowIsOneRowAndInboxIsNotASecondOne() {
        #expect(CadenceSidebarLayout.primaryDestinations.count == 4)
        #expect(!CadenceSidebarLayout.primaryDestinations.contains(.inbox))
        #expect(!CadenceSidebarLayout.navigationDestinations.contains(.inbox))
        #expect(CadenceSidebarLayout.navigationDestinations.count == 8)

        // And the row that replaced them is reachable from both destinations.
        #expect(CadenceSidebarLayout.navRow(for: .inbox) == .allTasks)
        #expect(CadenceSidebarLayout.navRow(for: .allTasks) == .allTasks)
        #expect(CadenceSidebarLayout.navigationDestinations.contains(CadenceSidebarLayout.navRow(for: .inbox)))
    }

    /// Every destination that has a page must land on a row that exists, or something is
    /// unreachable from the column. `.lists` and `.search` are the two that answer "no row" on
    /// purpose — the scrolling region and the header button.
    @Test func everyDestinationFoldsOntoARowTheSidebarActuallyDraws() {
        let rows = Set(CadenceSidebarLayout.navigationDestinations)

        for destination in CadenceFeatureDestination.allCases {
            let row = CadenceSidebarLayout.navRow(for: destination)
            if destination == .lists || destination == .search {
                #expect(!rows.contains(row), "\(destination.title) grew a row")
                continue
            }
            #expect(rows.contains(row), "\(destination.title) folds onto a row nothing draws")
        }
    }

    /// The row label is not always the destination's `title`: the Tasks row cannot read "All Tasks"
    /// while half of what it opens is the Inbox.
    @Test func theTasksRowIsLabelledTasks() {
        #expect(CadenceSidebarLayout.rowTitle(for: .allTasks) == "Tasks")

        for destination in CadenceSidebarLayout.navigationDestinations where destination != .allTasks {
            #expect(
                CadenceSidebarLayout.rowTitle(for: destination) == destination.title,
                "\(destination.title) grew a second name"
            )
        }
    }

    /// Both columns render these two as one row of glyphs rather than two labelled rows. macOS drew
    /// four labelled rows here until the user asked for the two sidebars to match; this is what
    /// would have to change back if that were ever revisited.
    @Test func theFooterGlyphsAreSettingsAndFocusInThatOrder() {
        #expect(CadenceSidebarLayout.footerGlyphDestinations == [.settings, .focus])
        #expect(CadenceSidebarLayout.secondaryRowDestinations == [.goals, .habits])

        // A view of the secondary group, never a second list.
        let secondary = Set(CadenceSidebarLayout.secondaryDestinations)
        #expect(Set(CadenceSidebarLayout.footerGlyphDestinations).isSubset(of: secondary))
        #expect(
            Set(CadenceSidebarLayout.secondaryRowDestinations)
                .union(CadenceSidebarLayout.footerGlyphDestinations) == secondary
        )
    }

    @Test func noDestinationSitsInBothGroupsAndGroupLookupAgrees() {
        let primary = Set(CadenceSidebarLayout.primaryDestinations)
        let secondary = Set(CadenceSidebarLayout.secondaryDestinations)
        #expect(primary.isDisjoint(with: secondary))

        for destination in CadenceFeatureDestination.allCases {
            switch CadenceSidebarLayout.group(for: destination) {
            case .primary:
                #expect(primary.contains(destination))
            case .secondary:
                #expect(secondary.contains(destination))
            case nil:
                #expect(!primary.contains(destination) && !secondary.contains(destination))
            }
        }
    }

    /// The three destinations the sidebar deliberately renders as something other than a nav row —
    /// Lists is the scrolling region, Search is the header button, and Inbox is a view inside the
    /// Tasks row. Pinned so that adding a destination and forgetting to place it is a test failure
    /// rather than a screen nobody can reach.
    @Test func theDestinationsWithoutANavRowAreExactlyTheKnownThree() {
        let missing = Set(CadenceFeatureDestination.allCases)
            .subtracting(CadenceSidebarLayout.navigationDestinations)

        #expect(missing == [.lists, .search, .inbox])
    }

    // MARK: - Ordering

    /// The rows Settings → Sidebar offers a handle for, on macOS.
    private let customisable: Set<CadenceFeatureDestination> = [
        .today, .allTasks, .focus, .calendar, .goals, .habits
    ]

    private func resolved(
        _ group: CadenceSidebarLayout.NavGroup,
        storedOrder: [CadenceFeatureDestination] = [],
        hidden: Set<CadenceFeatureDestination> = []
    ) -> [CadenceFeatureDestination] {
        CadenceSidebarLayout.resolvedDestinations(
            in: group,
            customisable: customisable,
            storedOrder: storedOrder,
            hidden: hidden
        )
    }

    @Test func withNothingCustomisedEachGroupIsItsDeclaredOrder() {
        #expect(resolved(.primary) == CadenceSidebarLayout.primaryDestinations)
        #expect(resolved(.secondary) == CadenceSidebarLayout.secondaryDestinations)
    }

    /// The regression this rule exists for: the *stored default* order lists Focus third, so
    /// feeding a defaults-filled list in would push Focus above Goals and Habits for a user who
    /// has never dragged anything. Only rows the user actually moved may move.
    @Test func aStoredOrderNamingOnlySomeRowsLeavesTheRestWhereTheyWereDeclared() {
        #expect(resolved(.secondary, storedOrder: [.focus]) == [.focus, .goals, .habits, .settings])
        #expect(resolved(.secondary, storedOrder: [.habits]) == [.habits, .goals, .focus, .settings])
        #expect(resolved(.primary, storedOrder: [.calendar]) == [.calendar, .today, .allTasks, .notes])
    }

    /// A user who reorders in Settings must not lose that. The stored order sorts *within* a
    /// group: Calendar can move above Today, and it still cannot cross the lists into the other
    /// group.
    @Test func theStoredOrderSortsWithinAGroup() {
        let reordered: [CadenceFeatureDestination] = [
            .calendar, .today, .allTasks, .habits, .goals, .focus
        ]

        #expect(resolved(.primary, storedOrder: reordered) == [.calendar, .today, .allTasks, .notes])
        #expect(resolved(.secondary, storedOrder: reordered) == [.habits, .goals, .focus, .settings])
    }

    /// Notes and Settings have no Settings → Sidebar handle, so they hold their declared slot
    /// instead of being swept to the front or the back of whatever the movable rows do.
    @Test func theRowsSettingsCannotMoveKeepTheirSlot() {
        let reversed: [CadenceFeatureDestination] = [
            .habits, .goals, .calendar, .focus, .allTasks, .today
        ]

        // Notes sits at index 3 of the primary group, the last of the four, and holds that slot
        // however the three movable rows above it are reordered.
        #expect(resolved(.primary, storedOrder: reversed)[3] == .notes)
        #expect(resolved(.secondary, storedOrder: reversed).last == .settings)
    }

    // MARK: - Visibility

    @Test func hidingARowRemovesItAndLeavesTheRestInOrder() {
        #expect(resolved(.primary, hidden: [.allTasks]) == [.today, .calendar, .notes])
        #expect(resolved(.secondary, hidden: [.goals, .focus]) == [.habits, .settings])
    }

    /// Only a row Settings offers a handle for can be hidden. A stray value for a row it does not
    /// — Settings itself, most of all — must not take the only door to preferences off the screen.
    @Test func aRowSettingsCannotHideStaysOnScreen() {
        #expect(resolved(.secondary, hidden: [.settings]) == CadenceSidebarLayout.secondaryDestinations)
        #expect(resolved(.primary, hidden: [.notes]) == CadenceSidebarLayout.primaryDestinations)
    }

    @Test func hidingEveryMovableRowStillLeavesTheFixedOnes() {
        #expect(resolved(.primary, hidden: customisable) == [.notes])
        #expect(resolved(.secondary, hidden: customisable) == [.settings])
    }

    // MARK: - Counts

    private let counts = CadenceSidebarCountInputs(
        todayOverdueCount: 3,
        openTaskCount: 41,
        activeGoalCount: 4,
        habitCount: 2
    )

    @Test func eachRowReadsItsOwnNumber() {
        #expect(CadenceSidebarLayout.count(for: .today, counts: counts)?.value == 3)
        #expect(CadenceSidebarLayout.count(for: .allTasks, counts: counts)?.value == 41)
        #expect(CadenceSidebarLayout.count(for: .goals, counts: counts)?.value == 4)
        #expect(CadenceSidebarLayout.count(for: .habits, counts: counts)?.value == 2)

        for destination in [CadenceFeatureDestination.calendar, .notes, .focus, .settings] {
            #expect(
                CadenceSidebarLayout.count(for: destination, counts: counts) == nil,
                "\(destination.title) grew a count that is volume rather than a call to act"
            )
        }
    }

    /// The rule the sidebar was the last surface still deciding for itself.
    @Test func todaysOverdueTallyIsTheOnlyCountAllowedToBeUrgent() {
        for destination in CadenceFeatureDestination.allCases {
            guard let count = CadenceSidebarLayout.count(for: destination, counts: counts) else { continue }
            #expect(
                (count.emphasis == .urgent) == (destination == .today),
                "\(destination.title) claims urgency it has not earned"
            )
        }

        #expect(CadenceSidebarLayout.listCount(openTaskCount: 7)?.emphasis == .neutral)
    }

    @Test func aZeroIsNoCountAtAllRatherThanABadgeReadingZero() {
        let empty = CadenceSidebarCountInputs()

        for destination in CadenceFeatureDestination.allCases {
            #expect(CadenceSidebarLayout.count(for: destination, counts: empty) == nil)
        }
        #expect(CadenceSidebarLayout.listCount(openTaskCount: 0) == nil)
        #expect(CadenceSidebarLayout.listCount(openTaskCount: 1)?.value == 1)
    }

    // MARK: - Overdue tally

    private func task(due: String, status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: "T")
        task.dueDate = due
        task.status = status
        return task
    }

    @Test func theOverdueTallyCountsOpenWorkWithAPassedDeadline() {
        let todayKey = "2026-08-16"
        let tasks = [
            task(due: "2026-08-15"),                    // late
            task(due: "2026-01-02"),                    // late
            task(due: "2026-08-16"),                    // due today is not late
            task(due: "2026-08-17"),                    // future
            task(due: ""),                              // no deadline to miss
            task(due: "2026-08-15", status: .done),     // finished
            task(due: "2026-08-15", status: .cancelled) // not work you are late on
        ]

        #expect(CadenceSidebarLayout.overdueTaskCount(from: tasks, todayKey: todayKey) == 2)
        #expect(CadenceSidebarLayout.overdueTaskCount(from: [], todayKey: todayKey) == 0)
    }

    /// The tally has to agree with the repo's one overdue predicate on everything except the
    /// cancelled case it deliberately drops, or the sidebar starts telling a different story from
    /// the red on the task rows.
    @Test func theTallyAgreesWithTheOneOverduePredicate() {
        let todayKey = "2026-08-16"

        for key in ["", "2026-08-15", "2026-08-16", "2026-08-17"] {
            for status in [TaskStatus.todo, .inProgress, .done] {
                let single = task(due: key, status: status)
                let expected = single.isOverdue(todayKey: todayKey) ? 1 : 0
                #expect(CadenceSidebarLayout.overdueTaskCount(from: [single], todayKey: todayKey) == expected)
            }
        }
    }
}

#if os(macOS)

/// The bridge between the shared layout and the macOS preference that customises it.
@MainActor
struct SidebarStaticDestinationBridgeTests {
    /// `CadenceFeatureDestination.sidebarStaticDestination` resolves by raw value, which is what
    /// carries the user's stored colour, order, and visibility across. A rename on either side
    /// would silently turn every customisation into a default.
    @Test func theTwoEnumsShareRawValues() {
        for destination in SidebarStaticDestination.allCases {
            #expect(destination.feature.rawValue == destination.rawValue)
            #expect(destination.feature.sidebarStaticDestination == destination)
        }
    }

    @Test func onlyTheCustomisableDestinationsResolveToAStaticOne() {
        let customisable = Set(SidebarStaticDestination.allCases.map(\.feature))

        for destination in CadenceFeatureDestination.allCases {
            #expect((destination.sidebarStaticDestination != nil) == customisable.contains(destination))
        }
    }

    /// Settings → Sidebar offers a visibility toggle and a colour picker for every
    /// `SidebarStaticDestination`. If one of them has no row in the layout, both of those controls
    /// silently do nothing — which is exactly what happened when Inbox was dropped from the
    /// primary group. So the set of customisable rows the sidebar does not render must be **empty**.
    @Test func everyRowSettingsLetsYouCustomiseIsActuallyRendered() {
        let customisable = Set(SidebarStaticDestination.allCases.map(\.feature))
        let rendered = Set(CadenceSidebarLayout.navigationDestinations)

        #expect(customisable.subtracting(rendered).isEmpty)
    }

    /// Every row the sidebar draws must resolve to a selection, or it is a button that navigates
    /// nowhere.
    @Test func everyNavRowResolvesToASelection() {
        for destination in CadenceSidebarLayout.navigationDestinations {
            #expect(destination.macSidebarItem != nil, "\(destination.title) has a row but no page")
        }

        #expect(CadenceFeatureDestination.lists.macSidebarItem == nil)
        #expect(CadenceFeatureDestination.search.macSidebarItem == nil)
    }
}

#endif
