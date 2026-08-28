import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceDeepLinkTests {
    @Test func deepLinkParsesTodayAndTaskURLs() throws {
        let taskID = UUID()
        let todayURL = try #require(URL(string: "cadence://today"))
        let taskURL = try #require(URL(string: "CADENCE://task/\(taskID.uuidString)"))

        let todayLink = try #require(CadenceDeepLink(url: todayURL))
        let taskLink = try #require(CadenceDeepLink(url: taskURL))

        #expect(todayLink == .today)
        #expect(taskLink == .task(taskID))
    }

    @Test func deepLinkRejectsWrongSchemeUnknownRoutesAndBadTaskIDs() throws {
        #expect(CadenceDeepLink(url: try #require(URL(string: "https://today"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://unknown"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://task/not-a-uuid"))) == nil)
    }

    @Test func deepLinkBuildsCanonicalURLs() {
        let taskID = UUID(uuidString: "B8C8927A-6AB3-4B25-8F8A-EA4E849C770B")!

        #expect(CadenceDeepLink.today.url.absoluteString == "cadence://today")
        #expect(CadenceDeepLink.task(taskID).url.absoluteString == "cadence://task/\(taskID.uuidString)")
    }

    @Test func managerTracksPendingTaskAndClearsOnlyMatchingTask() throws {
        let manager = CadenceDeepLinkManager.shared
        let taskID = UUID()
        let otherTaskID = UUID()

        manager.route = nil
        manager.pendingTaskID = nil

        manager.handle(try #require(URL(string: "cadence://task/\(taskID.uuidString)")))
        #expect(manager.route?.deepLink == .task(taskID))
        #expect(manager.pendingTaskID == taskID)

        manager.clearPendingTask(otherTaskID)
        #expect(manager.pendingTaskID == taskID)

        manager.clearPendingTask(taskID)
        #expect(manager.pendingTaskID == nil)

        manager.handle(try #require(URL(string: "cadence://today")))
        #expect(manager.route?.deepLink == .today)
        #expect(manager.pendingTaskID == nil)
    }

    // MARK: - T-368: a task link is resolved against the store, not applied blind

    /// Builds a context and returns it with today's key, so every test below asks the same
    /// question of the same day.
    private func makeStore() throws -> (ModelContext, String) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (ModelContext(container), DateFormatters.todayKey())
    }

    private func resetManager() -> CadenceDeepLinkManager {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        manager.pendingTaskID = nil
        return manager
    }

    /// The link that motivated T-368: an id for a row that is not there any more. It used to arm
    /// `pendingTaskID` and leave it armed forever, so the next screen that happened to draw that
    /// row opened a task the user had not asked for.
    @Test func taskDeepLinkForMissingTaskDisarmsPendingIDAndKeepsToday() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()
        let missingID = UUID()

        manager.handle(try #require(URL(string: "cadence://task/\(missingID.uuidString)")))
        #expect(manager.pendingTaskID == missingID)

        let destination = manager.resolvedDestination(
            for: .task(missingID),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .today)
        #expect(manager.pendingTaskID == nil)

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: missingID,
            task: nil,
            todayKey: todayKey
        )
        #expect(resolution.outcome == .missing)
        #expect(resolution.destination == .today)
        #expect(resolution.pendingTaskID == nil)
    }

    /// A widget link for work that was finished elsewhere. Today drops done tasks, so the row that
    /// would disarm the id never renders: the link routes to All Tasks and disarms here instead.
    @Test func completedTaskDeepLinkRoutesToAllTasksAndDoesNotStayArmed() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let task = AppTask(title: "Finished this morning")
        task.scheduledDate = todayKey
        task.status = .done
        task.completedAt = Date()
        modelContext.insert(task)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(task.id.uuidString)")))
        #expect(manager.pendingTaskID == task.id)

        let destination = manager.resolvedDestination(
            for: .task(task.id),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .allTasks)
        #expect(manager.pendingTaskID == nil)
        #expect(CadenceDeepLinkResolutionSupport.todayShows(task, todayKey: todayKey) == false)
    }

    /// Cancelled work takes the same route as done work, and a task dated for another day takes it
    /// too — the gate is Today's whole scope predicate, not an `isDone` check.
    @Test func cancelledAndOffDayTaskDeepLinksAlsoRouteToAllTasksDisarmed() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let cancelled = AppTask(title: "Dropped it")
        cancelled.scheduledDate = todayKey
        cancelled.status = .cancelled
        let laterTask = AppTask(title: "Next week")
        laterTask.scheduledDate = "9999-01-01"
        modelContext.insert(cancelled)
        modelContext.insert(laterTask)
        try modelContext.save()

        for task in [cancelled, laterTask] {
            manager.pendingTaskID = task.id
            let destination = manager.resolvedDestination(
                for: .task(task.id),
                modelContext: modelContext,
                todayKey: todayKey
            )
            #expect(destination == .allTasks)
            #expect(manager.pendingTaskID == nil)
        }

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: laterTask.id,
            task: laterTask,
            todayKey: todayKey
        )
        #expect(resolution.outcome == .outsideToday)
        #expect(resolution.pendingTaskID == nil)
    }

    /// The case that must keep working: a live task Today lists. Resolution routes to Today, the
    /// id stays armed for the row, and the row's `clearPendingTask` still disarms it.
    @Test func liveTodayTaskDeepLinkStaysArmedForItsRowAndTheRowStillClearsIt() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let task = AppTask(title: "Due today")
        task.dueDate = todayKey
        modelContext.insert(task)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(task.id.uuidString)")))

        let destination = manager.resolvedDestination(
            for: .task(task.id),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .today)
        #expect(manager.pendingTaskID == task.id)
        #expect(CadenceDeepLinkResolutionSupport.todayShows(task, todayKey: todayKey))

        // The row-level clear, unchanged and still the thing that ends a successful link.
        manager.clearPendingTask(task.id)
        #expect(manager.pendingTaskID == nil)
    }

    /// Resolution never disarms an id it does not own. A second link landing between `handle(_:)`
    /// and the root's resolve pass owns `pendingTaskID`; clearing it there would be this same bug
    /// pointed the other way.
    @Test func resolvingAStaleTaskLinkLeavesANewerPendingTaskAlone() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()
        let newerID = UUID()

        manager.pendingTaskID = newerID
        let destination = manager.resolvedDestination(
            for: .task(UUID()),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .today)
        #expect(manager.pendingTaskID == newerID)
        manager.pendingTaskID = nil
    }

    /// Singleton routes are untouched by resolution and never read the store.
    @Test func nonTaskDeepLinksResolveToTheirOwnDestinations() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        for (link, expected) in [
            (CadenceDeepLink.today, CadenceFeatureDestination.today),
            (.habits, .habits),
            (.goals, .goals),
            (.calendar(dateKey: nil), .calendar)
        ] {
            #expect(
                manager.resolvedDestination(for: link, modelContext: modelContext, todayKey: todayKey) == expected
            )
        }
    }
}

// MARK: - T-370(b) / T-375: the URL grammar, the reveal, and the root wiring

@MainActor
struct CadenceDeepLinkGrammarAndRevealTests {
    private func makeStore() throws -> (ModelContext, String) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (ModelContext(container), DateFormatters.todayKey())
    }

    private func resetManager() -> CadenceDeepLinkManager {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        manager.pendingTaskID = nil
        manager.revealedCompletedTaskID = nil
        return manager
    }

    // MARK: T-370(b) — lenient, the same way T-369 was lenient

    /// **The grammar decision, pinned.** The parser switched on `url.host` alone, which drew two
    /// arbitrary lines: `cadence:///today` puts the route in the *path* and so was rejected
    /// outright, while `cadence://today/junk` was accepted with the extra component ignored — the
    /// same slack granted in one shape and refused in the other.
    ///
    /// Lenient wins on T-369's own argument. That ticket chose to degrade a mangled
    /// `cadence://calendar/not-a-date` to the bare calendar link rather than reject it, because a
    /// URL naming a route the app has is a request to open that route and there is no error
    /// surface behind a deep link — a rejected link is a tap that does nothing. Rejecting
    /// `cadence:///today` is that decision made the other way for no reason.
    @Test func theParserAcceptsBothURLShapesAndIgnoresExtraSingletonComponents() throws {
        let taskID = UUID()

        // The authority-less shape, for every route.
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence:///today"))) == .today)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence:///habits"))) == .habits)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence:///goals"))) == .goals)
        #expect(
            CadenceDeepLink(url: try #require(URL(string: "cadence:///task/\(taskID.uuidString)")))
                == .task(taskID)
        )
        #expect(
            CadenceDeepLink(url: try #require(URL(string: "cadence:///calendar/2026-05-11")))
                == .calendar(dateKey: "2026-05-11")
        )

        // Extra components on a singleton route are ignored by *every* singleton, not by whichever
        // ones happened to have their payload in the path.
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://today/junk"))) == .today)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence:///goals/2026/extra"))) == .goals)

        // Case-insensitive on the route name only; a payload keeps its case.
        #expect(CadenceDeepLink(url: try #require(URL(string: "CADENCE:///TODAY"))) == .today)
    }

    /// Lenient about *shape*, not about a payload that is genuinely required. There is no bare
    /// "task" screen to degrade to, so a task link with no id or a broken id still fails — the
    /// same line T-369 drew when it kept `cadence://task/not-a-uuid` rejected while letting a
    /// mangled calendar date through.
    @Test func aMissingOrBrokenRequiredPayloadIsStillRejected() throws {
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://task"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence:///task"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://task/not-a-uuid"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://unknown"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence:///unknown/today"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "https://today"))) == nil)
    }

    /// Leniency is a property of what the app **accepts**. What it emits is unchanged, so the
    /// widgets keep round-tripping through the canonical form.
    @Test func leniencyDoesNotChangeWhatTheAppEmits() throws {
        let taskID = UUID()
        #expect(CadenceDeepLink.today.url.absoluteString == "cadence://today")
        #expect(CadenceDeepLink.habits.url.absoluteString == "cadence://habits")
        #expect(CadenceDeepLink.goals.url.absoluteString == "cadence://goals")
        #expect(CadenceDeepLink.task(taskID).url.absoluteString == "cadence://task/\(taskID.uuidString)")
        #expect(CadenceDeepLink.calendar(dateKey: nil).url.absoluteString == "cadence://calendar")
        #expect(
            CadenceDeepLink.calendar(dateKey: "2026-05-11").url.absoluteString
                == "cadence://calendar/2026-05-11"
        )

        // And the lenient shapes still round-trip back to the canonical one.
        let lenientURL = try #require(URL(string: "cadence:///today/extra"))
        let lenient = try #require(CadenceDeepLink(url: lenientURL))
        #expect(lenient.url.absoluteString == "cadence://today")
    }

    // MARK: T-375(a) — the reveal

    /// The product call: a link for work finished elsewhere **opens** All Tasks' collapsed
    /// Completed section, so the row the URL names is actually on the page it lands on.
    @Test func aFinishedTaskLinkAsksAllTasksToOpenItsCompletedSection() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let task = AppTask(title: "Finished last month")
        task.scheduledDate = todayKey
        task.status = .done
        task.completedAt = Date()
        modelContext.insert(task)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(task.id.uuidString)")))
        let destination = manager.resolvedDestination(
            for: .task(task.id),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .allTasks)
        #expect(manager.revealedCompletedTaskID == task.id)
        // The arm stays disarmed: T-368's invariant is untouched. See `TaskLinkResolution` for
        // why the reveal is not accompanied by a re-arm.
        #expect(manager.pendingTaskID == nil)

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: task.id,
            task: task,
            todayKey: todayKey
        )
        #expect(resolution.outcome == .outsideToday)
        #expect(resolution.revealedCompletedTaskID == task.id)
        #expect(resolution.pendingTaskID == nil)
    }

    /// Cancelled work takes the reveal too — the logbook predicate is `isFinishedTask`, which is
    /// done **or** cancelled, and is the same one the section is built from.
    @Test func cancelledWorkGetsTheRevealBecauseTheLogbookIsDoneOrCancelled() throws {
        let (_, todayKey) = try makeStore()
        let cancelled = AppTask(title: "Dropped it")
        cancelled.scheduledDate = todayKey
        cancelled.status = .cancelled

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: cancelled.id,
            task: cancelled,
            todayKey: todayKey
        )
        #expect(resolution.destination == .allTasks)
        #expect(resolution.revealedCompletedTaskID == cancelled.id)
    }

    /// An **open** task dated for another day also routes to All Tasks, and must not open the
    /// logbook: it is in that page's active list already, and expanding a section it has nothing
    /// to do with is a disclosure opening for no reason.
    @Test func anOpenTaskDatedForAnotherDayRoutesToAllTasksWithTheLogbookShut() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let later = AppTask(title: "Next week")
        later.scheduledDate = "9999-01-01"
        modelContext.insert(later)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(later.id.uuidString)")))
        #expect(manager.resolvedDestination(for: .task(later.id), modelContext: modelContext, todayKey: todayKey) == .allTasks)
        #expect(manager.revealedCompletedTaskID == nil)

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: later.id,
            task: later,
            todayKey: todayKey
        )
        #expect(resolution.outcome == .outsideToday)
        #expect(resolution.revealedCompletedTaskID == nil)
    }

    /// A live Today task and a missing one keep their T-368 answers, reveal included.
    @Test func aLiveTodayTaskAndAMissingTaskAskForNoReveal() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let live = AppTask(title: "Due today")
        live.dueDate = todayKey
        modelContext.insert(live)
        try modelContext.save()

        #expect(manager.resolvedDestination(for: .task(live.id), modelContext: modelContext, todayKey: todayKey) == .today)
        #expect(manager.revealedCompletedTaskID == nil)

        let missingID = UUID()
        manager.handle(try #require(URL(string: "cadence://task/\(missingID.uuidString)")))
        #expect(manager.resolvedDestination(for: .task(missingID), modelContext: modelContext, todayKey: todayKey) == .today)
        #expect(manager.revealedCompletedTaskID == nil)
    }

    /// The reveal's lifetime is the route's. A singleton link never reaches the resolver's task
    /// branch, so `handle(_:)` is what has to clear it — otherwise the previous link's logbook
    /// stays open on a page the new link has nothing to do with.
    @Test func anyNewLinkClearsThePreviousLinksReveal() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let task = AppTask(title: "Finished")
        task.scheduledDate = todayKey
        task.status = .done
        task.completedAt = Date()
        modelContext.insert(task)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(task.id.uuidString)")))
        manager.resolvedDestination(for: .task(task.id), modelContext: modelContext, todayKey: todayKey)
        #expect(manager.revealedCompletedTaskID == task.id)

        manager.handle(try #require(URL(string: "cadence://today")))
        #expect(manager.revealedCompletedTaskID == nil)
    }

    /// A surface opens its logbook only for a task it is actually about to list. Today's Completed
    /// section holds work settled *today*, so a link for something finished in January must leave
    /// it shut — a disclosure opening on an unrelated screen is the T-368 shape again.
    @Test func aSurfaceOpensItsLogbookOnlyForARowItLists() throws {
        let listed = AppTask(title: "Listed here")
        let elsewhere = AppTask(title: "Listed on another page")

        #expect(
            CadenceDeepLinkResolutionSupport.revealsCompletedSection(
                revealedTaskID: listed.id,
                completedTasks: [listed]
            )
        )
        #expect(
            !CadenceDeepLinkResolutionSupport.revealsCompletedSection(
                revealedTaskID: elsewhere.id,
                completedTasks: [listed]
            )
        )
        // No link, no reveal — the ordinary case, and the one every other appearance takes.
        #expect(
            !CadenceDeepLinkResolutionSupport.revealsCompletedSection(
                revealedTaskID: UUID?.none,
                completedTasks: [listed]
            )
        )
        #expect(
            !CadenceDeepLinkResolutionSupport.revealsCompletedSection(
                revealedTaskID: listed.id,
                completedTasks: [AppTask]()
            )
        )
    }

    /// **"Expanded" has to mean "listed."** The touch tier stops the logbook at
    /// `completedRowLimit`, newest-settled first, so the links most in need of the reveal — work
    /// finished long enough ago that the user went looking through a widget — are exactly the ones
    /// the cap would drop. Revealing into a section that still does not contain the task is the
    /// original defect with an animation in front of it.
    @Test func theRevealSurvivesTheTouchTiersCompletedRowCap() {
        let limit = CadenceTaskSurfaceOptions.completedRowLimit
        let tasks = (0..<(limit + 6)).map { AppTask(title: "Finished \($0)") }
        let beyondCap = tasks[limit + 3]
        let insideCap = tasks[2]

        let capped = CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: .touch)
        #expect(capped.count == limit)
        #expect(!capped.contains { $0.id == beyondCap.id })

        let revealed = CadenceTaskSurfaceOptions.completedRows(
            from: tasks,
            tier: .touch,
            revealing: beyondCap.id
        )
        #expect(revealed.count == limit + 1)
        #expect(revealed.last?.id == beyondCap.id)
        // Appended, not promoted: the logbook's order is when things were settled, and reordering
        // it around a deep link would misdate the rows above.
        #expect(revealed.prefix(limit).map(\.id) == capped.map(\.id))

        // A row already inside the cap is not duplicated, and an unknown id changes nothing.
        #expect(
            CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: .touch, revealing: insideCap.id)
                .map(\.id) == capped.map(\.id)
        )
        #expect(
            CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: .touch, revealing: UUID())
                .map(\.id) == capped.map(\.id)
        )
        // Desktop is uncapped, so the reveal is inert there and must not reorder anything.
        #expect(
            CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: .desktop, revealing: beyondCap.id)
                .map(\.id) == tasks.map(\.id)
        )
    }

    // MARK: T-375(b) — the macOS destination → page mapping

    /// **The `?? .today` fallback, pinned case by case.** The root mapped a resolved destination
    /// through `SidebarStaticDestination.allCases`, which is the *Settings customisation* table —
    /// six of the eleven destinations — so `.notes`, `.inbox` and `.settings` found no match and
    /// fell silently to Today. It was correct only because no resolver returned one of those three
    /// yet, which is a fact about today's `resolvedDestination` rather than about the mapping.
    @Test func everyDestinationThatIsAPageOpensItsOwnPageRatherThanToday() {
        let expected: [CadenceFeatureDestination: SidebarItem] = [
            .today: .today,
            .allTasks: .allTasks,
            .focus: .focus,
            .inbox: .inbox,
            .calendar: .calendar,
            .notes: .notes,
            .goals: .goals,
            .habits: .habits,
            .settings: .settings
        ]
        for (destination, item) in expected {
            #expect(destination.deepLinkSidebarItem == item, "\(destination.rawValue) routes to the wrong page")
        }

        // The three the old walk got wrong, named explicitly so a regression cannot hide inside a
        // dictionary that shrank.
        #expect(CadenceFeatureDestination.notes.deepLinkSidebarItem == .notes)
        #expect(CadenceFeatureDestination.inbox.deepLinkSidebarItem == .inbox)
        #expect(CadenceFeatureDestination.settings.deepLinkSidebarItem == .settings)

        // The fallback survives only for the two destinations that are genuinely not pages, and
        // for Today itself. Exactly three, so a future case cannot join them unnoticed.
        let fallsBackToToday = CadenceFeatureDestination.allCases.filter { $0.deepLinkSidebarItem == .today }
        #expect(Set(fallsBackToToday) == Set([.today, .lists, .search]))
        #expect(expected.count + 2 == CadenceFeatureDestination.allCases.count)
    }

    // MARK: T-370(a) — the wiring that consumes the route table

    /// The compact route *table* was already pinned; the code that applies it was not.
    ///
    /// A source scan because `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target
    /// builds for macOS, so there is no iOS symbol to call — and because both handlers are private
    /// methods on a SwiftUI view, which a test cannot reach even on macOS.
    @Test func bothRootsApplyTheResolvedDestinationRatherThanTheRawLink() throws {
        let iOSRaw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift")
        let iOSSource = CadenceSourceScan.strippingComments(iOSRaw)
        let macRaw = try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift")
        let macSource = CadenceSourceScan.strippingComments(macRaw)

        // Non-vacuity: the reader read code, the stripper stripped, and it kept its length.
        #expect(iOSSource != iOSRaw)
        #expect(iOSSource.count == iOSRaw.count)
        #expect(macSource != macRaw)
        #expect(macSource.count == macRaw.count)
        #expect(iOSSource.contains("struct iOSRootView: View"))
        #expect(macSource.contains("struct macOSRootView: View"))
        // Prose the stripper must have removed, so no assertion below can be reading a comment.
        #expect(iOSRaw.contains("One route, resolved once, applied to both shells."))
        #expect(!iOSSource.contains("One route, resolved once"))

        let iOSHandler = try #require(CadenceSourceScan.functionBody(named: "handleDeepLinkRoute", in: iOSSource))
        // Resolved against the store, never `featureDestination` straight off the link.
        #expect(iOSHandler.contains("deepLinkManager.resolvedDestination("))
        #expect(!iOSHandler.contains("featureDestination"))
        // **Both** halves. The regular shell reads `selection`; the compact shell reads the tab,
        // the Tasks segment and that tab's stack. Writing one and not the other leaves whichever
        // width the user is not on pointing somewhere else.
        #expect(iOSHandler.contains("selection = destination.item"))
        #expect(iOSHandler.contains("apply(destination.compactRoute)"))

        let macHandler = try #require(CadenceSourceScan.functionBody(named: "handleDeepLinkRoute", in: macSource))
        #expect(macHandler.contains("deepLinkManager.resolvedDestination("))
        #expect(!macHandler.contains("featureDestination"))
        #expect(macHandler.contains("selection = destination.deepLinkSidebarItem"))
        // T-375(b): the narrow table is gone from the handler entirely.
        #expect(!macHandler.contains("SidebarStaticDestination"))
        // T-369's half of the same handler, which a rewrite here could quietly drop.
        #expect(macHandler.contains("calendarNavigationManager.openCalendarLink(route)"))
    }

    /// Only the named tab's stack is touched. Pushing onto — or clearing — a tab the link did not
    /// name rearranges a screen the user is not looking at and will come back to.
    @Test func theCompactApplyTouchesExactlyOneTabsStack() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "apply", in: source))

        #expect(body.contains("selectedTabRaw = route.tab.rawValue"))
        #expect(body.contains("tasksSectionRaw = section.rawValue"))
        // Exactly one stack write, and it is keyed by the route's own tab.
        #expect(CadenceSourceScan.matchCount("compactPaths\\[", in: body) == 1)
        #expect(body.contains("compactPaths[route.tab] ="))
        // The regex needle compiles and discriminates — `matchCount` answers -1 for a pattern that
        // does not, which no `== 1` can reach by accident.
        #expect(CadenceSourceScan.matchCount("compactPaths\\[", in: "compactPaths[.tasks]") == 1)
        #expect(CadenceSourceScan.matchCount("compactPaths\\[", in: "selectedTabRaw = x") == 0)
    }

    /// Both All Tasks surfaces act on the reveal, and both hand it to the shared row builder so
    /// the touch cap cannot swallow the row the link named.
    @Test func bothAllTasksSurfacesOpenTheirLogbookForARevealedLink() throws {
        let macRaw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksListView.swift")
        let mac = CadenceSourceScan.strippingComments(macRaw)
        #expect(mac != macRaw)
        #expect(mac.count == macRaw.count)
        #expect(mac.contains("struct TasksListView: View"))
        #expect(mac.contains("isCompletedCollapsed = !revealsCompletedSection"))
        #expect(mac.contains("revealing: deepLinkManager.revealedCompletedTaskID"))
        #expect(mac.contains("CadenceDeepLinkResolutionSupport.revealsCompletedSection("))

        let phoneRaw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskCollectionViews.swift")
        let phone = CadenceSourceScan.strippingComments(phoneRaw)
        #expect(phone != phoneRaw)
        #expect(phone.count == phoneRaw.count)
        #expect(phone.contains("struct iOSAllTasksView: View"))
        #expect(phone.contains("CadenceDeepLinkResolutionSupport.revealsCompletedSection("))
        #expect(phone.contains("showCompleted = true"))

        let sections = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskCollectionPage.swift")
        )
        #expect(sections.contains("struct iOSTaskCollectionSections: View"))
        #expect(sections.contains("revealing: deepLinkManager.revealedCompletedTaskID"))
    }
}
