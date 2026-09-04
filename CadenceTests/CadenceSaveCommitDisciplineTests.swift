import Foundation
import Testing

/// **The `try? save()` rule, and the scan that enforces it (T-322).**
///
/// `try? modelContext.save()` is this repo's most-repeated line — 108 of them under `Cadence/` when
/// this file was written — and eight separate audits had each found one instance of it and filed
/// one ticket. What was missing was not another fix; it was a sentence saying which of the 108 are
/// wrong, so the 109th is written correctly instead of found by the ninth audit.
///
/// **The rule.** A `save()` may be written `try?` only when it commits *nothing but in-place field
/// edits to objects the store already holds*, and nothing after it tells the user it worked. Two
/// halves, and a site fails the rule if either one holds:
///
/// 1. **Existence.** The function that reaches the save also inserts or deletes. Commit it through
///    `CadencePendingChangePersistence.commitInsert` or `commitDelete` and throw.
/// 2. **Report.** Something in the same block dismisses, opens a sheet on what was just written, or
///    calls a completion handler — `dismiss()`, `isPresented = false`, `presentedNote = …`,
///    `onSave(…)`. Commit it through `CadencePendingChangePersistence.commitEdit(in:undo:)` and
///    throw; the caller catches and names the failure where the user is already looking.
///    **And one frame down (T-566).** The same report over a *callee* that swallows — the button
///    calls `save()`, `save()` calls a shared mutation, the mutation holds the `try?`. Every frame
///    passes the reading above, and the sheet still closes over a store that refused. Same fix,
///    applied to whichever frame owns the commit.
/// 3. **Commit reach.** The function changes existence and reaches **no commit at all** — added by
///    T-503, because halves 1 and 2 both key on the *presence* of a `try? …save()` and so a
///    function that never commits passed both. Twenty-one declarations were in that state; four of
///    them also reported success. The ~17 helpers the half must not fire on are subtracted **by
///    rule** rather than by name: a declaration handed a `ModelContext` is one whose caller owns
///    the unit of work. See `commitReachOffenders`.
///
/// **T-627 closed four measured blind spots, and they moved the count from 7 declarations to 53.**
/// A faithful emulation over all 563 files reproduced the six exemption entries exactly and
/// reported nothing else — which was the non-vacuity evidence *and* the proof that none of an
/// external audit's fifteen sites was caught by any half. The four:
///
/// - **Gap 1.** Only half 2 followed a call one frame down. Existence and commit reach both
///   required a literal `insert(`/`delete(` in the declaration's own body, and this app puts the
///   mutation one frame away from the button by design. `ExistenceIndex`.
/// - **Gap 2.** `declarations(in:)` parsed `func` and the literal `var body`, so a screen written
///   as `private var columnEditor: some View` was invisible to every half. `declarationHead`.
/// - **Gap 3.** Half 3 keyed on `insert(` only, so "delete and never commit" was covered by
///   nothing at all. `existenceCall`.
/// - **Gap 4.** `successReport` was a closed vocabulary missing this app's actual dismissals, and
///   it read only the text *after* the save while three real sites dismiss first. `successReport`,
///   `persistedReport`, and the whole-block window in `reportOffenders`.
///
/// The four exemption lists carry what that widening found. They are a schedule, not a silence:
/// nearly every entry names the ticket that owns its fix, and fixing one deletes its line.
///
/// **Why these and not "handle errors properly".** All three are decidable by reading one function,
/// which is what makes them enforceable below and applicable by a reviewer without judgement. And
/// both name a cost the user actually pays:
///
/// - A refused save does not merely fail to write. This app has **one** `ModelContext`, so the
///   change stays *pending* in it — to be committed by the next unrelated `save()` from any other
///   screen, or discarded by the next unrelated `rollback()` (`commitDelete` and `commitCascade`
///   both call one). Swallowing the error is therefore not "the change did not happen"; it is a
///   coin flip resolved on somebody else's code path. `CadencePendingChangePersistence` exists to
///   make the outcome binary, and its own doc comment names this ticket as the sweep it is the unit
///   of.
/// - The *existence* half is where that hurts most, because a re-render cannot repair it. A field
///   edit that did not land still shows the right value and is corrected by the next fetch; an
///   object that does or does not exist has no such halfway reading.
/// - The *report* half is the one the user sees. T-470 and T-471 were both this: a sheet that
///   dismissed as though it had made something, over a store that had refused.
///
/// **What stays.** 96 of the 108 — a save whose only witness is the value the user is already
/// looking at. `setPriority`, `scheduleToday`, `moveToSection`: the row redraws, the store agrees a
/// moment later or the next fetch corrects it, and there is nothing the user could have done
/// differently. Converting those would be 96 `do`/`catch` blocks buying nothing.
///
/// **Why a source scan and not a type.** The rule is about *call sites in views*, most of them
/// inside a `private func` on a SwiftUI `struct` that no test can call. That is the same reason
/// `CadenceSourceScan` exists at all.
@MainActor
struct CadenceSaveCommitDisciplineTests {

    // MARK: - The sweep

    /// Half 1: no swallowed save sits in a function that changes existence — its own, or one
    /// frame down (T-627 gap 1).
    @Test func noSwallowedSaveCommitsAnInsertOrADelete() throws {
        let existence = try existenceIndexOverTheApp()
        // Non-vacuity for the index, the same handle the one-frame-down report half carries: an
        // empty one silently narrows this half back to the literal-insert reading it had.
        #expect(existence.namesRead >= 30, "the existence index read \(existence.namesRead) callee names")

        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.existenceInstrument(changing: existence),
            allowed: CadenceSaveCommitRule.existenceExemptions
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) reach `try? …save()` from a function that also inserts or deletes. \
            A refused commit there leaves the context and the store disagreeing about whether an \
            object exists. Route it through CadencePendingChangePersistence.commitInsert/commitDelete \
            and throw.
            """
        )
    }

    /// Half 2: no swallowed save is followed, in its own block, by something that reports success.
    @Test func noSwallowedSaveIsFollowedByADismissOrACompletionHandler() throws {
        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.reportInstrument(),
            allowed: CadenceSaveCommitRule.reportExemptions
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) dismiss or call a completion handler after a `try? …save()`. \
            That is T-470/T-471 again: the screen reports success over a store that refused. \
            Commit through CadencePendingChangePersistence.commitEdit(in:undo:) and throw.
            """
        )
    }

    /// Half 2, one frame down: nothing reports success over a commit a *callee* swallowed (T-566).
    ///
    /// The hole half 2 had, and it is not an oversight — it is mechanical. Half 2 needs a literal
    /// `try?` in the reporting declaration's own body, and this app writes its mutations one frame
    /// away from the button: the Save button called `save()`, `save()` called
    /// `CadenceTaskMutationSupport.updateBundle`, and the third frame held the swallow. All three
    /// frames passed halves 1, 2 and 3 while the sheet closed over a store that had refused.
    @Test func noSuccessReportFollowsACommitSwallowedOneFrameDown() throws {
        let index = try swallowingIndexOverTheApp()
        // Non-vacuity for the index itself: an empty one makes this whole half permanently green,
        // and it is built by a fixed point that a parsing mistake would silently empty.
        #expect(index.namesRead >= 50, "the swallowing index read \(index.namesRead) callee names")

        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.indirectReportInstrument(swallowing: index),
            allowed: CadenceSaveCommitRule.indirectReportExemptions
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) report success after calling something that swallows its commit. \
            The frame with the `try?` in it is not the frame the user is looking at: commit \
            through CadencePendingChangePersistence, throw, and let the caller name the failure.
            """
        )
    }

    /// Half 2b: no hand-rolled `order` renumber sits over a swallowed commit, or none (T-614,
    /// [[T-871]]).
    ///
    /// **Read `rearrangementOffenders`' doc before believing this covers the clause.** T-614's
    /// "or a rearrangement the user can see" is a picture, not a word, and half 2's vocabulary is
    /// words. What this half enforces is the *spelling* [[T-868]] and [[T-869]] were written in —
    /// a `for` loop over `\.order` — and it is blind by construction to a blob-stored ordering
    /// ([[T-870]]), to a renumber delegated to `CadenceOrderCommit`, and to a bare
    /// `move(fromOffsets:toOffset:)`. A green run here is evidence about one spelling, not about
    /// the clause. The clause itself is enforced by whoever remembers it; [[T-996]] is the standing
    /// note that says so.
    @Test func noRenumberTheUserCanSeeSitsOverASwallowedOrMissingCommit() throws {
        let existence = try existenceIndexOverTheApp()
        #expect(existence.namesRead >= 30, "the existence index read \(existence.namesRead) callee names")

        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.rearrangementInstrument(changing: existence),
            allowed: CadenceSaveCommitRule.rearrangementExemptions
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) renumber `order` across a run of rows and either swallow the commit or \
            never make one. The rearrangement on screen is the success report, and a refused one \
            reverts at next launch with nothing for the user to retry. Commit through \
            CadenceOrderCommit.commit and show CadenceOrderCommit.failureNotice on `false`.
            """
        )
    }

    /// The non-vacuity this half needs beyond its own witness pair: the six declarations that do
    /// renumber in a loop are still there and are still read as renumbers.
    ///
    /// Without this, a `renumbersInALoop` that stopped matching — a regex typo, a `blockEnd` that
    /// returned the wrong brace — leaves the half above permanently green over a repository that
    /// still reorders things. Named sites rather than a count, because two of the six are
    /// allocations and could legitimately leave.
    @Test func theRearrangementHalfStillReadsTheAppsHandWrittenRenumbers() throws {
        let existence = try existenceIndexOverTheApp()
        for (path, name) in [
            ("Cadence/macOS/Views/SettingsView.swift", "moveContext"),
            ("Cadence/iOS/iOSSettingsView.swift", "moveContext"),
        ] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            // Reading the renumber: the declaration is there and this half parses it as one.
            #expect(
                CadenceSaveCommitRule.renumbersInALoopForTesting(named: name, in: source) == true,
                "\(path):\(name) is no longer read as a renumber, so the half above proves nothing"
            )
            // And it is not an offender, which is the claim T-614 fixed it to make.
            #expect(!CadenceSaveCommitRule.rearrangementOffenders(in: source, changing: existence).contains(name))
        }
    }

    /// Half 3: no declaration inserts and reaches no commit at all (T-503).
    ///
    /// The hole in the other two: both key on the *presence* of a `try? …save()`, so a function
    /// that inserts and commits nothing whatsoever passed both. The exemption list for this half is
    /// empty, because the ~17 helpers it must not fire on are subtracted by
    /// `commitReachOffenders`' signature rule rather than by name.
    @Test func noInsertIsLeftPendingWithNoCommitAnywhereInItsDeclaration() throws {
        let existence = try existenceIndexOverTheApp()
        #expect(existence.namesRead >= 30, "the existence index read \(existence.namesRead) callee names")
        #expect(existence.committersRead >= 100, "the commit index read \(existence.committersRead) names")

        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.commitReachInstrument(changing: existence),
            allowed: CadenceSaveCommitRule.commitReachExemptions
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) insert into a context they own and never commit it. The row stays pending \
            in the app's single ModelContext until some unrelated screen's save takes it or some \
            unrelated rollback() throws it away. Route it through \
            CadencePendingChangePersistence.commitInsert and throw.
            """
        )
    }

    // MARK: - Non-vacuity of the walk

    /// `sweep` refuses an empty or short file list, but it cannot know the tree it walked is the
    /// app. These are the four surfaces the rule is about, one of them the iOS tree the macOS test
    /// target cannot compile — which is exactly why a *source* scan covers it and a behavioural
    /// test cannot.
    @Test func theSaveCommitSweepReachesEverySurfaceOfTheApp() throws {
        let files = try saveCommitSwiftFiles()
        for path in [
            "Cadence/Shared/CadenceTaskMutationSupport.swift",
            "Cadence/Services/TagSupport.swift",
            "Cadence/macOS/Views/SettingsTagsSection.swift",
            "Cadence/iOS/iOSTrackingEditorSheets.swift",
        ] {
            #expect(files.contains(path), "the save-commit sweep never reaches \(path)")
        }

        // Reading contents, not just listing names: a walk that yields paths it cannot open would
        // satisfy every absence assertion above.
        let source = try CadenceSourceScan.sourceFile("Cadence/Shared/CadencePendingChangePersistence.swift")
        #expect(
            source.contains("enum CadencePendingChangePersistence"),
            "non-vacuity: the sweep's reader returned no content"
        )
    }

    /// The reader the sweep uses must blank comments, and this file's neighbours prove why: three
    /// doc comments under `Cadence/` quote the retired `try? modelContext.save()` line as the thing
    /// they were fixed away from. A scan that read prose would report those tombstones as offences
    /// and would have to be silenced by deleting the institutional memory.
    @Test func theSweepReadsCodeRatherThanTheTombstoneCommentsThatQuoteTheRetiredLine() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTrackingMutationSupport.swift")
        #expect(
            raw.contains("try? modelContext.save()"),
            "the tombstone this test is about is gone; pick another file or drop this test"
        )
        let read = CadenceSourceScan.codeOnly(raw)
        #expect(!read.contains("try? modelContext.save()"))
        #expect(read.contains("static func saveGoal("), "codeOnly blanked live code, not just prose")
    }

    // MARK: - The declaration split

    /// The body finder has to skip a `{` that belongs to a **default argument**, and this repo is
    /// full of them now: every `commit: (ModelContext) throws -> Void = { try $0.save() }` puts a
    /// brace inside the signature. Taking the first `{` after `func name(` would return that
    /// closure as the whole body — a body containing `try $0.save()` and nothing else, which is
    /// both the wrong text and one that a careless spelling of the rule would flag.
    @Test func theDeclarationSplitSkipsBracesInsideADefaultArgument() throws {
        let source = """
        enum Sample {
            static func commitThing(
                _ thing: Thing,
                in modelContext: ModelContext,
                commit: (ModelContext) throws -> Void = { try $0.save() }
            ) throws {
                modelContext.insert(thing)
                try commit(modelContext)
            }
        }
        """
        let bodies = CadenceSaveCommitRule.declarations(in: source)
        #expect(bodies.count == 1)
        #expect(bodies.first?.name == "commitThing")
        #expect(bodies.first?.body.contains("modelContext.insert(thing)") == true)
        // The signature half 3 reads is everything up to that same brace — so it carries the
        // `in modelContext: ModelContext` that exempts this helper, and not its body.
        #expect(bodies.first?.signature.contains("in modelContext: ModelContext") == true)
        #expect(bodies.first?.signature.contains("modelContext.insert(thing)") == false)
    }

    /// A save inside a button closure belongs to the declaration that encloses it, so a rule scoped
    /// to `func` bodies alone would not see the ones written in a `var body`.
    @Test func aSaveInsideAClosureIsAttributedToTheDeclarationThatEnclosesIt() throws {
        let source = """
        struct Sheet: View {
            var body: some View {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: source) == ["body"])
    }

    /// Half 2 keys on the **commit surface**, not on the name `save` (T-508), and the two halves of
    /// that widening are load-bearing **together**: measured over 552 files, either one alone finds
    /// nothing new, and the pair finds exactly one site — the audit's.
    ///
    /// The negative is the same helper call with the `try?` removed, so what is pinned is the
    /// swallow rather than the helper.
    @Test func halfTwoReadsASwallowedPersistenceHelperClosingAnInlineForm() throws {
        let swallowed = """
        private func addLink() {
            try? CadenceSavedLinkPersistence.insert(link, in: modelContext)
            newTitle = ""
            isAdding = false
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: swallowed) == ["addLink"])

        let committed = """
        private func addLink() throws {
            try CadenceSavedLinkPersistence.insert(link, in: modelContext)
            newTitle = ""
            isAdding = false
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: committed).isEmpty)

        // Each half of the widening on its own. `isAdding = false` after an ordinary swallowed
        // save was already covered before T-508 only for `isPresented`/`isEditing`; the flag
        // spelling is the general form of both.
        let helperThenDismiss = """
        private func addLink() {
            try? CadenceSavedLinkPersistence.insert(link, in: modelContext)
            dismiss()
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: helperThenDismiss) == ["addLink"])

        let saveThenFlag = """
        private func addLink() {
            try? modelContext.save()
            isAdding = false
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: saveThenFlag) == ["addLink"])

        // And the boundary the measurement drew: a swallowed **file** write is not this rule.
        // Nothing follows it that reports success, because the report is the absence of an error
        // sheet — so widening the needle to `write(to:` would add a spelling and find nothing.
        let fileWrite = """
        private func export(url: URL) {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: fileWrite).isEmpty)
    }

    /// The mechanism of the one-frame-down half, on fixtures: two frames, across two files, with
    /// the swallow in neither of them at the call site.
    ///
    /// The negative is the same pair with the callee **throwing** — which is T-566's fix in
    /// miniature — so what is pinned is the swallow rather than the call.
    @Test func theOneFrameDownHalfFollowsACallIntoAnotherFileAndStopsWhenItThrows() throws {
        let sheet = """
        struct Sheet: View {
            var body: some View {
                Button("Save") {
                    save()
                    dismiss()
                }
            }

            private func save() {
                CadenceTaskMutationSupport.updateBundle(bundle, modelContext: modelContext)
            }
        }
        """
        let swallowingMutation = """
        enum CadenceTaskMutationSupport {
            static func updateBundle(_ bundle: TaskBundle, modelContext: ModelContext) {
                bundle.title = title
                try? modelContext.save()
            }
        }
        """
        let throwingMutation = """
        enum CadenceTaskMutationSupport {
            static func updateBundle(
                _ bundle: TaskBundle,
                modelContext: ModelContext,
                commit: (ModelContext) throws -> Void = { try $0.save() }
            ) throws {
                bundle.title = title
                try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                    bundle.title = previous
                }
            }
        }
        """

        let swallowed = index(over: ["mutation.swift": swallowingMutation, "sheet.swift": sheet])
        #expect(CadenceSaveCommitRule.indirectReportOffenders(in: sheet, swallowing: swallowed) == ["body"])

        let committed = index(over: ["mutation.swift": throwingMutation, "sheet.swift": sheet])
        #expect(committed.namesRead == 0, "a throwing callee is not something a caller can swallow")
        #expect(CadenceSaveCommitRule.indirectReportOffenders(in: sheet, swallowing: committed).isEmpty)
    }

    /// A callee is resolved by **name and type**, not by name. Measured over the app on the same
    /// day: name-only resolution reports **17** sites where this reports 2, because `save`,
    /// `create` and `persistNote` are each declared in several files. One of the extras is
    /// `iOSEventNoteEditorSheet.persistNote` — read, and a genuine false positive: it returns an
    /// outcome its caller *guards on*, which is the shape this rule is asking for.
    @Test func theOneFrameDownHalfDoesNotConfuseTwoCalleesThatShareAName() throws {
        let swallowing = """
        enum CadenceTaskMutationSupport {
            static func updateBundle(_ bundle: TaskBundle, modelContext: ModelContext) {
                try? modelContext.save()
            }
        }
        """
        let otherType = """
        struct Sheet: View {
            var body: some View {
                Button("Save") {
                    SomeOtherService.updateBundle(bundle)
                    dismiss()
                }
            }
        }
        """
        let sameType = """
        struct Sheet: View {
            var body: some View {
                Button("Save") {
                    CadenceTaskMutationSupport.updateBundle(bundle, modelContext: modelContext)
                    dismiss()
                }
            }
        }
        """
        let swallowingIndex = index(over: ["mutation.swift": swallowing])
        #expect(CadenceSaveCommitRule.indirectReportOffenders(in: otherType, swallowing: swallowingIndex).isEmpty)
        #expect(CadenceSaveCommitRule.indirectReportOffenders(in: sameType, swallowing: swallowingIndex) == ["body"])
    }

    /// The two halves stay disjoint: a declaration half 2 already reports is not reported again
    /// here, so no site ever needs an entry in both exemption lists.
    @Test func theOneFrameDownHalfSubtractsWhatHalfTwoAlreadyReports() throws {
        let both = """
        struct Sheet: View {
            private func finish() {
                try? modelContext.save()
                helper()
                dismiss()
            }

            private func helper() {
                try? modelContext.save()
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: both) == ["finish"])
        let swallowed = index(over: ["sheet.swift": both])
        #expect(CadenceSaveCommitRule.indirectReportOffenders(in: both, swallowing: swallowed).isEmpty)
    }

    /// An index over fixtures rather than over the tree, for the tests above. Not `throws`: the
    /// builder is `rethrows` and a dictionary read cannot fail, so the fixture spelling is the one
    /// place this API is used without a file read behind it.
    // MARK: - The four blind spots T-627 closed

    /// **Gap 1.** Half 1 followed a call one frame down for the *report* half only (T-566); the
    /// *existence* half still needed a literal `insert(` in the swallowing declaration's own body.
    /// This app puts the two in different frames as a matter of style, so that reading found six of
    /// the fifteen sites an external audit had to find by hand.
    ///
    /// The negative is the same helper with the insert **committed**, which is what keeps the
    /// already-fixed sites quiet: a callee that commits is not something its caller inherits.
    @Test func halfOneFollowsAPendingInsertIntoAHelperThatWasHandedTheContext() throws {
        let sheet = """
        struct Editor: View {
            private func addImage(_ data: Data) {
                MarkdownImageAssetService.createAsset(data, in: modelContext)
                try? modelContext.save()
            }
        }
        """
        let pending = """
        enum MarkdownImageAssetService {
            static func createAsset(_ data: Data, in modelContext: ModelContext) -> MarkdownImageAsset {
                let asset = MarkdownImageAsset(data: data)
                modelContext.insert(asset)
                return asset
            }
        }
        """
        let committed = """
        enum MarkdownImageAssetService {
            static func createAsset(_ data: Data, in modelContext: ModelContext) throws -> MarkdownImageAsset {
                let asset = MarkdownImageAsset(data: data)
                modelContext.insert(asset)
                try CadencePendingChangePersistence.commitInsert(of: asset, in: modelContext)
                return asset
            }
        }
        """
        let leaves = existence(over: ["service.swift": pending, "sheet.swift": sheet])
        #expect(leaves.namesRead == 1, "the existence index read \(leaves.namesRead) callee names")
        #expect(CadenceSaveCommitRule.existenceOffenders(in: sheet, changing: leaves) == ["addImage"])

        let commits = existence(over: ["service.swift": committed, "sheet.swift": sheet])
        #expect(commits.namesRead == 0, "a callee that commits is not a pending existence change")
        #expect(CadenceSaveCommitRule.existenceOffenders(in: sheet, changing: commits).isEmpty)
    }

    /// **Gap 1, and why the index travels more than one frame.** Ticking a recurring task's circle
    /// on macOS is four frames deep and only the last one inserts. The three in between each
    /// disclaim ownership in their signature — which is half 3's own exemption rule, read forwards
    /// — so the obligation lands on `write`, the first frame that did not.
    ///
    /// This fixture also pins the recursion guard: `TaskWorkflowService.markDone` forwards to
    /// `CadenceTaskRecurrenceWorkflowSupport.markDone`, and a guard that dropped a call whose
    /// *name* matched its declaration's would read that forward as recursion and lose the chain.
    @Test func halfThreeCarriesAPendingInsertUpThroughEveryFrameThatDisclaimsOwnership() throws {
        let manager = """
        final class TaskCompletionAnimationManager {
            private func write(_ task: AppTask) {
                TaskWorkflowService.markDone(task, in: context)
            }
        }
        """
        let workflow = """
        enum TaskWorkflowService {
            static func markDone(_ task: AppTask, in context: ModelContext) {
                CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
            }
        }
        """
        let committingWorkflow = """
        enum TaskWorkflowService {
            static func markDone(_ task: AppTask, in context: ModelContext) throws {
                CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
                try context.save()
            }
        }
        """
        let recurrence = """
        enum CadenceTaskRecurrenceWorkflowSupport {
            static func markDone(_ task: AppTask, in context: ModelContext) {
                spawnNextOccurrenceIfNeeded(from: task, in: context)
            }

            private static func spawnNextOccurrenceIfNeeded(from task: AppTask, in context: ModelContext) {
                context.insert(makeNextRecurringTask(from: task))
            }
        }
        """
        let pending = existence(over: [
            "manager.swift": manager, "recurrence.swift": recurrence, "workflow.swift": workflow,
        ])
        #expect(
            CadenceSaveCommitRule.commitReachOffenders(in: manager, changing: pending) == ["write"],
            "the chain is three frames long and only the fourth inserts"
        )

        // The nearest negative, and it is this ticket's own fix in miniature: one frame in the
        // middle commits, and the obligation stops there instead of reaching the button.
        let stopped = existence(over: [
            "manager.swift": manager, "recurrence.swift": recurrence, "workflow.swift": committingWorkflow,
        ])
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: manager, changing: stopped).isEmpty)
    }

    /// The commit index resolves a call by name and type and **cannot see an argument list**, so a
    /// name is only allowed to vouch for itself when every overload of it agrees.
    ///
    /// Measured, and it cost a real finding before the rule existed: `SchedulingActions` declares
    /// two `createBundle(…in:)`. One forwards to `CadenceTaskMutationSupport.insertBundle`, which
    /// commits; the other inserts and does not. Letting the committing one vouch for the name made
    /// the timeline canvas and the schedule panel — [[T-636]](e)'s two sites — go quiet.
    @Test func theCommitIndexNeedsEveryOverloadOfANameToAgreeBeforeItVouchesForIt() throws {
        let mutation = """
        enum CadenceTaskMutationSupport {
            static func insertBundle(from task: AppTask, modelContext: ModelContext) {
                modelContext.insert(TaskBundle(title: task.title))
                try? modelContext.save()
            }
        }
        """
        let committingOverload = """
            static func createBundle(from task: AppTask, in context: ModelContext) {
                CadenceTaskMutationSupport.insertBundle(from: task, modelContext: context)
            }
        """
        let pendingOverload = """
            static func createBundle(title: String, in context: ModelContext) -> TaskBundle {
                let bundle = TaskBundle(title: title)
                context.insert(bundle)
                return bundle
            }
        """
        let canvas = """
        struct TimelineDayCanvas: View {
            var body: some View {
                TimelineCanvas(onCreateBundle: { title in
                    SchedulingActions.createBundle(title: title, in: modelContext)
                })
            }
        }
        """
        func actions(_ overloads: String...) -> String {
            "enum SchedulingActions {\n\(overloads.joined(separator: "\n"))\n}"
        }

        let split = existence(over: [
            "actions.swift": actions(pendingOverload, committingOverload),
            "canvas.swift": canvas,
            "mutation.swift": mutation,
        ])
        #expect(
            CadenceSaveCommitRule.commitReachOffenders(in: canvas, changing: split) == ["body"],
            "one committing overload must not vouch for its inserting sibling"
        )

        // The nearest negative: the same call, with the committing spelling the *only* one that
        // name has. Now the name genuinely does commit, and the canvas is clean.
        let unanimous = existence(over: [
            "actions.swift": actions(committingOverload),
            "canvas.swift": canvas,
            "mutation.swift": mutation,
        ])
        #expect(unanimous.committersRead >= 1, "the commit index read \(unanimous.committersRead) names")
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: canvas, changing: unanimous).isEmpty)
    }

    /// **Gap 3.** Half 3 keyed on `insert(` alone, so "delete and never commit at all" was covered
    /// by nothing: half 1 sees the delete but needs a `try?` that is not there, and half 3 saw only
    /// inserts. That is exactly where the bundle popover's end actions sat.
    @Test func halfThreeReadsADeleteThatReachesNoCommitAndNotOneThatDoes() throws {
        let pending = """
        private func endBundle() {
            detachMembers(bundle)
            modelContext.delete(bundle)
            showPopover = false
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: pending, changing: .init()) == ["endBundle"])

        let committed = """
        private func endBundle() {
            detachMembers(bundle)
            modelContext.delete(bundle)
            try? modelContext.save()
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: committed, changing: .init()).isEmpty)
    }

    /// **Gap 2.** `declarations(in:)` parsed `func` and the literal `var body`, so a whole screen
    /// written as `private var columnEditor: some View` was invisible to all four halves — 7 of 102
    /// swallowed-commit matches in the app sat outside every parsed declaration.
    ///
    /// The negative is the stored property beside it. A *computed* property opens its brace on its
    /// own line; a stored one does not open one at all, and a reader that let it reach forward for
    /// the next `{` would file somebody else's offences under a `CGFloat`'s name — which is what
    /// the first spelling of this fix did.
    @Test func theDeclarationSplitReadsAComputedPropertyAndNotAStoredOne() throws {
        let source = """
        struct Column: View {
            var verticalOffset: CGFloat = 0

            private var columnEditor: some View {
                Button("Save") {
                    try? modelContext.save()
                    showEditor = false
                }
            }
        }
        """
        #expect(CadenceSaveCommitRule.declarations(in: source).map(\.name) == ["columnEditor"])
        #expect(CadenceSaveCommitRule.reportOffenders(in: source) == ["columnEditor"])
    }

    /// **Gap 4, the window.** Half 2 read only the text *after* the save, and three measured sites
    /// dismiss first — macOS's Move Note calls `dismissPicker()` and then moves the note. Ordering
    /// was never the claim the rule makes.
    ///
    /// The negative is what the tail reading was accidentally protecting: `context.isArchived =
    /// false` is a **model field** being edited above a swallowed save, in four settings screens.
    /// Reading the whole block makes the vocabulary's `(?<![.\w])` anchor load-bearing.
    @Test func halfTwoReadsTheWholeBlockSoADismissalBeforeTheSaveStillCounts() throws {
        let dismissesFirst = """
        private func move(to list: TaskList) {
            dismissPicker()
            note.list = list
            try? modelContext.save()
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: dismissesFirst) == ["move"])

        let editsAModelField = """
        private func restore(_ context: Context) {
            context.isArchived = false
            try? modelContext.save()
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: editsAModelField).isEmpty)

        // A closure is its own block, so the discrimination the tail reading was really carrying —
        // a `var body` with an autosave in one closure and a `dismiss()` in an unrelated one — is
        // kept by the block scoping rather than by the direction.
        let twoClosures = """
        var body: some View {
            Toggle("Done", isOn: $done)
                .onChange(of: done) { _, _ in
                    try? modelContext.save()
                }
                .toolbar {
                    Button("Close") { dismiss() }
                }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: twoClosures).isEmpty)
    }

    /// **Gap 4, the vocabulary.** Four spellings this app dismisses with that the closed list had
    /// never been shown: `showEditor = false`, `selectedBundleID = nil`, `pendingRecurrenceRule =
    /// nil`, and a named `dismissPicker()`.
    ///
    /// `self.` counts and a model field does not, and both halves of that are measured: the same
    /// file writes `pendingRecurrenceRule = nil` in a binding and `self.pendingRecurrenceRule =
    /// nil` in a method, and they are the same dismissal.
    @Test func theVocabularyReadsThisAppsDismissalsAndNotAModelFieldThatHappensToStartWithIs() throws {
        for dismissal in [
            "showEditor = false",
            "selectedBundleID = nil",
            "self.pendingRecurrenceRule = nil",
            "dismissPicker()",
        ] {
            let source = """
            private func finish() {
                task.title = title
                try? modelContext.save()
                \(dismissal)
            }
            """
            #expect(CadenceSaveCommitRule.reportOffenders(in: source) == ["finish"], "\(dismissal)")
        }

        for fieldEdit in ["task.isFlagged = false", "bundle.selectedTaskID = nil"] {
            let source = """
            private func finish() {
                try? modelContext.save()
                \(fieldEdit)
            }
            """
            #expect(CadenceSaveCommitRule.reportOffenders(in: source).isEmpty, "\(fieldEdit)")
        }
    }

    /// **Gap 4, the drop handler.** A `-> Bool` handler has no sheet to close: its answer *is* the
    /// report, and `TasksPanelDropCoordinator` already says so — "a silent accept says the move
    /// happened".
    ///
    /// The negative is the same two words inside a predicate closure, in a declaration that answers
    /// nothing. Scoping the needle to the declaration's return type is what keeps it off every
    /// `guard`-shaped `return true` in the app.
    @Test func returningTrueIsASuccessReportOnlyFromADeclarationThatAnswersBool() throws {
        let dropHandler = """
        private func assignTask(_ id: UUID, to list: TaskList) -> Bool {
            task.list = list
            try? modelContext.save()
            return true
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: dropHandler) == ["assignTask"])

        let predicate = """
        private func prune() {
            items.removeAll { item in
                try? modelContext.save()
                return true
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: predicate).isEmpty)
    }

    /// **T-636(b): the Optional half of the same sentence.** `Bool` and `Optional` are the two
    /// return types that can say "it did not work", so they are the two in which the answer *is*
    /// the report. This app hands a repainted card back that way — `MarkdownTaskEmbedRenderInfo` —
    /// and the vocabulary had never seen the spelling.
    ///
    /// Three negatives, and each one is a different way the widening could have been too wide: the
    /// failure answer (`return nil`), no answer at all (`-> Void`), and a return type that belongs
    /// to a **closure parameter** rather than to this declaration.
    @Test func returningSomethingOtherThanNilIsASuccessReportFromADeclarationThatAnswersAnOptional() throws {
        let renderInfo = """
        private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) -> MarkdownTaskEmbedRenderInfo? {
            guard let task = embeddedTask(id: taskID),
                  let subtask = (task.subtasks ?? []).first(where: { $0.id == subtaskID }) else {
                return nil
            }
            subtask.isDone.toggle()
            try? modelContext.save()
            return MarkdownTaskEmbedRenderInfo.task(task)
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: renderInfo) == ["toggleEmbeddedSubtask"])

        let refusing = renderInfo.replacingOccurrences(
            of: "return MarkdownTaskEmbedRenderInfo.task(task)",
            with: "return nil"
        )
        #expect(CadenceSaveCommitRule.reportOffenders(in: refusing).isEmpty)

        let answerless = """
        private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) {
            guard let subtask = subtask(taskID: taskID, subtaskID: subtaskID) else { return }
            subtask.isDone.toggle()
            try? modelContext.save()
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: answerless).isEmpty)

        // The `$` anchor earning its place: the only `-> …?` in this signature belongs to a
        // **closure the caller passes in**, and this declaration's own answer is a `String`, which
        // has no way to say "it did not work" and so cannot be a report. Reading the parameter's
        // return type as the declaration's would make every handler-taking mutation an offender.
        let closureParameter = """
        private func retitle(_ task: AppTask, resolving lookup: (UUID) -> Tag?) -> String {
            task.title = draft
            try? modelContext.save()
            return task.title
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: closureParameter).isEmpty)
    }

    /// The Optional spelling reads the frame that **builds** the answer, not one frame down — and
    /// the negative is the shape that decided it. `macOSRootCommandSupport.handle` answers
    /// `NSEvent?` with the polarity inverted: `nil` is how "I consumed the event" is spelled, so a
    /// non-`nil` answer says the frame did *not* act.
    @Test func theOptionalAnswerIsNotReadThroughAFrameThatMerelyForwardsIt() throws {
        let router = """
        enum RootCommandEventSupport {
            static func handleCommandKeyEvent(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
                context.hoveredTask.map { toggleTodayDate(for: $0) }
                try? context.modelContext.save()
                return nil
            }
        }
        """
        let forwarding = """
        enum RootCommandSupport {
            static func handle(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
                guard event.modifierFlags.contains(.command) else { return event }
                return RootCommandEventSupport.handleCommandKeyEvent(event, context: context)
            }
        }
        """
        let swallowing = index(over: ["events.swift": router, "root.swift": forwarding])
        #expect(swallowing.namesRead > 0, "non-vacuity: the swallowing index read nothing")
        #expect(
            CadenceSaveCommitRule.indirectReportOffenders(in: forwarding, swallowing: swallowing).isEmpty
        )

        // The same forward, said with a spelling the vocabulary *does* read one frame down, so the
        // negative above is about the Optional answer rather than about the fixture being inert.
        let dismissing = forwarding.replacingOccurrences(
            of: "return RootCommandEventSupport.handleCommandKeyEvent(event, context: context)",
            with: """
            RootCommandEventSupport.handleCommandKeyEvent(event, context: context)
                        dismiss()
                        return nil
            """
        )
        #expect(
            CadenceSaveCommitRule.indirectReportOffenders(in: dismissing, swallowing: swallowing) == ["handle"]
        )
    }

    /// **Gap 4, the sharpest spelling.** Every other report in the vocabulary is state a redraw can
    /// repair. An `@AppStorage` write is not: it is the one false success that **outlives the
    /// rollback**, and Roll Over spells it as an assignment *from* the swallowing call — so the
    /// report sits textually before the call as well as outside the old vocabulary.
    @Test func writingAnAppStorageOverASwallowedCommitIsASuccessReport() throws {
        let rollover = """
        enum CadenceTodayRolloverSupport {
            static func rollOver(_ tasks: [AppTask], todayKey: String, modelContext: ModelContext) -> String {
                for task in tasks { modelContext.delete(task.bundle) }
                try? modelContext.save()
                return todayKey
            }
        }
        """
        let persisting = """
        struct TasksPanel: View {
            @AppStorage(CadenceTodayRolloverSupport.dismissedDateStorageKey) private var rolloverNoticeDismissedDate = ""

            private func rollOverPastDoTasks() {
                rolloverNoticeDismissedDate = CadenceTodayRolloverSupport.rollOver(
                    overdoTasks,
                    todayKey: todayKey,
                    modelContext: modelContext
                )
            }
        }
        """
        let swallowing = index(over: ["rollover.swift": rollover, "panel.swift": persisting])
        #expect(
            CadenceSaveCommitRule.indirectReportOffenders(in: persisting, swallowing: swallowing)
                == ["rollOverPastDoTasks"]
        )

        // The nearest negative: the same assignment to ordinary view state, which a redraw
        // repairs. Only the defaults write survives the next launch.
        let transient = persisting.replacingOccurrences(
            of: "@AppStorage(CadenceTodayRolloverSupport.dismissedDateStorageKey) private var",
            with: "@State private var"
        )
        #expect(
            CadenceSaveCommitRule.indirectReportOffenders(in: transient, swallowing: swallowing).isEmpty
        )
    }

    /// A `pending<Something> = nil` that the declaration also `cancel()`s is a scheduled unit of
    /// work being cleared, not a screen closing. Measured: the discriminator is worth exactly two
    /// false positives, and without it the `pending` spelling costs more than it finds.
    @Test func clearingACancelledWorkItemIsNotADismissal() throws {
        let workItem = """
        private func scheduleRefresh() {
            pendingAppDataRefresh?.cancel()
            let item = DispatchWorkItem {
                try? modelContext.save()
                pendingAppDataRefresh = nil
            }
            pendingAppDataRefresh = item
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: workItem).isEmpty)

        let dialog = """
        private func applyPendingRecurrenceRule() {
            task.recurrenceRule = pendingRecurrenceRule
            try? modelContext.save()
            pendingRecurrenceRule = nil
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: dialog) == ["applyPendingRecurrenceRule"])
    }

    private func index(over sources: [String: String]) -> CadenceSaveCommitRule.SwallowingIndex {
        CadenceSaveCommitRule.swallowingIndex(over: sources.keys.sorted()) { sources[$0] ?? "" }
    }

    private func existence(over sources: [String: String]) -> CadenceSaveCommitRule.ExistenceIndex {
        CadenceSaveCommitRule.existenceIndex(over: sources.keys.sorted()) { sources[$0] ?? "" }
    }

    private func swallowingIndexOverTheApp() throws -> CadenceSaveCommitRule.SwallowingIndex {
        try CadenceSaveCommitRule.swallowingIndex(over: try saveCommitSwiftFiles()) {
            CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0))
        }
    }

    private func existenceIndexOverTheApp() throws -> CadenceSaveCommitRule.ExistenceIndex {
        try CadenceSaveCommitRule.existenceIndex(over: try saveCommitSwiftFiles()) {
            CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0))
        }
    }

    // MARK: - What half 3 subtracts, and why by rule

    /// The seventeen helpers are subtracted by **signature**: a declaration handed a `ModelContext`
    /// is one whose caller owns the unit of work, so it is not the party that decides when to
    /// commit. The same body in a declaration that reached for an ambient context *is* the defect.
    ///
    /// Both fixtures below are the same four lines apart from the signature, which is the whole
    /// claim: nothing about the body distinguishes these two cases, so no body-only rule could
    /// have separated the 4 from the 21 without a list of names.
    @Test func halfThreeExemptsADeclarationHandedItsContextAndNotOneThatReachedForIt() throws {
        let handed = """
        static func insertSubtask(titled title: String, into parent: AppTask, modelContext: ModelContext) -> Subtask? {
            let subtask = Subtask(title: title)
            modelContext.insert(subtask)
            return subtask
        }
        """
        let ambient = """
        private func create() {
            let subtask = Subtask(title: title)
            modelContext.insert(subtask)
            dismiss()
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: handed, changing: .init()).isEmpty)
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: ambient, changing: .init()) == ["create"])

        // `commit:` is a commit being handed *in*, which is the opposite claim from a context being
        // handed in, so it must not exempt anything on its own.
        let handedACommitOnly = """
        private func create(commit: (ModelContext) throws -> Void = { try $0.save() }) {
            let subtask = Subtask(title: title)
            modelContext.insert(subtask)
            dismiss()
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: handedACommitOnly, changing: .init()) == ["create"])
    }

    /// The seventeenth: `CadenceWriteService.createTask` owns its context and does commit — through
    /// `saveNotifyAndAudit`, a sibling in the same file. So "reaches a commit" follows same-file
    /// calls to a fixed point, and it takes two hops here because the one-entry spelling forwards
    /// to the array one.
    ///
    /// The negative is the same file with the commit taken out of the sibling, so what is being
    /// pinned is the *reachability*, not the presence of a call.
    @Test func halfThreeFollowsASameFileCallChainToTheCommit() throws {
        let reaching = """
        func createTask() throws {
            let task = AppTask(title: title)
            context.insert(task)
            try saveNotifyAndAudit(entry)
        }
        private func saveNotifyAndAudit(_ entry: Entry) throws {
            try saveNotifyAndAudit([entry])
        }
        private func saveNotifyAndAudit(_ entries: [Entry]) throws {
            try context.save()
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: reaching, changing: .init()).isEmpty)

        let notReaching = """
        func createTask() throws {
            let task = AppTask(title: title)
            context.insert(task)
            try saveNotifyAndAudit(entry)
        }
        private func saveNotifyAndAudit(_ entry: Entry) throws {
            try saveNotifyAndAudit([entry])
        }
        private func saveNotifyAndAudit(_ entries: [Entry]) throws {
            recordAudit(entries)
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: notReaching, changing: .init()) == ["createTask"])

        // Only *this* file. The call graph stops at the file boundary, which is the honest limit of
        // a text scan, and it errs toward reporting — the safe direction for a half whose exemption
        // list is meant to stay empty.
        let acrossFiles = """
        func createTask() throws {
            let task = AppTask(title: title)
            context.insert(task)
            try SomeOtherFile.saveEverything(context)
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: acrossFiles, changing: .init()) == ["createTask"])
    }

    /// The `presented… =` spelling half 2 gained with T-503, and the reason it is `=(?!=)`: these
    /// sheets are *bound* with `presentedEventNote == nil`, so a needle that read a comparison as
    /// an assignment would report every one of them.
    @Test func halfTwoReadsPresentingASheetAsAReportButNotComparingOne() throws {
        let presents = """
        private func openEventNote() {
            try? modelContext.save()
            presentedEventNote = note
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: presents) == ["openEventNote"])

        let compares = """
        private func refresh() {
            try? modelContext.save()
            if presentedEventNote == nil { reload() }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: compares).isEmpty)
    }

    /// [[T-664]]: a surface that stays open and **fills itself in** reports success, and until now
    /// the vocabulary had no spelling for it.
    ///
    /// The fixture is `TagPickerPopoverViews.restore` as it stood before [[T-652]] — the site the
    /// measurement in T-664 was taken from, and the one every dismissal spelling walked past
    /// because nothing here closes and nothing here goes `nil`.
    @Test func halfTwoReadsAWriteThroughACollectionBindingAsAReport() throws {
        let fillsIn = """
        struct TagPickerPopover: View {
            @Binding var selectedTags: [Tag]

            private func restore(_ tag: Tag) {
                tag.isArchived = false
                try? modelContext.save()
                if !selectedTags.contains(where: { $0.id == tag.id }) {
                    selectedTags.append(tag)
                }
                query = ""
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: fillsIn) == ["restore"])

        // The nearest miss, and the reason the needle is not `.append(` on its own: the same
        // append, into the view's own `@State` scratch list rather than out through the binding.
        // Nobody outside the frame is told anything.
        let appendsToItsOwnState = """
        struct TagPickerPopover: View {
            @State private var recentTags: [Tag] = []

            private func restore(_ tag: Tag) {
                tag.isArchived = false
                try? modelContext.save()
                recentTags.append(tag)
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: appendsToItsOwnState).isEmpty)

        // And reading the binding is not writing it: `contains` above must not be what fired.
        let onlyReadsTheBinding = """
        struct TagPickerPopover: View {
            @Binding var selectedTags: [Tag]

            private func refresh(_ tag: Tag) {
                tag.isArchived = false
                try? modelContext.save()
                if selectedTags.contains(where: { $0.id == tag.id }) { highlight(tag) }
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: onlyReadsTheBinding).isEmpty)
    }

    // MARK: - Exemptions rot

    /// Each exemption claims a specific file still breaks the rule in a specific named function for
    /// a specific reason. When that stops being true the entry can only ever hide a regression, so
    /// it fails rather than sits there. This is also what stops a file with one *allowed* offender
    /// from masking a second, new one added beside it.
    @Test func everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule() throws {
        // The one-frame-down half needs the index the sweep uses; an entry there is a claim about
        // a *pair* of declarations, so checking it against an empty index would read every entry
        // as stale.
        let swallowing = try swallowingIndexOverTheApp()
        let existence = try existenceIndexOverTheApp()
        for (rule, exemptions, offenders) in [
            (
                "existence",
                CadenceSaveCommitRule.existenceExemptions,
                { CadenceSaveCommitRule.existenceOffenders(in: $0, changing: existence) }
            ),
            ("report", CadenceSaveCommitRule.reportExemptions, CadenceSaveCommitRule.reportOffenders),
            (
                "commit reach",
                CadenceSaveCommitRule.commitReachExemptions,
                { CadenceSaveCommitRule.commitReachOffenders(in: $0, changing: existence) }
            ),
            (
                "report one frame down",
                CadenceSaveCommitRule.indirectReportExemptions,
                { CadenceSaveCommitRule.indirectReportOffenders(in: $0, swallowing: swallowing) }
            ),
            (
                "rearrangement",
                CadenceSaveCommitRule.rearrangementExemptions,
                { CadenceSaveCommitRule.rearrangementOffenders(in: $0, changing: existence) }
            ),
        ] as [(String, [String: [String]], (String) -> [String])] {
            for (path, expected) in exemptions {
                let found = offenders(CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path)))
                #expect(
                    found.sorted() == expected.sorted(),
                    """
                    the \(rule) exemption for \(path) expects \(expected.sorted()) and the file now \
                    has \(found.sorted()). Either a listed site was fixed — delete the entry — or a \
                    new one was added under cover of it.
                    """
                )
            }
        }
    }

    private func saveCommitSweep(
        instrument: CadenceScanInstrument,
        allowed: [String: [String]]
    ) throws -> [String] {
        let files = try saveCommitSwiftFiles()
        let hits = try instrument.sweep(
            files,
            // 300+ Swift files under `Cadence/`; the floor `CadenceRetiredCopyTests` uses for the
            // same tree.
            atLeast: 300,
            // The file that holds 27 of the app's saves, so a walk that skipped `Shared/` cannot
            // report this rule clean.
            including: "Cadence/Shared/CadenceTaskMutationSupport.swift",
            read: { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        )
        return hits.filter { allowed[$0] == nil }
    }

    private func saveCommitSwiftFiles() throws -> [String] {
        let directory = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence")
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
        return enumerator.compactMap { element in
            guard let name = element as? String, name.hasSuffix(".swift") else { return nil }
            return "Cadence/\(name)"
        }
    }
}

// MARK: - The rule as source text

/// The two halves of the `try? save()` rule, spelled over Swift source (T-322).
///
/// Separate from the tests so both instruments and the exemption check read the *same* detector;
/// a rule stated twice is a rule that drifts.
enum CadenceSaveCommitRule {

    /// Where the rule stops. Each entry names the functions in that file that break it today and
    /// why they are allowed to, and `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule`
    /// makes the list fail when it goes stale.
    static let existenceExemptions: [String: [String]] = [
        // **`seedDefaultTags` and `deduplicateTags` are not launch-time maintenance, and saying so
        // was measurably false by the time T-653 checked (T-528 had already removed every
        // automatic caller).** Both are handed their `ModelContext` and both still swallow a
        // `context.save()` behind their own `saveChanges:`/`save:` default — but the only production
        // callers left are the four "Add Defaults" buttons (`SettingsTagsSection`,
        // `iOSSettingsTagsSection`, `TagPickerSupportViews`, `iOSTaskDetailComponents`), a person
        // pressed one, and there is very much something to report. T-653 gave those buttons
        // `TagSupport.seedDefaultTagsCommitting(in:commit:)` — `Cadence/Shared/CadenceInlineTagCreation.swift`
        // — which calls `seedDefaultTags(in:saveChanges: false)` and commits the whole cascade
        // itself, rolling it back on a refusal. The two raw declarations stay exempt because they
        // are still handed a context whose caller owns the unit of work, same as half 3 reads any
        // such declaration; nothing production-side reaches their own default any more, only tests.
        // `syncAllNoteTagsFromMarkdown` is the one entry the original rationale still fits: it is
        // launch-time maintenance with no user watching, joined with T-627 for the same shape one
        // frame down — `syncNoteTagsFromMarkdown` inserts the `Tag` rows — and it carries the same
        // `saveChanges:` opt-out for `CadenceMCPStorePreparation.prepare`, the one caller that owns
        // the unit of work and has nobody to report to either.
        "Cadence/Services/TagSupport.swift": ["seedDefaultTags", "deduplicateTags", "syncAllNoteTagsFromMarkdown"],
        // UI-test scaffolding. It runs only under `CadenceUITestSupport`'s launch argument, and
        // there is no user to tell.
        "Cadence/Services/CadenceUITestSupport.swift": ["seedDataIfNeeded"],

        // [[T-654]] closed the `CadenceFocusSupport.endSession` / `iOSFocusView.logBundleSession`
        // entries that used to sit here: both now commit through
        // `CadenceFocusBundleSupport.distributeMinutes(_:across:in:commit:)`, which snapshots every
        // credited task's minutes before writing and restores them all on a refusal, and neither
        // clears its clock until that commit actually lands.

        // MARK: Found by T-627's widening, held for the tickets that own them
        //
        // Everything below is a *new* sighting of an old shape: half 1 now follows a call one
        // frame down, so the frame holding the `try?` and the frame holding the `insert` no
        // longer have to be the same frame. Each entry names the ticket that owns the fix, and
        // fixing one means deleting its line here in the same change — that is what
        // `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` is for.

        // [[T-636]](a) and its family: the completion spine. `TaskWorkflowService.markDone` →
        // `CadenceTaskRecurrenceWorkflowSupport.markDone` → `spawnNextOccurrenceIfNeeded`, which
        // inserts the successor. Every surface that ticks a checkbox over a swallowed save is one
        // of these, and they must be fixed together or the spine grows a second answer.
        //
        // `toggleCompletion` left this list with T-636(a): it commits through `commitSettle` and
        // throws, and `CadenceTaskStatusEditing` names the refusal on
        // `CadenceTaskSettleFailureCenter`. **`setStatus` left with [[T-643]]**, the same door with
        // the other key: its settling half goes through the same `commitSettle` and its open half
        // through `commitEdit` over the two fields it writes, and the wrapper records the refusal
        // beside the toggle's. That empties `CadenceTaskMutationSupport.swift` out of this list —
        // do not re-add the file without re-deriving which function it is for.
        //
        // `CadenceFocusSupport.complete` left with T-636(c) — the focus timer's own door onto the
        // same recurrence insert. It throws, settles through the shared `commitSettle`, and puts
        // the banked minutes back; `CadenceTaskStatusEditing.completeFocusSession` records the
        // refusal and answers `false` so the stopwatch is not cleared over it.
        "Cadence/macOS/Views/ListNotesSupportViews.swift": ["toggleEmbeddedTask"],
        "Cadence/macOS/Views/NoteEditorPane.swift": ["toggleEmbeddedTask"],
        "Cadence/macOS/Views/NotePanel.swift": ["toggleEmbeddedTask"],
        // T-629 emptied the two image doors out of this list: macOS's `createAssets` and iOS's
        // `createPastedImageAssets`/`insertPickedImages` commit through `commitInsert` now and
        // write no reference over a refused commit, pinned by
        // `CadenceMarkdownImageCommitSurfaceTests`.
        //
        // [[T-651]] emptied the rest of [[T-631]]'s family, closed since this list was written.
        // `MarkdownEditor.createInlineTag` and `KanbanTagPickerPopover.body` (in
        // `KanbanCardMetaSupportViews.swift`) both called `TagSupport.resolveTags` from an ambient
        // `ModelContext` and committed nothing; both now go through
        // `TagSupport.committedTag(named:in:commit:)`, which commits the row it minted, if any,
        // before either surface can see it. `CadenceCoreNoteSupport.update` was the third —
        // `TagSupport.syncNoteTagsFromMarkdown` is now `syncNoteTagsFromMarkdownCommittingInsertions`
        // in `Cadence/Shared/CadenceInlineTagCreation.swift`, the same shape one call further in.
        // T-497 emptied the rest of this list before that: `CadenceNoteFolderSupport.createNote`,
        // `SettingsTagsSection.createTag`, `iOSSettingsTagsSection.createTag` and
        // `iOSCalendarEventEditSheet.openEventNote` all commit through `commitInsert` now, and are
        // pinned by `CadenceTagAndNoteCommitSurfaceTests`.
    ]

    /// The exemption list for half 2.
    ///
    /// **It no longer holds a "flush an in-place edit, then close" site, and that is the ticket's
    /// result.** Those were held rather than fixed for a week because each seemed to need an answer
    /// to a question the rule does not settle: what an *undo* means for an editor whose field is
    /// bound live to the model and still on screen. The answer was that they need no undo at all —
    /// see the note at the head of the list itself.
    ///
    /// The three inline tag editors that used to sit beside them — `SettingsTagsSection.saveEdits`
    /// and `TagPickerPopoverViews.saveEdits`/`archive` — are fixed (T-497) and pinned by
    /// `CadenceTagAndNoteCommitSurfaceTests`. They were the easier half of the same sentence: an
    /// inline row editor collapsing is a dismissal, but its fields are drafts held in `@State`
    /// rather than bindings onto the model, so restoring the model does not fight the caret.
    static let reportExemptions: [String: [String]] = [
        // [[T-497]] tier 3 emptied the two "flush an in-place edit, then close" entries that used
        // to open this list — `iOSSearchSupportViews.body` and
        // `iOSTaskDetailSheet.finishEditingAndDismiss` — along with
        // `iOSMarkdownReferenceSupport.body` in `indirectReportExemptions`. The question that
        // blocked them was answered by *not* answering it: an in-place edit on an object the store
        // already holds has nothing to un-insert, and an undo under a live caret would delete what
        // the user typed in order to report that it was not saved. The surfaces stay open now and
        // name the refusal (`CadenceInPlaceEditFlush`), so there is no undo to define.

        // MARK: Found by T-627's widened vocabulary and block window
        //
        // [[T-633]] emptied this entry: the row chip's scope dialog commits through
        // `CadenceTaskFieldEditCommit.commit(_:alsoRestoring:in:)` now and names a refusal in the
        // "Couldn't Update the Series" alert that already existed and could never fire.
        // [[T-636]](b): `return true` from a `-> Bool` drop handler. The repo argued this one
        // itself, in `TasksPanelDropCoordinator`: "a silent accept says the move happened".
        "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift": ["unschedule"],
        "Cadence/macOS/Views/TasksPanelSupport.swift": ["assignTask"],

        // MARK: Found by T-636(b)'s Optional half of the same sentence
        //
        // [[T-648]] left this list the same way: `iOSMarkdownEditingSurface.toggleEmbeddedSubtask`
        // answered `MarkdownTaskEmbedRenderInfo.task(task)` — the render info the editor repaints
        // the card from — over a swallowed commit. It answers `nil` and names the refusal now, and
        // so do its three macOS siblings, which were never in here because they hand the same
        // render info *sideways* through `refreshEmbeddedTask` rather than returning it. That
        // spelling is still invisible to the detector ([[T-657]]); the population it would have
        // caught here is now zero, which is what makes T-657 a smaller ticket rather than a
        // closed one.
        // [[T-651]] emptied [[T-631]]'s second half. `createInlineTag` called
        // `TagSupport.resolveTags` and answered `return .tag(tag)` over the swallowed commit that
        // would have minted it — the phantom tag was not only in Settings › Tags, it was in the
        // note's text, because the suggestion returned here is what the editor writes back in.
        // It now guards on `TagSupport.committedTag(named:in:commit:)`, so a refused insert never
        // reaches the `return .tag(tag)` that would have written it into the note.
        // `Cadence/iOS/iOSListSupportViews.swift: ["addLink"]` was the third entry — [[T-507]],
        // held here rather than fixed to keep two agents out of one file. It is fixed now:
        // `addLink` catches the insert and leaves the form open with an `actionError`, the way
        // macOS's `LinksView.addLink` already did. The entry is deleted in the same change,
        // because `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` fails on a
        // stale one — which is exactly how it was meant to leave.
    ]

    static func existenceInstrument(changing index: ExistenceIndex) throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "swallowed save over an insert or delete",
            fires: """
            func createTag() {
                modelContext.insert(tag)
                try? modelContext.save()
            }
            """,
            // The nearest negative: the same insert, committed the way the rule asks for. A
            // detector that merely looked for `insert(` in a file would fire on this.
            andNotOn: """
            func createTag() throws {
                modelContext.insert(tag)
                try CadencePendingChangePersistence.commitInsert(of: tag, in: modelContext)
            }
            """,
            by: { !existenceOffenders(in: $0, changing: index).isEmpty }
        )
    }

    static func reportInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "swallowed save followed by a success report",
            fires: """
            func save() {
                task.title = title
                try? modelContext.save()
                dismiss()
            }
            """,
            // The nearest negative: the same edit and the same dismiss, with the commit throwing.
            // A detector that looked for `dismiss()` anywhere near a save would fire on this.
            andNotOn: """
            func save() {
                task.title = title
                do {
                    try CadencePendingChangePersistence.commitEdit(in: modelContext) { task.title = previous }
                } catch {
                    actionError = TaskCreationService.saveFailureNotice
                    return
                }
                dismiss()
            }
            """,
            by: { !reportOffenders(in: $0).isEmpty }
        )
    }

    /// The exemption list for half 3. **It was empty until T-627, and the emptiness was the
    /// claim** — worth reading before adding to it.
    ///
    /// T-503 could keep it empty because half 3 only looked for a literal `insert(` in a
    /// declaration's own body, and the ~17 helpers that shape catches are all subtracted by the
    /// signature rule below. T-627 widened the half twice: it reads `delete(` as well (gap 3), and
    /// it follows a pending existence change **up** through every frame that disclaims ownership
    /// (gap 1). The population that widening describes is much larger than the one the mechanical
    /// exemption was built for, and *that* is what these entries record. The signature rule has not
    /// stopped working; it never covered these.
    ///
    /// Every entry is a real finding. The list is a schedule, not a silence: fixing one deletes its
    /// line here in the same change, because
    /// `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` fails on a stale entry.
    /// [[T-628]] is the first to leave that way — `TaskCompletionAnimationManager.write`,
    /// `TaskInspectorContentSupportViews.body` and `TimelineBundleBlock.body` were listed here for
    /// exactly one commit.
    static let commitReachExemptions: [String: [String]] = [
        // [[T-631]] emptied the five entries that used to open this list — `CreateTaskSheet`,
        // `InlineTaskComposerView`, `SchedulePanelComponents`, `iOSCreateTaskSheet` and
        // `iOSTaskDetailComponents` — along with `NoteEditorPane.createTag` below. All six reach
        // `TagSupport.committedTag` now, which commits the rows it minted through `commitInsert`
        // and answers `nil` rather than an unsaved `Tag` for the picker to draw a chip from.
        // Pinned by `CadenceInlineTagCommitSurfaceTests`.
        //
        // [[T-762]] emptied `NoteEditorPane`'s three-entry group that used to sit here — `body`,
        // `noteTagsBinding` and `persistEditorContentIfNeeded` each reached the pane's ambient
        // `ModelContext` and minted a `Tag` with nothing committing it, held open past T-631/T-651
        // because "what does an undo mean under the user's caret" read as unsettled. It was not:
        // none of the three writes `note.tags`/`note.content` until the mint's own commit has
        // already landed, so a refusal never reaches a write an undo would have to fight. `body`'s
        // `.onAppear` and `persistEditorContentIfNeeded` now call
        // `TagSupport.syncNoteTagsFromMarkdownCommittingInsertions`; `noteTagsBinding` calls the new
        // `TagSupport.setTagsCommittingInsertions`, added because it also folds the picked names
        // back into the note's frontmatter. Pinned by
        // `CadenceInlineTagCommitSurfaceTests.noteEditorPaneNoLongerNeedsACommitReachExemption`.
        // [[T-636]](e) and [[T-655]] emptied the three canvas entries that used to sit here.
        // `SchedulingActions.createBundle` inserts into a context it was handed and commits
        // nothing — correctly. Its `createTask` sibling was deleted outright by [[T-759]], having
        // had no production caller left. `SchedulePanel.body`, `CalDayColumn.body` and
        // `TimelineDayCanvas.body` each committed nothing either. All three own their unit of work
        // now, through `SchedulingActions.insertTask` / `insertBundle`, and each names its refusal
        // in an alert. **The siblings stayed** rather than growing a commit: the index vouches for
        // a name only when every overload of it commits, so a commit added to one `createBundle`
        // would have silenced nothing while the other still inserted and returned. Pinned by
        // `CadenceFocusSessionAndBlockCommitTests`.
        // [[T-654]] closed the `FocusView.swift: ["bundleTimerControls", "timerControls"]` entry
        // that used to sit here. Both controls now reach `FocusManager.commitElapsed`/`endSession`/
        // `startFocus`, which commit for real (they used to write the pending bank and stop, with
        // no `save()` of any kind — the reason this half, rather than half 1 or 2, was the one that
        // could see them at all), and `FocusSessionSupport.logSession`/`logBundleSession` commit
        // their own writes the same way. `FocusView.reportingFocusFailure` names a refusal on
        // `TaskCompletionAnimationManager.settleFailed`, the alert `macOSRootView` already shows.
        "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift": ["setStatus"],
        // **Not a defect, and the one entry here that is a limit of the scan rather than a
        // finding.** `CadenceWriteService.resolvedTags` reaches for the service's own stored
        // `context`, so the signature rule cannot subtract it — but the unit of work is owned by
        // `createTask` in the same file, which commits through `saveNotifyAndAudit`. The rule
        // reads "reaches a commit" downwards through same-file calls and has no reading for
        // "my *caller* in this file commits"; adding one would silence real defects, because
        // `body` calling a broken `createTag()` is exactly that shape. Held as a named
        // false positive rather than paid for with a weaker rule.
        "Cadence/Services/MCPReadOnly/CadenceWriteService.swift": ["resolvedTags"],
    ]

    static func commitReachInstrument(changing index: ExistenceIndex) throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "an insert that reaches no commit at all",
            fires: """
            func create() {
                modelContext.insert(habit)
                dismiss()
            }
            """,
            // The nearest negative, and the whole of the exemption mechanism: the same insert, in
            // a helper that was **handed** the context. A detector that only asked "does this
            // function insert without saving" would fire on this and on sixteen more like it.
            andNotOn: """
            static func insertSubtask(titled title: String, into parent: AppTask, modelContext: ModelContext) -> Subtask? {
                let subtask = Subtask(title: title)
                modelContext.insert(subtask)
                return subtask
            }
            """,
            by: { !commitReachOffenders(in: $0, changing: index).isEmpty }
        )
    }

    /// Half 3: a declaration that inserts must **reach a commit** (T-503).
    ///
    /// The hole halves 1 and 2 shared: both key on the *presence* of a `try? …save()`, so a
    /// function that inserts and never commits at all passed both. Measured over the same 552
    /// files, that was 21 declarations, four of which also reported success in the same function —
    /// [[T-471]]'s defect with the save missing entirely rather than swallowed.
    ///
    /// **What subtracts the other seventeen, and why it is a rule rather than a list.** Sixteen of
    /// them take the `ModelContext` as a **parameter**: `TaskCreationService.insertion(from:into:)`,
    /// `CadenceTaskMutationSupport.insertSubtask(…modelContext:)`, `TagSupport.resolveTags(named:in:)`,
    /// the five `NoteMigrationService` passes, and so on. That signature *is* the statement "my
    /// caller owns the unit of work" — the caller chose the context, so the caller chooses when it
    /// commits, and a helper that committed on its own behalf would break the caller's transaction
    /// rather than complete it. A declaration that inserts into an **ambient** context — a stored
    /// property, or `@Environment(\.modelContext)` on a view — has no such caller, so the unit of
    /// work ends with it and it must commit.
    ///
    /// The seventeenth is `CadenceWriteService.createTask`, which does own its context and does
    /// commit — through `saveNotifyAndAudit`, a sibling in the same file. So "reaches a commit"
    /// follows same-file calls to a fixed point rather than reading one body. That clause is worth
    /// its cost: without it the rule would have needed a by-name exemption for a function that
    /// obeys it.
    ///
    /// **What it does not claim.** The call graph stops at the file boundary and at a *name*, so a
    /// commit reached through a closure argument or another file is invisible to it. That is the
    /// usual honest limit of a text scan; it errs toward reporting, which is the safe direction for
    /// a rule whose exemption list is meant to stay empty.
    static func commitReachOffenders(in source: String, changing index: ExistenceIndex) -> [String] {
        let parsed = parsedDeclarations(in: source)
        let committing = committingNames(in: parsed, index: index)
        let local = pendingExistenceNames(in: parsed, committing: committing, index: index)
        return parsed
            .filter { declaration in
                (declaration.changesExistenceDirectly
                    || changesExistenceOneFrameDown(declaration, local: local, index: index))
                    && !declaration.disclaimsOwnership
                    && !commitsItself(declaration, committing: committing, index: index)
            }
            .map(\.name)
            .uniqued()
    }

    /// Every declaration in the file that reaches a commit, directly or through a same-file call.
    ///
    /// A fixed point rather than one hop: `CadenceWriteService.createTask` reaches `context.save()`
    /// through *two* forwarding spellings of `saveNotifyAndAudit`, and stopping at one hop would
    /// have needed a by-name exemption for a function that obeys the rule.
    /// Every declaration in the file that reaches a commit, directly or through a call.
    ///
    /// **The cross-file half applies only to a frame that disclaims ownership, and the asymmetry is
    /// measured rather than tidy.** A helper handed a `ModelContext` is one link in the chain the
    /// existence index propagates along, so "does this frame commit?" has to have the same reach as
    /// "does this frame leave something pending" — otherwise [[T-628]]'s own fix reads as an
    /// offence for ever, because `SchedulingActions.completeBundle` commits through
    /// `CadenceTaskMutationSupport.deleteBundle` in another file.
    ///
    /// A `var body`, or anything else that reached for an ambient context, keeps the same-file
    /// reading. It calls dozens of things and a great many of them commit *something* somewhere;
    /// letting that count made four real half-3 offenders go quiet in one measurement, including
    /// the task inspector's own completion path. The conservative reading errs toward reporting,
    /// which is the safe direction for the frame that owns the unit of work.
    fileprivate static func committingNames(
        in declarations: [ParsedDeclaration],
        index: ExistenceIndex,
        seed: Set<String> = []
    ) -> Set<String> {
        var committing = seed.union(declarations.filter(\.reachesACommitDirectly).map(\.name))
        var changed = true
        while changed {
            changed = false
            for declaration in declarations where !committing.contains(declaration.name) {
                if commitsItself(declaration, committing: committing, index: index) {
                    committing.insert(declaration.name)
                    changed = true
                }
            }
        }
        return committing
    }

    /// Whether this one declaration reaches a commit, given what is known so far.
    ///
    /// The per-declaration form of `committingNames`, which answers by *name*. Both readings are
    /// needed: a bare call inside a file can only be resolved by name, and publishing a name to the
    /// cross-file index needs every overload to agree.
    private static func commitsItself(
        _ declaration: ParsedDeclaration,
        committing: Set<String>,
        index: ExistenceIndex
    ) -> Bool {
        if declaration.reachesACommitDirectly { return true }
        return declaration.calls.contains { call in
            guard call.callee != "body", !isRecursive(call, in: declaration) else { return false }
            guard let qualifier = call.qualifier else { return committing.contains(call.callee) }
            return declaration.disclaimsOwnership && index.commits(call.callee, on: qualifier)
        }
    }

    /// Changing what the store holds, and it is `insert` **or** `delete` — gap 3 of T-627.
    ///
    /// Half 1 read both from the start; half 3 read only `insert(` for its first two tickets, so
    /// "delete and never commit at all" was covered by nothing at all: half 1 sees the delete but
    /// needs a `try?` that is not there, half 3 sees the missing commit but only for inserts.
    /// `SchedulingService.completeBundle` sat in exactly that hole ([[T-628]]).
    private static let existenceCall = "(modelContext|context|ctx)\\??\\.(insert|delete)\\("
    /// "My caller owns the unit of work", spelled as a signature. `:\s*ModelContext\b` and not
    /// merely `ModelContext`, so that `commit: (ModelContext) throws -> Void` — which is a
    /// *commit* being handed in, the opposite claim — does not exempt anything.
    private static let handedAModelContext = ":\\s*ModelContext\\b"
    private static let commitCall = "\\.save\\(\\)|CadencePendingChangePersistence\\.commit\\w*"

    /// Half 1: declarations holding both a swallowed save and an existence change — **theirs, or
    /// one frame down** (gap 1 of T-627).
    ///
    /// The literal-`insert(`-in-my-own-body reading is the one this app is worst suited to. Its
    /// mutations live one frame away from the button by design, so the frame that swallows the
    /// commit and the frame that calls `context.insert` are routinely different frames, and each
    /// read on its own is clean. `MarkdownEditorView` is the plain case: it swallows a save over
    /// `MarkdownImageAssetService.createAsset`, and the insert is in `createAsset` ([[T-629]]).
    static func existenceOffenders(in source: String, changing index: ExistenceIndex) -> [String] {
        let parsed = parsedDeclarations(in: source)
        let local = pendingExistenceNames(
            in: parsed,
            committing: committingNames(in: parsed, index: index),
            index: index
        )
        return parsed
            .filter { declaration in
                declaration.swallowsDirectly
                    && (declaration.changesExistenceDirectly
                        || changesExistenceOneFrameDown(declaration, local: local, index: index))
            }
            .map(\.name)
            .uniqued()
    }

    // MARK: - Half 2b: a rearrangement the user can see (T-614, T-871)

    /// A hand-rolled `order` renumber that reaches a swallowed commit, or none — [[T-871]], and
    /// **the only part of [[T-614]]'s clause that a text scan can be sound about.**
    ///
    /// **The clause, and why it has no spelling.** `AGENTS.md`'s half 2 lists the ways a screen says
    /// it worked, and every one of them is a *word*: `dismiss…()`, `is/show<X> = false`,
    /// `on(Save|Done|Complete|Commit)(`, `return true`. T-614 added "**or a rearrangement the user
    /// can see**" — a row that stays where you dropped it outclaims a dismissed sheet, and a refused
    /// reorder reverts at next launch with nothing to retry. That one is not a word. It is a
    /// *picture*, and `successReport` cannot grow an alternation for it.
    ///
    /// **What this fires on instead, and it is deliberately narrower than the clause.** The shape
    /// [[T-868]] and [[T-869]] were actually written in: a `for` loop assigning `\.order` on rows the
    /// frame did not just create, in a declaration that owns its unit of work and either swallows
    /// its commit or reaches none. That is a proxy for the clause, not the clause. It is *sound* —
    /// every site it names really does renumber and really does fail to commit — and it is
    /// **incomplete in three measured ways**, all of which are stated here so that nobody reads a
    /// green run as the clause being covered:
    ///
    /// 1. **An ordering that is not an `order` field is invisible.** [[T-870]] was the kanban
    ///    *column* order, a re-serialised `[TaskSectionConfig]` blob on the list.
    ///    `CadenceOrderCommit`'s own doc names this blind spot in the same words.
    /// 2. **A renumber delegated to a helper is invisible**, and that is now the *right* way to
    ///    write one: five of the seven sites T-868/T-869 fixed pass `writeOrder: { $0.order = $1 }`
    ///    to `CadenceOrderCommit.commit`, where the loop lives. So this half sees the wrong spelling
    ///    and not the right one — which is the useful polarity, but it means the count it reports is
    ///    not the count of reorder surfaces.
    /// 3. **`move(fromOffsets:toOffset:)` on a bound array is invisible.** SwiftUI's own reorder
    ///    gesture rearranges the array and never writes a field.
    ///
    /// **Why it is not `!disclaimsOwnership` by accident.** `TagSupport.seedDefaultTags(in:…)`
    /// writes `tag.order = index` in an `.enumerated()` loop and ends `try? context.save()`, and it
    /// is the single measured site this exclusion subtracts. It is handed its `ModelContext`, so its
    /// caller owns the unit of work — the same rule half 3 uses, for the same reason — and it is
    /// allocating initial positions rather than rearranging a sequence a user just dragged.
    ///
    /// Measured over `Cadence/` at `f75c2ba`: **six** declarations renumber `\.order` inside a loop,
    /// and after T-868/T-869/T-870 every one of them commits. The exemption list is empty and is
    /// meant to stay that way.
    static func rearrangementOffenders(in source: String, changing index: ExistenceIndex) -> [String] {
        let parsed = parsedDeclarations(in: source)
        let committing = committingNames(in: parsed, index: index)
        return parsed
            .filter { declaration in
                renumbersInALoop(declaration.body)
                    && !declaration.disclaimsOwnership
                    && (declaration.swallowsDirectly
                        || !commitsItself(declaration, committing: committing, index: index))
            }
            .map(\.name)
            .uniqued()
    }

    /// Whether the body assigns `\.order` **inside a loop**.
    ///
    /// In a loop rather than anywhere, because a single `row.order = next` is an *allocation* — where
    /// a new row goes — and cannot be a rearrangement of rows that were already placed.
    /// `CadenceOrderAllocation` is the family member that owns that case and it cannot fail.
    private static func renumbersInALoop(_ body: [Character]) -> Bool {
        let text = String(body)
        guard let regex = try? NSRegularExpression(pattern: "\\bfor\\b[^\\n{]*\\{") else { return false }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains { match in
            guard let range = Range(match.range, in: text) else { return false }
            let opens = text.distance(from: text.startIndex, to: range.upperBound)
            let loop = String(body[opens..<blockEnd(in: body, from: opens)])
            return CadenceSourceScan.matchCount(orderWrite, in: loop) > 0
        }
    }

    /// `something.order = …`, and not `==`. Anchored on the member so a local named `order` — a
    /// `for (index, order) in …` binding, of which this repo has several — is not read as a field.
    private static let orderWrite = "\\w\\.order\\s*=(?!=)"

    /// The reader `theRearrangementHalfStillReadsTheAppsHandWrittenRenumbers` uses to prove the
    /// loop matcher still matches, without exposing it to anything else.
    static func renumbersInALoopForTesting(named name: String, in source: String) -> Bool? {
        guard let declaration = parsedDeclarations(in: source).first(where: { $0.name == name }) else {
            return nil
        }
        return renumbersInALoop(declaration.body)
    }

    /// Empty, and the assertion is that it stays empty: every rearrangement in the app commits and
    /// names its refusal. An entry here would be a screen that rearranges over a store that has not
    /// agreed, which is the one failure in this rule with no halfway reading — the next fetch does
    /// not correct it, it silently undoes it.
    static let rearrangementExemptions: [String: [String]] = [:]

    static func rearrangementInstrument(changing index: ExistenceIndex) throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "a renumber the user can see over a commit that was swallowed or never made",
            fires: """
            private func reorderTask(from source: IndexSet, to destination: Int) {
                var ordered = tasks
                ordered.move(fromOffsets: source, toOffset: destination)
                for (index, task) in ordered.enumerated() {
                    task.order = index
                }
                try? modelContext.save()
            }
            """,
            // The nearest negative, and it is `ListDetailComponents.reorderTask` as [[T-869]] left
            // it: the same loop, committed through the shared surface, with the answer handed back
            // for the caller to turn into `CadenceOrderCommit.failureNotice`. A detector that only
            // asked "does this function write `\\.order` in a loop" would fire on this.
            andNotOn: """
            private func reorderTask(from source: IndexSet, to destination: Int) -> Bool {
                var ordered = tasks
                ordered.move(fromOffsets: source, toOffset: destination)
                return CadenceOrderCommit.commit(
                    ordered,
                    readOrder: { $0.order },
                    writeOrder: { $0.order = $1 },
                    in: modelContext
                )
            }
            """,
            by: { !rearrangementOffenders(in: $0, changing: index).isEmpty }
        )
    }

    // MARK: - Existence, one frame down (T-627 gap 1)

    /// The callees that leave an existence change **pending on their caller**: a declaration that
    /// inserts or deletes and does not itself reach a commit.
    ///
    /// Keyed by name **and enclosing type**, exactly as `SwallowingIndex` is and for the measured
    /// reason recorded there — resolving a qualified call by bare name reported 17 sites where the
    /// pairing reported 2, because `save`, `create` and `persistNote` are each declared in several
    /// files here.
    ///
    /// **Only declarations handed a `ModelContext` are in here, and that is the whole design.**
    /// Half 3's exemption already says such a declaration is *not* the party that decides when to
    /// commit — its caller owns the unit of work. Read forwards instead of backwards, that is a
    /// propagation rule: a pending insert or delete travels up through every handed-a-context frame
    /// and stops at the first frame that was **not** handed one. That frame is the offender, and it
    /// is the only one reported, so a chain N frames deep yields one finding rather than N.
    ///
    /// It also terminates for free. Chasing *every* callee would report every screen that
    /// transitively touches `TagSupport.resolveTags`; chasing only the frames that disclaim
    /// ownership reports the frame that has it.
    ///
    /// Transitive rather than one hop, because this app's chains are long: ticking a recurring
    /// task's circle on macOS goes `TaskCompletionAnimationManager.write` →
    /// `TaskWorkflowService.markDone(_:in:)` → `CadenceTaskRecurrenceWorkflowSupport.markDone` →
    /// `spawnNextOccurrenceIfNeeded`, and only the fourth frame holds `context.insert` ([[T-628]]).
    /// The middle three all disclaim ownership in their signatures.
    ///
    /// **A callee that commits is not in here**, which is what keeps the properly-fixed sites
    /// quiet: `CadencePendingChangePersistence.commitInsert` inserts and saves, and a caller of
    /// `CadenceTaskMutationSupport.deleteBundle` — [[T-322]]'s throwing sibling — reaches a commit
    /// through it rather than inheriting a pending delete.
    struct ExistenceIndex {
        fileprivate var typesByName: [String: Set<String>] = [:]
        /// The other half: every declaration in the app that **reaches a commit**, resolved the
        /// same way. Half 3 read this same question one file at a time, and after T-628 that was
        /// not enough — the fix routes `SchedulingActions.completeBundle` through
        /// `CadenceTaskMutationSupport.deleteBundle`, whose `commitDelete` is in another file, so a
        /// same-file-only reading would have called the fixed code an offender for ever.
        fileprivate var committersByName: [String: Set<String>] = [:]

        /// How many distinct callee names the index holds; the non-vacuity handle for a builder
        /// that silently read nothing, the same one `SwallowingIndex.namesRead` gives.
        var namesRead: Int { typesByName.count }

        /// How many distinct committing callee names it holds. Separate from `namesRead` because
        /// the two halves fail differently: an empty pending map makes the sweep blind, an empty
        /// committer map makes it *loud*, and a sweep should be able to say which.
        var committersRead: Int { committersByName.count }

        fileprivate func holds(_ callee: String, on qualifier: String) -> Bool {
            typesByName[callee]?.contains(qualifier) ?? false
        }

        fileprivate func commits(_ callee: String, on qualifier: String) -> Bool {
            committersByName[callee]?.contains(qualifier) ?? false
        }
    }

    static func existenceIndex(
        over files: [String],
        read: (String) throws -> String
    ) rethrows -> ExistenceIndex {
        let parsed = try files.map { parsedDeclarations(in: try read($0)) }
        var index = ExistenceIndex()

        // Two fixed points, in this order and not interleaved. Both grow monotonically, and a name
        // entering the committing set has to *remove* it from the pending one — so computing them
        // together would leave whatever the first round decided about a declaration whose callee
        // only became a committer later. Committing does not depend on pending, so running it to
        // completion first is both correct and cheaper.
        var committing = [Set<String>](repeating: [], count: parsed.count)
        var changed = true
        while changed {
            changed = false
            for (fileIndex, declarations) in parsed.enumerated() {
                let names = committingNames(in: declarations, index: index, seed: committing[fileIndex])
                if names != committing[fileIndex] {
                    committing[fileIndex] = names
                    changed = true
                }
                // **Published only when every overload of that name on that type commits.** The
                // index resolves a call by name and type and cannot see an argument list, so one
                // committing overload would vouch for its siblings: `SchedulingActions` declares
                // two `createBundle(…in:)`, and the one that forwards to
                // `CadenceTaskMutationSupport.insertBundle` does commit while the one the timeline
                // canvas calls inserts and does not. Unanimity is the safe direction here — a
                // missing committer costs a report, a wrong one costs the finding.
                for declaration in declarations where names.contains(declaration.name) {
                    let overloads = declarations.filter {
                        $0.name == declaration.name && $0.type == declaration.type
                    }
                    guard overloads.allSatisfy({ commitsItself($0, committing: names, index: index) }),
                          index.committersByName[declaration.name]?.contains(declaration.type) != true
                    else { continue }
                    index.committersByName[declaration.name, default: []].insert(declaration.type)
                    changed = true
                }
            }
        }

        var reached = [Set<String>](repeating: [], count: parsed.count)
        changed = true
        while changed {
            changed = false
            for (fileIndex, declarations) in parsed.enumerated() {
                let names = pendingExistenceNames(
                    in: declarations,
                    committing: committing[fileIndex],
                    index: index,
                    seed: reached[fileIndex]
                )
                guard names != reached[fileIndex] else { continue }
                for name in names.subtracting(reached[fileIndex]) {
                    for declaration in declarations where declaration.name == name {
                        index.typesByName[name, default: []].insert(declaration.type)
                    }
                }
                reached[fileIndex] = names
                changed = true
            }
        }
        return index
    }

    /// The declarations in one file that leave an existence change pending **on their caller**:
    /// handed a context, reaching no commit, and inserting or deleting either directly or through
    /// another such declaration.
    ///
    /// `body` is excluded because it is not a callee — nothing in this app calls `body(` — so an
    /// entry for it could only ever collide with a same-named function elsewhere.
    fileprivate static func pendingExistenceNames(
        in declarations: [ParsedDeclaration],
        committing: Set<String>,
        index: ExistenceIndex,
        seed: Set<String> = []
    ) -> Set<String> {
        var names = seed
        var changed = true
        while changed {
            changed = false
            for declaration in declarations
            where declaration.name != "body"
                && declaration.disclaimsOwnership
                && !names.contains(declaration.name)
                && !commitsItself(declaration, committing: committing, index: index) {
                let reaches = declaration.changesExistenceDirectly
                    || changesExistenceOneFrameDown(declaration, local: names, index: index)
                if reaches {
                    names.insert(declaration.name)
                    changed = true
                }
            }
        }
        return names
    }

    private static func changesExistenceOneFrameDown(
        _ declaration: ParsedDeclaration,
        local: Set<String>,
        index: ExistenceIndex
    ) -> Bool {
        declaration.calls.contains { call in
            guard !isRecursive(call, in: declaration) else { return false }
            guard let qualifier = call.qualifier else { return local.contains(call.callee) }
            return index.holds(call.callee, on: qualifier)
        }
    }

    /// Whether a call is the declaration calling **itself**, which the fixed points below must not
    /// count as reaching anything.
    ///
    /// Name equality alone is the wrong test, and it cost a real finding: `TaskWorkflowService`
    /// declares `markDone(_:in:)` and forwards to `CadenceTaskRecurrenceWorkflowSupport.markDone`,
    /// which is where the recurrence insert lives. A bare-name recursion guard reads that forward
    /// as self-recursion, drops it, and the whole macOS completion spine goes quiet — the chain
    /// [[T-628]](a) is about. A *qualified* call is only recursive when the qualifier is the
    /// declaration's own enclosing type.
    fileprivate static func isRecursive(
        _ call: (qualifier: String?, callee: String, end: Int),
        in declaration: ParsedDeclaration
    ) -> Bool {
        guard call.callee == declaration.name else { return false }
        guard let qualifier = call.qualifier else { return true }
        return qualifier == declaration.type
    }

    /// Half 2: declarations where something in the save's **own block** reports success.
    ///
    /// The save's own block rather than the whole declaration, because the whole declaration is
    /// wrong in the direction that matters: a `var body` holding an autosave in one closure and a
    /// `dismiss()` in an unrelated one is not this defect, and a rule that called it one would be
    /// silenced by an exemption instead of obeyed.
    ///
    /// **The whole block, not the tail after the save** — gap 4 of T-627. The rule read downwards
    /// only, and three measured sites dismiss *first*: `AIActionsSupportViews`' destination rows
    /// call `dismissPicker()` and then move the note ([[T-630]]). Ordering was never the claim —
    /// "the screen moved on over a store that refused" is true whichever line came first, and a
    /// closure is its own block, so the discrimination the tail reading was protecting is the block
    /// scoping rather than the direction.
    static func reportOffenders(in source: String) -> [String] {
        var names: [String] = []
        let persisted = persistedReport(in: source)
        let filledIn = filledInReport(in: source)
        for declaration in declarations(in: source) {
            let body = Array(declaration.body)
            let vocabulary = successReport(
                returning: declaration.signature,
                persisted: persisted,
                filledIn: filledIn,
                buildingItsOwnAnswer: true
            )
            let cancelled = cancelledWorkItemNames(in: declaration.body)
            var index = 0
            while index < body.count {
                guard let save = nextSave(in: body, from: index) else { break }
                let block = String(body[blockStart(in: body, before: save.start)..<blockEnd(in: body, from: save.end)])
                if reportsSuccess(in: block, vocabulary: vocabulary, ignoring: cancelled) {
                    names.append(declaration.name)
                    break
                }
                index = save.end
            }
        }
        return names.uniqued()
    }

    // MARK: - Half 2, one frame down (T-566)

    /// The callees a caller learns nothing from: a declaration that swallows a commit and does
    /// **not** `throws`, so "it returned" and "it was written" are the same observation.
    ///
    /// Keyed by name **and enclosing type**, not by name alone. Measured over the same file set:
    /// resolving a qualified call by bare name reports **17** sites where the pairing reports 2,
    /// because `save`, `create` and `persistNote` are each declared in several files. The one
    /// extra that was read through is `iOSEventNoteEditorSheet.persistNote`, which returns an
    /// outcome its caller *guards on* — the shape this rule asks for, reported as the defect.
    struct SwallowingIndex {
        fileprivate var typesByName: [String: Set<String>] = [:]

        /// How many distinct callee names the index holds. A sweep that asserts this is
        /// non-trivial is how a builder which silently read nothing gets caught — an empty index
        /// makes this whole half permanently green.
        var namesRead: Int { typesByName.count }

        fileprivate func holds(_ callee: String, on qualifier: String) -> Bool {
            typesByName[callee]?.contains(qualifier) ?? false
        }
    }

    /// Every declaration in the app whose answer hides a swallowed commit, directly or through a
    /// chain of same-file calls, resolved to a fixed point **across** files.
    ///
    /// Two frames is the shape this exists for and one hop would have missed it: T-566's Save
    /// button called `save()`, `save()` called `CadenceTaskMutationSupport.updateBundle`, and only
    /// the third frame held the `try? modelContext.save()`.
    static func swallowingIndex(
        over files: [String],
        read: (String) throws -> String
    ) rethrows -> SwallowingIndex {
        let parsed = try files.map { parsedDeclarations(in: try read($0)) }
        var index = SwallowingIndex()
        var reached = [Set<String>](repeating: [], count: parsed.count)
        var changed = true
        while changed {
            changed = false
            for (fileIndex, declarations) in parsed.enumerated() {
                let names = localSwallowingNames(in: declarations, index: index, seed: reached[fileIndex])
                guard names != reached[fileIndex] else { continue }
                for name in names.subtracting(reached[fileIndex]) {
                    for declaration in declarations where declaration.name == name {
                        index.typesByName[name, default: []].insert(declaration.type)
                    }
                }
                reached[fileIndex] = names
                changed = true
            }
        }
        return index
    }

    /// Half 2, one frame down: a declaration that calls something which swallows a commit and then
    /// reports success in the same block (T-566).
    ///
    /// Half 2 above needs a literal `try?` in the reporting function's own body, and that is not
    /// where this app writes its mutations: the sheet calls `save()`, `save()` calls a shared
    /// mutation, and the mutation swallows. Every frame in that chain passed both existing halves,
    /// and the user still watched a block get saved that the store had refused.
    ///
    /// **Declarations half 2 already reports are subtracted**, so the two halves stay disjoint and
    /// a site never needs an entry in both exemption lists.
    ///
    /// **What it does not claim.** A qualified call resolves only when the qualifier is the *type*
    /// that declares the callee, so an instance method swallowing in another file is invisible
    /// here — deliberately, see `SwallowingIndex`. And `try?` on a *throwing* helper is not a
    /// swallow this can see, because `swallowedSave` keys on the commit surface rather than on
    /// `try?` itself; `iOSCalendarBoardView.move` is that shape and is allowed to be, since a drag
    /// reports nothing.
    static func indirectReportOffenders(in source: String, swallowing index: SwallowingIndex) -> [String] {
        let parsed = parsedDeclarations(in: source)
        let reached = localSwallowingNames(in: parsed, index: index)
        let direct = Set(reportOffenders(in: source))
        var names: [String] = []
        let persisted = persistedReport(in: source)
        let filledIn = filledInReport(in: source)
        for declaration in parsed where !direct.contains(declaration.name) {
            // **`buildingItsOwnAnswer: false`**, and it is measured rather than cautious. The
            // Optional spelling is a claim by the frame that *builds* the answer; one frame down,
            // an Optional handed back is a forward. Extending it here adds exactly three sites over
            // 564 files and all three are forwards: `CadenceTaskMutationSupport.insertBundle` is
            // **handed** a `ModelContext` and returns its bundle to the caller that owns the
            // commit, and `macOSRootCommandSupport.handle` /
            // `RootCommandEventSupport.handleCommandKeyEvent` answer `NSEvent?` with the polarity
            // **inverted** — `nil` is how "I consumed the event" is spelled there, so a non-`nil`
            // answer says the frame did *not* act.
            let vocabulary = successReport(
                returning: declaration.signature,
                persisted: persisted,
                filledIn: filledIn,
                buildingItsOwnAnswer: false
            )
            let cancelled = cancelledWorkItemNames(in: declaration.text)
            for call in declaration.calls
            where !isRecursive(call, in: declaration)
                && reachesASwallow(call.qualifier, call.callee, reached: reached, index: index) {
                let opens = blockStart(in: declaration.body, before: call.end)
                let closes = blockEnd(in: declaration.body, from: call.end)
                let block = String(declaration.body[opens..<closes])
                if reportsSuccess(in: block, vocabulary: vocabulary, ignoring: cancelled) {
                    names.append(declaration.name)
                    break
                }
            }
        }
        return names.uniqued()
    }

    /// The exemption list for the half that follows a swallowed commit one frame down.
    ///
    /// The two sites it found that no other half could see were [[T-497]]'s last two, and both are
    /// fixed; what remains below came from T-627's widened vocabulary.
    static let indirectReportExemptions: [String: [String]] = [
        // [[T-497]] tier 3 emptied both entries that used to open this list.
        // `iOSMarkdownReferenceSupport.body` was the third "flush an in-place edit, then close" —
        // see `reportExemptions` for the decision that unblocked the family.
        // `KanbanCardMetaSupportViews.select` was never blocked on anything: the popover holds no
        // draft, so `CadenceTaskMutationSupport.moveToContainer` commits through
        // `commitEdit(in:undo:)` and answers, and the picker stays open over the refusal.

        // MARK: Found by T-627's widened vocabulary and block window
        //
        // T-630 emptied macOS Move Note out of this list. `dismissPicker()` ran *before* the move,
        // so the tail-only reading could not have seen it whatever the vocabulary said; the three
        // destination rows now hand their move to `moveNote`, which closes the popover only below
        // the `catch`. Pinned by `CadenceNoteMoveCommitTests`.
        // [[T-633]]'s other half — the task sheet's own scope dialog — left with the row chip's,
        // through the same unit and into the same alert.
        // [[T-636]](c) left too: `iOSFocusView.complete` guards its reset and its advance on
        // `completeFocusSession`'s answer, so the stopwatch is cleared only once the store has the
        // session it measured.
        // [[T-636]](a) from the note editor's task embed: `content` answers `true` to the popover
        // over `setStatus`, which reaches the recurrence insert.
        "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift": ["content"],
    ]

    static func indirectReportInstrument(swallowing index: SwallowingIndex) throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "a success report over a commit swallowed one frame down",
            fires: """
            struct Sheet: View {
                var body: some View {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }

                private func save() {
                    bundle.title = title
                    try? modelContext.save()
                }
            }
            """,
            // The nearest negative, and it is T-566's own fix: the same two frames, with the inner
            // one throwing and the outer one catching before it dismisses. A detector that merely
            // noticed `save()` above a `dismiss()` would fire on this.
            andNotOn: """
            struct Sheet: View {
                var body: some View {
                    Button("Save") {
                        do {
                            try save()
                        } catch {
                            saveFailed = true
                            return
                        }
                        dismiss()
                    }
                }

                private func save() throws {
                    bundle.title = title
                    try CadencePendingChangePersistence.commitEdit(in: modelContext) { bundle.title = previous }
                }
            }
            """,
            by: { !indirectReportOffenders(in: $0, swallowing: index).isEmpty }
        )
    }

    /// The declarations in one file that reach a swallowed commit, to a fixed point.
    ///
    /// `seed` is what the index builder carries between rounds: a name unlocked by another file's
    /// declaration becoming swallowing must not be recomputed from nothing.
    private static func localSwallowingNames(
        in declarations: [ParsedDeclaration],
        index: SwallowingIndex,
        seed: Set<String> = []
    ) -> Set<String> {
        var names = seed
        var changed = true
        while changed {
            changed = false
            for declaration in declarations
            where declaration.name != "body"
                && !declaration.throwsItsAnswer
                && !names.contains(declaration.name) {
                let reaches = declaration.swallowsDirectly || declaration.calls.contains {
                    !isRecursive($0, in: declaration)
                        && reachesASwallow($0.qualifier, $0.callee, reached: names, index: index)
                }
                if reaches {
                    names.insert(declaration.name)
                    changed = true
                }
            }
        }
        return names
    }

    private static func reachesASwallow(
        _ qualifier: String?,
        _ callee: String,
        reached: Set<String>,
        index: SwallowingIndex
    ) -> Bool {
        guard let qualifier else { return reached.contains(callee) }
        return index.holds(callee, on: qualifier)
    }

    fileprivate struct ParsedDeclaration {
        let name: String
        let type: String
        let signature: String
        let throwsItsAnswer: Bool
        let swallowsDirectly: Bool
        /// Whether the declaration's **own** body calls `insert(` or `delete(` on a context.
        let changesExistenceDirectly: Bool
        let reachesACommitDirectly: Bool
        /// "My caller owns the unit of work", read off the signature — half 3's exemption rule,
        /// which is also what makes a pending existence change propagate past this frame.
        let disclaimsOwnership: Bool
        let text: String
        let body: [Character]
        /// Every call in the body, as its qualifier (`nil` for a bare call), its callee, and the
        /// offset just past the opening paren — which is where the block tail is read from.
        let calls: [(qualifier: String?, callee: String, end: Int)]
    }

    /// `declarations(in:)` plus the three things this half needs per declaration, computed once.
    ///
    /// Once, because the index is a fixed point over every file: recomputing the regex work each
    /// round would run it six times over the whole tree.
    fileprivate static func parsedDeclarations(in source: String) -> [ParsedDeclaration] {
        let found = declarations(in: source)
        return zip(found, enclosingTypeNames(in: source, for: found)).map { declaration, type in
            ParsedDeclaration(
                name: declaration.name,
                type: type,
                signature: declaration.signature,
                throwsItsAnswer: declaration.signature.contains("throws"),
                swallowsDirectly: CadenceSourceScan.matchCount(swallowedSave, in: declaration.body) > 0,
                changesExistenceDirectly: CadenceSourceScan.matchCount(existenceCall, in: declaration.body) > 0,
                reachesACommitDirectly: CadenceSourceScan.matchCount(commitCall, in: declaration.body) > 0,
                disclaimsOwnership: CadenceSourceScan.matchCount(handedAModelContext, in: declaration.signature) > 0,
                text: declaration.body,
                body: Array(declaration.body),
                calls: callSites(in: declaration.body)
            )
        }
    }

    private static func callSites(in body: String) -> [(qualifier: String?, callee: String, end: Int)] {
        guard let regex = try? NSRegularExpression(pattern: callSite) else { return [] }
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match in
            guard let whole = Range(match.range, in: body),
                  let callee = Range(match.range(at: 2), in: body) else { return nil }
            return (
                Range(match.range(at: 1), in: body).map { String(body[$0]) },
                String(body[callee]),
                body.distance(from: body.startIndex, to: whole.upperBound)
            )
        }
    }

    /// The type each declaration is declared in, in the same order.
    ///
    /// Found by walking the file's type declarations alongside `declarations(in:)`'s own order
    /// rather than by parsing scopes: a text scan cannot tell a nested type from a sibling, and
    /// the last type opened before a `func` is the answer in every file in this repository.
    private static func enclosingTypeNames(
        in source: String,
        for declarations: [(name: String, signature: String, body: String)]
    ) -> [String] {
        let types = CadenceSourceScan.captures(typeDeclaration, in: source)
        var names: [String] = []
        var cursor = source.startIndex
        for declaration in declarations {
            let found = source.range(of: declaration.signature, range: cursor..<source.endIndex)
            let start = found?.lowerBound ?? cursor
            names.append(types.last { $0.range.lowerBound < start }?.text ?? "")
            if let found { cursor = found.lowerBound }
        }
        return names
    }

    private static let callSite = "(?:\\b(\\w+)\\s*\\.\\s*)?\\b(\\w+)\\s*\\("
    private static let typeDeclaration = "\\b(?:enum|struct|final class|class|actor|extension)\\s+(\\w+)"
    /// A `func` head, or a property head that carries a **type annotation**. The annotation is what
    /// separates a computed property from a stored one for this reader's purposes: `var draft = ""`
    /// never opens a brace, so requiring the `:` keeps the match set close to the declarations that
    /// actually have bodies without needing to look ahead for one.
    private static let declarationHead = "func\\s+([A-Za-z_]\\w*)\\s*[(<]|var\\s+([A-Za-z_]\\w*)\\s*:"

    /// What "swallowed" means, and it is **not** `save` (T-508).
    ///
    /// The rule keyed on the method name for its first three tickets, and an external audit found
    /// what that misses: `iOSListSupportViews.addLink` writes
    /// `try? CadenceSavedLinkPersistence.insert(link, in: modelContext)`. That helper commits and
    /// rolls back correctly — the caller throws the answer away. Keying on the *commit surface*
    /// rather than on one method's name is what makes it visible.
    ///
    /// **Where this stops, measured rather than assumed.** `try? content.write(to:)` in
    /// `NoteExportService.export` was the same swallow over a file rather than a store, and adding
    /// `\.write\(to:` to this needle finds **nothing**: nothing after that write reports success
    /// in source, because the report is the *absence* of an error sheet. It is outside this rule's
    /// shape rather than hidden from it — a file write has no pending-change semantics to be left
    /// in. Do not widen this needle for it; that site was fixed as T-506 and the shape is now swept
    /// by `NoteExportSurfaceTests.noExportSwallowsTheWriteThatProducesTheFile`, which is a separate
    /// guard precisely because this rule cannot see it.
    private static let swallowedSave = "try\\?\\s+([\\w.?]+\\.save\\(\\)|Cadence\\w*Persistence\\.\\w+\\()"
    /// The vocabulary, and it is deliberately a closed list rather than a notion of "reports
    /// success". Four spellings, each of which means the screen moved on:
    ///
    /// - `dismiss()` — the sheet closes.
    /// - `is<Something> = false` — the same thing said by a flag: `isPresented` for a sheet,
    ///   `isAdding` for an inline add form. Generalised from the literal `isPresented` in T-508,
    ///   after `iOSListSupportViews.addLink` turned out to close its form with `isAdding = false`.
    ///   On its own the widening finds nothing new across 552 files; it is only in combination
    ///   with the swallowed-call needle above that it reports that one site.
    /// - `onSave(…)` / `onDone(…)` / `onComplete(…)` / `onCommit(…)` — a completion handler, which
    ///   is a caller being told it worked.
    /// - `editingThing = nil`, and `isEditing = false` under the flag spelling above — an
    ///   **inline row editor** collapsing back to its display row. Added after measuring: without
    ///   it the rule missed three real sites in the two tag editors, where the row closes showing a
    ///   name the store may not hold. An inline editor closing is a dismissal; it just does not own
    ///   a sheet to say so with.
    /// - `presentedThing = …` — a sheet being **opened** on what was just written (T-503). The
    ///   mirror image of `dismiss()` and the sharpest spelling of the report half, because the
    ///   editor the user lands in is itself the claim that the row exists. `=(?!=)` rather than
    ///   `=`: `presentedEventNote == nil` is how these sheets are *bound*, and a needle that read
    ///   a comparison as an assignment would fire on every one of them.
    ///
    /// **T-627 gap 4 added the four spellings this app actually dismisses with**, measured rather
    /// than imagined. The vocabulary was assembled from three tickets' worth of sheets and had
    /// stopped describing the codebase around it:
    ///
    /// - `show<Something> = false` — the sibling of the `is` flag above, and the one macOS reaches
    ///   for: `showEditor = false` closes the kanban column editor ([[T-632]]), `showPopover =
    ///   false` closes the bundle popover ([[T-628]]).
    /// - `selected<Something> = nil` / `pending<Something> = nil` — a selection cleared *is* the
    ///   dismissal for a popover bound to it (`selectedBundleID = nil`), and
    ///   `pendingRecurrenceRule = nil` is literally what closes iOS's recurrence-scope dialog
    ///   ([[T-633]]). The same sentence `editing<Something> = nil` already said for inline editors.
    /// - `dismiss<Something>()` — the app's own named dismissals, `dismissPicker()` ([[T-630]]).
    ///   `\bdismiss` and not `\bdismiss\(\)`, so a helper that closes the thing counts as
    ///   closing the thing.
    ///
    /// **A flag spelling is `(?<![.\\w])`-anchored, and that is not decoration.** Every one of these
    /// names a piece of *view* state — the screen's own `@State`, which is the only thing that can
    /// move on. `context.isArchived = false` is a **model field** being edited, which is the case
    /// the rule deliberately leaves alone, and it appears above a swallowed save in four settings
    /// screens. The tail-only window used to hide that by accident; reading the whole block makes
    /// the anchor load-bearing.
    ///
    /// Widening it is how the rule grows. A spelling that is not here is not covered, which is the
    /// honest limit of a text scan and the reason the rule is also written in `AGENTS.md` for a
    /// reader.
    private static let successReport: String = {
        var spellings = ["\\bdismiss\\w*\\(", "\\bon(Save|Done|Complete|Commit)\\("]
        spellings.append(viewState + "(is|show)[A-Z]\\w*\\s*=\\s*false")
        spellings.append(viewState + "(editing|selected|pending)[A-Z]\\w*\\s*=\\s*nil")
        spellings.append(viewState + "presented[A-Z]\\w*\\s*=(?!=)")
        return spellings.joined(separator: "|")
    }()

    /// A flag that belongs to the **view**: unqualified, or written through `self.`.
    ///
    /// Both spellings appear in the same file — `iOSTaskRowActionViews` writes
    /// `pendingRecurrenceRule = nil` in a binding and `self.pendingRecurrenceRule = nil` in a
    /// method, and they are the same dismissal — so neither anchor alone describes the app.
    private static let viewState = "(?:(?<![.\\w])|(?<=\\bself\\.))"

    /// The vocabulary a declaration with this signature reports success in.
    ///
    /// **`return true` is a success report, but only from a `-> Bool`** — T-627 gap 4, and the repo
    /// had already written the argument down: `TasksPanelDropCoordinator` says of a drop handler
    /// that *"a silent accept says the move happened"*. A drop handler has no sheet to close and no
    /// completion handler to call; its answer **is** the report, and returning `true` over a
    /// swallowed commit tells the drag it landed. Scoping the needle to the return type is what
    /// keeps it from firing on every `guard`-shaped `return true` in the app.
    /// Whether anything in `block` reports success, discounting `pending…` names the enclosing
    /// declaration **cancels**.
    ///
    /// `pendingRecurrenceRule = nil` closes iOS's recurrence-scope dialog ([[T-633]]);
    /// `pendingAppDataRefresh = nil` clears a `DispatchWorkItem` that has just run, and
    /// `pendingFallbackContentSyncTask = nil` a `Task`. Both spellings are `pending<Something> =
    /// nil`, and the readable difference is that a unit of work is the kind of thing you
    /// `cancel()`. Measured: the discriminator is worth exactly two false positives, and without
    /// it the `pending` spelling costs more than it finds.
    private static func reportsSuccess(
        in block: String,
        vocabulary: String,
        ignoring cancelled: Set<String>
    ) -> Bool {
        guard !cancelled.isEmpty else { return CadenceSourceScan.matchCount(vocabulary, in: block) > 0 }
        guard let regex = try? NSRegularExpression(pattern: vocabulary) else { return false }
        return regex.matches(in: block, range: NSRange(block.startIndex..., in: block)).contains { match in
            guard let range = Range(match.range, in: block) else { return false }
            return !cancelled.contains { block[range].hasPrefix($0) || block[range].hasPrefix("self.\($0)") }
        }
    }

    private static func cancelledWorkItemNames(in body: String) -> Set<String> {
        Set(CadenceSourceScan.captures("\\b(pending[A-Z]\\w*)\\s*\\??\\.\\s*cancel\\(", in: body).map(\.text))
    }

    private static func successReport(
        returning signature: String,
        persisted: String?,
        filledIn: String?,
        buildingItsOwnAnswer: Bool
    ) -> String {
        var spellings = [successReport]
        if let persisted { spellings.append(persisted) }
        if let filledIn { spellings.append(filledIn) }
        if CadenceSourceScan.matchCount("->\\s*Bool\\b", in: signature) > 0 {
            spellings.append("\\breturn true\\b")
        }
        if buildingItsOwnAnswer, CadenceSourceScan.matchCount(optionalAnswer, in: signature) > 0 {
            spellings.append(nonNilAnswer)
        }
        return spellings.joined(separator: "|")
    }

    /// A declaration that answers an **Optional** — T-636(b), and the sibling of `return true`.
    ///
    /// `Bool` and `Optional` are the only two return types in which a declaration can say *"it did
    /// not work"*, so they are the only two in which the **answer itself** is a report. T-627 put
    /// `return true` from a `-> Bool` in the vocabulary on exactly that argument, quoting
    /// `TasksPanelDropCoordinator`: *"a silent accept says the move happened"*. The other half of
    /// the same sentence was never written down, and it is the spelling this app actually uses for
    /// a card it redraws: `iOSMarkdownEditingSurface.toggleEmbeddedSubtask` ticks a subtask,
    /// swallows the commit, and hands back `MarkdownTaskEmbedRenderInfo.task(task)` — which is what
    /// repaints the embed inside the note. Returning render info the caller draws is the same claim
    /// as returning `true`.
    ///
    /// `$`-anchored so it reads the declaration's **own** return type rather than a closure
    /// parameter's: `onSelect: (AppTask) -> Tag?` in an argument list is a callee's answer, not
    /// this one's.
    private static let optionalAnswer = "->\\s*[\\w.]+\\?\\s*$"
    /// `return` of anything that is not `nil`. The failure answer of an Optional is spelled exactly
    /// one way, so everything else is the success answer.
    private static let nonNilAnswer = "\\breturn\\s+(?!nil\\b)\\S"

    /// Writing an `@AppStorage` property, spelled for the file that declares one — T-627 gap 4, and
    /// the sharpest member of the vocabulary.
    ///
    /// Every other spelling here reports success to a screen, and a screen is redrawn. A defaults
    /// write **outlives the rollback**: [[T-635]]'s Roll Over assigns
    /// `rolloverNoticeDismissedDate = CadenceTodayRolloverSupport.rollOver(…)`, which returns
    /// today's key whether or not the roll committed, and the banner then stays hidden for the rest
    /// of the day over a store that may hold nothing. It is also gap 4's "assigned *from* the
    /// swallowing call" case: the report is the assignment, and it sits textually **before** the
    /// call rather than after it — invisible to the tail reading this half used to do.
    ///
    /// `nil` when the file declares none, so the needle is never an empty alternation.
    private static func persistedReport(in source: String) -> String? {
        let names = CadenceSourceScan
            .captures("@AppStorage\\([^)]*\\)[^\n]*?\\bvar\\s+(\\w+)", in: source)
            .map(\.text)
        guard !names.isEmpty else { return nil }
        return viewState + "(" + Set(names).sorted().joined(separator: "|") + ")\\s*=(?!=)"
    }

    /// Writing a **collection `@Binding`** — [[T-664]], and the vocabulary's first spelling for a
    /// surface that reports by *filling in* rather than by closing.
    ///
    /// Every other member of `successReport` is a **dismissal**: the sheet closes, the flag goes
    /// `false`, the completion handler runs. [[T-497]] caught `TagPickerPopoverViews.saveEdits` and
    /// `.archive` on exactly that spelling — both end `editingTag = nil` — and could not see
    /// `.restore`, which stays open and reports by putting the chip in the field:
    /// `selectedTags.append(tag)`, then `query = ""`. The popover made the strongest claim it makes
    /// — *the tag is back and it is on this task* — over a store that had refused the un-archive.
    ///
    /// **Why a collection `@Binding` and not `.append(` generally.** `.append(` alone is one of the
    /// commonest lines in the app and says nothing about who is being told. A write **through a
    /// binding** is by definition a report *outward*: the value lands in state this view does not
    /// own, in a parent that is redrawn from it and has no idea a commit was refused. That is the
    /// same argument `viewState`'s anchor makes in the other direction — `context.isArchived =
    /// false` is a model field and is left alone, `isPresented = false` is the screen moving on.
    ///
    /// **Measured, and the scope is the measurement.** `@Binding var <name>: [...]` is **11**
    /// declarations across 8 files under `Cadence/`, of which three hold a swallowed commit at all;
    /// `@Binding var` unrestricted is far larger and mostly scalar draft fields a sheet edits as its
    /// ordinary job, which is a different thing from handing a parent a finished row. Widening past
    /// collections needs its own false-positive count before it is worth having.
    ///
    /// **What it still cannot see.** The other half of `restore`'s report — `query = ""`, the search
    /// field blanking — has no spelling here and is not one this scan should try to grow: `= ""` on
    /// view state is ordinary field clearing. This covers the append; it does not cover "the surface
    /// filled itself in" in general, which stays a rule a reader enforces. See [[T-996]].
    ///
    /// `nil` when the file declares none, so the needle is never an empty alternation.
    private static func filledInReport(in source: String) -> String? {
        let names = CadenceSourceScan
            .captures("@Binding\\s+var\\s+(\\w+)\\s*:\\s*\\[", in: source)
            .map(\.text)
        guard !names.isEmpty else { return nil }
        return viewState
            + "(" + Set(names).sorted().joined(separator: "|") + ")"
            + "(?:\\.(?:append|insert|remove\\w*|move\\w*)\\b|\\s*=(?!=))"
    }

    private static func nextSave(in body: [Character], from start: Int) -> (start: Int, end: Int)? {
        let text = String(body[start...])
        guard let regex = try? NSRegularExpression(pattern: swallowedSave),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        let length = text.distance(from: range.lowerBound, to: range.upperBound)
        return (start + offset, start + offset + length)
    }

    /// The index at which the block enclosing `start` opens, or 0 when `start` is at the
    /// declaration's own top level.
    private static func blockStart(in body: [Character], before start: Int) -> Int {
        var depth = 0
        var index = min(start, body.count) - 1
        while index >= 0 {
            if body[index] == "}" {
                depth += 1
            } else if body[index] == "{" {
                if depth == 0 { return index + 1 }
                depth -= 1
            }
            index -= 1
        }
        return 0
    }

    /// The index at which the block enclosing `start` closes.
    private static func blockEnd(in body: [Character], from start: Int) -> Int {
        var depth = 0
        var index = start
        while index < body.count {
            if body[index] == "{" {
                depth += 1
            } else if body[index] == "}" {
                if depth == 0 { return index }
                depth -= 1
            }
            index += 1
        }
        return body.count
    }

    /// Every `func name(…) { … }` and every **computed property** `var name: T { … }` in the
    /// source, innermost last.
    ///
    /// **`var body` was once the only property spelling, and that was gap 2 of T-627.** This app
    /// writes whole screens as `private var columnEditor: some View { … }`, and everything inside
    /// one of those was invisible to all four halves: measured over 563 files, 7 of 102
    /// swallowed-commit matches sat outside every parsed declaration, one of them a live Report
    /// offender (`KanbanSectionColumnView.columnEditor`). Matching `var name:` rather than the
    /// literal `body` costs nothing — a *stored* property has no `{` before the next declaration
    /// head, so the body finder below already skips it.
    ///
    /// The opening brace is the first `{` found at **paren depth zero**, which is what skips a
    /// default argument's closure — see
    /// `theDeclarationSplitSkipsBracesInsideADefaultArgument`.
    ///
    /// `signature` is everything from the `func`/`var` keyword up to that brace. Half 3 is the
    /// only reader of it, and it is the whole of that half's exemption mechanism: a declaration
    /// **handed** a `ModelContext` is one whose caller owns the unit of work.
    static func declarations(in source: String) -> [(name: String, signature: String, body: String)] {
        let characters = Array(source)
        guard let regex = try? NSRegularExpression(pattern: declarationHead) else { return [] }

        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var found: [(name: String, signature: String, body: String)] = []
        for (position, match) in matches.enumerated() {
            guard let whole = Range(match.range, in: source) else { continue }
            let isProperty = Range(match.range(at: 1), in: source) == nil
            guard let identifier = Range(match.range(at: 1), in: source)
                ?? Range(match.range(at: 2), in: source) else { continue }
            let name = String(source[identifier])
            let start = source.distance(from: source.startIndex, to: whole.lowerBound)
            // A declaration's body must open before the *next* declaration begins. Without that
            // bound, a protocol requirement or a `func` with no body swallows the next
            // declaration's braces and every offence inside it is filed under the wrong name.
            var limit = position + 1 < matches.count
                ? source.distance(from: source.startIndex, to: Range(matches[position + 1].range, in: source)?.lowerBound ?? source.endIndex)
                : characters.count
            // A **property** head must open its brace on its own line, which is what separates a
            // computed property from a stored one. `var verticalOffset: CGFloat = 0` otherwise
            // reaches forward for somebody else's `{` and files their offences under its name —
            // measured, and it produced a finding attributed to a `CGFloat`.
            if isProperty, let newline = characters[start..<limit].firstIndex(where: \.isNewline) {
                limit = newline
            }

            var parenDepth = 0
            var index = start
            var open: Int?
            while index < limit {
                let character = characters[index]
                if character == "(" {
                    parenDepth += 1
                } else if character == ")" {
                    parenDepth = max(0, parenDepth - 1)
                } else if character == "{", parenDepth == 0 {
                    open = index
                    break
                }
                index += 1
            }
            guard let open else { continue }
            found.append((
                name,
                String(characters[start..<open]),
                String(characters[(open + 1)..<blockEnd(in: characters, from: open + 1)])
            ))
        }
        return found
    }
}

private extension Array where Element == String {
    /// Nested declarations are reported by both the inner and the outer body, so the same name can
    /// arrive twice; the exemption check compares lists.
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
