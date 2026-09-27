import Foundation
import SwiftData

/// The user's customised note templates, as one synced row (T-1346).
///
/// **The owner's sentence, 2026-09-27: "the note templates should sync. all data should sync
/// across devices."** Codex's R64 audit (`docs/audits/2026-09-22/sync-rollback/coverage.md`) found
/// this to be the one real coverage gap against that question: every other thing living outside the
/// synced models has a reason to be device-local — window geometry and navigation are about a
/// device, the OpenAI key is `ThisDeviceOnly` Keychain by a deliberate security boundary, EventKit
/// calendar identifiers differ per account — but a template the user *wrote* is the same kind of
/// thing as a note they wrote, and a note is a row.
///
/// ## Why a new `@Model` and not `NSUbiquitousKeyValueStore`
///
/// The cheap-looking alternative was the key-value store: no schema change, no Console deploy,
/// small strings. It was rejected on four counts, and the first is the one that removes its whole
/// advantage.
///
/// 1. **It does not avoid an owner action.** `NSUbiquitousKeyValueStore` needs
///    `com.apple.developer.ubiquity-kvstore-identifier`, and neither `Cadence.entitlements` nor
///    `Cadence-iOS.entitlements` carries it. Adding it is an App ID capability change and a
///    re-signed provisioning profile — an owner action of the same class as pressing *Deploy
///    Schema Changes*, with none of the precedent this repo already has for that press.
/// 2. **It has no clock to arbitrate with.** Its conflict rule is last-writer-wins on an opaque
///    key with no timestamp a reader can see, so two devices that each customised a template
///    offline cannot be reconciled by anything this code could write. The record below carries
///    `updatedAt`, which is what lets `CadenceNoteTemplatePreferenceStore.current(from:)` pick the
///    same winner on all three devices — and what lets the first-run merge in
///    `CadenceNoteTemplatePreferenceSync` be more than a coin toss.
/// 3. **It would be a fourth persistence mechanism** beside SwiftData/CloudKit, `UserDefaults` and
///    the Keychain, with its own size limits (1 MB total, 1 MB per value) and its own failure
///    modes, for one string.
/// 4. **It escapes every coverage rule this repo enforces off the schema.** Data export, archive
///    import, the privacy data reset and the markdown-image inventory are each driven by
///    `CadenceSchema.schema.entities` and each fails a test when a model is added and not handled.
///    A ubiquitous key is invisible to all four, so the user's templates would silently stop being
///    in their backup, their restore and their delete-everything.
///
/// ## Why its own type rather than a field on `LookPreference`
///
/// **Not because it is safer.** Per R49's reading of TN3164, a new *field* on an already-deployed
/// record type is the same Production mismatch as a new *record type*, and `LookPreference` is
/// itself undeployed today — so one press covers either shape and the risk is identical. What
/// decides it is the name, and names in a deployed CloudKit schema are permanent: a record type can
/// be deprecated and **never removed**. `LookPreference` is the accent palette, the sidebar tints
/// and four task surfaces' sort settings; a markdown template body is not a look, and R64 says so
/// in as many words — *"Do not silently widen `LookPreference.taskPresentationRaw` into a content
/// store."*
///
/// ## Why one row and not one row per template
///
/// Eight templates would be eight records to reconcile and eight more chances for a device to hold
/// half a set. The override map is already a single JSON string in `UserDefaults`, written and read
/// by `NoteTemplateLibrary` and by nothing else, so carrying that exact string is the change that
/// leaves the template feature's behaviour — the reset affordance, the seeded `# Title`, the
/// empty-title fallback — entirely untouched. Whole-map last-writer-wins is the stated conflict
/// rule; see `CadenceNoteTemplatePreferenceSync`.
///
/// The one limit the move introduces: a CloudKit record is capped at 1 MB, where a `UserDefaults`
/// string was not. Eight hand-typed stencils are three orders of magnitude below that, and a cap
/// enforced here would silently change what a template is, so there is none.
///
/// ## Additive by construction
///
/// CloudKit has been in Production since 2026-09-05 and this project has no `SchemaMigrationPlan`,
/// so nothing already stored may be re-typed, renamed or removed. Every property here is stored
/// with a default, there are no relationships, no `@Attribute(.unique)` and no `.deny` — the one
/// shape that cannot cost a device its data. `SidebarLayoutPreference` (T-1274) and
/// `LookPreference` (T-1307) are the worked examples and this follows both.
///
/// ## This type must not reach a distributed build before the Console deploy
///
/// `CD_NoteTemplatePreference` does not exist in the Production CloudKit schema until the owner
/// presses *Deploy Schema Changes*, and the cost of shipping before that is **not confined to this
/// type**: R49 reads TN3164 as documenting that a missing Production schema can fail mirroring
/// initialisation and abort exports for the whole store. `docs/apple-release-readiness.md` carries
/// the owed press where the owner reads it; this is the third type on that line and one press
/// covers all three. **Never take a model back out of `CadenceSchema` to quieten a red sync test**
/// ([[T-1294]] rejected that by name) — the fix is the press.
///
/// Locally, and on a signed build before the press, nothing breaks and nothing is said: the type
/// arrives as zero rows, which is the same shape as "nothing has synced yet", and every template
/// surface keeps reading the device-local `noteTemplateOverrides` default it already read. Nothing
/// can tell "not deployed" from "not downloaded yet", so there is no notice to show.
///
/// ## Duplicates
///
/// Two devices can each create a row before either sees the other's, and CloudKit forbids the
/// unique constraint that would prevent it. The reader picks the most recently updated row with
/// `id` breaking a tie, so every device picks the same one; writes go to the picked row, which
/// keeps it newest, and the losers are left inert rather than deleted — deleting a row another
/// device is mid-sync with is how a preference becomes a data-loss bug.
@Model final class NoteTemplatePreference {
    var id: UUID = UUID()
    /// The `NoteTemplateLibrary` override map, as JSON — the same string
    /// `NoteTemplateLibrary.rawOverrides(from:)` writes into `UserDefaults` today, canonicalised by
    /// `CadenceNoteTemplatePreferenceStore.canonicalRaw(_:)` before it is stored so that two
    /// spellings of the same map cannot read as a change.
    var overridesRaw: String = ""
    var createdAt: Date = Date()
    /// The last template edit on any device. The newest row wins when more than one exists.
    var updatedAt: Date = Date()

    init(overridesRaw: String = "", updatedAt: Date = Date()) {
        self.overridesRaw = overridesRaw
        self.createdAt = updatedAt
        self.updatedAt = updatedAt
    }
}
