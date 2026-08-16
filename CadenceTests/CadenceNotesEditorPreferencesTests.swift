import Foundation
import Testing

@testable import Cadence

/// The notes editor's Live/Edit/Preview picker is gone and live is the only mode. These pin the two
/// things that have to be true for anyone upgrading with a stored `Edit` or `Preview`: nothing reads
/// the value any more, and the app stops carrying it around.
struct CadenceNotesEditorPreferencesTests {
    /// A throwaway suite per test, torn down afterwards so nothing leaks into the shared domain.
    private func withTemporaryDefaults(_ body: (UserDefaults) -> Void) {
        let name = "CadenceNotesEditorPreferencesTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("Could not open a temporary UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func purgesAStoredEditModeSoNothingCanReadItBack() {
        withTemporaryDefaults { defaults in
            defaults.set("Edit", forKey: CadenceNotesEditorPreferences.retiredModeKey)
            defaults.set(true, forKey: CadenceNotesEditorPreferences.retiredLiveDefaultMigrationKey)

            let removed = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(removed.sorted() == CadenceNotesEditorPreferences.retiredKeys.sorted())
            #expect(defaults.object(forKey: CadenceNotesEditorPreferences.retiredModeKey) == nil)
            #expect(defaults.object(forKey: CadenceNotesEditorPreferences.retiredLiveDefaultMigrationKey) == nil)
        }
    }

    @Test func purgesAStoredPreviewMode() {
        withTemporaryDefaults { defaults in
            defaults.set("Preview", forKey: CadenceNotesEditorPreferences.retiredModeKey)

            let removed = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(removed == [CadenceNotesEditorPreferences.retiredModeKey])
            #expect(defaults.object(forKey: CadenceNotesEditorPreferences.retiredModeKey) == nil)
        }
    }

    /// It runs on every cold launch, so the second run must be a no-op rather than a write.
    @Test func isIdempotentAndReportsNothingOnACleanInstall() {
        withTemporaryDefaults { defaults in
            defaults.set("Live", forKey: CadenceNotesEditorPreferences.retiredModeKey)

            _ = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)
            let second = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(second.isEmpty)
        }
    }

    @Test func leavesUnrelatedPreferencesAlone() {
        withTemporaryDefaults { defaults in
            defaults.set("Week", forKey: "ios.calendar.viewMode")
            defaults.set("Edit", forKey: CadenceNotesEditorPreferences.retiredModeKey)

            _ = CadenceNotesEditorPreferences.purgeRetiredKeys(in: defaults)

            #expect(defaults.string(forKey: "ios.calendar.viewMode") == "Week")
        }
    }
}
