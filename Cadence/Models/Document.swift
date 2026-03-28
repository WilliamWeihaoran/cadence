import SwiftData
import Foundation

/// A freeform text document (markdown) attached to an Area or Project.
@Model final class Document {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var content: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var area: Area? = nil
    var project: Project? = nil

    init(title: String = "Untitled") {
        self.title = title
    }
}
