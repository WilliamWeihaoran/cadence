import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-319: iOS task creation reported success for a task that was not saved.
///
/// `iOSCreateTaskSheet.create()` built the task, called `try? modelContext.save()`, and then ran
/// the entire success experience over the result — a notification reconcile pass, `onCreated?`,
/// and a dismissal — with no branch in which the save had failed. The user watched the sheet close
/// on a task the store never took.
///
/// **Two halves, both load-bearing.** The behavioural half runs against a real container through
/// `TaskCreationService.createTask`, which is where the commit now lives and which this test
/// target can reach. The source half pins that the sheet uses it and that nothing below the commit
/// runs when it throws — `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS,
/// so a scan is the only tool available for the view itself.
@MainActor
struct CadenceCreateTaskCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private func draft(
        title: String,
        subtaskTitles: [String] = []
    ) -> TaskCreationDraft {
        TaskCreationDraft(
            title: title,
            notes: "Typed by hand.",
            priority: .high,
            container: .inbox,
            sectionName: "",
            dueDateKey: "2026-06-20",
            scheduledDateKey: "",
            subtaskTitles: subtaskTitles,
            tags: []
        )
    }

    // MARK: - What the commit actually does

    /// The success path, asserted from a **second context on the same container**: a single-context
    /// assertion passes against the bug, because the sheet's own context reports the task present
    /// whether or not the save threw.
    @Test func acreatedTaskIsInTheStoreBeforeTheSheetCouldClose() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let task = try #require(
            try TaskCreationService(areas: [], projects: [])
                .createTask(from: draft(title: "Ship the fix", subtaskTitles: ["First", "Second"]),
                            into: modelContext)
        )
        #expect(task.title == "Ship the fix")
        #expect(!modelContext.hasChanges, "the creation was left pending in the context")

        let store = ModelContext(container)
        let stored = try store.fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 1)
        #expect(stored.first?.title == "Ship the fix")
        #expect(stored.first?.notes == "Typed by hand.")
        #expect(stored.first?.priority == .high)
        #expect(stored.first?.dueDate == "2026-06-20")
        #expect(
            try store.fetch(FetchDescriptor<Subtask>()).map(\.title).sorted() == ["First", "Second"],
            "the subtasks were inserted but never committed"
        )
    }

    /// The failure path. A creation rolls back: the composer still holds every field the user
    /// typed, so undoing and reporting is strictly better than half-creating.
    @Test func acreationThatCannotBeCommittedTakesItsTaskAndSubtasksBackOut() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        #expect(throws: CommitRefused.self) {
            try TaskCreationService(areas: [], projects: [])
                .createTask(
                    from: draft(title: "Never lands", subtaskTitles: ["Orphan"]),
                    into: modelContext,
                    commit: { _ in throw CommitRefused() }
                )
        }

        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty,
            "the sheet's own context still holds the task the commit refused"
        )
        #expect(
            try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty,
            "the subtask outlived the task, attached to nothing"
        )
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// A failed creation must not take the user's existing tasks with it. This is why the insert
    /// undo deletes what it inserted rather than rolling the context back.
    @Test func afailedCreationLeavesTheTasksAlreadyInTheStoreAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let existing = AppTask(title: "Yesterday's task")
        modelContext.insert(existing)
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try TaskCreationService(areas: [], projects: [])
                .createTask(
                    from: draft(title: "Never lands"),
                    into: modelContext,
                    commit: { _ in throw CommitRefused() }
                )
        }

        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title)
                == ["Yesterday's task"])
    }

    /// An empty title is "nothing to create", not a failure — the same answer `insertTask` gave,
    /// and the reason `create()` can still `guard let task` after the `do`/`catch`.
    @Test func anEmptyDraftIsNilRatherThanAThrow() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        #expect(try TaskCreationService(areas: [], projects: [])
            .createTask(from: draft(title: "   "), into: modelContext) == nil)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// The sentence the sheet shows, held next to the service that produces the failure so the
    /// composers cannot come to word it differently.
    @Test func theCreationFailureNoticeNamesTheSave() {
        #expect(TaskCreationService.saveFailureNotice == "Couldn't save this task.")
    }

    // MARK: - The sheet

    /// `create()` is a private method on a SwiftUI view, so this is scoped to its **function
    /// body**, and the ordering is asserted as positions rather than as "contains".
    ///
    /// The bug was not that the sheet failed to save. It was that everything after the save ran
    /// unconditionally: the reconcile, the callback and the dismissal are the success experience,
    /// and each one has to sit after the point where a throw has already returned.
    @Test func theIOSComposerCommitsBeforeItReportsSuccess() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCreateTaskSheet.swift")
        #expect(raw.count > 400, "iOSCreateTaskSheet.swift read as \(raw.count) characters")

        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let create = try #require(
            CadenceSourceScan.functionBody(named: "create", in: stripped),
            "could not find create()"
        )

        // It goes through the committing entry point, and the old swallowed save is gone.
        #expect(create.contains(".createTask("))
        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0,
            "create() still swallows an error"
        )
        #expect(CadenceSourceScan.matchCount(#"insertTask\("#, in: create) == 0)

        // The failure branch exists and says why.
        let failure = try #require(
            create.range(of: "actionError = TaskCreationService.saveFailureNotice"),
            "create() has no branch that reports a failed commit"
        )
        let failureReturn = try #require(
            create.range(of: "return", range: failure.upperBound..<create.endIndex),
            "the failure branch falls through into the success path"
        )

        // And every part of the success experience sits after it.
        for spelling in ["HabitNotificationReconcileSupport.scheduleReconcile", "onCreated?(", "dismiss()"] {
            let success = try #require(
                create.range(of: spelling),
                "create() no longer spells \(spelling)"
            )
            #expect(
                success.lowerBound > failureReturn.upperBound,
                "\(spelling) runs before the failed commit has returned"
            )
        }

        // Exactly one dismissal in create(), so there is no second unguarded one below.
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: create) == 1)
    }

    /// The needles above match the spelling they hunt and miss the one they protect — otherwise
    /// the two `== 0` assertions are true of any text at all.
    @Test func theSwallowedSaveNeedlesMatchTheOldSpellingsOnly() {
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try? modelContext.save()") == 1)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try service.createTask(from: draft, into: c)") == 0)
        #expect(CadenceSourceScan.matchCount(#"insertTask\("#, in: ".insertTask(from: draft, into: c)") == 1)
        #expect(CadenceSourceScan.matchCount(#"insertTask\("#, in: ".createTask(from: draft, into: c)") == 0)
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: "dismiss()") == 1)
    }

    // MARK: - T-364: the other six surfaces

    /// One surface that creates a task and then reports that it did.
    ///
    /// **T-364.** Six of these called `insertTask` — the sibling that leaves the commit to the
    /// caller — and then skipped the save entirely or ran it through `try?` and reported success
    /// regardless. `failureBranch` is a regex rather than a substring on purpose: a `catch` that
    /// exists but falls through is exactly the bug, so the pattern has to see the exit too.
    private struct CommitSurface {
        let path: String
        let function: String
        /// The whole `catch` block, which must both say what went wrong and leave the function.
        let failureBranch: String
        /// Spellings that may only run once the commit has landed.
        let successSpellings: [String]
    }

    /// A composer reports a failed commit where the user is already looking and keeps everything
    /// they typed; an embed reports it by handing back no reference at all, which is what stops the
    /// note text from being written.
    private static let composerFailureBranch =
        #"catch \{[^}]*actionError = TaskCreationService\.saveFailureNotice[^}]*return[^}]*\}"#
    private static let embedFailureBranch = #"catch \{[^}]*return nil[^}]*\}"#

    private var commitSurfaces: [CommitSurface] {
        [
            CommitSurface(
                path: "Cadence/macOS/Sheets/CreateTaskSheet.swift",
                function: "createTask",
                failureBranch: Self.composerFailureBranch,
                successSpellings: [
                    "HabitNotificationReconcileSupport.scheduleReconcile",
                    "dismiss()",
                    "taskCreationManager.presentSuccessToast()"
                ]
            ),
            CommitSurface(
                path: "Cadence/macOS/Views/InlineTaskComposerView.swift",
                function: "create",
                failureBranch: Self.composerFailureBranch,
                successSpellings: [
                    "HabitNotificationReconcileSupport.scheduleReconcile",
                    "title = \"\"",
                    "entryGeneration += 1"
                ]
            ),
            CommitSurface(
                path: "Cadence/macOS/Views/NotePanel.swift",
                function: "createEmbeddedTask",
                failureBranch: Self.embedFailureBranch,
                successSpellings: ["recentEmbeddedTasks[", "return .task("]
            ),
            CommitSurface(
                path: "Cadence/macOS/Views/NoteEditorPane.swift",
                function: "createEmbeddedTask",
                failureBranch: Self.embedFailureBranch,
                successSpellings: ["recentEmbeddedTasks[", "return .task("]
            ),
            CommitSurface(
                path: "Cadence/macOS/Views/ListNotesSupportViews.swift",
                function: "createEmbeddedTask",
                failureBranch: Self.embedFailureBranch,
                successSpellings: ["recentEmbeddedTasks[", "return .task("]
            ),
            CommitSurface(
                path: "Cadence/iOS/iOSMarkdownEditingSurface.swift",
                function: "createEmbeddedTaskReference",
                failureBranch: Self.embedFailureBranch,
                successSpellings: [
                    "recentEmbeddedTasks[",
                    "return NoteReferenceParser.taskReferenceMarkdown("
                ]
            )
        ]
    }

    /// Every remaining creation surface goes through the committing entry point, and nothing that
    /// tells the user it worked sits above the branch where it did not.
    ///
    /// For the four note/markdown embeds "reports success" means **returning the reference**: the
    /// editors write `[[task:UUID|Title]]` into the note exactly when this returns non-nil, so the
    /// only thing keeping a note free of a reference to a task the store never took is that the
    /// return sits below the `catch`.
    @Test func everyRemainingCreateSurfaceCommitsBeforeItReportsSuccess() throws {
        for surface in commitSurfaces {
            let raw = try CadenceSourceScan.sourceFile(surface.path)
            #expect(raw.count > 400, "\(surface.path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(surface.path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(surface.path): the stripper changed the length")

            let body = try #require(
                CadenceSourceScan.functionBody(named: surface.function, in: stripped),
                "could not find \(surface.function)() in \(surface.path)"
            )
            #expect(!body.isEmpty, "\(surface.function)() in \(surface.path) read as an empty body")
            #expect(
                body.contains(".createTask("),
                "\(surface.path) does not create through the committing entry point"
            )
            #expect(
                CadenceSourceScan.matchCount(#"insertTask\("#, in: body) == 0,
                "\(surface.path) still calls the non-committing sibling"
            )
            #expect(
                CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                "\(surface.path) still swallows an error"
            )

            let failureBranch = try #require(
                body.range(of: surface.failureBranch, options: .regularExpression),
                "\(surface.path) has no catch branch that both reports the failure and returns"
            )
            for spelling in surface.successSpellings {
                let success = try #require(
                    body.range(of: spelling),
                    "\(surface.path) no longer spells \(spelling)"
                )
                #expect(
                    success.lowerBound >= failureBranch.upperBound,
                    "\(surface.path): \(spelling) runs before the failed commit has returned"
                )
            }
        }
    }

    /// The note embed pane bumps `note.updatedAt` as part of the creation, so that bump has to be
    /// put back when the commit throws — otherwise a refused embed leaves the note marked as
    /// edited for text that was never written. Both non-success exits restore it, which is why the
    /// count is two rather than one.
    @Test func theNoteEmbedPaneRestoresItsTimestampBumpOnEveryFailedExit() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorPane.swift")
        #expect(raw.count > 400, "NoteEditorPane.swift read as \(raw.count) characters")

        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "createEmbeddedTask", in: stripped),
            "could not find createEmbeddedTask()"
        )

        let snapshot = try #require(
            body.range(of: "let previousUpdatedAt = note.updatedAt"),
            "the bump is made with nothing held to put back"
        )
        let bump = try #require(body.range(of: "note.updatedAt = Date()"))
        #expect(snapshot.upperBound <= bump.lowerBound, "the snapshot is taken after the bump")
        #expect(
            CadenceSourceScan.matchCount(#"note\.updatedAt = Date\(\)"#, in: body) == 1,
            "the note is bumped more than once"
        )
        #expect(
            CadenceSourceScan.matchCount(#"note\.updatedAt = previousUpdatedAt"#, in: body) == 2,
            "one of the two non-success exits keeps the note marked as edited"
        )
    }

    /// Why that restore is the pane's own job and not something the shared helper does for it.
    ///
    /// `commitInsert` undoes **the insert**, deliberately: it deletes the objects it was handed and
    /// leaves every other pending edit in the context alone, so a failed creation cannot take the
    /// user's unrelated work with it. The note's timestamp is one of those unrelated edits, so
    /// nothing puts it back and the caller has to.
    ///
    /// **`hasChanges` is the assertion that can tell the two undo shapes apart.** The value on
    /// `note.updatedAt` cannot: a live `Note` reference reads back the assigned value whether the
    /// context kept the edit or discarded it, so a `commitInsert` mutated to `modelContext
    /// .rollback()` survives an equality check on it. The pending-change flag does not — a targeted
    /// delete leaves the note's edit pending, a context rollback throws it away with everything
    /// else. Found by mutating exactly that and watching the equality check pass.
    @Test func aRefusedCreationLeavesTheNotesOwnTimestampForTheCallerToRestore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let note = Note(kind: .list, title: "Plan")
        modelContext.insert(note)
        try modelContext.save()

        let previousUpdatedAt = note.updatedAt
        let bumped = Date(timeIntervalSince1970: 1_800_000_000)
        note.updatedAt = bumped

        #expect(throws: CommitRefused.self) {
            try TaskCreationService(areas: [], projects: [])
                .createTask(
                    from: draft(title: "Embedded"),
                    into: modelContext,
                    commit: { _ in throw CommitRefused() }
                )
        }

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(
            modelContext.hasChanges,
            "the undo discarded the note's pending edit too, so the pane's restore is dead code"
        )
        #expect(note.updatedAt == bumped && bumped != previousUpdatedAt)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// Non-vacuity for the scan above: it names six real files, each holding the function it says
    /// it does, and a path that does not exist throws rather than reading as an empty pass.
    @Test func theSixCreateSurfaceFilesAreAllReachedByTheScan() throws {
        var paths: Set<String> = []
        for surface in commitSurfaces {
            let raw = try CadenceSourceScan.sourceFile(surface.path)
            #expect(raw.count > 400, "\(surface.path) read as \(raw.count) characters")
            #expect(
                raw.contains("func \(surface.function)("),
                "\(surface.path) holds no func \(surface.function)("
            )
            paths.insert(surface.path)
        }
        #expect(paths.count == 6, "the surface table lost a file: \(paths.sorted())")

        #expect(throws: (any Error).self) {
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ThereIsNoSuchFile.swift")
        }
    }

    /// The two `catch` patterns match a branch that reports and leaves, and miss one that only
    /// reports — which is the whole difference this ticket is about.
    @Test func theFailedCommitBranchPatternsRequireTheCatchToLeaveTheFunction() {
        #expect(CadenceSourceScan.matchCount(Self.embedFailureBranch, in: "catch {\n return nil\n }") == 1)
        #expect(CadenceSourceScan.matchCount(Self.embedFailureBranch, in: "catch {\n }") == 0)
        #expect(CadenceSourceScan.matchCount(
            Self.composerFailureBranch,
            in: "catch {\n actionError = TaskCreationService.saveFailureNotice\n return\n }"
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            Self.composerFailureBranch,
            in: "catch {\n actionError = TaskCreationService.saveFailureNotice\n }"
        ) == 0)
    }
}
