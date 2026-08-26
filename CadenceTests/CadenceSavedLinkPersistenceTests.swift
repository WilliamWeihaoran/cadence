import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-327: a saved link deleted on macOS could come back.
///
/// `modelContext.delete(link)` marks the row deleted in the context and nothing more. Until
/// something saves, the store still holds it — so a quit or a crash before SwiftData's autosave
/// flushes puts the link back on next launch, with nothing anywhere that looks like a failure.
/// macOS's `LinksView` did that on both the delete and the insert.
///
/// Every assertion below is a **fetch from a second context on the same container**, which is the
/// difference the bug turns on: the editing context reports the row gone either way, and only the
/// store answers whether the change survives the process. `hasChanges` is asserted alongside for
/// the same reason from the other side.
@MainActor
struct CadenceSavedLinkPersistenceTests {

    /// The delete. A second context must stop seeing the link, and must have stopped seeing it
    /// before anything else runs — not eventually, when autosave gets round to it.
    @Test func aDeletedLinkIsGoneFromTheStoreAndNotJustFromItsContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let link = SavedLink(title: "Docs", url: "https://example.com")

        try CadenceSavedLinkPersistence.insert(link, in: modelContext)
        #expect(try ModelContext(container).fetch(FetchDescriptor<SavedLink>()).count == 1)

        try CadenceSavedLinkPersistence.delete(link, in: modelContext)

        #expect(!modelContext.hasChanges, "the delete was left pending in the context")
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<SavedLink>()).isEmpty,
            "the store still holds the deleted link, so a relaunch restores it"
        )
    }

    /// The insert, which had the same hole: a link created and never committed is a link the user
    /// typed and lost.
    @Test func aNewLinkIsInTheStoreBeforeTheSheetCloses() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let link = SavedLink(title: "Roadmap", url: "https://example.com/roadmap")
        link.order = 4

        try CadenceSavedLinkPersistence.insert(link, in: modelContext)

        #expect(!modelContext.hasChanges, "the insert was left pending in the context")
        let stored = try ModelContext(container).fetch(FetchDescriptor<SavedLink>())
        #expect(stored.count == 1)
        #expect(stored.first?.title == "Roadmap")
        #expect(stored.first?.url == "https://example.com/roadmap")
        #expect(stored.first?.order == 4)
    }

    /// Deleting one link commits that link and leaves its siblings alone — the commit is not a
    /// blanket flush that happens to work.
    @Test func deletingOneLinkLeavesTheOthersInTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let links = (0..<3).map { index -> SavedLink in
            let link = SavedLink(title: "Link \(index)", url: "https://example.com/\(index)")
            link.order = index
            return link
        }
        for link in links {
            try CadenceSavedLinkPersistence.insert(link, in: modelContext)
        }

        try CadenceSavedLinkPersistence.delete(links[1], in: modelContext)

        let stored = try ModelContext(container)
            .fetch(FetchDescriptor<SavedLink>(sortBy: [SortDescriptor(\.order)]))
        #expect(stored.map(\.title) == ["Link 0", "Link 2"])
        #expect(!modelContext.hasChanges)
    }

    /// The two sentences the macOS list shows when a commit throws. They are held here rather than
    /// spelled inline at each call site, so the delete and the insert cannot drift apart.
    @Test func theFailureNoticesSayWhichWriteFailed() {
        #expect(CadenceSavedLinkPersistence.saveFailureNotice == "Couldn't save this link.")
        #expect(CadenceSavedLinkPersistence.deleteFailureNotice == "Couldn't delete this link.")
        #expect(CadenceSavedLinkPersistence.saveFailureNotice != CadenceSavedLinkPersistence.deleteFailureNotice)
    }

    /// `LinksView.addLink()` and `LinksView.deleteLink(_:)` are private methods on a SwiftUI view,
    /// so no test can call them. These scans are scoped to those two **function bodies**.
    ///
    /// The file-wide check that follows them is deliberate rather than lazy: the delete this
    /// ticket is about was written inside a confirmation closure in `body`, which is a computed
    /// property and has no function body to scope to. `LinksView` is one screen with one model
    /// type, and every write it makes belongs behind the helper, so "nowhere in this file" is the
    /// rule being stated.
    @Test func theMacOSLinkListCommitsBothWritesThroughTheHelper() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        #expect(raw.count > 400, "LinksView.swift read as \(raw.count) characters")

        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")

        let addBody = try #require(
            CadenceSourceScan.functionBody(named: "addLink", in: stripped),
            "could not find addLink()"
        )
        #expect(addBody.contains("CadenceSavedLinkPersistence.insert("))
        #expect(addBody.contains("CadenceSavedLinkPersistence.saveFailureNotice"))

        let deleteBody = try #require(
            CadenceSourceScan.functionBody(named: "deleteLink", in: stripped),
            "could not find deleteLink()"
        )
        #expect(deleteBody.contains("CadenceSavedLinkPersistence.delete("))
        #expect(deleteBody.contains("CadenceSavedLinkPersistence.deleteFailureNotice"))

        #expect(
            CadenceSourceScan.matchCount(#"modelContext\.delete\("#, in: stripped) == 0,
            "LinksView deletes a link without committing it"
        )
        #expect(
            CadenceSourceScan.matchCount(#"modelContext\.insert\("#, in: stripped) == 0,
            "LinksView inserts a link without committing it"
        )
    }

    /// The two needles above match the spelling they hunt and miss the one they protect.
    @Test func theUncommittedWriteNeedlesMatchTheOldSpellingsOnly() {
        #expect(CadenceSourceScan.matchCount(#"modelContext\.delete\("#, in: "modelContext.delete(link)") == 1)
        #expect(CadenceSourceScan.matchCount(#"modelContext\.insert\("#, in: "modelContext.insert(link)") == 1)
        #expect(
            CadenceSourceScan.matchCount(
                #"modelContext\.delete\("#,
                in: "try CadenceSavedLinkPersistence.delete(link, in: modelContext)"
            ) == 0
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"modelContext\.insert\("#,
                in: "try CadenceSavedLinkPersistence.insert(link, in: modelContext)"
            ) == 0
        )
    }
}
