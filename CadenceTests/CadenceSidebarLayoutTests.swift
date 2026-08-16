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

    @Test func theTwoGroupsAreTheChosenEightRowsInOrder() {
        #expect(CadenceSidebarLayout.primaryDestinations == [.today, .allTasks, .calendar, .notes, .inbox])
        #expect(CadenceSidebarLayout.secondaryDestinations == [.goals, .habits, .focus, .settings])
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
    /// Lists is the scrolling region, Search is the header button, Inbox has no row at all in this
    /// layout. Pinned so that adding a destination and forgetting to place it is a test failure
    /// rather than a screen nobody can reach.
    @Test func theDestinationsWithoutANavRowAreExactlyTheKnownThree() {
        let missing = Set(CadenceFeatureDestination.allCases)
            .subtracting(CadenceSidebarLayout.navigationDestinations)

        #expect(missing == [.lists, .search])
    }

    // MARK: - Ordering

    /// The rows Settings → Sidebar offers a handle for, on macOS.
    private let customisable: Set<CadenceFeatureDestination> = [
        .today, .allTasks, .focus, .inbox, .calendar, .goals, .habits
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
        #expect(resolved(.primary, storedOrder: [.calendar]) == [.calendar, .today, .allTasks, .notes, .inbox])
    }

    /// A user who reorders in Settings must not lose that. The stored order sorts *within* a
    /// group: Calendar can move above Today, and it still cannot cross the lists into the other
    /// group.
    @Test func theStoredOrderSortsWithinAGroup() {
        let reordered: [CadenceFeatureDestination] = [
            .calendar, .today, .allTasks, .habits, .goals, .focus, .inbox
        ]

        #expect(resolved(.primary, storedOrder: reordered) == [.calendar, .today, .allTasks, .notes, .inbox])
        #expect(resolved(.secondary, storedOrder: reordered) == [.habits, .goals, .focus, .settings])
    }

    /// Notes and Settings have no Settings → Sidebar handle, so they hold their declared slot
    /// instead of being swept to the front or the back of whatever the movable rows do.
    @Test func theRowsSettingsCannotMoveKeepTheirSlot() {
        let reversed: [CadenceFeatureDestination] = [
            .habits, .goals, .calendar, .inbox, .focus, .allTasks, .today
        ]

        // Notes sits at index 3 of the primary group and is not last — Inbox follows it. The
        // assertion is that a fixed row holds its *declared slot*, not that it lands at an end.
        #expect(resolved(.primary, storedOrder: reversed)[3] == .notes)
        #expect(resolved(.secondary, storedOrder: reversed).last == .settings)
    }

    // MARK: - Visibility

    @Test func hidingARowRemovesItAndLeavesTheRestInOrder() {
        #expect(resolved(.primary, hidden: [.allTasks]) == [.today, .calendar, .notes, .inbox])
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

    /// Inbox is the one row Settings → Sidebar still offers a colour and a visibility toggle for
    /// while the sidebar renders no row for it — its toggle is inert and its colour override is
    /// stranded. Pinned deliberately: if Inbox comes back to the column, or if its Settings entry
    /// goes away, this is the test that should be updated with it.
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
