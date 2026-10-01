#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The commit the drop path makes, counted, and refusable on demand.
///
/// The same reason `CountingBoardEventDaySource` exists one surface over (T-1570): a count taken
/// against the shipping object alone is worth nothing, because an in-memory container cannot be
/// made to refuse a `save()` and every reading would come out the same whether the path commits
/// once, twice, or never. `commit:` is the seam — it is on `assignTask` for exactly this reason —
/// and the two configurations below are this file's authorised/unauthorised pair: one takes the
/// write, one refuses it, and no assertion here is worth anything unless the two readings differ.
private final class CountingDropCommit {
    /// What the store answers. `true` is the refusal that cannot be provoked any other way.
    var refuses = false

    private(set) var commitCount = 0

    struct Refused: Error {}

    /// Handed to `assignTask(commit:)`.
    func commit(_ modelContext: ModelContext) throws {
        commitCount += 1
        if refuses { throw Refused() }
        try modelContext.save()
    }
}

/// **[[T-1580]] — All Tasks' and Today's drop path reported success over a commit it could not see
/// refused, and it committed the halves of a compound drop separately.**
///
/// The question came out of [[T-1501]], which left `TasksListView.dropCoordinator` as the page's
/// second whole-store derivation per render because parameterising it tripped
/// `CadenceSaveCommitDisciplineTests.noSuccessReportFollowsACommitSwallowedOneFrameDown`. **The
/// sweep was asking a real question and the answer is yes:** `TasksPanelSupport.assignTask` ended
/// `try? modelContext.save(); return true`, and that `true` is what `.dropDestination` reads to
/// decide whether the row stays where it was dropped. A refused list move was accepted, drawn in
/// its new section, and reverted at the next launch with nothing to retry — the [[T-566]] shape,
/// one screen over from the reorder half [[T-868]] fixed on this same coordinator.
///
/// **The second half is the one no `Bool` could have carried.** A drop key is compound —
/// `list:p_<uuid>|date:today` — and the date half committed *itself*, through
/// `CadenceTaskMutationSupport.setScheduledDate`'s own swallowed save, before the list half was
/// ever offered to the store. So a drop was two commits with no undo between them, and
/// `theOldExpressionCommittedTheDateHalfWhereNoUndoCouldReachIt` below runs the pre-ticket
/// expression verbatim to show it landing in a second `ModelContext` that the refused shipping
/// path leaves untouched.
///
/// **Counts and relations only, never a duration** (CI runs Xcode 26, this Mac 27 — T-1279/T-1296).
@MainActor
struct TasksListDropCommitRateTests {

    private static let todayKey = DateFormatters.todayKey()

    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    /// A task already in the store, so every write below is an in-place edit and not an insert.
    private func seeded(in modelContext: ModelContext) throws -> (AppTask, Project) {
        let project = Project(name: "Website")
        let task = AppTask(title: "Draft")
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()
        return (task, project)
    }

    /// One drop on a section header, through the call `TasksPanelDropCoordinator` makes.
    @discardableResult
    private func drop(
        _ task: AppTask,
        onKey dropKey: String,
        projects: [Project],
        in modelContext: ModelContext,
        commit: CountingDropCommit
    ) -> TasksPanelDropOutcome {
        TasksPanelSupport.assignTask(
            task,
            for: dropKey,
            todayKey: Self.todayKey,
            areas: [],
            projects: projects,
            modelContext: modelContext,
            reconciler: .inert,
            commit: commit.commit
        )
    }

    /// The expression `TasksPanelSupport.assignTask` **held before this ticket**, written out.
    ///
    /// Nothing here models the old decision; it is the old body — the same parse through
    /// `dropAssignments(forDropKey:)`, the same four writes, the same date edit left to
    /// `CadenceTaskDateEditing`'s defaulted (and then swallowed) commit, and the same
    /// `try? modelContext.save(); return true` at the end. It takes no `commit:` because the old
    /// one had none to take, which is the whole of what the counting object reads as zero.
    @discardableResult
    private func dropThroughThePreTicketExpression(
        _ task: AppTask,
        onKey dropKey: String,
        projects: [Project],
        in modelContext: ModelContext
    ) -> Bool {
        var applied = false
        for assignment in TasksPanelSupport.dropAssignments(forDropKey: dropKey) {
            switch assignment {
            case .inbox:
                task.area = nil
                task.project = nil
                task.context = nil
                applied = true
            case .area:
                continue
            case .project(let projectID):
                guard let target = projects.first(where: { $0.id == projectID }) else { continue }
                task.project = target
                task.area = nil
                task.context = target.resolvedContext
                applied = true
            case .scheduleToday:
                CadenceTaskDateEditing.setScheduledDate(
                    Self.todayKey,
                    for: task,
                    in: modelContext,
                    reconciler: .inert
                )
                applied = true
            case .pushToScheduled, .clearSchedule:
                continue
            case .priority(let priority):
                task.priority = priority
                applied = true
            }
        }
        guard applied else { return false }
        try? modelContext.save()
        return true
    }

    // MARK: - The denominator, first

    /// **What makes every number below mean anything.** One drop on a header whose list is there
    /// reaches the commit exactly once and answers `.applied`; the identical drop on a header whose
    /// list is gone reaches it **zero** times and answers `.resolvedNothing`.
    ///
    /// The zero is not a hypothetical control. It is what a count written against a path that
    /// silently did nothing would read no matter what the code did — and it is also the behaviour
    /// the ticket requires, because a key that resolves to nothing must not commit the unrelated
    /// pending work the app's single `ModelContext` is holding. The two numbers must differ or
    /// nothing in this file is measuring a commit.
    @Test("The counted commit is the one a section drop makes, and an unresolvable key reads zero")
    func theCountedDropCommitIsTheOneTheAllTasksDropPathMakes() throws {
        let (_, modelContext) = try store()
        let (task, project) = try seeded(in: modelContext)

        let live = CountingDropCommit()
        let landed = drop(task, onKey: "list:p_\(project.id.uuidString)", projects: [project], in: modelContext, commit: live)

        #expect(landed == .applied)
        #expect(live.commitCount == 1, "a resolvable drop committed \(live.commitCount) times, not once")
        #expect(task.project?.id == project.id)

        let (_, otherContext) = try store()
        let (stranger, goneList) = try seeded(in: otherContext)
        let unresolvable = CountingDropCommit()
        let nothing = drop(
            stranger,
            onKey: "list:p_\(UUID().uuidString)",
            projects: [goneList],
            in: otherContext,
            commit: unresolvable
        )

        #expect(nothing == .resolvedNothing)
        #expect(
            unresolvable.commitCount == 0,
            """
            a key naming a list that is gone committed \(unresolvable.commitCount) times. At any \
            number other than 0 the control is not the vacuous reading it is here to name.
            """
        )
        #expect(stranger.project == nil)
        #expect(
            live.commitCount != unresolvable.commitCount,
            "both readings came out \(live.commitCount); this file measures nothing"
        )
        #expect(landed != nothing, "both drops answered \(landed); this file measures nothing")
    }

    // MARK: - The report the ticket is about

    /// **A refused drop answers `.refused`, and "nothing was changed" is true when it does.**
    ///
    /// Both halves, because either alone is satisfiable by a path that does nothing: the fields are
    /// back where they were *and* a second `ModelContext` over the same container — the store, not
    /// the live object — has never heard of the move. The control is the same drop over the same
    /// fixture with the commit taking it, which must come out the other way in both.
    @Test("A refused section drop answers refused, puts the fields back, and reaches the store with nothing")
    func aRefusedListDropLeavesNothingInTheStoreAndSaysSo() throws {
        let (container, modelContext) = try store()
        let (task, project) = try seeded(in: modelContext)

        let refusing = CountingDropCommit()
        refusing.refuses = true
        let refused = drop(task, onKey: "list:p_\(project.id.uuidString)", projects: [project], in: modelContext, commit: refusing)

        #expect(refused == .refused)
        #expect(refusing.commitCount == 1, "the refused drop never reached the commit")
        #expect(task.project == nil, "the field kept a value the store refused")
        #expect(task.context == nil)
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first?.project == nil,
            "the store took a move it had refused"
        )

        // The control, over a fresh fixture: the identical drop with the commit taking it lands in
        // that same second context. Without this, "the store holds nothing" is true of any path.
        let (takingContainer, takingContext) = try store()
        let (other, otherProject) = try seeded(in: takingContext)
        let taking = CountingDropCommit()
        let applied = drop(other, onKey: "list:p_\(otherProject.id.uuidString)", projects: [otherProject], in: takingContext, commit: taking)

        #expect(applied == .applied)
        #expect(taking.commitCount == refusing.commitCount, "the two paths did not make the same number of commits")
        #expect(
            try ModelContext(takingContainer).fetch(FetchDescriptor<AppTask>()).first?.project?.id == otherProject.id,
            "the taking control did not land either, so the refusal above proves nothing"
        )
        #expect(applied != refused)
    }

    /// **One commit per drop, not one per assignment** — the relation, not a magic number.
    ///
    /// A Today list header hands out `list:p_<uuid>|date:today`: two assignments, one gesture. The
    /// date half used to commit itself and the list half followed with a second save, so the drop
    /// had no single point at which it could be refused as a whole. Six drops are six commits, and
    /// the assignment count is read from the parse rather than typed here, so a key vocabulary that
    /// grows a third part does not quietly make this test a tautology.
    @Test("A compound drop key commits once, and six drops are six commits")
    func aCompoundDropKeyCommitsOnceAndNotOncePerAssignment() throws {
        let (_, modelContext) = try store()
        let (task, project) = try seeded(in: modelContext)
        let dropKey = "list:p_\(project.id.uuidString)\(CadenceTaskDropSupport.separator)date:today"

        let assignments = TasksPanelSupport.dropAssignments(forDropKey: dropKey)
        #expect(assignments.count == 2, "the compound key parsed to \(assignments.count) assignments, not 2")

        let commit = CountingDropCommit()
        #expect(drop(task, onKey: dropKey, projects: [project], in: modelContext, commit: commit) == .applied)
        #expect(commit.commitCount == 1, "one compound drop made \(commit.commitCount) commits, not 1")
        #expect(task.project?.id == project.id)
        #expect(task.scheduledDate == Self.todayKey, "both halves of the key must still land")

        for _ in 0..<5 {
            #expect(drop(task, onKey: dropKey, projects: [project], in: modelContext, commit: commit) == .applied)
        }
        #expect(commit.commitCount == 6, "six drops made \(commit.commitCount) commits")
        #expect(
            commit.commitCount < assignments.count * 6,
            "the commit count followed the assignments rather than the drops"
        )
    }

    /// **The before and the after, over one fixture each, through two code paths that differ in
    /// exactly the thing that changed.**
    ///
    /// The pre-ticket expression reports `true` and the date it wrote is in the store — committed
    /// by `CadenceTaskMutationSupport.setScheduledDate`'s own swallowed save, inside the drop,
    /// where no later refusal could undo it. The shipping path over the same compound key with the
    /// commit refusing answers `.refused`, and the second `ModelContext` has neither half.
    ///
    /// The counting object reads **zero** against the old expression, which is not a bug in the
    /// control: the old expression had no `commit:` to hand it. That is the defect stated as a
    /// reading.
    @Test("The pre-T-1580 expression commits the date half where no undo can reach it")
    func theOldExpressionCommittedTheDateHalfWhereNoUndoCouldReachIt() throws {
        let (oldContainer, oldContext) = try store()
        let (oldTask, oldProject) = try seeded(in: oldContext)
        let oldKey = "list:p_\(oldProject.id.uuidString)\(CadenceTaskDropSupport.separator)date:today"
        let unreachable = CountingDropCommit()

        #expect(dropThroughThePreTicketExpression(oldTask, onKey: oldKey, projects: [oldProject], in: oldContext))
        #expect(
            unreachable.commitCount == 0,
            "the old expression reached an injected commit \(unreachable.commitCount) times — it had none"
        )
        let oldStored = try ModelContext(oldContainer).fetch(FetchDescriptor<AppTask>()).first
        #expect(oldStored?.scheduledDate == Self.todayKey, "the old path's date half did not reach the store")
        #expect(oldStored?.project?.id == oldProject.id)

        let (newContainer, newContext) = try store()
        let (newTask, newProject) = try seeded(in: newContext)
        let newKey = "list:p_\(newProject.id.uuidString)\(CadenceTaskDropSupport.separator)date:today"
        let refusing = CountingDropCommit()
        refusing.refuses = true

        #expect(drop(newTask, onKey: newKey, projects: [newProject], in: newContext, commit: refusing) == .refused)
        #expect(refusing.commitCount == 1)
        #expect(newTask.scheduledDate.isEmpty, "the date half survived the undo")
        #expect(newTask.project == nil, "the list half survived the undo")
        let newStored = try ModelContext(newContainer).fetch(FetchDescriptor<AppTask>()).first
        #expect(newStored?.scheduledDate.isEmpty == true, "the refused drop's date half is in the store")
        #expect(newStored?.project == nil)
        #expect(
            oldStored?.scheduledDate != newStored?.scheduledDate,
            "both paths left the store in the same state; this comparison measures nothing"
        )
    }

    // MARK: - What the two surfaces draw

    /// Both macOS drop surfaces map the three outcomes the same way, and the sentence they show is
    /// the one whose "Nothing was changed" the undo has already made true.
    ///
    /// Source shape rather than behaviour because the mapping lives in a SwiftUI `@State` write,
    /// and the pair is what matters: a page that returned `outcome == .applied` without naming the
    /// refusal would pass every behavioural assertion above.
    @Test("Both drop surfaces answer only for an applied drop and name a refused one")
    func everyAllTasksDropSurfaceNamesARefusedAssignmentInTheUndoneSentence() throws {
        #expect(CadencePendingChangePersistence.editFailureNotice == "Couldn't save these changes. Nothing was changed.")

        var read = 0
        for path in ["Cadence/macOS/Views/TasksListView.swift", "Cadence/macOS/Views/TasksPanel.swift"] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("struct"), "\(path) read as nothing, so nothing below is a reading")
            #expect(
                source.contains("reorderFailureNotice = outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil"),
                "\(path) does not name and clear a refused assignment in one expression"
            )
            #expect(
                source.contains("return outcome == .applied"),
                "\(path) reports a drop the store did not take"
            )
            read += 1
        }
        #expect(read == 2, "expected two macOS drop surfaces, read \(read)")

        // And the swallow the ticket is about is gone from the unit that held it.
        let support = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSupport.swift")
        )
        #expect(support.contains("static func assignTask("), "the reader missed the declaration it is about")
        #expect(!support.contains("try? modelContext.save()"), "TasksPanelSupport swallows a commit again")
        #expect(support.contains("CadenceTaskFieldEditCommit.commit("))
    }

    // MARK: - The render cost the answer unblocked

    /// **The smaller half, and it follows for free:** `dropCoordinator` takes the universe now, so
    /// one body evaluation of `TasksListView` derives the whole store **once** where it derived it
    /// seven times before T-1501 and twice after it.
    ///
    /// The walk carries its own denominator: with the deferred-closure rule off it finds *more*
    /// references to the same property — the two `revealsCompletedSection` names inside `.onAppear`
    /// and `.onChange`, which cost a render nothing. A scan that had simply stopped reading would
    /// come out `0` both times, which is the reading this pair refuses to be.
    @Test("One body evaluation of the All Tasks list derives the task store once")
    func theAllTasksListDerivesItsUniverseOnceAndTheWalkThatCountedItStillFindsThings() throws {
        let declarations = [
            "body": "var body: some View",
            "visibleTaskUniverse": "var visibleTaskUniverse",
            "naturalActiveTasks": "func naturalActiveTasks(",
            "completedTasks": "func completedTasks(",
            "completedTaskCount": "func completedTaskCount(",
            "dropCoordinator": "func dropCoordinator(",
            "revealsCompletedSection": "var revealsCompletedSection",
            "isEmptyPage": "func isEmptyPage("
        ]
        let file = "Cadence/macOS/Views/TasksListView.swift"
        let rendered = try TaskSurfaceDerivationScan.graph(file: file, declarations: declarations)
        #expect(rendered.missing.isEmpty, "the census could not find: \(rendered.missing)")

        let perRender = rendered.reach(to: "visibleTaskUniverse")
        #expect(perRender == .init(fixed: 1, perElement: 0), "All Tasks (list) universe passes: \(perRender)")

        let stored = try TaskSurfaceDerivationScan
            .graph(file: file, declarations: declarations, stripDeferred: false)
            .reach(to: "visibleTaskUniverse")
        #expect(
            stored.fixed > perRender.fixed,
            "the unstripped walk found \(stored) — it is reading nothing, so the \(perRender) above is not a count"
        )
        // The body builds the coordinator from the universe it already bound, rather than from a
        // second derivation of its own.
        let body = try #require(rendered.split["body"]).fixed
        #expect(body.contains("let coordinator = dropCoordinator(in: universe)"))
    }
}
#endif
