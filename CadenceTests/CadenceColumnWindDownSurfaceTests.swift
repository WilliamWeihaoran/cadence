import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-247, the sibling of T-215 one level down. macOS's `KanbanSectionColumnView` has always called
/// `TaskContainerLifecycleService` when a kanban column is archived (cancel) or completed (done);
/// iOS wrote those two flags onto a `CadenceSectionDraft` in the list editor and saved them with
/// every other edit in the sheet, settling nothing. So the same column left different open work
/// behind depending on which device the board was on.
///
/// **A column is not a model**, which is what makes "the tasks in this column" a query rather than
/// a relationship: it is a `TaskSectionConfig` value JSON-encoded into `sectionConfigsRaw`, and
/// `AppTask.sectionName` is a plain string pointing at one. Half of these tests are about that
/// query being the same array the confirmation counts.
///
/// The other half are source-text assertions, for the reason `CadenceListWindDownSurfaceTests`
/// records: `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS, so
/// there is no iOS symbol to reference. They strip comments rather than allowlist, count exactly
/// rather than "contains", and end in a non-vacuity test.
@MainActor
struct CadenceColumnWindDownSurfaceTests {

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func task(_ title: String, section: String, status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = section
        task.status = status
        if status == .done || status == .cancelled {
            task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        }
        return task
    }

    /// An area holding `tasks`, with `Doing` and `Later` configured as columns.
    private func board(_ tasks: [AppTask], in context: ModelContext) -> Area {
        let area = Area(name: "Board")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "Later")
        ]
        context.insert(area)
        for task in tasks {
            task.area = area
            context.insert(task)
        }
        area.tasks = tasks
        return area
    }

    // MARK: - What the confirmation promises

    /// The count is the settle's own array, scoped to the one column: other columns are untouched,
    /// already-settled work is excluded, and the number is a promise about exactly which rows change.
    @Test func theColumnSummaryCountsExactlyWhatTheWindDownWillSettle() throws {
        let context = ModelContext(try container())
        let open = task("open", section: "Doing")
        let inProgress = task("in progress", section: "Doing", status: .inProgress)
        let alreadyDone = task("already done", section: "Doing", status: .done)
        let alreadyCancelled = task("already cancelled", section: "Doing", status: .cancelled)
        let elsewhere = task("elsewhere", section: "Later")
        let area = board([open, inProgress, alreadyDone, alreadyCancelled, elsewhere], in: context)
        try context.save()

        let column = area.sectionConfigs.first { $0.name == "Doing" }!
        let summary = CadenceContainerWindDownSummary.forColumn(column, area: area, project: nil, outcome: .cancelled)
        #expect(summary.openTasks == 2)
        #expect(summary.requiresConfirmation)
        #expect(summary.settledLine == "2 open tasks will be canceled")

        TaskContainerLifecycleService.cancelRemainingActiveTasks(in: column, area: area, project: nil, in: context)

        #expect([open, inProgress].map(\.isCancelled) == [true, true])
        #expect(alreadyDone.status == .done)
        #expect(alreadyCancelled.status == .cancelled)
        #expect(elsewhere.status == .todo)
        #expect(
            CadenceContainerWindDownSummary
                .forColumn(column, area: area, project: nil, outcome: .cancelled)
                .openTasks == 0
        )
    }

    /// A task that never named a section resolves to Default, so it belongs to the Default column's
    /// number rather than to nobody's. This is the `resolvedSectionName` half of "the tasks in this
    /// column" — get it wrong and archiving Default promises 0 and settles 3, or promises 3 and
    /// settles 0.
    @Test func aTaskWithNoSectionIsCountedInTheDefaultColumn() throws {
        let context = ModelContext(try container())
        let unfiled = task("unfiled", section: "")
        let named = task("named", section: "Doing")
        let area = board([unfiled, named], in: context)
        try context.save()

        let defaultColumn = area.sectionConfigs.first { $0.name == TaskSectionDefaults.defaultName }!
        let promised = TaskContainerLifecycleService.remainingActiveTasks(in: defaultColumn, area: area, project: nil)
        #expect(promised.map(\.title) == ["unfiled"])

        TaskContainerLifecycleService.cancelRemainingActiveTasks(in: defaultColumn, area: area, project: nil, in: context)
        #expect(unfiled.isCancelled)
        #expect(named.status == .todo)
    }

    /// Both directions settle, and the sentence names which. A confirmation that said "canceled"
    /// over an action that marks work done would be the one thing this type exists to prevent.
    @Test func completingAColumnMarksItsWorkDoneAndArchivingCancelsIt() throws {
        let context = ModelContext(try container())
        let finished = task("to finish", section: "Doing")
        let abandoned = task("to abandon", section: "Later")
        let area = board([finished, abandoned], in: context)
        try context.save()

        let doing = area.sectionConfigs.first { $0.name == "Doing" }!
        let later = area.sectionConfigs.first { $0.name == "Later" }!

        #expect(
            CadenceContainerWindDownSummary
                .forColumn(doing, area: area, project: nil, outcome: .done)
                .settledLine == "1 open task will be marked done"
        )
        #expect(
            CadenceContainerWindDownSummary
                .forColumn(later, area: area, project: nil, outcome: .cancelled)
                .settledLine == "1 open task will be canceled"
        )

        TaskContainerLifecycleService.completeRemainingActiveTasks(in: doing, area: area, project: nil, in: context)
        TaskContainerLifecycleService.cancelRemainingActiveTasks(in: later, area: area, project: nil, in: context)

        #expect(finished.isDone)
        #expect(abandoned.isCancelled)
        #expect(finished.completedAt != nil)
        #expect(abandoned.completedAt != nil)
    }

    /// A column with nothing open in it asks nothing, which is why the confirmation can be taken
    /// seriously on the columns that do ask.
    @Test func anEmptyColumnRequiresNoConfirmation() throws {
        let context = ModelContext(try container())
        let settled = task("done", section: "Doing", status: .done)
        let area = board([settled], in: context)
        try context.save()

        let doing = area.sectionConfigs.first { $0.name == "Doing" }!
        let summary = CadenceContainerWindDownSummary.forColumn(doing, area: area, project: nil, outcome: .cancelled)
        #expect(summary.isEmpty)
        #expect(!summary.requiresConfirmation)
        #expect(summary.settledLine == nil)
    }

    /// **The Default column cannot be wound down, and the model is what says so.**
    /// `normalizedSectionConfigs` forces `isCompleted` and `isArchived` false on it on every read
    /// and every write. So an action offered there would state a count, cancel or finish every task
    /// in the column, and leave the column visibly Active — which is why `lifecycle(for:)` hands
    /// that row `nil` and macOS gates its own Archive item on `!section.isDefault`.
    @Test func theModelDiscardsALifecycleFlagWrittenOntoTheDefaultColumn() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName, isCompleted: true, isArchived: true),
            TaskSectionConfig(name: "Doing", isCompleted: true, isArchived: true)
        ]
        try context.save()

        let stored = area.sectionConfigs
        let defaultColumn = stored.first { $0.isDefault }
        #expect(defaultColumn?.isArchived == false)
        #expect(defaultColumn?.isCompleted == false)

        // And the control: a non-default column keeps both, so the assertion above is about
        // `Default` rather than about the setter dropping flags generally.
        let doing = stored.first { $0.name == "Doing" }
        #expect(doing?.isArchived == true)
        #expect(doing?.isCompleted == true)
    }

    /// **T-212/T-213's invariant, on the surface T-247 is about.** `markDone` / `markCancelled`
    /// spawn the next occurrence, and `makeNextRecurringTask` copies `area`, `project` *and*
    /// `sectionName` — so a column wind-down routed through either would refill the column it just
    /// archived. The control at the end is the point: the same task, cancelled the single-task way,
    /// does mint a successor, so the first assertion cannot be passing because the recurrence was
    /// never configured.
    @Test func aColumnWindDownDoesNotRefillTheColumnItJustArchived() throws {
        let context = ModelContext(try container())
        let recurring = task("standup", section: "Doing")
        recurring.recurrenceRule = .daily
        recurring.scheduledDate = DateFormatters.todayKey()
        let area = board([recurring], in: context)
        try context.save()

        let doing = area.sectionConfigs.first { $0.name == "Doing" }!
        TaskContainerLifecycleService.cancelRemainingActiveTasks(in: doing, area: area, project: nil, in: context)
        try context.save()

        #expect(recurring.isCancelled)
        #expect(recurring.recurrenceSpawnedTaskID == nil)
        let afterWindDown = try context.fetch(FetchDescriptor<AppTask>())
        #expect(afterWindDown.count == 1)

        // Control: the single-task transition on an identical task does spawn one.
        let control = task("standup control", section: "Doing")
        control.recurrenceRule = .daily
        control.scheduledDate = DateFormatters.todayKey()
        control.area = area
        context.insert(control)
        area.tasks = (area.tasks ?? []) + [control]
        try context.save()

        CadenceTaskRecurrenceWorkflowSupport.markCancelled(control, in: context)
        try context.save()

        #expect(control.recurrenceSpawnedTaskID != nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 3)
    }

    // MARK: - iOS reaches it, from one place

    /// The literal T-247 bug is that iOS never called the service at all. One call per direction,
    /// from the one file that owns the mutation — and none from the editor, which asks rather than
    /// settles.
    @Test func iOSWindsDownAColumnThroughTheSharedServiceFromOnePlaceOnly() throws {
        try expectCallSites(of: "TaskContainerLifecycleService.cancelRemainingActiveTasks", at: [
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListEditorViews.swift": 0
        ])
        try expectCallSites(of: "TaskContainerLifecycleService.completeRemainingActiveTasks", at: [
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListEditorViews.swift": 0
        ])

        // `windDownColumn` is declared once and reached once: the editor's single apply path, which
        // both the immediate and the confirmed route run.
        try expectOccurrences(of: "windDownColumn(", at: [
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListEditorViews.swift": 1
        ])

        // Nowhere on iOS is a column's lifecycle a *binding* on a draft. That is the ticket's
        // shape half stated as a sweep: `Toggle(isOn: $draft.isArchived)` is the bug, and it is the
        // `$` that makes it one — `applyColumnWindDown` writes `draft.isArchived` unprefixed to
        // keep the row in step with a flag already committed to the model.
        //
        // **The needle has no witness in this corpus and cannot have one** (T-553): every file the
        // sweep reads is required *not* to contain it, and it is spelled nowhere else in the
        // repository either, so a typo in it would empty the sweep in perfect silence. The
        // instrument is what supplies the missing witness — its two literal fixtures are checked
        // when it is built, so a detector that has stopped discriminating cannot reach the walk at
        // all. The negative fixture is the nearest neighbour on purpose: the same two flags,
        // written the way `applyColumnWindDown` writes them, beside a `$draft.` binding that is
        // legitimate.
        let draftsALifecycleFlag = try CadenceScanInstrument(
            "a column lifecycle flag bound as a draft",
            fires: """
            Toggle("Archived", isOn: $draft.isArchived)
            Toggle("Completed", isOn: $draft.isCompleted)
            """,
            andNotOn: """
            TextField("Column name", text: $draft.name)
            case .archive: draft.isArchived = true
            case .complete: draft.isCompleted = true
            """,
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                return code.contains("$draft.isArchived") || code.contains("$draft.isCompleted")
            }
        )

        let offenders = try draftsALifecycleFlag.sweep(
            try swiftFiles(under: "Cadence/iOS"),
            // 105 files when this was written; a walk that collapses is how an absence sweep
            // passes forever.
            atLeast: 80,
            including: "Cadence/iOS/iOSListEditorViews.swift",
            read: sourceFile
        )
        #expect(
            offenders.isEmpty,
            "column lifecycle flag(s) bound as a draft in: \(offenders.joined(separator: ", "))"
        )
    }

    /// The shape half of the ticket. The two `Toggle`s are gone, the decision is asked once, and it
    /// is asked by the editor rather than by the row — so a second column surface cannot come to
    /// ask a different question.
    @Test func theListEditorAsksTheDecisionOnceAndDraftsNeitherFlag() throws {
        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(!editor.contains("Toggle(\"Completed\""))
        #expect(!editor.contains("Toggle(\"Archived\""))

        // Two since [[T-8562]]: the column's decision, and the whole list's for the editor's own
        // Status / Archive rows -- each asked once, neither by a row.
        try expectOccurrences(of: "requiresConfirmation", at: [
            "Cadence/iOS/iOSListEditorViews.swift": 2,
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 0
        ])

        // One confirmation, built in one place, and it is the same sheet the list archive uses.
        try expectCallSites(of: "iOSWindDownConfirmationSheet", at: [
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListEditorViews.swift": 0
        ])
    }

    /// The other direction of the same divergence. macOS's two column branches are what iOS was
    /// measured against, so closing T-247 by *removing* the Mac's wind-down would satisfy every
    /// assertion above and be the wrong fix.
    @Test func macOSStillWindsDownAColumnOnArchiveAndOnCompletion() throws {
        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        #expect(column.components(separatedBy: "TaskContainerLifecycleService.cancelRemainingActiveTasks(").count - 1 == 2)
        #expect(column.components(separatedBy: "TaskContainerLifecycleService.completeRemainingActiveTasks(").count - 1 == 1)
    }

    // MARK: - T-15661 / T-15662: the Mac column settles and asks as the iPad does

    // `KanbanSectionStateSupport` and `KanbanColumnWindDown` are macOS-only; the iOS leg compiles
    // this bundle too, so the value tests are fenced and the source-reading one below is not.
    #if os(macOS)

    /// [[T-15661]]. A column completed on the iPad before [[T-15722]] stayed on the board
    /// (`windDownColumn(.complete)` wrote `isCompleted` alone), so a card can be added to it
    /// afterwards, and such columns are still in stores. Archiving that column
    /// on the Mac used to skip the cancel because the column was completed, leaving the card open
    /// under a column the board no longer draws; the iPad's archive of the same column cancels it.
    /// The decision is the one `saveSection` and `toggleSectionArchive` both read, composed here
    /// with the settle they run on it.
    @Test func archivingACompletedColumnOnTheMacCancelsTheCardAddedSince() throws {
        let context = ModelContext(try container())
        let addedSince = task("added since", section: "Doing")
        let area = board([addedSince], in: context)
        area.sectionConfigs = area.sectionConfigs.map { config in
            var config = config
            if config.name == "Doing" { config.isCompleted = true }
            return config
        }
        try context.save()

        let before = try #require(area.sectionConfigs.first { $0.name == "Doing" })
        #expect(before.isCompleted && !before.isArchived)
        var archived = before
        archived.isArchived = true

        // It asks first, promising the card the settle below cancels.
        let request = try #require(KanbanColumnWindDown.archiveRequest(for: before, area: area, project: nil))
        #expect(request.summary.openTasks == 1)

        let settle = KanbanSectionStateSupport.windDownOutcome(from: before, to: archived)
        #expect(settle == .cancelled)
        if settle == .cancelled {
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: before, area: area, project: nil, in: context)
        }
        #expect(addedSince.isCancelled)
    }

    /// The other arms of the same rule: entering completion marks done, and so does the countdown's
    /// write of both flags at once; unarchiving (which clears `isCompleted` too) and an unchanged
    /// column settle nothing.
    @Test func theMacColumnSettleDecisionMatchesEachTransition() {
        let open = TaskSectionConfig(name: "Doing")
        var completed = open
        completed.isCompleted = true
        var completedAndArchived = completed
        completedAndArchived.isArchived = true
        var archived = open
        archived.isArchived = true

        #expect(KanbanSectionStateSupport.windDownOutcome(from: open, to: completed) == .done)
        #expect(KanbanSectionStateSupport.windDownOutcome(from: open, to: completedAndArchived) == .done)
        #expect(KanbanSectionStateSupport.windDownOutcome(from: open, to: archived) == .cancelled)
        #expect(KanbanSectionStateSupport.windDownOutcome(from: completed, to: completedAndArchived) == .cancelled)
        #expect(KanbanSectionStateSupport.windDownOutcome(from: archived, to: open) == nil)
        #expect(KanbanSectionStateSupport.windDownOutcome(from: completedAndArchived, to: open) == nil)
        #expect(KanbanSectionStateSupport.windDownOutcome(from: open, to: open) == nil)
    }

    /// [[T-15662]]. Archive Column and Complete Column ask first when, and only when, there is open
    /// work to settle -- `requiresConfirmation`, the rule the iPad's editor and the Mac sidebar
    /// follow -- and say the count in the sidebar's sentence.
    @Test func theMacColumnAsksBeforeSettlingOpenWorkAndOnlyThen() throws {
        let context = ModelContext(try container())
        let one = task("one", section: "Doing")
        let two = task("two", section: "Doing", status: .inProgress)
        let finished = task("finished", section: "Later", status: .done)
        let area = board([one, two, finished], in: context)
        try context.save()

        let doing = try #require(area.sectionConfigs.first { $0.name == "Doing" })
        let later = try #require(area.sectionConfigs.first { $0.name == "Later" })
        let defaultColumn = try #require(area.sectionConfigs.first { $0.isDefault })

        let archive = try #require(KanbanColumnWindDown.archiveRequest(for: doing, area: area, project: nil))
        #expect(archive.outcome == .cancelled)
        #expect(archive.confirmationTitle == "Archive Column?")
        #expect(archive.confirmationMessage == "2 open tasks will be canceled. Unarchiving the column later does not reopen them.")

        let complete = try #require(
            KanbanColumnWindDown.completionRequest(for: doing, isPendingCompletion: false, area: area, project: nil)
        )
        #expect(complete.outcome == .done)
        #expect(complete.actionTitle == "Complete Column")
        #expect(complete.confirmationMessage == "2 open tasks will be marked done. Reopening the column later does not reopen them.")

        // Nothing open: one click, as before.
        #expect(KanbanColumnWindDown.archiveRequest(for: later, area: area, project: nil) == nil)
        #expect(KanbanColumnWindDown.completionRequest(for: later, isPendingCompletion: false, area: area, project: nil) == nil)

        // The reverse transitions and the countdown's cancel settle nothing, so they ask nothing.
        var doingCompleted = doing
        doingCompleted.isCompleted = true
        var doingArchived = doing
        doingArchived.isArchived = true
        #expect(KanbanColumnWindDown.completionRequest(for: doingCompleted, isPendingCompletion: false, area: area, project: nil) == nil)
        #expect(KanbanColumnWindDown.completionRequest(for: doing, isPendingCompletion: true, area: area, project: nil) == nil)
        #expect(KanbanColumnWindDown.completionRequest(for: doingArchived, isPendingCompletion: false, area: area, project: nil) == nil)
        #expect(KanbanColumnWindDown.archiveRequest(for: doingArchived, area: area, project: nil) == nil)

        // A completed column with open work asks before archiving ([[T-15661]]).
        #expect(KanbanColumnWindDown.archiveRequest(for: doingCompleted, area: area, project: nil)?.summary.openTasks == 2)

        // Default has no lifecycle, whatever is open in it.
        let unfiled = task("unfiled", section: "")
        unfiled.area = area
        context.insert(unfiled)
        area.tasks = (area.tasks ?? []) + [unfiled]
        #expect(KanbanColumnWindDown.archiveRequest(for: defaultColumn, area: area, project: nil) == nil)
        #expect(KanbanColumnWindDown.completionRequest(for: defaultColumn, isPendingCompletion: false, area: area, project: nil) == nil)
    }

    #endif

    /// The wiring half: every route into the two wind-downs asks through the request, the settle
    /// decision is the shared one in both write paths, and the `isCompleted` exemption is gone.
    @Test func everyMacColumnWindDownRouteAsksAndBothWritesReadTheSharedDecision() throws {
        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))

        #expect(column.contains("onToggleCompletion: requestSectionCompletion,"), "the header glyph completes without asking")
        #expect(column.contains("onToggleArchive: requestSectionArchive,"), "the popover's Archive Column archives without asking")
        let fromEditor = try #require(CadenceSourceScan.functionBody(named: "toggleCompletionFromEditor", in: column))
        #expect(fromEditor.contains("requestSectionCompletion()"), "the popover's Complete Column completes without asking")
        #expect(
            CadenceSourceScan.matchCount(#"hoveredSectionManager\.beginHovering\(id: section\.id\) \{\s*requestSectionCompletion\(\)"#, in: column) == 1,
            "Cmd+Return completes without asking"
        )
        // The toggles are reached from the request (nothing to ask) and the confirmation, only.
        #expect(column.components(separatedBy: "toggleSectionCompletion()").count - 1 == 3)
        #expect(column.components(separatedBy: "toggleSectionArchive()").count - 1 == 3)
        #expect(column.components(separatedBy: ".confirmationDialog(").count - 1 == 1)

        for name in ["saveSection", "toggleSectionArchive"] {
            let body = try #require(CadenceSourceScan.functionBody(named: name, in: column))
            #expect(body.contains("KanbanSectionStateSupport.windDownOutcome(from:"), "\(name)() decides its settle on its own")
            #expect(!body.contains("isCompleted && !"), "\(name)() exempts a completed column again")
            #expect(!body.contains("!config.isCompleted"), "\(name)() exempts a completed column again")
        }

        // One sentence for the sidebar and the column.
        let sidebar = try strippingComments(sourceFile("Cadence/macOS/Views/SidebarComponents.swift"))
        #expect(sidebar.contains("summary.confirmationMessage(containerNoun:"))
    }

    /// Without this, every zero and every absence assertion above could be passing because the
    /// reader returned an empty string, or because the scan was pointed at the wrong folder.
    @Test func theSourceScanActuallyReadsTheseFilesInColumnWindDownSurface() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300)
        #expect(files.contains("Cadence/iOS/iOSColumnWindDownSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSWindDownConfirmation.swift"))
        #expect(files.contains("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/KanbanSectionColumnView.swift"))

        // The `Toggle("Completed"` / `Toggle("Archived"` absence checks would pass vacuously if the
        // reader had returned nothing or no longer saw a `Toggle(` spelling. The anchor is the
        // sheet's hide-empty toggle: [[T-9804]] retired both "Due date" switches (the column row's,
        // then the project's), which this line used to read.
        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(editor.contains("private struct iOSSectionDraftRow: View"))
        #expect(editor.contains("Text(CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle)"))
        #expect(editor.contains("lifecycle: iOSSectionRowLifecycle?"))
        // The Default column is gated out of the wind-down, for the reason the model test above
        // pins. Asserted as live code, so deleting the guard is a failure here as well as a
        // silently discarded flag at runtime.
        #expect(editor.contains("!config.isDefault"))

        // And the `$draft.` sweep would pass vacuously if the row had stopped binding drafts at all.
        #expect(editor.contains("$draft.name"))
        #expect(editor.contains("$draft.colorHex"))

        // And the `isArchived = true` / `isCompleted = true` sweep would pass vacuously if the one
        // file that does spell them had stopped spelling them.
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSColumnWindDownSupport.swift"))
        #expect(support.contains("config.isArchived = true"))
        #expect(support.contains("config.markColumnCompleted()"))
    }

    // MARK: - T-15722: completing a column archives it, on both platforms

    /// [[T-15722]]. The shared write sets both flags, on the stored config and on the iPad
    /// editor's draft alike, and composed with the settle `windDownColumn(.complete)` runs it marks
    /// the open card done and takes the column off the board -- what the Mac's countdown did all
    /// along. A column already archived stays so, and Default still refuses both flags (T-268).
    @Test func completingAColumnArchivesItAndMarksItsOpenWorkDone() throws {
        let context = ModelContext(try container())
        let open = task("open", section: "Doing")
        let inProgress = task("in progress", section: "Doing", status: .inProgress)
        let elsewhere = task("elsewhere", section: "Later")
        let area = board([open, inProgress, elsewhere], in: context)
        try context.save()

        let doing = try #require(area.sectionConfigs.first { $0.name == "Doing" })
        #expect(!doing.isCompleted && !doing.isArchived)
        #expect(area.sectionNames.contains("Doing"))

        // The write and the settle, composed as `ModelContext.windDownColumn(.complete)` composes
        // them: the flag pair through `updateSectionConfig`, then the column's open work done.
        let found = CadenceSectionConfigMerge.container(area: area, project: nil)?
            .updateSectionConfig(uuid: doing.uuid) { $0.markColumnCompleted() }
        #expect(found == true)
        TaskContainerLifecycleService.completeRemainingActiveTasks(in: doing, area: area, project: nil, in: context)
        try context.save()

        let stored = try #require(area.sectionConfigs.first { $0.uuid == doing.uuid })
        #expect(stored.isCompleted)
        #expect(stored.isArchived)
        #expect(!area.sectionNames.contains("Doing"), "a completed column is still drawn on the board")
        #expect([open, inProgress].map(\.status) == [.done, .done])
        #expect(elsewhere.status == .todo)
        #expect(area.sectionConfigs.first { $0.name == "Later" }.map { !$0.isCompleted && !$0.isArchived } == true)

        // The iPad editor's draft follows the same write, so its own Save cannot write the
        // archive back off.
        var draft = CadenceSectionDraft(config: doing)
        draft.markColumnCompleted()
        #expect(draft.isCompleted && draft.isArchived)
        #expect(draft.config.isCompleted && draft.config.isArchived)

        // Default refuses the pair whoever writes it.
        let defaultColumn = try #require(area.sectionConfigs.first { $0.isDefault })
        CadenceSectionConfigMerge.container(area: area, project: nil)?
            .updateSectionConfig(uuid: defaultColumn.uuid) { $0.markColumnCompleted() }
        let storedDefault = try #require(area.sectionConfigs.first { $0.isDefault })
        #expect(!storedDefault.isCompleted && !storedDefault.isArchived)
    }

    /// The wiring half of [[T-15722]]: the Mac countdown, the iPad wind-down and the iPad editor's
    /// draft all reach the one completion write, and neither platform spells `isCompleted = true`
    /// for a column on its own any more -- the split that let the two write different pairs.
    @Test func bothPlatformsCompleteAColumnThroughTheOneSharedWrite() throws {
        try expectOccurrences(of: "markColumnCompleted()", at: [
            "Cadence/macOS/Services/SectionCompletionAnimationManager.swift": 1,
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListEditorViews.swift": 1
        ])
        for path in [
            "Cadence/macOS/Services/SectionCompletionAnimationManager.swift",
            "Cadence/iOS/iOSColumnWindDownSupport.swift",
            "Cadence/iOS/iOSListEditorViews.swift"
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("isCompleted = true"), "\(path) completes a column with its own flag write again")
        }

        // The iPad's confirmation says what the write now does.
        let support = try sourceFile("Cadence/iOS/iOSColumnWindDownSupport.swift")
        #expect(!support.contains("stays on the board"))
        #expect(support.contains("The column is marked complete and leaves the board"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
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

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
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

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix an isolated build tree resolves.
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

/// Blanks `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
