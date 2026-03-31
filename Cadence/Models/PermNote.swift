import SwiftData
import Foundation

/// A permanent, single notepad that persists indefinitely without any date key.
/// The app ensures at most one instance exists.
@Model final class PermNote {
    var id: UUID = UUID()
    var content: String = ""
    var updatedAt: Date = Date()

    init() {}
}
