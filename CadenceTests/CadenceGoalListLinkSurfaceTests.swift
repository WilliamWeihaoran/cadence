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

    /// A `GoalListLink` row, built **directly** rather than through a helper ([[T-2079]]).
    ///
    /// Every fixture here used to call `ModelContext.attachList`, the app's one link writer. That
    /// helper is gone — the owner retired goals and nothing in the app creates or removes a link
    /// any more — so a test that needs a link in the store builds one itself. **A test is allowed
    /// to do this and `Cadence/` is not**, which is exactly what
    /// `nothingUnderCadenceConstructsAGoalListLink` below now asserts: the scan it replaced said
    /// "only the shared helper constructs a link", and with no helper left the stronger reading is
    /// that no shipped file constructs one at all.
    ///
    /// It is deliberately **not** idempotent. `attachList`'s early return was a guard on a *user*
    /// tapping the same list twice, and re-spelling it here would make a fixture quietly disagree
    /// with the rows it says it inserted.
    @discardableResult
    private func link(_ target: GoalLinkTarget, to goal: Goal, in modelContext: ModelContext) -> GoalListLink {
        let row: GoalListLink
        switch target {
        case .area(let area): row = GoalListLink(goal: goal, area: area)
        case .project(let project): row = GoalListLink(goal: goal, project: project)
        }
        modelContext.insert(row)
        goal.listLinks = (goal.listLinks ?? []) + [row]
        modelContext.processPendingChanges()
        return row
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
            overdueTaskIDs: [],
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

        link(.area(store.area), to: store.goal, in: store.modelContext)

        let after = GoalContributionResolver.summary(for: store.goal)
        #expect(after.totalTasks == 2)
        #expect(after.completedTasks == 1)
        #expect(after.progress == 0.5)
        #expect(after.linkedListCount == 1)
        #expect(after.directTaskCount == 0)
    }

    // MARK: - Attach / detach

    // **The ten tests that drove the link writers left with [[T-2079]].**
    //
    // They covered `attachList`'s idempotence, `toggleGoalListLink`'s two directions,
    // `detachGoalListLink`'s deliberate do-nothing-else shape ([[T-1321]]), the [[T-1301]]
    // refusal discipline on all three, and `deleteGoal` taking a goal's links with it. All
    // three helpers and `deleteGoal` are gone, so every one of those assertions is about a
    // function that does not exist — obsolete rather than weakened. The replacement is
    // `nothingUnderCadenceConstructsAGoalListLink` below, which is strictly stronger: not
    // "only the shared helper may", but "no shipped file may".

    // MARK: - A deleted link, and what the readers say about it ([[T-1306]])

    /// The `isDeleted` skip on its own, against the state it exists for — and **toolchain-free by
    /// construction** ([[T-1306]], [[T-1296]]).
    ///
    /// This used to be asserted twice over: the retired `attachList` processed its restore, and
    /// `links(of:)` skipped a deleted link besides. The writers left with [[T-2079]], and the
    /// attach sheets' `isAttached` reading and its `existingLink` guard left with [[T-4495]], so
    /// `links(of:)` is the one inspector reading left. It is exercised directly rather than
    /// through a refusal: a link deleted and **not** processed is the state the skip answers for,
    /// and if a toolchain clears the array at the delete instead, the assertion below still holds.
    @Test func aDeletedLinkIsNotALinkedList() throws {
        let store = try makeStore()
        let link = link(.area(store.area), to: store.goal, in: store.modelContext)
        try store.modelContext.save()
        #expect(GoalLinkPresentation.links(of: store.goal).count == 1, "the saved link is not drawn at all")

        store.modelContext.delete(link)

        #expect(
            GoalLinkPresentation.links(of: store.goal).isEmpty,
            "a row the store is about to drop is still drawn as a linked list"
        )
    }

    /// **The third reading, and the one no filter in `GoalLinkPresentation` could reach**
    /// ([[T-1306]]'s open half, closed by [[T-1321]]).
    ///
    /// `GoalContributionResolver` walks `goal.listLinks` **raw** — once for the tasks the goal
    /// counts and once for the "N lists" chip — so a link the store is about to drop moved the
    /// goal's *progress bar*, which is the part of this no inspector-side filter can protect. It
    /// is also what makes it safe for `detachGoalListLink` to stop severing the link's references
    /// before deleting it: the reading that matters no longer depends on the inverse array having
    /// caught up, only on the object's own `isDeleted`.
    ///
    /// Deleted and **not** processed, deliberately — that is the state a refusal leaves behind
    /// between the throw and the next processed change, and the state a detach is in before its
    /// flush.
    @Test func aDeletedLinkIsNotCountedByTheProgressBarEither() throws {
        let store = try makeStore()
        let task = AppTask(title: "Area task")
        task.area = store.area
        store.modelContext.insert(task)
        let link = link(.area(store.area), to: store.goal, in: store.modelContext)
        try store.modelContext.save()

        // The link is what the goal's progress is made of, so the assertions below are not
        // measuring a goal that never counted anything.
        #expect(GoalContributionResolver.summary(for: store.goal).totalTasks == 1)
        #expect(GoalContributionResolver.summary(for: store.goal).linkedListCount == 1)

        store.modelContext.delete(link)

        let summary = GoalContributionResolver.summary(for: store.goal)
        #expect(
            summary.totalTasks == 0,
            "a row the store is about to drop is still counted in the goal's progress bar"
        )
        #expect(
            summary.linkedListCount == 0,
            "a row the store is about to drop is still counted by the \"N lists\" chip"
        )
    }

    // MARK: - Which links a goal shows

    /// A link pointing at nothing is dropped, because `GoalContributionResolver.linkedListCount`
    /// drops it too — a surviving "Missing List" row would be a contributor the percentage has
    /// never heard of.
    @Test func targetlessLinksAreNotShown() throws {
        let store = try makeStore()

        let broken = GoalListLink(goal: store.goal)
        store.modelContext.insert(broken)
        link(.area(store.area), to: store.goal, in: store.modelContext)

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

        link(.area(store.area), to: store.goal, in: store.modelContext)
        link(.area(second), to: store.goal, in: store.modelContext)
        link(.area(third), to: store.goal, in: store.modelContext)

        let titles = GoalLinkPresentation.links(of: store.goal).map(\.title)
        #expect(titles.first == "Admin")
        #expect(titles.count == 3)
        // Case-insensitive equals means the id tie-break decides, so the result must not depend on
        // the order the relationship hands them over — and a stored to-many has no promised order.
        // The previous assertion compared one call to another call, which is a value against itself
        // and could never fail.
        let forward = GoalLinkPresentation.links(of: store.goal).map(\.id)
        store.goal.listLinks = (store.goal.listLinks ?? []).reversed()
        #expect(GoalLinkPresentation.links(of: store.goal).map(\.id) == forward)
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

        link(.area(store.area), to: store.goal, in: store.modelContext)
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

        link(.area(store.area), to: milestone, in: store.modelContext)

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

        #expect(groups.map(\.title) == ["Work", "Home", CadenceSidebarLists.ungroupedTitle])
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

    @Test func anUntitledListStillGetsANameInGoalListLinkSurface() throws {
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
        #expect(GoalLinkTarget.openTaskLabel(count: 1) == "1 active task")
        #expect(GoalLinkTarget.openTaskLabel(count: 0) == "0 active tasks")
        #expect(GoalLinkTarget.openTaskLabel(count: 12) == "12 active tasks")
    }

    // MARK: - Both platforms reach the one path

    /// **Nothing under `Cadence/` constructs a `GoalListLink` any more** ([[T-2079]]), and that is
    /// strictly stronger than what it replaced.
    ///
    /// This was `onlyTheSharedHelperConstructsALink`: the app had exactly one link writer —
    /// `GoalLinkTarget`'s `makeLink`, reached through `ModelContext.attachList` — so neither
    /// platform could grow its own spelling of "attach a list", which is what the macOS sheet's
    /// four private `insert(GoalListLink(...))` lines had been. The owner retired goals, the two
    /// attach sheets are deleted and the helper with them, so the question is no longer *which*
    /// file may construct one: it is that **no shipped file may**, which is a claim a scan can
    /// make and a reviewer cannot forget to re-derive.
    ///
    /// **The archive importer is the one exemption, and it is narrower than it was.** It restores
    /// rows the owner already had rather than authoring new ones, in two passes, because a link's
    /// goal and list may arrive later in the same archive than the link does: pass one builds every
    /// row bare and copies scalars, pass two resolves ids into relationships. So the exemption is
    /// the **empty** construction, asserted as such — the importer may write `GoalListLink()` and
    /// nothing else, and the day it writes `GoalListLink(goal:area:)` it has started authoring and
    /// this goes red. Keeping the importer whole is what makes [[T-2077]]'s retirement reversible:
    /// a backup that silently dropped the owner's links would be the opposite of the depth they
    /// chose.
    @Test func nothingUnderCadenceConstructsAGoalListLink() throws {
        // A plain substring count is wrong here, and finding that out was worth the run: every
        // `modelContext.toggleGoalListLink(` call contained `GoalListLink(`, so a
        // `components(separatedBy:)` count once made the shared helper's own file report 5 and
        // named all four of its call sites as offenders. The initializer needs a left word
        // boundary, and the needle keeps it.
        let pattern = "(?<![A-Za-z0-9_])GoalListLink\\("
        var offenders: [String] = []
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            let count = code.matchCount(ofPattern: pattern)
            guard count > 0 else { continue }
            offenders.append("\(path):\(count)")
        }

        #expect(
            offenders.contains("Cadence/Services/CadenceArchiveImportService.swift:1"),
            "the importer no longer constructs a link — delete this exemption: \(offenders)"
        )
        offenders.removeAll { $0 == "Cadence/Services/CadenceArchiveImportService.swift:1" }
        let importer = try strippingComments(sourceFile("Cadence/Services/CadenceArchiveImportService.swift"))
        #expect(
            importer.matchCount(ofPattern: "(?<![A-Za-z0-9_])GoalListLink\\(\\)") == 1,
            "the importer's link construction is no longer the argument-less one"
        )
        // And the relationships really are set in pass two, which is the reason the construction
        // can be empty: without this the assertion above would also pass on an importer that
        // simply lost the goal and the list.
        #expect(importer.contains("model.goal = record.goalID.flatMap { destination.goals[$0] }"))
        #expect(importer.contains("model.area = record.areaID.flatMap { destination.areas[$0] }"))
        #expect(importer.contains("model.project = record.projectID.flatMap { destination.projects[$0] }"))

        #expect(offenders.isEmpty, "a shipped file constructs a GoalListLink: \(offenders)")
        // Non-vacuity: the sweep really walked the shipped tree. An empty offender list is what a
        // broken walk also produces, which is the trap an inverted scan has to be built against.
        #expect(try swiftFiles(under: "Cadence").count > 100, "the sweep read no tree")
    }

    // **`bothPlatformsReadTheSharedLinkPresentation` and
    // `theIOSGoalDetailShowsTheLinkedListsSectionAndTheAttribution` left with [[T-5002]].** Both
    // counted `GoalLinkPresentation` call sites inside `iOSFeatureDetailViews.swift`,
    // `GoalInspectorView.swift` and `GoalsSupportViews.swift` — the three deleted files that drew
    // a goal's linked lists. There is no surface left to read the presentation from.
    //
    // **The presentation itself is NOT deleted and is still fully tested above**, by value rather
    // than by call site: `GoalListLinkHelpers` is in `Shared/` and `GoalContributionSummary` reads
    // it, so the ordering rule, the contribution label and metric, the attribution line and the
    // inherited-list note all keep their behavioural tests. Which of its members are now
    // callerless in product code is the second-tier dead-code sweep, filed separately rather than
    // pulled into a decided ticket.

    // MARK: - The scan itself

    /// The counts above are only worth anything if the scan actually reads files, and a scan that
    /// silently returns nothing passes every zero-count assertion. This is the test that stops them
    /// going vacuous — the exact failure mode that let a `/tmp` against `/private/tmp` path
    /// mismatch look like real regressions while the scan was reading nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInGoalListLinkSurface() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Shared/GoalListLinkHelpers.swift"))
        #expect(files.contains("Cadence/Models/GoalContributionSummary.swift"))

        // **The three the sweep must NOT find ([[T-2079]]).** `iOSGoalAttachListsSheet.swift`,
        // `GoalAttachWorkSheet.swift` and `CreateGoalSheet.swift` were each asserted present
        // above; all three were pure write surfaces and are deleted. Asserted absent rather than
        // simply dropped from the list, because "the line is gone" and "the file is gone" are
        // different claims and only one of them is this ticket's.
        #expect(!files.contains("Cadence/iOS/iOSGoalAttachListsSheet.swift"))
        #expect(!files.contains("Cadence/macOS/Views/GoalAttachWorkSheet.swift"))
        #expect(!files.contains("Cadence/macOS/Sheets/CreateGoalSheet.swift"))

        // **And the four READ surfaces [[T-5002]] deleted**, asserted the same way and for the
        // same reason: these drew a goal's linked lists, and the whole point of that ticket is
        // that nothing navigates to them any more.
        #expect(!files.contains("Cadence/iOS/iOSFeatureDetailViews.swift"))
        #expect(!files.contains("Cadence/macOS/Views/GoalInspectorView.swift"))
        #expect(!files.contains("Cadence/macOS/Views/GoalsSupportViews.swift"))
        #expect(!files.contains("Cadence/macOS/Views/GoalsView.swift"))

        // And it must be reading *code*, not an empty string: a positive assertion over the same
        // reader the counts above use. Pointed at the helpers file since [[T-5002]] deleted every
        // view this suite used to read — and it is the right file for it, because it is the one
        // this suite is actually about.
        let helpers = try strippingComments(sourceFile("Cadence/Shared/GoalListLinkHelpers.swift"))
        #expect(helpers.contains("enum GoalLinkPresentation"))
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
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
