import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-191: `GoalContributionResolver` folds `goal.listLinks`' tasks into a goal's percentage on
/// every platform, and `GoalListLink` had **zero** references under `Cadence/iOS` — so an iOS user
/// watched a number move for a reason the device could not show or change.
///
/// **Two kinds of test here, and the second kind is the point.** The first half pins the pure
/// decisions: which links a goal shows, what the attribution sentence says, and that attaching a
/// list really does move `summary.progress`. The second half reads the real source files and fails
/// the moment iOS grows its own `insert(GoalListLink(...))` beside macOS's — a helper can be right
/// while nothing calls it, which is exactly how this gap opened.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The helpers follow `CadenceSharedTaskRowJobsTests` — exact per-file counts rather than
/// "contains", comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan
/// cannot make the absence assertions pass silently.
@MainActor
struct CadenceGoalListLinkSurfaceTests {

    // MARK: - Fixtures

    private struct Store {
        let container: ModelContainer
        let modelContext: ModelContext
        let context: Context
        let area: Area
        let project: Project
        let goal: Goal
    }

    private func makeStore() throws -> Store {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        let project = Project(name: "Launch", context: context)
        let goal = Goal(title: "Ship it", context: context)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)

        return Store(
            container: container,
            modelContext: modelContext,
            context: context,
            area: area,
            project: project,
            goal: goal
        )
    }

    private func summary(
        progressType: GoalProgressType = .subtasks,
        totalTasks: Int,
        directTaskCount: Int,
        linkedListCount: Int
    ) -> GoalContributionSummary {
        GoalContributionSummary(
            progressType: progressType,
            targetHours: 10,
            totalTasks: totalTasks,
            completedTasks: 0,
            directTaskCount: directTaskCount,
            linkedListCount: linkedListCount,
            focusMinutes: 0,
            overdueTaskCount: 0,
            recentCompletedCount: 0,
            nextActionTitle: nil,
            nextActionDueDate: nil
        )
    }

    // MARK: - The premise

    /// The ticket's claim, asserted rather than assumed: a link is what moves the bar, and nothing
    /// about the goal itself changed between these two reads.
    @Test func attachingAListMovesTheGoalsProgress() throws {
        let store = try makeStore()

        let open = AppTask(title: "Open")
        open.area = store.area
        let done = AppTask(title: "Done")
        done.area = store.area
        done.status = .done
        store.modelContext.insert(open)
        store.modelContext.insert(done)

        let before = GoalContributionResolver.summary(for: store.goal)
        #expect(before.totalTasks == 0)
        #expect(before.progress == 0)

        store.modelContext.attachList(.area(store.area), to: store.goal)

        let after = GoalContributionResolver.summary(for: store.goal)
        #expect(after.totalTasks == 2)
        #expect(after.completedTasks == 1)
        #expect(after.progress == 0.5)
        #expect(after.linkedListCount == 1)
        #expect(after.directTaskCount == 0)
    }

    // MARK: - Attach / detach

    @Test func attachingInsertsOneLinkAndIsIdempotent() throws {
        let store = try makeStore()

        store.modelContext.attachList(.area(store.area), to: store.goal)
        store.modelContext.attachList(.area(store.area), to: store.goal)

        let links = try store.modelContext.fetch(FetchDescriptor<GoalListLink>())
        #expect(links.count == 1)
        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)
        #expect(GoalLinkPresentation.isAttached(.area(store.area), to: store.goal))
        #expect(!GoalLinkPresentation.isAttached(.project(store.project), to: store.goal))
    }

    /// A second link to the same list would double that list's tasks in every count that walks
    /// `listLinks`, and the picker's checkmark would hide the first one — the only symptom would be
    /// a percentage moving twice per completion.
    @Test func aDuplicateAttachCannotDoubleCountAListsTasks() throws {
        let store = try makeStore()

        let task = AppTask(title: "Counted once")
        task.area = store.area
        store.modelContext.insert(task)

        store.modelContext.attachList(.area(store.area), to: store.goal)
        store.modelContext.attachList(.area(store.area), to: store.goal)

        #expect(GoalContributionResolver.summary(for: store.goal).totalTasks == 1)
    }

    @Test func togglingAttachesThenDetaches() throws {
        let store = try makeStore()

        #expect(store.modelContext.toggleGoalListLink(.project(store.project), on: store.goal))
        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)

        #expect(!store.modelContext.toggleGoalListLink(.project(store.project), on: store.goal))
        #expect(GoalLinkPresentation.links(of: store.goal).isEmpty)
        #expect(try store.modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
    }

    /// The reverse of `ListDeleteHelpers` cascading `goalLinks` when a list is deleted: detaching
    /// removes the join row and **nothing else**. The list, its tasks and the goal are the user's
    /// real work and outlive the link, exactly as they outlive a deleted goal.
    @Test func detachingOrphansNothingButRemovesTheRow() throws {
        let store = try makeStore()

        let task = AppTask(title: "Area task")
        task.area = store.area
        store.modelContext.insert(task)

        store.modelContext.attachList(.area(store.area), to: store.goal)
        let link = try #require(GoalLinkPresentation.links(of: store.goal).first)

        store.modelContext.detachGoalListLink(link)

        #expect(try store.modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(GoalLinkPresentation.links(of: store.goal).isEmpty)
        #expect((store.goal.listLinks ?? []).isEmpty)
        #expect((store.area.goalLinks ?? []).isEmpty)
        // The far side survives.
        #expect(try store.modelContext.fetch(FetchDescriptor<Area>()).count == 1)
        #expect(try store.modelContext.fetch(FetchDescriptor<Goal>()).count == 1)
        #expect(try store.modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)
        #expect(store.area.tasks?.count == 1)
        // And the goal stops counting the list's work.
        #expect(GoalContributionResolver.summary(for: store.goal).totalTasks == 0)
    }

    /// `deleteGoal` already removes a goal's links; this is the same guarantee read from the other
    /// end, because a surviving link is a row whose `goal` is gone and whose `tasks` still resolve.
    @Test func deletingAGoalTakesItsLinksWithIt() throws {
        let store = try makeStore()
        store.modelContext.attachList(.area(store.area), to: store.goal)

        store.modelContext.deleteGoal(store.goal)

        #expect(try store.modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try store.modelContext.fetch(FetchDescriptor<Area>()).count == 1)
    }

    // MARK: - Which links a goal shows

    /// A link pointing at nothing is dropped, because `GoalContributionResolver.linkedListCount`
    /// drops it too — a surviving "Missing List" row would be a contributor the percentage has
    /// never heard of.
    @Test func targetlessLinksAreNotShown() throws {
        let store = try makeStore()

        let broken = GoalListLink(goal: store.goal)
        store.modelContext.insert(broken)
        store.modelContext.attachList(.area(store.area), to: store.goal)

        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)
        #expect(GoalContributionResolver.summary(for: store.goal).linkedListCount == 1)
    }

    /// `listLinks` is a SwiftData to-many with no defined order, so the sort has to be total:
    /// title alone leaves two lists of the same name swapping places between renders.
    @Test func linksAreOrderedTotally() throws {
        let store = try makeStore()

        let second = Area(name: "documents", context: store.context)
        let third = Area(name: "Admin", context: store.context)
        store.modelContext.insert(second)
        store.modelContext.insert(third)

        store.modelContext.attachList(.area(store.area), to: store.goal)
        store.modelContext.attachList(.area(second), to: store.goal)
        store.modelContext.attachList(.area(third), to: store.goal)

        let titles = GoalLinkPresentation.links(of: store.goal).map(\.title)
        #expect(titles.first == "Admin")
        #expect(titles.count == 3)
        // Case-insensitive equals means the tie-break decides, and it must decide the same way
        // twice in a row.
        #expect(GoalLinkPresentation.links(of: store.goal).map(\.id) == GoalLinkPresentation.links(of: store.goal).map(\.id))
    }

    @Test func theContributionLabelCountsOnlyWorkTheGoalCounts() throws {
        let store = try makeStore()

        let open = AppTask(title: "Open")
        open.area = store.area
        let cancelled = AppTask(title: "Cancelled")
        cancelled.area = store.area
        cancelled.status = .cancelled
        store.modelContext.insert(open)
        store.modelContext.insert(cancelled)

        store.modelContext.attachList(.area(store.area), to: store.goal)
        let link = try #require(GoalLinkPresentation.links(of: store.goal).first)

        #expect(GoalLinkPresentation.contributingTaskCount(for: link) == 1)
        #expect(GoalLinkPresentation.contributionLabel(for: link) == "1 contributing task")
        #expect(GoalLinkPresentation.contributionLabel(taskCount: 0) == "0 contributing tasks")
        #expect(GoalLinkPresentation.contributionLabel(taskCount: 12) == "12 contributing tasks")
        // The row-metric spelling of the same figure, for the trailing slot of a 44pt row.
        #expect(GoalLinkPresentation.contributionMetric(for: link) == "1 task")
        #expect(GoalLinkPresentation.contributionMetric(taskCount: 0) == "0 tasks")
        #expect(GoalLinkPresentation.contributionMetric(taskCount: 12) == "12 tasks")
    }

    // MARK: - Explaining the number

    @Test func theAttributionLineNamesTheLinkedShareOfTheCount() {
        #expect(
            GoalLinkPresentation.attributionLine(
                for: summary(totalTasks: 9, directTaskCount: 2, linkedListCount: 2)
            ) == "7 of 9 counted tasks come from 2 linked lists."
        )
        #expect(
            GoalLinkPresentation.attributionLine(
                for: summary(totalTasks: 4, directTaskCount: 3, linkedListCount: 1)
            ) == "1 of 4 counted tasks come from 1 linked list."
        )
    }

    /// Nothing to explain gets no line — a goal whose counted work is all directly assigned should
    /// not carry a sentence saying zero, and neither should a goal with a link whose list is empty.
    @Test func theAttributionLineIsSilentWhenThereIsNothingToExplain() {
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 5, directTaskCount: 5, linkedListCount: 0)) == nil)
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 5, directTaskCount: 5, linkedListCount: 2)) == nil)
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 0, directTaskCount: 0, linkedListCount: 1)) == nil)
        // A direct count above the total cannot make the sentence claim negative work.
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 2, directTaskCount: 5, linkedListCount: 1)) == nil)
    }

    /// An hours goal's bar is logged time, so the linked tasks move the task count and not the
    /// percentage. Saying so is the difference between explaining the number and naming the wrong
    /// cause for it.
    @Test func anHoursGoalSaysWhatItsBarActuallyTracks() {
        let line = GoalLinkPresentation.attributionLine(
            for: summary(progressType: .hours, totalTasks: 6, directTaskCount: 1, linkedListCount: 1)
        )
        #expect(line == "5 of 6 counted tasks come from 1 linked list. Progress tracks logged hours.")
    }

    /// `linkedListCount` recurses sub-goals, so a direction's chip can outnumber the rows in its
    /// own section — and the lists you cannot see are the ones moving a number you cannot explain.
    @Test func inheritedLinksAreNamedRatherThanSilentlyMissing() {
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 1, totalLinkCount: 1) == nil)
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 2, totalLinkCount: 1) == nil)
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 1, totalLinkCount: 2) == "1 more list is attached to a milestone.")
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 0, totalLinkCount: 3) == "3 more lists are attached to milestones.")
    }

    /// The section's own count and the recursive chip must be able to disagree — which is the whole
    /// reason the note above exists.
    @Test func aMilestonesLinkCountsForItsDirectionWithoutBecomingItsRow() throws {
        let store = try makeStore()
        let milestone = Goal(title: "Milestone", context: store.context)
        milestone.parentGoal = store.goal
        store.modelContext.insert(milestone)

        store.modelContext.attachList(.area(store.area), to: milestone)

        let summary = GoalContributionResolver.summary(for: store.goal)
        #expect(summary.linkedListCount == 1)
        #expect(GoalLinkPresentation.links(of: store.goal).isEmpty)
        #expect(
            GoalLinkPresentation.inheritedListNote(
                ownLinkCount: GoalLinkPresentation.links(of: store.goal).count,
                totalLinkCount: summary.linkedListCount
            ) == "1 more list is attached to a milestone."
        )
    }

    // MARK: - Candidates

    @Test func candidatesAreGroupedByContextWithAreasBeforeProjects() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let workArea = Area(name: "Docs", context: work)
        let workProject = Project(name: "Launch", context: work)
        let homeArea = Area(name: "House", context: home)
        let unfiled = Project(name: "Loose Ends")
        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(workArea)
        modelContext.insert(workProject)
        modelContext.insert(homeArea)
        modelContext.insert(unfiled)

        let groups = GoalLinkPresentation.candidateGroups(
            contexts: [work, home],
            areas: [workArea, homeArea],
            projects: [workProject, unfiled],
            query: ""
        )

        #expect(groups.map(\.title) == ["Work", "Home", "No Context"])
        #expect(groups[0].targets.map(\.displayName) == ["Docs", "Launch"])
        #expect(groups[1].targets.map(\.displayName) == ["House"])
        #expect(groups[2].targets.map(\.displayName) == ["Loose Ends"])
        #expect(GoalLinkPresentation.candidateCount(in: groups) == 4)
    }

    @Test func searchFiltersCandidatesAndDropsEmptiedGroups() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let docs = Area(name: "Documents", context: work)
        let house = Area(name: "House", context: home)
        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(docs)
        modelContext.insert(house)

        let groups = GoalLinkPresentation.candidateGroups(
            contexts: [work, home],
            areas: [docs, house],
            projects: [],
            query: "  DOC "
        )

        #expect(groups.count == 1)
        #expect(groups[0].targets.map(\.displayName) == ["Documents"])
    }

    /// No status filter, deliberately: progress keeps counting an archived list's tasks, so hiding
    /// it here would leave a contributor that cannot be detached from the picker that manages
    /// contributors.
    @Test func anArchivedListStaysAttachableBecauseItStillContributes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let archived = Project(name: "Old Launch", context: work)
        archived.status = .archived
        modelContext.insert(work)
        modelContext.insert(archived)

        let groups = GoalLinkPresentation.candidateGroups(
            contexts: [work],
            areas: [],
            projects: [archived],
            query: ""
        )

        #expect(GoalLinkPresentation.candidateCount(in: groups) == 1)
    }

    @Test func anUntitledListStillGetsAName() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "   ")
        let project = Project(name: "")
        modelContext.insert(area)
        modelContext.insert(project)

        #expect(GoalLinkTarget.area(area).displayName == "Untitled Area")
        #expect(GoalLinkTarget.project(project).displayName == "Untitled Project")
    }

    @Test func theCandidateSubtitleUsesTheAppsOwnActiveTaskSpelling() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Docs")
        let task = AppTask(title: "Open")
        task.area = area
        modelContext.insert(area)
        modelContext.insert(task)

        // "1 active task", not the "\(count) active tasks" the attach sheet used to interpolate.
        #expect(GoalLinkTarget.area(area).openTaskLabel == "1 active task")
    }

    // MARK: - Both platforms reach the one path

    /// **The call-site half.** `GoalListLink` is constructed in exactly one place in the app now,
    /// so neither platform can grow its own spelling of "attach a list" — which is what the macOS
    /// sheet's four private `insert(GoalListLink(...))` lines were, and what iOS would otherwise
    /// have had to copy.
    @Test func onlyTheSharedHelperConstructsALink() throws {
        // A plain substring count is wrong here, and finding that out was worth the run: every
        // `modelContext.toggleGoalListLink(` and `detachGoalListLink(` call *contains*
        // `GoalListLink(`, so a `components(separatedBy:)` count made the shared helper's own file
        // report 5 and named all four call sites as offenders. The initializer needs a left word
        // boundary.
        let pattern = "(?<![A-Za-z0-9_])GoalListLink\\("
        var offenders: [String] = []
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            let count = code.matchCount(ofPattern: pattern)
            guard count > 0 else { continue }
            offenders.append("\(path):\(count)")
        }
        #expect(offenders == ["Cadence/Shared/GoalListLinkHelpers.swift:2"])
    }

    /// iOS's detach and macOS's are the same function, and iOS's attach sheet and macOS's are the
    /// same toggle. Exact counts, not "contains": reverting *one* of these call sites has to fail.
    @Test func bothPlatformsCallTheSharedAttachAndDetachPath() throws {
        try expectCallSites(of: "toggleGoalListLink", at: [
            // Declaration.
            "Cadence/Shared/GoalListLinkHelpers.swift": 1,
            "Cadence/iOS/iOSGoalAttachListsSheet.swift": 1,
            "Cadence/macOS/Views/GoalAttachWorkSheet.swift": 1
        ])

        try expectCallSites(of: "detachGoalListLink", at: [
            // Declaration, plus the call inside `toggleGoalListLink`.
            "Cadence/Shared/GoalListLinkHelpers.swift": 2,
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalsView.swift": 1
        ])

        try expectCallSites(of: "attachList", at: [
            // Declaration, plus the call inside `toggleGoalListLink`.
            "Cadence/Shared/GoalListLinkHelpers.swift": 2,
            "Cadence/macOS/Sheets/CreateGoalSheet.swift": 2
        ])

        try expectCallSites(of: "candidateGroups", at: [
            "Cadence/Shared/GoalListLinkHelpers.swift": 1,
            "Cadence/iOS/iOSGoalAttachListsSheet.swift": 1,
            "Cadence/macOS/Views/GoalAttachWorkSheet.swift": 1
        ])
    }

    /// The presentation decisions are read from one place on both platforms — the ordering rule,
    /// the row's task-count label, and the empty section's copy.
    @Test func bothPlatformsReadTheSharedLinkPresentation() throws {
        try expectOccurrences(of: "GoalLinkPresentation.links(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalInspectorView.swift": 1
        ])

        // macOS's row has the width for the sentence; iOS's 44pt row takes the metric. Both come
        // from `contributingTaskCount`, and neither file spells the count itself.
        try expectOccurrences(of: "GoalLinkPresentation.contributionLabel(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 0,
            "Cadence/macOS/Views/GoalsSupportViews.swift": 1
        ])
        try expectOccurrences(of: "GoalLinkPresentation.contributionMetric(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalsSupportViews.swift": 0
        ])

        try expectOccurrences(of: "GoalLinkPresentation.emptyExplanation", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalInspectorView.swift": 1
        ])
    }

    /// The explanation is on the screen, not only in the value type: the iOS goal detail draws the
    /// attribution line under its progress bar and the inherited-links note in its section.
    @Test func theIOSGoalDetailShowsTheLinkedListsSectionAndTheAttribution() throws {
        try expectOccurrences(of: "GoalLinkPresentation.attributionLine(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1
        ])
        try expectOccurrences(of: "GoalLinkPresentation.inheritedListNote(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1
        ])
        try expectOccurrences(of: "iOSGoalAttachListsSheet(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1
        ])
        try expectOccurrences(of: "linkedListsSection", at: [
            // The declaration and the one place the body reads it.
            "Cadence/iOS/iOSFeatureDetailViews.swift": 2
        ])
    }

    // MARK: - The scan itself

    /// The counts above are only worth anything if the scan actually reads files, and a scan that
    /// silently returns nothing passes every zero-count assertion. This is the test that stops them
    /// going vacuous — the exact failure mode that let a `/tmp` against `/private/tmp` path
    /// mismatch look like real regressions while the scan was reading nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Shared/GoalListLinkHelpers.swift"))
        #expect(files.contains("Cadence/iOS/iOSGoalAttachListsSheet.swift"))
        #expect(files.contains("Cadence/iOS/iOSFeatureDetailViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalAttachWorkSheet.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalInspectorView.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalsSupportViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalsView.swift"))
        #expect(files.contains("Cadence/macOS/Sheets/CreateGoalSheet.swift"))

        // And it must be reading *code*, not an empty string: a positive assertion over the same
        // reader the counts above use.
        let sheet = try strippingComments(sourceFile("Cadence/iOS/iOSGoalAttachListsSheet.swift"))
        #expect(sheet.contains("struct iOSGoalAttachListsSheet: View"))
        #expect(!sheet.contains("Attach or detach the areas and projects"))
    }
}

// MARK: - Source-reading helpers

private extension String {
    /// Regex match count, for scans where a bare substring would over-count — `GoalListLink(`
    /// sits inside `toggleGoalListLink(`.
    func matchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}


/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file. Unlike
/// `expectCallSites` this does not append `(`, so it can pin a property read too.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
