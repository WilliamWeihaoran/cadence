import SwiftData
import Foundation

@Model final class MarkdownImageAsset {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data = Data()
    var mimeType: String = "image/jpeg"
    var originalFilename: String = ""
    var altText: String = ""
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var displayWidth: Double = 520
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        data: Data,
        mimeType: String,
        originalFilename: String = "",
        altText: String = "",
        pixelWidth: Int,
        pixelHeight: Int,
        displayWidth: Double
    ) {
        self.id = UUID()
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
        self.altText = altText
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayWidth = displayWidth
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
