import Foundation

/// The sentence an image door shows when it loses items **before** the commit (T-649).
///
/// [[T-629]] gave both doors a notice for a *refused commit* —
/// `CadencePendingChangePersistence.editFailureNotice` — and that failure is all-or-nothing by
/// construction, because `commitInsert` un-inserts the whole batch. The other way the same door
/// loses pictures is partial, and it used to say nothing at all: `try? await
/// item.loadTransferable(type: Data.self)` returns `nil` for a photo the picker cannot vend, and
/// the `compactMap`s over `MarkdownImageAssetService.createAsset` drop every image
/// `normalizedImageData` cannot decode. The survivors are committed and referenced as though
/// nothing had happened. Pick eight photos, get six, no sentence.
///
/// **This lands in the same `imageFailureNotice` slot the commit refusal uses**, deliberately,
/// rather than as a second notice: one door, one place to look. The two cannot contradict each
/// other, because they describe disjoint outcomes — a batch that lost items before the commit
/// still commits its survivors, and a batch whose commit was refused has no survivors to report a
/// partial success about.
///
/// **It says how many, because the count is the whole complaint.** The user picked a number of
/// photos and got a different number, and the door is the only party that knows both. It does not
/// say *which* ones: the picker hands back opaque `PhotosPickerItem`s and the pasteboard hands
/// back bare images, so on three of the four doors there is no name to print, and a notice whose
/// specificity depends on which door you came through is worse than one that is always true.
enum CadenceMarkdownImageInsertionNotice {

    /// The sentence for `attempted` items offered and `accepted` assets minted, or `nil` when the
    /// door lost nothing.
    ///
    /// `nil` is also what a door with nothing to insert gets, which is what makes assigning this
    /// result the way a *clean* insertion clears the notice an earlier one left behind.
    static func notice(attempted: Int, accepted: Int) -> String? {
        let skipped = attempted - accepted
        guard skipped > 0 else { return nil }

        // Nothing survived, so there is no partial success to report — only the refusal, in the
        // same voice as every other `Couldn't …` notice in the app.
        if accepted == 0 {
            return skipped == 1
                ? "Couldn't add that image. It may be damaged or in a format Cadence can't read."
                : "Couldn't add any of those \(skipped) images. They may be damaged or in a format Cadence can't read."
        }

        // `accepted > 0` and `skipped > 0` means at least two were offered, so the plural in the
        // first sentence is always right and only the second sentence has to agree with a count.
        return skipped == 1
            ? "Added \(accepted) of \(attempted) images. One couldn't be read."
            : "Added \(accepted) of \(attempted) images. \(skipped) couldn't be read."
    }
}
