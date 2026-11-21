import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-18950]].** Contexts had no total order on screen. Every surface took
/// `@Query(sort: \Context.order)` as handed, and among equal keys SwiftData promises nothing, so
/// two contexts sharing a number -- a merge import, or two devices each creating one offline at
/// `max + 1` -- drew their sidebar sections, Today / All Tasks by-list groups and Kanban columns in
/// whatever order the store returned, while MCP listed them by order, name, id.
///
/// The behaviour half pins `CadenceDisplayOrder` and the two shared derivations that read it
/// (`CadenceTaskQuerySupport.listGroupOrder`, `CadencePickerSupport.sorted`) against **both
/// permutations** of a tie. The census half pins that no view reads a `@Query` over `Context` bare.
@MainActor
struct CadenceDisplayOrderTests {

    private static let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let highID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!

    private struct Fixture {
        let modelContext: ModelContext
        /// Same `order`, different names: the name leg decides.
        let beta: Context
        let alpha: Context
        /// Same `order` **and** same name (case aside): only the `id` leg decides.
        let twinHigh: Context
        let twinLow: Context
    }

    private func fixture() throws -> Fixture {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let beta = Context(name: "Beta")
        let alpha = Context(name: "alpha")
        let twinHigh = Context(name: "Twin")
        twinHigh.id = Self.highID
        let twinLow = Context(name: "twin")
        twinLow.id = Self.lowID
        for context in [beta, alpha, twinHigh, twinLow] {
            context.order = 3
            modelContext.insert(context)
        }
        try modelContext.save()
        return Fixture(modelContext: modelContext, beta: beta, alpha: alpha, twinHigh: twinHigh, twinLow: twinLow)
    }

    // MARK: - The order

    @Test func tiedContextsComeOutInOneOrderWhicheverWayTheyAreHanded() throws {
        let f = try fixture()
        let handed = [f.beta, f.twinHigh, f.alpha, f.twinLow]
        let expected = [f.alpha.id, f.beta.id, f.twinLow.id, f.twinHigh.id]

        #expect(CadenceDisplayOrder.contexts(handed).map(\.id) == expected)
        #expect(CadenceDisplayOrder.contexts(handed.reversed()).map(\.id) == expected)
    }

    @Test func orderStillLeadsTheNameAndTheID() throws {
        let f = try fixture()
        f.twinHigh.order = 1
        #expect(CadenceDisplayOrder.contexts([f.alpha, f.twinLow, f.twinHigh]).first?.id == Self.highID)
    }

    /// The screen and an agent's `list_contexts` read the same store, so they must agree on it.
    @Test func theScreensOrderIsMCPsOrder() throws {
        let f = try fixture()
        let handed = [f.twinHigh, f.beta, f.twinLow, f.alpha]
        #expect(
            CadenceDisplayOrder.contexts(handed).map(\.id)
                == handed.sorted(by: CadenceMCPOrdering.precedes).map(\.id)
        )
    }

    // MARK: - The shared derivations

    /// Today's groups and All Tasks' by-list groups: both permutations, one answer.
    @Test func listGroupOrderBreaksAContextTieTheSameWayBothWays() throws {
        let f = try fixture()
        let projects = [f.twinHigh, f.twinLow].map { context -> Project in
            let project = Project(name: "Plan", context: context)
            f.modelContext.insert(project)
            return project
        }
        try f.modelContext.save()

        let forward = CadenceTaskQuerySupport.listGroupOrder(contexts: [f.twinHigh, f.twinLow])
        let backward = CadenceTaskQuerySupport.listGroupOrder(contexts: [f.twinLow, f.twinHigh])

        #expect(forward == backward)
        #expect(forward == [
            CadenceTaskDropSupport.containerKey(for: .inbox),
            CadenceTaskDropSupport.containerKey(for: .project(projects[1].id)),
            CadenceTaskDropSupport.containerKey(for: .project(projects[0].id)),
        ])
    }

    /// A context picker lists contexts in the order the sidebars draw them, `id` leg included.
    @Test func thePickerEndsANameTieOnTheID() throws {
        let f = try fixture()
        let handed = [f.twinHigh, f.beta, f.twinLow, f.alpha]
        let expected = CadenceDisplayOrder.contexts(handed).map(\.id)
        #expect(CadenceContextPickerSupport.sorted(handed).map(\.id) == expected)
        #expect(CadenceContextPickerSupport.sorted(handed.reversed()).map(\.id) == expected)
    }

    // MARK: - The census

    /// Names of every `@Query` property typed `[Context]` in `source`.
    private static func contextQueryNames(in source: String) -> [String] {
        CadenceSourceScan.captures(
            #"@Query\b[^\n]*?\bvar\s+(\w+)\s*:\s*\[Context\]"#,
            in: source
        ).map(\.text)
    }

    /// A file that reads a `@Query` over `Context` without `CadenceDisplayOrder`: a query not named
    /// `storedContexts`, or a `storedContexts` read anywhere but inside the one wrapping call.
    private static func readsAContextQueryBare(_ source: String) -> Bool {
        let names = contextQueryNames(in: source)
        guard !names.isEmpty else { return false }
        if names.contains(where: { $0 != "storedContexts" }) { return true }
        let mentions = CadenceSourceScan.matchCount(#"\bstoredContexts\b"#, in: source)
        let wrapped = CadenceSourceScan.matchCount(
            #"CadenceDisplayOrder\.contexts\(\s*storedContexts\s*\)"#,
            in: source
        )
        return mentions != names.count + wrapped || wrapped < names.count
    }

    @Test func noViewReadsAContextQueryWithoutTheDisplayOrder() throws {
        let instrument = try CadenceScanInstrument(
            "@Query over Context read bare",
            fires: #"""
                @Query(sort: \Context.order) private var contexts: [Context]
                var body: some View { List(contexts) { Text($0.name) } }
                """#,
            andNotOn: #"""
                @Query(sort: \Context.order) private var storedContexts: [Context]
                private var contexts: [Context] { CadenceDisplayOrder.contexts(storedContexts) }
                var body: some View { List(contexts) { Text($0.name) } }
                """#,
            by: Self.readsAContextQueryBare
        )
        // The nearest miss the other way: renamed, but read around the wrapper.
        #expect(instrument.fires(on: #"""
            @Query(sort: \Context.order) private var storedContexts: [Context]
            private var contexts: [Context] { CadenceDisplayOrder.contexts(storedContexts) }
            var first: Context? { storedContexts.first }
            """#))

        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let read: (String) throws -> String = { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        let hits = try instrument.sweep(
            files,
            atLeast: 600,
            including: "Cadence/macOS/Views/SidebarView.swift",
            read: read
        )
        #expect(hits.isEmpty, "these read a Context @Query without CadenceDisplayOrder: \(hits)")

        // Non-vacuity: the census is about the surfaces T-18950 measured, on both platforms.
        let querying = try files.filter { !Self.contextQueryNames(in: try read($0)).isEmpty }
        #expect(querying.count >= 18)
        #expect(querying.contains("Cadence/iOS/iOSRootSidebar.swift"))
        #expect(querying.contains("Cadence/macOS/Views/KanbanSupportViews.swift"))
    }
}
