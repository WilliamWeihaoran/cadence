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

    // MARK: - Normalising what the user typed (T-509)

    /// The defect, in the one line that had it twice: `hasPrefix` is case-sensitive and a URI
    /// scheme is not, so a link pasted out of an address bar as `HTTPS://example.com` matched
    /// neither prefix and was "repaired" into `https://HTTPS://example.com`.
    ///
    /// Behavioural, not a scan — `CadenceSavedLinkURL` is in `Cadence/Shared/`, which this target
    /// compiles, so both platforms' rule can be *called* here even though neither view can be.
    @Test func aTypedLinkKeepsWhateverSchemeItAlreadyHasWhateverItsCase() {
        for scheme in ["http", "https", "HTTP", "HTTPS", "HtTpS", "Http"] {
            let typed = "\(scheme)://example.com/roadmap"
            #expect(
                CadenceSavedLinkURL.normalized(typed) == typed,
                "\(typed) was given a second scheme"
            )
        }
    }

    /// And the half that has to keep working: a scheme-less host still gets `https://`, which is
    /// the whole reason the check is there.
    @Test func aTypedLinkWithNoSchemeIsGivenTheAssumedOne() {
        #expect(CadenceSavedLinkURL.normalized("example.com") == "https://example.com")
        #expect(CadenceSavedLinkURL.normalized("example.com/a?b=c") == "https://example.com/a?b=c")
        // A scheme the list does not recognise is not a scheme as far as this rule is concerned —
        // the behaviour both platforms already shipped, pinned rather than changed.
        #expect(CadenceSavedLinkURL.normalized("ftp://example.com") == "https://ftp://example.com")
        #expect(CadenceSavedLinkURL.assumedScheme == "https://", "a typed link was downgraded to cleartext")
    }

    /// Trimming and the blank case moved into the helper with the scheme check, so that the guard
    /// both call sites wrote by hand cannot be spelled two ways either. `"   "` is blank; a bare
    /// `isEmpty` on the untrimmed field lets it through and stores `https://   `.
    @Test func aBlankURLFieldNormalisesToNothingAndTheRestIsTrimmed() {
        #expect(CadenceSavedLinkURL.normalized("") == nil)
        #expect(CadenceSavedLinkURL.normalized("   ") == nil)
        #expect(CadenceSavedLinkURL.normalized("\n\t ") == nil)
        #expect(CadenceSavedLinkURL.normalized("  example.com  ") == "https://example.com")
        #expect(CadenceSavedLinkURL.normalized("  HTTPS://example.com\n") == "HTTPS://example.com")
    }

    /// The scheme test is anchored. Without `.anchored` a host that merely *contains* `http://`
    /// later on — a redirector query string is the everyday one — reads as already-schemed and is
    /// stored with no scheme at all.
    @Test func theSchemeTestIsAPrefixRatherThanASearch() {
        #expect(!CadenceSavedLinkURL.hasRecognisedScheme("example.com/r?to=https://elsewhere.com"))
        #expect(
            CadenceSavedLinkURL.normalized("example.com/r?to=https://elsewhere.com")
                == "https://example.com/r?to=https://elsewhere.com"
        )
        #expect(CadenceSavedLinkURL.hasRecognisedScheme("HTTP://example.com"))
    }

    /// Both add forms defer to it rather than respelling it. This is the half that makes the
    /// behavioural tests above cover the two screens, and the only half available for iOS.
    @Test func neitherPlatformStillHandRollsTheSchemeCheck() throws {
        for path in [
            "Cadence/macOS/Views/LinksView.swift",
            "Cadence/iOS/iOSListSupportViews.swift",
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "the comment stripper removed nothing in \(path)")

            let body = try #require(
                CadenceSourceScan.functionBody(named: "addLink", in: stripped),
                "\(path) has no addLink()"
            )
            #expect(
                body.contains("CadenceSavedLinkURL.normalized("),
                "\(path) does not normalise the typed URL through the shared helper"
            )
            #expect(
                CadenceSourceScan.matchCount(#"hasPrefix\(\"http"#, in: stripped) == 0,
                "\(path) still tests the scheme with a case-sensitive hasPrefix (T-509)"
            )
        }
    }

    /// ...and that needle really does match the spelling it hunts.
    @Test func theHandRolledSchemeNeedleMatchesTheSpellingItReplaced() {
        #expect(CadenceSourceScan.matchCount(#"hasPrefix\(\"http"#, in: #"url.hasPrefix("https://")"#) == 1)
        #expect(CadenceSourceScan.matchCount(#"hasPrefix\(\"http"#, in: #"url.hasPrefix("http://")"#) == 1)
        #expect(
            CadenceSourceScan.matchCount(
                #"hasPrefix\(\"http"#,
                in: "guard let url = CadenceSavedLinkURL.normalized(newURL) else { return }"
            ) == 0
        )
    }

    // MARK: - iOS reports a refused write (T-507)

    /// `iOSListLinksPanel.addLink()` and `.delete(_:)` are private methods on a SwiftUI view in
    /// `Cadence/iOS/`, which this macOS test target does not compile — so this is **source shape**,
    /// not behaviour. What is behavioural is above and in `CadencePendingChangePersistenceTests`:
    /// the helper these two now let throw already commits and rolls back correctly. The defect was
    /// only ever the caller discarding the answer.
    @Test func theIOSLinkListReportsBothRefusedWritesRatherThanSwallowingThem() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.contains("struct iOSListLinksPanel"), "the scan read the wrong file")

        let addBody = try #require(
            CadenceSourceScan.functionBody(named: "addLink", in: stripped),
            "could not find addLink()"
        )
        #expect(addBody.contains("CadenceSavedLinkPersistence.insert("))
        #expect(
            addBody.contains("CadenceSavedLinkPersistence.saveFailureNotice"),
            "the iOS add form still closes over an insert the store refused (T-507)"
        )

        let deleteBody = try #require(
            CadenceSourceScan.functionBody(named: "delete", in: stripped),
            "could not find delete(_:)"
        )
        #expect(deleteBody.contains("CadenceSavedLinkPersistence.delete("))
        #expect(
            deleteBody.contains("CadenceSavedLinkPersistence.deleteFailureNotice"),
            "the iOS list still swallows a refused delete (T-507)"
        )

        // The report half of the `try? save()` rule cannot see the delete — nothing followed the
        // swallow there — so the file-wide needle is what covers it. Both writes, one rule.
        #expect(
            CadenceSourceScan.matchCount(#"try\?\s*CadenceSavedLinkPersistence"#, in: stripped) == 0,
            "a saved-link commit in the iOS list is swallowed again (T-507)"
        )
        // And the notice has somewhere to be read. A caught error assigned to a property no view
        // draws is the same silence with more code.
        #expect(
            stripped.contains("Text(actionError)"),
            "iOSListLinksPanel records actionError and never shows it"
        )
    }

    /// The swallowed-commit needle matches the spelling it hunts and misses the fix.
    @Test func theSwallowedSavedLinkCommitNeedleMatchesOnlyTheOldSpelling() {
        #expect(
            CadenceSourceScan.matchCount(
                #"try\?\s*CadenceSavedLinkPersistence"#,
                in: "try? CadenceSavedLinkPersistence.insert(link, in: modelContext)"
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"try\?\s*CadenceSavedLinkPersistence"#,
                in: "try CadenceSavedLinkPersistence.insert(link, in: modelContext)"
            ) == 0
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
