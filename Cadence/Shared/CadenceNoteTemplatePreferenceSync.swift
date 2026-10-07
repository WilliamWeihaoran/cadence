import Combine
import Foundation
import SwiftData
import SwiftUI

/// The one thing that carries note-template overrides between the synced `NoteTemplatePreference`
/// record and the device-local `noteTemplateOverrides` default that every template surface already
/// reads (T-1346).
///
/// **No template code changed.** That is the point of the shape. `NoteTemplateLibrary` still
/// decides what an override is, the two Settings sections still write the same `@AppStorage`
/// binding they always wrote, and the five readers — macOS `NoteEditorPane`,
/// `ListNotesSupportViews` and `SettingsView`, iOS `iOSNotesView` and `iOSSettingsView` — still
/// read the same key. So *Reset Template*, the "Customized" chip, the empty-title fallback and the
/// seeded `# Title` behave exactly as they did; the record is a second home for the same string,
/// not a second definition of it.
///
/// ## Three directions, and they are triggered by different things
///
/// - **Seed** runs once per device, gated on `CadenceNoteTemplatePreferenceStore
///   .migrationCompletedKey`. It carries templates this device customised *before* the feature
///   synced into the shared row. It merges rather than overwrites — see `firstRunMerge`.
/// - **Adopt** runs whenever the record changes: a remote row arriving, or this device's own write
///   landing. It reads the record *down* into the local default. The record is the source of truth
///   across devices, so this direction never asks whether the local value was "newer"; there is no
///   such thing across three devices without a clock nobody can trust.
/// - **Publish** runs on `UserDefaults.didChangeNotification`, which fires only because something
///   was actually written. It reads the local default *up* into the record.
///
/// Seed and adopt are one call — `reconcile` — because the order matters and the two cannot see
/// each other's work through the `@Query` array in the same frame: a seed that writes a merged map
/// and an adopt that then re-reads the *stale* record would push the pre-merge value back into the
/// local default, and the publish that followed would undo the merge in the record. `reconcile`
/// adopts the value it just wrote instead.
///
/// ## The pair cannot loop
///
/// Adopt writes the local default only when the canonical forms differ, so an adopt that changes
/// nothing posts no notification; publish compares the same canonical forms and commits nothing on
/// an empty diff. Canonicalisation is what makes that airtight — `""`, `"{}"` and two different key
/// orderings of the same map would otherwise each read as a change and the devices would correct
/// each other's punctuation forever.
///
/// ## What two devices do to each other
///
/// **Whole-map last-writer-wins, and the loser's row is kept.** Customise a template on the Mac
/// and on the phone and the later write is what all three devices end up reading; the earlier one
/// is not merged in, and it is not deleted either — if both devices created a row before either saw
/// the other's, `CadenceNoteTemplatePreferenceStore.current(from:)` simply stops picking the loser.
/// Per-template merging was considered and rejected for the steady state: a template id the record
/// does not mention is one somebody *reset*, and re-adding it from another device's stale map would
/// make *Reset Template* undoable. The one moment that reading is unavailable is this device's
/// first participation, and that is exactly where the seed merges instead.
@MainActor
@Observable
final class CadenceNoteTemplatePreferenceSync {
    /// Why the last commit was refused, kept rather than shown.
    ///
    /// A refused commit costs nothing the user can see: the local default was written first — or,
    /// for the seed, never touched — so this device already shows the templates they asked for, and
    /// only the trip to the other two is deferred to the next change or the next launch. A banner
    /// for that would be telling someone about a failure with no action attached to it.
    private(set) var lastFailureNotice: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = CadenceDefaults.store) {
        self.defaults = defaults
    }

    /// `true` once this device has made its one-time seeding decision.
    var hasSeeded: Bool {
        defaults.bool(forKey: CadenceNoteTemplatePreferenceStore.migrationCompletedKey)
    }

    private var localRaw: String {
        defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
    }

    // MARK: - Seed, then adopt

    /// Brings this device into line with the shared row: seeds it if this device has never
    /// contributed, then reads the effective value down into the local default.
    ///
    /// Returns `true` when the local default actually moved, so a test can tell a reconcile that
    /// did something from one that found everything already right.
    @discardableResult
    func reconcile(
        records: [NoteTemplatePreference],
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let seeded = seedIfNeeded(records: records, in: modelContext, now: now, commit: commit)
        // The value this device should be showing: what the seed just wrote if it wrote anything,
        // otherwise whatever the record says. Read from the seed's own return value rather than
        // from `records` again, which cannot yet see an insert made in this frame.
        let readable = CadenceNoteTemplatePreferenceStore.currentReadable(from: records)
        guard let effective = seeded ?? readable?.overridesRaw else {
            // No row this device can read: the device-local default stands. That is the shape of
            // "the Production schema has no `CD_NoteTemplatePreference` yet", of "nothing has
            // downloaded yet", and of "the only row here came from a build I do not understand" —
            // nothing can tell those apart, so there is no notice here and nothing is overwritten.
            return false
        }
        return writeLocal(effective)
    }

    /// The one-time contribution of this device's pre-sync templates, returning the raw map it
    /// wrote, or `nil` when it wrote nothing.
    ///
    /// The flag is set only on a decision that stuck: a refused commit leaves it clear so the next
    /// launch tries again, and a device with nothing to contribute sets it immediately so it never
    /// re-enters this path.
    @discardableResult
    func seedIfNeeded(
        records: [NoteTemplatePreference],
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> String? {
        guard !hasSeeded else { return nil }

        // The readable row, so a row this build cannot parse is not read as "the record dropped
        // every key you hold". The write below still targets `current`, which repairs it.
        let record = CadenceNoteTemplatePreferenceStore.currentReadable(from: records)
        guard let merged = CadenceNoteTemplatePreferenceStore.firstRunMerge(
            localRaw: localRaw,
            recordRaw: record?.overridesRaw
        ) else {
            // Nothing local to carry, or the record already holds everything this device had.
            defaults.set(true, forKey: CadenceNoteTemplatePreferenceStore.migrationCompletedKey)
            return nil
        }

        let raw = NoteTemplateLibrary.rawOverrides(from: merged)
        do {
            try CadenceNoteTemplatePreferenceStore.write(
                raw, records: records, in: modelContext, now: now, commit: commit
            )
            defaults.set(true, forKey: CadenceNoteTemplatePreferenceStore.migrationCompletedKey)
            lastFailureNotice = nil
            return raw
        } catch {
            lastFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return nil
        }
    }

    /// Reads the record down into the local default. Returns the keys-equivalent answer: `true`
    /// when the default actually moved.
    @discardableResult
    func adopt(records: [NoteTemplatePreference]) -> Bool {
        // `currentReadable`, not `current`: a row whose map this build cannot parse says nothing,
        // and `writeLocal` would canonicalise "nothing" to `{}` — one foreign row resetting the
        // templates on every device that received it. See the note on `overridesRaw(from:)`.
        guard let record = CadenceNoteTemplatePreferenceStore.currentReadable(from: records) else { return false }
        return writeLocal(record.overridesRaw)
    }

    /// `true` when the default actually moved. An equivalent write is skipped so adopt cannot post
    /// a change notification that would send publish round again.
    ///
    /// **A `raw` that says nothing moves nothing** (T-3017). This used to canonicalise it to
    /// `emptyRaw`, which would overwrite the device's templates with a reset. Both callers read
    /// through `currentReadable` (or the seed's own encoded map), so that was unreachable — the
    /// guard lived in the callers; it lives here now. Internal rather than private only so
    /// `CadenceNoteTemplatePreferenceTests` can state the property directly.
    func writeLocal(_ raw: String) -> Bool {
        guard let wanted = CadenceNoteTemplatePreferenceStore.canonicalRaw(raw) else { return false }
        guard CadenceNoteTemplatePreferenceStore.canonicalRaw(localRaw) != wanted else { return false }
        defaults.set(wanted, forKey: NoteTemplateLibrary.storageKey)
        return true
    }

    // MARK: - Publish

    /// Reads this device's local default up into the record, committing only when something
    /// differs.
    ///
    /// **Refused before the seed decision has been made.** Otherwise an unrelated `@AppStorage`
    /// write at launch — and there are dozens — would push this device's local map up as a plain
    /// overwrite and pre-empt the merge `reconcile` is about to do, which is the one place another
    /// device's customisations could be lost without anybody editing a template.
    ///
    /// Not `try?`: this inserts on the first write, and there is one `ModelContext` app-wide, so a
    /// swallowed insert is a pending change for the next unrelated `save()` to take. The failure is
    /// kept in `lastFailureNotice` and the next local change tries again.
    func publish(
        records: [NoteTemplatePreference],
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) {
        guard hasSeeded else { return }
        // `nil` is "this string says nothing" — the untouched default, or text that would not
        // decode. Neither may become a reset in the record the other two devices read.
        guard let local = CadenceNoteTemplatePreferenceStore.canonicalRaw(localRaw) else { return }

        let record = CadenceNoteTemplatePreferenceStore.current(from: records)
        if let record,
           (CadenceNoteTemplatePreferenceStore.canonicalRaw(record.overridesRaw)
            ?? CadenceNoteTemplatePreferenceStore.emptyRaw) == local {
            return
        }

        do {
            try CadenceNoteTemplatePreferenceStore.write(
                local, records: records, in: modelContext, now: now, commit: commit
            )
            lastFailureNotice = nil
        } catch {
            lastFailureNotice = CadencePendingChangePersistence.editFailureNotice
        }
    }
}

// MARK: - The host

/// The invisible view both roots attach, and the only place `CadenceNoteTemplatePreferenceSync` is
/// driven.
///
/// A `@Query` rather than a fetch, so a row arriving from another device re-runs `reconcile`
/// without anything having to poll. It draws nothing: the templates it carries are drawn by the
/// surfaces that already read the local default.
struct CadenceNoteTemplatePreferenceSyncHost: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var templatePreferences: [NoteTemplatePreference]
    @State private var sync = CadenceNoteTemplatePreferenceSync()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { sync.reconcile(records: templatePreferences, in: modelContext) }
            .onChange(of: templatePreferences.map(\.updatedAt)) { _, _ in
                sync.reconcile(records: templatePreferences, in: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                sync.publish(records: templatePreferences, in: modelContext)
            }
    }
}

extension View {
    /// Attaches the synced note templates to a root view. Idempotent and cheap: one hidden overlay
    /// holding one `@Query`.
    func cadenceSyncedNoteTemplates() -> some View {
        overlay(alignment: .topLeading) { CadenceNoteTemplatePreferenceSyncHost() }
    }
}
