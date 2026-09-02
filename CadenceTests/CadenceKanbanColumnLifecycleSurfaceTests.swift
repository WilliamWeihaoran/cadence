import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-268. macOS offered **"Mark Section Completed"** on the **Default** kanban column, and the
/// model throws the flag away while the settle underneath the button still runs.
///
/// The two halves have to be read together, because either one alone looks harmless:
///
/// 1. `Area.normalizedSectionConfigs` / `Project.normalizedSectionConfigs` force `isCompleted` and
///    `isArchived` false on the Default column on **every read and every write**. That is correct
///    and deliberate — Default is synthesised rather than created, `resolvedSectionName` sends
///    every task with no section name into it, and `sectionNames` hides archived columns, so a
///    completed-or-archived Default would be an invisible bucket still collecting every new task.
/// 2. `KanbanSectionColumnView.saveSection` calls
///    `TaskContainerLifecycleService.completeRemainingActiveTasks` **before** the flag is written
///    back — and that call does not consult the flag, so it settles every open card in the column
///    regardless.
///
/// So the pressed button did the irreversible half and skipped the visible half: the cards were
/// marked done, and the column re-rendered Active with its stack empty. That is worse than either
/// refusing the action or persisting it, which is why
/// `theCompletionSaveOnDefaultSettlesTheWorkAndKeepsTheColumnActive` below still passes after the fix — it drives the mutation layer directly, and it is the reason
/// the *request* has to be refused one layer up.
///
/// The refusal is `TaskSectionConfig.supportsLifecycle`, and macOS has three routes to a column's
/// completion — the header glyph, the editor popover's item, and `Cmd+Return` over the hovered
/// column. All three are gated, plus the point they converge on. Only the first of those is
/// testable as a symbol: the other three are inside a private SwiftUI `View`, so they are pinned
/// as source text, under the rules in `Cadence/Shared/AGENTS.md`.
///
/// iOS states the same rule for the same column in `iOSListEditorSheet.lifecycle(for:)`, which
/// returns `nil` for Default (T-247). This file deliberately asserts nothing about that file: it
/// was in flight when this landed.
@MainActor
struct CadenceKanbanColumnLifecycleSurfaceTests {

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - The rule, as a value

    /// The Default column has no lifecycle; every other column has one. Case-insensitively,
    /// because that is how `isDefault` and every section comparison in the app match names — a
    /// column stored as `default` is the same column.
    @Test func onlyTheDefaultColumnRefusesALifecycle() {
        #expect(!TaskSectionConfig(name: TaskSectionDefaults.defaultName).supportsLifecycle)
        #expect(!TaskSectionConfig(name: "default").supportsLifecycle)
        #expect(!TaskSectionConfig(name: "DEFAULT").supportsLifecycle)

        // Controls: the property is about Default and not about columns generally, and not about
        // a column that merely *contains* the word.
        #expect(TaskSectionConfig(name: "Doing").supportsLifecycle)
        #expect(TaskSectionConfig(name: "Default Later").supportsLifecycle)
        #expect(TaskSectionConfig(name: "Shipped", isCompleted: true, isArchived: true).supportsLifecycle)
    }

    // MARK: - What the ungated button actually did

    /// **The measured defect.** This composes exactly what `KanbanSectionColumnView.saveSection`
    /// composes — `KanbanSectionStateSupport.saveSection` plus
    /// `TaskContainerLifecycleService.completeRemainingActiveTasks` — with the flags
    /// `SectionCompletionAnimationManager` writes at the end of its sweep, and points it at the
    /// Default column.
    ///
    /// Both halves are asserted: the tasks are done and stay done, and the column reads Active
    /// afterwards. The non-default control at the end is what makes the second assertion a
    /// statement about Default rather than about the setter dropping flags generally.
    ///
    /// This still passes with the fix in place, and that is the point — nothing at this layer
    /// changed. The action is refused before it reaches here.
    @Test func theCompletionSaveOnDefaultSettlesTheWorkAndKeepsTheColumnActive() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]

        let unfiled = AppTask(title: "unfiled")
        unfiled.sectionName = ""
        let named = AppTask(title: "explicitly default")
        named.sectionName = TaskSectionDefaults.defaultName
        let elsewhere = AppTask(title: "doing")
        elsewhere.sectionName = "Doing"
        for task in [unfiled, named, elsewhere] {
            task.area = area
            context.insert(task)
        }
        area.tasks = [unfiled, named, elsewhere]
        try context.save()

        let defaultColumn = area.sectionConfigs.first { $0.isDefault }!
        completeColumnTheWayTheMacButtonDid(defaultColumn, area: area, in: context)

        // Half one: the settle ran, and it is not undoable by re-reading the column.
        #expect(unfiled.isDone)
        #expect(named.isDone)
        #expect(elsewhere.status == .todo)

        // Half two: the flag it was paired with is gone, so the column reads Active with an
        // empty stack — the "worst of both" the ticket names.
        let storedDefault = area.sectionConfigs.first { $0.isDefault }
        #expect(storedDefault?.isCompleted == false)
        #expect(storedDefault?.isArchived == false)

        // Control: the identical write on a non-default column persists, so the two assertions
        // above are about Default and not about the setter.
        let doing = area.sectionConfigs.first { $0.name == "Doing" }!
        completeColumnTheWayTheMacButtonDid(doing, area: area, in: context)
        let storedDoing = area.sectionConfigs.first { $0.name == "Doing" }
        #expect(storedDoing?.isCompleted == true)
        #expect(storedDoing?.isArchived == true)
        #expect(elsewhere.isDone)
    }

    /// `SectionCompletionAnimationManager` is what all three buttons actually drive, and it is
    /// where the pair of flags is decided. Both directions are pinned so the reproduction above
    /// cannot be passing against flags this repo does not really write.
    ///
    /// The **reopen** direction is asserted as behaviour, because it is synchronous. The
    /// **complete** direction is a 2.5s sweep on a detached `Task`, and a test that slept for it
    /// failed once here under the suite's own parallel load rather than because anything was
    /// wrong — so it is asserted as source text instead of as a race. What is asserted about it
    /// behaviourally is the part that does not need a clock: pressing the control puts the column
    /// into the pending state, i.e. the sweep really is what the button starts.
    @Test func theCompletionManagerWritesBothFlagsAndClearsBothOnReopen() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing", isCompleted: true, isArchived: true)
        ]
        try context.save()

        let manager = SectionCompletionAnimationManager.shared
        let completed = area.sectionConfigs.first { $0.name == "Doing" }!
        #expect(completed.isCompleted && completed.isArchived)

        // Reopen: synchronous, and it clears *both* — a column that stayed archived after being
        // marked active would be off the board with no way back.
        manager.toggleCompletion(
            for: completed,
            getCurrent: { area.sectionConfigs.first { $0.id == completed.id } },
            save: { KanbanSectionStateSupport.saveSection(updatedSection: $0, area: area, project: nil) }
        )
        let reopened = area.sectionConfigs.first { $0.id == completed.id }
        #expect(reopened?.isCompleted == false)
        #expect(reopened?.isArchived == false)
        #expect(!manager.isPending(completed))

        // Complete: the press starts the sweep rather than writing immediately, which is why the
        // flags below are read off the manager's source rather than raced for.
        let active = area.sectionConfigs.first { $0.id == completed.id }!
        manager.toggleCompletion(
            for: active,
            getCurrent: { area.sectionConfigs.first { $0.id == active.id } },
            save: { KanbanSectionStateSupport.saveSection(updatedSection: $0, area: area, project: nil) }
        )
        #expect(manager.isPending(active))
        manager.cancelPending(for: active.id)
        #expect(!manager.isPending(active))

        // And the sweep's landing writes the pair `completeColumnTheWayTheMacButtonDid` uses.
        let sweep = try strippingComments(sourceFile("Cadence/macOS/Services/SectionCompletionAnimationManager.swift"))
        #expect(sweep.contains("current.isCompleted = true"))
        #expect(sweep.contains("current.isArchived = true"))
        #expect(sweep.contains("current.isCompleted = false"))
        #expect(sweep.contains("current.isArchived = false"))
    }

    /// The mutation `saveSection` performs when a completion sweep lands, spelled the way
    /// `KanbanSectionColumnView.saveSection` spells it. `theMacColumnStillWindsDownEveryOtherColumn`
    /// pins that the view has not stopped composing it this way.
    private func completeColumnTheWayTheMacButtonDid(
        _ column: TaskSectionConfig,
        area: Area,
        in context: ModelContext
    ) {
        var updated = column
        updated.isCompleted = true
        updated.isArchived = true
        KanbanSectionStateSupport.saveSection(updatedSection: updated, area: area, project: nil)
        TaskContainerLifecycleService.completeRemainingActiveTasks(in: updated, area: area, project: nil, in: context)
        try? context.save()
    }

    // MARK: - The three routes, gated

    /// The header glyph and the editor popover's item are the two visible routes, and both live in
    /// `KanbanColumnSupportViews.swift`. Asserted as *structure* — the gate immediately above the
    /// button — rather than as the presence of a string anywhere in the file, and with the count
    /// of gates pinned so a third `Button(action: onToggleCompletion)` cannot appear outside one.
    @Test func bothVisibleCompletionControlsSitInsideTheLifecycleGate() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))

        // The column header's completion glyph.
        #expect(
            matches(#"if section\.supportsLifecycle \{\s*Button\(action: onToggleCompletion\)"#, in: code) == 1,
            "the section header's completion glyph is not directly inside a supportsLifecycle gate"
        )
        // The editor popover's "Mark Section Completed", which now shares Archive's gate — the
        // divider came inside with it.
        #expect(
            matches(#"if section\.supportsLifecycle \{\s*Divider\(\)[^\n]*\s*Button\(action: onToggleCompletion\)"#, in: code) == 1,
            "the editor popover's completion item is not inside the same gate as Archive"
        )

        // Exactly two completion controls in this file, and exactly two gates: a third of either
        // would mean one of them is ungated.
        #expect(code.components(separatedBy: "Button(action: onToggleCompletion)").count - 1 == 2)
        #expect(code.components(separatedBy: "section.supportsLifecycle").count - 1 == 2)

        // Archive and Delete are still gated too — this fix moved Completion in beside them, it
        // did not move them out.
        #expect(matches(#"Button\(action: onToggleArchive\)"#, in: code) == 1)
        #expect(matches(#"Button\(action: onDelete\)"#, in: code) == 1)
    }

    /// The third route has no control to hide: `Cmd+Return` over a hovered column fires whatever
    /// `HoveredSectionManager` is holding. Default does not register a target at all — registering
    /// a no-op would make `triggerToggleComplete()` claim the keystroke instead of letting it fall
    /// through. And the point all three converge on refuses too, so a *fourth* route is safe by
    /// default rather than only the three that exist today.
    @Test func theKeyboardRouteAndTheConvergencePointBothRefuseDefault() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))

        #expect(
            matches(#"if section\.supportsLifecycle \{\s*hoveredSectionManager\.beginHovering\("#, in: code) == 1,
            "the hovered-column completion target is registered for the Default column"
        )
        #expect(
            matches(#"guard section\.supportsLifecycle else \{ return \}\s*sectionCompletionAnimationManager\.toggleCompletion\("#, in: code) == 1,
            "toggleSectionCompletion does not refuse a column with no lifecycle"
        )
        #expect(code.components(separatedBy: "section.supportsLifecycle").count - 1 == 2)
    }

    /// The fix must not be read as "columns no longer wind down". Every non-default column still
    /// settles its open work on completion and on archive — removing those calls would satisfy
    /// every gate assertion above and be the wrong fix, the same trap
    /// `CadenceListWindDownSurfaceTests` guards against one level up.
    @Test func theMacColumnStillWindsDownEveryOtherColumn() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        #expect(code.components(separatedBy: "TaskContainerLifecycleService.completeRemainingActiveTasks(").count - 1 == 1)
        #expect(code.components(separatedBy: "TaskContainerLifecycleService.cancelRemainingActiveTasks(").count - 1 == 2)
    }

    // MARK: - T-645: the editor's other three writes, and where the rename commits

    /// **The three writes that reached no commit at all, and the one that closed the popover over
    /// nothing (T-645).**
    ///
    /// None of them was visible to the `try? save()` rule, and the reason is the same for all
    /// three: a `TaskSectionConfig` is a struct inside the container's `sectionConfigsRaw` JSON
    /// rather than a `@Model`, so `modelContext.delete(` never fires and halves 1 and 3 have
    /// nothing to see — and there was no `try?` anywhere for half 2 to key on, only
    /// `showEditor = false` reporting a delete the store had never been asked to take.
    ///
    /// **`commitEdit` for the discrete two and `CadenceInPlaceEditFlush` for the rename, and the
    /// split is asserted rather than assumed.** Clearing a date and deleting a column can be put
    /// back and reported as "Nothing was changed". A rename cannot: the field is still on screen
    /// with the caret in it, and restoring the model would delete what the user typed in order to
    /// tell them it had not saved. That is the decision `CadenceInPlaceEditFlush` records, and the
    /// two sentences it separates are pinned as different below — one flag holding both would make
    /// the choice untestable.
    @Test func theColumnEditorsOtherThreeWritesReachACommit() throws {
        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        #expect(column.contains("struct ListSectionKanbanColumn: View"), "non-vacuity: wrong file read")
        #expect(matches(#"try\?"#, in: column) == 0, "the column swallows a commit again")

        // The two discrete writes: an undo, a commit through the shared helper, and a notice.
        for name in ["clearSectionDueDate", "deleteSection"] {
            let body = try #require(CadenceSourceScan.functionBody(named: name, in: column), "\(name)() is not declared")
            #expect(
                body.contains("CadencePendingChangePersistence.commitEdit(in: modelContext, undo: { undo?.restore() })"),
                "\(name)() commits without an undo, or does not commit"
            )
            #expect(
                body.contains("saveFailureNotice = CadencePendingChangePersistence.editFailureNotice"),
                "\(name)() does not name a refused commit"
            )
            #expect(matches(#"modelContext\.rollback\(\)"#, in: body) == 0, "\(name) rolls the app's context back")
        }

        // The delete snapshots the cards it is about to re-point, and it is **not** the settling
        // set: deleting a column moves its whole stack, finished cards included.
        let delete = try #require(CadenceSourceScan.functionBody(named: "deleteSection", in: column))
        #expect(delete.contains("editSnapshotMovingTasks(outOf: section.name)"))
        #expect(!delete.contains("editSnapshot(settling:"), "the delete snapshots only the open half of the column")

        // The two snapshots differ in exactly one thing — which tasks they hand over — so both are
        // read. They are two names rather than an overload deliberately: `functionBody(named:)` and
        // `bodies(of:expected:)` anchor on `func <name>(`, so a second `editSnapshot(` would have
        // changed what three existing tests in `CadenceEditorSaveCommitSurfaceTests` were reading.
        let settlingSnapshot = try #require(CadenceSourceScan.functionBody(named: "editSnapshot", in: column))
        #expect(settlingSnapshot.contains("TaskContainerLifecycleService.remainingActiveTasks("))
        let movingSnapshot = try #require(CadenceSourceScan.functionBody(named: "editSnapshotMovingTasks", in: column))
        #expect(
            movingSnapshot.contains("KanbanSectionStateSupport.tasksMoving("),
            "the delete's snapshot walks the column itself instead of the walk moveTasks performs"
        )
        #expect(!movingSnapshot.contains("remainingActiveTasks("), "the two snapshots have collapsed into one set")

        // Clearing the date puts the popover's own flag back too — a popover showing "no date" over
        // a column that still has one is the report inverted.
        let clear = try #require(CadenceSourceScan.functionBody(named: "clearSectionDueDate", in: column))
        #expect(clear.contains("let hadDueDate = editorHasDueDate"))
        #expect(clear.contains("editorHasDueDate = hadDueDate"))

        // And the popover closes on the commit rather than on the tap.
        let editor = try #require(bodyOfComputed("columnEditor", in: column))
        #expect(editor.contains("guard deleteSection() else { return }"))
        #expect(editor.contains("onClearDate: { _ = clearSectionDueDate() }"))
        let guardRange = try #require(editor.range(of: "guard deleteSection() else { return }"))
        let close = try #require(editor.range(of: "showEditor = false"))
        #expect(close.lowerBound > guardRange.upperBound, "the popover closes above the refused delete")
        #expect(
            matches(#"showEditor = false"#, in: editor) == 1,
            "the editor closes in more than one place, so the guard above does not cover them all"
        )
    }

    /// **The rename's commit *point*, which is the part that could not simply be "add a commit"
    /// (T-645).**
    ///
    /// `onNameChanged` fires on every character of the rename field. A commit there would ask the
    /// store for a transaction per keystroke and hand the user a refusal notice mid-word, so the
    /// write and the commit are separate calls: `applySectionEdits` per character,
    /// `commitSectionEdits` when the edit ends — Return, focus leaving the field, or any of the
    /// discrete controls, all of which land while the popover is still on screen to carry a notice.
    ///
    /// Asserted at both ends, because either alone is satisfiable by the defect: the view must fire
    /// two different callbacks from two different events, and the column must wire the per-keystroke
    /// one to a function that does **not** commit.
    @Test func theColumnRenameCommitsAtTheEndOfTheEditRatherThanPerKeystroke() throws {
        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        let popover = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))
        #expect(popover.contains("struct KanbanSectionEditorPopover"), "non-vacuity: wrong file read")

        // The per-keystroke write commits nothing at all — that is the whole of what it is for.
        let apply = try #require(CadenceSourceScan.functionBody(named: "applySectionEdits", in: column))
        #expect(apply.contains("container.applySectionConfigEdits("), "the apply no longer writes the blob")
        #expect(matches(#"\.save\(\)|CadencePendingChangePersistence\.commit|CadenceInPlaceEditFlush"#, in: apply) == 0,
                "applySectionEdits commits, so the rename is back to one transaction per character")

        // The commit point, and the sentence that keeps the user's text.
        let commit = try #require(CadenceSourceScan.functionBody(named: "commitSectionEdits", in: column))
        #expect(commit.contains("applySectionEdits()"))
        #expect(commit.contains("guard CadenceInPlaceEditFlush.flush(in: modelContext) else {"))
        #expect(commit.contains("saveFailureNotice = CadenceInPlaceEditFlush.failureNotice"))
        #expect(matches(#"modelContext\.rollback\(\)|undo"#, in: commit) == 0,
                "the rename restores something, which deletes what the user is still typing")

        // The wiring: per-keystroke apply, commit at the end, and the three discrete controls
        // committing on the spot.
        #expect(column.contains("onNameChanged: applySectionEdits"))
        #expect(column.contains("onNameCommitted: { _ = commitSectionEdits() }"))
        #expect(column.contains("onColorSelected: { _ = commitSectionEdits() }"))
        #expect(column.contains("onDueDateChanged: { _ = commitSectionEdits() }"))

        // And the popover raises the two callbacks from two different events. A view that fired
        // `onNameCommitted` from `onChange(of: editorName)` would satisfy every assertion above
        // while committing per character after all.
        #expect(matches(#"\.onChange\(of: editorName\) \{ _, _ in onNameChanged\(\) \}"#, in: popover) == 1)
        #expect(matches(#"\.onSubmit \{ onNameCommitted\(\) \}"#, in: popover) == 1)
        #expect(matches(#"\.onChange\(of: isNameFieldFocused\)"#, in: popover) == 1)
        #expect(matches(#"onNameCommitted\(\)"#, in: popover) == 2, "the rename's commit point moved or grew a third trigger")

        // The two failure sentences are genuinely different questions, which is what makes the
        // choice above a choice. "Nothing was changed" is only true because an undo ran.
        #expect(CadenceInPlaceEditFlush.failureNotice != CadencePendingChangePersistence.editFailureNotice)
        #expect(CadenceInPlaceEditFlush.failureNotice.contains("still here"))
        #expect(CadencePendingChangePersistence.editFailureNotice.contains("Nothing was changed"))
    }

    /// **A refused column delete puts the column back and every card it was moving with it.**
    ///
    /// The behavioural half, composed the way `deleteSection` composes it —
    /// `KanbanSectionStateSupport.tasksMoving` for the snapshot, then `moveTasks` and
    /// `removeSection` — under a commit that throws.
    ///
    /// **The finished card is the assertion that matters.** `editSnapshot(settling:)`, which every
    /// other write on this popover uses, hands over
    /// `TaskContainerLifecycleService.remainingActiveTasks` — the *open* half of the column. A
    /// delete moves the whole stack, so a snapshot of the open half restores the to-do card and
    /// leaves the done one filed under a column the store no longer has. That failure is invisible
    /// to a fixture with only open cards in it.
    @Test func aRefusedColumnDeleteRestoresTheColumnAndEveryCardItWasMoving() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]

        let open = AppTask(title: "still open")
        let finished = AppTask(title: "already done")
        finished.status = .done
        let elsewhere = AppTask(title: "in Default")
        for task in [open, finished] { task.sectionName = "Doing" }
        elsewhere.sectionName = TaskSectionDefaults.defaultName
        for task in [open, finished, elsewhere] {
            task.area = area
            context.insert(task)
        }
        area.tasks = [open, finished, elsewhere]
        try context.save()

        let column = try #require(area.sectionConfigs.first { $0.name == "Doing" })
        let moving = KanbanSectionStateSupport.tasksMoving(
            universeTasks: [open, finished, elsewhere],
            area: area,
            project: nil,
            from: column.name
        )
        // Non-vacuity, and the point of the ticket in one line: the walk the delete performs
        // reaches the finished card too, and stops at the column boundary.
        #expect(moving.map(\.title).sorted() == ["already done", "still open"])

        let undo = CadenceListEditSnapshot(area, tasks: moving)
        KanbanSectionStateSupport.moveTasks(
            universeTasks: [open, finished, elsewhere],
            area: area,
            project: nil,
            from: column.name,
            to: TaskSectionDefaults.defaultName
        )
        KanbanSectionStateSupport.removeSection(sectionID: column.id, area: area, project: nil)
        #expect(area.sectionConfigs.contains { $0.name == "Doing" } == false)
        #expect(open.sectionName == TaskSectionDefaults.defaultName)
        #expect(finished.sectionName == TaskSectionDefaults.defaultName)

        #expect(throws: ColumnCommitRefused.self) {
            try CadencePendingChangePersistence.commitEdit(
                in: context,
                commit: { _ in throw ColumnCommitRefused() },
                undo: undo.restore
            )
        }

        #expect(area.sectionConfigs.contains { $0.name == "Doing" })
        #expect(open.sectionName == "Doing")
        #expect(finished.sectionName == "Doing", "the finished card was left in a column that no longer exists")
        #expect(elsewhere.sectionName == TaskSectionDefaults.defaultName)
    }

    // MARK: - T-646: a refused column completion reaches the user

    /// **The countdown outlives the popover, so the notice cannot live only in the popover
    /// (T-646).**
    ///
    /// `SectionCompletionAnimationManager` writes a *reopen* synchronously and defers a
    /// *completion* behind a 2.5-second sweep on a detached `Task`. `toggleCompletionFromEditor`
    /// closes the popover as soon as the synchronous half comes back clean — so when the deferred
    /// write is refused, `saveSection` sets `saveFailureNotice` into a surface that has been gone
    /// for two and a half seconds. The undo is correct and the column visibly stays active; the
    /// report reaches nobody. And two of the three routes into `toggleSectionCompletion` — the
    /// header glyph and Cmd+Return over the hovered column — never open a popover at all, so their
    /// refusals had nowhere to appear either.
    ///
    /// The fix is one flag read through two surfaces rather than a second flag: `columnFailureNotice`
    /// is `saveFailureNotice` while the editor is closed and `nil` while it is open, so a refusal is
    /// reported exactly once and by whichever surface the user can actually see.
    @Test func aRefusedColumnCompletionIsReportedOnTheColumnOnceThePopoverIsGone() throws {
        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        let support = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))

        // The deferral that makes this necessary, as a value rather than as prose.
        #expect(SectionCompletionAnimationManager.animationDuration == 2.5)
        let toggle = try #require(CadenceSourceScan.functionBody(named: "toggleCompletionFromEditor", in: column))
        #expect(toggle.contains("showEditor = false"), "the editor no longer closes ahead of the sweep")

        // One flag, read through `showEditor`. A literal `nil` or a second stored notice would both
        // pass a `contains("columnFailureNotice")`, so the expression itself is pinned.
        #expect(
            matches(#"private var columnFailureNotice: String\? \{\s*showEditor \? nil : saveFailureNotice\s*\}"#, in: column) == 1,
            "the column's notice is no longer the popover's notice read through showEditor"
        )
        #expect(matches(#"failureNotice: columnFailureNotice"#, in: column) == 1)
        #expect(
            matches(#"saveFailureNotice = CadencePendingChangePersistence\.editFailureNotice"#, in: column) == 4,
            """
            the column's refusals are set somewhere other than the four commits that can be \
            refused: saveSection, toggleSectionArchive, clearSectionDueDate and deleteSection
            """
        )

        // And the header draws it, under the line the countdown wrote. Same component the popover
        // uses — this is a failure, and it must not be quieter than the "Completing…" it replaces.
        let detail = try #require(bodyOfComputed("headerDetail", in: support))
        #expect(detail.contains("Completing"), "non-vacuity: wrong slice read")
        #expect(detail.contains("CadenceInlineFailureNotice(text: failureNotice)"))
        let countdown = try #require(detail.range(of: "isPendingCompletion"))
        let notice = try #require(detail.range(of: "CadenceInlineFailureNotice(text: failureNotice)"))
        #expect(notice.lowerBound > countdown.upperBound, "the refusal draws above the countdown it answers")

        // Both notices in this file are the shared component, and there are exactly two: the
        // popover's and the column's.
        #expect(matches(#"CadenceInlineFailureNotice\("#, in: support) == 2)
    }

    // MARK: - The scans are real

    /// Every count and every regex above passes against an empty string, so this asserts the
    /// reader read, the stripper stripped, and the patterns are the patterns they look like.
    @Test func theSourceScanActuallyReadsTheseFilesAndThePatternsWork() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300)
        #expect(files.contains("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/KanbanSectionColumnView.swift"))

        // Positive reads: the controls this file is about are still drawn, and the Default branch
        // of the popover still explains itself — with completion now named in it.
        let support = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))
        #expect(support.contains("Mark Section Completed"))
        #expect(support.contains("Default always stays available and cannot be renamed, completed, archived, or deleted."))
        #expect(support.contains("struct KanbanSectionEditorPopover"))

        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        #expect(column.contains("private func toggleSectionCompletion()"))
        #expect(column.contains("hoveredSectionManager.endHovering(id: section.id)"))

        // The stripper stripped: `supportsLifecycle` is named in prose in both files, so a
        // comment-blind count would exceed the two live uses each one asserts.
        #expect(rawSourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift").components(separatedBy: "supportsLifecycle").count - 1 > 2)
        #expect(support.components(separatedBy: "supportsLifecycle").count - 1 == 2)

        // Pattern self-check: each needle matches a literal that must match and misses one that
        // must not, so a typo cannot pass every scan built on it.
        let gateHeader = #"if section\.supportsLifecycle \{\s*Button\(action: onToggleCompletion\)"#
        #expect(matches(gateHeader, in: "if section.supportsLifecycle {\n    Button(action: onToggleCompletion) {") == 1)
        #expect(matches(gateHeader, in: "Button(action: onToggleCompletion) {") == 0)
        #expect(matches(gateHeader, in: "if section.isDefault {\n    Button(action: onToggleCompletion) {") == 0)

        let gateGuard = #"guard section\.supportsLifecycle else \{ return \}\s*sectionCompletionAnimationManager\.toggleCompletion\("#
        #expect(matches(gateGuard, in: "guard section.supportsLifecycle else { return }\n    sectionCompletionAnimationManager.toggleCompletion(") == 1)
        #expect(matches(gateGuard, in: "sectionCompletionAnimationManager.toggleCompletion(") == 0)
    }
}

// MARK: - Source-reading helpers

/// A commit the store refuses, for the undo paths a real in-memory container cannot provoke.
private struct ColumnCommitRefused: Error {}

/// The body of a computed property, for the two slices above that are `var x: some View` rather
/// than `func x()`. `CadenceSourceScan.functionBody(named:)` anchors on `func <name>(` and finds
/// nothing here, which would read as an absent declaration rather than as the wrong question.
private func bodyOfComputed(_ name: String, in source: String) -> String? {
    guard let signature = source.range(of: "var \(name): some View") else { return nil }
    var depth = 0
    var start: String.Index?
    var index = signature.upperBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" {
            if depth == 0 { start = source.index(after: index) }
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0, let start { return String(source[start..<index]) }
            if depth < 0 { return nil }
        }
        index = source.index(after: index)
    }
    return nil
}

/// Number of non-overlapping matches of `pattern` in `text`.
private func matches(_ pattern: String, in text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return -1 }
    return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
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

/// The raw file, comments and all — used only to prove the stripper below removed something.
private func rawSourceFile(_ relativePath: String) -> String {
    (try? sourceFile(relativePath)) ?? ""
}

/// Blanks `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
