import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-751: the six filters that keep [[T-623]] inert, pinned to that reason.**
///
/// T-623 is that a hard list deletion walks only the local replica.
/// `CadenceListDeleteHelpers`' three cascades each build their whole tree out of local to-many
/// arrays — `context.areas ?? []`, `area.goalLinks ?? []`, `habits.flatMap { $0.completions ?? [] }`
/// — with no gate on sync state, so a child row that has not yet imported is not in the array, is
/// not deleted, and arrives afterwards with its owner gone. That mechanism is real and confirmed.
/// It is parked deliberately: re-measured 2026-09-03, the durable fix is far larger than it was
/// sized at and the import gate it was sized against does not exist. **This suite is not an attempt
/// to unpark it.**
///
/// T-623 is survivable only because the row it strands is **inert at every read site**. Six filters
/// do that work, and not one of them was written for it:
///
/// | site | its own reason |
/// | --- | --- |
/// | `GoalLinkPresentation.links(of:)` | avoid a cosmetic "Missing List" row |
/// | `GoalContributionResolver.linkedListCount` | keep the goal's own count honest |
/// | `CadenceReadService.goalSummary` | mirror that count on the MCP wire |
/// | `DataIntegrityRepairService.repairDuplicateHabitCompletions` | it groups by `habit.id` |
/// | `LinksView.links` | that is how a per-list panel is built at all |
/// | `iOSListLinksPanel.links` | the same, on iOS |
///
/// Remove any one of them for a perfectly good local reason and T-623 stops being inert and starts
/// being **visible corruption** — a "Missing List" contributor inside a goal's percentage, an
/// orphaned check-in collapsed into a stranger's habit-day, a phantom saved link on somebody
/// else's list — with no test going red anywhere and a parked ticket saying it does not matter.
///
/// So each test below fails *for that reason*, in its message. A person deleting one of these
/// filters should learn from the failure that T-623's parking depends on it, not merely that some
/// count changed.
///
/// **Two kinds of test, because two of the six sites cannot be called.** `LinksView.links` and
/// `iOSListLinksPanel.links` are private computed properties on SwiftUI views, and
/// `Cadence/iOS/` is entirely inside `#if os(iOS)` and invisible to this macOS-built target. Those
/// two are pinned by reading the source, through `CadenceScanInstrument` so a scan that stopped
/// discriminating fails its own constructor rather than sweeping green.
///
/// Every pin here was mutation-tested: each filter was deleted in an isolated tree and the
/// corresponding test went red. A pin that survives its own deletion would be worse than no pin,
/// because it would license unparking T-623 on the belief it is guarded.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceOrphanRowInertnessTests {

    // MARK: - Fixtures

    /// A goal carrying one live link and one **orphan** — the row T-623 strands: a `GoalListLink`
    /// whose `area` and `project` are both `nil` because its owner was deleted on another device
    /// before this replica ever imported it.
    ///
    /// Built by nulling the relationship rather than by never setting it, so the row is the same
    /// shape SwiftData's nullify leaves behind rather than a shape only a test can make.
    private struct StrandedGoal {
        let container: ModelContainer
        let modelContext: ModelContext
        let goal: Goal
        let live: GoalListLink
        let orphan: GoalListLink
    }

    private func makeStrandedGoal() throws -> StrandedGoal {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        let doomed = Area(name: "Retired", context: context)
        let goal = Goal(title: "Ship it", context: context)
        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(doomed)
        modelContext.insert(goal)

        let live = GoalListLink(goal: goal, area: area)
        let orphan = GoalListLink(goal: goal, area: doomed)
        modelContext.insert(live)
        modelContext.insert(orphan)
        try modelContext.save()

        // The T-623 event: the owner goes, the link does not. `deleteArea` would have taken the
        // link with it — the point is that on the replica where the link had not yet arrived, it
        // could not, and the row lands here afterwards pointing at nothing.
        orphan.area = nil
        modelContext.delete(doomed)
        try modelContext.save()

        #expect(orphan.area == nil && orphan.project == nil, "the fixture did not strand the link")
        #expect(orphan.title == "Missing List", "GoalListLink stopped labelling an owner-less row")
        #expect((goal.listLinks ?? []).count == 2, "the stranded link fell off the goal")

        return StrandedGoal(
            container: container,
            modelContext: modelContext,
            goal: goal,
            live: live,
            orphan: orphan
        )
    }

    // MARK: - GoalLinkPresentation.links(of:)

    /// `Cadence/Shared/GoalListLinkHelpers.swift` — `.filter { $0.area != nil || $0.project != nil }`.
    ///
    /// Its stated reason is cosmetic: a target-less row renders as `GoalListLink.title`'s fallback,
    /// the literal `"Missing List"`, with a `questionmark.folder` icon. Its load-bearing reason is
    /// that this is the list every goal surface on both platforms renders, so it is where a T-623
    /// orphan would first become something the user can see and tap.
    @Test func aStrandedGoalLinkIsNotOneOfTheLinksAGoalShows() throws {
        let fixture = try makeStrandedGoal()

        let shown = GoalLinkPresentation.links(of: fixture.goal)

        #expect(
            shown.map(\.id) == [fixture.live.id],
            """
            GoalLinkPresentation.links(of:) is showing a link with neither an area nor a project. \
            That filter is what keeps T-623 inert: a hard list deletion walks only the local \
            replica, so a goal link that had not yet imported survives its owner, and this is the \
            surface where it becomes a visible "Missing List" row the user can tap. Do not remove \
            it without unparking T-623.
            """
        )
        #expect(
            shown.contains(where: { $0.title == "Missing List" }) == false,
            "a T-623 orphan reached the goal's link list as a \"Missing List\" row"
        )
    }

    // MARK: - GoalContributionResolver

    /// `Cadence/Models/GoalContributionSummary.swift:114` — the same predicate, one line, feeding
    /// `linkedListCount`.
    ///
    /// This is the number the goal card and inspector print as "N lists", and `links(of:)`'s doc
    /// comment names it as the reason that filter exists at all: the two must agree or the sentence
    /// under the progress bar counts a row the list above it does not show.
    @Test func aStrandedGoalLinkIsNotCountedAmongAGoalsLinkedLists() throws {
        let fixture = try makeStrandedGoal()

        let summary = GoalContributionResolver.summary(for: fixture.goal)

        #expect(
            summary.linkedListCount == 1,
            """
            linkedListCount counted \(summary.linkedListCount) of 2 links, so a link with no area \
            and no project is being counted. That filter is what keeps T-623 inert: a goal link \
            stranded by a partial list deletion would otherwise appear inside the goal's own \
            "N lists" figure while contributing no tasks to it. Do not remove it without \
            unparking T-623.
            """
        )
        #expect(
            summary.linkedListCount == GoalLinkPresentation.links(of: fixture.goal).count,
            "the count and the rendered list disagree about how many lists feed this goal"
        )
    }

    // MARK: - CadenceReadService

    /// `Cadence/Services/MCPReadOnly/CadenceReadService.swift:1144` — the same predicate again, on
    /// the MCP wire.
    ///
    /// Third copy, third reason: an agent reading `ownLinkedListCount` gets the number the app
    /// shows. Without the filter it would get a count no `cadence_get_goal` follow-up could
    /// explain, because the link it counts names no list.
    @Test func aStrandedGoalLinkIsNotCountedOnTheMCPWire() throws {
        let fixture = try makeStrandedGoal()
        let service = CadenceReadService(container: fixture.container)

        let page = try service.listGoals(options: .init(limit: 50))
        let row = try #require(page.items.first { $0.id == fixture.goal.id.uuidString })

        #expect(
            row.ownLinkedListCount == 1,
            """
            ownLinkedListCount reported \(row.ownLinkedListCount) of 2 links, so the MCP surface is \
            counting a link with no area and no project. That filter is what keeps T-623 inert: it \
            is the read side of a partial list deletion, and an agent cannot resolve a link that \
            names no list. Do not remove it without unparking T-623.
            """
        )
    }

    // MARK: - DataIntegrityRepairService

    /// `Cadence/Services/DataIntegrityRepairService.swift` — `repairDuplicateHabitCompletions`
    /// groups by `HabitDay(habitID: habit.id, date:)` behind
    /// `guard let habit = completion.habit, !completion.date.isEmpty`.
    ///
    /// **The gentlest-looking of the six and the only destructive one.** `deleteContext` deletes a
    /// context's habits *and* `habits.flatMap { $0.completions ?? [] }` — a local-replica walk, so
    /// a check-in that had not yet imported survives its habit. Widening the grouping to
    /// `completion.habit?.id` looks like a strict improvement (why should orphans be exempt from
    /// de-duplication?) and would make every stranded check-in in the store share one group with
    /// every other stranded check-in on the same date, regardless of which habit each came from.
    /// The pass would then *delete* rows: unrelated users' unrelated habits, collapsed into one
    /// "habit-day", on an unattended startup pass, unrecoverably.
    ///
    /// The orphan sweep that would legitimately handle these rows is [[T-328]], and this pass says
    /// in its own doc comment that it is not that sweep.
    @Test func strandedHabitCheckInsAreNotCollapsedIntoOneAnother() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        // A live habit with a genuine duplicated day, so the pass is demonstrably running: a test
        // whose only evidence is "nothing was deleted" passes just as well when the pass is
        // skipped entirely.
        let habit = Habit(title: "Meditate")
        modelContext.insert(habit)
        for _ in 0..<2 {
            modelContext.insert(HabitCompletion(date: "2026-03-09", habit: habit))
        }

        // Two check-ins from two *different* habits, stranded on one date by T-623. Nothing in the
        // store can tell them apart any more, which is exactly why they must be left alone.
        let strandedA = HabitCompletion(date: "2026-03-09")
        let strandedB = HabitCompletion(date: "2026-03-09")
        modelContext.insert(strandedA)
        modelContext.insert(strandedB)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(
            report.duplicateHabitCompletionsRemoved == 1,
            """
            the duplicate-habit-day pass removed \(report.duplicateHabitCompletionsRemoved) rows \
            where exactly one live duplicate exists, so it is grouping habit-less rows together. \
            Grouping by habit.id is what keeps T-623 inert: a hard list deletion walks only the \
            local replica, so check-ins that had not yet imported survive their habits, and two \
            such rows sharing a date are two different habits' days that nothing can tell apart. \
            Collapsing them deletes real check-ins, unattended, at launch. Do not widen this \
            grouping without unparking T-623 — the orphan sweep is T-328, not this pass.
            """
        )

        let stranded = try modelContext.fetch(FetchDescriptor<HabitCompletion>())
            .filter { $0.habit == nil }
        #expect(
            stranded.count == 2,
            "a stranded check-in was deleted by the duplicate-habit-day pass (\(stranded.count) of 2 left)"
        )
        #expect((habit.completions ?? []).count == 1, "the live duplicated day was not collapsed")
    }

    // MARK: - The two saved-link panels

    /// `LinksView.links` (macOS) and `iOSListLinksPanel.links` (iOS) both filter
    /// `@Query`'d `[SavedLink]` down to the rows whose `area`/`project` **id equals this list's**.
    ///
    /// Read as text because both are private computed properties on SwiftUI views and the iOS one
    /// is inside `#if os(iOS)`, invisible to this macOS-built target.
    ///
    /// The reason it is load-bearing is the comparison, not the presence of a filter. `deleteArea`
    /// and `deleteProject` delete `area.links` / `project.links` from the local replica only, so a
    /// saved link that had not yet imported survives with its owner nulled. `$0.area?.id == area.id`
    /// is `nil == someUUID`, which is false, so the orphan lands in no panel. A panel that returned
    /// `allLinks` — or filtered on anything weaker than owner identity, such as `$0.area != nil` —
    /// would show one list's bookmark on a different list, or every list's bookmarks on all of them.
    @Test func neitherSavedLinkPanelCanShowAListItDoesNotOwn() throws {
        let unfiltered = """
            private var links: [SavedLink] {
                if let area {
                    return allLinks
                }
                return []
            }
            """
        let filtered = """
            private var links: [SavedLink] {
                if let area {
                    return allLinks.filter { $0.area?.id == area.id }
                }
                return []
            }
            """
        let instrument = try CadenceScanInstrument(
            "a saved-link panel returns the whole query",
            fires: unfiltered,
            andNotOn: filtered,
            by: { CadenceSourceScan.matchCount("return allLinks(?!\\.filter)", in: $0) > 0 }
        )

        for path in [
            "Cadence/macOS/Views/LinksView.swift",
            "Cadence/iOS/iOSListSupportViews.swift"
        ] {
            let code = try CadenceCommitSurfaceScan.scanned(path)
            let body = try cadenceFunctionBody("private var links: [SavedLink]", in: code)

            #expect(
                instrument.fires(on: body) == false,
                """
                \(path)'s saved-link panel returns its whole SavedLink query unfiltered. Filtering \
                by owner id is what keeps T-623 inert: a hard list deletion walks only the local \
                replica, so a saved link that had not yet imported survives with its owner nulled, \
                and an unfiltered panel shows that phantom bookmark on every list. Do not remove \
                it without unparking T-623.
                """
            )
            #expect(
                CadenceSourceScan.matchCount("\\$0\\.area\\?\\.id == area\\.id", in: body) == 1
                    && CadenceSourceScan.matchCount("\\$0\\.project\\?\\.id == project\\.id", in: body) == 1,
                """
                \(path)'s saved-link panel no longer selects by owner **identity** on both branches. \
                `$0.area?.id == area.id` is false for a nulled owner, which is the whole reason a \
                T-623 orphan cannot appear here; a weaker predicate such as `$0.area != nil` admits \
                it onto every list's panel. Do not weaken it without unparking T-623.
                """
            )
            #expect(
                CadenceSourceScan.matchCount("allLinks", in: body) == 2,
                "\(path): the panel reads its query \(CadenceSourceScan.matchCount("allLinks", in: body)) times, not twice — the scan is no longer reading the two branches it is about"
            )
        }
    }
}
