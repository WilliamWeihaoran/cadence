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
/// The other half are source-text assertions, for the reason `CadenceListArchiveSurfaceTests`
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
        #expect(summary.settledLine == "2 open tasks will be cancelled")

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

    /// Both directions settle, and the sentence names which. A confirmation that said "cancelled"
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
                .settledLine == "1 open task will be cancelled"
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
        for path in try swiftFiles(under: "Cadence/iOS") {
            let code = try strippingComments(sourceFile(path))
            #expect(
                !code.contains("$draft.isArchived"),
                "\(path) drafts a column's archived flag instead of acting on it"
            )
            #expect(
                !code.contains("$draft.isCompleted"),
                "\(path) drafts a column's completed flag instead of acting on it"
            )
        }
    }

    /// The shape half of the ticket. The two `Toggle`s are gone, the decision is asked once, and it
    /// is asked by the editor rather than by the row — so a second column surface cannot come to
    /// ask a different question.
    @Test func theListEditorAsksTheDecisionOnceAndDraftsNeitherFlag() throws {
        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(!editor.contains("Toggle(\"Completed\""))
        #expect(!editor.contains("Toggle(\"Archived\""))

        try expectOccurrences(of: "requiresConfirmation", at: [
            "Cadence/iOS/iOSListEditorViews.swift": 1,
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 0
        ])

        // One confirmation, built in one place, and it is the same sheet the list archive uses.
        try expectCallSites(of: "iOSWindDownConfirmationSheet", at: [
            "Cadence/iOS/iOSColumnWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListArchiveSupport.swift": 1,
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

    /// Without this, every zero and every absence assertion above could be passing because the
    /// reader returned an empty string, or because the scan was pointed at the wrong folder.
    @Test func theSourceScanActuallyReadsTheseFiles() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300)
        #expect(files.contains("Cadence/iOS/iOSColumnWindDownSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSWindDownConfirmation.swift"))
        #expect(files.contains("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/KanbanSectionColumnView.swift"))

        // The `Toggle("Completed"` / `Toggle("Archived"` absence checks would pass vacuously if the
        // row had stopped drawing toggles at all, or if the reader had returned nothing.
        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(editor.contains("private struct iOSSectionDraftRow: View"))
        #expect(editor.contains("Toggle(\"Due date\""))
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
        #expect(support.contains("config.isCompleted = true"))
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
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
