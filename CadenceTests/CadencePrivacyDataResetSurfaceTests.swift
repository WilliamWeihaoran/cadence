import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The shipped privacy policy promised in-app deletion that iOS had no route to.
///
/// `PrivacyDataResetService` sat in `Cadence/macOS/Services/` behind an `#if os(macOS)` while
/// importing only Foundation and SwiftData — the `RemindersManager` shape exactly — and iOS's
/// Settings > Data Safety drew read-only count tiles. `docs/privacy.html` and
/// `docs/app-review-notes.md` said the user could delete their account and data from
/// Settings > Account or Settings > Data Safety; on iOS neither existed.
///
/// **Why this file reads source text.** T-161: a committed fix was revertible with the whole suite
/// green because the tests pinned a helper while nothing observed the call site. `Cadence/iOS/` is
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference —
/// the only tool for the iOS half is the real file, with exact per-file counts, comments stripped,
/// and a non-vacuity test at the end. The pattern is `CadenceInboxRemindersSurfaceTests`'.
@MainActor
struct CadencePrivacyDataResetSurfaceTests {

    // MARK: - The reset empties the whole schema

    /// **The test that fails when a model is added to `CadenceSchema` and not to the service.**
    ///
    /// Driven from `CadenceSchema.schema` rather than a hand-written list, in two steps, because
    /// SwiftData cannot instantiate a model from a `Schema.Entity`:
    ///
    /// 1. `probesByEntityName` must cover the schema *exactly* — the test below. Add a model to
    ///    the schema and that one fails until a probe exists here.
    /// 2. Every probe's type must be empty after the reset — this test. So once the probe exists,
    ///    this fails until `PrivacyDataResetService` actually deletes the new type.
    ///
    /// `docs/CLAUDE_REFERENCE.md` warns that a missed model "leaves orphans"; nothing was checking it.
    @Test func theResetEmptiesEveryTypeInTheSchema() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let probes = Self.probesByEntityName

        for probe in probes.values {
            probe.seed(context)
        }
        try context.save()

        // Positive control: the seed actually landed, so an empty store cannot pass this by
        // accident the way a scan that reads no files passes every absence assertion.
        for probe in probes.values {
            #expect(try probe.count(context) == 1, "\(probe.name) was never seeded")
        }

        try await PrivacyDataResetService.deleteCadenceData(in: context)

        for probe in probes.values.sorted(by: { $0.name < $1.name }) {
            #expect(
                try probe.count(context) == 0,
                "PrivacyDataResetService left \(probe.name) rows behind — add it to deleteCadenceData"
            )
        }
    }

    /// Step 1 of the pair above: the probe table and the schema are the same set of entities.
    ///
    /// Stated in both directions on purpose. A missing probe means the reset is unverified for a
    /// live model; a stale probe means this file is testing a type the app no longer persists.
    @Test func everySchemaEntityHasAProbe() {
        let schemaNames = Set(CadenceSchema.schema.entities.map(\.name))
        let probeNames = Set(Self.probesByEntityName.keys)

        #expect(
            probeNames == schemaNames,
            """
            probe table and CadenceSchema disagree — \
            missing probes: \(schemaNames.subtracting(probeNames).sorted()), \
            stale probes: \(probeNames.subtracting(schemaNames).sorted())
            """
        )
        // Not an empty-set-equals-empty-set pass.
        #expect(schemaNames.count >= 20, "CadenceSchema reports only \(schemaNames.count) entities")
    }

    // MARK: - The reset finishes what it reports

    /// **T-297.** The reset used to spawn `Task { await NotificationManager.shared.cancelAll() }`
    /// and return, so "Cadence account and data were deleted." could be shown with the
    /// cancellation still in flight — quit promptly and a deleted habit's daily reminder outlives
    /// the data it describes.
    ///
    /// The canceller suspends for real before it records, which is what makes the fire-and-forget
    /// spelling *deterministically* red rather than red-if-the-scheduler-cooperates: an awaited
    /// call cannot return before `didFinish` is set, and a spawned one cannot have set it.
    @Test func theResetDoesNotReturnUntilPendingNotificationsAreCancelled() async throws {
        let recorder = CancellationRecorder()
        let context = ModelContext(try makeContainer())
        context.insert(Habit(title: "Stretch"))
        try context.save()

        let started = Date()
        try await PrivacyDataResetService.deleteCadenceData(
            in: context,
            canceller: recorder.canceller(suspendingFor: .milliseconds(60))
        )

        #expect(recorder.runs == 1, "the reset no longer cancels pending notifications at all")
        #expect(
            recorder.didFinish,
            "the reset returned with the notification cancellation still in flight (T-297)"
        )
        // And the suspension was real, so a recorder that finished instantly could not have
        // passed the assertion above by accident.
        #expect(Date().timeIntervalSince(started) >= 0.05)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == 0)
    }

    /// The reset runs over an in-memory store in this suite and in every other suite that drives
    /// it; `default` being inert is what keeps those runs away from `UNUserNotificationCenter`.
    /// Same guard, same reason, as `CadenceWindDownReconciler.default`.
    @Test func theDefaultCancellerIsInertInsideATestHost() {
        #expect(NotificationManager.isTestEnvironment)
        #expect(CadenceNotificationCanceller.default.isLive == false)
        #expect(CadenceNotificationCanceller.live.isLive)
        #expect(CadenceNotificationCanceller.inert.isLive == false)
    }

    /// **T-310.** `clearStoredState` drops the widget snapshot out of the app group and asks
    /// WidgetKit for nothing, so the last rendered timeline entry — deleted task and habit titles
    /// included — stays on the home screen until the system next decides to refresh. The reset
    /// has to force the reload, and force it *after* the clear: the clear removes the reload
    /// timestamp, so a reload that ran first would leave nothing behind.
    @Test func theResetForcesAWidgetReloadAfterClearingTheSnapshot() throws {
        try withTemporaryDefaults("cadence.tests.privacy-reset") { defaults in
            let taskID = UUID()
            let stale = Date(timeIntervalSince1970: 1_000)
            CadenceWidgetRefreshCenter.reloadAllWidgets(force: true, now: stale, userDefaults: defaults)
            CadenceWidgetRefreshCenter.markTaskCompleted(taskID, now: stale, userDefaults: defaults)

            // Positive controls: the state this is about to check for removal was really there.
            #expect(CadenceWidgetRefreshCenter.lastReloadDate(userDefaults: defaults) == stale)
            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: stale, userDefaults: defaults) == [taskID])

            let before = Date()
            PrivacyDataResetService.clearWidgetState(userDefaults: defaults)

            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(userDefaults: defaults).isEmpty)
            let reload = try #require(
                CadenceWidgetRefreshCenter.lastReloadDate(userDefaults: defaults),
                "the reset cleared the widget snapshot and never asked WidgetKit for a new timeline (T-310)"
            )
            #expect(reload >= before)
        }
    }

    // MARK: - iOS reaches the reset

    /// **The T-161 test for this ticket.** Delete the iOS call site and this fails; nothing else
    /// in the suite would, because the service is a static function with no view attached and
    /// iOS's section is invisible to a macOS-built test target.
    @Test func bothPlatformsReachTheResetFromSettings() throws {
        try expectCallSites(
            of: "PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts",
            at: [
                "Cadence/iOS/iOSDataResetSettingsSection.swift": 1,
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 1,
            ]
        )
        // And the iOS section is actually drawn, in the category the docs name.
        try expectCallSites(
            of: "iOSDataResetSettingsSection",
            at: ["Cadence/iOS/iOSSettingsView.swift": 1]
        )
    }

    /// Data Safety is the one category both documents promise on iOS, so the route has to be the
    /// `.data` case rather than some other screen that happens to host the section.
    @Test func theIOSDeleteActionIsInTheDataSafetyCategory() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSSettingsView.swift"))
        let range = try #require(source.range(of: "case .data:"))
        let tail = source[range.upperBound...]
        let nextCase = tail.range(of: "\n        case ")?.lowerBound ?? tail.endIndex

        #expect(
            tail[..<nextCase].contains("dataSafetySection"),
            "Settings > Data Safety no longer routes to the section holding the delete action"
        )
        #expect(
            try strippingComments(sourceFile("Cadence/iOS/iOSSettingsView.swift"))
                .contains("iOSDataResetSettingsSection()")
        )
    }

    /// One reset sequence, not two. The steps that outlive the store — the OpenAI key, the widget
    /// snapshot, the pending restore, the local backups — were assembled inline in macOS's pane;
    /// a second hand-written copy on iOS is how "delete my data" comes to mean two things.
    @Test func neitherPlatformReSpellsTheResetSequence() throws {
        let mentions = try filesMentioning("deleteCadenceDataAndLocalArtifacts")
        #expect(
            mentions == [
                "Cadence/Services/CadencePrivacyDataResetService.swift",
                "Cadence/iOS/iOSDataResetSettingsSection.swift",
                "Cadence/macOS/Views/SettingsDataSafetySection.swift",
            ],
            "the shared reset sequence is reached from \(mentions.sorted())"
        )

        for path in [
            "Cadence/iOS/iOSDataResetSettingsSection.swift",
            "Cadence/macOS/Views/SettingsDataSafetySection.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(!source.contains("deleteAllBackups"), "\(path) deletes backups itself again")
            #expect(!source.contains("removeAPIKey"), "\(path) removes the OpenAI key itself again")
            #expect(!source.contains("clearStoredState"), "\(path) clears widget state itself again")
        }
    }

    // MARK: - The service is no longer platform-gated

    /// The guard and the folder were the bug. A reader who greps `PrivacyDataResetService` must
    /// land on the shared path, and the old path must be a comment and nothing else — a tombstone
    /// under the *unprefixed* name, because a same-named file at both paths is a `.stringsdata`
    /// collision and a hard build error.
    @Test func theResetServiceIsCrossPlatformAndTheOldPathIsOnlyATombstone() throws {
        let service = try sourceFile("Cadence/Services/CadencePrivacyDataResetService.swift")
        let live = try strippingComments(service)

        #expect(!live.contains("#if os("), "the reset service is platform-gated again")
        #expect(!live.contains("import AppKit"), "the reset service imports AppKit")
        #expect(live.contains("enum PrivacyDataResetService"), "the type moved or was renamed")

        let tombstone = try sourceFile("Cadence/macOS/Services/PrivacyDataResetService.swift")
        #expect(
            try strippingComments(tombstone).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "the old macOS path has live code in it again"
        )
        #expect(tombstone.contains("CadencePrivacyDataResetService"), "the tombstone stopped naming the new path")
    }

    // MARK: - The confirmation gate

    /// A single tap must not be able to reach the destructive action. The phrase is the gate, and
    /// it is a value type outside any platform guard precisely so it can be pinned here.
    @Test func onlyTheExactPhraseArmsTheDestructiveButton() {
        #expect(PrivacyDataResetConfirmation.authorizes("DELETE"))
        #expect(PrivacyDataResetConfirmation.authorizes("delete"))
        #expect(PrivacyDataResetConfirmation.authorizes("  DELETE  "))

        #expect(!PrivacyDataResetConfirmation.authorizes(""))
        #expect(!PrivacyDataResetConfirmation.authorizes("   "))
        #expect(!PrivacyDataResetConfirmation.authorizes("\n\t"))
        #expect(!PrivacyDataResetConfirmation.authorizes("DELET"))
        #expect(!PrivacyDataResetConfirmation.authorizes("DELETE ALL"))
        #expect(!PrivacyDataResetConfirmation.authorizes("Cadence"))
    }

    /// The gate has to be *wired*, not merely present. Two properties of the iOS screen:
    /// the card's own button opens the sheet rather than deleting, and the sheet's destructive
    /// button is disabled until `authorizes(_:)` says otherwise.
    @Test func theIOSDestructiveControlLivesBehindTheTypedPhrase() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSDataResetSettingsSection.swift"))

        #expect(source.contains("PrivacyDataResetConfirmation.authorizes"), "the typed-phrase gate is gone")
        #expect(source.contains("isDisabled: !isArmed"), "the destructive button is no longer gated on the phrase")
        #expect(source.contains(".sheet(isPresented: $isConfirming)"), "the confirmation modal is gone")

        // The section's own button presents; it must not be able to delete. Exactly one call to the
        // reset lives in this file (asserted above) and it is not inside the card's action.
        #expect(
            source.contains("action: { isConfirming = true }"),
            "the Data Safety card's button no longer merely opens the confirmation"
        )
    }

    /// **T-575: the Mac is behind the same gate, and it had to be — the Mac's reset is the bigger
    /// one.**
    ///
    /// This pane gated the reset behind a `confirmationDialog` whose destructive button was live
    /// the moment it appeared, one click from the settings pane, while iPhone and iPad required
    /// `DELETE` to be typed for a reset that does **not** sign an Apple account out. The less
    /// guarded path deleted more. The same three properties asserted of iOS above.
    @Test func theMacDestructiveControlLivesBehindTheSameTypedPhrase() throws {
        let source = try strippingComments(sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift"))

        #expect(source.contains("PrivacyDataResetConfirmation.authorizes"), "the typed-phrase gate is gone from macOS")
        #expect(source.contains("isDisabled: !isArmed"), "the macOS destructive button is no longer gated on the phrase")
        #expect(
            source.contains(".sheet(isPresented: $isConfirmingDataDelete)"),
            "the macOS confirmation modal is gone"
        )
        #expect(
            source.contains("onDeleteData: { isConfirmingDataDelete = true }"),
            "the macOS Data Safety card's button no longer merely opens the confirmation"
        )

        // The one-click dialog is *gone*, not merely unreached. A second presenter left beside the
        // sheet is exactly how the weaker path comes back, and it would satisfy every assertion
        // above.
        #expect(
            !source.contains("Delete Cadence Account and Data?"),
            "the one-click destructive confirmation dialog is back on macOS"
        )
        // One `confirmationDialog` left in the pane, and it is the *restore* one. The reset's
        // dialog is gone rather than merely unpresented, and the reset itself is reached from
        // exactly one place — the sheet's confirm handler.
        #expect(
            source.components(separatedBy: ".confirmationDialog(").count - 1 == 1,
            "the pane presents a second confirmationDialog again"
        )
        #expect(source.contains("\"Restore Backup?\""), "non-vacuity: the surviving dialog is the restore one")
        // Three mentions of the name and no more: the declaration, the sheet's `onConfirm:`, and
        // the shared sequence it calls. A fourth is a second route to the reset.
        #expect(
            source.components(separatedBy: "deleteCadenceData").count - 1 == 3,
            "the reset is reached from somewhere other than its declaration and the sheet"
        )
        #expect(
            source.contains("SettingsDataResetConfirmationSheet(onConfirm: deleteCadenceData)"),
            "the sheet is no longer what confirms the reset"
        )
    }

    /// One gate, read once per surface. Delete either read and this fails; nothing else would,
    /// because `Cadence/iOS/` is invisible to a macOS-built test target and the two views share no
    /// type whose absence a compiler could notice.
    @Test func bothResetSurfacesReachTheOneConfirmationGate() throws {
        try expectCallSites(
            of: "PrivacyDataResetConfirmation.authorizes",
            at: [
                "Cadence/iOS/iOSDataResetSettingsSection.swift": 1,
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 1,
            ]
        )

        let mentions = try filesMentioning("PrivacyDataResetConfirmation")
        #expect(
            mentions == [
                "Cadence/Services/CadencePrivacyDataResetService.swift",
                "Cadence/iOS/iOSDataResetSettingsSection.swift",
                "Cadence/macOS/Views/SettingsDataSafetySection.swift",
            ],
            "the confirmation gate is reached from \(mentions.sorted())"
        )

        // Neither surface re-spells the phrase. A literal beside the field is how the label and
        // the rule come to disagree about what arms the button.
        for path in [
            "Cadence/iOS/iOSDataResetSettingsSection.swift",
            "Cadence/macOS/Views/SettingsDataSafetySection.swift",
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(
                code.contains("PrivacyDataResetConfirmation.requiredPhrase"),
                "\(path) no longer shows the shared phrase"
            )
            #expect(
                !code.contains("\"DELETE\""),
                "\(path) re-spells the required phrase as a literal"
            )
        }
    }

    // MARK: - The wording both platforms show

    /// macOS's two status strings were inline in the view. They are the outcome's now, so neither
    /// platform invents a sentence — but there are **two** sentences, because the two platforms do
    /// not delete the same things.
    ///
    /// Both are pinned verbatim, plural included, so a "cleanup" that collapsed them back into one
    /// shared string fails here instead of shipping.
    @Test func theOutcomeSentenceIsSharedAndCountsCorrectlyInPrivacyDataResetSurface() {
        #expect(PrivacyDataResetOutcome(removedBackupCount: 0).accountAndDataStatusMessage
            == "Cadence account and data were deleted.")
        #expect(PrivacyDataResetOutcome(removedBackupCount: 1).accountAndDataStatusMessage
            == "Cadence account, data, and 1 backup were deleted.")
        #expect(PrivacyDataResetOutcome(removedBackupCount: 4).accountAndDataStatusMessage
            == "Cadence account, data, and 4 backups were deleted.")

        #expect(PrivacyDataResetOutcome(removedBackupCount: 0).dataOnlyStatusMessage
            == "Cadence data was deleted.")
        #expect(PrivacyDataResetOutcome(removedBackupCount: 1).dataOnlyStatusMessage
            == "Cadence data and 1 backup were deleted.")
        #expect(PrivacyDataResetOutcome(removedBackupCount: 4).dataOnlyStatusMessage
            == "Cadence data and 4 backups were deleted.")
    }

    /// **T-474, as the property rather than as three string comparisons.**
    ///
    /// The iOS screen explains that Sign in with Apple is macOS-only and that there is no account
    /// profile to clear here — and then printed "Cadence account and data were deleted." on the way
    /// out. The sentence iOS shows must not contain the word "account" in any casing, at any backup
    /// count, including counts nobody wrote a literal for above.
    @Test func theSentenceIOSShowsNeverClaimsAnAccountWasDeleted() {
        for count in [0, 1, 2, 4, 11] {
            let outcome = PrivacyDataResetOutcome(removedBackupCount: count)

            #expect(
                !outcome.dataOnlyStatusMessage.lowercased().contains("account"),
                "the iOS success notice claims an account was deleted: \(outcome.dataOnlyStatusMessage)"
            )
            // Non-vacuity in both directions. An outcome whose two messages were both the empty
            // string would satisfy the assertion above: the iOS sentence has to be a sentence, and
            // the macOS one — the sentence this must *not* be — still says "account".
            #expect(outcome.dataOnlyStatusMessage.hasPrefix("Cadence data"))
            #expect(outcome.dataOnlyStatusMessage.hasSuffix("deleted."))
            #expect(outcome.accountAndDataStatusMessage.lowercased().contains("account"))
        }
    }

    /// The property above is worth nothing if the iOS view reads the other sentence. Exact per-file
    /// counts, in both directions, for the reason `expectCallSites` records: a "contains" check
    /// stays green when one of two call sites reverts.
    @Test func eachPlatformPrintsTheSentenceThatMatchesWhatItDeleted() throws {
        let expectations: [String: [String: Int]] = [
            "Cadence/iOS/iOSDataResetSettingsSection.swift": [
                "outcome.dataOnlyStatusMessage": 1,
                "outcome.accountAndDataStatusMessage": 0,
            ],
            "Cadence/macOS/Views/SettingsDataSafetySection.swift": [
                "outcome.dataOnlyStatusMessage": 0,
                "outcome.accountAndDataStatusMessage": 1,
            ],
        ]

        for (path, needles) in expectations {
            let code = try strippingComments(sourceFile(path))
            #expect(code.contains("PrivacyDataResetService"), "non-vacuity: \(path) is not a caller of the reset")
            for (needle, expected) in needles {
                let actual = code.components(separatedBy: needle).count - 1
                #expect(actual == expected, "\(path) reads \(needle) \(actual) times, expected \(expected)")
            }
        }

        // And the undivided sentence is gone rather than merely unread, so a third caller cannot
        // pick it back up. Both views keep a `statusMessage` of their own `@State`, so the needle
        // has to be the *outcome's* declaration.
        let service = try strippingComments(sourceFile("Cadence/Services/CadencePrivacyDataResetService.swift"))
        #expect(service.contains("struct PrivacyDataResetOutcome"), "non-vacuity: the outcome moved or was renamed")
        #expect(
            !service.contains("var statusMessage"),
            "PrivacyDataResetOutcome has one undivided status sentence again (T-474)"
        )
    }

    /// **T-582: a status line belongs to the card whose button produced it.**
    ///
    /// The Mac's Data Safety pane declared one `statusMessage` and rendered it in **two** cards at
    /// once — the Backups card and the reset card — so creating a backup printed "Created
    /// backup-….sqlite." underneath the red **Delete Account & Data** button. iOS never had it:
    /// `iOSDataExportSettingsSection` and `iOSDataResetSettingsSection` each own their own line.
    ///
    /// **The export card's sharing is deliberate and is asserted here rather than merely spared.**
    /// It has no status line of its own, and its outcome is drawn by the reset card directly below
    /// it because both answer "what just happened to my data". An assertion that only forbade
    /// sharing would be satisfied by splitting that pair too, which is the opposite fix.
    ///
    /// Read as text, for this file's usual reason: a `@State String?` rendered inside a `body` has
    /// no seam a macOS-built test target can call.
    @Test func aBackupOutcomeIsPrintedUnderTheBackupButtonsAndNotUnderTheDeleteButton() throws {
        let path = "Cadence/macOS/Views/SettingsDataSafetySection.swift"
        let code = try strippingComments(sourceFile(path))
        #expect(code.contains("struct SettingsDataSafetySection"), "non-vacuity: wrong file")
        #expect(
            code.contains("@State private var backupStatusMessage"),
            "the Backups card has no status line of its own again (T-582)"
        )

        // Per function, not per file: a whole-file count stays green when one of the four reverts.
        for name in ["createBackup", "cleanUpAutomaticBackups", "revealBackupFolder", "stageRestore"] {
            let body = try #require(
                CadenceSourceScan.functionBody(named: name, in: code),
                "\(name) is gone from \(path)"
            )
            #expect(
                CadenceSourceScan.matchCount("backupStatusMessage =", in: body) > 0,
                "\(name) reports its outcome nowhere"
            )
            // `backupStatusMessage` capitalises the S, so this needle counts writes to the shared
            // line only — it does not double-count the ones asserted above.
            #expect(
                CadenceSourceScan.matchCount("statusMessage =", in: body) == 0,
                "\(name)'s outcome still reaches the reset card (T-582)"
            )
        }

        // And the two that belong there still land there.
        for name in ["prepareArchiveExport", "deleteCadenceData"] {
            let body = try #require(
                CadenceSourceScan.functionBody(named: name, in: code),
                "\(name) is gone from \(path)"
            )
            #expect(
                CadenceSourceScan.matchCount("backupStatusMessage =", in: body) == 0,
                "\(name) reports into the Backups card"
            )
            #expect(
                CadenceSourceScan.matchCount("statusMessage =", in: body) > 0,
                "\(name) reports its outcome nowhere"
            )
        }

        // Each line is rendered once, by one card. This is the assertion the bug failed: the count
        // for `statusMessage` was two.
        #expect(
            CadenceSourceScan.matchCount("if let statusMessage \\{", in: code) == 1,
            "the export/reset status line is drawn by more or fewer than one card (T-582)"
        )
        #expect(
            CadenceSourceScan.matchCount("if let backupStatusMessage \\{", in: code) == 1,
            "the backup status line is drawn by more or fewer than one card"
        )
        #expect(
            CadenceSourceScan.matchCount("statusMessage: statusMessage", in: code) == 1,
            "the reset card is no longer the one place the export and reset outcome is shown"
        )
    }

    /// The rest of the iOS screen, which was already right about the account — which is why the
    /// success notice read as a contradiction rather than as a slip.
    ///
    /// Stated as an absence over the whole file's live code, so it covers the button, the card
    /// title *and* the section label. The label said "Delete Account & Data" — macOS's words on the
    /// platform with no account — which is the notice's claim again, one control earlier.
    @Test func theIOSResetScreenNeverNamesAnAccountInAnythingItDraws() throws {
        let code = try strippingComments(sourceFile("Cadence/iOS/iOSDataResetSettingsSection.swift"))

        #expect(code.contains("struct iOSDataResetSettingsSection"), "non-vacuity: wrong file")
        #expect(code.contains("Delete Cadence Data"), "non-vacuity: the screen draws no delete control")
        #expect(
            !code.lowercased().contains("account"),
            "the iOS reset screen names an account in something it draws (T-474)"
        )

        // macOS keeps the word, because macOS keeps the account. Without this the assertion above
        // is satisfiable by deleting the concept from both platforms, which is the opposite fix.
        let desktop = try strippingComments(sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift"))
        #expect(desktop.contains("Delete Account & Data"))
    }

    // MARK: - The shipped documents

    /// The falsehood this ticket exists for, guarded so it cannot come back. Both documents are
    /// submission-facing, and the previous wording promised iOS a route that did not exist.
    @Test func theShippedDocumentsDescribeTheRoutesEachPlatformActuallyHas() throws {
        let privacy = try repositoryFile("docs/privacy.html")
        let review = try repositoryFile("docs/app-review-notes.md")

        // The unqualified "Settings, Account or Settings, Data Safety" promise is gone, and the
        // iOS route is named.
        #expect(!privacy.contains("You can delete your Cadence account and data in the app from Settings, Account or Settings, Data Safety."))
        #expect(privacy.contains("On iPhone and iPad the same deletion is in Settings, Data Safety."))

        // The second falsehood: Calendar access is not revoked in macOS System Settings on a phone.
        #expect(!privacy.contains("in macOS System Settings"))
        #expect(privacy.contains("in the Settings app on iPhone and iPad"))

        #expect(!review.contains("- Users can delete their Cadence account and data in Settings > Account or Settings > Data Safety."))
        #expect(review.contains("On iPhone and iPad, users delete their Cadence data in Settings > Data Safety."))
        // The notes have to say something true and specific about the gate, not just name a screen.
        #expect(review.contains("requires the word DELETE to be typed"))
    }

    // MARK: - The scan itself

    /// The absence assertions above are worth nothing if the scan reads no files, and a scan that
    /// silently returns nothing passes every one of them. Same guard, same reason, as
    /// `CadenceInboxRemindersSurfaceTests`: a `/tmp` against `/private/tmp` path mismatch once made
    /// a scan that read nothing at all look like four clean results.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInPrivacyDataResetSurface() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Services/CadencePrivacyDataResetService.swift"))
        #expect(files.contains("Cadence/iOS/iOSDataResetSettingsSection.swift"))
        #expect(files.contains("Cadence/iOS/iOSSettingsView.swift"))
        #expect(files.contains("Cadence/macOS/Views/SettingsDataSafetySection.swift"))
        #expect(!files.contains("Cadence/macOS/Services/CadencePrivacyDataResetService.swift"))

        // Reading content, not just listing names.
        #expect(try strippingComments(sourceFile("Cadence/Services/CadencePrivacyDataResetService.swift"))
            .contains("func deleteCadenceDataAndLocalArtifacts"))
        #expect(try !filesMentioning("deleteCadenceDataAndLocalArtifacts").isEmpty)
        #expect(try repositoryFile("docs/privacy.html").contains("Account and Data Deletion"))
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// One live row per schema entity, keyed by the entity name `CadenceSchema` reports.
    ///
    /// A dictionary keyed by entity name rather than an array, so `everySchemaEntityHasAProbe`
    /// can compare it to the schema as a set and name what is missing.
    ///
    /// Computed rather than a stored `static let`: a stored static's initializer runs in a
    /// nonisolated context and everything in this target is main-actor by default, so the model
    /// initializers inside would not be callable from it. Twenty rows is not worth a caching dance.
    private static var probesByEntityName: [String: ModelProbe] {
        let probes: [ModelProbe] = [
            probe { Context(name: "Work") },
            probe { Area(name: "Home") },
            probe { Project(name: "Kitchen") },
            probe { Pursuit(title: "Stay healthy") },
            probe { Tag(name: "errand") },
            probe { AppTask(title: "Buy milk") },
            probe { TaskBundle(title: "Morning", dateKey: "2026-08-20", startMin: 540, durationMinutes: 60) },
            probe { Subtask(title: "Find the receipt") },
            probe { DailyNote(date: "2026-08-20") },
            probe { WeeklyNote(weekKey: "2026-W34") },
            probe { PermNote() },
            probe { Document(title: "Spec") },
            probe { Note(kind: .permanent, title: "Ideas") },
            probe { SavedLink(title: "Docs", url: "https://example.com") },
            probe { EventNote(calendarEventID: "evt-1", eventTitle: "Standup") },
            probe {
                MarkdownImageAsset(
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    mimeType: "image/png",
                    pixelWidth: 2,
                    pixelHeight: 2,
                    displayWidth: 2
                )
            },
            probe { Goal(title: "Ship v1") },
            probe { GoalListLink() },
            probe { Habit(title: "Stretch") },
            probe { HabitCompletion(date: "2026-08-20") },
        ]
        return Dictionary(uniqueKeysWithValues: probes.map { ($0.name, $0) })
    }
}

// MARK: - The cancellation recorder

/// Stands in for `NotificationManager.cancelAll()`, which early-returns inside a test host and so
/// cannot tell an awaited call from an abandoned one on its own.
///
/// It records *after* a real suspension deliberately. A recorder that set its flag synchronously
/// would be satisfied by `Task { await canceller.run() }` whenever the scheduler happened to run
/// the child task before the caller's continuation — which is precisely the bug this pins.
@MainActor
private final class CancellationRecorder {
    private(set) var runs = 0
    private(set) var didFinish = false

    func canceller(suspendingFor duration: Duration) -> CadenceNotificationCanceller {
        CadenceNotificationCanceller {
            self.runs += 1
            try? await Task.sleep(for: duration)
            self.didFinish = true
        }
    }
}

// MARK: - Schema-driven probes

/// One schema entity, with the two operations a coverage check needs: put a row in, count rows.
///
/// `Schema.Entity` carries a name and no way to build an instance, so the seed and the count are
/// closures captured over a concrete type. The *set* of probes is still checked against the schema,
/// which is what makes the pair schema-driven rather than a hand-maintained list.
private struct ModelProbe {
    let name: String
    let seed: @MainActor (ModelContext) -> Void
    let count: @MainActor (ModelContext) throws -> Int
}

@MainActor
private func probe<T: PersistentModel>(_ make: @escaping @MainActor () -> T) -> ModelProbe {
    ModelProbe(
        name: String(describing: T.self),
        seed: { $0.insert(make()) },
        count: { try $0.fetchCount(FetchDescriptor<T>()) }
    )
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// Exact counts rather than "contains", for the reason `CadenceSharedBoardChromeTests` records: a
/// mutation that reverted *one* of several call sites left a "contains" assertion green.
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

/// Every file under `Cadence/` whose **live code** mentions `name`, sorted. Comments are stripped
/// so the tombstones and design notes this repo keeps do not count as callers.
private func filesMentioning(_ name: String) throws -> [String] {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"
    return try swiftFiles(under: "Cadence")
        .filter { try strippingComments(sourceFile($0)).range(of: pattern, options: .regularExpression) != nil }
        .sorted()
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
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
    try repositoryFile(relativePath)
}

private func repositoryFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
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
