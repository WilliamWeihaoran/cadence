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
/// 1. **Existence.** The function that reaches the save also calls `modelContext.insert(…)` or
///    `modelContext.delete(…)`. Commit it through `CadencePendingChangePersistence.commitInsert`
///    or `commitDelete` and throw.
/// 2. **Report.** Something in the same block *after* the save dismisses, opens a sheet on what
///    was just written, or calls a completion handler — `dismiss()`, `isPresented = false`,
///    `presentedNote = …`, `onSave(…)`. Commit it through
///    `CadencePendingChangePersistence.commitEdit(in:undo:)` and throw; the caller catches and
///    names the failure where the user is already looking.
///    **And one frame down (T-566).** The same report over a *callee* that swallows — the button
///    calls `save()`, `save()` calls a shared mutation, the mutation holds the `try?`. Every frame
///    passes the reading above, and the sheet still closes over a store that refused. Same fix,
///    applied to whichever frame owns the commit.
/// 3. **Commit reach.** The function inserts and reaches **no commit at all** — added by T-503,
///    because halves 1 and 2 both key on the *presence* of a `try? …save()` and so a function that
///    never commits passed both. Twenty-one declarations were in that state; four of them also
///    reported success. The other seventeen are subtracted **by rule** rather than by name: a
///    declaration handed a `ModelContext` is one whose caller owns the unit of work. See
///    `commitReachOffenders`.
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

    /// Half 1: no swallowed save sits in a function that also inserts or deletes.
    @Test func noSwallowedSaveCommitsAnInsertOrADelete() throws {
        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.existenceInstrument(),
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

    /// Half 3: no declaration inserts and reaches no commit at all (T-503).
    ///
    /// The hole in the other two: both key on the *presence* of a `try? …save()`, so a function
    /// that inserts and commits nothing whatsoever passed both. The exemption list for this half is
    /// empty, because the ~17 helpers it must not fire on are subtracted by
    /// `commitReachOffenders`' signature rule rather than by name.
    @Test func noInsertIsLeftPendingWithNoCommitAnywhereInItsDeclaration() throws {
        let offenders = try saveCommitSweep(
            instrument: CadenceSaveCommitRule.commitReachInstrument(),
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
    private func index(over sources: [String: String]) -> CadenceSaveCommitRule.SwallowingIndex {
        CadenceSaveCommitRule.swallowingIndex(over: sources.keys.sorted()) { sources[$0] ?? "" }
    }

    private func swallowingIndexOverTheApp() throws -> CadenceSaveCommitRule.SwallowingIndex {
        try CadenceSaveCommitRule.swallowingIndex(over: try saveCommitSwiftFiles()) {
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
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: handed).isEmpty)
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: ambient) == ["create"])

        // `commit:` is a commit being handed *in*, which is the opposite claim from a context being
        // handed in, so it must not exempt anything on its own.
        let handedACommitOnly = """
        private func create(commit: (ModelContext) throws -> Void = { try $0.save() }) {
            let subtask = Subtask(title: title)
            modelContext.insert(subtask)
            dismiss()
        }
        """
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: handedACommitOnly) == ["create"])
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
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: reaching).isEmpty)

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
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: notReaching) == ["createTask"])

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
        #expect(CadenceSaveCommitRule.commitReachOffenders(in: acrossFiles) == ["createTask"])
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
        for (rule, exemptions, offenders) in [
            ("existence", CadenceSaveCommitRule.existenceExemptions, CadenceSaveCommitRule.existenceOffenders),
            ("report", CadenceSaveCommitRule.reportExemptions, CadenceSaveCommitRule.reportOffenders),
            ("commit reach", CadenceSaveCommitRule.commitReachExemptions, CadenceSaveCommitRule.commitReachOffenders),
            (
                "report one frame down",
                CadenceSaveCommitRule.indirectReportExemptions,
                { CadenceSaveCommitRule.indirectReportOffenders(in: $0, swallowing: swallowing) }
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
        // Launch-time maintenance with no user watching and nothing to report to. Both are
        // idempotent and re-run every launch, so a refused commit costs one launch's worth of
        // seeding and repairs itself; and `saveChanges:`/`save:` already let a caller that *does*
        // have a unit of work take the commit over. Filed as the follow-up's lowest tier.
        "Cadence/Services/TagSupport.swift": ["seedDefaultTags", "deduplicateTags"],
        // UI-test scaffolding. It runs only under `CadenceUITestSupport`'s launch argument, and
        // there is no user to tell.
        "Cadence/Services/CadenceUITestSupport.swift": ["seedDataIfNeeded"],
        // T-497 emptied the rest of this list: `CadenceNoteFolderSupport.createNote`,
        // `SettingsTagsSection.createTag`, `iOSSettingsTagsSection.createTag` and
        // `iOSCalendarEventEditSheet.openEventNote` all commit through `commitInsert` now, and are
        // pinned by `CadenceTagAndNoteCommitSurfaceTests`. What is left is the two genuine
        // non-defects above.
    ]

    /// The two live instances of half 2, both of them "flush an in-place edit, then close".
    ///
    /// They are held rather than fixed because each needs an answer to a question the rule does not
    /// settle: what an *undo* means for an editor whose field is bound live to the model and is
    /// still on screen. Restoring it under the user's cursor is not obviously better than leaving
    /// it. See the T-322 follow-up ticket.
    ///
    /// The three inline tag editors that used to sit below them — `SettingsTagsSection.saveEdits`
    /// and `TagPickerPopoverViews.saveEdits`/`archive` — are fixed (T-497) and pinned by
    /// `CadenceTagAndNoteCommitSurfaceTests`. They were the easier half of the same sentence: an
    /// inline row editor collapsing is a dismissal, but its fields are drafts held in `@State`
    /// rather than bindings onto the model, so restoring the model does not fight the caret.
    static let reportExemptions: [String: [String]] = [
        // "Flush an in-place edit, then close." Both are live instances of half 2.
        "Cadence/iOS/iOSSearchSupportViews.swift": ["body"],
        "Cadence/iOS/iOSTaskDetailSheet.swift": ["finishEditingAndDismiss"],
        // `Cadence/iOS/iOSListSupportViews.swift: ["addLink"]` was the third entry — [[T-507]],
        // held here rather than fixed to keep two agents out of one file. It is fixed now:
        // `addLink` catches the insert and leaves the form open with an `actionError`, the way
        // macOS's `LinksView.addLink` already did. The entry is deleted in the same change,
        // because `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` fails on a
        // stale one — which is exactly how it was meant to leave.
    ]

    static func existenceInstrument() throws -> CadenceScanInstrument {
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
            by: { !existenceOffenders(in: $0).isEmpty }
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

    /// The exemption list for half 3, and it is **empty** — deliberately, and that is the claim.
    ///
    /// Half 1 and half 2 each carry a handful of sites held back on a product decision. Half 3
    /// carries none, because the ~17 declarations it must not fire on are subtracted by the rule
    /// below rather than by name. An entry appearing here would mean the mechanical exemption has
    /// stopped describing the population, which is worth noticing rather than papering over.
    static let commitReachExemptions: [String: [String]] = [:]

    static func commitReachInstrument() throws -> CadenceScanInstrument {
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
            by: { !commitReachOffenders(in: $0).isEmpty }
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
    static func commitReachOffenders(in source: String) -> [String] {
        let all = declarations(in: source)
        let committing = committingDeclarationNames(in: all)
        return all
            .filter { declaration in
                CadenceSourceScan.matchCount(insertCall, in: declaration.body) > 0
                    && CadenceSourceScan.matchCount(handedAModelContext, in: declaration.signature) == 0
                    && !committing.contains(declaration.name)
            }
            .map(\.name)
            .uniqued()
    }

    /// Every declaration in the file that reaches a commit, directly or through a same-file call.
    ///
    /// A fixed point rather than one hop: `CadenceWriteService.createTask` reaches `context.save()`
    /// through *two* forwarding spellings of `saveNotifyAndAudit`, and stopping at one hop would
    /// have needed a by-name exemption for a function that obeys the rule.
    private static func committingDeclarationNames(
        in declarations: [(name: String, signature: String, body: String)]
    ) -> Set<String> {
        var committing = Set(
            declarations
                .filter { CadenceSourceScan.matchCount(commitCall, in: $0.body) > 0 }
                .map(\.name)
        )
        var changed = true
        while changed {
            changed = false
            for declaration in declarations where !committing.contains(declaration.name) {
                let callsACommitter = committing.contains { callee in
                    callee != "body"
                        && callee != declaration.name
                        && CadenceSourceScan.matchCount("\\b\(callee)\\s*\\(", in: declaration.body) > 0
                }
                if callsACommitter {
                    committing.insert(declaration.name)
                    changed = true
                }
            }
        }
        return committing
    }

    private static let insertCall = "(modelContext|context|ctx)\\??\\.insert\\("
    /// "My caller owns the unit of work", spelled as a signature. `:\s*ModelContext\b` and not
    /// merely `ModelContext`, so that `commit: (ModelContext) throws -> Void` — which is a
    /// *commit* being handed in, the opposite claim — does not exempt anything.
    private static let handedAModelContext = ":\\s*ModelContext\\b"
    private static let commitCall = "\\.save\\(\\)|CadencePendingChangePersistence\\.commit\\w*"

    /// Half 1: declarations holding both a swallowed save and an insert or a delete.
    static func existenceOffenders(in source: String) -> [String] {
        let existence = "(modelContext|context|ctx)\\??\\.(insert|delete)\\("
        return declarations(in: source)
            .filter {
                CadenceSourceScan.matchCount(swallowedSave, in: $0.body) > 0
                    && CadenceSourceScan.matchCount(existence, in: $0.body) > 0
            }
            .map(\.name)
            .uniqued()
    }

    /// Half 2: declarations where something in the save's **own block**, after it, reports success.
    ///
    /// The save's own block rather than the whole declaration, because the whole declaration is
    /// wrong in the direction that matters: a `var body` holding an autosave in one closure and a
    /// `dismiss()` in an unrelated one is not this defect, and a rule that called it one would be
    /// silenced by an exemption instead of obeyed.
    static func reportOffenders(in source: String) -> [String] {
        var names: [String] = []
        for declaration in declarations(in: source) {
            let body = Array(declaration.body)
            var index = 0
            while index < body.count {
                guard let save = nextSave(in: body, from: index) else { break }
                let tail = String(body[save.end..<blockEnd(in: body, from: save.end)])
                if CadenceSourceScan.matchCount(successReport, in: tail) > 0 {
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
        for declaration in parsed where !direct.contains(declaration.name) {
            for call in declaration.calls
            where call.callee != declaration.name
                && reachesASwallow(call.qualifier, call.callee, reached: reached, index: index) {
                let tail = String(
                    declaration.body[call.end..<blockEnd(in: declaration.body, from: call.end)]
                )
                if CadenceSourceScan.matchCount(successReport, in: tail) > 0 {
                    names.append(declaration.name)
                    break
                }
            }
        }
        return names.uniqued()
    }

    /// The two sites this half finds that no other half can see. Both are live; neither is T-566,
    /// which is fixed. They re-scope [[T-497]]'s "2 sites left" to four.
    static let indirectReportExemptions: [String: [String]] = [
        // "Flush an in-place edit, then close" — the third instance of the family already held in
        // `reportExemptions`, and blocked on the same undecided question: what an undo means for a
        // field the user is still looking at and still has focus in. `persistNote()` swallows its
        // commit and `body` dismisses after it.
        "Cadence/iOS/iOSMarkdownReferenceSupport.swift": ["body"],
        // A popover picking a task's list: `moveToContainer` swallows, `select` closes the popover
        // with `isPresented = false`. Not blocked on anything — the popover holds no draft, so the
        // fix is the ordinary `commitEdit(in:undo:)` one — just out of T-566's scope.
        "Cadence/macOS/Views/KanbanCardMetaSupportViews.swift": ["select"],
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
                    $0.callee != declaration.name
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
        let throwsItsAnswer: Bool
        let swallowsDirectly: Bool
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
                throwsItsAnswer: declaration.signature.contains("throws"),
                swallowsDirectly: CadenceSourceScan.matchCount(swallowedSave, in: declaration.body) > 0,
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
    /// Widening it is how the rule grows. A spelling that is not here is not covered, which is the
    /// honest limit of a text scan and the reason the rule is also written in `AGENTS.md` for a
    /// reader.
    private static let successReport = "\\bdismiss\\(\\)|\\bis[A-Z]\\w*\\s*=\\s*false|\\bon(Save|Done|Complete|Commit)\\(|\\bediting[A-Z]\\w*\\s*=\\s*nil|\\bpresented[A-Z]\\w*\\s*=(?!=)"

    private static func nextSave(in body: [Character], from start: Int) -> (start: Int, end: Int)? {
        let text = String(body[start...])
        guard let regex = try? NSRegularExpression(pattern: swallowedSave),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        let length = text.distance(from: range.lowerBound, to: range.upperBound)
        return (start + offset, start + offset + length)
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

    /// Every `func name(…) { … }` and `var body { … }` in the source, innermost last.
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
        let pattern = "func\\s+([A-Za-z_]\\w*)\\s*[(<]|var\\s+(body)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var found: [(name: String, signature: String, body: String)] = []
        for (position, match) in matches.enumerated() {
            guard let whole = Range(match.range, in: source) else { continue }
            var name = "body"
            if let identifier = Range(match.range(at: 1), in: source) {
                name = String(source[identifier])
            }
            let start = source.distance(from: source.startIndex, to: whole.lowerBound)
            // A declaration's body must open before the *next* declaration begins. Without that
            // bound, a protocol requirement or a `func` with no body swallows the next
            // declaration's braces and every offence inside it is filed under the wrong name.
            let limit = position + 1 < matches.count
                ? source.distance(from: source.startIndex, to: Range(matches[position + 1].range, in: source)?.lowerBound ?? source.endIndex)
                : characters.count

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
