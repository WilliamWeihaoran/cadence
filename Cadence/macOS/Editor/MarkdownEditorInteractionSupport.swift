#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class CadenceTextView: NSTextView, NSTextFieldDelegate {
    var markdownImageAssets: [UUID: MarkdownImageRenderAsset] = [:]
    var markdownImageAssetVersions: [UUID: Date] = [:]
    var markdownImageRects: [UUID: NSRect] = [:]
    var markdownTaskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    var markdownTaskEmbedRects: [UUID: MarkdownTaskEmbedHitRects] = [:]
    var hoveredMarkdownTaskEmbed: MarkdownTaskEmbedHover?
    var selectedMarkdownImageID: UUID?
    var referenceSuggestions: [MarkdownReferenceSuggestion] = []
    var tagSuggestions: [MarkdownTagSuggestion] = []
    var onOpenMarkdownReference: ((MarkdownReferenceTarget) -> Void)?
    var onCreateEmbeddedMarkdownTask: ((String) -> MarkdownReferenceSuggestion?)?
    var onToggleEmbeddedMarkdownTask: ((UUID) -> Void)?
    var onToggleEmbeddedMarkdownSubtask: ((UUID, UUID) -> Void)?
    var onRenameEmbeddedMarkdownTask: ((UUID, String) -> Void)?
    var onOpenEmbeddedMarkdownTask: ((UUID) -> Void)?
    var onEditEmbeddedMarkdownTask: ((UUID, MarkdownTaskEmbedField) -> Void)?
    var onHoverEmbeddedMarkdownTask: ((UUID, Bool) -> Void)?
    var onCreateMarkdownImages: (([NSImage], [URL]) -> [MarkdownImageAsset])?
    var onResizeMarkdownImage: ((UUID, CGFloat) -> Void)?
    /// The host's `MarkdownEditor.allowsImageInsertion`, threaded down so the *drag* answer matches
    /// the one every other image door already gives (T-478).
    ///
    /// `onCreateMarkdownImages` returning `[]` was enough to make a refused drop harmless, but not
    /// enough to make it honest: `draggingEntered` answered `.copy` for any image payload, so the
    /// pointer showed the copy badge over an editor that was about to decline. Read by
    /// `markdownImageDropOperation(for:)` and by `registerMarkdownDraggedTypes()`.
    var allowsMarkdownImageInsertion = true

    private var resizingImageID: UUID?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    private var trackingAreaForHover: NSTrackingArea?
    private var pendingTaskEmbedMouseDown: (id: UUID, target: MarkdownTaskEmbedHitTarget, point: NSPoint, event: NSEvent)?
    private var draggingTaskEmbedID: UUID?
    private var inlineTaskTitleEditor: NSTextField?
    private var inlineTaskTitleTaskID: UUID?
    private var pendingInlineTaskTitleEditID: UUID?
    private var isEndingInlineTaskTitleEdit = false
    private let taskEmbedDragThreshold: CGFloat = 4

    // MARK: - Rendered tables (T-221)

    /// What the last table draw pass measured, one entry per rendered table.
    var markdownTableHits: [MarkdownTableHitInfo] = []
    /// The one table whose markdown source is deliberately on screen, by its first character.
    ///
    /// The raw-source escape is a **command** — "Show Table Source" in the table's context menu —
    /// and not an accident of caret position. Anchoring it to a storage location rather than a line
    /// index means an edit *inside* the revealed table keeps it revealed, which is the whole point
    /// of the mode; an edit above it drops back to the rendered grid, which is a cheap and visible
    /// way to leave.
    var revealedTableAnchor: Int?
    var tableCellEditor: NSTextField?
    var tableCellEditAddress: MarkdownTableCellAddress?
    var tableCellEditAnchor: Int?
    var isEndingTableCellEdit = false

    var hasPendingInlineTaskTitleEdit: Bool {
        pendingInlineTaskTitleEditID != nil
    }

    /// The main-actor half of the editor's decoration layer.
    ///
    /// `CadenceLayoutManager` draws the six decorations that need nothing but colours and
    /// arithmetic; the task-embed card and the standalone image write this view's hit-rect caches
    /// and read its hover/selection state, so they cannot run from a `nonisolated` layout-manager
    /// override and run from here instead. This hook is deliberately the one *before*
    /// `super.draw(_:)` rather than after it — see `MarkdownEditorTextViewDecorations.swift` for
    /// what that preserves and what was measured rather than assumed.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawMarkdownDecorations(in: rect)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if MarkdownKeyboardShortcutSupport.handle(event, in: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func performMarkdownFormatCommand(_ command: MarkdownFormatCommand) {
        _ = MarkdownKeyboardShortcutSupport.apply(command, in: self)
    }

    /// Widened so an image-only pasteboard makes **Paste** applicable at all.
    ///
    /// AppKit validates the Paste command against this list before dispatching it, so with the
    /// stock list a screenshot left the menu item disabled and `paste(_:)` below was never called.
    /// The reasoning, and why this is the fix rather than `importsGraphics = true`, is on
    /// `MarkdownImageAssetService.readableImagePasteboardTypes`.
    ///
    /// Appended, never prepended: `readSelection(from:)` picks the first of *these* types the
    /// pasteboard carries, so text keeps resolving to RTF or string exactly as before and only a
    /// pasteboard with nothing else on it reaches an image type.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        for type in MarkdownImageAssetService.readableImagePasteboardTypes where !types.contains(type) {
            types.append(type)
        }
        return types
    }

    override func paste(_ sender: Any?) {
        if insertMarkdownImages(from: NSPasteboard.general) {
            return
        }
        super.paste(sender)
    }

    /// Registers the drag types this view accepts, image types included only at a host that will
    /// mint an asset for them.
    ///
    /// `.fileURL` stays registered on both paths: it is not image-specific, and a file drop a
    /// refusing host does not want is answered by `super` below rather than by advertising a
    /// capability and then falling through.
    func registerMarkdownDraggedTypes() {
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        if allowsMarkdownImageInsertion {
            types.append(contentsOf: [.tiff, .png])
        }
        registerForDraggedTypes(types)
    }

    /// The drag operation this view claims for `pasteboard`, or `nil` when the drag is not its to
    /// claim and `super` should answer.
    ///
    /// Split out of `draggingEntered` so the rule can be exercised against a private pasteboard.
    /// `NSDraggingInfo` is a protocol with a dozen members a test would have to stub, none of which
    /// this decision reads.
    func markdownImageDropOperation(for pasteboard: NSPasteboard) -> NSDragOperation? {
        guard allowsMarkdownImageInsertion, hasImagePayload(pasteboard) else { return nil }
        return .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownImageDropOperation(for: sender.draggingPasteboard) ?? super.draggingEntered(sender)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaForHover {
            removeTrackingArea(trackingAreaForHover)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaForHover = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredTaskEmbed(at: convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        clearHoveredTaskEmbed()
        super.mouseExited(with: event)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if insertMarkdownImages(from: sender.draggingPasteboard) {
            return true
        }
        return super.performDragOperation(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let inlineTaskTitleEditor,
           !inlineTaskTitleEditor.frame.insetBy(dx: -4, dy: -4).contains(viewPoint) {
            endInlineTaskTitleEdit(commit: true)
        }
        if let tableCellEditor,
           !tableCellEditor.frame.insetBy(dx: -4, dy: -4).contains(viewPoint) {
            endTableCellEdit(commit: true)
        }

        if let hit = imageResizeHit(at: viewPoint) {
            resizingImageID = hit.id
            selectedMarkdownImageID = nil
            resizeStartX = viewPoint.x
            resizeStartWidth = hit.rect.width
            return
        }
        if let hit = imageHit(at: viewPoint) {
            selectedMarkdownImageID = hit.id
            if let range = markdownImageRange(for: hit.id) {
                setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            }
            needsDisplay = true
            return
        }
        selectedMarkdownImageID = nil

        if let taskHit = taskEmbedHit(at: viewPoint) {
            pendingTaskEmbedMouseDown = (taskHit.id, taskHit.target, viewPoint, event)
            return
        }

        if let hit = checklistMarkerHit(at: viewPoint) {
            if shouldChangeText(in: hit.stateRange, replacementString: hit.replacement) {
                textStorage?.replaceCharacters(in: hit.stateRange, with: hit.replacement)
                didChangeText()
                return
            }
        }

        if let reference = markdownReferenceHit(at: viewPoint) {
            onOpenMarkdownReference?(reference)
            return
        }

        if let hit = markdownTableCellHit(at: viewPoint) {
            beginTableCellEdit(anchor: hit.anchor, address: hit.address)
            return
        }

        super.mouseDown(with: event)
        snapCaretAwayFromHiddenMarkdown(preferringForward: true)
    }

    override func mouseDragged(with event: NSEvent) {
        if let pendingTaskEmbedMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            let distance = hypot(point.x - pendingTaskEmbedMouseDown.point.x, point.y - pendingTaskEmbedMouseDown.point.y)
            if distance >= taskEmbedDragThreshold,
               beginTaskEmbedDrag(id: pendingTaskEmbedMouseDown.id, event: pendingTaskEmbedMouseDown.event) {
                self.pendingTaskEmbedMouseDown = nil
            }
            return
        }

        guard let resizingImageID else {
            super.mouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        // One resolver, shared with the iOS pan: start width plus travel, clamped once. The local
        // re-clamp that used to sit below was a second copy of the same bounds.
        let newWidth = MarkdownImageAssetService.resolvedDisplayWidth(
            startWidth: resizeStartWidth,
            translation: point.x - resizeStartX
        )
        onResizeMarkdownImage?(resizingImageID, newWidth)
        if let current = markdownImageAssets[resizingImageID] {
            markdownImageAssets[resizingImageID] = MarkdownImageRenderAsset(
                id: current.id,
                image: current.image,
                displayWidth: newWidth,
                pixelSize: current.pixelSize
            )
        }
        if let scrollView = enclosingScrollView {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: self)
                MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
            }
        } else {
            MarkdownStylist.apply(to: self)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizingImageID != nil {
            resizingImageID = nil
            return
        }
        if let pendingTaskEmbedMouseDown {
            performTaskEmbedClick(pendingTaskEmbedMouseDown)
            self.pendingTaskEmbedMouseDown = nil
            return
        }
        super.mouseUp(with: event)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingTaskEmbedID = nil
    }

    func snapCaretAwayFromHiddenMarkdown(preferringForward: Bool) {
        clampSelectionOutOfHiddenFrontmatter()
        let selection = selectedRange()
        guard selection.length == 0 else { return }
        let snapped = MarkdownHiddenRangeSupport.snappedCaretLocation(
            selection.location,
            in: textStorage,
            preferringForward: preferringForward
        )
        if snapped != selection.location {
            setSelectedRange(NSRange(location: snapped, length: 0))
        }
    }

    /// Pushes any selection that reaches into the hidden frontmatter block down to the first
    /// character of the body.
    ///
    /// The block renders at zero height, so no position inside it is reachable by eye. Anything
    /// that lands there — a click above the first visible line, Cmd+Up, Home on the first line —
    /// gets moved out. For a *ranged* selection only the leading edge moves, which is what keeps
    /// Cmd+A then typing from silently deleting the YAML: the replacement starts at the body.
    func clampSelectionOutOfHiddenFrontmatter() {
        guard let textStorage else { return }
        let bodyStart = MarkdownHiddenRangeSupport.bodyStartLocation(in: textStorage)
        guard bodyStart > 0 else { return }
        let selection = selectedRange()
        guard selection.location < bodyStart else { return }
        let end = max(NSMaxRange(selection), bodyStart)
        setSelectedRange(NSRange(location: bodyStart, length: min(end, textStorage.length) - bodyStart))
    }

    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        clampSelectionOutOfHiddenFrontmatter()
    }

    /// `true` when the caret is parked on the first body character of a note whose frontmatter is
    /// hidden — i.e. the only thing behind it is invisible YAML.
    func isCaretAtHiddenFrontmatterBoundary() -> Bool {
        guard let textStorage else { return false }
        let bodyStart = MarkdownHiddenRangeSupport.bodyStartLocation(in: textStorage)
        guard bodyStart > 0 else { return false }
        let selection = selectedRange()
        return selection.length == 0 && selection.location <= bodyStart
    }

    /// Rewrites the title inside every `[[task:UUID|Title]]` reference to one task.
    ///
    /// Which runs to rewrite, and what a title is allowed to look like once it is inside a
    /// reference, are `MarkdownTaskEmbedParser`'s — a platform-free decision the test target can
    /// actually run, and the same one iOS's inline rename asks. This method is only the
    /// `NSTextStorage` mutation half of it.
    func replaceEmbeddedTaskReferenceTitle(id: UUID, title: String) {
        guard let textStorage else { return }
        let displayTitle = CadenceTitleNormalization.referenceDisplay(
            title,
            fallback: MarkdownTaskEmbedRenderInfo.untitledTaskTitle
        )
        let current = string as NSString
        var didReplace = false
        for titleRange in MarkdownTaskEmbedParser.referenceTitleRanges(of: id, in: string).reversed() {
            guard current.substring(with: titleRange) != displayTitle,
                  shouldChangeText(in: titleRange, replacementString: displayTitle) else { continue }
            textStorage.replaceCharacters(in: titleRange, with: displayTitle)
            didReplace = true
        }
        guard didReplace else { return }
        didChangeText()
    }

    /// Brings every `[[task:UUID|Title]]` in this note back in line with the task it points at.
    ///
    /// The many-tasks spelling of `replaceEmbeddedTaskReferenceTitle`, and the one the app needs.
    /// A task embed's title is stored twice — on the task, which is what the card is drawn from,
    /// and inside the note's own reference text. Only the inline rename over the card wrote both;
    /// renaming the same task from the inspector wrote the task and left the note behind, and the
    /// card kept looking right because it is drawn from the live task. The drift only surfaces
    /// where the reference text is the only title left: an exported note, a content search, or a
    /// deleted task, whose card is rendered by `MarkdownTaskEmbedRenderInfo.missing(reference:)`.
    ///
    /// `titles` is the whole embed table, which on this surface is every task the editor was handed
    /// — so which references to rewrite is decided by `MarkdownTaskEmbedParser`, from the
    /// references actually present in the text, and costs one regex per *embedded* task rather than
    /// one per candidate. Same call iOS makes when its task sheet dismisses.
    ///
    /// Applied as the one minimal edit that turns the current text into the reconciled text, so a
    /// note the user is sitting in keeps its caret, its scroll position and one undo step, instead
    /// of being replaced wholesale.
    func reconcileEmbeddedTaskReferenceTitles(titles: [UUID: String]) {
        guard let textStorage,
              let reconciled = MarkdownTaskEmbedParser.reconcilingReferenceTitles(
                in: string,
                titles: titles,
                fallback: MarkdownTaskEmbedRenderInfo.untitledTaskTitle
              ) else { return }

        let current = string as NSString
        let updated = reconciled as NSString
        let edit = MarkdownTextEditDiff.minimalEdit(from: current, to: updated)
        let replacement = updated.substring(with: edit.replacementRange)
        guard shouldChangeText(in: edit.range, replacementString: replacement) else { return }

        let selection = selectedRange()
        textStorage.replaceCharacters(in: edit.range, with: replacement)
        didChangeText()
        setSelectedRange(
            MarkdownTextEditDiff.selection(selection, after: edit, in: textStorage.length)
        )
    }

    func deleteMarkdownImageForCommand(backward: Bool) -> Bool {
        if let selectedMarkdownImageID,
           let range = markdownImageRange(for: selectedMarkdownImageID) {
            deleteMarkdownImage(in: range)
            return true
        }

        let selection = selectedRange()
        if selection.length > 0,
           let range = markdownImageRange(intersecting: selection) {
            deleteMarkdownImage(in: NSUnionRange(selection, range))
            return true
        }

        guard selection.length == 0 else { return false }
        let probeLocation = backward ? selection.location - 1 : selection.location
        guard let range = markdownImageRange(containingOrAdjacentTo: probeLocation) else { return false }
        deleteMarkdownImage(in: range)
        return true
    }

    func deleteEmbeddedMarkdownTaskForCommand(backward: Bool) -> Bool {
        let selection = selectedRange()
        if selection.length > 0,
           let range = markdownTaskEmbedRange(intersecting: selection) {
            deleteEmbeddedMarkdownTask(in: NSUnionRange(selection, range))
            return true
        }

        guard selection.length == 0 else { return false }
        let probeLocation = backward ? selection.location - 1 : selection.location
        guard let range = markdownTaskEmbedRange(containingOrAdjacentTo: probeLocation) else { return false }
        deleteEmbeddedMarkdownTask(in: range)
        return true
    }

    func resizeHandleRect(for imageRect: NSRect) -> NSRect {
        NSRect(x: imageRect.maxX - 22, y: imageRect.maxY - 22, width: 18, height: 18)
    }

    func insertMarkdownImages(_ assets: [MarkdownImageAsset]) {
        guard !assets.isEmpty else { return }
        let markdown = assets.map { MarkdownImageAssetService.markdown(for: $0) }.joined(separator: "\n\n")
        let selection = selectedRange()
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(markdown, in: string, selection: selection)
        guard shouldChangeText(in: selection, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: selection, with: insertion)
        let location = selection.location + (insertion as NSString).length
        setSelectedRange(NSRange(location: location, length: 0))
        didChangeText()
    }

    func insertMarkdownReference(_ markdown: String) {
        let insertion = inlinePaddedInsertion(markdown)
        let selection = selectedRange()
        guard shouldChangeText(in: selection, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: selection, with: insertion)
        let location = selection.location + (insertion as NSString).length
        setSelectedRange(NSRange(location: location, length: 0))
        typingAttributes = MarkdownStylist.baseAttributes
        didChangeText()
    }

    func chooseMarkdownImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self,
                  response == .OK,
                  let assets = self.onCreateMarkdownImages?([], panel.urls),
                  !assets.isEmpty else { return }
            self.insertMarkdownImages(assets)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func imageResizeHit(at point: NSPoint) -> (id: UUID, rect: NSRect)? {
        for (id, rect) in markdownImageRects where resizeHandleRect(for: rect).contains(point) {
            return (id, rect)
        }
        return nil
    }

    private func imageHit(at point: NSPoint) -> (id: UUID, rect: NSRect)? {
        for (id, rect) in markdownImageRects where rect.contains(point) {
            return (id, rect)
        }
        return nil
    }

    private func performTaskEmbedClick(_ pending: (id: UUID, target: MarkdownTaskEmbedHitTarget, point: NSPoint, event: NSEvent)) {
        switch pending.target {
        case .checkbox:
            onToggleEmbeddedMarkdownTask?(pending.id)
        case .subtaskCheckbox(let subtaskID):
            onToggleEmbeddedMarkdownSubtask?(pending.id, subtaskID)
        case .subtaskText:
            onOpenEmbeddedMarkdownTask?(pending.id)
        case .field(let field):
            if field == .title {
                beginInlineTaskTitleEdit(id: pending.id)
            } else {
                onEditEmbeddedMarkdownTask?(pending.id, field)
            }
        case .card:
            onOpenEmbeddedMarkdownTask?(pending.id)
        }
    }

    fileprivate func beginInlineTaskTitleEdit(id: UUID, retryIfNeeded: Bool = true) {
        endInlineTaskTitleEdit(commit: true)
        guard let task = markdownTaskEmbeds[id],
              let titleRect = taskEmbedTitleRect(id: id, task: task) else {
            guard retryIfNeeded else { return }
            DispatchQueue.main.async { [weak self] in
                self?.beginInlineTaskTitleEdit(id: id, retryIfNeeded: false)
            }
            return
        }

        let editorFrame = titleRect.insetBy(dx: -4, dy: -2)
        let editor = NSTextField(frame: editorFrame)
        editor.stringValue = task.title == MarkdownTaskEmbedRenderInfo.untitledTaskTitle ? "" : task.title
        editor.placeholderString = MarkdownTaskEmbedRenderInfo.untitledTaskTitle
        editor.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        editor.textColor = MarkdownStylist.textColor
        editor.backgroundColor = MarkdownStylist.codeBackground
        editor.isBordered = false
        editor.focusRingType = .none
        editor.delegate = self
        editor.target = self
        editor.action = #selector(commitInlineTaskTitleEditor)
        editor.lineBreakMode = .byTruncatingTail
        editor.cell?.sendsActionOnEndEditing = false
        addSubview(editor)
        inlineTaskTitleEditor = editor
        inlineTaskTitleTaskID = id
        window?.makeFirstResponder(editor)
        editor.selectText(nil)
    }

    /// Internal rather than `fileprivate` because `MarkdownEditorCoordinator` calls it and
    /// now lives in its own file.
    func queueInlineTaskTitleEdit(id: UUID) {
        pendingInlineTaskTitleEditID = id
    }

    /// Internal rather than `fileprivate` because `MarkdownEditorCoordinator` calls it and
    /// now lives in its own file.
    func performPendingInlineTaskTitleEditIfNeeded() {
        guard let pendingInlineTaskTitleEditID else { return }
        self.pendingInlineTaskTitleEditID = nil
        beginInlineTaskTitleEdit(id: pendingInlineTaskTitleEditID)
    }

    @objc private func commitInlineTaskTitleEditor() {
        endInlineTaskTitleEdit(commit: true)
    }

    private func endInlineTaskTitleEdit(commit: Bool) {
        guard !isEndingInlineTaskTitleEdit,
              let editor = inlineTaskTitleEditor,
              let taskID = inlineTaskTitleTaskID else { return }
        isEndingInlineTaskTitleEdit = true
        let rawTitle = TaskTitleSupport.normalized(editor.stringValue)
        let referenceTitle = TaskTitleSupport.priorityShortcut(in: rawTitle)?.title ?? rawTitle
        editor.delegate = nil
        editor.removeFromSuperview()
        inlineTaskTitleEditor = nil
        inlineTaskTitleTaskID = nil
        if commit {
            onRenameEmbeddedMarkdownTask?(taskID, rawTitle)
            replaceEmbeddedTaskReferenceTitle(id: taskID, title: referenceTitle)
        }
        isEndingInlineTaskTitleEdit = false
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === tableCellEditor {
            endTableCellEdit(commit: true)
            return
        }
        guard field === inlineTaskTitleEditor else { return }
        endInlineTaskTitleEdit(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField else { return false }
        if field === tableCellEditor {
            return handleTableCellCommand(commandSelector)
        }
        guard field === inlineTaskTitleEditor else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            endInlineTaskTitleEdit(commit: true)
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endInlineTaskTitleEdit(commit: false)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func updateHoveredTaskEmbed(at point: NSPoint) {
        let hit = taskEmbedHit(at: point)
        let next = hit.map { MarkdownTaskEmbedHover(id: $0.id, target: $0.target) }
        guard next != hoveredMarkdownTaskEmbed else { return }
        let didChangeID = next?.id != hoveredMarkdownTaskEmbed?.id
        if didChangeID, let hoveredMarkdownTaskEmbed {
            onHoverEmbeddedMarkdownTask?(hoveredMarkdownTaskEmbed.id, false)
        }
        hoveredMarkdownTaskEmbed = next
        if let next {
            if didChangeID {
                onHoverEmbeddedMarkdownTask?(next.id, true)
            }
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
        needsDisplay = true
    }

    private func clearHoveredTaskEmbed() {
        guard let hoveredMarkdownTaskEmbed else { return }
        onHoverEmbeddedMarkdownTask?(hoveredMarkdownTaskEmbed.id, false)
        self.hoveredMarkdownTaskEmbed = nil
        pendingTaskEmbedMouseDown = nil
        NSCursor.iBeam.set()
        needsDisplay = true
    }

    private func beginTaskEmbedDrag(id: UUID, event: NSEvent) -> Bool {
        guard let rects = markdownTaskEmbedRects[id] else { return false }
        draggingTaskEmbedID = id
        let item = NSPasteboardItem()
        item.setString(TaskDragPayload.string(for: id), forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(rects.card, contents: taskEmbedDragPreview(for: id, rect: rects.card))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        return true
    }

    private func taskEmbedDragPreview(for id: UUID, rect: NSRect) -> NSImage {
        let image = NSImage(size: rect.size)
        image.lockFocus()
        MarkdownStylist.codeBackground.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: rect.size), xRadius: 11, yRadius: 11).fill()
        MarkdownStylist.blueColor.withAlphaComponent(0.48).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(origin: .zero, size: rect.size).insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        border.lineWidth = 1
        border.stroke()

        let title = markdownTaskEmbeds[id]?.title ?? "Task"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: MarkdownStylist.textColor
        ]
        (title as NSString).draw(in: NSRect(x: 16, y: 10, width: max(20, rect.width - 32), height: 20), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    private func taskEmbedHit(at point: NSPoint) -> (id: UUID, target: MarkdownTaskEmbedHitTarget)? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        var result: (id: UUID, target: MarkdownTaskEmbedHitTarget)?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                  range.location < textStorage.length else { return }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let cardRect = MarkdownTaskEmbedDrawing.cardRect(
                forLineRect: lineRect,
                textContainerWidth: textContainer.containerSize.width,
                task: embed.task
            )
            let checkboxRect = MarkdownTaskEmbedDrawing.checkboxRect(in: cardRect).insetBy(dx: -6, dy: -6)
            if checkboxRect.contains(point) {
                result = (embed.task.id, .checkbox)
                stop.pointee = true
            } else if let subtaskHit = MarkdownTaskEmbedDrawing.subtaskHit(at: point, task: embed.task, cardRect: cardRect) {
                switch subtaskHit {
                case .checkbox(let subtaskID):
                    result = (embed.task.id, .subtaskCheckbox(subtaskID))
                case .openInspector:
                    result = (embed.task.id, .subtaskText)
                }
                stop.pointee = true
            } else if let field = MarkdownTaskEmbedDrawing.fieldHit(at: point, task: embed.task, cardRect: cardRect) {
                result = (embed.task.id, .field(field))
                stop.pointee = true
            } else if cardRect.contains(point) {
                result = (embed.task.id, .card)
                stop.pointee = true
            }
        }
        return result
    }

    private func taskEmbedTitleRect(id: UUID, task: MarkdownTaskEmbedRenderInfo) -> NSRect? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        var result: NSRect?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                  embed.task.id == id,
                  range.location < textStorage.length else { return }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let cardRect = MarkdownTaskEmbedDrawing.cardRect(
                forLineRect: lineRect,
                textContainerWidth: textContainer.containerSize.width,
                task: task
            )
            result = MarkdownTaskEmbedDrawing.titleRect(task: task, cardRect: cardRect)
            stop.pointee = true
        }
        return result
    }

    /// The checklist box under `point`, if any, together with the one-character edit that flips it.
    ///
    /// Both spellings toggle through `MarkdownChecklistSupport`, which already answers for each; only
    /// *where the box is* differs. A legacy `○` / `✓` is a real glyph, so its own bounding rect is the
    /// target. A GitHub `- [x] ` prefix is hidden and drawn, so the target is the rect the layout
    /// manager drew — asking the hidden run for its bounds would give a sliver at the wrong place.
    private func checklistMarkerHit(at point: NSPoint) -> (stateRange: NSRange, replacement: String)? {
        guard let layoutManager = layoutManager as? CadenceLayoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let nsString = string as NSString
        guard characterIndex < nsString.length else { return nil }

        let lineRange = nsString.lineRange(for: NSRange(location: characterIndex, length: 0))
        let line = nsString.substring(with: NSRange(location: lineRange.location, length: min(lineRange.length, nsString.length - lineRange.location)))
            .trimmingCharacters(in: .newlines)
        guard let checklist = MarkdownChecklistSupport.lineInfo(in: line),
              let toggle = MarkdownChecklistSupport.toggledState(in: line) else {
            return nil
        }

        let stateRange = NSRange(location: lineRange.location + toggle.stateRange.location, length: toggle.stateRange.length)
        guard NSMaxRange(stateRange) <= nsString.length else { return nil }

        let boxRect: NSRect?
        switch checklist.syntax {
        case .legacy:
            let markerRange = NSRange(location: lineRange.location + checklist.stateRange.location, length: checklist.stateRange.length)
            let markerGlyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            boxRect = markerGlyphRange.length > 0
                ? layoutManager.boundingRect(forGlyphRange: markerGlyphRange, in: textContainer)
                : nil
        case .github:
            let prefixRange = NSRange(location: lineRange.location + checklist.markerRange.location, length: checklist.markerRange.length)
            boxRect = layoutManager.checklistBoxRect(forPrefixCharacterRange: prefixRange, in: textContainer)
        }

        guard let boxRect else { return nil }
        let target = boxRect
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: -6, dy: -5)
        guard target.contains(point) else { return nil }
        return (stateRange, toggle.replacement)
    }

    private func markdownImageRange(for id: UUID) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let info = value as? MarkdownImageLayoutInfo, info.id == id else { return }
            result = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: range, in: string)
            stop.pointee = true
        }
        return result
    }

    private func markdownImageRange(intersecting selection: NSRange) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard value is MarkdownImageLayoutInfo,
                  NSIntersectionRange(range, selection).length > 0 else { return }
            result = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: range, in: string)
            stop.pointee = true
        }
        return result
    }

    private func markdownImageRange(containingOrAdjacentTo location: Int) -> NSRange? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let clamped = min(max(location, 0), textStorage.length - 1)
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        if textStorage.attribute(.cadenceMarkdownImage, at: clamped, effectiveRange: &effectiveRange) is MarkdownImageLayoutInfo,
           effectiveRange.location != NSNotFound {
            return MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: effectiveRange, in: string)
        }
        return nil
    }

    private func markdownTaskEmbedRange(intersecting selection: NSRange) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard value is MarkdownTaskEmbedLayoutInfo,
                  NSIntersectionRange(range, selection).length > 0 else { return }
            result = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: range, in: string)
            stop.pointee = true
        }
        return result
    }

    private func markdownTaskEmbedRange(containingOrAdjacentTo location: Int) -> NSRange? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let candidates = [location, location - 1, location + 1]
        for candidate in candidates {
            guard candidate >= 0, candidate < textStorage.length else { continue }
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            if textStorage.attribute(.cadenceMarkdownTaskEmbed, at: candidate, effectiveRange: &effectiveRange) is MarkdownTaskEmbedLayoutInfo,
               effectiveRange.location != NSNotFound {
                return MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: effectiveRange, in: string)
            }
        }
        return nil
    }

    private func markdownReferenceHit(at point: NSPoint) -> MarkdownReferenceTarget? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.cadenceMarkdownReference, at: characterIndex, effectiveRange: nil) as? MarkdownReferenceTarget
    }

    private func deleteMarkdownImage(in rawRange: NSRange) {
        let range = NSIntersectionRange(rawRange, NSRange(location: 0, length: (string as NSString).length))
        guard range.length > 0,
              shouldChangeText(in: range, replacementString: "") else { return }
        selectedMarkdownImageID = nil
        textStorage?.replaceCharacters(in: range, with: "")
        setSelectedRange(NSRange(location: range.location, length: 0))
        typingAttributes = MarkdownStylist.baseAttributes
        didChangeText()
    }

    private func deleteEmbeddedMarkdownTask(in rawRange: NSRange) {
        let range = NSIntersectionRange(rawRange, NSRange(location: 0, length: (string as NSString).length))
        guard range.length > 0,
              shouldChangeText(in: range, replacementString: "") else { return }
        markdownTaskEmbedRects.removeAll()
        textStorage?.replaceCharacters(in: range, with: "")
        setSelectedRange(NSRange(location: range.location, length: 0))
        typingAttributes = MarkdownStylist.baseAttributes
        didChangeText()
    }

    /// The whole paste path — read, create, insert — with its pasteboard as an argument.
    ///
    /// Taking the pasteboard rather than reaching for `NSPasteboard.general` is what lets a test
    /// exercise this against a private pasteboard it owns. A test that wrote the system clipboard
    /// would destroy whatever the person running it had copied.
    @discardableResult
    func insertMarkdownImages(from pasteboard: NSPasteboard) -> Bool {
        let urls = MarkdownImageAssetService.imageFileURLs(from: pasteboard)
        let images = urls.isEmpty ? MarkdownImageAssetService.images(from: pasteboard) : []
        guard !urls.isEmpty || !images.isEmpty,
              let assets = onCreateMarkdownImages?(images, urls),
              !assets.isEmpty
        else { return false }
        insertMarkdownImages(assets)
        return true
    }

    private func hasImagePayload(_ pasteboard: NSPasteboard) -> Bool {
        !MarkdownImageAssetService.imageFileURLs(from: pasteboard).isEmpty ||
            !MarkdownImageAssetService.images(from: pasteboard).isEmpty
    }

    private func inlinePaddedInsertion(_ markdown: String) -> String {
        let nsText = string as NSString
        let selection = selectedRange()
        let needsLeadingSpace: Bool
        if selection.location == 0 {
            needsLeadingSpace = false
        } else {
            let previous = nsText.substring(with: NSRange(location: max(0, selection.location - 1), length: 1))
            needsLeadingSpace = !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let needsTrailingSpace: Bool
        if NSMaxRange(selection) >= nsText.length {
            needsTrailingSpace = false
        } else {
            let next = nsText.substring(with: NSRange(location: NSMaxRange(selection), length: 1))
            needsTrailingSpace = !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return (needsLeadingSpace ? " " : "") + markdown + (needsTrailingSpace ? " " : "")
    }
}
#endif
