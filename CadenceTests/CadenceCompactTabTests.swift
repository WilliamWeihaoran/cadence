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
    /// nor listed somewhere that pushes it has no door at all once the Home grid is gone.
    ///
    /// **There are two such lists since T-2072**, not one. The Tasks tab stopped being a root for
    /// its three task surfaces when its switcher became an index, so Today, Tasks and Inbox are
    /// pushes now — reached from `CadenceCompactTab.tasksIndexDestinations`, exactly as Goals is
    /// reached from `compactMoreSections`. Asserting against More alone would now fail for three
    /// destinations that are perfectly reachable, and — the half that matters — asserting against
    /// neither would let a fourth go dark unnoticed.
    @Test func everyDestinationIsEitherATabRootOrReachableFromAnIndex() {
        let moreRows = Set(CadenceFeatureDestination.compactMoreSections.flatMap(\.destinations))
        let tasksRows = Set(CadenceCompactTab.tasksIndexDestinations())
        let indexed = moreRows.union(tasksRows)

        #expect(moreRows.isDisjoint(with: tasksRows), "a destination is listed by two indexes")

        for destination in CadenceFeatureDestination.allCases {
            if destination.isCompactTabRoot {
                #expect(
                    indexed.contains(destination) == false,
                    "\(destination.title) is both a tab root and an index row — two doors to one room"
                )
            } else {
                #expect(
                    indexed.contains(destination),
                    "\(destination.title) is not a tab root and no index lists it: nothing can reach it"
                )
            }
        }

        #expect(moreRows == Set(CadenceCompactTab.more.destinations))
        #expect(tasksRows == Set(CadenceCompactTab.tasks.destinations))
    }

    /// **The index is the sidebar's rows, filtered — not a fourth list of task surfaces** (T-2072).
    ///
    /// The order and the hidden set are the synced `SidebarLayoutPreference` ones (T-1274), so a
    /// row hidden on the Mac is hidden on the phone's index too. Inbox is the single exception and
    /// it is a derived one: `CadenceSidebarLayout` deliberately gives Inbox no row of its own —
    /// `navRow(for: .inbox)` is `.allTasks` — so the index appends it to the Tasks row it belongs
    /// to and hides it with that row rather than inventing a second rule.
    @Test func theTasksIndexIsTheSidebarsOwnRowsWithInboxUnderTasks() {
        #expect(CadenceCompactTab.tasksIndexDestinations() == [.today, .allTasks, .inbox])

        // The user's order moves Today and Tasks; Inbox travels with the row that opens it.
        #expect(
            CadenceCompactTab.tasksIndexDestinations(storedOrder: [.allTasks, .today])
                == [.allTasks, .inbox, .today]
        )

        // Hiding Today leaves the other two; hiding Tasks takes Inbox with it, because the
        // sidebar's rule is that Inbox *is* one of the Tasks row's two views.
        #expect(CadenceCompactTab.tasksIndexDestinations(hidden: [.today]) == [.allTasks, .inbox])
        #expect(CadenceCompactTab.tasksIndexDestinations(hidden: [.allTasks]) == [.today])
        #expect(CadenceCompactTab.tasksIndexDestinations(hidden: [.today, .allTasks]).isEmpty)

        // Nothing another tab owns can be dragged into this index by reordering the sidebar.
        let everythingReordered = CadenceCompactTab.tasksIndexDestinations(
            storedOrder: [.calendar, .notes, .goals, .habits, .allTasks, .today]
        )
        #expect(everythingReordered.allSatisfy { $0.compactTab == .tasks })
        #expect(everythingReordered == [.allTasks, .inbox, .today])
    }

    /// The three slices and the three destinations are the same three, however they are drawn —
    /// a segmented control until T-2072, rows in the tab's index since.
    @Test func theTasksTabOwnsExactlyTheThreeSlices() {
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

        // Calendar and Notes are the whole of that set now. Stated as a literal rather than
        // derived, because "which tabs show their destination without a push" is precisely what
        // T-2072 changed and precisely what a widget tap depends on.
        #expect(
            CadenceFeatureDestination.allCases.filter(\.isCompactTabRoot) == [.calendar, .notes]
        )
    }

    @Test func aMoreDestinationRoutesToMoreWithItselfPushed() {
        for destination in CadenceCompactTab.more.destinations {
            let route = destination.compactRoute
            #expect(route.tab == .more)
            #expect(route.tasksSection == nil)
            #expect(route.pushedDestination == destination)
        }
    }

    /// **The three task destinations are pushes now, and the push is the whole of T-2072's
    /// routing.** They used to select a segment and stop — the tab's root *was* the screen — so a
    /// Today widget tap could land on the Tasks tab and be finished. The root is an index of rows
    /// now, so a route that asked for no push would open that index and claim to have arrived at
    /// Today. The slice is still recorded: it is what a widening size class reads when the stack
    /// is empty (`CadenceShellNavigationBridge`).
    @Test func theThreeTaskDestinationsPushOntoTheTasksIndex() {
        #expect(
            CadenceFeatureDestination.today.compactRoute
                == CadenceCompactRoute(tab: .tasks, tasksSection: .today, pushedDestination: .today)
        )
        #expect(
            CadenceFeatureDestination.allTasks.compactRoute
                == CadenceCompactRoute(tab: .tasks, tasksSection: .all, pushedDestination: .allTasks)
        )
        #expect(
            CadenceFeatureDestination.inbox.compactRoute
                == CadenceCompactRoute(tab: .tasks, tasksSection: .inbox, pushedDestination: .inbox)
        )
    }

    // MARK: - Deep links and widgets

    @Test func everyDeepLinkResolvesToATab() {
        let taskID = UUID()

        #expect(CadenceDeepLink.today.featureDestination == .today)
        #expect(CadenceDeepLink.task(taskID).featureDestination == .today)
        #expect(CadenceDeepLink.habits.featureDestination == .habits)
        #expect(CadenceDeepLink.goals.featureDestination == .goals)
        #expect(CadenceDeepLink.calendar(dateKey: nil).featureDestination == .calendar)

        #expect(CadenceDeepLink.today.compactRoute.tab == .tasks)
        #expect(CadenceDeepLink.task(taskID).compactRoute.tasksSection == .today)
        #expect(CadenceDeepLink.calendar(dateKey: nil).compactRoute.tab == .calendar)
        #expect(CadenceDeepLink.calendar(dateKey: nil).compactRoute.pushedDestination == nil)
        #expect(CadenceDeepLink.habits.compactRoute.tab == .more)
        #expect(CadenceDeepLink.habits.compactRoute.pushedDestination == .habits)
        #expect(CadenceDeepLink.goals.compactRoute.pushedDestination == .goals)
    }

    /// The widget URLs are the deep links, so this pins that a widget tap cannot land on a tab the
    /// link did not name.
    @Test func widgetURLsRouteToTheTabTheirFeatureLivesOn() throws {
        let urls: [(URL, CadenceCompactTab)] = [
            (CadenceDeepLink.today.url, .tasks),
            (CadenceDeepLink.calendar(dateKey: nil).url, .calendar),
            (CadenceDeepLink.habits.url, .more),
            (CadenceDeepLink.goals.url, .more)
        ]

        for (url, expected) in urls {
            let link = try #require(CadenceDeepLink(url: url))
            #expect(link.compactRoute.tab == expected)
        }
    }

    // MARK: - The desktop scope, against these segments

    /// **The three slices outlived the control that drew them.** They were a segmented switcher in
    /// the Tasks tab's header until T-2072 and are rows in that tab's index now; what has not
    /// changed is that `ios.compact.tasksSection` persists these raw values, so a rename here
    /// silently resets every phone to Today.
    ///
    /// Spelled as literal raw values rather than derived from the enum: a test that reads
    /// `allCases` agrees with any rename by construction, which is the failure mode this is for.
    /// Order and storage are pinned separately on purpose, because only one of them is allowed to
    /// move. The segments were reordered at the user's request from `today, all, inbox` to
    /// `today, inbox, all` — a narrowing, with the widest slice last — and this test failed on that
    /// change, which is what it is for. What must **not** move is the raw values: they are
    /// persisted as `ios.compact.tasksSection`, so reordering the cases has to be presentation
    /// only. A change that alters the second assertion is a change that silently resets which
    /// slice every existing install widens into.
    @Test func theThreeTasksSegmentsAndTheirStoredSpellingsAreFixed() {
        #expect(CadenceTasksSection.allCases == [.today, .inbox, .all])
        #expect(Set(CadenceTasksSection.allCases.map(\.rawValue)) == ["today", "all", "inbox"])
        #expect(CadenceTasksSection.allCases.map(\.title) == ["Today", "Inbox", "All"])
        #expect(CadenceTasksSection.allCases.map(\.destination) == [.today, .inbox, .allTasks])
        #expect(CadenceTasksSection.defaultSection == .today)

        // The spelling each case stores, independent of where it sits in the control.
        #expect(CadenceTasksSection.today.rawValue == "today")
        #expect(CadenceTasksSection.inbox.rawValue == "inbox")
        #expect(CadenceTasksSection.all.rawValue == "all")
        #expect(CadenceTasksSection.resolved("all") == .all)
        #expect(CadenceTasksSection.resolved("inbox") == .inbox)
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
    /// phone's index gives each a row of its own, and widgets deep-link to them.
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

/// **T-169: the More tab is a grouped list, and the grouping is the design decision.**
///
/// The routing tests above flatten `compactMoreSections` before they look at it, so every one of
/// them passes just as happily against a single section holding all six rows — which is precisely
/// the "flat run that describes the tab bar's overflow rather than a design" the ticket was filed
/// about. Nothing pinned the grouping itself. These do.
struct CadenceMoreTabGroupingTests {
    /// Three groups, in order, with their eyebrows and their contents.
    ///
    /// Spelled as literals rather than derived from the sections: a test that reads
    /// `compactMoreSections` and asserts something about what it read agrees with any regrouping by
    /// construction, which is the failure mode this is for. The shape is
    /// `CadenceMobileSettingsLayout.groups`' — the precedent the ticket named — and the contents are
    /// not: what a phone does *with* the app (Focus, Goals, Habits), what it organises the app
    /// *with* (Lists), and what it does *to* the app (Search, Settings). Search sits beside Settings
    /// rather than beside the task surfaces because from here it searches everything, not tasks.
    @Test func theMoreTabIsThreeNamedGroupsRatherThanOneFlatRun() {
        let sections = CadenceFeatureDestination.compactMoreSections

        #expect(sections.count == 3)
        #expect(sections.map(\.kind) == [.progress, .organize, .workspace])
        #expect(sections.map(\.title) == ["Progress", "Organize", "Workspace"])
        #expect(
            sections.map(\.destinations) == [
                [.focus, .goals, .habits],
                [.lists],
                [.search, .settings]
            ]
        )
    }

    /// The invariants a regrouping has to keep, stated so that moving a row is cheap and losing or
    /// duplicating one is a failure.
    ///
    /// `Organize` holding a single row is deliberate and not a smell — Settings' `About` sits in a
    /// group of one for the same reason — so this asserts groups are non-*empty*, not that they
    /// hold more than one.
    @Test func everyMoreRowIsFiledUnderExactlyOneNonEmptyGroup() {
        let sections = CadenceFeatureDestination.compactMoreSections
        let filed = sections.flatMap(\.destinations)

        #expect(Set(filed).count == filed.count, "a More row is filed under two groups")
        #expect(Set(filed) == Set(CadenceCompactTab.more.destinations))

        for section in sections {
            #expect(!section.destinations.isEmpty, "\(section.title) is an eyebrow over nothing")
        }

        // `CadenceFeatureSection` is `Identifiable` by its `kind`, so two sections of one kind
        // would silently collapse into a single row of the `ForEach` that draws them rather than
        // drawing twice.
        #expect(Set(sections.map(\.id)).count == sections.count)
    }

    /// Nothing that has a tab of its own may also appear as a More row, in either direction. The
    /// flattened version of this is already above; this one is per-group, so a row copied into a
    /// second group cannot hide behind the union.
    @Test func noGroupSmugglesInATabRoot() {
        for section in CadenceFeatureDestination.compactMoreSections {
            for destination in section.destinations {
                #expect(
                    destination.compactTab == .more,
                    "\(destination.title) is under \(section.title) but its tab is \(destination.compactTab.title)"
                )
                #expect(!destination.isCompactTabRoot)
            }
        }
    }
}

/// **The call site.** The grouping above is a value in `Shared/`; the view that draws it is in
/// `Cadence/iOS/`, inside `#if os(iOS)` and therefore invisible to this macOS-built target.
///
/// That gap is the whole of T-161: a correct grouped value read by a view that flattens it back
/// into one run of rows leaves every assertion above green and ships the bug. So this asserts the
/// three structural facts that *are* the grouping — an outer loop over the sections, one eyebrow
/// per section, an inner loop over that section's own destinations — positively rather than banning
/// a needle like `flatMap`, which correct code could legitimately grow.
struct CadenceMoreTabGroupingSurfaceTests {
    @Test func theMoreTabDrawsOneEyebrowAndOneRowRunPerGroup() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSMoreTabView.swift"))

        #expect(
            source.contains("ForEach(CadenceFeatureDestination.compactMoreSections)"),
            "the More tab stopped iterating the shared grouping"
        )
        #expect(
            source.contains("SectionEyebrowLabel(text: section.title)"),
            "the More tab's groups lost the eyebrow that names them"
        )
        #expect(
            source.contains("ForEach(section.destinations)"),
            "the More tab draws its rows from something other than the group it is inside"
        )
    }

    /// The guard that stops all of the above going vacuous. Every `contains` assertion in a scan
    /// that silently read nothing is a `contains` against the empty string, and a path that
    /// resolves through a symlinked prefix on an isolated build tree produces exactly that.
    @Test func theMoreTabScanReadsRealSourceAndReallyStripsComments() throws {
        let raw = try sourceFile("Cadence/iOS/iOSMoreTabView.swift")
        let stripped = try strippingComments(raw)

        #expect(raw.count > 1_000, "the More tab scan read nothing")
        #expect(raw.contains("/// "), "the fixture has no doc comments, so stripping proves nothing")
        #expect(!stripped.contains("/// "), "strippingComments did not strip")
        #expect(stripped.contains("struct iOSMoreTabView"), "the scan is reading some other file")
    }
}

// MARK: - Source-reading helpers

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
