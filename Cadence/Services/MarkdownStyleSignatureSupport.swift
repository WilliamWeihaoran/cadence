import CoreGraphics
import Foundation

/// **Everything a re-style depends on, reduced to one `Equatable` value.**
///
/// It answers one question on each platform, and the two are not the same question:
///
/// - **iOS asks it forwards.** `iOSMarkdownEditor.Coordinator.refreshStylingIfNeeded` re-runs the
///   styler when this changes and skips it when it does not, so a field left out of the signature
///   is a rendered block that silently stops updating — an image resized to a new `displayWidth`
///   that keeps its old canvas, a task embed whose title changed on the Mac and still reads the old
///   one here. `revealedBlockRange` is in it for the opposite reason: moving the caret into a code
///   fence changes the styling with **no** text edit to trigger a refresh.
/// - **macOS asks it backwards** (T-1045). It never gates a restyle — `MarkdownStylist.apply` runs
///   unconditionally from `textDidChange` — it *records* what the last styling was computed
///   against, on `CadenceTextView.markdownLayoutSignature`, so a later layout pass can tell that
///   the editor has since changed width and re-derive the reserved heights that were measured from
///   the old one. Without that record a width-dependent block is stale with nothing able to notice:
///   a 640 × 360 picture reserved 28.6pt and was drawn 292.5pt tall on a fresh launch, because
///   SwiftUI runs `updateNSView` before it gives the representable a frame.
///
/// Lives in `Services/` rather than beside the iOS styler that built it, because `Cadence/iOS/` is
/// inside `#if os(iOS)` and invisible to the macOS-built test target — the same reason
/// `CadenceCompactTab` sits in `Shared/`. Nothing here is platform-specific.
struct MarkdownStyleSignature: Equatable {
    let theme: String
    /// The code fence or table the caret is currently inside, which the styler leaves un-rendered
    /// so its source can be edited. Part of the signature because moving the caret in or out of one
    /// changes the styling with no text edit to trigger a refresh.
    let revealedBlockRange: NSRange?
    /// The tables the reader has asked to see the markdown of, by the storage location of each
    /// one's first character. **The one entry T-221's iOS half could not do without.**
    ///
    /// "Show Table Source" is a render decision with no text edit behind it, exactly like
    /// `revealedBlockRange` above — and unlike that one it is a *command*, so nothing else in the
    /// editor moves when it is issued. Left out of this value, `refreshStylingIfNeeded` would
    /// compare an unchanged signature, skip, and the menu item would do nothing at all.
    ///
    /// Anchors rather than ranges because an anchor survives an edit made *inside* the table it
    /// names: a cell rewrite, a row insert and a whole-table column rewrite all start at or after
    /// the table's first character, so the table stays revealed across its own edits and drops back
    /// to the grid when something above it moves.
    let tableSourceAnchors: [Int]
    let contentWidthBucket: Int
    let imageAssetRevision: String
    let taskEmbedRevision: String

    static func current(
        revealedBlockRange: NSRange?,
        imageAssets: [MarkdownImageAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        contentWidth: CGFloat = 0,
        tableSourceAnchors: Set<Int> = []
    ) -> MarkdownStyleSignature {
        MarkdownStyleSignature(
            theme: "fixed",
            revealedBlockRange: revealedBlockRange,
            // Sorted, so the same set of revealed tables is the same signature however the caller
            // happened to accumulate it — the rule `imageAssetRevision` below already follows.
            tableSourceAnchors: tableSourceAnchors.sorted(),
            contentWidthBucket: bucket(for: contentWidth),
            imageAssetRevision: imageAssets
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.displayWidth)" }
                .joined(separator: "|"),
            taskEmbedRevision: revision(of: taskEmbeds)
        )
    }

    /// **The macOS feed of the same value** (T-1045).
    ///
    /// macOS holds a note's pictures as `MarkdownImageRenderAsset`, the already-decoded render
    /// struct, rather than as the `MarkdownImageAsset` model the iOS editor passes above — so the
    /// revision string here is built from the two fields a *reserved height* depends on,
    /// `displayWidth` and `pixelSize`, which are the arguments `MarkdownImageAssetService.fittedSize`
    /// takes beside the content width. The picture bytes are deliberately not in it: redrawing the
    /// same rectangle with different pixels changes no layout.
    ///
    /// The two feeds therefore spell `imageAssetRevision` differently for the same image, and that
    /// is not a defect: a signature is only ever compared against another built by the same feed on
    /// the same platform, and neither one is persisted or sent anywhere.
    static func current(
        revealedBlockRange: NSRange?,
        renderAssets: [UUID: MarkdownImageRenderAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        contentWidth: CGFloat = 0,
        tableSourceAnchors: Set<Int> = []
    ) -> MarkdownStyleSignature {
        MarkdownStyleSignature(
            theme: "fixed",
            revealedBlockRange: revealedBlockRange,
            tableSourceAnchors: tableSourceAnchors.sorted(),
            contentWidthBucket: bucket(for: contentWidth),
            imageAssetRevision: renderAssets.values
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { "\($0.id.uuidString):\($0.displayWidth):\($0.pixelSize.width)x\($0.pixelSize.height)" }
                .joined(separator: "|"),
            taskEmbedRevision: revision(of: taskEmbeds)
        )
    }

    /// The one place a content width is reduced to the value the signature compares, so the two
    /// feeds above and every reader round it identically.
    ///
    /// Whole points, because nothing below a point survives to the screen: the layout manager will
    /// not lay a line out differently for a third of a point, and `MarkdownStylist`'s own
    /// width-dependent refresh already ignores sub-half-point differences in the heights it derives.
    static func bucket(for contentWidth: CGFloat) -> Int {
        Int(max(0, contentWidth).rounded())
    }

    private static func revision(of taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]) -> String {
        taskEmbeds.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.title,
                    $0.statusRaw,
                    $0.priorityRaw,
                    $0.dueDate,
                    $0.scheduledDate,
                    "\($0.scheduledStartMin)",
                    "\($0.estimatedMinutes)",
                    "\($0.actualMinutes)",
                    "\($0.completedSubtaskCount)/\($0.subtaskTotalCount)",
                    "\($0.isDone)",
                    "\($0.isMissing)"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    /// The same record with **only** its content width advanced.
    ///
    /// The one write `MarkdownStylist.refreshWidthDependentLayout(in:)` makes. That pass re-derives
    /// every width-dependent reserved height and nothing else — it is not a restyle — so stamping
    /// the whole current signature there would have the record claim the styling had also caught up
    /// with, say, a task embed's new title, which it has not. A future reader that gated a full
    /// restyle on this value would then skip one it needed. Everything but the width still means
    /// "the last full styling saw this".
    func advancingContentWidth(to contentWidth: CGFloat) -> MarkdownStyleSignature {
        MarkdownStyleSignature(
            theme: theme,
            revealedBlockRange: revealedBlockRange,
            tableSourceAnchors: tableSourceAnchors,
            contentWidthBucket: Self.bucket(for: contentWidth),
            imageAssetRevision: imageAssetRevision,
            taskEmbedRevision: taskEmbedRevision
        )
    }
}
