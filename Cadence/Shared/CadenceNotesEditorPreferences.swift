import Foundation

/// The notes editor has exactly one mode: the live, editable preview.
///
/// It used to have three — `Live`, `Edit` (raw markdown) and `Preview` (read-only) — chosen from a
/// three-icon segmented control that sat in every editor header on iPhone and iPad, and persisted
/// app-wide under `ios.notes.editorMode`. The picker, the raw mode and the read-only mode are all
/// gone; the editor renders live-styled text and commits, the way a Notion-style editor does.
///
/// Three `UserDefaults` keys outlive their features on any device that ran an earlier build.
/// Nothing reads them any more, so a stored `Edit` or `Preview` cannot strand anyone on a mode that
/// no longer exists — but a key the app keeps around and never reads is exactly the kind of thing
/// the next person to grep for `editorMode` will mistake for live state, so the app clears them
/// once at launch and stops writing them.
///
/// **This is `UserDefaults`, not model state.** `iOSMarkdownEditorPreferences.modeKey` was an
/// `@AppStorage` string; no SwiftData `@Model` ever had an editor-mode property, so nothing here
/// can drop persisted user data. Verified against `Cadence/Models/` and `CadenceSchema.swift`
/// before the removal.
enum CadenceNotesEditorPreferences {
    /// Was `@AppStorage("ios.notes.editorMode")` — the Live/Edit/Preview selection, read at roughly
    /// a dozen editor hosts.
    static let retiredModeKey = "ios.notes.editorMode"

    /// Was `@AppStorage("ios.notes.didMigrateLiveEditorDefault")` — the one-shot flag guarding a
    /// migration that moved a stored `Edit` to `Live`. Live is now the only mode, so the migration
    /// it guarded is unconditional and the flag has nothing to gate.
    static let retiredLiveDefaultMigrationKey = "ios.notes.didMigrateLiveEditorDefault"

    /// Was `@AppStorage("ios.notes.activeCoreTab")` — which of the Notes strip's tabs the iPad
    /// Today inspector reopened on. The strip is one merged view now and its tab is plain
    /// `@State` on both hosts, deliberately: see `iOSNotesView`, which records the decision that
    /// the tab resets to Daily every launch rather than persisting. The key named a three-case
    /// enum that no longer describes a four-tab strip, so there is nothing to migrate — only a
    /// value to stop carrying. T-394.
    static let retiredNotesTabKey = "ios.notes.activeCoreTab"

    static let retiredKeys = [retiredModeKey, retiredLiveDefaultMigrationKey, retiredNotesTabKey]

    /// Removes the retired keys and reports which ones were actually present.
    ///
    /// Idempotent, so it is safe to call from every cold launch: the second run finds nothing and
    /// returns an empty array.
    @discardableResult
    static func purgeRetiredKeys(in defaults: UserDefaults = .standard) -> [String] {
        let present = retiredKeys.filter { defaults.object(forKey: $0) != nil }
        for key in present {
            defaults.removeObject(forKey: key)
        }
        return present
    }
}
