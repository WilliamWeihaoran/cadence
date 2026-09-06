import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The half [[T-274]] left for [[T-1082]]: a user can now *start* an import.
///
/// `CadenceArchiveImportSurfaceTests` proves the engine restores the graph. Nothing there says a
/// person can reach it, that they see what it would do before it happens, or that the words on the
/// screen describe the operation the engine actually performs. Those are this suite's three
/// subjects, and the third is the one with teeth: an import **merges and never deletes**, so a
/// control labelled *Restore* would promise a rollback the service cannot do.
///
/// **`.preservesTheStoredLaunchReports` is load-bearing, not copied decoration.**
/// `CadenceArchiveImportFlow.confirm()` calls `CadenceArchiveImportService.importArchive`, which
/// runs `NoteMigrationService` over the imported rows and writes `noteMigration.lastReport.v1` to
/// `UserDefaults.standard`. The trait puts the app's real report back. `StoredLaunchReportSuiteRule`
/// still does not ask for it here, and [[T-1083]]'s fix does not change that: the reach it follows
/// is spelled `Type.name(`, and this suite calls `flow.confirm()` on an **instance**, so there is no
/// type for the index to resolve — the same limit `CadenceSaveCommitRule.SwallowingIndex` documents
/// for the same reason. So this trait is here because the author checked, not because a test
/// demanded it.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceArchiveImportEntryPointTests {

    // MARK: - Nothing is written until the preview is confirmed

    /// The whole point of a preview. Choosing a file reads, decodes and fully validates it — and
    /// the destination store is still empty on the other side of that.
    @Test func choosingAnArchiveShowsAPlanAndLeavesTheStoreEmpty() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(Context(name: "Work"))
        source.insert(AppTask(title: "Buy milk"))
        try source.save()

        let url = try Self.writeArchive(from: source)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try CadenceTestStore.container()
        let flow = CadenceArchiveImportFlow()
        flow.preview(.success(url), in: destination)

        let plan = try #require(flow.plan)
        #expect(plan.insertCountsByEntityName["AppTask"] == 1)
        #expect(plan.insertCountsByEntityName["Context"] == 1)
        #expect(plan.changesAnything)
        #expect(flow.isPreviewing)
        let untouched = try ModelContext(destination).fetchCount(FetchDescriptor<AppTask>())
        #expect(untouched == 0)
    }

    /// …and confirming writes, exactly once, and says so on the card.
    @Test func confirmingThePreviewWritesTheArchiveAndReportsIt() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(Context(name: "Work"))
        source.insert(AppTask(title: "Buy milk"))
        try source.save()

        let url = try Self.writeArchive(from: source)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try CadenceTestStore.container()
        let flow = CadenceArchiveImportFlow()
        flow.preview(.success(url), in: destination)
        flow.confirm()

        let written = ModelContext(destination)
        #expect(try written.fetchCount(FetchDescriptor<AppTask>()) == 1)
        #expect(try written.fetchCount(FetchDescriptor<Context>()) == 1)
        let message = try #require(flow.statusMessage)
        #expect(message.hasPrefix("Imported "))
        // The sheet is gone and the archive with it: a confirmed import must not stay armed.
        #expect(flow.plan == nil)
        #expect(!flow.isPreviewing)
    }

    /// Dismissing the sheet drops the file. Otherwise a `confirm()` arriving from anywhere — a
    /// keyboard shortcut, a second tap in flight — would write an archive the user cancelled.
    @Test func cancellingThePreviewDisarmsTheImportEntirely() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(AppTask(title: "Buy milk"))
        try source.save()

        let url = try Self.writeArchive(from: source)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try CadenceTestStore.container()
        let flow = CadenceArchiveImportFlow()
        flow.preview(.success(url), in: destination)
        #expect(flow.isPreviewing)

        flow.cancel()
        flow.confirm()

        #expect(flow.plan == nil)
        #expect(flow.statusMessage == nil)
        let afterCancel = try ModelContext(destination).fetchCount(FetchDescriptor<AppTask>())
        #expect(afterCancel == 0)
    }

    /// A file that is not an archive is refused at the card, with nothing pending behind it. The
    /// decode happens in `plan`, before the preview exists, so there is no sheet to dismiss.
    @Test func aFileThatIsNotAnArchiveLeavesNoPreviewAndNothingArmed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-import-not-an-archive-\(UUID().uuidString).json")
        try Data("{\"hello\":\"world\"}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try CadenceTestStore.container()
        let flow = CadenceArchiveImportFlow()
        flow.preview(.success(url), in: destination)

        #expect(flow.plan == nil)
        #expect(!flow.isPreviewing)
        #expect(flow.statusMessage?.hasPrefix("Import failed: ") == true)

        flow.confirm()
        let afterRefusal = try ModelContext(destination).fetchCount(FetchDescriptor<AppTask>())
        #expect(afterRefusal == 0)
    }

    /// A cancelled or failed file picker reports on the card and arms nothing.
    @Test func aFailedFilePickerIsReportedWithoutArmingAnImport() throws {
        let flow = CadenceArchiveImportFlow()
        let container = try CadenceTestStore.container()
        flow.preview(.failure(CocoaError(.fileReadNoSuchFile)), in: container)

        #expect(flow.plan == nil)
        #expect(flow.statusMessage?.hasPrefix("Import failed: ") == true)
    }

    // MARK: - The mode choice moves the counts, not just the label

    /// Re-importing a file the store already has is a no-op under the default mode and a rewrite
    /// under the other. `changesAnything` flips between them, so the preview must recount rather
    /// than relabel — a screen that kept the merge counts under the overwrite heading would tell
    /// the user nothing would change while the Import button was about to rewrite 4,000 rows.
    @Test func switchingModesWhileThePreviewIsUpRecountsThePlan() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(Context(name: "Work"))
        source.insert(AppTask(title: "Buy milk"))
        try source.save()

        let url = try Self.writeArchive(from: source)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try CadenceTestStore.container()
        let flow = CadenceArchiveImportFlow()
        flow.preview(.success(url), in: destination)
        flow.confirm()

        // Second pass over the same file, into the store that now holds it.
        flow.preview(.success(url), in: destination)
        let merged = try #require(flow.plan)
        #expect(merged.mode == .mergeKeepingExistingRows)
        #expect(merged.totalInsertCount == 0)
        #expect(merged.totalMatchedCount > 0)
        #expect(!merged.changesAnything)

        flow.mode = .restoreOverwritingExistingRows
        let overwriting = try #require(flow.plan)
        #expect(overwriting.mode == .restoreOverwritingExistingRows)
        #expect(overwriting.totalMatchedCount == merged.totalMatchedCount)
        #expect(overwriting.changesAnything)
    }

    // MARK: - The words

    /// The rule this ticket exists to keep: the operation merges, so nothing on either surface may
    /// call it a restore. A user reaching for "restore" expects the store to end up equal to the
    /// archive, and it will not.
    @Test func nothingTheImportSurfaceSaysCallsThisARestore() {
        let plan = Self.plan(mode: .restoreOverwritingExistingRows, inserts: ["AppTask": 3], matches: ["AppTask": 2])
        let outcome = CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: 3,
            overwrittenRecordCount: 2,
            skippedRecordCount: 0,
            notesFoldedFromLegacyRows: 1
        )

        var shown = [
            CadenceArchiveImportPresentation.title,
            CadenceArchiveImportPresentation.description,
            CadenceArchiveImportPresentation.buttonTitle,
            CadenceArchiveImportPresentation.previewTitle,
            CadenceArchiveImportPresentation.confirmButtonTitle,
            CadenceArchiveImportPresentation.cancelButtonTitle,
            CadenceArchiveImportPresentation.neverDeletesNote,
            CadenceArchiveImportPresentation.modeQuestion,
            CadenceArchiveImportPresentation.planSummary(plan),
            CadenceArchiveImportPresentation.successMessage(outcome),
            CadenceArchiveImportPresentation.failureMessage("disk full"),
        ]
        for mode in CadenceArchiveImportMode.allCases {
            shown.append(CadenceArchiveImportPresentation.modeTitle(mode))
            shown.append(CadenceArchiveImportPresentation.modeExplanation(mode))
        }

        for row in CadenceArchiveImportPresentation.modeRows() {
            shown.append(row.title)
            if let subtitle = row.subtitle { shown.append(subtitle) }
        }

        #expect(shown.count >= 19, "the sweep only looked at \(shown.count) strings")
        for sentence in shown {
            #expect(
                !sentence.lowercased().contains("restore"),
                "an import merges and never deletes, so this must not say restore: \(sentence)"
            )
        }
        // Non-vacuity: the same predicate does fire on a string that breaks the rule, so the
        // emptiness above is the copy passing rather than the check being dead.
        #expect("Restore From Archive".lowercased().contains("restore"))
    }

    /// The correction itself, in the place a user reads before choosing. It has to do three things:
    /// say nothing is deleted, say what that costs (this is not a rollback), and name the two-step
    /// route that *is* one.
    @Test func theImportNoteCorrectsTheRollbackExpectationAndNamesTheRouteThatWorks() {
        let note = CadenceArchiveImportPresentation.neverDeletesNote
        #expect(note.contains("never deletes"))
        #expect(note.contains("cannot roll Cadence back"))
        #expect(note.contains("delete Cadence's data first"))
        #expect(note.contains("import into the empty store"))
    }

    /// The chooser puts **both** consequences on screen at once, which the segmented control it
    /// replaced could not: that control had room for two titles and nothing else, so
    /// `modeExplanation` could only ever describe the mode already chosen and the cost of the other
    /// one was invisible until you had taken it. Each row now carries its own explanation.
    @Test func theModeChooserShowsWhatEachChoiceCostsBeforeItIsMade() {
        let rows = CadenceArchiveImportPresentation.modeRows()
        #expect(rows.count == CadenceArchiveImportMode.allCases.count)
        #expect(rows.map(\.value) == CadenceArchiveImportMode.allCases)

        for row in rows {
            #expect(row.title == CadenceArchiveImportPresentation.modeTitle(row.value))
            #expect(row.subtitle == CadenceArchiveImportPresentation.modeExplanation(row.value))
        }
        // Distinct rows, not two spellings of one: identity is derived from `value`, so a chooser
        // whose two options collapsed would draw one row.
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    /// And it is not a `Picker`. `SettingsSharedVocabularyTests` sweeps macOS Settings for
    /// `.pickerStyle(` — a segmented control on the Mac is AppKit's bezel and AppKit's accent — but
    /// that sweep's corpus is `Cadence/macOS/Views/*Settings*` only, so the phone's identical copy
    /// of this sheet was outside it. This is the half that watches iOS.
    @Test func neitherArchiveImportSurfaceDrawsANativePicker() throws {
        for path in [
            "Cadence/macOS/Views/SettingsArchiveImportCard.swift",
            "Cadence/iOS/iOSArchiveImportSettingsSection.swift",
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(!code.contains(".pickerStyle("), "\(path) draws a native Picker again")
            #expect(code.contains("ChoicePopoverList("), "non-vacuity: \(path) lost the shared chooser")
        }
    }

    /// Each mode says what happens to a row that already exists, in the words the counts use.
    @Test func eachImportModeSaysWhatHappensToARowTheStoreAlreadyHas() {
        #expect(CadenceArchiveImportPresentation.modeTitle(.mergeKeepingExistingRows) == "Add what's missing")
        #expect(CadenceArchiveImportPresentation.modeTitle(.restoreOverwritingExistingRows) == "Overwrite what matches")
        #expect(
            CadenceArchiveImportPresentation.modeExplanation(.mergeKeepingExistingRows)
                .contains("left exactly as they are")
        )
        #expect(
            CadenceArchiveImportPresentation.modeExplanation(.restoreOverwritingExistingRows)
                .contains("are lost")
        )
        // Both modes have to admit the thing they share, or the choice reads as delete-vs-keep.
        #expect(
            CadenceArchiveImportPresentation.modeExplanation(.restoreOverwritingExistingRows)
                .contains("Records the archive never had are still kept")
        )
    }

    /// The summary names the mode's consequence, not one total. Same two counts, two sentences.
    @Test func thePlanSummaryReadsDifferentlyUnderEachImportMode() {
        let merging = Self.plan(mode: .mergeKeepingExistingRows, inserts: ["AppTask": 4], matches: ["AppTask": 9])
        let overwriting = Self.plan(mode: .restoreOverwritingExistingRows, inserts: ["AppTask": 4], matches: ["AppTask": 9])

        let mergeSentence = CadenceArchiveImportPresentation.planSummary(merging)
        let overwriteSentence = CadenceArchiveImportPresentation.planSummary(overwriting)

        #expect(mergeSentence.contains("4 records would be added"))
        #expect(mergeSentence.contains("9 records already here would be left untouched"))
        #expect(overwriteSentence.contains("4 records would be added"))
        #expect(overwriteSentence.contains("replaced by this archive's copy"))
        #expect(mergeSentence != overwriteSentence)
    }

    /// A second import of the same file changes nothing under the default mode, and the preview has
    /// to say *that* rather than "0 records would be added", which reads as a failure.
    @Test func aPlanThatWouldChangeNothingSaysSoRatherThanCountingZero() {
        let repeated = Self.plan(mode: .mergeKeepingExistingRows, inserts: [:], matches: ["AppTask": 12])
        #expect(CadenceArchiveImportPresentation.planSummary(repeated).contains("would change nothing"))
        #expect(CadenceArchiveImportPresentation.planSummary(repeated).contains("12 records"))

        let empty = Self.plan(mode: .mergeKeepingExistingRows, inserts: [:], matches: [:])
        #expect(CadenceArchiveImportPresentation.planSummary(empty).contains("no records"))

        // The same matched rows under the other mode *are* a change, and the sentence says so.
        let rewrite = Self.plan(mode: .restoreOverwritingExistingRows, inserts: [:], matches: ["AppTask": 12])
        #expect(!CadenceArchiveImportPresentation.planSummary(rewrite).contains("would change nothing"))
    }

    @Test func theRecordCountPhraseIsSingularForExactlyOne() {
        #expect(CadenceArchiveImportPresentation.records(0) == "0 records")
        #expect(CadenceArchiveImportPresentation.records(1) == "1 record")
        #expect(CadenceArchiveImportPresentation.records(2) == "2 records")
    }

    @Test func theOutcomeSentenceCountsBothHalvesAndTheFoldedNotes() {
        let plan = Self.plan(mode: .restoreOverwritingExistingRows, inserts: ["AppTask": 3], matches: ["AppTask": 2])

        let both = CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: 3,
            overwrittenRecordCount: 2,
            skippedRecordCount: 0,
            notesFoldedFromLegacyRows: 0
        )
        #expect(CadenceArchiveImportPresentation.successMessage(both) == "Imported 3 records and replaced 2 records.")

        let addedOnly = CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: 1,
            overwrittenRecordCount: 0,
            skippedRecordCount: 0,
            notesFoldedFromLegacyRows: 0
        )
        #expect(CadenceArchiveImportPresentation.successMessage(addedOnly) == "Imported 1 record.")

        let nothing = CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: 0,
            overwrittenRecordCount: 0,
            skippedRecordCount: 7,
            notesFoldedFromLegacyRows: 0
        )
        #expect(CadenceArchiveImportPresentation.successMessage(nothing).contains("Nothing changed"))

        let folded = CadenceArchiveImportOutcome(
            plan: plan,
            insertedRecordCount: 4,
            overwrittenRecordCount: 0,
            skippedRecordCount: 0,
            notesFoldedFromLegacyRows: 1
        )
        #expect(CadenceArchiveImportPresentation.successMessage(folded).contains("1 older note was brought forward"))
    }

    @Test func theImportFailureSentenceNamesTheReasonItWasGiven() {
        #expect(CadenceArchiveImportPresentation.failureMessage("disk full") == "Import failed: disk full")
    }

    // MARK: - The per-kind rows

    /// The preview lists the kinds that change and drops the ones that do not. `CadenceSchema` has
    /// twenty-odd entities and a typical archive touches a handful; listing all of them would bury
    /// the ones that matter under a column of zeroes.
    @Test func thePreviewListsOnlyTheKindsAnImportWouldTouch() {
        let plan = Self.plan(
            mode: .mergeKeepingExistingRows,
            inserts: ["AppTask": 40, "Note": 2, "Habit": 0],
            matches: ["AppTask": 1, "Tag": 5, "Habit": 0]
        )
        let lines = CadenceArchiveImportPresentation.planLines(plan)

        #expect(lines.map(\.entityName) == ["AppTask", "Tag", "Note"], "biggest first, then by name")
        #expect(!lines.contains { $0.entityName == "Habit" }, "a kind at zero on both sides is not a row")
    }

    /// A row says what happens to its matched rows. "3 already here" reads identically under a mode
    /// that keeps them and a mode that overwrites them, which is the one thing the reader is
    /// choosing between.
    @Test func aPreviewRowSaysKeptOrReplacedRatherThanMerelyMatched() throws {
        let merging = Self.plan(mode: .mergeKeepingExistingRows, inserts: ["AppTask": 4], matches: ["AppTask": 3])
        let overwriting = Self.plan(mode: .restoreOverwritingExistingRows, inserts: ["AppTask": 4], matches: ["AppTask": 3])

        let keptRow = try #require(CadenceArchiveImportPresentation.planLines(merging).first)
        let replacedRow = try #require(CadenceArchiveImportPresentation.planLines(overwriting).first)
        #expect(keptRow.detail == "4 added · 3 kept")
        #expect(replacedRow.detail == "4 added · 3 replaced")
    }

    /// Reported, not thrown: the rest of the document is still importable and refusing it would
    /// strand the user's only copy of everything else.
    @Test func kindsThisBuildCannotStoreAreNamedInThePreviewRatherThanRefused() throws {
        let readable = Self.plan(mode: .mergeKeepingExistingRows, inserts: ["AppTask": 1], matches: [:])
        #expect(CadenceArchiveImportPresentation.unreadableKindsNote(readable) == nil)

        let stranger = CadenceArchiveImportPlan(
            mode: .mergeKeepingExistingRows,
            insertCountsByEntityName: ["AppTask": 1],
            matchedCountsByEntityName: [:],
            entityNamesOnlyInTheArchive: ["MoodEntry"]
        )
        let note = try #require(CadenceArchiveImportPresentation.unreadableKindsNote(stranger))
        #expect(note.contains("Mood entries"))
        #expect(note.contains("Everything else above still imports"))
    }

    // MARK: - Naming a table for a reader

    /// `HabitCompletion: 240` tells the user about the schema. These are the words the app uses.
    @Test func everySchemaEntityGetsAReadableNameInThePreview() {
        let names = CadenceSchema.schema.entities.map(\.name)
        #expect(names.count >= 20, "CadenceSchema reports only \(names.count) entities")

        for name in names {
            let title = CadenceArchiveImportPresentation.entityTitle(name)
            #expect(!title.isEmpty)
            #expect(title.hasSuffix("s"), "\(name) reads as \(title)")
            #expect(
                title.dropFirst().allSatisfy { !$0.isUppercase },
                "\(name) still reads as a type name: \(title)"
            )
        }
    }

    /// The one override and the pluralisation rules, pinned. The override exists because "App
    /// tasks" is the type's name and "Tasks" is the app's word for the same thing.
    @Test func theEntityNamerOverridesTasksAndPluralisesTheAwkwardEndings() {
        #expect(CadenceArchiveImportPresentation.entityTitle("AppTask") == "Tasks")
        #expect(CadenceArchiveImportPresentation.entityTitle("HabitCompletion") == "Habit completions")
        #expect(CadenceArchiveImportPresentation.entityTitle("SavedLink") == "Saved links")
        #expect(CadenceArchiveImportPresentation.entityTitle("MarkdownImageAsset") == "Markdown image assets")
        // Consonant + y pluralises to -ies; a vowel before it does not.
        #expect(CadenceArchiveImportPresentation.entityTitle("Category") == "Categories")
        #expect(CadenceArchiveImportPresentation.entityTitle("Day") == "Days")
        // Sibilant endings take -es rather than a bare -s.
        #expect(CadenceArchiveImportPresentation.entityTitle("Address") == "Addresses")
        #expect(CadenceArchiveImportPresentation.entityTitle("Box") == "Boxes")
        #expect(CadenceArchiveImportPresentation.entityTitle("Branch") == "Branches")
    }

    // MARK: - Both platforms reach it, once each

    /// The [[T-161]] test for this ticket, and the one that would have caught the state this
    /// suite's first two thirds shipped in: `SettingsArchiveImportCard` and
    /// `iOSArchiveImportSettingsSection` existed, compiled, and were mounted **nowhere**, so every
    /// value assertion above passed over a control no user could see. Delete either mount and this
    /// fails; nothing else in the target would, because a view is not a call and iOS's section is
    /// invisible to a macOS-built test target.
    @Test func bothPlatformsMountTheImportCardOnTheirDataSafetyScreen() throws {
        try Self.expectMountSites(
            of: "SettingsArchiveImportCard",
            at: ["Cadence/macOS/Views/SettingsDataSafetySection.swift": 1]
        )
        try Self.expectMountSites(
            of: "iOSArchiveImportSettingsSection",
            at: ["Cadence/iOS/iOSSettingsView.swift": 1]
        )
    }

    /// And each mount is beside the export it is the other half of, rather than filed under some
    /// unrelated settings category. Ordering, not merely presence: keep-a-copy reads before
    /// read-one-back, and both read before the control that deletes everything.
    @Test func eachImportCardSitsBetweenTheExportAndTheDelete() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        )
        let macExport = try #require(mac.range(of: "SettingsDataExportCard(")).lowerBound
        let macImport = try #require(mac.range(of: "SettingsArchiveImportCard(")).lowerBound
        let macReset = try #require(mac.range(of: "SettingsDataResetCard(")).lowerBound
        #expect(macExport < macImport && macImport < macReset)

        let phone = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsView.swift")
        )
        let phoneExport = try #require(phone.range(of: "iOSDataExportSettingsSection(")).lowerBound
        let phoneImport = try #require(phone.range(of: "iOSArchiveImportSettingsSection(")).lowerBound
        let phoneReset = try #require(phone.range(of: "iOSDataResetSettingsSection(")).lowerBound
        #expect(phoneExport < phoneImport && phoneImport < phoneReset)
    }

    /// The scan is not vacuous. Without this, a wrong repository root makes every count above read
    /// an empty string and pass by finding nothing at all.
    @Test func theImportMountScanReadsTheRealFiles() throws {
        let mac = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        #expect(mac.contains("struct SettingsDataSafetySection"), "non-vacuity: wrong file")
        let phone = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsView.swift")
        #expect(phone.contains("iOSDataResetSettingsSection()"), "non-vacuity: wrong file")

        // Comments are stripped before counting, so a mount named only in prose — a tombstone
        // paragraph, a "see also", a commented-out call — is not read as a mount.
        let commentedOut = CadenceSourceScan.strippingComments("// SettingsArchiveImportCard()\nlet a = 1")
        #expect(!commentedOut.contains("SettingsArchiveImportCard"))
        #expect(commentedOut.contains("let a = 1"), "the stripper ate the code as well")
    }

    // MARK: - Fixtures

    /// A plan with the shape the surface reads, without a store behind it. The counts are the
    /// subject of every assertion above; where they came from is not.
    private static func plan(
        mode: CadenceArchiveImportMode,
        inserts: [String: Int],
        matches: [String: Int]
    ) -> CadenceArchiveImportPlan {
        CadenceArchiveImportPlan(
            mode: mode,
            insertCountsByEntityName: inserts,
            matchedCountsByEntityName: matches,
            entityNamesOnlyInTheArchive: []
        )
    }

    /// The real exporter's bytes on disk, which is what `.fileImporter` hands the flow. Writing the
    /// file rather than injecting `Data` is deliberate: the read path is part of what this pins.
    private static func writeArchive(from context: ModelContext) throws -> URL {
        let outcome = try CadenceDataExportService.exportArchive(in: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-import-fixture-\(UUID().uuidString).json")
        try outcome.data.write(to: url)
        return url
    }

    // MARK: - Reading the app's own source

    /// Through `CadenceSourceScan` rather than a fourth hand-rolled stripper in this target. Its
    /// blanking-not-deleting rule is what `eachImportCardSitsBetweenTheExportAndTheDelete` needs:
    /// the offsets it compares still mean what they mean in the file on disk.
    fileprivate static func expectMountSites(
        of name: String,
        at mountSites: [String: Int],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for (path, expected) in mountSites {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let actual = code.components(separatedBy: "\(name)(").count - 1
            #expect(
                actual == expected,
                "\(path) mounts \(name) \(actual) times, expected \(expected)",
                sourceLocation: sourceLocation
            )
        }
    }
}
