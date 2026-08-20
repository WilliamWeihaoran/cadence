import Foundation
import Testing
@testable import Cadence

/// **The value that decides whether the editor re-styles at all.**
///
/// `MarkdownStyleSignature` was `iOSMarkdownStyleSignature`, declared inside `#if os(iOS)` where no
/// test could reach it, and it is the gate in front of the entire rendering pass: the editor
/// compares it and skips styling when it is unchanged. A field missing from it is not a wrong
/// colour, it is a block that stops updating — the failure mode T-121 exists because of.
///
/// So each test here changes exactly one input and asserts the signature moved.
@MainActor
struct MarkdownStyleSignatureTests {
    private func asset(displayWidth: Double = 520, updatedAt: Date? = nil) -> MarkdownImageAsset {
        let asset = MarkdownImageAsset(
            data: Data([0x01]),
            mimeType: "image/png",
            pixelWidth: 640,
            pixelHeight: 360,
            displayWidth: displayWidth
        )
        if let updatedAt { asset.updatedAt = updatedAt }
        return asset
    }

    private func embed(id: UUID, title: String) -> MarkdownTaskEmbedRenderInfo {
        .missing(reference: MarkdownTaskEmbedReference(id: id, title: title, range: NSRange(location: 0, length: 0)))
    }

    @Test
    func thesameInputsProduceTheSameSignature() {
        let fixed = asset()
        let left = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [fixed], contentWidth: 360)
        let right = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [fixed], contentWidth: 360)
        #expect(left == right)
    }

    /// Resizing an image changes only `displayWidth`; without it in the signature the old canvas
    /// stays on screen at the old width.
    @Test
    func resizingAnImageChangesTheSignature() {
        let narrow = asset(displayWidth: 300)
        let wide = asset(displayWidth: 520)
        #expect(
            MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [narrow])
                != MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [wide])
        )
    }

    /// Replacing an image's bytes bumps `updatedAt` and nothing else the styler reads.
    @Test
    func reuploadingAnImageChangesTheSignature() {
        let old = asset(updatedAt: Date(timeIntervalSinceReferenceDate: 0))
        let new = asset(updatedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(
            MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [old])
                != MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [new])
        )
    }

    /// Image order must not matter — assets arrive from a `@Query` whose order is not guaranteed,
    /// and a signature that flipped with it would re-style on every unrelated redraw.
    @Test
    func theOrderOfTheImageAssetsDoesNotChangeTheSignature() {
        let first = asset(displayWidth: 300)
        let second = asset(displayWidth: 520)
        #expect(
            MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [first, second])
                == MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [second, first])
        )
    }

    /// **Moving the caret into a code fence changes the styling with no text edit behind it.**
    @Test
    func revealingABlockChangesTheSignature() {
        #expect(
            MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [])
                != MarkdownStyleSignature.current(revealedBlockRange: NSRange(location: 4, length: 9), imageAssets: [])
        )
    }

    /// Width is bucketed to whole points, so a fractional layout pass does not re-render every
    /// canvas — but a real rotation or split-view change does.
    @Test
    func theContentWidthIsBucketedToWholePoints() {
        let a = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], contentWidth: 360.2)
        let b = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], contentWidth: 360.4)
        let c = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], contentWidth: 361)
        #expect(a == b)
        #expect(a != c)
    }

    /// A task renamed on another device has to redraw its embedded card.
    @Test
    func renamingAnEmbeddedTaskChangesTheSignature() {
        let id = UUID()
        #expect(
            MarkdownStyleSignature.current(
                revealedBlockRange: nil,
                imageAssets: [],
                taskEmbeds: [id: embed(id: id, title: "Ship it")]
            ) != MarkdownStyleSignature.current(
                revealedBlockRange: nil,
                imageAssets: [],
                taskEmbeds: [id: embed(id: id, title: "Ship it later")]
            )
        )
    }

    /// Task embeds arrive in a dictionary, so their iteration order is genuinely arbitrary and the
    /// signature sorts them by id before joining.
    @Test
    func theOrderOfTheTaskEmbedsDoesNotChangeTheSignature() {
        let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let embeds = [first: embed(id: first, title: "A"), second: embed(id: second, title: "B")]

        let signature = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], taskEmbeds: embeds)
        let reversed = MarkdownStyleSignature.current(
            revealedBlockRange: nil,
            imageAssets: [],
            taskEmbeds: [second: embeds[second]!, first: embeds[first]!]
        )
        #expect(signature == reversed)
    }
}
