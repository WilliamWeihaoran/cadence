#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// **The task panel, opened in the note's own text flow** ([[T-1481]], macOS half).
///
/// A field chip on an embedded task's card used to open `TaskEmbedFieldEditorPopover`, which
/// floated over the text and never had to care where the text went. The panel now opens *in* the
/// note, directly under the card, and the note reflows around it.
///
/// ## How it sits in the text — the rendered table's rule, reused
///
/// The markdown source never changes. The embed's line already reserves the card's height through
/// its paragraph style (`MarkdownStylist.applyTaskEmbedBlock`); while the panel is open that same
/// paragraph's `paragraphSpacing` grows by the panel's height, so every line below moves down by
/// exactly that much and the card itself does not move at all — it is drawn from the top of the
/// fragment. A hosted SwiftUI view is then laid over the space reserved, the way the rendered
/// table lays a hosted cell editor over its grid (T-221). Nothing enters the text storage, so
/// undo, selection and copy see the note exactly as they did before it opened.
///
/// ## The three decisions the ticket named
///
/// 1. **Reflow, with the task kept visible.** The reservation above is the reflow. On opening, the
///    view scrolls to show the card and the panel, and if both do not fit, the card wins — the
///    panel is about that task, so the task stays on screen.
/// 2. **Dismissal.** Save commits and closes; Cancel discards and closes; **Escape** cancels,
///    whether focus is in the panel (`onExitCommand`) or back in the note text (the coordinator's
///    `cancelOperation`, ahead of the caret commands). Clicking elsewhere does not close it: the
///    draft is unsaved work. Opening another task's panel replaces this one; deleting the embed's
///    line from the note closes it.
/// 3. iPhone is the other half and is not here; see the ticket.
enum MarkdownInlineTaskPanelLayout {
    /// The space between the card and the panel, and between the panel and the next line.
    static let gap: CGFloat = 8
    /// Widest the panel gets in a wide note. A note column can be very wide; a form stretched to
    /// it reads worse than one at a form's width.
    static let maxWidth: CGFloat = 460
    static let minWidth: CGFloat = 160

    /// What the embed's paragraph adds below itself while the panel is open: the panel and a gap
    /// on either side of it, so the next line starts clear of the panel's bottom edge.
    static func reservedSpacing(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight) + gap * 2
    }

    /// Where the panel is drawn: under the card, on the card's left edge.
    static func panelFrame(cardRect: NSRect, textContainerWidth: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: cardRect.minX,
            y: cardRect.maxY + gap,
            width: panelWidth(textContainerWidth: textContainerWidth),
            height: max(0, height)
        )
    }

    static func panelWidth(textContainerWidth: CGFloat) -> CGFloat {
        min(maxWidth, max(minWidth, textContainerWidth - 16))
    }
}

/// Which chip opens what. Every field chip opens the panel **except status**: the panel draws no
/// status control (the card's checkbox completes and reopens), and Start / Cancel — the only way
/// to put a task in progress from a note — stay on the status chip's own small editor.
enum MarkdownInlineTaskPanelRouting {
    static func opensPanel(for field: MarkdownTaskEmbedField) -> Bool {
        switch field {
        case .status, .title:
            // `.title` never reaches a host: the card edits its title in place.
            return false
        case .priority, .container, .section, .scheduledDate, .dueDate, .estimate, .recurrence:
            return true
        }
    }
}

/// The open panel's record on the text view.
@MainActor
final class MarkdownInlineTaskPanelState {
    let taskID: UUID
    let host: NSHostingView<MarkdownInlineTaskPanelFrame>
    var height: CGFloat

    init(taskID: UUID, host: NSHostingView<MarkdownInlineTaskPanelFrame>, height: CGFloat) {
        self.taskID = taskID
        self.host = host
        self.height = height
    }
}

/// The hosted root: the host's panel at the width the note gives it, reporting its height back so
/// the reservation follows it as rows expand and collapse.
struct MarkdownInlineTaskPanelFrame: View {
    var width: CGFloat
    let content: AnyView
    let onHeightChange: (CGFloat) -> Void
    let onCancel: () -> Void

    var body: some View {
        content
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                onHeightChange(height)
            }
            .onExitCommand(perform: onCancel)
            // Top-aligned, so a panel that has just grown is never centred in a host that has not
            // caught up with it yet — it extends downward for that one pass instead.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The height the panel wants at `width`, measured before it is laid out in the note — the
    /// root above fills whatever frame it is given, so it cannot be asked itself.
    @MainActor
    static func idealHeight(of content: AnyView, width: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: content.frame(width: width).fixedSize(horizontal: false, vertical: true))
        return ceil(probe.fittingSize.height)
    }
}

extension CadenceTextView {
    var openInlineTaskPanelID: UUID? {
        inlineTaskPanel?.taskID
    }

    /// Opens the shared task panel under this task's card. See the type note above.
    func presentInlineTaskPanel(
        for task: AppTask,
        in modelContext: ModelContext,
        onSaved: @escaping (AppTask) -> Void
    ) {
        presentInlineTaskPanel(taskID: task.id) { close in
            AnyView(
                CadenceTaskInlinePanel(task: task, onClose: close, onSaved: onSaved)
                    .cadenceCard(cornerRadius: Theme.radiusPanel)
                    .modelContext(modelContext)
            )
        }
    }

    /// The content-agnostic half, which the layout tests drive with a fixed-height view.
    ///
    /// Asking again for the task already open keeps it, draft and all; asking for another task
    /// replaces it.
    func presentInlineTaskPanel(taskID: UUID, makeContent: (_ close: @escaping () -> Void) -> AnyView) {
        if inlineTaskPanel?.taskID == taskID { return }
        removeInlineTaskPanelHost()

        let width = MarkdownInlineTaskPanelLayout.panelWidth(
            textContainerWidth: textContainer?.containerSize.width ?? bounds.width
        )
        let content = makeContent { [weak self] in self?.closeInlineTaskPanel() }
        let host = NSHostingView(
            rootView: MarkdownInlineTaskPanelFrame(
                width: width,
                content: content,
                onHeightChange: { [weak self] height in
                    // Reported from inside SwiftUI's layout pass; restyling the note from there
                    // would re-enter it.
                    DispatchQueue.main.async { self?.updateInlineTaskPanelHeight(height, for: taskID) }
                },
                onCancel: { [weak self] in self?.closeInlineTaskPanel() }
            )
        )
        host.sizingOptions = []
        let height = MarkdownInlineTaskPanelFrame.idealHeight(of: content, width: width)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        addSubview(host)
        inlineTaskPanel = MarkdownInlineTaskPanelState(taskID: taskID, host: host, height: height)

        restyleForInlineTaskPanel()
        revealInlineTaskPanel()
    }

    /// Closes the panel and gives the note its space back. Safe to call when nothing is open.
    func closeInlineTaskPanel() {
        guard inlineTaskPanel != nil else { return }
        removeInlineTaskPanelHost()
        restyleForInlineTaskPanel()
        window?.makeFirstResponder(self)
    }

    /// Escape. `true` when there was a panel to close, so the key goes no further.
    @discardableResult
    func cancelInlineTaskPanel() -> Bool {
        guard inlineTaskPanel != nil else { return false }
        closeInlineTaskPanel()
        return true
    }

    /// The extra space the embed paragraph for `taskID` reserves below its card: zero unless that
    /// task's panel is the one open.
    func inlineTaskPanelReservedSpacing(forTaskID taskID: UUID) -> CGFloat {
        guard let inlineTaskPanel, inlineTaskPanel.taskID == taskID else { return 0 }
        return MarkdownInlineTaskPanelLayout.reservedSpacing(panelHeight: inlineTaskPanel.height)
    }

    /// The panel's height moved — a row expanded or collapsed — so the reservation follows it.
    func updateInlineTaskPanelHeight(_ height: CGFloat, for taskID: UUID) {
        guard let inlineTaskPanel, inlineTaskPanel.taskID == taskID else { return }
        let rounded = ceil(height)
        guard abs(rounded - inlineTaskPanel.height) > 0.5 else { return }
        inlineTaskPanel.height = rounded
        restyleForInlineTaskPanel()
    }

    /// Lays the hosted panel over the space its embed reserved. Run after every styling pass and
    /// every width change; closes the panel when its embed is no longer in the note.
    func positionInlineTaskPanel() {
        guard let inlineTaskPanel, let textContainer else { return }
        guard let lineRect = taskEmbedLineRect(for: inlineTaskPanel.taskID),
              let info = taskEmbedLayoutInfo(for: inlineTaskPanel.taskID)?.task else {
            // The embed's line was deleted or the note was swapped out from under it. No paragraph
            // carries the reservation any more, so there is no space to hand back — only the view.
            removeInlineTaskPanelHost()
            return
        }
        let cardRect = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: lineRect,
            textContainerWidth: textContainer.containerSize.width,
            task: info
        )
        let frame = MarkdownInlineTaskPanelLayout.panelFrame(
            cardRect: cardRect,
            textContainerWidth: textContainer.containerSize.width,
            height: inlineTaskPanel.height
        ).integral
        let host = inlineTaskPanel.host
        if host.rootView.width != frame.width {
            host.rootView.width = frame.width
        }
        if host.frame != frame {
            host.frame = frame
        }
        host.isHidden = false
    }

    /// The card's rect and the panel's, in view coordinates — what the tests and the reveal read.
    func inlineTaskPanelGeometry() -> (card: NSRect, panel: NSRect)? {
        guard let inlineTaskPanel, let textContainer,
              let lineRect = taskEmbedLineRect(for: inlineTaskPanel.taskID),
              let info = taskEmbedLayoutInfo(for: inlineTaskPanel.taskID)?.task else { return nil }
        let card = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: lineRect,
            textContainerWidth: textContainer.containerSize.width,
            task: info
        )
        return (card, inlineTaskPanel.host.frame)
    }

    // MARK: - Private

    private func removeInlineTaskPanelHost() {
        guard let inlineTaskPanel else { return }
        inlineTaskPanel.host.removeFromSuperview()
        self.inlineTaskPanel = nil
    }

    private func restyleForInlineTaskPanel() {
        guard let scrollView = enclosingScrollView else {
            MarkdownStylist.apply(to: self)
            needsDisplay = true
            return
        }
        MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
            MarkdownStylist.apply(to: self)
        }
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        needsDisplay = true
    }

    /// Decision (1): the card and the panel on screen, and the card first if both do not fit.
    private func revealInlineTaskPanel() {
        guard let geometry = inlineTaskPanelGeometry() else { return }
        scrollToVisible(geometry.card.union(geometry.panel))
        scrollToVisible(geometry.card)
    }

    /// The line fragment of the embed for `taskID`, in view coordinates.
    private func taskEmbedLineRect(for taskID: UUID) -> NSRect? {
        guard let layoutManager, let textStorage,
              let location = taskEmbedCharacterLocation(for: taskID),
              location < textStorage.length else { return nil }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let origin = textContainerOrigin
        return layoutManager
            .lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            .offsetBy(dx: origin.x, dy: origin.y)
    }

    private func taskEmbedLayoutInfo(for taskID: UUID) -> MarkdownTaskEmbedLayoutInfo? {
        guard let textStorage, let location = taskEmbedCharacterLocation(for: taskID) else { return nil }
        return textStorage.attribute(.cadenceMarkdownTaskEmbed, at: location, effectiveRange: nil)
            as? MarkdownTaskEmbedLayoutInfo
    }

    private func taskEmbedCharacterLocation(for taskID: UUID) -> Int? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        var found: Int?
        textStorage.enumerateAttribute(
            .cadenceMarkdownTaskEmbed,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, range, stop in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo, embed.task.id == taskID else { return }
            found = range.location
            stop.pointee = true
        }
        return found
    }
}
#endif
