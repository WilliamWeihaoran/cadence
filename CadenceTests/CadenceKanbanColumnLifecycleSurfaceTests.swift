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

    /// **Exactly what `ListSectionKanbanColumn.applySectionEdits` writes**, and nothing else: the
    /// container's blob, merged against the frozen `editorBase`, with every one of that function's
    /// four declines spelled the same way. It is a transcription because the original is a private
    /// member of a SwiftUI `View`; the source assertions in
    /// `theRenameMovesItsCardsOnceAtTheCommitPointRatherThanPerKeystroke` are what keep the two
    /// from drifting, and the one line this transcription deliberately does **not** have is the
    /// per-keystroke `moveTasks` that T-713 removed. The due-date branch is the one field left as
    /// the base's: no test here edits a date, and `clearSectionDueDate` owns that write anyway.
    private func applyColumnEditsTheWayThePopoverDoes(
        base: TaskSectionConfig,
        typedName: String,
        colorHex: String? = nil,
        area: Area
    ) {
        let trimmed = base.isDefault ? base.name : typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = area.sectionConfigs
        guard current.contains(where: { $0.uuid == base.uuid }) else { return }
        if trimmed.caseInsensitiveCompare(base.name) != .orderedSame,
           current.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }
        var edited = base
        edited.name = trimmed
        edited.colorHex = colorHex ?? base.colorHex
        area.applySectionConfigEdits(
            base: current.map { $0.uuid == base.uuid ? base : $0 },
            edited: current.map { $0.uuid == base.uuid ? edited : $0 }
        )
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
        // **`filedCardName` and not `section.name` since T-713.** The rename writes the config per
        // keystroke and moves the cards at the commit point, so a column typed into and then
        // deleted without committing has a config name its cards do not carry. Both the snapshot
        // and the move must ask where the cards are, and they must ask the same question.
        let delete = try #require(CadenceSourceScan.functionBody(named: "deleteSection", in: column))
        #expect(delete.contains("editSnapshotMovingTasks(outOf: filedCardName)"))
        #expect(delete.contains("moveTasks(from: filedCardName, to: TaskSectionDefaults.defaultName)"))
        #expect(matches(#"section\.name"#, in: delete) == 0, "the delete walks the config's name instead of the cards'")
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

    // MARK: - T-713: the rename moves its cards once, at the commit point

    /// **The defect, reproduced with two keystrokes and nothing but shipped API.**
    ///
    /// This is the composition `applySectionEdits` used to perform per character: merge the
    /// container's blob against the frozen `editorBase`, then
    /// `moveTasks(from: base.name, to: trimmed)`. Because `base` is the column *as the popover
    /// opened* and is never advanced, only the first keystroke finds any cards. The second looks
    /// for cards still called `Doing`, finds none, and leaves them where the first put them —
    /// while the config, matched by `uuid`, goes all the way to `Doingxy`.
    ///
    /// `AppTask.resolvedSectionName` falls back to Default only for an **empty** name, so the
    /// cards are not rescued: they are filed under `Doingx`, and no column in the list is called
    /// that. The board draws them nowhere.
    ///
    /// **This test passes before and after the fix and is meant to** — it drives the old policy
    /// directly rather than through the column, so what it pins is that the strand is real and what
    /// its shape is. The fix is pinned by the two tests below and by the source assertions in
    /// `theRenameMovesItsCardsOnceAtTheCommitPointRatherThanPerKeystroke`.
    @Test func theOldPerKeystrokeRenameStrandsTheColumnsCardsUnderANameNoColumnHas() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]
        let card = AppTask(title: "in the column")
        card.sectionName = "Doing"
        card.area = area
        context.insert(card)
        area.tasks = [card]
        try context.save()

        let base = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        for typed in ["Doingx", "Doingxy"] {
            applyColumnEditsTheWayThePopoverDoes(base: base, typedName: typed, area: area)
            // The half this ticket removes: the move, taken per keystroke, out of the frozen base.
            KanbanSectionStateSupport.moveTasks(
                universeTasks: [card], area: area, project: nil, from: base.name, to: typed
            )
        }

        // The config reached the name the user typed, because the merge matches on `uuid`.
        #expect(area.sectionConfigs.map(\.name).contains("Doingxy"))
        // The card did not, and it is not in Default either.
        #expect(card.sectionName == "Doingx")
        #expect(card.resolvedSectionName == "Doingx")
        #expect(
            area.sectionConfigs.contains { $0.name.caseInsensitiveCompare("Doingx") == .orderedSame } == false,
            "the strand is only a strand if no column has the name"
        )
    }

    /// **The fix: one move, at the commit point, to the name the store actually took (T-713).**
    ///
    /// The same two keystrokes as above, with the move where the user decision put it. Nothing
    /// touches a card until the commit, and then the cards land on `Doingxy` — the name the
    /// container holds, read back out of it rather than taken from the field.
    ///
    /// **The second commit is the half a frozen source would still get wrong.** Return, type more,
    /// pick a colour is one editing session with two commit points in it, and by the second one the
    /// cards are no longer under the name the popover opened with. So the source advances with the
    /// cards — which is `editorFiledCardName`, and deliberately not `editorBase`: that snapshot
    /// stays frozen for the merge, and the test below is the case it is frozen for.
    @Test func theRenameCommitFilesEveryCardUnderTheNameTheStoreTook() throws {
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

        let universe = [open, finished, elsewhere]
        let base = try #require(area.sectionConfigs.first { $0.name == "Doing" })
        var filed = base.name

        // Two keystrokes, neither of which may touch a card.
        for typed in ["Doingx", "Doingxy"] {
            applyColumnEditsTheWayThePopoverDoes(base: base, typedName: typed, area: area)
            #expect(open.sectionName == "Doing", "an intermediate name reached a card")
            #expect(finished.sectionName == "Doing", "an intermediate name reached a card")
        }

        let moved = KanbanSectionStateSupport.moveCardsToStoredName(
            universeTasks: universe, area: area, project: nil,
            columnUUID: base.uuid, typedName: "Doingxy", filedName: filed
        )
        #expect(moved == "Doingxy")
        filed = try #require(moved)

        // The whole stack, finished card included, and nothing outside the column.
        #expect(open.sectionName == "Doingxy")
        #expect(finished.sectionName == "Doingxy")
        #expect(elsewhere.sectionName == TaskSectionDefaults.defaultName)
        // And every card names a column the list actually has.
        let names = Set(area.sectionConfigs.map { $0.name.lowercased() })
        for task in universe {
            #expect(names.contains(task.resolvedSectionName.lowercased()))
        }

        // **A second commit in the same session.** The cards are under `Doingxy` now, not under the
        // name the popover opened with, so a source frozen at `editorBase` strands them again here.
        applyColumnEditsTheWayThePopoverDoes(base: base, typedName: "Shipping", area: area)
        let movedAgain = KanbanSectionStateSupport.moveCardsToStoredName(
            universeTasks: universe, area: area, project: nil,
            columnUUID: base.uuid, typedName: "Shipping", filedName: filed
        )
        #expect(movedAgain == "Shipping")
        #expect(open.sectionName == "Shipping")
        #expect(finished.sectionName == "Shipping")
        #expect(elsewhere.sectionName == TaskSectionDefaults.defaultName)
    }

    /// **A rename the store never took moves no card (T-713).**
    ///
    /// The commit point runs `applySectionEdits()` and then the move, and the apply can decline:
    /// an empty name, or one another column already has. The destination is therefore read back out
    /// of the container and required to be the name the caller typed — so a refused rename leaves
    /// the stored name alone, the two disagree, and nothing moves.
    ///
    /// The `Shipping` control at the end is what makes the two `nil`s above about the refusal
    /// rather than about the mover never moving anything in this fixture.
    @Test func aRenameTheStoreRefusedLeavesEveryCardWhereItWas() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "Done")
        ]
        let card = AppTask(title: "in the column")
        card.sectionName = "Doing"
        card.area = area
        context.insert(card)
        area.tasks = [card]
        try context.save()

        let base = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        // A name another column already has. The apply declines, so the store still says `Doing`.
        applyColumnEditsTheWayThePopoverDoes(base: base, typedName: "Done", area: area)
        #expect(area.sectionConfigs.first { $0.uuid == base.uuid }?.name == "Doing")
        #expect(
            KanbanSectionStateSupport.moveCardsToStoredName(
                universeTasks: [card], area: area, project: nil,
                columnUUID: base.uuid, typedName: "Done", filedName: "Doing"
            ) == nil
        )
        #expect(card.sectionName == "Doing", "the cards moved for a name that was never stored")

        // An empty name, refused the same way.
        applyColumnEditsTheWayThePopoverDoes(base: base, typedName: "   ", area: area)
        #expect(area.sectionConfigs.first { $0.uuid == base.uuid }?.name == "Doing")
        #expect(
            KanbanSectionStateSupport.moveCardsToStoredName(
                universeTasks: [card], area: area, project: nil,
                columnUUID: base.uuid, typedName: "", filedName: "Doing"
            ) == nil
        )
        #expect(card.sectionName == "Doing")

        // Control: a name nothing else holds is taken, and then the card does move.
        applyColumnEditsTheWayThePopoverDoes(base: base, typedName: "Shipping", area: area)
        #expect(
            KanbanSectionStateSupport.moveCardsToStoredName(
                universeTasks: [card], area: area, project: nil,
                columnUUID: base.uuid, typedName: "Shipping", filedName: "Doing"
            ) == "Shipping"
        )
        #expect(card.sectionName == "Shipping")
    }

    /// **T-358's own case, still holding after T-713 moved the cards to the commit point.**
    ///
    /// The reason `editorBase` is frozen: the popover snapshots name, colour and due date when it
    /// opens and writes all three, so a colour press must not write the *old* name back over a
    /// rename that landed from another device while the popover was up. The merge applies only the
    /// fields that differ from `base`, and the name does not differ, so the remote name survives.
    ///
    /// **The half this ticket adds is the second assertion**: the commit point's card move must not
    /// undo that either. A colour press has typed no rename, the typed name is not what the store
    /// holds, and the mover declines — so no card is re-pointed behind a colour press, and none is
    /// re-pointed at a name the local user never asked for.
    ///
    /// If this test ever goes red, the fix traded T-713 for the bug the snapshot exists to prevent.
    @Test func aColourPressStillCannotWriteAStaleNameOverARenameFromAnotherDevice() throws {
        let context = ModelContext(try container())
        let area = Area(name: "Board")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing", colorHex: TaskSectionDefaults.defaultColorHex)
        ]
        let card = AppTask(title: "in the column")
        card.sectionName = "Doing"
        card.area = area
        context.insert(card)
        area.tasks = [card]
        try context.save()

        // The popover opens and freezes the column it opened on.
        let base = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        // Another device renames the same column while the popover is up.
        area.updateSectionConfig(uuid: base.uuid) { config in config.name = "Shipping" }
        #expect(area.sectionConfigs.first { $0.uuid == base.uuid }?.name == "Shipping")

        // The user presses a colour swatch and has typed nothing into the name field.
        applyColumnEditsTheWayThePopoverDoes(
            base: base, typedName: base.name, colorHex: Theme.greenHex, area: area
        )

        let stored = try #require(area.sectionConfigs.first { $0.uuid == base.uuid })
        #expect(stored.name == "Shipping", "the colour press wrote the stale name back over the remote rename")
        #expect(stored.colorHex == Theme.greenHex, "the colour the user actually pressed was dropped")

        // And the commit point moves no card for it.
        #expect(
            KanbanSectionStateSupport.moveCardsToStoredName(
                universeTasks: [card], area: area, project: nil,
                columnUUID: base.uuid, typedName: base.name, filedName: "Doing"
            ) == nil
        )
        #expect(card.sectionName == "Doing", "a colour press re-pointed a card")

        // Control: the same write with the name *edited* does reach the store, so the assertion
        // above is about the freeze rather than about the merge never writing a name at all.
        applyColumnEditsTheWayThePopoverDoes(
            base: base, typedName: "Doingxy", colorHex: Theme.greenHex, area: area
        )
        #expect(area.sectionConfigs.first { $0.uuid == base.uuid }?.name == "Doingxy")
    }

    /// **Where the move lives, and where the snapshot does not (T-713).**
    ///
    /// The behavioural tests above drive `KanbanSectionStateSupport.moveCardsToStoredName`
    /// directly; this is what ties that function to the column, since `applySectionEdits` and
    /// `commitSectionEdits` are private members of a SwiftUI `View`.
    ///
    /// Three things are asserted, and the third is the user decision rather than an implementation
    /// detail: `editorBase` is assigned in exactly one place, `openSectionEditor()`. Advancing it
    /// after a move is the one-line repair this ticket names and refuses — it is the snapshot T-358
    /// froze, and the test above is the case it was frozen for.
    @Test func theRenameMovesItsCardsOnceAtTheCommitPointRatherThanPerKeystroke() throws {
        let column = try strippingComments(sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        #expect(column.contains("struct ListSectionKanbanColumn: View"), "non-vacuity: wrong file read")

        // The per-keystroke write moves nothing at all.
        let apply = try #require(CadenceSourceScan.functionBody(named: "applySectionEdits", in: column))
        #expect(apply.contains("container.applySectionConfigEdits("), "the apply no longer writes the blob")
        #expect(matches(#"moveTasks\("#, in: apply) == 0,
                "applySectionEdits moves cards again, so an intermediate name reaches them")

        // `applyColumnEditsTheWayThePopoverDoes` above transcribes this function's four declines.
        // Asserting each one here is what stops the transcription and the original drifting apart.
        for decline in [
            "let trimmed = base.isDefault ? base.name : editorName.trimmingCharacters(in: .whitespacesAndNewlines)",
            "guard !trimmed.isEmpty else { return }",
            "guard current.contains(where: { $0.uuid == base.uuid }) else { return }",
            "current.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })"
        ] {
            #expect(apply.contains(decline), "applySectionEdits no longer spells: \(decline)")
        }

        // The commit point does, after the apply and before the flush.
        let commit = try #require(CadenceSourceScan.functionBody(named: "commitSectionEdits", in: column))
        #expect(commit.contains("moveCardsToStoredColumnName()"))
        let applied = try #require(commit.range(of: "applySectionEdits()"))
        let move = try #require(commit.range(of: "moveCardsToStoredColumnName()"))
        let flush = try #require(commit.range(of: "CadenceInPlaceEditFlush.flush(in: modelContext)"))
        #expect(applied.upperBound < move.lowerBound, "the cards move before the name is applied")
        #expect(move.upperBound < flush.lowerBound, "the cards move after the commit that would report a refusal")

        // The mover asks the shared decision rather than re-deriving one here, and it hands it the
        // name the cards are under — not the frozen snapshot.
        let mover = try #require(CadenceSourceScan.functionBody(named: "moveCardsToStoredColumnName", in: column))
        #expect(mover.contains("KanbanSectionStateSupport.moveCardsToStoredName("))
        #expect(mover.contains("filedName: filedCardName"))
        #expect(mover.contains("editorFiledCardName = filed"))
        #expect(matches(#"editorBase\.name|base\.name"#, in: mover) == 0,
                "the move takes its source from the frozen snapshot again")

        // **The decision: `editorBase` is never advanced.** One assignment, in `openSectionEditor`.
        #expect(matches(#"editorBase = "#, in: column) == 1, "editorBase is assigned somewhere other than the open")
        let open = try #require(CadenceSourceScan.functionBody(named: "openSectionEditor", in: column))
        #expect(open.contains("editorBase = section"))
        #expect(open.contains("editorFiledCardName = section.name"))

        // And the cards' name is its own piece of state, read through one accessor.
        #expect(column.contains("@State private var editorFiledCardName: String?"))
        #expect(matches(#"editorFiledCardName = "#, in: column) == 2, "the cards' filed name is written somewhere else too")
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
