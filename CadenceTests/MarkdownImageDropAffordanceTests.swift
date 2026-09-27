import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **What the pointer promises over a dropped image** (T-478).
///
/// `MarkdownEditor.allowsImageInsertion` closes four image doors — the toolbar's photo button, the
/// `/image` command, the paste and the drop — but it only reached the first three. The drop was
/// *safe*: `onCreateMarkdownImages` returned `[]`, `insertMarkdownImages` answered `false`, and
/// `performDragOperation` fell through to `super`. It was not *honest*: `draggingEntered` answered
/// `.copy` for any image payload, so a host that had already declined images showed the copy badge
/// right up until the drop did nothing.
///
/// These exercise the decision, not the AppKit plumbing. `NSDraggingInfo` is a protocol with a
/// dozen members none of which this rule reads, so the rule is split into
/// `markdownImageDropOperation(for:)` and driven with a **private** pasteboard — the same reason
/// `MarkdownImagePasteTests` owns its boards rather than writing `NSPasteboard.general`, which
/// would destroy whatever the person running the suite had copied.
@MainActor
struct MarkdownImageDropAffordanceTests {

    // MARK: - Fixtures

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

    private func dropPasteboard(_ name: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("com.haoranwei.Cadence.tests.drop.\(name)"))
        board.clearContents()
        return board
    }

    /// A bitmap dragged out of another app: TIFF and nothing else.
    private func draggedBitmap(_ name: String) -> NSPasteboard {
        let board = dropPasteboard(name)
        board.setData(makeImage().tiffRepresentation!, forType: .tiff)
        return board
    }

    /// A PNG dragged out of Finder: a file URL, no bitmap. This is the case `.fileURL` keeps
    /// admitting even at a refusing host, so it is the one the operation rule has to answer for.
    private func draggedImageFile(_ name: String, filename: String) throws -> (NSPasteboard, URL) {
        let board = dropPasteboard(name)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        let rep = NSBitmapImageRep(data: makeImage().tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        _ = board.writeObjects([url as NSURL])
        return (board, url)
    }

    private func makeTextView(allowsImages: Bool) -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 900),
            textContainer: container
        )
        textView.allowsMarkdownImageInsertion = allowsImages
        return textView
    }

    // MARK: - The verdict the pointer draws

    @Test func anAcceptingHostClaimsADraggedBitmapAsACopy() {
        let textView = makeTextView(allowsImages: true)
        #expect(textView.markdownImageDropOperation(for: draggedBitmap("accept.bitmap")) == .copy)
    }

    /// The defect, stated the way the user met it: same payload, same editor, at the host that has
    /// already dropped its photo button and its `/image` entry.
    @Test func aRefusingHostDoesNotClaimADraggedBitmap() {
        let textView = makeTextView(allowsImages: false)
        #expect(textView.markdownImageDropOperation(for: draggedBitmap("refuse.bitmap")) == nil)
    }

    @Test func aRefusingHostDoesNotClaimADraggedImageFileEither() throws {
        let (board, url) = try draggedImageFile("refuse.file", filename: "drop-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let accepting = makeTextView(allowsImages: true)
        let refusing = makeTextView(allowsImages: false)
        // Both halves together: the file case is only interesting because the accepting host does
        // claim it, which is what makes the refusing host's `nil` a decision rather than a gap.
        #expect(accepting.markdownImageDropOperation(for: board) == .copy)
        #expect(refusing.markdownImageDropOperation(for: board) == nil)
    }

    /// A drag with no image in it was never this view's to claim, at either host — `super` answers,
    /// exactly as before. Without this the fix could have been "claim nothing", which would take
    /// ordinary text drops with it.
    @Test func aDragWithNoImagePayloadIsLeftToAppKitAtBothHosts() {
        let board = dropPasteboard("textonly")
        board.setString("just words", forType: .string)
        #expect(makeTextView(allowsImages: true).markdownImageDropOperation(for: board) == nil)
        #expect(makeTextView(allowsImages: false).markdownImageDropOperation(for: board) == nil)
    }

    /// Hosts that never mention the flag are untouched — every note, document and task-notes editor
    /// in the app, which is all but two of them.
    @Test func aTextViewAcceptsImagesUntilAHostSaysOtherwise() {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 900),
            textContainer: container
        )
        #expect(textView.allowsMarkdownImageInsertion)
    }

    // MARK: - The types AppKit is told about

    @Test func anAcceptingHostRegistersTheImageDragTypes() {
        let textView = makeTextView(allowsImages: true)
        textView.registerMarkdownDraggedTypes()
        #expect(textView.registeredDraggedTypes.contains(.tiff))
        #expect(textView.registeredDraggedTypes.contains(.png))
        #expect(textView.registeredDraggedTypes.contains(.fileURL))
    }

    /// The second half of the fix: a refusing host stops advertising the bitmap types at all, so a
    /// dragged screenshot never reaches `draggingEntered` and the pointer shows the no-drop cursor
    /// rather than a copy badge that gets withdrawn.
    ///
    /// `.fileURL` deliberately stays on both paths. It is not image-specific, and the operation
    /// rule above already answers for the file case.
    @Test func aRefusingHostRegistersNoBitmapDragTypes() {
        let textView = makeTextView(allowsImages: false)
        textView.registerMarkdownDraggedTypes()
        #expect(textView.registeredDraggedTypes.contains(.tiff) == false)
        #expect(textView.registeredDraggedTypes.contains(.png) == false)
        #expect(textView.registeredDraggedTypes.contains(.fileURL))
    }

    // MARK: - Whether Cadence's registration can take a drag type away (T-511)

    /// The editor's text view, in a real `NSWindow`, because **the offscreen fixture above cannot
    /// see the behaviour these three tests are about** and that is the whole reason [[T-511]] sat
    /// open. With no window, `NSTextView` never runs its own `updateDragTypeRegistration`, so
    /// every measurement taken there shows only what Cadence registered and nothing about what
    /// AppKit would have.
    ///
    /// `defer: true` and never ordered on screen: nothing here needs the window drawn, and the
    /// suite must not flash blank windows over whatever the person running it is doing.
    private func makeWindowedTextView(allowsImages: Bool) -> (NSWindow, CadenceTextView) {
        let textView = makeTextView(allowsImages: allowsImages)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentView = textView
        return (window, textView)
    }

    /// **`registerForDraggedTypes` on an `NSTextView` unions into the list. It cannot remove a
    /// type.** This is the fact [[T-511]] turned on, and it had never been measured either way.
    ///
    /// [[T-495]] asked whether `registerMarkdownDraggedTypes` clobbers the text types AppKit
    /// would otherwise accept, which would mean a plain-text drag no longer reaches the note
    /// editor at all. It disproved the *mechanism* offscreen — with registration never called the
    /// list is empty at every step, so there was nothing to displace — but an empty list is also
    /// what you would see if the fixture simply never ran AppKit's own registration, and
    /// [[T-551]] found exactly that when its re-measurement of the "AppKit unions" clause gave 3
    /// where the original said 22. That left the direction of the operation unknown, which is
    /// what made T-511 a live question rather than a formality.
    ///
    /// Measured here, in a window: register a text type, then run the markdown registration over
    /// it, three times, the way `updateNSView` does on every SwiftUI pass. The text type survives
    /// all three. AppKit's `unregisterDraggedTypes` is the only thing measured to clear the list,
    /// and nothing in this app reaches for it.
    @Test func theMarkdownRegistrationCannotRemoveATextTypeAlreadyRegistered() {
        let (window, textView) = makeWindowedTextView(allowsImages: true)
        defer { window.contentView = nil }

        textView.registerForDraggedTypes([.string])
        #expect(textView.registeredDraggedTypes.contains(.string))

        textView.registerMarkdownDraggedTypes()
        textView.registerMarkdownDraggedTypes()
        textView.registerMarkdownDraggedTypes()

        #expect(textView.registeredDraggedTypes.contains(.string))
        #expect(textView.registeredDraggedTypes.contains(.tiff))
        #expect(textView.registeredDraggedTypes.contains(.fileURL))
    }

    /// The refusing host takes the same path, and it matters more there: its registration is the
    /// *narrowest* one in the app (`.fileURL` alone), so if any call were going to replace a list
    /// rather than add to it, this is the one that would.
    @Test func theRefusingHostsNarrowRegistrationCannotRemoveATextTypeEither() {
        let (window, textView) = makeWindowedTextView(allowsImages: false)
        defer { window.contentView = nil }

        textView.registerForDraggedTypes([.string])
        textView.registerMarkdownDraggedTypes()

        #expect(textView.registeredDraggedTypes.contains(.string))
        #expect(textView.registeredDraggedTypes.contains(.fileURL))
        // T-478 still holds for what *Cadence* advertises: the bitmap types are not added here.
        #expect(textView.registeredDraggedTypes.contains(.tiff) == false)
        #expect(textView.registeredDraggedTypes.contains(.png) == false)
    }

    /// And the union runs the other way too: whatever AppKit registers for itself survives the
    /// markdown registration that follows it.
    ///
    /// `isEditable` is toggled because that is the documented trigger for
    /// `updateDragTypeRegistration`, and — measured — it is the *only* thing that fires it here.
    /// Adding the view to a window does not, ordering that window on screen does not, making the
    /// view first responder does not, and neither does a run loop spun for a second and a half
    /// with a `display()` in the middle. That last point is why this test asserts a *subset*
    /// rather than a count: what AppKit registers, and when, is AppKit's business, and pinning its
    /// list would be pinning stock `NSTextView` behaviour rather than Cadence's.
    @Test func appKitsOwnDragTypesSurviveTheMarkdownRegistration() {
        let (window, textView) = makeWindowedTextView(allowsImages: true)
        defer { window.contentView = nil }

        textView.isEditable = false
        textView.isEditable = true
        let afterAppKit = Set(textView.registeredDraggedTypes)
        // Non-vacuity: the toggle really did make AppKit register something of its own, so the
        // subset assertion below is not trivially true of an empty set.
        #expect(afterAppKit.count > 3)

        textView.registerMarkdownDraggedTypes()

        #expect(afterAppKit.isSubset(of: Set(textView.registeredDraggedTypes)))
    }

    /// **The clause [[T-551]] could not settle, settled: the offscreen `3` was the fixture, not
    /// the framework.**
    ///
    /// [[T-495]] closed on three measurements, and one of them —"AppKit's own re-registration
    /// unions rather than replaces; toggling `isEditable` yields 22 types, `acceptableDragTypes`'
    /// 19 plus Cadence's 3" — did not reproduce when T-551 re-measured it: **3** after the toggle,
    /// **3** after `isRichText`, **3** after `importsGraphics`. T-551 filed that as *unverified*
    /// rather than false on the suspicion that a view with no window never runs AppKit's
    /// `updateDragTypeRegistration`, and the suspicion was right.
    ///
    /// **Measured 2026-09-27 on Xcode 27**, both arms in one run, the windowed one built exactly
    /// as `makeWindowedTextView` builds it: offscreen stays at **3** through every step, and in a
    /// window the `isEditable` toggle brings **19** of AppKit's own — `NSStringPboardType`, both
    /// RTF flavours, the filenames and URL types — which the markdown registration then adds its
    /// three to for **22**. The original number, to the digit, and a stock `NSTextView` beside it
    /// behaves identically, so none of this is `CadenceTextView`'s. Setting `contentView` alone
    /// does not fire it and `orderFront` does not either; the toggle is what does.
    ///
    /// **None of those counts is asserted, deliberately** (T-1279, T-1296, and the worked example
    /// in `CadenceStartupRecoveryReasonTests`). CI runs Xcode 26 and this Mac runs 27, AppKit 27
    /// moved `NSTextView` selection onto `NSTextSelectionManager`, and *what* stock `NSTextView`
    /// registers for, and when, is AppKit's business in either. What is asserted is ours and holds
    /// whatever the framework's list turns out to be: the editor's own three types are advertised
    /// in a window and out of one, the markdown registration is additive from both sides, and a
    /// window never advertises less than the same view offscreen. The floor that says AppKit
    /// really did contribute is `appKitsOwnDragTypesSurviveTheMarkdownRegistration` above, which
    /// has been green in CI on Xcode 26 since `3eb023d` — which is what makes this a framework
    /// behaviour rather than a 27 one.
    @Test func theWindowIsWhatLetsAppKitRegisterItsOwnDragTypes() {
        let cadencesOwn: Set<NSPasteboard.PasteboardType> = [.fileURL, .tiff, .png]

        let offscreen = makeTextView(allowsImages: true)
        offscreen.isEditable = false
        offscreen.isEditable = true
        offscreen.registerMarkdownDraggedTypes()
        let offscreenTypes = Set(offscreen.registeredDraggedTypes)

        let (window, windowed) = makeWindowedTextView(allowsImages: true)
        defer { window.contentView = nil }
        windowed.isEditable = false
        windowed.isEditable = true
        let appKitsOwn = Set(windowed.registeredDraggedTypes)
        windowed.registerMarkdownDraggedTypes()
        let windowedTypes = Set(windowed.registeredDraggedTypes)

        // Ours, and the same on both arms: the host's image policy decides what Cadence
        // advertises, and a window has nothing to do with it.
        #expect(cadencesOwn.isSubset(of: offscreenTypes))
        #expect(cadencesOwn.isSubset(of: windowedTypes))

        // Additive from both sides, which is the mechanism T-495 and T-511 both turn on.
        #expect(appKitsOwn.isSubset(of: windowedTypes))
        #expect(offscreenTypes.count <= windowedTypes.count)

        // And the consequence, stated only where the framework did register for itself: whatever
        // AppKit brings, it brings text. That is [[T-511]]'s question — whether a plain-text drag
        // is advertised to the note editor at all — and the answer is yes, by AppKit's own
        // registration rather than by anything Cadence does. Conditional because a runtime that
        // registered nothing here would be a framework difference, not a defect in this app.
        if !appKitsOwn.isEmpty {
            #expect(
                appKitsOwn.contains(where: Self.isTextDragType),
                """
                AppKit registered \(appKitsOwn.count) drag types of its own and not one of them \
                was text: \(appKitsOwn.map(\.rawValue).sorted().joined(separator: ", "))
                """
            )
        }
    }

    /// Text drag flavours under both their modern UTI names and the NeXT/Apple legacy ones AppKit
    /// still registers — `registeredDraggedTypes` reports the legacy spellings, so
    /// `contains(.string)` alone would read false over a list that plainly carries text.
    private static func isTextDragType(_ type: NSPasteboard.PasteboardType) -> Bool {
        [
            "public.utf8-plain-text", "public.plain-text", "public.text",
            "NSStringPboardType",
            "public.rtf", "NeXT Rich Text Format v1.0 pasteboard type",
            "public.rtfd", "NeXT RTFD pasteboard type"
        ].contains(type.rawValue)
    }

    // MARK: - The wire from the host down to the view

    /// `configure(_:context:)` is a `NSViewRepresentable` update pass; nothing headless can run it.
    /// This is the one link in the chain that has to be read rather than exercised, and without it
    /// every test above could pass on a text view no host ever sets the flag on.
    @Test func theRepresentableThreadsTheHostsImagePolicyIntoTheTextView() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorView.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "configure", in: source))
        #expect(body.contains("textView.allowsMarkdownImageInsertion = allowsImageInsertion"))
        #expect(body.contains("textView.registerMarkdownDraggedTypes()"))
        // The unconditional registration is gone, not merely shadowed by a later call.
        #expect(CadenceSourceScan.matchCount("registerForDraggedTypes", in: body) == 0)
    }

    /// And that the flag arrives from the host rather than defaulting inside the representable.
    @Test func theEditorHandsItsImagePolicyToTheRepresentable() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorView.swift")
        )
        #expect(source.contains("allowsImageInsertion: allowsImageInsertion"))
    }
}
#endif
