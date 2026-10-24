// macOS only: the loaders are macOS views.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-5831]] — clicking from one list straight to another opens the new list on its OWN tab
/// and controls.** `RootDetailContent` routes every area to one `AreaDetailLoader` arm (and every
/// project to one `ProjectDetailLoader` arm), and the sidebar sets `selection` directly, so Area A
/// -> Area B kept `ListDetailView`'s `@State` — tab, Sort, Order, Group, Show Archived — and never
/// re-ran the `onAppear` that restores B's remembered values. Keying the page on its list gives each
/// list its own identity. A SwiftUI identity cannot be observed from a unit test, so this pins the
/// two call sites in source.
struct ListDetailListIdentityTests {

    private func loaderBody(_ name: String, endingAt next: String, in source: String) throws -> String {
        let start = try #require(source.range(of: "struct \(name): View"), "\(name) is gone")
        let end = try #require(source.range(of: next, range: start.upperBound..<source.endIndex))
        return String(source[start.upperBound..<end.lowerBound])
    }

    @Test func eachListDetailPageIsKeyedOnItsOwnList() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailView.swift")
        let area = try loaderBody("AreaDetailLoader", endingAt: "struct ProjectDetailLoader", in: source)
        let project = try loaderBody("ProjectDetailLoader", endingAt: "struct MissingListDetailView", in: source)

        #expect(area.contains("ListDetailView(area: area, project: nil)"), "non-vacuity: not the area loader")
        #expect(area.contains(".id(area.id)"), "Area A -> Area B keeps A's tab and controls")
        #expect(project.contains("ListDetailView(area: nil, project: project)"), "non-vacuity: not the project loader")
        #expect(project.contains(".id(project.id)"), "Project A -> Project B keeps A's tab and controls")
    }
}
#endif
