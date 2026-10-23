#if os(macOS)
import Foundation
import Observation

@Observable
final class ListNavigationManager {
    struct Request: Equatable {
        var areaID: UUID?
        var projectID: UUID?
        var page: ListDetailPage
        var sectionName: String? = nil
        var eventNoteID: UUID? = nil
        /// The list document the Documents tab should select on arrival ([[T-3084]]). Separate
        /// from `eventNoteID` because the two land in different columns of `ListNotesView` and a
        /// single field would have to be disambiguated by fetching the note again.
        var listNoteID: UUID? = nil
        var token: UUID = UUID()
    }

    static let shared = ListNavigationManager()

    var request: Request?

    private init() {}

    func open(areaID: UUID, page: ListDetailPage) {
        request = Request(areaID: areaID, projectID: nil, page: page)
    }

    func open(projectID: UUID, page: ListDetailPage) {
        request = Request(areaID: nil, projectID: projectID, page: page)
    }

    func open(areaID: UUID, page: ListDetailPage, sectionName: String?) {
        request = Request(areaID: areaID, projectID: nil, page: page, sectionName: sectionName)
    }

    func open(projectID: UUID, page: ListDetailPage, sectionName: String?) {
        request = Request(areaID: nil, projectID: projectID, page: page, sectionName: sectionName)
    }

    func open(areaID: UUID, page: ListDetailPage, eventNoteID: UUID) {
        request = Request(areaID: areaID, projectID: nil, page: page, eventNoteID: eventNoteID)
    }

    func open(projectID: UUID, page: ListDetailPage, eventNoteID: UUID) {
        request = Request(areaID: nil, projectID: projectID, page: page, eventNoteID: eventNoteID)
    }

    /// Open a list's Documents tab **with one of its documents selected** ([[T-3084]]).
    ///
    /// Without the id the tab selects whatever `ListNotesView.selectFirstNoteIfNeeded` reaches
    /// first, so a global-search hit on a list document would open some other document as though
    /// it were the hit.
    func open(areaID: UUID, page: ListDetailPage, listNoteID: UUID) {
        request = Request(areaID: areaID, projectID: nil, page: page, listNoteID: listNoteID)
    }

    func open(projectID: UUID, page: ListDetailPage, listNoteID: UUID) {
        request = Request(areaID: nil, projectID: projectID, page: page, listNoteID: listNoteID)
    }

    func consumeIfMatches(areaID: UUID?, projectID: UUID?) -> Request? {
        guard let request else { return nil }
        if request.areaID == areaID || request.projectID == projectID {
            self.request = nil
            return request
        }
        return nil
    }
}
#endif
