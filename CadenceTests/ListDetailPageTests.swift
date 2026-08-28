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

    /// The T-351 case, exactly as reported: a list still remembering `Planning`, a user whose
    /// global default is `Links`, and an expected `Tasks`.
    ///
    /// `restoreRememberedTab()` read the per-list value through the *failable*
    /// `ListDetailPage(rawValue:)` and, on `nil`, threw it away and resolved the **global**
    /// default instead. But a stale remembered tab is an unrecognised page name, which is the one
    /// thing `resolved(_:)` exists to map to Tasks; it is not evidence about what the user wants
    /// for this list.
    @Test("A stale per-list tab resolves to Tasks, not to the global default")
    func aStalePerListTabResolvesToTasksRatherThanTheGlobalDefault() {
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: "Planning", defaultPageRawValue: "Links") == .tasks
        )
        // And it is the *stale* case that is being handled, not "always Tasks": a global default
        // still wins when the list has never remembered anything.
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: nil, defaultPageRawValue: "Links") == .links
        )
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: "", defaultPageRawValue: "Links") == .links
        )
    }

    @Test("A live remembered tab still wins over the global default")
    func aLiveRememberedTabWins() {
        for page in ListDetailPage.allCases {
            #expect(
                ListDetailPage.rememberedPage(
                    storedRawValue: page.rawValue,
                    defaultPageRawValue: ListDetailPage.links.rawValue
                ) == page
            )
        }
    }

    /// A stale *global* default is still resolved too, so neither half of the pair can strand a
    /// list on a page that does not exist.
    @Test("A stale global default also resolves to Tasks")
    func aStaleGlobalDefaultAlsoResolvesToTasks() {
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: nil, defaultPageRawValue: "Planning") == .tasks
        )
    }

    /// `restoreRememberedTab()` is private to a SwiftUI view, so this reads the one thing a test
    /// cannot call: that the restore goes through the shared rule rather than re-deriving it.
    @Test("macOS restores a remembered tab through the shared rule")
    func macOSRestoreUsesTheSharedRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailView.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper never fired, so this read prose as code")
        #expect(source.count == raw.count, "the stripper changed the file's length, so it is not blanking")

        // Needle self-check: it must match the failable initialiser being banned, and must not
        // match the shared rule that replaces it.
        #expect(CadenceSourceScan.matchCount("ListDetailPage\\(rawValue:", in: "ListDetailPage(rawValue: raw)") == 1)
        #expect(
            CadenceSourceScan.matchCount("ListDetailPage\\(rawValue:", in: "ListDetailPage.rememberedPage(") == 0
        )

        let body = try #require(
            CadenceSourceScan.functionBody(named: "restoreRememberedTab", in: source),
            "restoreRememberedTab() is gone or its braces do not balance"
        )
        #expect(body.contains("ListDetailPage.rememberedPage"), "got: \(body)")
        #expect(
            CadenceSourceScan.matchCount("ListDetailPage\\(rawValue:", in: body) == 0,
            "the restore still parses the remembered value with the failable initialiser"
        )
    }

    /// The Settings picker highlights by identity and labels by raw value, so two pages sharing
    /// either would leave it ambiguous.
    @Test("Pages have distinct ids and icons")
    func pagesAreDistinct() {
        #expect(Set(ListDetailPage.allCases.map(\.id)).count == ListDetailPage.allCases.count)
        #expect(Set(ListDetailPage.allCases.map(\.icon)).count == ListDetailPage.allCases.count)
    }
}
