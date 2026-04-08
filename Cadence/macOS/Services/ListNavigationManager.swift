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
