#if os(macOS)
import AppKit
import SwiftData
import Testing
@testable import Cadence

@MainActor
@Suite(.serialized)
struct MarkdownImageAssetServiceTests {
    @Test func extractsStandaloneCadenceImageReferences() {
        let firstID = UUID()
        let secondID = UUID()
        let markdown = """
        Intro

        ![Diagram](cadence-image://\(firstID.uuidString))
        Inline ![ignored](cadence-image://\(UUID().uuidString)) text
        ![](cadence-image://\(secondID.uuidString))
        """

        let references = MarkdownImageAssetService.references(in: markdown)

        #expect(references.map(\.id) == [firstID, secondID])
        #expect(references.map(\.altText) == ["Diagram", ""])
    }

    @Test func findsUnreferencedAssetsAcrossMarkdownFields() {
        let referencedID = UUID()
        let orphanID = UUID()
        let referenced = MarkdownImageAsset(
            data: Data([1]),
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        referenced.id = referencedID
        let orphan = MarkdownImageAsset(
            data: Data([2]),
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        orphan.id = orphanID

        let unused = MarkdownImageAssetService.unreferencedAssets(
            allAssets: [referenced, orphan],
            markdownTexts: ["![used](cadence-image://\(referencedID.uuidString))"]
        )

        #expect(unused.map(\.id) == [orphanID])
    }

    @Test func createsImageAssetWithMetadataAndDisplayWidth() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let image = testImage(size: CGSize(width: 800, height: 400))

        let asset = try #require(MarkdownImageAssetService.createAsset(
            from: image,
            originalFilename: "diagram.png",
            altText: "Diagram",
            in: context
        ))

        #expect(asset.originalFilename == "diagram.png")
        #expect(asset.altText == "Diagram")
        #expect(asset.data.isEmpty == false)
        #expect(asset.pixelWidth == 800)
        #expect(asset.pixelHeight == 400)
        #expect(asset.displayWidth == Double(MarkdownImageAssetService.defaultDisplayWidth))
        #expect(["image/png", "image/jpeg"].contains(asset.mimeType))
    }

    @Test func downscalesOversizedImagesToLongEdgeLimit() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let image = testImage(size: CGSize(width: 3_000, height: 1_200))

        let asset = try #require(MarkdownImageAssetService.createAsset(from: image, in: context))

        #expect(max(asset.pixelWidth, asset.pixelHeight) <= Int(MarkdownImageAssetService.maxLongEdge))
        #expect(asset.pixelWidth == 2_400)
        #expect(asset.pixelHeight == 960)
    }

    private func testImage(size: CGSize) -> NSImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        if let bitmapData = rep.bitmapData {
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * rep.bytesPerRow + x * 4
                    bitmapData[offset] = UInt8((x + y) % 255)
                    bitmapData[offset + 1] = UInt8((x * 2) % 255)
                    bitmapData[offset + 2] = UInt8((y * 2) % 255)
                    bitmapData[offset + 3] = 255
                }
            }
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
