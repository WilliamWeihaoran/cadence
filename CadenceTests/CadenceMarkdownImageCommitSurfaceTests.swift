import Foundation
import SwiftData
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

/// **T-629: image insertion wrote a reference for an asset row the store may never hold.**
///
/// The three image doors — macOS's `MarkdownEditorView.createAssets`, iOS's `insertPickedImages`
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
