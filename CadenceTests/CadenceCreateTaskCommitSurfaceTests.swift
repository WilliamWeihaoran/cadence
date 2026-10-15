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

    // MARK: - T-470 / T-471: the iOS calendar quick-create sheet

    /// The sentence a refused block creation shows. It names the object being made, and it is not
    /// the task sentence, which is the whole reason it is a second constant rather than a reuse of
    /// `TaskCreationService.saveFailureNotice`. The quick-create sheet's Block branch that first
    /// read it is gone ([[T-3170]]); the drag-two-tasks-together gestures still do.
    @Test func theBlockCreationFailureNoticeNamesTheBlockRatherThanATask() {
        #expect(CadenceTaskMutationSupport.bundleSaveFailureNotice == "Couldn't save this block.")
        #expect(CadenceTaskMutationSupport.bundleSaveFailureNotice != TaskCreationService.saveFailureNotice)
        #expect(
            CadenceTaskMutationSupport.bundleSaveFailureNotice
                != CadenceTaskMutationSupport.deleteFailureNotice
        )
        // The create family's shape: one sentence, no "Nothing was …" promise.
        #expect(!CadenceTaskMutationSupport.bundleSaveFailureNotice.contains("Nothing"))
        #expect(CadenceTaskMutationSupport.bundleSaveFailureNotice.hasPrefix("Couldn't save this "))
    }

    /// T-470. `createTask()` guarded on `try? insertScheduledTask(...)` and returned on `nil`, so a
    /// refused save and an empty title produced the identical silent exit: the create button looked
    /// inert while the sheet stayed open with no word on it — and this is the *same sheet* whose
    /// Event branch has reported its refusals since T-324.
    ///
    /// Source shape, not behaviour: `Cadence/iOS/` is behind `#if os(iOS)` and this target builds
    /// for macOS, so the view cannot be compiled here, let alone driven. Scoped to the function
    /// body; the ordering is asserted as positions rather than as "contains".
    @Test func theQuickCreateSheetReportsARefusedTaskRatherThanLookingInert() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(raw.count > 400, "iOSCalendarQuickCreateSheet.swift read as \(raw.count) characters")

        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "createTask", in: stripped),
            "could not find createTask()"
        )
        #expect(
            body.contains("CadenceTaskMutationSupport.insertScheduledTask("),
            "createTask() body looks wrong"
        )
        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
            "createTask() still swallows the insert error"
        )

        let failureBranch = try #require(
            body.range(of: Self.composerFailureBranch, options: .regularExpression),
            "createTask() has no catch branch that both reports the failure and returns"
        )

        // The empty-title answer stays a silent return -- `insertScheduledTask` returns `nil`
        // rather than throwing for a title there is nothing to make a task out of, exactly as
        // `iOSCreateTaskSheet.create()` still `guard let task = created`s after its own `do`. What
        // must not happen is dismissing over it.
        let nothingToCreate = try #require(
            body.range(of: #"guard created != nil else \{ return \}"#, options: .regularExpression),
            "createTask() dismisses over an insert that made nothing"
        )
        #expect(
            nothingToCreate.lowerBound >= failureBranch.upperBound,
            "the nothing-to-create guard sits above the failure branch"
        )

        for spelling in ["HabitNotificationReconcileSupport.scheduleReconcile", "dismiss()"] {
            let success = try #require(
                body.range(of: spelling),
                "createTask() no longer spells \(spelling)"
            )
            #expect(
                success.lowerBound >= nothingToCreate.upperBound,
                "createTask(): \(spelling) runs before the failed insert has returned"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: body) == 1,
            "createTask() has a second, unguarded dismissal"
        )
    }

    /// **[[T-3170]].** The sheet creates a task or an event and nothing else: the Block segment,
    /// its `createBundle()` and the empty-slot constructor it called are gone with the Block
    /// feature. T-471's two pins on that branch (no dismissal over a refused block, and the block
    /// in the store before the sheet could close) went with it — there is no branch left to hold
    /// to either rule.
    ///
    /// Source shape, for the same `#if os(iOS)` reason as above: this target cannot compile the
    /// sheet, so it reads it with comments stripped.
    @Test func theQuickCreateSheetOffersNoBlockArm() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(raw.count > 400, "iOSCalendarQuickCreateSheet.swift read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)

        let kindEnum = try #require(
            stripped.range(of: #"enum iOSCalendarQuickCreateKind[^{]*\{[^}]*\}"#, options: .regularExpression),
            "could not find iOSCalendarQuickCreateKind's case list"
        )
        let cases = CadenceSourceScan.matchCount(#"\bcase [a-z]+\n"#, in: String(stripped[kindEnum]))
        #expect(cases == 2, "iOSCalendarQuickCreateKind declares \(cases) cases, not task and event")
        #expect(CadenceSourceScan.matchCount(#"\bcase bundle\b"#, in: stripped) == 0)
        #expect(CadenceSourceScan.matchCount(#"\.bundle\b"#, in: stripped) == 0)
        #expect(CadenceSourceScan.matchCount(#"insertBundle\("#, in: stripped) == 0)
        #expect(CadenceSourceScan.matchCount(#"bundleSaveFailureNotice"#, in: stripped) == 0)
    }

    /// Neither branch may spell its own sentence: both read a shared constant, so the sheet cannot
    /// come to word "that didn't work" three ways -- which is the note its own `actionErrorNotice`
    /// already carries about the Event branch.
    @Test func theQuickCreateSheetReadsSharedFailureNoticesRatherThanItsOwn() throws {
        let stripped = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        )
        #expect(stripped.contains("actionError = TaskCreationService.saveFailureNotice"))
        #expect(
            CadenceSourceScan.matchCount(#""Couldn.t save this"#, in: stripped) == 0,
            "the sheet spells a save-failure sentence itself"
        )
    }

    /// The needles above match the spellings they hunt and miss the ones they protect -- otherwise
    /// the `== 0` assertions are true of any text at all.
    @Test func theQuickCreateCommitNeedlesMatchTheOldSpellingsOnly() {
        #expect(CadenceSourceScan.matchCount(
            #"try\?"#,
            in: "guard (try? CadenceTaskMutationSupport.insertScheduledTask("
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"try\?"#,
            in: "try CadenceTaskMutationSupport.insertBundle("
        ) == 0)
        #expect(CadenceSourceScan.matchCount(#"\bcase [a-z]+\n"#, in: "case task\n case bundle\n case event\n") == 3)
        #expect(CadenceSourceScan.matchCount(#"\bcase [a-z]+\n"#, in: "case .task: return \"Task\"\n") == 0)
        #expect(CadenceSourceScan.matchCount(#"\.bundle\b"#, in: "case .bundle:") == 1)
        #expect(CadenceSourceScan.matchCount(#"\.bundle\b"#, in: "task.bundled") == 0)
        #expect(CadenceSourceScan.matchCount(
            #"guard created != nil else \{ return \}"#,
            in: "guard created != nil else { return }"
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"guard created != nil else \{ return \}"#,
            in: "guard let task = created else { return }"
        ) == 0)
        #expect(CadenceSourceScan.matchCount(#""Couldn.t save this"#, in: "\"Couldn't save this block.\"") == 1)
        #expect(CadenceSourceScan.matchCount(
            #""Couldn.t save this"#,
            in: "CadenceTaskMutationSupport.bundleSaveFailureNotice"
        ) == 0)
    }
}

/// **T-589.** An inline notice that outlives the thing it is complaining about.
///
/// `iOSSchedulePanel`'s timed-task composer drew `quickCreateError` under its title field, and the
/// two clears it had — `selectQuickCreateStart` and `cancelQuickCreate` — were both about the
/// *composer*, not about the field. So "Add a title first." sat there in red while you typed the
/// title, which is the one edit that answers it. Reachable in one keystroke: the `+` was disabled
/// on a whitespace-only title, but `.onSubmit` on the field was not, so Return with an empty field
/// posted the notice and nothing took it down.
///
/// **The composer this guarded no longer exists; the rule it guards does** ([[T-3169]]).
/// `iOSScheduleQuickCreateBar` and its three `quickCreate*` properties were deleted when the iPad
/// timeline stopped creating through a bar bolted under the canvas. The notice, the field and the
/// clear all moved into `CadenceSchedulePanel`, which is **shared**, so this suite now reads
/// `Cadence/Shared/Components/` — and the rule got wider rather than narrower in the move, because
/// the panel is the one macOS will adopt under [[T-3171]] as well.
///
/// Re-pointed, not relaxed: every claim below is the claim it was, against the symbols that carry
/// it now (`draft.title` for `quickCreateTitle`, `actionError` for `quickCreateError`, `commit()`
/// for `createScheduledTask()`). It is still a scan rather than a compiled test, for the same
/// reason as the tests above — a SwiftUI body cannot be exercised from this target.
///
/// **Return stays unguarded, deliberately**, and that is the other half of the fix. Disabling the
/// button is a visible refusal; silently swallowing Return is an inert control with no word on it,
/// which is exactly what T-470 and T-471 went through this app removing. Return reports, and the
/// report goes away by itself.
struct CadenceScheduleComposerNoticeTests {
    private static let panelPath = "Cadence/Shared/Components/CadenceSchedulePanel.swift"

    private func panelSource() throws -> String {
        let raw = try CadenceSourceScan.sourceFile(Self.panelPath)
        #expect(raw.count > 400, "CadenceSchedulePanel.swift read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")
        return stripped
    }

    /// The bar really is gone, rather than this suite having quietly stopped looking at it. Without
    /// this, re-pointing the three tests below would be indistinguishable from abandoning them.
    @Test func theDockedComposerTheseTestsGuardedIsGone() throws {
        let pane = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        )
        #expect(!pane.contains("iOSScheduleQuickCreateBar"))
        #expect(!pane.contains("quickCreateError"))
        #expect(!pane.contains("quickCreateTitle"))
    }

    @Test func typingTheTitleClearsTheNoticeThatAsksForOne() throws {
        let source = try panelSource()

        #expect(
            source.contains("\"Add a title first.\""),
            "the notice this is about is no longer spelled here — re-point the test or delete it"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"onChange\(of: draft\.title\)[^}]*actionError = nil"#,
                in: source
            ) == 1,
            "nothing clears actionError when the title changes"
        )
    }

    /// The notice is still posted rather than swallowed: Return on an empty field says something.
    @Test func returnOnAnEmptyFieldStillReportsRatherThanDoingNothing() throws {
        let source = try panelSource()

        #expect(source.contains(".onSubmit(commit)"), "the field no longer submits")
        let body = try #require(
            CadenceSourceScan.functionBody(named: "commit", in: source),
            "could not find commit()"
        )
        #expect(body.contains("actionError = \"Add a title first.\""))
        // The guard must *report* and return, not refuse silently. A `canCommit`-style early exit
        // here would make Return do nothing at all, which is the inert control this test exists for.
        #expect(
            CadenceSourceScan.matchCount(#"guard canCommit"#, in: body) == 0,
            "commit() grew a silent empty-title guard, which makes the notice unreachable"
        )
    }

    /// The needles match the spelling they hunt and miss the one they protect.
    @Test func theComposerNoticeNeedlesMatchTheOldSpellingOnly() {
        let clearPattern = #"onChange\(of: draft\.title\)[^}]*actionError = nil"#
        #expect(CadenceSourceScan.matchCount(
            clearPattern,
            in: ".onChange(of: draft.title) { _, _ in\n actionError = nil\n }"
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            clearPattern,
            in: ".onChange(of: draft.kind) { _, _ in\n actionError = nil\n }"
        ) == 0)
        #expect(CadenceSourceScan.matchCount(
            clearPattern,
            in: ".onChange(of: draft.title) { _, _ in\n isTitleFocused = false\n }"
        ) == 0)
    }
}
