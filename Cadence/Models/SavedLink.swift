import SwiftData
import Foundation

/// A bookmarked URL attached to an Area or Project.
@Model final class SavedLink {
    var id: UUID = UUID()
    var title: String = ""
    var url: String = ""
    var order: Int = 0
    var createdAt: Date = Date()

    var area: Area? = nil
    var project: Project? = nil

    init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}
