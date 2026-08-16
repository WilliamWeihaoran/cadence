import Testing
@testable import Cadence

/// `ListDetailPage` is read back from two persisted places — the Settings "default list page"
/// preference (`CadencePreferenceKeys.listDetailDefaultPage`) and macOS's per-list remembered tab —
/// and both can still hold "Planning", a page neither platform has any more.
@Suite("List detail page resolution")
struct ListDetailPageTests {
    @Test("A stored Planning preference resolves to Tasks")
    func planningResolvesToTasks() {
        #expect(ListDetailPage.resolved("Planning") == .tasks)
        #expect(ListDetailPage.resolved("planning") == .tasks)
    }

    @Test("Planning is not a page")
    func planningIsNotACase() {
        #expect(ListDetailPage(rawValue: "Planning") == nil)
        #expect(!ListDetailPage.allCases.contains { $0.rawValue.lowercased() == "planning" })
    }

    @Test("An unset or unknown preference resolves to the default page")
    func unknownResolvesToDefault() {
        #expect(ListDetailPage.resolved("") == ListDetailPage.defaultPage)
        #expect(ListDetailPage.resolved("Timeline") == ListDetailPage.defaultPage)
        #expect(ListDetailPage.defaultPage == .tasks)
    }

    @Test("Every live page round-trips through its stored raw value")
    func livePagesRoundTrip() {
        for page in ListDetailPage.allCases {
            #expect(ListDetailPage.resolved(page.rawValue) == page)
        }
    }

    /// The Settings picker highlights by identity and labels by raw value, so two pages sharing
    /// either would leave it ambiguous.
    @Test("Pages have distinct ids and icons")
    func pagesAreDistinct() {
        #expect(Set(ListDetailPage.allCases.map(\.id)).count == ListDetailPage.allCases.count)
        #expect(Set(ListDetailPage.allCases.map(\.icon)).count == ListDetailPage.allCases.count)
    }
}
