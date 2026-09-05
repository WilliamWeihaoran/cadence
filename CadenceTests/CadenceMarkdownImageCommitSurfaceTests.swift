import Foundation
import SwiftData
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

/// **T-629: image insertion wrote a reference for an asset row the store may never hold.**
///
/// The three image doors — macOS's `MarkdownEditor.createAssets`, iOS's `insertPickedImages`
/// and `createPastedImageAssets` — each called `MarkdownImageAssetService.createAsset(… in:)`,
/// which does `modelContext.insert(asset)` and nothing else, and then committed it with `try?
/// modelContext.save()`. That is half 1 of the `try? save()` rule (`AGENTS.md`), **existence, one
/// frame down**: the insert happens a frame below the swallowed commit, so the frame holding the
/// `try?` never had to spell `insert` for the defect to be there.
///
/// The picture rendered either way, because the context still holds the row. It stopped rendering
/// the first time anything unrelated called `rollback()` on the app's single `ModelContext` — the
/// pending insert went with it, and the note kept the `![…](cadence-image://<uuid>)` reference it
/// had already been given. Permanently broken, and not self-healing: nothing rewrites a note to
/// drop a reference whose asset never existed.
///
/// **This has to agree with [[T-620]] (`9d38854`), which is the same model type from the other
/// side.** That fix made the delete sweep a *candidate-set* delete, because an asset whose owning
/// row has not imported from CloudKit yet is indistinguishable from an unreferenced one — so
/// deletion errs toward keeping, and pays for it in leaked bytes. The two must not err in opposite
/// directions. This fix errs the same way: a refused commit **un-inserts the asset and writes no
/// reference at all**, so the failure costs the user the paste rather than leaving a token pointing
/// at nothing. Neither half ever leaves markdown referencing an asset the store does not hold.
///
/// **Two halves.** The commit unit is callable, so the un-insert is pinned behaviourally against a
/// real container with a `commit` that throws — a `save()` that throws cannot be provoked out of an
/// in-memory container. The three doors are `private func`s on SwiftUI views, two of them inside
/// `#if os(iOS)` which this macOS target does not compile at all, so their shape is a source scan.
@MainActor
struct CadenceMarkdownImageCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private static let macEditor = "Cadence/macOS/Editor/MarkdownEditorView.swift"
    private static let iosSurface = "Cadence/iOS/iOSMarkdownEditingSurface.swift"

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

#if os(macOS)
    private func makeImage(width: Int = 40, height: Int = 20) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Behavioural: the unit the three doors now commit through

    /// The premise. `createAsset` inserts and does **not** commit, so the row is pending in the
    /// context and absent from the store until its caller says otherwise. That is why the caller
    /// owning the commit is the whole fix — and why swallowing it was the whole defect.
    @Test func creatingAnImageAssetLeavesTheRowPendingUntilTheCallerCommits() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        let asset = try #require(MarkdownImageAssetService.createAsset(from: makeImage(), in: modelContext))

        #expect(modelContext.hasChanges, "createAsset committed on its own")
        let reader = ModelContext(modelContainer)
        #expect(try reader.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
        // The reference the editor would write, so the assertion below is about the same id.
        #expect(MarkdownImageAssetService.markdown(for: asset).contains(asset.id.uuidString))
    }

    /// The success path: one commit and the row is in the store, read through a second context so
    /// the creating context's own memory cannot satisfy it, with nothing left pending.
    @Test func acommittedImageAssetIsInTheStoreBeforeAnyReferenceIsWritten() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let asset = try #require(MarkdownImageAssetService.createAsset(from: makeImage(), in: modelContext))

        try CadencePendingChangePersistence.commitInsert(of: [asset], in: modelContext)

        #expect(!modelContext.hasChanges)
        let reader = ModelContext(modelContainer)
        let stored = try reader.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(stored.map(\.id) == [asset.id])
    }

    /// **The failure this ticket is about.** A refused commit un-inserts every asset it was handed,
    /// so the context stops holding a row the store never took — and the caller, which has not
    /// written the reference yet, gets the error instead of a token pointing at nothing.
    ///
    /// The whole batch is undone, not just the first: a multi-image paste writes one reference per
    /// asset, so leaving any of them behind leaves markdown a later `rollback()` can strand.
    @Test func arefusedImageCommitLeavesNoAssetForAReferenceToPointAt() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let assets = try (0..<3).map { _ in
            try #require(MarkdownImageAssetService.createAsset(from: makeImage(), in: modelContext))
        }

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitInsert(of: assets, in: modelContext) { _ in
                throw CommitRefused()
            }
        }

        // The defect's own mechanism, run forwards: the next unrelated `save()` from any screen,
        // on the app's single context. With the un-insert it commits nothing. Without it, this is
        // the line that would put the refused rows in the store — or, had `rollback()` come first
        // instead, the line that would have left the note's reference pointing at nothing.
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
        let reader = ModelContext(modelContainer)
        #expect(try reader.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
    }
#endif

    // MARK: - Source shape: macOS

    /// macOS's single funnel — the panel, the paste and the drop all reach `createAssets`.
    ///
    /// Returning `[]` is already how this function refuses (`allowsImageInsertion`), and
    /// `CadenceTextView.insertMarkdownImages` no-ops on an empty list, so a refused commit reaches
    /// the text layer as "there are no images", which is true.
    @Test func themacOSImageFunnelWritesNoReferenceOverARefusedCommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.macEditor)
        let create = try CadenceCommitSurfaceScan.declarationBody(named: "createAssets", in: source)

        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0, "createAssets still swallows its commit")
        #expect(create.contains("CadencePendingChangePersistence.commitInsert(of: assets, in: modelContext)"))
        #expect(create.contains("imageFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("return assets", in: create),
            "the assets are handed back above the failure branch"
        )
        // The reader discriminates: the refusal's own `return []` sits *inside* the catch.
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("guard allowsImageInsertion", in: create))

        #expect(source.contains("@State private var imageFailureNotice: String?"))
        #expect(
            source.contains("CadenceInlineFailureNotice(text: imageFailureNotice)"),
            "the macOS editor sets a notice it never draws"
        )

        // `resizeImage` is deliberately untouched: it edits a stored field in place on a row the
        // store already holds and reports nothing, which is exactly what the rule still allows.
        let resize = try CadenceCommitSurfaceScan.declarationBody(named: "resizeImage", in: source)
        #expect(resize.contains("try? modelContext.save()"))
    }

    // MARK: - Source shape: iOS

    /// iOS has two doors rather than one funnel, and they fail differently: the photos picker owns
    /// the text it is about to write, so it returns before writing it; the paste door answers UIKit
    /// with an asset list, so it answers with an empty one.
    @Test func bothiOSImageDoorsWriteNoReferenceOverARefusedCommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.iosSurface)

        let picked = try CadenceCommitSurfaceScan.declarationBody(named: "insertPickedImages", in: source)
        #expect(CadenceSourceScan.matchCount(#"try\?\s*modelContext"#, in: picked) == 0)
        #expect(picked.contains("CadencePendingChangePersistence.commitInsert(of: insertedAssets, in: modelContext)"))
        #expect(picked.contains("imageFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("applyCommandToDraft(.insertMarkdown(markdown))", in: picked),
            "the picker writes its markdown above the failure branch"
        )

        let pasted = try CadenceCommitSurfaceScan.declarationBody(named: "createPastedImageAssets", in: source)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: pasted) == 0)
        #expect(pasted.contains("CadencePendingChangePersistence.commitInsert(of: assets, in: modelContext)"))
        #expect(pasted.contains("imageFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("return assets", in: pasted),
            "the paste door hands its assets back above the failure branch"
        )

        #expect(source.contains("@State private var imageFailureNotice: String?"))
        #expect(
            source.contains("CadenceInlineFailureNotice(text: imageFailureNotice)"),
            "the iOS editor sets a notice it never draws"
        )

        // Same carve-out as macOS, and for the same reason.
        let resize = try CadenceCommitSurfaceScan.declarationBody(named: "resizeImageAsset", in: source)
        #expect(resize.contains("try? modelContext.save()"))
    }

    // MARK: - T-649: the items lost before the commit ever happens

    /// **The sentence, on its own.** `CadenceMarkdownImageInsertionNotice` is shared and
    /// unconditional, so unlike the doors it can be exercised rather than scanned — which matters,
    /// because "eight in, six out" is an arithmetic claim and the three doors all delegate it here.
    ///
    /// The `nil`s are the load-bearing half. A door with nothing to insert and a door that lost
    /// nothing both get `nil`, and assigning that result is how a clean insertion **clears** the
    /// notice an earlier failure left on screen. A function that returned a sentence for
    /// `attempted == accepted` would leave the editor permanently accusing itself.
    @Test func theImageInsertionNoticeCountsWhatTheDoorLostBeforeTheCommit() {
        let notice = CadenceMarkdownImageInsertionNotice.notice(attempted:accepted:)

        // Nothing lost, nothing said — including the empty door, and including a nonsense pair no
        // caller should produce, because a scan helper must not assert on malformed input.
        #expect(notice(0, 0) == nil)
        #expect(notice(8, 8) == nil)
        #expect(notice(1, 2) == nil)

        // The ticket's own example, and the singular beside it.
        #expect(notice(8, 6) == "Added 6 of 8 images. 2 couldn't be read.")
        #expect(notice(8, 7) == "Added 7 of 8 images. One couldn't be read.")
        #expect(notice(2, 1) == "Added 1 of 2 images. One couldn't be read.")

        // Nothing survived: there is no partial success to report, so the sentence is a refusal.
        #expect(notice(1, 0) == "Couldn't add that image. It may be damaged or in a format Cadence can't read.")
        #expect(
            notice(3, 0) == "Couldn't add any of those 3 images. They may be damaged or in a format Cadence can't read."
        )

        // The count in the sentence is the count the caller passed, not a constant: the two halves
        // of every partial sentence move independently.
        #expect(notice(20, 19)?.contains("19 of 20") == true)
        #expect(notice(20, 5)?.contains("15 couldn't be read") == true)
    }

    /// macOS's single funnel counts what it was handed and reports what it lost — on both exits,
    /// because "no asset survived" is the same defect with the count at its maximum.
    ///
    /// It reaches the same `imageFailureNotice` T-629 writes to, deliberately: the assertion that
    /// the file still declares exactly one such `@State` is what keeps a second notice from being
    /// bolted on beside the first.
    @Test func themacOSImageFunnelNamesTheItemsItDroppedBeforeTheCommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.macEditor)
        let create = try CadenceCommitSurfaceScan.declarationBody(named: "createAssets", in: source)

        #expect(create.contains("let attempted = urls.count + images.count"), "the funnel counts nothing")
        let reported = CadenceSourceScan.matchCount("CadenceMarkdownImageInsertionNotice.notice", in: create)
        #expect(reported == 2, "the funnel reports on \(reported) of its two exits")
        #expect(create.contains("accepted: assets.count"), "the surviving-asset exit reports a hardcoded count")
        // The empty exit used to be a bare `return []`; it is the maximal loss, not the silent one.
        #expect(!create.contains("guard !assets.isEmpty else { return [] }"))

        // One notice for the whole door, still, and still drawn.
        #expect(
            CadenceSourceScan.matchCount("@State private var imageFailureNotice", in: source) == 1,
            "the macOS editor grew a second image notice"
        )
        #expect(source.contains("CadenceInlineFailureNotice(text: imageFailureNotice)"))
    }

    /// Both iOS doors, which lose items in different places: the picker's `continue` covers a photo
    /// the picker cannot vend *and* one `UIImage` cannot decode, and the paste door's `compactMap`
    /// covers the second alone.
    @Test func bothiOSImageDoorsNameTheItemsTheyDroppedBeforeTheCommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.iosSurface)

        let picked = try CadenceCommitSurfaceScan.declarationBody(named: "insertPickedImages", in: source)
        #expect(picked.contains("let attempted = items.count"), "the picker counts nothing")
        #expect(CadenceSourceScan.matchCount("CadenceMarkdownImageInsertionNotice.notice", in: picked) == 2)
        #expect(picked.contains("accepted: insertedAssets.count"))
        #expect(!picked.contains("guard !insertedAssets.isEmpty else { return }"))

        let pasted = try CadenceCommitSurfaceScan.declarationBody(named: "createPastedImageAssets", in: source)
        #expect(pasted.contains("let attempted = images.count"), "the paste door counts nothing")
        #expect(CadenceSourceScan.matchCount("CadenceMarkdownImageInsertionNotice.notice", in: pasted) == 2)
        #expect(pasted.contains("accepted: assets.count"))
        #expect(!pasted.contains("guard !assets.isEmpty else { return [] }"))

        // `allowsImageInsertion` is untouched on purpose: a door closed by configuration is not a
        // door that lost the user's pictures, and it has nothing to say.
        #expect(pasted.contains("guard allowsImageInsertion else { return [] }"))

        #expect(
            CadenceSourceScan.matchCount("@State private var imageFailureNotice", in: source) == 1,
            "the iOS editor grew a second image notice"
        )
    }

    // MARK: - T-708: the notice that had no way to go away

    /// The component decides dismissal, and it decides it as a *parameter*.
    ///
    /// The bare form is still the default, because 43 of the 49 call sites sit beside the control
    /// that failed and are cleared by the next press of it. The dismissable form exists for the
    /// six that are not: a notice inside a markdown editing surface, where the next thing the user
    /// does is type, and typing never reaches the door that set it.
    @Test func theInlineFailureNoticeDrawsADismissControlOnlyWhenItIsGivenOne() throws {
        let path = "Cadence/Shared/Components/CadenceInlineFailureNotice.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
        #expect(code != raw, "expected comments and literals to have been blanked")
        #expect(code.count == raw.count, "the stripper changed the length")

        // Optional and defaulted, so the 43 bare callers keep compiling and keep looking the same.
        #expect(
            CadenceSourceScan.matchCount(#"var onDismiss: \(\(\) -> Void\)\?"#, in: code) == 1,
            "dismissal is not an optional parameter of the component"
        )
        #expect(
            CadenceSourceScan.matchCount(#"let onDismiss:"#, in: code) == 0,
            "a required onDismiss would force a control on every call site"
        )
        #expect(code.contains("if let onDismiss {"), "the control is drawn unconditionally")
        #expect(code.contains("Button(action: onDismiss)"), "nothing calls back to the caller")
        #expect(raw.contains(#"accessibilityLabel("Dismiss")"#), "the dismiss control is unlabelled")

        // Both branches draw the same sentence — one component, not two spellings of red text.
        #expect(
            CadenceSourceScan.matchCount(#"\bsentence\b"#, in: code) == 3,
            "the dismissable and bare forms no longer share one sentence view"
        )
        #expect(code.contains("@ViewBuilder"), "a two-branch body needs it")
    }

    /// Exactly six call sites take a dismissal, and every one of them is a markdown editing
    /// surface. Named individually rather than counted, because a count that still totals six
    /// cannot tell you the six are the six that need it.
    @Test func onlyTheMarkdownEditingSurfacesOfferToDismissTheirFailureNotice() throws {
        let dismissable = try CadenceScanInstrument(
            "inline failure notice with a dismissal",
            fires: "CadenceInlineFailureNotice(text: imageFailureNotice) { self.imageFailureNotice = nil }",
            andNotOn: "CadenceInlineFailureNotice(text: imageFailureNotice)",
            by: { CadenceSourceScan.matchCount(#"CadenceInlineFailureNotice\(text: [A-Za-z]+\) \{"#, in: $0) > 0 }
        )

        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let hits = try dismissable.sweep(
            paths,
            atLeast: 400,
            including: Self.macEditor,
            read: CadenceSourceScan.strippedSourceReader()
        )
        #expect(
            hits == [
                "Cadence/iOS/iOSMarkdownEditingSurface.swift",
                "Cadence/macOS/Editor/MarkdownEditorView.swift",
                "Cadence/macOS/Views/ListNotesSupportViews.swift",
                "Cadence/macOS/Views/NoteEditorPane.swift",
                "Cadence/macOS/Views/NotePanel.swift"
            ],
            "a dismissal appeared outside the markdown editing surfaces, or left one of them"
        )

        // Five files, six notices: the iOS surface carries both of its own.
        var withDismissal = 0
        var total = 0
        for path in paths {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            total += CadenceSourceScan.matchCount(#"CadenceInlineFailureNotice\(text: "#, in: code)
            withDismissal += CadenceSourceScan.matchCount(#"CadenceInlineFailureNotice\(text: [A-Za-z]+\) \{"#, in: code)
        }
        // T-813/T-817: 51, not 49 -- `CadenceTerminalRecoveryView` added two (neither dismissable;
        // there is nothing to dismiss back to on the one screen that shows when every store this
        // launch tried has already failed). T-614 then made it 52: macOS `moveContext` reports a
        // refused reorder instead of swallowing it, and a reorder has a retry control beside it,
        // so it is bare like the other 45. T-868/T-869/T-870 finished that sweep and made it 58 --
        // the other six drag-to-rearrange surfaces (Today, All Tasks/Inbox, the sidebar, a list's
        // Tasks tab, the All Tasks board's list column, and the section board's column rail), all
        // bare for the same reason: the retry is the drag itself.
        #expect(total == 60, "the inline notice has \(total) call sites, not the 60 this test was written over")
        #expect(withDismissal == 6, "\(withDismissal) call sites offer a dismissal, not 6")

        // And each of the six is named, so one swapping places with another is still a failure.
        for (path, notices) in [
            (Self.macEditor, ["CadenceInlineFailureNotice(text: imageFailureNotice) { self.imageFailureNotice = nil }"]),
            (Self.iosSurface, [
                "CadenceInlineFailureNotice(text: imageFailureNotice) { self.imageFailureNotice = nil }",
                "CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { self.embeddedTaskFailureNotice = nil }"
            ]),
            ("Cadence/macOS/Views/NotePanel.swift", ["CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { self.embeddedTaskFailureNotice = nil }"]),
            ("Cadence/macOS/Views/NoteEditorPane.swift", ["CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { self.embeddedTaskFailureNotice = nil }"]),
            ("Cadence/macOS/Views/ListNotesSupportViews.swift", ["CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { self.embeddedTaskFailureNotice = nil }"])
        ] {
            let source = try CadenceSourceScan.sourceFile(path)
            for notice in notices {
                #expect(source.contains(notice), "\(path) no longer offers to dismiss \(notice)")
            }
        }
    }

    // MARK: - The scan read what it claims to

    /// Both files are real, long, and carry the needles a blanked reader could not produce.
    @Test func theImageCommitScanReachesBothEditorsItClaimsTo() throws {
        for path in [Self.macEditor, Self.iosSurface] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(source.count > 8_000, "\(path) read as \(source.count) characters")
            #expect(source.contains("MarkdownImageAssetService.createAsset"), "\(path) has no image door in it")
        }
        // The stripper keeps code and blanks prose: each file's own platform fence survives.
        #expect(try CadenceCommitSurfaceScan.scanned(Self.macEditor).contains("#if os(macOS)"))
        #expect(try CadenceCommitSurfaceScan.scanned(Self.iosSurface).contains("#if os(iOS)"))
    }
}
