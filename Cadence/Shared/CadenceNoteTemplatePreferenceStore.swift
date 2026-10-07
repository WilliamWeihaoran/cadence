import Foundation
import SwiftData

/// Reading and writing the synced note-template overrides (T-1346).
///
/// The duplicate rule, the canonical spelling of an override map and the first-run merge live here
/// and nowhere else, so the two Settings surfaces, the three template readers and the sync host
/// cannot come to disagree about what the stored string means.
///
/// Everything above the write helper is pure, so `CadenceNoteTemplatePreferenceTests` can pin the
/// rules without a model container.
///
/// Main-actor isolated by the project default. Nothing off the main actor compiles this file:
/// `CadenceWidgets` and `CadenceMCPServer` build `Cadence/Models/NoteTemplatePreference.swift` for
/// the schema and neither has a template surface.
enum CadenceNoteTemplatePreferenceStore {

    /// The device-local flag that says this device has made its one-time seeding decision.
    ///
    /// Deliberately **not** in `CadencePreferenceKeys`, whose stated rule is that a key only one
    /// file reads does not earn a constant there — this one is read and written by
    /// `CadenceNoteTemplatePreferenceSync` alone. It is device-local on purpose: "has *this* Mac
    /// already contributed its local templates to the shared row" is a fact about this Mac, and
    /// syncing it would make the second device skip the merge that is the whole point.
    static let migrationCompletedKey = "noteTemplateOverrides.syncSeeded.v1"

    /// The canonical spelling of an empty override map — what `NoteTemplateLibrary.resetOverride`
    /// leaves behind when the last customisation is reset, and therefore a real, deliberate value
    /// rather than an absence.
    static var emptyRaw: String { NoteTemplateLibrary.rawOverrides(from: [:]) }

    // MARK: - Canonical form

    /// `raw` re-encoded the one way this app spells an override map, or `nil` when `raw` says
    /// nothing at all.
    ///
    /// **Two spellings of the same map must not read as a change.** `""` (never written) and `"{}"`
    /// (everything reset) both parse to no overrides, and `JSONEncoder` without `.sortedKeys` can
    /// order two identical maps differently — so a diff on the raw text would publish and adopt in
    /// circles, each device "correcting" the other's punctuation forever. Canonicalising both sides
    /// before comparing is what makes `adopt`/`publish` provably terminate.
    ///
    /// `nil` is returned for the empty string and for text that will not decode, and the caller
    /// must treat both the same way: **say nothing**. A publish that turned an unreadable local
    /// default into `{}` in the record would propagate one device's corruption to the other two as
    /// a reset. An unknown template id inside a map that *does* decode is not corruption — it is a
    /// newer build's template — and is carried through untouched, the same way
    /// `NoteTemplateLibrary.setOverride` leaves other keys alone.
    static func canonicalRaw(_ raw: String) -> String? {
        NoteTemplateLibrary.decodedOverrides(from: raw).map(NoteTemplateLibrary.rawOverrides)
    }

    // MARK: - Which record

    /// The row every device must agree on when more than one exists.
    ///
    /// Newest edit wins, because that is what a person means by changing a template on the device
    /// in front of them. `id.uuidString` breaks a tie so two devices reading the same pair pick the
    /// same row rather than each picking its own and writing over the other forever.
    static func current(from records: [NoteTemplatePreference]) -> NoteTemplatePreference? {
        records.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The newest row whose map this build can actually read (T-1346).
    ///
    /// **Separate from `current(from:)` on purpose, and only for the read.** `current` stays the
    /// row every device *writes* to — moving the write target would stop the three devices
    /// converging on one row, which is the whole reason the newest-wins rule exists. But a row
    /// whose `overridesRaw` says nothing cannot be the row a device *shows*, and the next thing it
    /// can honestly show is the newest row that does say something. The unreadable row is left
    /// inert rather than deleted, like every loser here, and the next local edit publishes over it
    /// and repairs it.
    static func currentReadable(from records: [NoteTemplatePreference]) -> NoteTemplatePreference? {
        current(from: records.filter { canonicalRaw($0.overridesRaw) != nil })
    }

    /// The override string the app should be reading, given what has synced and what this device
    /// already had.
    ///
    /// With a readable record, the record — **including an empty map**. That is the difference from
    /// `CadenceLookPreferenceSync`, where an empty accent id means "never chosen" and is skipped:
    /// here a row exists only because somebody customised or reset a template, so `{}` is the exact
    /// state *Reset Template* leaves and it has to travel. Without one the device-local value
    /// stands, which is also the answer while `CD_NoteTemplatePreference` is undeployed or has
    /// simply not arrived yet — the two are indistinguishable and neither deserves a notice.
    ///
    /// **A row this build cannot read is silence, not a reset.** `publish` already refuses to turn
    /// an unparseable *local* string into a reset in the record; this is the same rule read the
    /// other way, and it was missing. `""` is what SwiftData hands back for a field a CloudKit
    /// record did not carry — a partially written record, or a row from a build that does not write
    /// this column — and canonicalising that to `{}` would have erased the templates on every
    /// device that received it. The distinction is only available because `write` canonicalises:
    /// the reset this app stores is `{}` and never `""`.
    static func overridesRaw(from records: [NoteTemplatePreference], localRaw: String) -> String {
        guard let record = currentReadable(from: records) else { return localRaw }
        return record.overridesRaw
    }

    // MARK: - The first-run merge

    /// The map this device should seed into the shared row the first time it participates, or `nil`
    /// when it has nothing to add.
    ///
    /// **Union, and only here.** After this device has published once, the rule is whole-map
    /// last-writer-wins: a template id the record does not mention is one somebody reset, and
    /// re-adding it would make a reset un-doable. Before this device has *ever* published, that
    /// reading is unavailable — the record cannot have deliberately dropped a key this device
    /// contributed, because this device has contributed nothing. So a key held locally and absent
    /// remotely is unambiguously new information at this one moment, and merging it is the answer
    /// that loses nobody's writing.
    ///
    /// Remote wins on a key both hold: the record is the shared state two other devices may already
    /// be reading, and this device's local copy of the same id is the older claim by construction.
    static func firstRunMerge(localRaw: String, recordRaw: String?) -> [String: NoteTemplateOverride]? {
        guard let local = NoteTemplateLibrary.decodedOverrides(from: localRaw), !local.isEmpty else {
            return nil
        }
        guard let recordRaw else { return local }
        let remote = NoteTemplateLibrary.decodedOverrides(from: recordRaw) ?? [:]
        let merged = local.merging(remote) { _, remoteValue in remoteValue }
        return merged == remote ? nil : merged
    }

    // MARK: - Writing

    /// What `write` throws for a `raw` that says nothing (T-3017).
    struct UnreadableOverridesRefusal: Error, Equatable {}

    /// Writes an override map, creating the synced row the first time.
    ///
    /// **Refuses a `raw` that `canonicalRaw` cannot read — `""` or unparseable text — and throws
    /// `UnreadableOverridesRefusal` before touching the row** (T-3017). It used to substitute
    /// `emptyRaw`, which would publish "say nothing" to every device as `{}`, a reset. Both callers
    /// already hand it a canonical string (`seedIfNeeded` an encoded map, `publish` a `canonicalRaw`
    /// it proved non-`nil`), so the substitution was unreachable — but only because each caller
    /// carried the guard, which the next caller would not know about. The guard is here now.
    ///
    /// Commits through `CadencePendingChangePersistence` rather than `try? save()`: this inserts on
    /// the first write, and there is one `ModelContext` app-wide, so a swallowed insert leaves the
    /// row pending for somebody else's `save()` or `rollback()`.
    @MainActor
    static func write(
        _ raw: String,
        records: [NoteTemplatePreference],
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard let canonical = canonicalRaw(raw) else { throw UnreadableOverridesRefusal() }

        guard let record = current(from: records) else {
            let created = NoteTemplatePreference(overridesRaw: canonical, updatedAt: now)
            modelContext.insert(created)
            try CadencePendingChangePersistence.commitInsert(of: created, in: modelContext, commit: commit)
            return
        }

        let previousRaw = record.overridesRaw
        let previousUpdatedAt = record.updatedAt
        record.overridesRaw = canonical
        record.updatedAt = now
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            record.overridesRaw = previousRaw
            record.updatedAt = previousUpdatedAt
        }
    }
}
