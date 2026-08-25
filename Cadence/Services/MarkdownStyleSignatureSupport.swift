import CoreGraphics
import Foundation

/// **Everything a re-style depends on, reduced to one `Equatable` value.**
///
/// The editor re-runs the styler when this changes and skips it when it does not, so a field left
/// out of the signature is a rendered block that silently stops updating — an image resized to a
/// new `displayWidth` that keeps its old canvas, a task embed whose title changed on the Mac and
/// still reads the old one here. `revealedBlockRange` is in it for the opposite reason: moving the
/// caret into a code fence changes the styling with **no** text edit to trigger a refresh.
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
            contentWidthBucket: Int(max(0, contentWidth).rounded()),
            imageAssetRevision: imageAssets
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.displayWidth)" }
                .joined(separator: "|"),
            taskEmbedRevision: taskEmbeds.values
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
        )
    }
}
