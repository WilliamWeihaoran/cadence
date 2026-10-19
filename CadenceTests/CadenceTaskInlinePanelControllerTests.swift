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
}
#endif
