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
/// 2. **Report.** Something in the same block *after* the save dismisses, or calls a completion
///    handler — `dismiss()`, `isPresented = false`, `onSave(…)`. Commit it through
///    `CadencePendingChangePersistence.commitEdit(in:undo:)` and throw; the caller catches and
///    names the failure where the user is already looking.
///
/// **Why those two and not "handle errors properly".** Both are decidable by reading one function,
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

    // MARK: - Exemptions rot

    /// Each exemption claims a specific file still breaks the rule in a specific named function for
    /// a specific reason. When that stops being true the entry can only ever hide a regression, so
    /// it fails rather than sits there. This is also what stops a file with one *allowed* offender
    /// from masking a second, new one added beside it.
    @Test func everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule() throws {
        for (rule, exemptions, offenders) in [
            ("existence", CadenceSaveCommitRule.existenceExemptions, CadenceSaveCommitRule.existenceOffenders),
            ("report", CadenceSaveCommitRule.reportExemptions, CadenceSaveCommitRule.reportOffenders),
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

    private static let swallowedSave = "try\\?\\s+[\\w.?]+\\.save\\(\\)"
    /// The vocabulary, and it is deliberately a closed list rather than a notion of "reports
    /// success". Four spellings, each of which means the screen moved on:
    ///
    /// - `dismiss()` — the sheet closes.
    /// - `isPresented = false` — the same thing said by a binding.
    /// - `onSave(…)` / `onDone(…)` / `onComplete(…)` / `onCommit(…)` — a completion handler, which
    ///   is a caller being told it worked.
    /// - `isEditing = false` / `editingThing = nil` — an **inline row editor** collapsing back to
    ///   its display row. Added after measuring: without it the rule missed three real sites in the
    ///   two tag editors, where the row closes showing a name the store may not hold. An inline
    ///   editor closing is a dismissal; it just does not own a sheet to say so with.
    ///
    /// Widening it is how the rule grows. A spelling that is not here is not covered, which is the
    /// honest limit of a text scan and the reason the rule is also written in `AGENTS.md` for a
    /// reader.
    private static let successReport = "\\bdismiss\\(\\)|isPresented\\s*=\\s*false|\\bon(Save|Done|Complete|Commit)\\(|\\bisEditing\\s*=\\s*false|\\bediting[A-Z]\\w*\\s*=\\s*nil"

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
    static func declarations(in source: String) -> [(name: String, body: String)] {
        let characters = Array(source)
        let pattern = "func\\s+([A-Za-z_]\\w*)\\s*[(<]|var\\s+(body)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var found: [(name: String, body: String)] = []
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
            found.append((name, String(characters[(open + 1)..<blockEnd(in: characters, from: open + 1)])))
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
