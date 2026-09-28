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
/// Most of these exercise the decision, not the AppKit plumbing. `NSDraggingInfo` is a protocol
/// with fourteen required members none of which this rule reads, so the rule is split into
/// `markdownImageDropOperation(for:)` and driven with a **private** pasteboard — the same reason
/// `MarkdownImagePasteTests` owns its boards rather than writing `NSPasteboard.general`, which
/// would destroy whatever the person running the suite had copied.
///
/// The last section drives the real `draggingEntered` with a **stood-up `NSDraggingInfo`**
/// ([[T-1418]]). That the protocol cannot be stood up from a unit-test seat is what T-478 and
/// T-1418 both recorded, and it is not so; see `MarkdownDropInfo` at the foot of this file for
/// what makes it a measurement rather than a stand-in.
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

    /// The second half of the fix: a refusing host stops advertising the bitmap types at all, so
    /// nothing Cadence says about this view offers a screenshot to it.
    ///
    /// **This comment used to end "so a dragged screenshot never reaches `draggingEntered`", and
    /// that clause was wrong** ([[T-1418]]). What Cadence registers is not the view's whole list:
    /// in a window AppKit runs its own `updateDragTypeRegistration` and — measured 2026-09-27 on
    /// Xcode 27, at this very host — brings `NeXT TIFF v4.0 pasteboard type` and `Apple PNG
    /// pasteboard type` with it, `importsGraphics` off or not. The screenshot *does* reach
    /// `draggingEntered`; what keeps the copy badge off it is `super` refusing the payload one
    /// layer further in, which is measured by
    /// `aRefusingHostDrawsNoCopyBadgeForADraggedBitmapAndTakesNothingFromIt` below. The assertions
    /// here were always right about what they assert — only the consequence drawn from them was
    /// overstated.
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

    // MARK: - What `super` does with the drag Cadence declines (T-1418)

    /// The editor's view in a window with AppKit's own registration already fired — the only
    /// configuration in which a bitmap drag is offered to a **refusing** host at all, and so the
    /// only one in which the question below exists.
    private func makeWindowedTextViewAppKitHasRegisteredFor(
        allowsImages: Bool
    ) -> (NSWindow, CadenceTextView) {
        let (window, textView) = makeWindowedTextView(allowsImages: allowsImages)
        // The documented trigger for `updateDragTypeRegistration`, and — measured in
        // `theWindowIsWhatLetsAppKitRegisterItsOwnDragTypes` above — the only thing that fires it.
        textView.isEditable = false
        textView.isEditable = true
        textView.registerMarkdownDraggedTypes()
        return (window, textView)
    }

    /// **The residual [[T-1418]] left open, measured: the screenshot reaches `draggingEntered` and
    /// is refused there.**
    ///
    /// [[T-478]] closed on two halves — a refusing host claims no image payload, and it registers
    /// no bitmap type — and the second half was read as meaning the drag never arrives. It does
    /// arrive, by AppKit's own registration. `markdownImageDropOperation(for:)` correctly answers
    /// `nil` (the drag is not Cadence's to claim), `super` answers, and `super` refuses: measured
    /// `[]` here, because `importsGraphics` is off. The pointer therefore shows the no-drop cursor
    /// and the drop takes nothing — T-478's conclusion, reached through a door it did not know
    /// about.
    ///
    /// Both assertions fail only in the direction that is a defect: a `.copy` here is the badge
    /// T-478 removed, and an insertion is a U+FFFC attachment in a text storage whose whole
    /// invariant is that it holds markdown source (`MarkdownImageAssetService`
    /// `.readableImagePasteboardTypes`).
    @Test func aRefusingHostDrawsNoCopyBadgeForADraggedBitmapAndTakesNothingFromIt() {
        let (window, textView) = makeWindowedTextViewAppKitHasRegisteredFor(allowsImages: false)
        defer { window.contentView = nil }
        let board = draggedBitmap("entered.refuse")
        let info = MarkdownDropInfo(pasteboard: board, window: window)

        // A bounded observation and deliberately not an assertion ([[T-1296]]): *whether* AppKit
        // offers a bitmap to a refusing host is AppKit's, it differs between toolchains by
        // construction, and both answers are safe. Measured 2026-09-27 on Xcode 27 it does, as
        // `NeXT TIFF v4.0 pasteboard type` — which is what gives the two assertions below
        // something to refuse. On a runtime that offered nothing, T-478's original sentence would
        // be literally true and this test would be vacuous rather than wrong; the accepting-host
        // test below is the non-vacuity that does not depend on the framework at all.
        let offered = board.availableType(from: textView.registeredDraggedTypes)?.rawValue ?? "nothing"

        #expect(
            textView.draggingEntered(info).contains(.copy) == false,
            """
            A host that has already declined images claimed a dragged bitmap as a copy \
            (AppKit offered it as: \(offered)). That is the badge [[T-478]] removed, back through \
            a door Cadence does not own — the fix is in `draggingEntered`, refusing an image \
            payload outright at a refusing host instead of deferring to `super`.
            """
        )
        #expect(textView.performDragOperation(info) == false)
        #expect(textView.string.isEmpty)
    }

    /// The same drag, the same override, at a host that allows images — and here Cadence's own
    /// rule answers before `super` is ever consulted.
    ///
    /// This is the non-vacuity for the test above and it is entirely ours: if `MarkdownDropInfo`
    /// were not really driving `draggingEntered`, or if `draggingEntered` were not really reading
    /// the host's policy, the two hosts would agree.
    @Test func anAcceptingHostClaimsTheSameDraggedBitmapThroughDraggingEntered() {
        let (window, textView) = makeWindowedTextViewAppKitHasRegisteredFor(allowsImages: true)
        defer { window.contentView = nil }
        let info = MarkdownDropInfo(pasteboard: draggedBitmap("entered.accept"), window: window)
        #expect(textView.draggingEntered(info) == .copy)
    }

    /// **A drag is one gesture, so the editor must give it one answer** ([[T-1491]]).
    ///
    /// AppKit calls `draggingEntered` once, as the pointer crosses into the view, and
    /// `draggingUpdated` on every movement after that. The badge the user actually watches while
    /// they aim the drop is therefore the *second* one's, and until [[T-1491]] the editor
    /// overrode only the first: Cadence's rule answered for one frame and `super` answered for the
    /// rest of the drag. At a host that has declined images that is invisible, because the rule
    /// answers `nil` there and `super` answers both calls; at a host that accepts them it reversed
    /// [[T-478]] — `.copy` on entry, the no-drop cursor from the first movement on, over an editor
    /// that would have taken the picture.
    ///
    /// **The assertion is that the editor's two answers agree, and nothing about what AppKit's
    /// do** ([[T-1296]]). The payload is one the editor's own rule claims, so after the fix both
    /// answers are Cadence's and `super` is consulted by neither — the equality holds by
    /// construction on any toolchain. What `super` would have said is read into the failure
    /// message, which is the only place a framework answer belongs.
    @Test func theEditorsDragAnswerIsTheSameOnEntryAndOnEveryMoveAfterIt() {
        let (window, textView) = makeWindowedTextViewAppKitHasRegisteredFor(allowsImages: true)
        defer { window.contentView = nil }
        let board = draggedBitmap("updated.accept")
        let info = MarkdownDropInfo(pasteboard: board, window: window)

        let entered = textView.draggingEntered(info)
        let updated = textView.draggingUpdated(info)
        let offered = board.availableType(from: textView.registeredDraggedTypes)?.rawValue ?? "nothing"

        #expect(entered == .copy, "the accepting host stopped claiming a dragged bitmap on entry")
        #expect(
            updated == entered,
            """
            The editor claimed this drag as \(entered.rawValue) when the pointer entered and \
            \(updated.rawValue) when it moved (AppKit offered the payload as: \(offered)). \
            `draggingUpdated` draws the badge for all but the first frame of a drag, so the two \
            overrides have to read the same rule — see `markdownImageDropOperation(for:)`.
            """
        )
    }

    /// And the refusing host is untouched by that: it claims neither call, so `super` still
    /// answers both and [[T-1447]]'s deferral is exactly where it was.
    ///
    /// This asserts Cadence's decision — `markdownImageDropOperation(for:)` answers `nil` on both
    /// paths — rather than `super`'s verdict, which is [[T-1418]]'s to observe and not to pin.
    @Test func aRefusingHostStillDefersBothDragAnswersToAppKit() throws {
        let (board, url) = try draggedImageFile("updated.refuse", filename: "drop-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let (window, textView) = makeWindowedTextViewAppKitHasRegisteredFor(allowsImages: false)
        defer { window.contentView = nil }

        #expect(textView.markdownImageDropOperation(for: board) == nil)
        let info = MarkdownDropInfo(pasteboard: board, window: window)
        #expect(textView.draggingUpdated(info) == textView.draggingEntered(info))
    }

    /// The wire, so neither override can quietly stop reading the rule the other one reads.
    ///
    /// Both of the above drive real methods; this is what stops a future edit satisfying them by
    /// making `draggingUpdated` call `draggingEntered` — which would answer `super.draggingEntered`
    /// on the fall-through, and so move the caret as though the pointer had just arrived on every
    /// mouse movement of every text drag.
    @Test func bothDragOverridesReadTheSameRuleAndFallThroughToTheirOwnSuper() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift")
        )
        let entered = try #require(CadenceSourceScan.functionBody(named: "draggingEntered", in: source))
        let updated = try #require(CadenceSourceScan.functionBody(named: "draggingUpdated", in: source))
        #expect(entered.contains("markdownImageDropOperation(for: sender.draggingPasteboard)"))
        #expect(updated.contains("markdownImageDropOperation(for: sender.draggingPasteboard)"))
        #expect(entered.contains("super.draggingEntered(sender)"))
        #expect(updated.contains("super.draggingUpdated(sender)"))
        #expect(updated.contains("super.draggingEntered") == false)
    }

    /// **`importsGraphics` is what refuses the drop, so it is the one line that must never be
    /// written** ([[T-1418]]).
    ///
    /// Measured 2026-09-27 on Xcode 27, one view and one bitmap with that property the only
    /// difference: `draggingEntered` answers `[]` with it off and `.copy` with it on, and the drop
    /// that follows inserts a U+FFFC attachment. Turning it on would therefore re-open [[T-478]]
    /// *and* break the storage invariant in the same line — which is the same conclusion
    /// `MarkdownImageAssetService.readableImagePasteboardTypes` reached from the paste door, for
    /// its own reason.
    ///
    /// The runtime half reads the default rather than pinning it; the sweep is the half that
    /// holds, and it is ours and toolchain-independent. The reader blanks comments, so the doc
    /// comments that name the property — there are four, and they are the reasoning — are not
    /// hits; an assignment is.
    @Test func nothingInTheAppTurnsOnImportsGraphics() throws {
        let (window, textView) = makeWindowedTextViewAppKitHasRegisteredFor(allowsImages: false)
        defer { window.contentView = nil }
        #expect(
            textView.importsGraphics == false,
            "The editor's text view imports graphics: a refused image drop now inserts an attachment."
        )

        let read = CadenceSourceScan.strippedSourceReader()
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            #expect(
                try read(path).contains("importsGraphics") == false,
                "\(path) touches `importsGraphics`; read T-1418 before it lands."
            )
        }
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

/// **A stood-up `NSDraggingInfo`** ([[T-1418]]).
///
/// [[T-478]] and [[T-1418]] both recorded this protocol as out of reach of a unit test — "a dozen
/// members a test would have to stub", "a dozen members a unit test cannot stand up". It has
/// fourteen required members and every one of them is a pasteboard, a window, a point, a number,
/// or a call `NSTextView` does not make on this path.
///
/// What makes it a measurement rather than a stand-in is that AppKit **discriminates** against it:
/// one view, one bitmap, `importsGraphics` the only difference, `draggingEntered` answers `[]` and
/// `.copy` respectively (measured 2026-09-27 on Xcode 27). A framework that ignored this object
/// could not tell those two runs apart.
///
/// It does not make `markdownImageDropOperation(for:)`'s split pointless. That rule reads nothing
/// but the pasteboard, so the tests at the top of the suite still drive it directly; this exists
/// for the half of the path that only `super` can answer.
@MainActor
private final class MarkdownDropInfo: NSObject, NSDraggingInfo {
    private let pasteboard: NSPasteboard
    private let window: NSWindow?

    init(pasteboard: NSPasteboard, window: NSWindow?) {
        self.pasteboard = pasteboard
        self.window = window
    }

    var draggingDestinationWindow: NSWindow? { window }
    /// Everything a real drag source could offer, so the answer under test is the destination's
    /// and never a mask this object narrowed for it.
    var draggingSourceOperationMask: NSDragOperation { [.copy, .move, .link, .generic] }
    var draggingLocation: NSPoint { NSPoint(x: 100, y: 100) }
    var draggedImageLocation: NSPoint { NSPoint(x: 100, y: 100) }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
#endif
