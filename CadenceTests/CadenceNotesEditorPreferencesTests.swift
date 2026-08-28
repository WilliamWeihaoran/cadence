import Foundation
import Testing

@testable import Cadence

/// The notes editor's Live/Edit/Preview picker is gone and live is the only mode. These pin the two
/// things that have to be true for anyone upgrading with a stored `Edit` or `Preview`: nothing reads
/// the value any more, and the app stops carrying it around.
struct CadenceNotesEditorPreferencesTests {
    @Test func purgesAStoredEditModeSoNothingCanReadItBack() throws {
        try withTemporaryDefaults("CadenceNotesEditorPreferencesTests") { defaults in
            defaults.set("Edit", forKey: CadenceNotesEditorPreferences.retiredModeKey)
            defaults.set(true, forKey: CadenceNotesEditorPreferences.retiredLiveDefaultMigrationKey)
            defaults.set("Daily", forKey: "ios.notes.activeCoreTab")

            let removed = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(removed.sorted() == CadenceNotesEditorPreferences.retiredKeys.sorted())
            #expect(defaults.object(forKey: CadenceNotesEditorPreferences.retiredModeKey) == nil)
            #expect(defaults.object(forKey: CadenceNotesEditorPreferences.retiredLiveDefaultMigrationKey) == nil)
        }
    }

    @Test func purgesAStoredPreviewMode() throws {
        try withTemporaryDefaults("CadenceNotesEditorPreferencesTests") { defaults in
            defaults.set("Preview", forKey: CadenceNotesEditorPreferences.retiredModeKey)

            let removed = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(removed == [CadenceNotesEditorPreferences.retiredModeKey])
            #expect(defaults.object(forKey: CadenceNotesEditorPreferences.retiredModeKey) == nil)
        }
    }

    /// It runs on every cold launch, so the second run must be a no-op rather than a write.
    @Test func isIdempotentAndReportsNothingOnACleanInstall() throws {
        try withTemporaryDefaults("CadenceNotesEditorPreferencesTests") { defaults in
            defaults.set("Live", forKey: CadenceNotesEditorPreferences.retiredModeKey)

            _ = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)
            let second = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(second.isEmpty)
        }
    }

    /// The Notes strip's remembered tab.
    ///
    /// `iOSNotesPanel` and `iOSCompactNotesView` merged into one `iOSNotesView`, and the merged
    /// strip keeps its tab in plain `@State` — deliberately, so a relaunch opens on Daily instead
    /// of on a Weekly note with the date snapped back to this week. That left
    /// `ios.notes.activeCoreTab` with no reader and no writer, and it was not in `retiredKeys`, so
    /// the purge that exists for exactly this shape of key walked past it every launch. T-394.
    @Test func purgesTheRetiredNotesTabKey() throws {
        try withTemporaryDefaults("CadenceNotesEditorPreferencesTests") { defaults in
            defaults.set("Weekly", forKey: "ios.notes.activeCoreTab")

            let removed = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(removed == ["ios.notes.activeCoreTab"])
            #expect(defaults.object(forKey: "ios.notes.activeCoreTab") == nil)
            #expect(CadenceNotesEditorPreferences.retiredKeys.contains("ios.notes.activeCoreTab"))
        }
    }

    /// The premise the purge rests on, checked rather than trusted: the key is orphaned, so the
    /// only place it is spelled in shipping code is its own retirement. Comments are stripped, so
    /// the paragraph in `iOSNotesView` explaining the decision does not count as a use.
    @Test func theOnlyCodeMentionOfTheRetiredNotesTabKeyIsItsRetirement() throws {
        let sourceRoot = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        )

        var scannedFiles = 0
        var strippedSomething = false
        var keptItsLength = true
        var mentions: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scannedFiles += 1
            let raw = try String(contentsOf: url, encoding: .utf8)
            let code = CadenceSourceScan.strippingComments(raw)
            if code != raw { strippedSomething = true }
            if code.count != raw.count { keptItsLength = false }
            if code.contains("ios.notes.activeCoreTab") {
                mentions.append(url.lastPathComponent)
            }
        }

        // Non-vacuity: a scan that read nothing, or stripped nothing, proves nothing.
        #expect(scannedFiles > 400, "the scan read only \(scannedFiles) Swift files")
        #expect(strippedSomething, "the comment stripper never fired, so it read prose as code")
        #expect(keptItsLength, "the comment stripper changed a file's length, so it is not blanking")
        #expect(mentions == ["CadenceNotesEditorPreferences.swift"], "got \(mentions)")
    }

    @Test func leavesUnrelatedPreferencesAlone() throws {
        try withTemporaryDefaults("CadenceNotesEditorPreferencesTests") { defaults in
            defaults.set("Week", forKey: "ios.calendar.viewMode")
            defaults.set("Edit", forKey: CadenceNotesEditorPreferences.retiredModeKey)

            _ = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(defaults.string(forKey: "ios.calendar.viewMode") == "Week")
        }
    }
}
