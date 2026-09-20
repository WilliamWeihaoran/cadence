import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-1302]]: the macOS new-goal sheet used to seed its **Initial Linked List** with
/// `_ = try? modelContext.attachList(target, to: goal)` and dismiss regardless, so a refused attach
/// left the user with a goal, no list, and no sentence.
///
/// **The hazard this suite exists for is the fix's, not the defect's.** The obvious repair — set
/// `saveError` and skip the `dismiss()` — keeps the sheet open, and `editingGoal` is a `let` that
/// is `nil` on the create path: a second press of the button would therefore run
/// `saveGoal(nil, …)` again and insert a **second goal** for one gesture. That is why [[T-1301]]
/// filed this rather than folding it in, and it is what
/// `theRetryAfterARefusedAttachEditsTheHeldGoalAndDoesNotInsertASecond` and its negative control
/// pin: the first argument `save()` hands `saveGoal` is the whole difference between one goal and
/// two, and the sheet now hands it `targetGoal` (`createdGoal ?? editingGoal`).
///
/// **Two instruments, and which claim each carries.** `save()`, `attachInitialList(to:)`,
/// `isEditing` and `targetGoal` are private members of a SwiftUI `View`, so nothing here can call
/// them — the same constraint `CadenceCreateSheetCommitSurfaceTests` and
/// `CadenceTrackingEditorSaveCommitTests.themacGoalSheetDismissesOnlyThroughASuccessfulTry` work
/// under, and source scans are this repository's established answer to it. What a scan cannot say
/// is that passing the held goal *works*, so the store-level half runs the exact two-press sequence
/// forwards against a real container with a refused `commit:` and counts the goals afterwards.
/// Neither half is decoration: back out the `targetGoal` wiring and the scan goes red; run the
/// retry with `nil` and the behavioural control counts two goals.
///
/// **Toolchain-independent by construction ([[T-1296]]).** Nothing below reads a relationship
/// across a `rollback()`. `attachList` undoes through `commitInsert`, which deletes what it was
/// handed, and re-applies the goal's own captured `listLinks`; the pending-change assertion is
/// [[T-1295]]'s shape — run the *next* unrelated `save()` forwards and read the store from a
/// second context.
@MainActor
struct CadenceCreateGoalInitialAttachTests {

    // MARK: - Fixtures

    /// A commit that refuses. `ModelContext.save()` cannot be made to throw out of an in-memory
    /// container, which is why both mutations take their commit as a parameter at all.
    private struct CommitRefused: Error {}

    private static func refuse(_ modelContext: ModelContext) throws {
        throw CommitRefused()
    }

    private static let sheetPath = "Cadence/macOS/Sheets/CreateGoalSheet.swift"

    private struct Store {
        let container: ModelContainer
        let modelContext: ModelContext
        let area: Area
    }

    private func makeStore() throws -> Store {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        modelContext.insert(context)
        modelContext.insert(area)
        try modelContext.save()

        return Store(container: container, modelContext: modelContext, area: area)
    }

    /// One press of the sheet's primary button, in the fields `save()` actually passes: the goal it
    /// is writing to (`targetGoal`) first, and the live `allGoals` the `@Query` would hold.
    @discardableResult
    private func press(_ goal: Goal?, in store: Store) throws -> Goal? {
        try CadenceTrackingMutationSupport.saveGoal(
            goal,
            title: "Ship the thing",
            desc: "",
            startDate: "2026-09-20",
            endDate: "2026-10-20",
            progressType: goal?.progressType ?? .subtasks,
            targetHours: goal?.targetHours ?? 0,
            icon: "flag.fill",
            colorHex: Theme.blueHex,
            kind: .completable,
            status: .active,
            context: nil,
            parentGoal: nil,
            allGoals: try store.modelContext.fetch(FetchDescriptor<Goal>()),
            modelContext: store.modelContext
        )
    }

    // MARK: - The second-goal hazard, run forwards

    /// **The load-bearing one**, and it runs the sheet's two presses in the sheet's own order: the
    /// goal commits, the seeded attach is refused, and the retry press re-enters `saveGoal` with
    /// the goal the sheet is holding before re-trying the attach. One goal in the store at the end,
    /// and one link.
    ///
    /// **No assertion here about `goal.listLinks` between the two presses.** Measured on this
    /// machine (Xcode 27, 2026-09-20): after the refused attach the array still holds the
    /// pending-*deleted* link until something processes pending changes, so its count is a
    /// toolchain answer of exactly the kind [[T-1296]] says not to pin — and it is the subject of
    /// [[T-1306]], filed out of this work, rather than of this ticket. What is pinned instead is
    /// what the store holds, which no framework timing can move.
    @Test func theRetryAfterARefusedAttachEditsTheHeldGoalAndDoesNotInsertASecond() throws {
        let store = try makeStore()

        // Press one: the goal commits, and `save()` writes it to `createdGoal` here.
        let created = try #require(try press(nil, in: store))
        #expect(try ModelContext(store.container).fetch(FetchDescriptor<Goal>()).count == 1)

        // …and the list the composer seeded is refused.
        #expect(throws: CommitRefused.self) {
            try store.modelContext.attachList(.area(store.area), to: created, commit: Self.refuse)
        }

        // Press two — the retry, which is an edit of the held goal followed by the attach again.
        let retried = try #require(try press(created, in: store))
        #expect(retried === created, "the retry wrote to a different goal object")
        try store.modelContext.attachList(.area(store.area), to: created)
        #expect(!store.modelContext.hasChanges, "the default commit left the attach pending")

        let reader = ModelContext(store.container)
        #expect(
            try reader.fetch(FetchDescriptor<Goal>()).count == 1,
            "the retry inserted a second goal for one gesture"
        )
        #expect(
            try reader.fetch(FetchDescriptor<GoalListLink>()).count == 1,
            "the retried attach committed nothing, or committed twice"
        )
        #expect(GoalLinkPresentation.links(of: created).count == 1)
    }

    /// The other half of a refused attach, in [[T-1295]]'s shape: this app has one `ModelContext`,
    /// so the refusal must leave nothing for the next unrelated `save()` — from any screen — to
    /// commit. Run forwards, and read from a second context, so it depends on no framework timing.
    @Test func arefusedInitialAttachLeavesNothingForTheNextSaveToCommit() throws {
        let store = try makeStore()
        let created = try #require(try press(nil, in: store))

        #expect(throws: CommitRefused.self) {
            try store.modelContext.attachList(.area(store.area), to: created, commit: Self.refuse)
        }

        try store.modelContext.save()

        let reader = ModelContext(store.container)
        #expect(try reader.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(
            try reader.fetch(FetchDescriptor<Goal>()).count == 1,
            "the goal the sheet is holding is not in the store, so its sentence is false"
        )
    }

    /// The negative control, and the reason the scan below is about one argument. Handing
    /// `saveGoal` the `nil` that `editingGoal` holds on the create path — the sheet as it stood
    /// before [[T-1302]], kept open — really does make the second goal.
    @Test func theSameRetryWithNilInsteadOfTheHeldGoalIsWhatMakesTheSecondGoal() throws {
        let store = try makeStore()

        let created = try #require(try press(nil, in: store))
        #expect(throws: CommitRefused.self) {
            try store.modelContext.attachList(.area(store.area), to: created, commit: Self.refuse)
        }

        let second = try #require(try press(nil, in: store))
        #expect(second !== created)
        #expect(
            try ModelContext(store.container).fetch(FetchDescriptor<Goal>()).count == 2,
            "non-vacuity: the first argument is what decides, so pinning it is not decoration"
        )
    }

    // MARK: - The sheet's wiring

    /// **Source shape, and the claim the behavioural half cannot make:** `save()` writes to the
    /// goal the sheet is *holding*, and takes hold of it **before** the attach that can refuse.
    /// Either half backed out is a second goal on the second press.
    @Test func theSheetRetriesIntoTheGoalItIsHoldingRatherThanCreatingASecond() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned(Self.sheetPath)
        let save = try CadenceCommitSurfaceScan.declarationBody(named: "save", in: sheet)

        #expect(CadenceSourceScan.matchCount(#"saveGoal\(\s*targetGoal,"#, in: save) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"saveGoal\(\s*editingGoal,"#, in: save) == 0,
            "save() creates again on the second press"
        )
        #expect(
            CadenceSourceScan.matchCount(#"private var targetGoal: Goal\? \{\s*createdGoal \?\? editingGoal\s*\}"#, in: sheet) == 1
        )

        let held = try #require(save.range(of: "createdGoal = saved"))
        let attach = try #require(save.range(of: "attachInitialList(to: saved)"))
        #expect(
            held.upperBound < attach.lowerBound,
            "the goal is taken hold of only after the attach could already have failed"
        )
    }

    /// **Source shape.** The refusal is said out loud rather than swallowed: the attach throws, the
    /// sentence is the one written for this event, and `dismiss()` is below the failure branch so
    /// the sheet stays open on the **Initial Linked List** field the sentence is about.
    @Test func arefusedInitialAttachNamesItselfInsteadOfClosingTheSheet() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned(Self.sheetPath)
        let save = try CadenceCommitSurfaceScan.declarationBody(named: "save", in: sheet)
        let attach = try CadenceCommitSurfaceScan.declarationBody(named: "attachInitialList", in: sheet)

        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: attach) == 0,
            "the seeded attach still swallows its refusal"
        )
        #expect(attach.contains("try modelContext.attachList(target, to: goal)"))
        #expect(
            CadenceSourceScan.matchCount(#"saveError = GoalLinkPresentation\.initialAttachFailureNotice"#, in: save) == 1
        )
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: save),
            "the sheet closes above its failure branch"
        )
        #expect(sheet.contains("if let saveError {"), "the sheet sets a notice it never draws")

        // The button beside the sentence says what is left to do, and the one next to it stops
        // offering to cancel a goal the store is holding.
        #expect(CadenceSourceScan.matchCount(#"if createdGoal != nil \{ return "Retry" \}"#, in: sheet) == 1)
        #expect(sheet.contains(#"title: createdGoal == nil ? "Cancel" : "Close""#))
    }

    /// The sentence itself, and why it is a third one rather than either of the two this repository
    /// already had: the goal **was** committed, so "Nothing was changed." denies it and
    /// `goalSaveFailureNotice` denies it the other way round — the second would send the user back
    /// to press Create for a goal that already exists.
    @Test func theInitialAttachNoticeStatesBothHalvesAndDeniesNeither() {
        let notice = GoalLinkPresentation.initialAttachFailureNotice

        #expect(notice == "Goal saved, but couldn't attach the list. Try again, or attach it from the goal.")
        #expect(!notice.contains("Nothing was changed."))
        #expect(notice != GoalLinkPresentation.changeFailureNotice)
        #expect(notice != CadenceTrackingMutationSupport.goalSaveFailureNotice)
    }

    /// **Source shape.** Holding a created goal must not turn the sheet into an editor: `isEditing`
    /// still asks only whether the sheet was *opened* on a goal, so the Delete button, the Status
    /// section and the Initial Linked List field do not change under the user because an attach was
    /// refused. The count is the assertion — `createdGoal` may be read by the Cancel/Close title in
    /// `body` and by nothing else there.
    @Test func holdingACreatedGoalDoesNotTurnTheSheetIntoAnEditor() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned(Self.sheetPath)

        #expect(
            CadenceSourceScan.matchCount(#"private var isEditing: Bool \{\s*editingGoal != nil\s*\}"#, in: sheet) == 1,
            "isEditing now flips when the sheet is merely holding a goal"
        )

        let body = try cadenceFunctionBody("var body: some View", in: sheet)
        #expect(CadenceSourceScan.matchCount(#"if isEditing \{"#, in: body) == 2)
        #expect(body.contains(#"fieldGroup("Status")"#))
        #expect(body.contains(#"fieldGroup("Initial Linked List")"#))
        #expect(body.contains(#"title: "Delete""#))
        #expect(
            CadenceSourceScan.matchCount(#"\bcreatedGoal\b"#, in: body) == 1,
            "a second control in the sheet now changes when an attach is refused"
        )
        #expect(body.contains(#"title: createdGoal == nil ? "Cancel" : "Close""#))
    }

    // MARK: - Non-vacuity

    /// The scans above read real Swift, the stripper discriminates on this file, and the ordering
    /// helper answers differently for the two orders — the three ways a green scan means nothing.
    @Test func thecreateGoalInitialAttachScansReadRealSource() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.sheetPath)
        #expect(raw.contains("struct CreateGoalSheet: View"))
        #expect(CadenceSourceScan.strippingComments(raw) != raw)

        let save = try CadenceCommitSurfaceScan.declarationBody(
            named: "save",
            in: CadenceSourceScan.strippingComments(raw)
        )
        #expect(save.contains("do {"))

        #expect(CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: "do { } catch { } dismiss()"))
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: "dismiss() ; do { } catch { }"))
    }
}
