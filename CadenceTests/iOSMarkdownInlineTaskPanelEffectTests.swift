import Foundation
import SwiftUI
import Testing
@testable import Cadence

// [[T-3260]] item (1): the iOS editor's half of [[T-1481]], held by what it DOES.
//
// `CadenceTaskInlinePanelControllerTests` measures the platform-neutral decisions on macOS, and
// until [[T-3244]] the iOS editor's wiring of them could only be read: a scan asserted that
// `applyMarkdownStyle`'s body spelled `storage.setAttributedString(styled)` before
// `applyInlineTaskPanelReservation(to: storage)`, that it named `positionInlineTaskPanel`, and that
// `handleTaskEmbedHit` spelled the inline panel before `parent.onOpenEmbeddedTask`. Text order is
// not behaviour: a reservation written before the styled string landed would be wiped by it, and
// the scan could not see that, only that the characters came in a certain order.
//
// This suite drives a real `iOSMarkdownEditor.Coordinator` over a real `iOSMarkdownTextView` on an
// iOS destination: it styles a note holding a task embed, opens the panel, restyles, and taps the
// card through the same `handleReferenceTap` the editor's recognizer calls. Gated `#if os(iOS)`
// because none of these types exists on the macOS leg.
#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

@Suite @MainActor
struct iOSMarkdownInlineTaskPanelEffectTests {
    nonisolated private static let embedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private static let markdown = [
        "Prose above the embed.",
        "",
        "[[task:11111111-2222-3333-4444-555555555555|First]]",
        "",
        "Prose below the embed."
    ].joined(separator: "\n")

    /// A tap the test places: `handleReferenceTap` reads only `state`, `view` and `location(in:)`.
    private final class ScriptedTap: UITapGestureRecognizer {
        var point: CGPoint = .zero
        override var state: UIGestureRecognizer.State {
            get { .ended }
            set {}
        }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    /// What the editor asked its host for: panels from the factory, inspector sheets from the
    /// fallback.
    private final class Requests {
        var panels: [UUID] = []
        var sheets: [UUID] = []
        /// Every value the editor wrote to its `isFocused` binding — a card hit writes `false`.
        var focusWrites: [Bool] = []
        /// What `onInlineTaskPanelPresenceChange` was told, in order ([[T-3249]] item 3).
        var presence: [Bool] = []
    }

    private struct Fixture {
        let coordinator: iOSMarkdownEditor.Coordinator
        let textView: iOSMarkdownTextView
        let requests: Requests
    }

    private static func renderInfo() -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: embedID,
            title: "First",
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
        )
    }

    /// A styled note with one embed. `givesPanel: false` is a host whose factory has no panel for
    /// the task (it is gone), which is when the editor must fall back to the inspector sheet.
    private func makeFixture(givesPanel: Bool = true) -> Fixture {
        let requests = Requests()
        let editor = iOSMarkdownEditor(
            text: .constant(Self.markdown),
            isFocused: Binding(get: { false }, set: { requests.focusWrites.append($0) }),
            taskEmbeds: [Self.embedID: Self.renderInfo()],
            onOpenEmbeddedTask: { requests.sheets.append($0) },
            inlineTaskPanelContent: { taskID, _ in
                requests.panels.append(taskID)
                return givesPanel ? AnyView(Text("Panel").frame(height: 120)) : nil
            },
            onInlineTaskPanelPresenceChange: { requests.presence.append($0) }
        )
        let coordinator = iOSMarkdownEditor.Coordinator(parent: editor)
        let textView = iOSMarkdownTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 2000)
        textView.text = Self.markdown
        textView.selectedRange = NSRange(location: 0, length: 0)
        coordinator.applyMarkdownStyle(to: textView, text: Self.markdown)
        return Fixture(coordinator: coordinator, textView: textView, requests: requests)
    }

    private func embedLocation(in textView: UITextView) throws -> Int {
        try #require(CadenceTaskInlinePanelReservation.embedLocation(for: Self.embedID, in: textView.textStorage))
    }

    private func embedParagraphSpacing(in textView: UITextView) throws -> CGFloat {
        let location = try embedLocation(in: textView)
        let style = try #require(
            textView.textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacing
    }

    /// The embed's card in text-view coordinates, computed the way the editor paints it.
    private func cardRect(in textView: UITextView) throws -> CGRect {
        let storage = textView.textStorage
        let location = try embedLocation(in: textView)
        let canvas = try #require(
            storage.attribute(.cadenceMarkdownBlockCanvas, at: location, effectiveRange: nil) as? iOSMarkdownBlockCanvas,
            "non-vacuity: the styled embed carries no card canvas"
        )
        let layoutManager = textView.layoutManager
        layoutManager.ensureLayout(for: textView.textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return iOSMarkdownBlockCanvas.blockRect(
            inLineFragment: fragment,
            size: canvas.image.size,
            leadingInset: canvas.leadingInset,
            yOffset: canvas.yOffset
        )
        .offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
    }

    /// A point on the card's body, not on its status box or a subtask's, in text-view coordinates.
    private func cardBodyPoint(in textView: UITextView) throws -> CGPoint {
        let card = try cardRect(in: textView)
        let layout = iOSMarkdownTaskEmbedLayoutInfo(task: Self.renderInfo())
        let candidates = [
            CGPoint(x: card.width * 0.6, y: card.height / 2),
            CGPoint(x: card.width - 16, y: card.height - 8),
            CGPoint(x: card.width / 2, y: card.height - 6)
        ]
        let local = try #require(candidates.first { point in
            if case .card = layout.hitTarget(at: point, maxWidth: textView.markdownContentWidth) { return true }
            return false
        }, "no candidate point lands on the card body")
        return CGPoint(x: card.minX + local.x, y: card.minY + local.y)
    }

    private func tap(_ point: CGPoint, on fixture: Fixture) {
        let recognizer = ScriptedTap(target: nil, action: nil)
        recognizer.point = point
        fixture.textView.addGestureRecognizer(recognizer)
        defer { fixture.textView.removeGestureRecognizer(recognizer) }
        fixture.coordinator.handleReferenceTap(recognizer)
    }

    // MARK: - The styling pass

    /// Retires the scan's "`setAttributedString(styled)` precedes the reservation" pin. A
    /// reservation written before the styled string lands is overwritten by it, so the paragraph
    /// would come back at the styler's own spacing with the panel still open over it.
    @Test func aRestyleUnderAnOpenPanelKeepsThePanelsRoomInTheEmbedsParagraph() throws {
        let fixture = makeFixture()
        let unreserved = try embedParagraphSpacing(in: fixture.textView)

        #expect(fixture.coordinator.presentInlineTaskPanel(
            taskID: Self.embedID,
            in: fixture.textView,
            makeContent: try #require(fixture.coordinator.parent.inlineTaskPanelContent)
        ))
        let reserved = fixture.coordinator.inlineTaskPanel.reservedSpacing(forTaskID: Self.embedID)
        #expect(reserved > 0, "non-vacuity: the open panel reserves no room")

        fixture.coordinator.applyMarkdownStyle(to: fixture.textView, text: Self.markdown)

        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == Self.embedID)
        #expect(try embedParagraphSpacing(in: fixture.textView) == unreserved + reserved)
    }

    /// Retires the scan's "`applyMarkdownStyle` names `positionInlineTaskPanel`" pin. Every restyle
    /// rebuilds the card's geometry; the hosted panel has to be laid back over its room each time.
    @Test func aRestyleLaysTheOpenPanelBackUnderItsCard() throws {
        let fixture = makeFixture()
        #expect(fixture.coordinator.presentInlineTaskPanel(
            taskID: Self.embedID,
            in: fixture.textView,
            makeContent: try #require(fixture.coordinator.parent.inlineTaskPanelContent)
        ))
        let host = try #require(fixture.coordinator.inlineTaskPanel.host)
        let placed = host.view.frame
        let card = try cardRect(in: fixture.textView)
        #expect(placed.minY >= card.maxY, "the panel sits under its card")
        #expect(!host.view.isHidden)

        host.view.frame = .zero
        host.view.isHidden = true
        fixture.coordinator.applyMarkdownStyle(to: fixture.textView, text: Self.markdown)

        #expect(host.view.frame == placed)
        #expect(!host.view.isHidden)
    }

    // MARK: - The card tap

    /// Retires the scan's "the inline panel is tried before the inspector" pin: a tap on the card
    /// opens the panel inside the note, and the sheet is never asked for.
    @Test func aCardTapOpensThePanelInTheNoteAndNeverTheInspectorSheet() throws {
        let fixture = makeFixture()
        let unreserved = try embedParagraphSpacing(in: fixture.textView)

        tap(try cardBodyPoint(in: fixture.textView), on: fixture)

        #expect(fixture.requests.panels == [Self.embedID])
        #expect(fixture.requests.sheets.isEmpty)
        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == Self.embedID)
        let host = try #require(fixture.coordinator.inlineTaskPanel.host)
        #expect(host.view.superview === fixture.textView)
        #expect(try embedParagraphSpacing(in: fixture.textView) > unreserved, "the note made room for the panel")
    }

    /// The other half of the same order: a host with no panel for the task falls back to the sheet.
    @Test func aCardTapWithNoPanelForTheTaskFallsBackToTheInspectorSheet() throws {
        let fixture = makeFixture(givesPanel: false)

        tap(try cardBodyPoint(in: fixture.textView), on: fixture)

        #expect(fixture.requests.panels == [Self.embedID], "non-vacuity: the tap reached the factory")
        #expect(fixture.requests.sheets == [Self.embedID])
        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == nil)
        #expect(!fixture.textView.subviews.contains { $0.accessibilityIdentifier == iOSMarkdownInlineTaskPanel.accessibilityIdentifier })
    }

    // MARK: - [[T-3249]] item 2: the card's touch target

    /// The embed's own line fragment in text-view coordinates — the band a tap would otherwise
    /// drop a caret on the embed line from.
    private func embedFragment(in textView: UITextView) throws -> CGRect {
        let location = try embedLocation(in: textView)
        let layoutManager = textView.layoutManager
        layoutManager.ensureLayout(for: textView.textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            .offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
    }

    /// A tap beside the card, further off than the old 4pt pad but within a fingertip, opens it.
    @Test func aTapBesideTheCardWithinAFingertipOpensThePanel() throws {
        let fixture = makeFixture()
        let card = try cardRect(in: fixture.textView)
        let point = CGPoint(x: card.maxX + 15, y: card.midY)
        #expect(fixture.textView.bounds.contains(point), "non-vacuity: the probe is inside the note")

        tap(point, on: fixture)

        #expect(fixture.requests.panels == [Self.embedID])
        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == Self.embedID)
    }

    /// A tap below the card but still on the embed's own line opens it rather than placing a caret.
    @Test func aTapBelowTheCardOnItsOwnLineOpensThePanel() throws {
        let fixture = makeFixture()
        let card = try cardRect(in: fixture.textView)
        let fragment = try embedFragment(in: fixture.textView)
        let point = CGPoint(x: card.midX, y: fragment.maxY - 1)
        #expect(point.y - card.maxY > 4, "non-vacuity: the probe is past the old 4pt pad")

        tap(point, on: fixture)

        #expect(fixture.requests.panels == [Self.embedID])
    }

    /// The wider target ends where the next line begins: a tap there belongs to that line.
    @Test func aTapOnTheLineBelowTheEmbedNeverOpensThePanel() throws {
        let fixture = makeFixture()
        let card = try cardRect(in: fixture.textView)
        let fragment = try embedFragment(in: fixture.textView)
        let point = CGPoint(x: card.midX, y: fragment.maxY + 2)
        #expect(
            point.y < card.maxY + iOSMarkdownEditor.Coordinator.cardTouchSlop,
            "non-vacuity: an unclipped slop would reach the probe"
        )

        tap(point, on: fixture)

        #expect(fixture.requests.panels.isEmpty)
        #expect(fixture.requests.sheets.isEmpty)
        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == nil)
    }

    /// A touch on the open panel is the panel's, even inside the card's widened target.
    @Test func aTapOnTheOpenPanelIsNeverASecondCardTap() throws {
        let fixture = makeFixture()
        tap(try cardBodyPoint(in: fixture.textView), on: fixture)
        let host = try #require(fixture.coordinator.inlineTaskPanel.host)
        let card = try cardRect(in: fixture.textView)
        let point = CGPoint(x: card.midX, y: host.view.frame.minY + 2)
        #expect(
            point.y < card.maxY + iOSMarkdownEditor.Coordinator.cardTouchSlop,
            "non-vacuity: the probe is inside the card's widened target"
        )
        fixture.requests.focusWrites.removeAll()

        tap(point, on: fixture)

        #expect(fixture.requests.focusWrites.isEmpty, "the card hit path ran for a touch on the panel")
        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == Self.embedID)
    }

    // MARK: - [[T-3249]] item 3: the page's `+` yields to an open panel

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func theHostHearsThePanelOpenAndClose() async throws {
        let fixture = makeFixture()

        tap(try cardBodyPoint(in: fixture.textView), on: fixture)
        await drainMainQueue()
        #expect(fixture.requests.presence == [true])

        fixture.coordinator.applyMarkdownStyle(to: fixture.textView, text: Self.markdown)
        await drainMainQueue()
        #expect(fixture.requests.presence == [true], "a restyle with the panel still open reports nothing")

        fixture.coordinator.closeInlineTaskPanel(in: fixture.textView)
        await drainMainQueue()
        #expect(fixture.requests.presence == [true, false])
    }

    @Test func theHostHearsThePanelGoWhenItsEmbedLeavesTheNote() async throws {
        let fixture = makeFixture()
        tap(try cardBodyPoint(in: fixture.textView), on: fixture)
        await drainMainQueue()
        #expect(fixture.requests.presence == [true])

        let without = "Prose above the embed.\n\nProse below the embed."
        fixture.textView.text = without
        fixture.coordinator.applyMarkdownStyle(to: fixture.textView, text: without)
        await drainMainQueue()

        #expect(fixture.coordinator.inlineTaskPanel.openTaskID == nil, "non-vacuity: the panel closed")
        #expect(fixture.requests.presence == [true, false])
    }

    @Test func theFloatingButtonStandsAsideOnlyWhileAPanelIsOpen() {
        #expect(iOSFloatingCreateTaskVisibility.showsButton(isRegularWidth: true, inlineTaskPanelIsOpen: false))
        #expect(!iOSFloatingCreateTaskVisibility.showsButton(isRegularWidth: true, inlineTaskPanelIsOpen: true))
        #expect(!iOSFloatingCreateTaskVisibility.showsButton(isRegularWidth: false, inlineTaskPanelIsOpen: false))
    }

    @Test func eitherOfTwoEditorsOnAPageIsEnoughToYieldFor() {
        for (first, second) in [(true, false), (false, true), (true, true)] {
            var value = first
            iOSInlineTaskPanelPresenceKey.reduce(value: &value) { second }
            #expect(value)
        }
        var none = iOSInlineTaskPanelPresenceKey.defaultValue
        iOSInlineTaskPanelPresenceKey.reduce(value: &none) { false }
        #expect(!none)
    }
}
#endif
