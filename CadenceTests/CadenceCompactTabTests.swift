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
