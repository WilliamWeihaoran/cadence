import Foundation
import SwiftData

/// The part of Cadence's presentation the owner asked to follow them between their Mac, iPhone and
/// iPad (T-1307, folding in [[T-1288]]).
///
/// Their sentence, and the rule this type is designed against: *"of course iphone and ipad and mac
/// os should look different, but they should all have a unified look."* So the accent set, the
/// per-destination sidebar tints, and how a task list is sorted, grouped and filtered live here;
/// view mode, zoom level, calendar presentation, sidebar width, remembered scroll positions, the
/// selected tab and collapsed state stay device-local `@AppStorage`, because those are the ways one
/// device is not another.
///
/// ## This type must not reach a distributed build before the console deploy
///
/// `CD_LookPreference` does not exist in the Production CloudKit schema until the owner presses
/// *Deploy Schema Changes*, and **the cost of shipping before that is not confined to this type**.
/// Codex R49 (2026-09-20) reads Apple's TN3164 as documenting that a missing Production schema —
/// a record type *or a field* — can fail mirroring initialisation and abort exports for the whole
/// store. So a TestFlight build carrying this model with no deploy behind it risks stopping *all*
/// sync, not just the accent palette. `docs/apple-release-readiness.md` carries the rule where the
/// owner reads it; [[T-1294]] is the ticket that asked, and its "is it type-isolated?" framing is
/// the thing R49 answered with *no*.
///
/// **Never take a model back out of `CadenceSchema` to work around that.** For one already in use
/// it destroys the column's data — there is no `SchemaMigrationPlan` here — and for a new one it is
/// still the wrong shape. The fix is the press.
///
/// ## Why a second preference record rather than more fields on an existing model
///
/// Not because it is safer: it is not. A **new field on an already-deployed record type is the same
/// Production mismatch as a new record type**, so relocating these three strings onto `Context` or
/// `Area` would have moved the risk rather than removed it — and there is no spare already-deployed
/// property to hide them in that is not the owner's own data.
///
/// Reusing `SidebarLayoutPreference` specifically buys nothing at all on that axis, because that
/// type is *itself* undeployed and awaiting the same single press. What it would cost is permanent:
/// a record type in Production can be deprecated and **never removed**, so a row called
/// `SidebarLayoutPreference` holding the accent palette and four task surfaces' sort modes is a name
/// no doc comment repairs. One press covers both types either way.
///
/// ## Additive by construction
///
/// CloudKit has been in Production since 2026-09-05 and this project has no
/// `SchemaMigrationPlan`, so nothing already stored could be re-typed, renamed or removed. This is
/// a new `@Model` with every property defaulted — the one shape that cannot cost a device its
/// data. `SidebarLayoutPreference` (T-1274) is the worked example two days older than this one,
/// and this type follows it deliberately: same duplicate rule, same device-local fallback, same
/// "a value this build cannot read is left alone rather than rewritten".
///
/// ## Three strings, not twenty columns
///
/// Sixteen separate columns for four surfaces × four settings would be sixteen CloudKit fields to
/// deploy and sixteen more chances to need a seventeenth. `taskPresentationRaw` is instead a
/// `key=value;key=value` map in the same spirit as `SidebarLayoutPreference`'s comma-separated
/// lists — and it improves on them in one way that matters here: **a pair this build does not
/// recognise is carried through a write untouched rather than dropped.** That is the whole answer
/// to "what happens when a device holds a value the other cannot represent": an
/// `allTasks.showCompleted` written by an iPhone is, to the Mac, an unknown pair it re-emits
/// verbatim. See `CadenceLookPreferenceStore`.
///
/// ## The accent's app-group mirror is not redundant
///
/// `cadence.appearance.accentPaletteID` stays in the app-group suite exactly where
/// `CadenceAccentPaletteStore` has always written it. `CadenceWidgets` is a separate process that
/// compiles `Theme.swift` and reads the palette on its next timeline reload **without a SwiftData
/// fetch**; it has no model container and must never grow one. So this record is the source of
/// truth *across devices* and the app-group default is its mirror on this one — written on every
/// adopt, which is what keeps the widget correct. Same shape for the sidebar tints and the sort
/// keys: every existing reader keeps reading the local default it already read, and
/// `CadenceLookPreferenceSync` is the only thing that carries values between the two layers.
///
/// ## Duplicates
///
/// Two devices can each create a row before either sees the other's, and CloudKit forbids the
/// unique constraint that would prevent it. The reader picks the most recently updated row, with
/// `id` breaking a tie so every device picks the same one; writes go to the picked row, which keeps
/// it newest, and the losers are left inert rather than deleted — deleting a row another device is
/// mid-sync with is how a preference becomes a data-loss bug.
@Model final class LookPreference {
    var id: UUID = UUID()

    /// The selected `CadenceAccentPalette.id`, or `""` for "never chosen", which resolves to
    /// `CadenceAccentPalette.standard` exactly as an absent app-group default does. An id written
    /// by a build offering a palette this one does not know resolves to `standard` too, so a newer
    /// device cannot leave an older one with no accents.
    var accentPaletteID: String = ""

    /// Per-destination sidebar tints, in the same encoding
    /// `CadencePreferenceKeys.sidebarTabColors` has always held — so the five surfaces that read
    /// that key keep reading it, and this is what gets mirrored into it. [[T-1288]].
    var sidebarTabColorsRaw: String = ""

    /// `key=value` pairs joined by `;`, keys sorted, holding the sort mode, sort direction,
    /// grouping mode and show-completed flag of each task surface. Parsed and emitted only by
    /// `CadenceLookPreferenceStore`, which also owns the rule that unknown pairs survive a write.
    var taskPresentationRaw: String = ""

    var createdAt: Date = Date()
    /// The last edit on any device. The newest row wins when more than one exists.
    var updatedAt: Date = Date()

    init(
        accentPaletteID: String = "",
        sidebarTabColorsRaw: String = "",
        taskPresentationRaw: String = "",
        updatedAt: Date = Date()
    ) {
        self.accentPaletteID = accentPaletteID
        self.sidebarTabColorsRaw = sidebarTabColorsRaw
        self.taskPresentationRaw = taskPresentationRaw
        self.createdAt = updatedAt
        self.updatedAt = updatedAt
    }
}
