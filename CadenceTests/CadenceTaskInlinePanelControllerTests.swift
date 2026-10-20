import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **[[T-1481]]'s iOS half: the task panel opens in the note's text flow.**
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and this target builds for macOS, so there is no
/// `UITextView` to drive. The decisions the iOS editor makes are therefore platform-neutral
/// (`CadenceTaskInlinePanelReservation`, `CadenceTaskInlinePanelController`) and measured here on
/// a real TextKit 1 stack — `NSLayoutManager` is what the iOS editor builds too
/// (`iOSMarkdownTextView.init`) — over a storage spelled the way `applyTaskEmbedBlock` spells an
/// embed. The hosting itself is UIKit and is pinned by the scans at the bottom.
@MainActor
struct CadenceTaskInlinePanelControllerTests {
    nonisolated private static let embedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    nonisolated private static let otherID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
    nonisolated private static let panelHeight: CGFloat = 300
    /// `applyTaskEmbedBlock`'s reservation for an 80pt card: the canvas plus 12.
    nonisolated private static let cardHeight: CGFloat = 80

    /// A stand-in for the hosted view, so detaching is observable.
    final class FakeHost {
        var isAttached = true
    }

    private static func embedInfo(id: UUID) -> MarkdownTaskEmbedLayoutInfo {
        MarkdownTaskEmbedLayoutInfo(task: MarkdownTaskEmbedRenderInfo(
            id: id,
            title: "Task",
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            sectionName: "",
            containerName: "",
            containerColorHex: Theme.blueHex,
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: []
        ))
    }

    private static let lines = [
        "Prose above the embed.",
        "",
        "[[task:11111111-2222-3333-4444-555555555555|First]]",
        "",
        "Prose below the embed.",
        "",
        "[[task:99999999-2222-3333-4444-555555555555|Second]]",
        "",
        "Prose at the end."
    ]

    /// The storage as the iOS styler leaves it: each embed line's first character carries the
    /// embed, and its paragraph reserves the card's height.
    private func makeStorage() -> NSTextStorage {
        let text = Self.lines.joined(separator: "\n")
        let storage = NSTextStorage(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 17)]
        )
        let ns = text as NSString
        for (id, needle) in [(Self.embedID, "[[task:1111"), (Self.otherID, "[[task:9999")] {
            let start = ns.range(of: needle).location
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            let content = NSRange(location: line.location, length: line.length - 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = Self.cardHeight + 12
            paragraph.maximumLineHeight = Self.cardHeight + 12
            paragraph.lineBreakMode = .byClipping
            paragraph.paragraphSpacingBefore = 7
            paragraph.paragraphSpacing = 5
            storage.addAttribute(.paragraphStyle, value: paragraph, range: content)
            storage.addAttribute(.cadenceMarkdownTaskEmbed, value: Self.embedInfo(id: id), range: NSRange(location: start, length: 1))
        }
        return storage
    }

    /// Lays `storage` out at a phone's width and returns the line fragment holding `needle`.
    private func fragment(of needle: String, in storage: NSTextStorage) throws -> CGRect {
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        defer { storage.removeLayoutManager(layoutManager) }
        layoutManager.ensureLayout(for: container)
        let range = (storage.string as NSString).range(of: needle)
        try #require(range.location != NSNotFound)
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    private func makeController() -> CadenceTaskInlinePanelController<FakeHost> {
        CadenceTaskInlinePanelController { $0.isAttached = false }
    }

    @discardableResult
    private func open(_ controller: CadenceTaskInlinePanelController<FakeHost>, id: UUID = embedID) -> FakeHost? {
        var made: FakeHost?
        controller.present(taskID: id) {
            let host = FakeHost()
            made = host
            return (host, Self.panelHeight)
        }
        return made
    }

    // MARK: - Decision 1: the note reflows, the task stays put

    @Test func theReservedParagraphPushesTheNoteDownAndLeavesTheCardWhereItWas() throws {
        let plain = makeStorage()
        let cardBefore = try fragment(of: "[[task:1111", in: plain)
        let belowBefore = try fragment(of: "Prose below", in: plain)
        let aboveBefore = try fragment(of: "Prose above", in: plain)

        let controller = makeController()
        open(controller)
        let storage = makeStorage()
        let spacing = try #require(controller.applyReservation(to: storage))

        #expect(spacing == CadenceTaskInlinePanelReservation.reservedSpacing(panelHeight: Self.panelHeight))
        #expect(try fragment(of: "[[task:1111", in: storage).minY == cardBefore.minY)
        #expect(try fragment(of: "Prose above", in: storage).minY == aboveBefore.minY)
        #expect(try fragment(of: "Prose below", in: storage).minY - belowBefore.minY == spacing)
    }

    /// TextKit counts paragraph spacing inside the fragment, and the iOS canvas is centred in the
    /// fragment, so the card would sink by half the reservation without the offset correction.
    @Test func theCentredCardDoesNotSinkIntoTheRoomReservedUnderIt() throws {
        let before = try fragment(of: "[[task:1111", in: makeStorage())
        let controller = makeController()
        open(controller)
        let storage = makeStorage()
        let spacing = try #require(controller.applyReservation(to: storage))
        let after = try fragment(of: "[[task:1111", in: storage)

        #expect(after.height - before.height == spacing)
        // `iOSMarkdownBlockCanvas.blockRect`'s centring, with the editor's correction applied.
        func cardTop(_ fragment: CGRect, yOffset: CGFloat) -> CGFloat {
            fragment.minY + max(0, (fragment.height - Self.cardHeight) / 2) + yOffset
        }
        let corrected = CadenceTaskInlinePanelReservation.centredCanvasOffset(0, reservedSpacing: spacing)
        #expect(cardTop(after, yOffset: corrected) == cardTop(before, yOffset: 0))
        #expect(cardTop(after, yOffset: 0) != cardTop(before, yOffset: 0))
    }

    @Test func onlyTheOpenTasksParagraphGrowsWhicheverEmbedItIs() throws {
        let controller = makeController()
        open(controller)
        #expect(controller.reservedSpacing(forTaskID: Self.otherID) == 0)
        #expect(controller.reservedSpacing(forTaskID: Self.embedID) > Self.panelHeight)

        let plain = makeStorage()
        let storage = makeStorage()
        controller.applyReservation(to: storage)
        // The second embed's own paragraph is untouched: it moves down by the first one's room,
        // and the line under it by exactly the same amount, not by twice that.
        let spacing = controller.reservedSpacing(forTaskID: Self.embedID)
        #expect(try fragment(of: "[[task:9999", in: storage).minY - fragment(of: "[[task:9999", in: plain).minY == spacing)
        #expect(try fragment(of: "Prose at the end", in: storage).minY - fragment(of: "Prose at the end", in: plain).minY == spacing)

        // And the other way round: the second task's panel opens under the second card, so the
        // prose between the two embeds stays where it was.
        let second = makeController()
        open(second, id: Self.otherID)
        let reservedUnderSecond = makeStorage()
        let secondSpacing = try #require(second.applyReservation(to: reservedUnderSecond))
        #expect(try fragment(of: "Prose below", in: reservedUnderSecond).minY == fragment(of: "Prose below", in: plain).minY)
        #expect(try fragment(of: "Prose at the end", in: reservedUnderSecond).minY
            - fragment(of: "Prose at the end", in: plain).minY == secondSpacing)
    }

    @Test func aTallerPanelReservesMoreRoomAndAReportForAnotherTaskChangesNothing() throws {
        let controller = makeController()
        open(controller)
        #expect(controller.updateHeight(450, for: Self.embedID))
        #expect(controller.reservedSpacing(forTaskID: Self.embedID)
            == CadenceTaskInlinePanelReservation.reservedSpacing(panelHeight: 450))
        #expect(!controller.updateHeight(900, for: Self.otherID))
        #expect(!controller.updateHeight(449.8, for: Self.embedID))
        #expect(controller.session?.height == 450)
    }

    @Test func thePanelSitsUnderItsCardAtTheNotesWidthCappedOnAWideNote() {
        let card = CGRect(x: 20, y: 100, width: 300, height: 80)
        let phone = CadenceTaskInlinePanelReservation.panelFrame(cardRect: card, contentWidth: 343, height: 300)
        #expect(phone.minX == card.minX)
        #expect(phone.minY == card.maxY + CadenceTaskInlinePanelReservation.gap)
        #expect(phone.width == 343)
        #expect(phone.maxY + CadenceTaskInlinePanelReservation.gap
            == card.maxY + CadenceTaskInlinePanelReservation.reservedSpacing(panelHeight: 300))
        let pad = CadenceTaskInlinePanelReservation.panelFrame(cardRect: card, contentWidth: 900, height: 300)
        #expect(pad.width == CadenceTaskInlinePanelReservation.maxWidth)
    }

    // MARK: - Decision 2: dismissal

    @Test func closingDetachesTheViewAndGivesTheSpaceBack() throws {
        let belowBefore = try fragment(of: "Prose below", in: makeStorage())
        let controller = makeController()
        let host = try #require(open(controller))

        #expect(controller.close())

        #expect(controller.openTaskID == nil)
        #expect(!host.isAttached)
        let storage = makeStorage()
        #expect(controller.applyReservation(to: storage) == nil)
        #expect(try fragment(of: "Prose below", in: storage).minY == belowBefore.minY)
        #expect(!controller.close())
    }

    @Test func openingAnotherTasksPanelReplacesTheFirstAndAskingAgainKeepsIt() throws {
        let controller = makeController()
        let first = try #require(open(controller))

        let second = try #require(open(controller, id: Self.otherID))

        #expect(controller.openTaskID == Self.otherID)
        #expect(!first.isAttached)
        #expect(second.isAttached)
        #expect(controller.reservedSpacing(forTaskID: Self.embedID) == 0)
        // Asking again for the open task keeps the same view, and with it the draft.
        #expect(open(controller, id: Self.otherID) == nil)
        #expect(controller.host === second)
        #expect(second.isAttached)
    }

    @Test func aStylingPassThatFindsTheEmbedGoneClosesThePanel() throws {
        let controller = makeController()
        let host = try #require(open(controller))

        let edited = NSMutableAttributedString(string: "Prose above the embed.\n\nProse below the embed.\n")
        #expect(controller.applyReservation(to: edited) == nil)

        #expect(controller.openTaskID == nil)
        #expect(!host.isAttached)
    }

    // MARK: - The iOS wiring, scanned (it is `#if os(iOS)`)

    @Test func theIOSEditorReservesAfterEveryStylingPassAndRoutesTheCardTap() throws {
        let editor = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditor.swift"))
        let style = try #require(CadenceSourceScan.functionBody(named: "applyMarkdownStyle", in: editor))
        let landed = try #require(style.range(of: "storage.setAttributedString(styled)"))
        let reserved = try #require(style.range(of: "applyInlineTaskPanelReservation(to: storage)"))
        #expect(landed.upperBound <= reserved.lowerBound)
        #expect(style.contains("positionInlineTaskPanel(in: textView)"))

        let hit = try #require(CadenceSourceScan.functionBody(named: "handleTaskEmbedHit", in: editor))
        let inline = try #require(hit.range(of: "presentInlineTaskPanel(taskID: hit.task.id"))
        let sheet = try #require(hit.range(of: "parent.onOpenEmbeddedTask?(hit.task.id)"))
        #expect(inline.upperBound <= sheet.lowerBound, "the inline panel is tried first, the inspector is the fallback")
    }

    @Test func theIOSHostRemovesItsViewAndKeepsTheCardCentred() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownInlineTaskPanelSupport.swift")
        let support = CadenceSourceScan.codeOnly(raw)
        #expect(support != raw && support.count == raw.count)
        let factory = try #require(CadenceSourceScan.functionBody(named: "makeInlineTaskPanelController", in: support))
        #expect(factory.contains("host.view.removeFromSuperview()"))
        let reservation = try #require(CadenceSourceScan.functionBody(named: "applyInlineTaskPanelReservation", in: support))
        #expect(reservation.contains("inlineTaskPanel.applyReservation(to: storage)"))
        #expect(reservation.contains("CadenceTaskInlinePanelReservation.centredCanvasOffset("))
        let content = try #require(CadenceSourceScan.functionBody(named: "content", in: support))
        #expect(content.contains("CadenceTaskInlinePanel(task: task, onClose: close, onSaved: onSaved)"))

        let textView = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownTextView.swift"))
        let gate = try #require(CadenceSourceScan.functionBody(named: "gestureRecognizerShouldBegin", in: textView))
        #expect(gate.contains("panel.frame.contains(gestureRecognizer.location(in: self))"))
        #expect(gate.contains("gestureRecognizer !== panGestureRecognizer"))
    }

    /// The call site this whole slice exists for: the note editor hands the editor a panel factory,
    /// so a card tap opens the shared panel in the note instead of `iOSTaskInspectorSheet`.
    ///
    /// Scanned rather than driven for the reason named at the top of this file, and asserted on the
    /// *bound* closure as well as the argument — passing `inlineTaskPanelContent:` while the closure
    /// returned `nil` would wire the parameter up and still open the sheet every time.
    @Test func theIOSNoteSurfaceHandsTheEditorTheInlinePanelInsteadOfTheInspectorSheet() throws {
        let surface = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        )
        let editorSurface = try #require(
            CadenceSourceScan.declarationBody("private var editorSurface: some View", in: surface)
        )
        #expect(editorSurface.contains("inlineTaskPanelContent: inlineTaskPanelContent"))

        let factory = try #require(
            CadenceSourceScan.declarationBody(
                "let inlineTaskPanelContent: iOSMarkdownInlineTaskPanelContent =",
                in: editorSurface
            )
        )
        #expect(factory.contains("embeddedTask(id: taskID)"))
        #expect(factory.contains("iOSMarkdownInlineTaskPanel.content("))
        #expect(factory.contains("reconcileEmbeddedTaskReferenceTitles()"))
        // The note's text has to be in the store before the panel writes to it.
        let resolved = try #require(factory.range(of: "embeddedTask(id: taskID)"))
        let committed = try #require(factory.range(of: "commitDraftImmediately()"))
        let built = try #require(factory.range(of: "iOSMarkdownInlineTaskPanel.content("))
        #expect(resolved.upperBound <= committed.lowerBound)
        #expect(committed.upperBound <= built.lowerBound)

        // The inspector sheet stays, as the fallback for an embed whose task is gone.
        #expect(surface.contains("iOSTaskInspectorSheet(task: task)"))
        #expect(surface.contains("selectedEmbeddedTask = task"))
    }
    // MARK: - [[T-3243]]: the keyboard, Escape, and the rule that was spelled twice

    /// **The panel's Save and Cancel, under the keyboard** ([[T-3243]] (1)).
    ///
    /// Reproduced on `Cadence-iPadPro11` before this existed: focusing the panel's title field
    /// raised the keyboard over the panel's action row, and the note did not move. The panel is a
    /// subview of the note's `UITextView`, which SwiftUI's keyboard avoidance does not reach.
    ///
    /// Everything below is in the note's content coordinates, y growing downward, and
    /// `visibleRect` is what the keyboard has left of the note.
    @Test func theNoteScrollsTheFocusedPanelFieldAndItsActionsClearOfTheKeyboard() {
        // The bug itself: the field reads, the actions 100pt below the keyboard's top do not.
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: 100, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: 60, width: 300, height: 340),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 300)
            ) == 100
        )
        // The field itself under the keyboard: it comes up with the actions.
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: 350, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: 60, width: 300, height: 340),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 300)
            ) == 100
        )
    }

    /// The field wins when the panel is too tall for both to fit: someone typing has to see what
    /// they are typing, even at the price of Save staying hidden.
    @Test func aPanelTooTallForTheRemainingSpaceKeepsTheFocusedFieldRatherThanItsActions() {
        // Field at the top, actions 1000pt down: scrolling to the actions would take the field
        // off the top, so nothing moves.
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: 10, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: 0, width: 300, height: 1000),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 300)
            ) == 0
        )
        // Field just below the keyboard's top, actions far below: the field alone comes up.
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: 290, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: 0, width: 300, height: 900),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 300)
            ) == 20
        )
    }

    @Test func aPanelFieldAlreadyAboveTheKeyboardDoesNotMoveTheNote() {
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: 50, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: 40, width: 300, height: 160),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 300)
            ) == 0
        )
        // A keyboard that has taken the whole note leaves nothing to reveal into.
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: 50, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: 40, width: 300, height: 160),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 0)
            ) == 0
        )
    }

    /// Scrolled the other way: a field above the top of what is left comes back down, and that
    /// beats the actions below it.
    @Test func aPanelFieldScrolledOffTheTopComesBackBeforeTheActionsDo() {
        #expect(
            CadenceTaskInlinePanelReservation.keyboardRevealOffset(
                focusedRect: CGRect(x: 0, y: -40, width: 300, height: 30),
                panelFrame: CGRect(x: 0, y: -60, width: 300, height: 500),
                visibleRect: CGRect(x: 0, y: 0, width: 300, height: 300)
            ) == -40
        )
    }

    /// **[[T-3243]] (3): one rule, spelled once.** The Mac enum kept its own `gap`, `maxWidth`,
    /// `minWidth`, `reservedSpacing`, `panelWidth` and `panelFrame` after the shared reservation
    /// grew the same six.
    ///
    /// Which of the two widths was right is settled here: the Mac's `-16`. iOS hands the shared
    /// rule a width already net of its insets; AppKit's text container width is not, and the card
    /// is drawn `MarkdownTaskEmbedDrawing.cardHorizontalInset` in on each side, so taking those
    /// off is what makes the panel the width of the card it hangs under.
    @Test func theMacPanelLayoutIsTheSharedRuleAtTheCardsOwnWidth() throws {
        #expect(MarkdownTaskEmbedDrawing.cardHorizontalInset == 8)
        #expect(MarkdownInlineTaskPanelLayout.contentWidth(textContainerWidth: 300) == 284)
        #expect(MarkdownInlineTaskPanelLayout.panelWidth(textContainerWidth: 300) == 284)
        // Capped and floored by the shared rule, not by a second copy of it.
        #expect(MarkdownInlineTaskPanelLayout.panelWidth(textContainerWidth: 1200) == 460)
        #expect(MarkdownInlineTaskPanelLayout.panelWidth(textContainerWidth: 100) == 160)
        #expect(MarkdownInlineTaskPanelLayout.reservedSpacing(panelHeight: 250) == 266)
        #expect(
            MarkdownInlineTaskPanelLayout.panelFrame(
                cardRect: NSRect(x: 8, y: 40, width: 200, height: 80),
                textContainerWidth: 300,
                height: 250
            ) == NSRect(x: 8, y: 128, width: 284, height: 250)
        )
        // Never wider than the card above it is allowed to be, which is the point of the 16.
        let widestCard = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            textContainerWidth: 300,
            task: Self.embedInfo(id: Self.embedID).task
        )
        #expect(MarkdownInlineTaskPanelLayout.panelWidth(textContainerWidth: 300) >= widestCard.width)

        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownInlineTaskPanelSupport.swift")
        )
        let layout = try #require(CadenceSourceScan.declarationBody("enum MarkdownInlineTaskPanelLayout", in: mac))
        // The second copy is gone, not merely unused.
        #expect(!layout.contains("static let gap"))
        #expect(!layout.contains("static let maxWidth"))
        #expect(!layout.contains("static let minWidth"))
        #expect(layout.contains("CadenceTaskInlinePanelReservation.reservedSpacing("))
        #expect(layout.contains("CadenceTaskInlinePanelReservation.panelFrame("))
        #expect(layout.contains("CadenceTaskInlinePanelReservation.panelWidth("))
    }

    /// **[[T-3243]] (2): Escape, from the panel and from the note text** — the Mac rule, which iOS
    /// had on neither side. Scanned for the reason named at the top of this file, and because a
    /// hardware-key press is not something this repo's simulator tooling can inject.
    @Test func escapeCancelsTheInlinePanelFromInsideItAndFromTheNoteText() throws {
        let support = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownInlineTaskPanelSupport.swift")
        )
        let host = try #require(
            CadenceSourceScan.declarationBody("final class iOSMarkdownInlineTaskPanelHost", in: support)
        )
        #expect(host.contains("UIKeyCommand.inputEscape"))
        #expect(host.contains("onCancelKey?()"))

        let present = try #require(CadenceSourceScan.functionBody(named: "presentInlineTaskPanel", in: support))
        #expect(present.contains("host.onCancelKey = close"))
        #expect(present.contains("markdownTextView.inlineTaskPanelCancelHandler = close"))
        // Closing takes the key away again, so Escape is offered only while there is a panel.
        let made = try #require(CadenceSourceScan.functionBody(named: "makeInlineTaskPanelController", in: support))
        #expect(made.contains("inlineTaskPanelCancelHandler = nil"))

        let textView = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownTextView.swift")
        )
        let offered = try #require(
            CadenceSourceScan.declarationBody("private var inlineTaskPanelKeyCommands: [UIKeyCommand]", in: textView)
        )
        #expect(offered.contains("UIKeyCommand.inputEscape"))
        #expect(offered.contains("inlineTaskPanelCancelHandler != nil"))
        let keyCommands = try #require(
            CadenceSourceScan.declarationBody("override var keyCommands: [UIKeyCommand]?", in: textView)
        )
        #expect(keyCommands.contains("inlineTaskPanelKeyCommands"))
    }

    /// The UIKit half of the keyboard fix: the host measures, the shared rule decides, the note
    /// scrolls. Without the last of those the first two are a calculation nobody acts on.
    @Test func theIOSHostScrollsTheNoteWithTheSharedKeyboardRule() throws {
        let support = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownInlineTaskPanelSupport.swift")
        )
        let reveal = try #require(
            CadenceSourceScan.functionBody(named: "revealFocusedFieldAboveKeyboard", in: support)
        )
        #expect(reveal.contains("CadenceTaskInlinePanelReservation.keyboardRevealOffset("))
        #expect(reveal.contains("textView.setContentOffset("))
        // Moving between two of the panel's own fields raises no new keyboard, so the keyboard
        // frame notifications alone would miss the second one.
        #expect(support.contains("UIResponder.keyboardWillChangeFrameNotification"))
        #expect(support.contains("UITextField.textDidBeginEditingNotification"))
        #expect(support.contains("UITextView.textDidBeginEditingNotification"))

        // The bottom inset the reveal adds has to come back off, or a closed panel leaves the
        // note scrollable past its own end for the rest of the session.
        let release = try #require(CadenceSourceScan.functionBody(named: "releaseKeyboardInset", in: support))
        #expect(release.contains("applyKeyboardInset(0, to: textView)"))
        let made = try #require(CadenceSourceScan.functionBody(named: "makeInlineTaskPanelController", in: support))
        #expect(made.contains("host.releaseKeyboardInset()"))
        #expect(try #require(CadenceSourceScan.functionBody(named: "keyboardWillHide", in: support))
            .contains("releaseKeyboardInset()"))
    }
}
#endif
