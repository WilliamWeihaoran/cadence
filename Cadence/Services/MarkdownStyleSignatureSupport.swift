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
    let contentWidthBucket: Int
    let imageAssetRevision: String
    let taskEmbedRevision: String

    static func current(
        revealedBlockRange: NSRange?,
        imageAssets: [MarkdownImageAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        contentWidth: CGFloat = 0
    ) -> MarkdownStyleSignature {
        MarkdownStyleSignature(
            theme: "fixed",
            revealedBlockRange: revealedBlockRange,
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
