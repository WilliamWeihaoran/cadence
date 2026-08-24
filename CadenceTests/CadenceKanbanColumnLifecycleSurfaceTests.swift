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
