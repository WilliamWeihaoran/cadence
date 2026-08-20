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
    /// `CLAUDE.md` warns that a missed model "leaves orphans"; nothing was checking it.
    @Test func theResetEmptiesEveryTypeInTheSchema() throws {
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

        try PrivacyDataResetService.deleteCadenceData(in: context)

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

    // MARK: - The wording both platforms show

    /// macOS's two status strings were inline in the view. They are the outcome's now, so iOS says
    /// the same thing rather than inventing a third sentence.
    @Test func theOutcomeSentenceIsSharedAndCountsCorrectly() {
        #expect(PrivacyDataResetOutcome(removedBackupCount: 0).statusMessage
            == "Cadence account and data were deleted.")
        #expect(PrivacyDataResetOutcome(removedBackupCount: 1).statusMessage
            == "Cadence account, data, and 1 backup were deleted.")
        #expect(PrivacyDataResetOutcome(removedBackupCount: 4).statusMessage
            == "Cadence account, data, and 4 backups were deleted.")
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
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
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
