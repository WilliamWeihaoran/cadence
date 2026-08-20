import Foundation
import Testing
@testable import Cadence

/// The iPhone tab shell's routing table.
///
/// The shell replaced a single `NavigationStack` rooted at a grid that listed every destination, so
/// "can you still get there" stopped being obvious by construction and became a mapping that has to
/// be right. These tests are the guard: every `CadenceFeatureDestination` must answer which tab owns
/// it, every deep link must resolve to a tab rather than to a bare push, and a link to a tab's own
/// root must not ask for a push on top of it.
@MainActor
struct CadenceCompactTabTests {
    // MARK: - Coverage

    @Test func everyDestinationIsOwnedByExactlyOneTab() {
        let owned = CadenceCompactTab.allCases.flatMap(\.destinations)

        #expect(Set(owned).count == owned.count, "a destination is listed under two tabs")
        #expect(Set(owned) == Set(CadenceFeatureDestination.allCases))

        for destination in CadenceFeatureDestination.allCases {
            #expect(
                destination.compactTab.destinations.contains(destination),
                "\(destination.title) claims a tab that does not list it"
            )
        }
    }

    /// The one that would have caught a screen going dark: a destination that is neither a tab root
    /// nor listed in More has no door at all once the Home grid is gone.
    @Test func everyDestinationIsEitherATabRootOrReachableFromMore() {
        let moreRows = Set(CadenceFeatureDestination.compactMoreSections.flatMap(\.destinations))

        for destination in CadenceFeatureDestination.allCases {
            if destination.isCompactTabRoot {
                #expect(
                    moreRows.contains(destination) == false,
                    "\(destination.title) is both a tab root and a More row — two doors to one room"
                )
            } else {
                #expect(
                    moreRows.contains(destination),
                    "\(destination.title) is not a tab root and is not in More: nothing can reach it"
                )
            }
        }

        #expect(moreRows == Set(CadenceCompactTab.more.destinations))
    }

    @Test func theTasksTabOwnsExactlyTheThreeSegments() {
        #expect(
            Set(CadenceTasksSection.allCases.map(\.destination))
                == Set(CadenceCompactTab.tasks.destinations)
        )

        for section in CadenceTasksSection.allCases {
            #expect(section.destination.compactTasksSection == section)
        }

        for destination in CadenceFeatureDestination.allCases {
            let hasSection = destination.compactTasksSection != nil
            #expect(hasSection == (destination.compactTab == .tasks))
        }
    }

    // MARK: - Routing

    @Test func aTabRootRoutesWithoutAPush() {
        for destination in CadenceFeatureDestination.allCases where destination.isCompactTabRoot {
            let route = destination.compactRoute
            #expect(route.tab == destination.compactTab)
            #expect(route.pushedDestination == nil, "\(destination.title) would stack on its own tab")
        }
    }

    @Test func aMoreDestinationRoutesToMoreWithItselfPushed() {
        for destination in CadenceCompactTab.more.destinations {
            let route = destination.compactRoute
            #expect(route.tab == .more)
            #expect(route.tasksSection == nil)
            #expect(route.pushedDestination == destination)
        }
    }

    @Test func theThreeTaskDestinationsSelectTheirSegment() {
        #expect(
            CadenceFeatureDestination.today.compactRoute
                == CadenceCompactRoute(tab: .tasks, tasksSection: .today, pushedDestination: nil)
        )
        #expect(
            CadenceFeatureDestination.allTasks.compactRoute
                == CadenceCompactRoute(tab: .tasks, tasksSection: .all, pushedDestination: nil)
        )
        #expect(
            CadenceFeatureDestination.inbox.compactRoute
                == CadenceCompactRoute(tab: .tasks, tasksSection: .inbox, pushedDestination: nil)
        )
    }

    // MARK: - Deep links and widgets

    @Test func everyDeepLinkResolvesToATab() {
        let taskID = UUID()

        #expect(CadenceDeepLink.today.featureDestination == .today)
        #expect(CadenceDeepLink.task(taskID).featureDestination == .today)
        #expect(CadenceDeepLink.habits.featureDestination == .habits)
        #expect(CadenceDeepLink.goals.featureDestination == .goals)
        #expect(CadenceDeepLink.calendar.featureDestination == .calendar)

        #expect(CadenceDeepLink.today.compactRoute.tab == .tasks)
        #expect(CadenceDeepLink.task(taskID).compactRoute.tasksSection == .today)
        #expect(CadenceDeepLink.calendar.compactRoute.tab == .calendar)
        #expect(CadenceDeepLink.calendar.compactRoute.pushedDestination == nil)
        #expect(CadenceDeepLink.habits.compactRoute.tab == .more)
        #expect(CadenceDeepLink.habits.compactRoute.pushedDestination == .habits)
        #expect(CadenceDeepLink.goals.compactRoute.pushedDestination == .goals)
    }

    /// The widget URLs are the deep links, so this pins that a widget tap cannot land on a tab the
    /// link did not name.
    @Test func widgetURLsRouteToTheTabTheirFeatureLivesOn() throws {
        let urls: [(URL, CadenceCompactTab)] = [
            (CadenceDeepLink.today.url, .tasks),
            (CadenceDeepLink.calendar.url, .calendar),
            (CadenceDeepLink.habits.url, .more),
            (CadenceDeepLink.goals.url, .more)
        ]

        for (url, expected) in urls {
            let link = try #require(CadenceDeepLink(url: url))
            #expect(link.compactRoute.tab == expected)
        }
    }

    // MARK: - The desktop scope, against these segments

    /// **The iPhone is out of scope for the All Tasks / Inbox merge and must stay that way.** Its
    /// Tasks tab has been this design in tab-bar form since it shipped — three segments, Today
    /// among them — and `ios.compact.tasksSection` persists these raw values, so a rename here
    /// silently resets every phone to Today.
    ///
    /// Spelled as literal raw values rather than derived from the enum: a test that reads
    /// `allCases` agrees with any rename by construction, which is the failure mode this is for.
    @Test func theThreeTasksSegmentsAndTheirStoredSpellingsAreFixed() {
        #expect(CadenceTasksSection.allCases == [.today, .all, .inbox])
        #expect(CadenceTasksSection.allCases.map(\.rawValue) == ["today", "all", "inbox"])
        #expect(CadenceTasksSection.allCases.map(\.title) == ["Today", "All", "Inbox"])
        #expect(CadenceTasksSection.allCases.map(\.destination) == [.today, .allTasks, .inbox])
        #expect(CadenceTasksSection.defaultSection == .today)
    }

    /// The desktop and iPad **Tasks** destination hosts two of those three views. It borrows its
    /// labels rather than writing a second set, so the phone cannot end up saying "All" while the
    /// Mac says "All Tasks" in the same control — and `.today` is deliberately absent, because
    /// Today is a three-pane dashboard rather than a filter over the same rows.
    @Test func theDesktopScopeIsTwoOfTheThreeSegmentsAndBorrowsTheirWords() {
        #expect(CadenceTasksPageScope.allCases == [.all, .inbox])
        #expect(CadenceTasksPageScope.allCases.map(\.section) == [.all, .inbox])
        #expect(CadenceTasksPageScope.allCases.map(\.destination) == [.allTasks, .inbox])

        for scope in CadenceTasksPageScope.allCases {
            #expect(scope.title == scope.section.title)
            #expect(scope.destination == scope.section.destination)
            #expect(scope.pageTitle == scope.destination.title)
            #expect(CadenceTasksPageScope(destination: scope.destination) == scope)
        }

        #expect(CadenceTasksPageScope(destination: .today) == nil)
        #expect(CadenceTasksPageScope.allCases.map(\.pageTitle) == ["All Tasks", "Inbox"])
    }

    /// Both destinations still exist and still route on their own, which is the whole reason the
    /// merge stayed a sidebar-and-page change: the command palette names them separately, the
    /// phone's segments select them separately, and widgets deep-link to them.
    @Test func theMergeDidNotCollapseTheTwoDestinations() {
        #expect(CadenceFeatureDestination.allCases.contains(.allTasks))
        #expect(CadenceFeatureDestination.allCases.contains(.inbox))
        #expect(CadenceFeatureDestination.allTasks.compactTasksSection == .all)
        #expect(CadenceFeatureDestination.inbox.compactTasksSection == .inbox)
        #expect(CadenceFeatureDestination.inbox.compactTab == .tasks)
    }

    /// **The regression the merge could most easily have shipped.**
    ///
    /// Inbox showed Apple Reminders inline and nothing else in the app does. Folding it into the
    /// Tasks page is exactly the kind of change that drops a section by omission, and it would look
    /// like nothing at all until someone with reminders opened the Inbox. So the gate is a function
    /// rather than a `guard` in a view body, and this is what fails if it goes.
    @Test func theRemindersStripBelongsToInboxAndOnlyInbox() {
        for isAuthorized in [true, false] {
            for isLoading in [true, false] {
                for hasReminders in [true, false] {
                    #expect(
                        CadenceTasksPageScope.showsRemindersStrip(
                            scope: .all,
                            isAuthorized: isAuthorized,
                            isLoading: isLoading,
                            hasReminders: hasReminders
                        ) == false,
                        "All Tasks grew an Apple Reminders strip"
                    )
                }
            }
        }

        // Reminders to show.
        #expect(CadenceTasksPageScope.showsRemindersStrip(scope: .inbox, isAuthorized: true, isLoading: false, hasReminders: true))
        // Nothing to show, but something to say: the Connect row, and the loading row.
        #expect(CadenceTasksPageScope.showsRemindersStrip(scope: .inbox, isAuthorized: false, isLoading: false, hasReminders: false))
        #expect(CadenceTasksPageScope.showsRemindersStrip(scope: .inbox, isAuthorized: true, isLoading: true, hasReminders: false))
        // Authorized, settled, and empty: the user has no active reminders, so the strip is a
        // heading over nothing.
        #expect(!CadenceTasksPageScope.showsRemindersStrip(scope: .inbox, isAuthorized: true, isLoading: false, hasReminders: false))
    }

    @Test func anUnknownStoredScopeFallsBackRatherThanLeavingNoView() {
        #expect(CadenceTasksPageScope.resolved("inbox") == .inbox)
        #expect(CadenceTasksPageScope.resolved("all") == .all)
        #expect(CadenceTasksPageScope.resolved("") == CadenceTasksPageScope.defaultScope)
        #expect(CadenceTasksPageScope.resolved("allTasks") == CadenceTasksPageScope.defaultScope)
        #expect(CadenceTasksPageScope.defaultScope == .all)
    }

    // MARK: - Persistence

    @Test func persistedTabAndSectionFallBackRatherThanLeavingNoSelection() {
        #expect(CadenceCompactTab.resolved("calendar") == .calendar)
        #expect(CadenceCompactTab.resolved("") == .tasks)
        #expect(CadenceCompactTab.resolved("home") == .tasks)
        #expect(CadenceCompactTab.resolved(CadenceCompactTab.more.rawValue) == .more)

        #expect(CadenceTasksSection.resolved("inbox") == .inbox)
        #expect(CadenceTasksSection.resolved("") == .today)
        #expect(CadenceTasksSection.resolved("allTasks") == .today)
    }
}
