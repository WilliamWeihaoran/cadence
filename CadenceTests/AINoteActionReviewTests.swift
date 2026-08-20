import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-185: AI note actions on iOS, and the review gate every draft has to pass.
///
/// **Two kinds of test, and the second kind is the point.** Pinning `validation(for:)` proves the
/// rules are right; it proves nothing about anybody enforcing them. T-161 is the standing example —
/// a committed fix was revertible with the whole suite green because the tests pinned a helper while
/// nothing observed the call site. So the value tests below are followed by source-text assertions
/// that read the real files and fail the moment iOS starts writing drafts without going through the
/// review.
///
/// Source text is the only tool available for the iOS half: `Cadence/iOS/` is entirely inside
/// `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference. The
/// helpers follow `CadenceSharedTaskRowJobsTests` — exact per-file counts rather than "contains",
/// comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan cannot make
/// the zero expectations pass silently.
@MainActor
struct AINoteActionReviewTests {

    // MARK: - validation(for:)

    private func draft(
        title: String = "Ship it",
        priority: String = "none",
        dueDate: String = "",
        scheduledDate: String = "",
        scheduledStartMin: Int? = nil,
        estimatedMinutes: Int? = nil
    ) -> AITaskDraft {
        AITaskDraft(
            title: title,
            priority: priority,
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            scheduledStartMin: scheduledStartMin,
            estimatedMinutes: estimatedMinutes
        )
    }

    @Test func aWellFormedDraftValidates() {
        let validation = AIActionService.validation(for: draft(
            priority: "high",
            dueDate: "2026-08-25",
            scheduledDate: "2026-08-20",
            scheduledStartMin: 540,
            estimatedMinutes: 45
        ))

        #expect(validation.isValid)
        #expect(validation.errors.isEmpty)
    }

    /// A title is the one field a task cannot be created without, and whitespace is not a title.
    @Test func aTitleOfNothingButSpacesIsNoTitle() {
        #expect(!AIActionService.validation(for: draft(title: "   \n ")).isValid)
        #expect(!AIActionService.validation(for: draft(title: "")).isValid)
    }

    /// The four priorities, and the fact that the check is case- and whitespace-insensitive: a model
    /// answering "High " is answering correctly.
    @Test func onlyTheFourPrioritiesValidate() {
        for raw in ["none", "low", "medium", "high", "High ", " MEDIUM"] {
            #expect(AIActionService.validation(for: draft(priority: raw)).isValid, "\(raw) should validate")
        }
        for raw in ["urgent", "P1", "", "critical"] {
            #expect(!AIActionService.validation(for: draft(priority: raw)).isValid, "\(raw) should not validate")
        }
    }

    /// **The one that matters most.** A date the model invented in another format is refused rather
    /// than coerced, because the coercion is silent and the result is a task due on the wrong day.
    @Test func onlyIsoDatesValidate() {
        #expect(AIActionService.validation(for: draft(dueDate: "2026-08-20")).isValid)
        #expect(AIActionService.validation(for: draft(scheduledDate: "2026-08-20")).isValid)

        for raw in ["next Tuesday", "08/20/2026", "20 Aug 2026", "tomorrow", "2026-13-45", "2026-08-20T09:00:00Z"] {
            #expect(!AIActionService.validation(for: draft(dueDate: raw)).isValid, "\(raw) should not validate")
        }

        // `DateFormatters.ymd` is lenient about a single-digit month, so this *does* validate. It is
        // pinned rather than left implicit because the leniency is what made `normalizedDate`'s
        // canonicalisation necessary — see `normalizedDateCanonicalisesALenientlyParsedDay`.
        #expect(AIActionService.validation(for: draft(dueDate: "2026-8-20")).isValid)
    }

    /// **The defect this file found.** `normalizedDate` validated by parsing and then returned the
    /// string as typed, so `"2026-8-20"` reached `TaskCreationDraft.dueDateKey` verbatim. Every date
    /// comparison in Cadence is a string comparison against a canonical `yyyy-MM-dd`, so that task
    /// was due on a day nothing in the app could see: not "due today", not a group heading, not a
    /// sort key. Re-formatting through the day it parsed to is the fix.
    @Test func normalizedDateCanonicalisesALenientlyParsedDay() {
        #expect(AIActionService.normalizedDate("2026-8-20") == "2026-08-20")
        #expect(AIActionService.normalizedDate("2026-08-9") == "2026-08-09")
        #expect(AIActionService.normalizedDate(" 2026-1-2 ") == "2026-01-02")
    }

    /// An empty date is not an invalid date — it is a field the model declined to fill in, which the
    /// schema explicitly allows.
    @Test func anAbsentDateIsNotAnInvalidDate() {
        #expect(AIActionService.validation(for: draft(dueDate: "", scheduledDate: "   ")).isValid)
    }

    @Test func aScheduledTimeMustBeAMinuteOfTheDayAndMustHaveADay() {
        #expect(AIActionService.validation(for: draft(scheduledDate: "2026-08-20", scheduledStartMin: 0)).isValid)
        #expect(AIActionService.validation(for: draft(scheduledDate: "2026-08-20", scheduledStartMin: 1439)).isValid)
        #expect(!AIActionService.validation(for: draft(scheduledDate: "2026-08-20", scheduledStartMin: 1440)).isValid)
        #expect(!AIActionService.validation(for: draft(scheduledDate: "2026-08-20", scheduledStartMin: -1)).isValid)
        // A time with no day is the schema's one cross-field rule: `scheduledStartMin` is minutes
        // from midnight *of some day*, and there is no day here.
        #expect(!AIActionService.validation(for: draft(scheduledStartMin: 540)).isValid)
    }

    @Test func anEstimateMustBeBetweenOneMinuteAndOneDay() {
        #expect(AIActionService.validation(for: draft(estimatedMinutes: 1)).isValid)
        #expect(AIActionService.validation(for: draft(estimatedMinutes: 1440)).isValid)
        #expect(!AIActionService.validation(for: draft(estimatedMinutes: 0)).isValid)
        #expect(!AIActionService.validation(for: draft(estimatedMinutes: 1441)).isValid)
        #expect(!AIActionService.validation(for: draft(estimatedMinutes: -30)).isValid)
    }

    @Test func everyBrokenFieldIsReportedRatherThanTheFirst() {
        let validation = AIActionService.validation(for: draft(
            title: "",
            priority: "urgent",
            dueDate: "next Tuesday",
            estimatedMinutes: 0
        ))

        #expect(validation.errors.count == 4)
    }

    // MARK: - normalizedDate

    /// The last line of defence, and pinned directly rather than inferred: whatever
    /// `applyTaskDrafts` hands `TaskCreationDraft` for a date is what the task will be due on.
    @Test func normalizedDateKeepsOnlyRealIsoDays() {
        #expect(AIActionService.normalizedDate("2026-08-20") == "2026-08-20")
        #expect(AIActionService.normalizedDate("  2026-08-20  ") == "2026-08-20")
        #expect(AIActionService.normalizedDate("") == "")
        #expect(AIActionService.normalizedDate("   ") == "")
        #expect(AIActionService.normalizedDate("next Tuesday") == "")
        #expect(AIActionService.normalizedDate("08/20/2026") == "")
        #expect(AIActionService.normalizedDate("2026-08-20T09:00:00Z") == "")
    }

    // MARK: - The summary append

    @Test func aSummaryIsFiledUnderItsOwnHeadingWithOneBlankLineAboveIt() {
        #expect(
            CadenceAINoteSummary.appending("Recap.", to: "# Monday\n\nNotes.")
                == "# Monday\n\nNotes.\n\n## AI Summary\n\nRecap."
        )
    }

    /// No separator when there is nothing to separate from, and nothing written at all when the
    /// summary is empty — an empty "## AI Summary" section is worse than no section.
    @Test func anEmptySummaryOrAnEmptyNoteChangesTheSeparatorOrTheAnswer() {
        #expect(CadenceAINoteSummary.appending("Recap.", to: "") == "## AI Summary\n\nRecap.")
        #expect(CadenceAINoteSummary.appending("Recap.", to: "   \n ") == "   \n ## AI Summary\n\nRecap.")
        #expect(CadenceAINoteSummary.appending("", to: "Notes.") == nil)
        #expect(CadenceAINoteSummary.appending("  \n ", to: "Notes.") == nil)
    }

    // MARK: - The review gate

    @Test func everyDraftStartsApprovedAndCanBeRejectedIndividually() {
        let first = draft(title: "One")
        let second = draft(title: "Two")
        var review = CadenceAIDraftReview(drafts: [first, second])

        #expect(review.selectedIDs == Set([first.id, second.id]))
        #expect(review.canCreate)

        review.setSelected(false, for: second.id)

        #expect(review.selectedDrafts.map(\.title) == ["One"])
        #expect(!review.isSelected(second))
        #expect(review.canCreate)
    }

    @Test func rejectingEveryDraftClosesTheGate() {
        let only = draft()
        var review = CadenceAIDraftReview(drafts: [only])
        review.setSelected(false, for: only.id)

        #expect(!review.canCreate)
        #expect(review.refusalMessage == "Select at least one draft to create it.")
    }

    @Test func anEmptyResponseClosesTheGateAndSaysSoDifferently() {
        let review = CadenceAIDraftReview(drafts: [])

        #expect(!review.canCreate)
        #expect(review.refusalMessage == "There is nothing to create.")
    }

    /// **The gate closes on validity, not only on selection.** `applyTaskDrafts` already threw for
    /// an invalid draft — after the button was pressed. Refusing up front is what lets the sheet
    /// mark the card while it is still editable.
    @Test func oneApprovedBrokenDraftClosesTheGateForAllOfThem() {
        let good = draft(title: "Fine")
        let bad = draft(title: "Broken", priority: "urgent")
        var review = CadenceAIDraftReview(drafts: [good, bad])

        #expect(!review.canCreate)
        #expect(!review.blockingErrors.isEmpty)

        // Rejecting the broken one reopens it. A draft the user has already declined is not a
        // problem to be fixed.
        review.setSelected(false, for: bad.id)

        #expect(review.canCreate)
        #expect(review.blockingErrors.isEmpty)
        #expect(review.refusalMessage == nil)
    }

    @Test func aRejectedBrokenDraftDoesNotContributeErrors() {
        let bad = draft(title: "", priority: "urgent", dueDate: "someday")
        var review = CadenceAIDraftReview(drafts: [bad, draft(title: "Fine")])
        review.setSelected(false, for: bad.id)

        #expect(review.blockingErrors.isEmpty)
        // The card still knows it is broken — it is drawn in red; it just is not blocking anything.
        #expect(!review.validation(for: bad).isValid)
    }

    // MARK: - The gate is load-bearing, not advisory

    private func emptyStore() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func taskCount(in modelContext: ModelContext) throws -> Int {
        try modelContext.fetch(FetchDescriptor<AppTask>()).count
    }

    /// **The most valuable assertion in this file.** `applyApproved` is the only write path either
    /// platform's review sheet uses, and it refuses on its own account — so losing the `disabled(…)`
    /// on a Create button cannot write anything.
    @Test func nothingIsWrittenWhileAnApprovedDraftIsInvalid() throws {
        let modelContext = try emptyStore()
        let review = CadenceAIDraftReview(drafts: [draft(title: "Broken", dueDate: "next Tuesday")])

        #expect(throws: AIActionError.self) {
            try review.applyApproved(areas: [], projects: [], modelContext: modelContext)
        }
        #expect(try taskCount(in: modelContext) == 0)
    }

    @Test func nothingIsWrittenWhenEveryDraftHasBeenRejected() throws {
        let modelContext = try emptyStore()
        let only = draft(title: "Perfectly fine")
        var review = CadenceAIDraftReview(drafts: [only])
        review.setSelected(false, for: only.id)

        #expect(throws: AIActionError.self) {
            try review.applyApproved(areas: [], projects: [], modelContext: modelContext)
        }
        #expect(try taskCount(in: modelContext) == 0)
    }

    @Test func nothingIsWrittenForAnEmptyResponse() throws {
        let modelContext = try emptyStore()
        let review = CadenceAIDraftReview(drafts: [])

        #expect(throws: AIActionError.self) {
            try review.applyApproved(areas: [], projects: [], modelContext: modelContext)
        }
        #expect(try taskCount(in: modelContext) == 0)
    }

    /// The other side of the gate: once the review passes, exactly the approved drafts are written,
    /// with their fields intact and into the container the sheet was opened from.
    @Test func exactlyTheApprovedDraftsAreWrittenOnceTheReviewPasses() throws {
        let modelContext = try emptyStore()
        let context = Context(name: "Work")
        let project = Project(name: "Launch", context: context)
        project.sectionNames = [TaskSectionDefaults.defaultName, "Build"]
        modelContext.insert(context)
        modelContext.insert(project)
        try modelContext.save()

        let approved = AITaskDraft(
            title: "Write the review sheet",
            notes: "From the note",
            priority: "high",
            dueDate: "2026-09-01",
            scheduledDate: "2026-08-31",
            scheduledStartMin: 600,
            estimatedMinutes: 60,
            sectionName: "Build",
            subtaskTitles: ["Gate", "Card"]
        )
        let rejected = draft(title: "Not this one")
        var review = CadenceAIDraftReview(drafts: [approved, rejected])
        review.setSelected(false, for: rejected.id)

        let created = try review.applyApproved(
            project: project,
            areas: [],
            projects: [project],
            modelContext: modelContext
        )

        #expect(created.count == 1)
        #expect(try taskCount(in: modelContext) == 1)
        #expect(created.first?.title == "Write the review sheet")
        #expect(created.first?.priority == .high)
        #expect(created.first?.dueDate == "2026-09-01")
        #expect(created.first?.scheduledDate == "2026-08-31")
        #expect(created.first?.scheduledStartMin == 600)
        #expect(created.first?.estimatedMinutes == 60)
        #expect(created.first?.sectionName == "Build")
        #expect(created.first?.project?.id == project.id)
    }

    /// A date the model got wrong on an *edited* draft: the review passes once the user has fixed it,
    /// and the fixed value is what lands.
    @Test func correctingADraftInTheReviewIsWhatGetsWritten() throws {
        let modelContext = try emptyStore()
        var review = CadenceAIDraftReview(drafts: [draft(title: "Fix me", dueDate: "next Tuesday")])

        #expect(!review.canCreate)
        review.drafts[0].dueDate = "2026-08-25"
        #expect(review.canCreate)

        let created = try review.applyApproved(areas: [], projects: [], modelContext: modelContext)

        #expect(created.count == 1)
        #expect(created.first?.dueDate == "2026-08-25")
    }

    // MARK: - iOS reaches the service, and reaches it through the review

    private static let iosActionsView = "Cadence/iOS/iOSAINoteActionsViews.swift"
    private static let macReviewSheet = "Cadence/macOS/Views/NoteActionReviewSheets.swift"
    private static let sharedSupport = "Cadence/Services/AI/AINoteActionSupport.swift"

    /// The guard is gone, and gone rather than narrowed. A `#if os(macOS)` anywhere in this file
    /// would put iOS back where T-185 found it.
    @Test func theActionServiceIsNoLongerFencedOffFromiOS() throws {
        let code = try strippingComments(sourceFile("Cadence/Services/AI/AIActionService.swift"))

        #expect(!code.contains("#if os(macOS)"))
        #expect(!code.contains("#if os(iOS)"))
        #expect(code.contains("enum AIActionService"))
        // It also did not move: `Cadence/Services/AI/` is already the cross-platform home, so
        // there is no tombstone under an old name and no `.stringsdata` collision to design around.
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot().appendingPathComponent("Cadence/macOS/Services/AIActionService.swift").path
        ))
    }

    /// **The call-site test.** `AIActionService.applyTaskDrafts` is called from exactly one place in
    /// the whole app — inside `CadenceAIDraftReview.applyApproved`, behind the `canCreate` guard.
    /// Neither review sheet may call it directly, and a new surface cannot either.
    @Test func theWriteIsReachableOnlyThroughTheReviewGate() throws {
        var callers: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            let count = code.components(separatedBy: "AIActionService.applyTaskDrafts(").count - 1
            if count > 0 { callers[path] = count }
        }

        #expect(callers == [Self.sharedSupport: 1], "unexpected direct callers: \(callers)")

        let support = try strippingComments(sourceFile(Self.sharedSupport))
        #expect(support.contains("guard canCreate else {"))
    }

    /// Both review sheets write through `applyApproved`, exactly once each. Exact counts, not
    /// "contains": a version of this asserting only that each file mentioned it somewhere would stay
    /// green with one of the two call sites reverted.
    @Test func bothPlatformsReviewSheetsWriteThroughTheSameGate() throws {
        try expectOccurrences(of: "applyApproved(", at: [
            Self.iosActionsView: 1,
            Self.macReviewSheet: 1,
            Self.sharedSupport: 1,
        ])
    }

    /// The iOS entry point exists, reaches both provider calls, and puts each answer in a review
    /// sheet rather than in the store.
    @Test func theiOSEntryPointRunsBothActionsAndReviewsBothAnswers() throws {
        let code = try strippingComments(sourceFile(Self.iosActionsView))

        #expect(code.contains("struct iOSNoteAIActionsMenu: View"))
        #expect(code.contains("struct iOSAITaskDraftReviewSheet: View"))
        #expect(code.contains("struct iOSAISummaryReviewSheet: View"))
        // Both actions, from the shared enum rather than from two literals.
        #expect(code.contains("CadenceNoteAIAction.allCases"))
        try expectOccurrences(of: "provider.summarizeNote(", at: [Self.iosActionsView: 1])
        try expectOccurrences(of: "provider.extractTasks(", at: [Self.iosActionsView: 1])
        // The response goes into `payload`, and `payload` is only ever read by the sheets.
        try expectOccurrences(of: "payload = .summary(", at: [Self.iosActionsView: 1])
        try expectOccurrences(of: "payload = .taskDrafts(", at: [Self.iosActionsView: 1])
        #expect(code.contains(".sheet(item: $payload)"))
    }

    /// Off by default means **absent** by default: with no key the control does not render, so the
    /// note editor is byte-for-byte what it was before T-185 for a user who has not opted in.
    @Test func theiOSControlIsAbsentWithoutAnAPIKey() throws {
        let code = try strippingComments(sourceFile(Self.iosActionsView))

        try expectOccurrences(of: "if aiSettingsManager.hasAPIKey {", at: [Self.iosActionsView: 1])
        // And nothing reaches the provider outside the tapped action — no `.onAppear` or `.task`
        // that could fire on opening a note.
        #expect(!code.contains(".task {"))
        #expect(!code.contains(".onAppear"))
    }

    /// The entry point is wired into all three iOS note editors: the two-column header, the
    /// full-screen cover, and the event-note sheet. Exact counts, so removing one is a failure.
    @Test func everyiOSNoteEditorCarriesTheEntryPoint() throws {
        try expectOccurrences(of: "iOSNoteAIActionsMenu(", at: [
            // Once in the notes header (two-column), once in `iOSNoteEditorCover`'s toolbar.
            "Cadence/iOS/iOSNotesView.swift": 2,
            "Cadence/iOS/iOSEventNoteEditorSheet.swift": 1,
            // Never anywhere else — the control is not a page-level affordance.
            "Cadence/iOS/iOSTasksTabView.swift": 0,
            "Cadence/iOS/iOSSettingsView.swift": 0,
        ])
    }

    /// The hard safety rule, as a test. Nothing in the AI folder or the iOS view logs, and nothing
    /// there caches a request: the key lives in the Keychain and the prompt lives in memory.
    @Test func nothingInTheAIPathLogsOrPersistsARequest() throws {
        var aiFiles = try swiftFiles(under: "Cadence/Services/AI")
        aiFiles.append(Self.iosActionsView)
        aiFiles.append(Self.macReviewSheet)
        #expect(aiFiles.count == 6)

        for path in aiFiles {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("print("), "\(path) logs")
            #expect(!code.contains("NSLog("), "\(path) logs")
            #expect(!code.contains("debugPrint("), "\(path) logs")
        }

        // `AISettingsManager` is the one file allowed to touch `UserDefaults`, and only for the
        // model ID. The key is `KeychainCredentialStore`'s, and the request body is nobody's.
        for path in aiFiles where !path.hasSuffix("AISettingsManager.swift") {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("UserDefaults"), "\(path) reaches for UserDefaults")
            #expect(!code.contains("@AppStorage"), "\(path) reaches for AppStorage")
        }

        let settings = try strippingComments(sourceFile("Cadence/Services/AI/AISettingsManager.swift"))
        #expect(settings.components(separatedBy: "defaults.set(").count - 1 == 1)
        // The one `defaults.set` writes the model, never the key.
        #expect(settings.contains("defaults.set(model.trimmingCharacters"))

        // And the provider never puts the key anywhere but the Authorization header.
        let provider = try strippingComments(sourceFile("Cadence/Services/AI/AIProvider.swift"))
        #expect(provider.components(separatedBy: "apiKey").count - 1 == 5)
        #expect(provider.contains("\"Bearer \\(apiKey)\", forHTTPHeaderField: \"Authorization\""))
    }

    /// No fork: the drafts review is one sheet per platform over one shared decision type, not two
    /// copies of the decision. `CadenceNoteAIAction` is where the vocabulary lives.
    @Test func theReviewDecisionIsSharedRatherThanForked() throws {
        let support = try strippingComments(sourceFile(Self.sharedSupport))

        #expect(support.contains("struct CadenceAIDraftReview"))
        #expect(support.contains("enum CadenceNoteAIAction"))
        #expect(support.contains("enum CadenceAINoteSummary"))
        // The support file is outside every platform guard, which is the only reason this test can
        // see it at all.
        #expect(!support.contains("#if os("))
        // Neither sheet reads the validation rules for itself: both take them from the review, so a
        // card's red border and its Create button can never be two reads of one rule.
        try expectOccurrences(of: "review.validation(for: draft)", at: [
            Self.iosActionsView: 1,
            Self.macReviewSheet: 1,
        ])
        for path in [Self.iosActionsView, Self.macReviewSheet] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("AIActionService.validation("), "\(path) re-derives validation")
        }
    }

    // MARK: - The scan itself

    /// The zero expectations above are worth nothing if the scan reads nothing, and a scan that
    /// silently returns an empty string passes every one of them. This is the test that stops them
    /// going vacuous — the `/tmp` against `/private/tmp` path mismatch on an isolated build tree is
    /// the exact failure mode it guards.
    @Test func theSourceScanActuallyReachesTheFilesItAssertsAbout() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains(Self.iosActionsView))
        #expect(files.contains(Self.macReviewSheet))
        #expect(files.contains(Self.sharedSupport))
        #expect(files.contains("Cadence/Services/AI/AIActionService.swift"))
        #expect(files.contains("Cadence/Services/AI/AIProvider.swift"))
        #expect(files.contains("Cadence/Services/AI/AISettingsManager.swift"))
        #expect(files.contains("Cadence/iOS/iOSNotesView.swift"))
        #expect(files.contains("Cadence/iOS/iOSEventNoteEditorSheet.swift"))
        #expect(files.contains("Cadence/iOS/iOSTasksTabView.swift"))
        #expect(files.contains("Cadence/iOS/iOSSettingsView.swift"))

        // And it is reading code, not an empty string: a positive assertion through the same reader.
        #expect(try strippingComments(sourceFile(Self.iosActionsView)).contains("struct iOSNoteAIActionsMenu: View"))
        #expect(try strippingComments(sourceFile(Self.macReviewSheet)).contains("struct AITaskDraftReviewSheet: View"))
        #expect(try strippingComments(sourceFile("Cadence/iOS/iOSNotesView.swift")).contains("struct iOSNotesView: View"))

        // The comment stripper is doing its job too: this file's own name for the guard it removed
        // appears in prose in `AIActionService.swift`, and `theActionServiceIsNoLongerFencedOffFromiOS`
        // would fail if prose counted as code.
        let raw = try sourceFile("Cadence/Services/AI/AIActionService.swift")
        #expect(raw.contains("#if os(macOS)"))
    }
}

// MARK: - Source-reading helpers

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

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
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

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
