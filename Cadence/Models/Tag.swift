import Foundation
import SwiftData

@Model final class Tag {
    var id: UUID = UUID()
    var slug: String = ""
    var name: String = ""
    var desc: String = ""
    var colorHex: String = "#6b7a99"
    var order: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(inverse: \AppTask.tags) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Note.tags) var notes: [Note]? = nil

    init(
        id: UUID = UUID(),
        name: String,
        slug: String? = nil,
        desc: String = "",
        colorHex: String = "#6b7a99",
        order: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.slug = slug ?? TagSupport.slug(for: name)
        self.desc = desc
        self.colorHex = colorHex
        self.order = order
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
