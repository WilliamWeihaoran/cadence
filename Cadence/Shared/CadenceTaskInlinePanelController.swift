import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// **Where an inline task panel sits in a note's text, decided once for any text view** ([[T-1481]],
/// iOS half).
///
/// The iOS editor opens `CadenceTaskInlinePanel` *in* the note, directly under the embedded task's
/// card, the way the Mac editor does (`MarkdownInlineTaskPanelSupport`). The markdown source never
/// changes: the embed paragraph's `paragraphSpacing` grows by the panel's height plus a gap either
/// side, so every line below moves down exactly that much, and a hosted SwiftUI view is laid over
/// the space reserved.
///
/// Platform-neutral on purpose, and outside every `#if os(iOS)`: `CadenceTests` builds for macOS
/// and cannot compile `Cadence/iOS/`, so the decisions live here, where a real `NSLayoutManager`
/// can measure them, and the iOS file keeps only the UIKit hosting.
enum CadenceTaskInlinePanelReservation {
    /// The space between the card and the panel, and between the panel and the next line.
    static let gap: CGFloat = 8
    /// Widest the panel gets on a wide iPad note; a form stretched across a page reads worse.
    static let maxWidth: CGFloat = 460
    static let minWidth: CGFloat = 160

    /// What the embed's paragraph adds below itself while the panel is open.
    static func reservedSpacing(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight) + gap * 2
    }

    static func panelWidth(contentWidth: CGFloat) -> CGFloat {
        min(maxWidth, max(minWidth, contentWidth))
    }

    /// The panel's frame in the coordinates the card's rect is in: under the card, on its left edge.
    static func panelFrame(cardRect: CGRect, contentWidth: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: cardRect.minX,
            y: cardRect.maxY + gap,
            width: panelWidth(contentWidth: contentWidth),
            height: max(0, height)
        )
    }

    /// **How far the note has to scroll to put a focused panel field, and the panel's Save and
    /// Cancel under it, clear of the keyboard** ([[T-3243]]).
    ///
    /// The panel is a subview of the note's text view, which SwiftUI's keyboard avoidance does not
    /// reach: focusing the panel's title or notes field raises the keyboard straight over the
    /// panel's action row, and nothing scrolls it clear. The caller hands in the rects it measured
    /// and applies the returned delta to its own scroll offset, so the decision is one rule that a
    /// test can drive rather than UIKit geometry read off a screenshot.
    ///
    /// Everything is in one coordinate space, y growing downward, and `visibleRect` is what is
    /// left of the note once the keyboard has taken its bite. The focused field wins when both
    /// cannot fit: a user typing must see what they are typing, even if Save stays hidden.
    /// Positive scrolls the note down (content up); zero means it already reads.
    static func keyboardRevealOffset(
        focusedRect: CGRect,
        panelFrame: CGRect,
        visibleRect: CGRect
    ) -> CGFloat {
        guard visibleRect.height > 0 else { return 0 }
        // The field was scrolled off the top: bring it back before worrying about the buttons.
        if focusedRect.minY < visibleRect.minY { return focusedRect.minY - visibleRect.minY }
        let withActions = focusedRect.union(
            CGRect(x: panelFrame.minX, y: panelFrame.maxY, width: max(0, panelFrame.width), height: 0)
        )
        let target = withActions.height <= visibleRect.height ? withActions : focusedRect
        guard target.maxY > visibleRect.maxY else { return 0 }
        // Never take the focused field off the top to make room for the rest of the panel.
        return min(target.maxY - visibleRect.maxY, focusedRect.minY - visibleRect.minY)
    }

    /// **Keeps a centred canvas where it was.** TextKit 1 counts `paragraphSpacing` inside the line
    /// fragment rect, and the iOS editor centres a block canvas in that rect
    /// (`iOSMarkdownBlockCanvas.blockRect`). Growing the spacing by `reservedSpacing` therefore
    /// moves the card down by half of it unless its offset gives that half back. The Mac card is
    /// drawn from the fragment's top and needs no such correction.
    static func centredCanvasOffset(_ base: CGFloat, reservedSpacing: CGFloat) -> CGFloat {
        base - reservedSpacing / 2
    }

    /// The first character of the embed for `taskID`, or `nil` when the note no longer holds it.
    static func embedLocation(for taskID: UUID, in storage: NSAttributedString) -> Int? {
        guard storage.length > 0 else { return nil }
        var found: Int?
        storage.enumerateAttribute(
            .cadenceMarkdownTaskEmbed,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, stop in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo, embed.task.id == taskID else { return }
            found = range.location
            stop.pointee = true
        }
        return found
    }

    /// Grows the embed paragraph for `taskID` by `spacing`. `false` when the note holds no embed
    /// for that task, so there is nothing to reserve under.
    @discardableResult
    static func reserve(_ spacing: CGFloat, forTaskID taskID: UUID, in storage: NSMutableAttributedString) -> Bool {
        guard let location = embedLocation(for: taskID, in: storage) else { return false }
        let paragraphRange = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        var styleRange = NSRange(location: location, length: 0)
        let existing = storage.attribute(
            .paragraphStyle,
            at: location,
            longestEffectiveRange: &styleRange,
            in: paragraphRange
        ) as? NSParagraphStyle ?? NSParagraphStyle.default
        guard let grown = existing.mutableCopy() as? NSMutableParagraphStyle else { return false }
        grown.paragraphSpacing = existing.paragraphSpacing + max(0, spacing)
        storage.addAttribute(.paragraphStyle, value: grown, range: styleRange)
        return true
    }
}

/// **The open inline panel's lifetime, with the platform's view left abstract.**
///
/// `Host` is whatever the editor hangs in its text view (a `UIHostingController` on iOS); `detach`
/// takes it out again. Keeping the view generic is what lets the dismissal rules below be run on
/// macOS against a stand-in, rather than only read.
///
/// The rules are the Mac half's, unchanged: asking again for the task already open keeps it, draft
/// and all; asking for another task replaces it; closing gives the space back; and a styling pass
/// that finds the embed gone closes it.
@MainActor
final class CadenceTaskInlinePanelController<Host: AnyObject> {
    struct Session {
        let taskID: UUID
        let host: Host
        var height: CGFloat
    }

    private(set) var session: Session?
    private let detach: (Host) -> Void

    init(detach: @escaping (Host) -> Void) {
        self.detach = detach
    }

    var openTaskID: UUID? { session?.taskID }
    var host: Host? { session?.host }

    /// Opens the panel for `taskID`. `false` — and `makeHost` never called — when that task's panel
    /// is already the open one.
    @discardableResult
    func present(taskID: UUID, makeHost: () -> (host: Host, height: CGFloat)) -> Bool {
        if session?.taskID == taskID { return false }
        detachCurrent()
        let made = makeHost()
        session = Session(taskID: taskID, host: made.host, height: max(0, ceil(made.height)))
        return true
    }

    /// `true` when there was a panel to close.
    @discardableResult
    func close() -> Bool {
        guard session != nil else { return false }
        detachCurrent()
        return true
    }

    /// The room the embed for `taskID` reserves below its card: zero unless its panel is open.
    func reservedSpacing(forTaskID taskID: UUID) -> CGFloat {
        guard let session, session.taskID == taskID else { return 0 }
        return CadenceTaskInlinePanelReservation.reservedSpacing(panelHeight: session.height)
    }

    /// The panel reported a new height. `true` when it moved enough to restyle for; a report for a
    /// task whose panel is not the open one changes nothing.
    @discardableResult
    func updateHeight(_ height: CGFloat, for taskID: UUID) -> Bool {
        guard var current = session, current.taskID == taskID else { return false }
        let rounded = ceil(height)
        guard abs(rounded - current.height) > 0.5 else { return false }
        current.height = rounded
        session = current
        return true
    }

    /// Run after every styling pass. Reserves the open panel's room and returns how much; closes
    /// the panel and returns `nil` when its embed has left the note — no paragraph carries the
    /// reservation any more, so only the view has to go.
    @discardableResult
    func applyReservation(to storage: NSMutableAttributedString) -> CGFloat? {
        guard let session else { return nil }
        let spacing = reservedSpacing(forTaskID: session.taskID)
        guard CadenceTaskInlinePanelReservation.reserve(spacing, forTaskID: session.taskID, in: storage) else {
            detachCurrent()
            return nil
        }
        return spacing
    }

    private func detachCurrent() {
        guard let session else { return }
        self.session = nil
        detach(session.host)
    }
}
