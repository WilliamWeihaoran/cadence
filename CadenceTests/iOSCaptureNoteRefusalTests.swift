import Foundation
import SwiftData
import Testing
@testable import Cadence

// [[T-5161]]: the capture palette's Note segment names a refused create instead of doing nothing.
//
// `iOSCaptureNoteCreation` is iOS-only, so its behaviour is tested on an iOS destination; the
// modifier's wiring — that `present(_:)` routes the refusal into the notice and `body` draws it —
// lives in a private SwiftUI modifier, so it is pinned from source and runs on both legs.

#if os(iOS)
@Suite @MainActor
struct iOSCaptureNoteCreationTests {
    private struct Refused: Error {}

    @Test func aRefusedCreateNamesTheRefusalAndLeavesNoNoteBehind() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let outcome = iOSCaptureNoteCreation.create(in: context, commit: { _ in throw Refused() })
        guard case .refused(let notice) = outcome else {
            Issue.record("a refused commit opened a cover onto a note the store did not take")
            return
        }
        #expect(notice == CadencePendingChangePersistence.editFailureNotice)
        // "Nothing was changed" is only true if the insert was taken back out.
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    @Test func anAcceptedCreateHandsBackTheNoteItSaved() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        guard case .created(let note) = iOSCaptureNoteCreation.create(in: context) else {
            Issue.record("an accepted commit reported a refusal")
            return
        }
        let stored = try context.fetch(FetchDescriptor<Note>())
        #expect(stored.map(\.id) == [note.id])
        #expect(note.kind == .permanent)
    }
}
#endif

@Suite
struct iOSCaptureNoteRefusalWiringTests {
    private static let path = "Cadence/iOS/iOSCaptureRadialMenu.swift"

    @Test func theNoteSegmentRoutesARefusalIntoTheNotice() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.path)
        let present = try #require(CadenceSourceScan.functionBody(named: "present", in: source))
        #expect(!present.contains("try?"), "present(_:) swallows the create again")
        #expect(present.contains("iOSCaptureNoteCreation.create(in: modelContext)"))
        let refused = try #require(present.range(of: "case .refused(let notice):"), "no refusal arm")
        let assign = try #require(present.range(of: "noteCaptureFailureNotice = notice"), "the refusal is not kept")
        #expect(refused.upperBound <= assign.lowerBound)
        // Cleared first, so any next press of the palette — the retry — takes the sentence away.
        let clear = try #require(present.range(of: "noteCaptureFailureNotice = nil"))
        let route = try #require(present.range(of: "switch request.kind"))
        #expect(clear.upperBound <= route.lowerBound, "the notice is cleared after routing, or not at all")
    }

    @Test func theHostDrawsTheNoticeWithoutADismissal() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.path)
        let body = try #require(CadenceSourceScan.declarationBody("func body(content: Content) -> some View", in: source))
        #expect(body.contains("if let noteCaptureFailureNotice {"))
        #expect(body.contains("CadenceInlineFailureNotice(text: noteCaptureFailureNotice)"))
        #expect(!body.contains("CadenceInlineFailureNotice(text: noteCaptureFailureNotice) {"),
                "the retry clears this notice, so it must not offer a dismissal")
    }

    @Test func theCreationHelperReportsTheNotepadSentence() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.path)
        let helper = try #require(CadenceSourceScan.declarationBody("enum iOSCaptureNoteCreation", in: source))
        #expect(helper.contains("createPermanentNote(in: modelContext, commit: commit)"))
        #expect(helper.contains("return .refused(notice: CadencePendingChangePersistence.editFailureNotice)"))
    }
}
