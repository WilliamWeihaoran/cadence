import Foundation
import Testing
@testable import Cadence

/// **T-609.** A title fallback spelled inline instead of read from the shared helper.
///
/// The shape is `task.title.isEmpty ? "Untitled" : task.title`, and it is not a style problem.
/// `"   ".isEmpty` is **false**, so a title of spaces passes the guard, the fallback is skipped and
/// the surface draws three spaces — a blank line where a placeholder belongs.
/// `CadenceTitleNormalization.display(_:fallback:)` (reached as `TaskTitleSupport.displayTitle`
/// from the app) trims *before* it tests, which is why the four calendar sites [[T-569]] fixed and
/// the ~28 this ticket swept can share one call.
///
/// The near-miss spelling is its own half of the family:
/// `title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title` tests the
/// *trimmed* value and then returns the **untrimmed** one, so a whitespace-only title is caught but
/// `"  Standup  "` is stored and drawn with its padding. `display` returns the trimmed string, which
/// is the reason its doc comment exists.
///
/// **The copy was deliberately not touched.** Every site keeps the exact fallback string it already
/// showed, passed explicitly — "Untitled", "Untitled List", "Untitled subtask", "Missing Task",
/// "New Task", "Event Note", "Goal", "Linked event note". T-569 made that call for the compact
/// wording and this sweep holds it: what changed is the trim and nothing else. Re-wording any of
/// them is a copy decision, not a de-duplication, and belongs in its own ticket.
///
/// **"Goal" left this list under T-688.** It was `iOSTaskRowGoalChip`'s literal, and it disagreed
/// with the picker beside it — the copy freeze this paragraph describes was T-609's own scope, not
/// a permanent rule, and T-688 is the ticket that lifted it for that one pair. See
/// `theTaskRowsGoalChipAndItsPickerAgreeOnTheBlankGoalFallback` below.
///
/// **What these instruments deliberately do not see, measured rather than assumed.** Both needles
/// require the fallback to be a **string literal**, because that is the shape T-569 measured and
/// T-609 was scoped to. Allowing a *constant* there — `task.title.isEmpty ?
/// CadenceTitleNormalization.defaultGoalTitle : task.title` — finds **27 more sites**, and a
/// mutation is how that came out: M2 rewrote the widget row's fallback as the constant rather than
/// the literal, the behavioural test killed it and this sweep did not.
///
/// They are filed, not swept, and the reason is that the 27 are **not uniform**. Most are ordinary
/// placeholder fallbacks that T-505/T-513 already de-literalised and that still need the trim. But
/// `LinksView.swift:102` falls back to the URL, `iOSListSupportViews.swift:797` to `link.url`, and
/// `MarkdownNoteSupport.swift:85` to a *template's* title — those fall back to another real value,
/// where "should the branch trim?" is a decision per site rather than a mechanical substitution.
/// Sweeping them behind one regex is the mistake this ticket was told to avoid for copy, one axis
/// over. The same argument applies to the identical shape on a `name` rather than a `title`,
/// 7 more sites. Both lists are in the ticket.
struct CadenceEmptyTitleFallbackSweepTests {

    // MARK: - The premise, stated once

    /// Why the ternary is a defect rather than a long way of writing the helper.
    @Test func theInlineTernaryCannotSeeATitleOfSpacesAndTheSharedHelperCan() {
        let spaces = "   "

        // The inline spelling: the guard is false, so the fallback never runs.
        #expect(spaces.isEmpty == false)
        #expect((spaces.isEmpty ? "Untitled" : spaces) == spaces)

        // The shared spelling: blank is blank, and the result comes back trimmed.
        #expect(TaskTitleSupport.displayTitle(spaces, fallback: TaskTitleSupport.defaultCompactDisplayTitle) == "Untitled")
        #expect(TaskTitleSupport.displayTitle("  Buy milk  ") == "Buy milk")
    }

    // MARK: - The behavioural half

    /// The widget row is the one swept site reachable from a test, and it is the *trimmed-test,
    /// untrimmed-return* spelling: `"   "` was already handled, `"  Buy milk  "` was not.
    ///
    /// It also proves the target-boundary half of the ticket. `TaskTitleSupport` lives in
    /// `Cadence/Shared/`, which the widget extension's explicit Sources phase does not compile, so
    /// this site reads `CadenceTitleNormalization` in `Cadence/Models/` instead — the one tree all
    /// three targets build.
    @MainActor @Test func theTodayWidgetRowDrawsATrimmedTitleAndNeverABlankOne() {
        let todayKey = "2026-05-11"

        func task(_ title: String) -> AppTask {
            let task = AppTask(title: title)
            task.dueDate = todayKey
            return task
        }

        let padded = task("  Buy milk  ")
        let blank = task("   ")
        blank.order = 1
        padded.order = 0

        let snapshot = CadenceTodayWidgetSupport.snapshot(
            from: [padded, blank],
            todayKey: todayKey,
            limit: 3
        )

        #expect(snapshot.tasks.count == 2, "non-vacuity: both rows reached the snapshot")
        #expect(snapshot.tasks.map(\.title) == ["Buy milk", CadenceTitleNormalization.defaultCompactTitle])
    }

    /// The meeting note's `# heading` is the other reachable site, and the same spelling: an event
    /// titled with padding wrote that padding into markdown, where a trailing space is not neutral.
    @MainActor @Test func theEventNoteHeadingTrimsTheEventTitleItNames() {
        #expect(CadenceEventNoteSupport.initialContent(eventTitle: "  Standup  ", nativeNotes: nil) == "# Standup\n\n")
        #expect(CadenceEventNoteSupport.initialContent(eventTitle: "   ", nativeNotes: nil) == "# Event Note\n\n")
    }

    /// `EventNote`'s own initializer already trimmed before it tested — the correct hand-spelling,
    /// kept as the control so the sweep below reads as a de-duplication rather than a behaviour
    /// change everywhere.
    @MainActor @Test func theEventNoteModelStillResolvesABlankTitleToItsLabel() {
        #expect(EventNote(calendarEventID: "e", eventTitle: "   ").title == "Event Note")
        #expect(EventNote(calendarEventID: "e", eventTitle: "  Standup  ").title == "Standup")
    }

    // MARK: - T-688: the goal chip and its own picker agree

    /// **T-688.** `iOSTaskRowGoalChip` and `iOSTaskRowGoalPickerContent` both name the same field
    /// on the same task — its `goal` — and disagreed on what a blank one is called: the chip's
    /// literal "Goal" (kept verbatim by T-609's "change no copy" rule) against the picker's
    /// `CadenceTitleNormalization.defaultMilestoneTitle` ("Untitled Milestone"). The picker's own
    /// `@Query` reads every `Goal` in the store, top-level directions included, so "Milestone" was
    /// wrong for most of the rows it names — `CadenceTitleNormalization.defaultGoalTitle`
    /// ("Untitled Goal") is the fallback that actually describes the model both views draw, and
    /// T-609's copy freeze is lifted for these two so they can converge on it.
    @Test func theTaskRowsGoalChipAndItsPickerAgreeOnTheBlankGoalFallback() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift")
        )
        #expect(code.contains("struct iOSTaskRowGoalChip: View"), "non-vacuity: file unread")
        #expect(code.contains("struct iOSTaskRowGoalPickerContent: View"), "non-vacuity: the picker moved")

        // The pre-T-688 spellings.
        #expect(code.contains("fallback: \"Goal\"") == false, "the chip still spells its own literal")
        #expect(
            CadenceSourceScan.matchCount("fallback: CadenceTitleNormalization\\.defaultMilestoneTitle", in: code) == 0,
            "the picker still disagrees with the chip beside it"
        )

        // The converged spelling, once per site, through the call each already used.
        #expect(
            CadenceSourceScan.matchCount(
                "TaskTitleSupport\\.displayTitle\\(goal\\.title, fallback: CadenceTitleNormalization\\.defaultGoalTitle\\)",
                in: code
            ) == 1,
            "the chip does not read the converged fallback"
        )
        #expect(
            CadenceSourceScan.matchCount(
                "CadenceTitleNormalization\\.display\\(goal\\.title, fallback: CadenceTitleNormalization\\.defaultGoalTitle\\)",
                in: code
            ) == 1,
            "the picker row does not read the converged fallback"
        )
        #expect(CadenceTitleNormalization.defaultGoalTitle == "Untitled Goal")
    }

    // MARK: - The sweep

    /// **No file in the product spells the fallback inline.** This is the guard that stops a 26th
    /// site appearing; the behavioural tests above cover only the two sites a test can call.
    ///
    /// `strippingComments`, not `codeOnly`: `codeOnly` blanks string literals as well, so the
    /// `? "…" :` in the needle could never match and the sweep would be permanently green.
    /// Three files discuss this exact ternary in prose — `DeleteConfirmationManager`,
    /// `iOSTodaySchedulePanel` and `CadenceEventTitleSupport` — so the stripper is load-bearing
    /// rather than decorative, and `theSweepReadsCodeAndNotTheProseAboutIt` pins that.
    @Test func noSurfaceHandSpellsAnEmptyTitleFallback() throws {
        let instrument = try Self.inlineTitleFallbackInstrument()
        var paths: [String] = []
        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            paths += try CadenceSourceScan.swiftFiles(under: root)
        }

        // `sweep` takes one witness; the ticket's claim is about **three** targets, and two of them
        // are exactly the ones the `Cadence` scheme would not have told us about. So each root gets
        // its own witness — a walk that quietly stopped covering `CadenceMCPServer` would otherwise
        // read as "no hits there", which is the answer this sweep is supposed to have earned.
        #expect(paths.contains("CadenceWidgets/TodayTasksWidget.swift"))
        #expect(paths.contains("CadenceMCPServer/CadenceMCPToolRouter.swift"))

        // **The reader, pinned here and not only in `theSweepReadsCodeAndNotTheProseAboutIt`.**
        // Until T-686 this asserted an *exact* expected set, and that shape made the reader
        // self-proving: blinding it emptied the hits and the equality went red for free. The last
        // site is fixed, so the assertion is `isEmpty` now — which a blinded reader satisfies
        // without reading anything, exactly the trap
        // `noSurfaceTestsATrimmedTitleAndThenReturnsTheUntrimmedOne` records below. So the reader
        // is asserted separately, before the result is believed.
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try read("Cadence/Models/ModelEnums.swift").contains("\"Untitled Task\""),
                "the sweep's reader blanks string literals, so its needle can never match")

        let hits = try instrument.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift",
            read: read
        )

        #expect(hits.isEmpty, "these surfaces hand-spell an empty-title fallback: \(hits)")
    }

    /// **T-687.** The same untrimmed ternary with a **constant** between the `?` and the `:`.
    ///
    /// T-609's needle required a string *literal* there, because that was the shape T-569 measured.
    /// Allowing a constant found **27 more sites** — mostly ones [[T-505]]/[[T-513]] had already
    /// de-literalised, so they read the right placeholder and *still* drew a blank line for a title
    /// of spaces. A surviving mutation is what found this: M2 rewrote the widget row's fallback as
    /// the constant rather than the literal, the behavioural test killed it and T-609's sweep did
    /// not, which is the argument for mutating a scan you are only reading through.
    ///
    /// **The copy is untouched, as T-609 decided.** Every one of the 25 sites this closed keeps the
    /// exact fallback expression it already had; what changed is the trim, and nothing else.
    ///
    /// The two survivors are the exemption below, and they are the reason this was not a blind
    /// sweep: they fall back to **another real value**, not to a placeholder.
    @Test func noSurfaceHandSpellsAnEmptyTitleFallbackAgainstAConstant() throws {
        let instrument = try Self.constantTitleFallbackInstrument()
        var paths: [String] = []
        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            paths += try CadenceSourceScan.swiftFiles(under: root)
        }
        #expect(paths.contains("CadenceWidgets/TodayTasksWidget.swift"))
        #expect(paths.contains("CadenceMCPServer/CadenceMCPToolRouter.swift"))

        // The reader, before the result is believed: `codeOnly` blanks string literals and the
        // needle would never match, which is a permanently green sweep over nothing.
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try read("Cadence/Models/ModelEnums.swift").contains("\"Untitled Task\""),
                "the sweep's reader blanks string literals, so its needle can never match")

        let hits = try instrument.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/iOS/iOSFeatureDetailViews.swift",
            read: read
        )

        #expect(
            hits == Self.constantFallbackExemptions,
            "these surfaces hand-spell an empty-title fallback against a constant: \(hits)"
        )
    }

    /// The exemption, exact and named line by line rather than counted.
    ///
    /// `MarkdownNoteSupport.resolved(_:with:)` merges a note-template **override** into its
    /// template: `override.title.isEmpty ? template.title : override.title` falls back to the
    /// template's own value, not to a placeholder, and the two are stored strings rather than a
    /// drawn label. Trimming there would silently rewrite what a user saved, which is a decision
    /// about override semantics rather than the mechanical substitution the other 25 were — so it
    /// is written down here and owned by [[T-785]] instead of swept.
    ///
    /// Stated as the exact pair, so a third ternary appearing in that file is a failure rather than
    /// something the file-level exemption quietly absorbs.
    @Test func theOverrideMergeExemptionIsStillExactlyTheTwoLinesItWasMeasuredAs() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownNoteSupport.swift")
        )
        #expect(source.contains("static func resolved(_ template: NoteTemplate, with override: NoteTemplateOverride)"),
                "non-vacuity: the exempted function is gone, so the exemption may be stale")
        #expect(
            CadenceSourceScan.matchCount(
                "override.title.isEmpty \\? template.title : override.title",
                in: source
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(
                "override.subtitle.isEmpty \\? template.subtitle : override.subtitle",
                in: source
            ) == 1
        )
        let pattern = "[A-Za-z0-9_.]*[Tt]itle\\.isEmpty \\? [A-Za-z_][A-Za-z0-9_.]* : "
        #expect(
            CadenceSourceScan.matchCount(pattern, in: source) == 2,
            "MarkdownNoteSupport has grown a third constant-fallback ternary, which the file-level exemption would hide"
        )
    }

    /// The *near-miss* spelling, swept separately because it is a different regex and a different
    /// symptom: the trim happens, and then the untrimmed original is returned anyway.
    @Test func noSurfaceTestsATrimmedTitleAndThenReturnsTheUntrimmedOne() throws {
        let instrument = try Self.trimmedTestUntrimmedReturnInstrument()
        var paths: [String] = []
        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            paths += try CadenceSourceScan.swiftFiles(under: root)
        }

        #expect(paths.contains("CadenceWidgets/TodayTasksWidget.swift"))
        #expect(paths.contains("CadenceMCPServer/CadenceMCPToolRouter.swift"))

        // **The reader, pinned — and this one is load-bearing in a way the sweep above is not.**
        // That sweep asserts an exact expected set, so blinding its reader empties the hits and it
        // goes red. This one asserts `isEmpty`, which a blinded reader satisfies **for free**: swap
        // `strippingComments` for `codeOnly` and every string literal becomes spaces, the needle can
        // never match, and the test passes forever over nothing. Mutation M8 did exactly that and
        // this test survived it, which is how the assertion below got written. So: prove the reader
        // still hands back string literals before believing an empty result.
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try read("Cadence/Models/ModelEnums.swift").contains("\"Untitled Task\""),
                "the sweep's reader blanks string literals, so its needle can never match")

        let hits = try instrument.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/Services/CadenceTodayWidgetSupport.swift",
            read: read
        )

        #expect(hits.isEmpty, "these files test a trimmed title and return the untrimmed one: \(hits)")
    }

    /// The sweep's reader, pinned. A detector this narrow is worthless if the text it runs over is
    /// the wrong text, and both failure modes are silent: `codeOnly` would blank the literal out of
    /// the needle, and a raw read would count the three files that only *describe* the ternary.
    @Test func theSweepReadsCodeAndNotTheProseAboutIt() throws {
        let instrument = try Self.inlineTitleFallbackInstrument()
        let prose = try CadenceSourceScan.sourceFile("Cadence/macOS/Services/DeleteConfirmationManager.swift")

        #expect(prose.contains("task.title.isEmpty ? \"Untitled\" : task.title"),
                "non-vacuity: the paragraph that names the ternary is gone")
        #expect(instrument.fires(on: prose), "non-vacuity: the detector cannot see its own shape in raw text")
        #expect(instrument.fires(on: CadenceSourceScan.strippingComments(prose)) == false,
                "the sweep counts a comment about the defect as the defect")
        #expect(instrument.fires(on: CadenceSourceScan.codeOnly(prose)) == false,
                "codeOnly blanks string literals, so it can never answer this needle — do not sweep with it")
    }

    // MARK: - T-539: the prompt is not the fallback

    /// **T-539.** `"Untitled task"` as a `TextField` *prompt* and `"Untitled Task"` as a *fallback*
    /// are two pieces of copy doing two jobs, and the T-609 sweep above must not merge them.
    ///
    /// [[T-513]] left the prompt alone deliberately, and said why: capitalising it would make it the
    /// only prompt in the app phrased as a placeholder *value*, and folding it into
    /// `defaultTaskTitle` would freeze that drift under a change that looks like cleanup. The fix
    /// was never "capitalise" — it is "say what the field is", which is what every other title
    /// prompt already does.
    @Test func theTaskInspectorTitleFieldPromptsWithANounPhrase() throws {
        let inspector = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        )
        #expect(inspector.contains("struct iOSTaskEditorTitleCard"), "non-vacuity: wrong file read")
        #expect(inspector.contains("TextField(\"Task title\", text: $task.title"))
        #expect(inspector.contains("Untitled task") == false,
                "the prompt is back to a placeholder value")
    }

    /// Every title prompt in the app names the field. Stated over the tree rather than over the one
    /// line T-539 changed, because "the only prompt phrased as a value" is a claim about the set.
    @Test func everyTitlePromptInTheAppIsANounPhrase() throws {
        let pattern = try NSRegularExpression(pattern: "TextField\\(\"([^\"]*)\"[^\n]*text: \\$[A-Za-z0-9_.]*[Tt]itle")
        let read = CadenceSourceScan.strippedSourceReader()
        var prompts: Set<String> = []
        var filesRead = 0

        for root in ["Cadence"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                let source = try read(path)
                filesRead += 1
                let range = NSRange(source.startIndex..., in: source)
                for match in pattern.matches(in: source, range: range) {
                    guard let captured = Range(match.range(at: 1), in: source) else { continue }
                    prompts.insert(String(source[captured]))
                }
            }
        }

        #expect(filesRead >= 300, "the prompt harvest read \(filesRead) files")
        #expect(prompts.contains("Task title"), "non-vacuity: the harvest found no title prompt at all")
        let placeholderValues = prompts.filter { $0.lowercased().hasPrefix("untitled") }
        #expect(placeholderValues.isEmpty, "these title prompts are phrased as a value: \(placeholderValues.sorted())")
    }

    // MARK: - T-550: an argument that repeats its own default

    /// **T-550**, [[T-374]] family. `GoalLinkPickerButton.emptyText` already defaults to
    /// `"No matching goals"`; two call sites passed exactly that. Behaviour-neutral to delete, and
    /// worth pinning because a redundant argument is indistinguishable from a deliberate override
    /// the next time somebody changes the default.
    @Test func noGoalPickerCallSiteRepeatsTheEmptyTextDefault() throws {
        let picker = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GoalPickerViews.swift")
        )
        #expect(picker.contains("struct GoalLinkPickerButton"), "non-vacuity: wrong file read")
        #expect(picker.contains("var emptyText: String = \"No matching goals\""),
                "the default moved, so the call sites below may no longer be redundant")

        let read = CadenceSourceScan.strippedSourceReader()
        var callers: [String] = []
        var filesRead = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") where path != "Cadence/macOS/Views/GoalPickerViews.swift" {
            filesRead += 1
            if try read(path).contains("emptyText: \"No matching goals\"") { callers.append(path) }
        }

        #expect(filesRead >= 300, "the caller harvest read \(filesRead) files")
        #expect(callers.isEmpty, "these call sites repeat GoalLinkPickerButton's own default: \(callers)")

        // Non-vacuity for the harvest itself: the two files T-550 named are still read and still
        // pass the picker something, so an empty result means "no redundant argument" rather than
        // "no file matched".
        for path in ["Cadence/macOS/Sheets/CreateGoalSheet.swift", "Cadence/macOS/Views/HabitsFormSupportViews.swift"] {
            #expect(try read(path).contains("GoalLinkPickerButton("), "non-vacuity: \(path) no longer uses the picker")
        }
    }

    // MARK: - Instruments

    /// `X.isEmpty ? "…" : X`, where `X` is a title. The back-reference is what makes it decidable:
    /// the guarded expression and the else-branch have to be the same text, so
    /// `query.isEmpty ? "Tags" : "#\(slug)"` — a *choice* between two strings — is not a hit.
    static func inlineTitleFallbackInstrument() throws -> CadenceScanInstrument {
        let pattern = try NSRegularExpression(
            pattern: "([A-Za-z0-9_.]*[Tt]itle)\\.isEmpty \\? \"[^\"]*\" : \\1(?![A-Za-z0-9_])"
        )
        return try CadenceScanInstrument(
            "inline empty-title fallback",
            fires: "Text(task.title.isEmpty ? \"Untitled\" : task.title)",
            andNotOn: "Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))",
            by: { source in
                pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
            }
        )
    }

    /// The 27 sites' shape: `X.isEmpty ? SomeConstant : X`, where `X` is a title. The same
    /// back-reference as T-609's instrument, and the same reason for it — the guarded expression
    /// and the else-branch must be the same text, so a *choice* between two values is not a hit.
    ///
    /// The negative witness is the T-609 spelling with a literal, which the other instrument owns:
    /// a detector matching both would report T-609's sweep as this one's and make either result
    /// unattributable.
    static func constantTitleFallbackInstrument() throws -> CadenceScanInstrument {
        let pattern = try NSRegularExpression(
            pattern: "([A-Za-z0-9_.]*[Tt]itle)\\.isEmpty \\? ([A-Za-z_][A-Za-z0-9_.]*) : \\1(?![A-Za-z0-9_])"
        )
        return try CadenceScanInstrument(
            "constant empty-title fallback",
            fires: "Text(goal.title.isEmpty ? CadenceTitleNormalization.defaultGoalTitle : goal.title)",
            andNotOn: "Text(task.title.isEmpty ? \"Untitled\" : task.title)",
            by: { source in
                pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
            }
        )
    }

    /// The only files allowed to hold the shape above, and why is in
    /// `theOverrideMergeExemptionIsStillExactlyTheTwoLinesItWasMeasuredAs`.
    static let constantFallbackExemptions = ["Cadence/Services/MarkdownNoteSupport.swift"]

    /// `X.trimmingCharacters(…).isEmpty ? "…" : X` — the trim happens and is then thrown away.
    /// The negative witness is the *correct* hand-spelling, which trims into a local and tests
    /// that: near enough that a detector matching on `trimmingCharacters` alone would fail here.
    static func trimmedTestUntrimmedReturnInstrument() throws -> CadenceScanInstrument {
        let pattern = try NSRegularExpression(
            pattern: "([A-Za-z0-9_.]*[Tt]itle)\\.trimmingCharacters\\(in: \\.whitespacesAndNewlines\\)\\.isEmpty \\? \"[^\"]*\" : \\1(?![A-Za-z0-9_])"
        )
        return try CadenceScanInstrument(
            "trimmed test, untrimmed return",
            fires: "title: task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? \"Untitled\" : task.title,",
            andNotOn: """
            let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = trimmed.isEmpty ? "Untitled" : trimmed
            """,
            by: { source in
                pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
            }
        )
    }
}
