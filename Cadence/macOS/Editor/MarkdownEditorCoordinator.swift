#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class MarkdownEditorCoordinator: NSObject, NSTextViewDelegate {
    private var parent: MarkdownEditorView
    private let slashCommandPicker = MarkdownSlashCommandPickerController()
    private let referencePicker = MarkdownReferencePickerController()
    private let tagPicker = MarkdownTagPickerController()
    private weak var reportedTextView: CadenceTextView?
    private weak var pendingSlashCommandTextView: NSTextView?
    private weak var pendingReferenceTextView: NSTextView?
    private weak var pendingTagTextView: NSTextView?
    private var isApplyingEditorMutations = false
    private var slashCommandUpdateIsScheduled = false
    private var referenceUpdateIsScheduled = false
    private var tagUpdateIsScheduled = false

    init(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func update(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func notifyTextViewIfNeeded(_ textView: CadenceTextView, onChange: @escaping (CadenceTextView) -> Void) {
        guard reportedTextView !== textView else { return }
        reportedTextView = textView
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.reportedTextView === textView else { return }
            onChange(textView)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }

        // Transforms and normalization now close their edits with `didChangeText()`, which posts
        // this same notification back. The nested pass would only redo work the rest of this one
        // is about to do with the final text, so it is skipped rather than allowed to recurse.
        guard !isApplyingEditorMutations else { return }
        isApplyingEditorMutations = true
        applyInputTransforms(to: textView)
        normalizeMarkdownListPrefixes(in: textView)
        normalizeOrderedListMarkers(in: textView)
        isApplyingEditorMutations = false

        parent.text = textView.string
        applyStyling(to: textView, in: textView.enclosingScrollView)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        scheduleSlashCommandPickerUpdate(for: textView)
        scheduleReferencePickerUpdate(for: textView)
        scheduleTagPickerUpdate(for: textView)
    }

    /// Catches every way the caret can reach the hidden frontmatter block that does not route
    /// through `doCommandBy` — clicking above the first visible line, Cmd+Up, Home, page-up,
    /// find-and-select. Deliberately frontmatter-only: it must not re-introduce the
    /// snap-on-every-selection-change behaviour that used to eject carets resting at the leading
    /// edge of an inline marker.
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? CadenceTextView else { return }
        textView.clampSelectionOutOfHiddenFrontmatter()
    }

    func textDidBeginEditing(_ notification: Notification) {
        parent.onEditingChanged(true)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
            parent.onEditingChanged(false)
            return
        }
        applyStyling(to: textView, in: textView.enclosingScrollView)
        parent.onEditingChanged(false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if let handled = handleTagPickerCommand(commandSelector, in: textView) { return handled }
        if let handled = handleReferencePickerCommand(commandSelector, in: textView) { return handled }
        if let handled = handleSlashCommandPickerCommand(commandSelector, in: textView) { return handled }
        if let handled = handleCaretMovementCommand(commandSelector, in: textView) { return handled }
        if let handled = handleIndentationCommand(commandSelector, in: textView) { return handled }
        if let handled = handleDeletionCommand(commandSelector, in: textView) { return handled }
        return handleNewlineCommand(commandSelector, in: textView)
    }
}

// MARK: - Command Routing

extension MarkdownEditorCoordinator {
    private func handleTagPickerCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        guard tagPicker.isShown else { return nil }
        if tagPicker.isShown {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                tagPicker.moveSelection(delta: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                tagPicker.moveSelection(delta: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                tagPicker.close()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return tagPicker.applyHighlighted { [weak self] choice, context in
                    self?.applyTagCompletion(choice, context: context, in: textView)
                }
            }
        }
        return nil
    }

    private func handleReferencePickerCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        guard referencePicker.isShown else { return nil }
        if referencePicker.isShown {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                referencePicker.moveSelection(delta: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                referencePicker.moveSelection(delta: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                referencePicker.close()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return referencePicker.applyHighlighted { [weak self] suggestion, context in
                    self?.applyReferenceSuggestion(suggestion, context: context, in: textView)
                }
            }
        }
        return nil
    }

    private func handleSlashCommandPickerCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        guard slashCommandPicker.isShown else { return nil }
        if slashCommandPicker.isShown {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                slashCommandPicker.moveSelection(delta: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                slashCommandPicker.moveSelection(delta: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                slashCommandPicker.close()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return slashCommandPicker.applyHighlighted { [weak self] command, context in
                    self?.applySlashCommand(command, context: context, in: textView)
                }
            }
        }
        return nil
    }

    private func handleCaretMovementCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        if commandSelector == #selector(NSResponder.moveLeft(_:)) {
            return moveCaret(in: textView, forward: false, extendSelection: false)
        }

        if commandSelector == #selector(NSResponder.moveRight(_:)) {
            return moveCaret(in: textView, forward: true, extendSelection: false)
        }

        if commandSelector == #selector(NSResponder.moveLeftAndModifySelection(_:)) {
            return moveCaret(in: textView, forward: false, extendSelection: true)
        }

        if commandSelector == #selector(NSResponder.moveRightAndModifySelection(_:)) {
            return moveCaret(in: textView, forward: true, extendSelection: true)
        }
        return nil
    }

    private func handleIndentationCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return adjustIndentation(in: textView, increase: true)
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return adjustIndentation(in: textView, increase: false)
        }
        return nil
    }

    private func handleDeletionCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            // At the top of the body there is nothing behind the caret but the hidden frontmatter
            // block. Swallow the keystroke instead of letting it chew invisible characters — the
            // user would see nothing happen while the block quietly came apart.
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.isCaretAtHiddenFrontmatterBoundary() {
                return true
            }
            if slashCommandPicker.isShown {
                scheduleSlashCommandPickerUpdate(for: textView)
            }
            if tagPicker.isShown {
                scheduleTagPickerUpdate(for: textView)
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteMarkdownImageForCommand(backward: true) {
                return true
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteEmbeddedMarkdownTaskForCommand(backward: true) {
                return true
            }
            return deleteBackwardFromListPrefix(in: textView)
        }

        if commandSelector == #selector(NSResponder.deleteForward(_:)) {
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteMarkdownImageForCommand(backward: false) {
                return true
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteEmbeddedMarkdownTaskForCommand(backward: false) {
                return true
            }
            return false
        }
        return nil
    }

    private func handleNewlineCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let rawLine = nsText.substring(with: NSRange(location: lineRange.location,
                                                     length: min(lineRange.length, nsText.length - lineRange.location)))
        let line = rawLine.trimmingCharacters(in: .newlines)

        if createEmbeddedTaskIfNeeded(in: textView, lineRange: lineRange, line: line) {
            return true
        }

        guard let mutation = MarkdownLineBreakSupport.mutation(in: textView.string, selection: selection) else { return false }
        guard textView.shouldChangeText(in: mutation.replacementRange, replacementString: mutation.replacement) else { return false }
        textView.textStorage?.replaceCharacters(in: mutation.replacementRange, with: mutation.replacement)
        textView.setSelectedRange(mutation.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }
}

// MARK: - Caret & Indentation

extension MarkdownEditorCoordinator {
    private func moveCaret(in textView: NSTextView, forward: Bool, extendSelection: Bool) -> Bool {
        let selection = textView.selectedRange()
        let storage = textView.textStorage

        if extendSelection {
            let anchor = forward ? selection.location : selection.location + selection.length
            let movingEdge = forward ? selection.location + selection.length : selection.location
            let next = MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: movingEdge, movingForward: forward, in: storage)
            let newLocation = min(anchor, next)
            let newLength = abs(next - anchor)
            textView.setSelectedRange(NSRange(location: newLocation, length: newLength))
            return true
        }

        let baseLocation = selection.length > 0 ? (forward ? selection.location + selection.length : selection.location) : selection.location
        let next = MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: baseLocation, movingForward: forward, in: storage)
        textView.setSelectedRange(NSRange(location: next, length: 0))
        return true
    }

    private func adjustIndentation(in textView: NSTextView, increase: Bool) -> Bool {
        guard let result = MarkdownListSupport.adjustedListIndentation(
            in: textView.string,
            selection: textView.selectedRange(),
            increase: increase
        ) else { return false }

        guard textView.shouldChangeText(in: result.replacementRange, replacementString: result.replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacement)
        textView.setSelectedRange(result.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func deleteBackwardFromListPrefix(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard let mutation = MarkdownBackspaceSupport.listPrefixMutation(in: textView.string, selection: selection) else {
            return false
        }

        guard textView.shouldChangeText(in: mutation.replacementRange, replacementString: mutation.replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: mutation.replacementRange, with: mutation.replacement)
        textView.setSelectedRange(mutation.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }
}

// MARK: - Input Transforms & Embedded Tasks

extension MarkdownEditorCoordinator {
    private func applyInputTransforms(to textView: NSTextView) {
        let nsText = textView.string as NSString
        let cursor = textView.selectedRange().location
        guard cursor > 0 else { return }

        if cursor >= 4 {
            let range = NSRange(location: cursor - 4, length: 4)
            let snippet = nsText.substring(with: range)
            if snippet == "( ) ",
               MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
               createUntitledEmbeddedTask(fromTriggerRange: range, in: textView) {
                return
            }
        }

        if cursor >= 3 {
            let range = NSRange(location: cursor - 3, length: 3)
            let snippet = nsText.substring(with: range)
            if snippet == "() ",
               MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
               createUntitledEmbeddedTask(fromTriggerRange: range, in: textView) {
                return
            }
        }

        if let mutation = MarkdownTypingTransformSupport.mutation(in: textView.string, cursor: cursor) {
            replaceText(
                in: textView,
                range: mutation.replacementRange,
                with: mutation.replacement,
                selection: mutation.selection
            )
            return
        }
    }

    private func createUntitledEmbeddedTask(fromTriggerRange range: NSRange, in textView: NSTextView) -> Bool {
        guard let cadenceTextView = textView as? CadenceTextView,
              let suggestion = cadenceTextView.onCreateEmbeddedMarkdownTask?(MarkdownTaskEmbedRenderInfo.untitledTaskTitle),
              suggestion.kind == .task,
              MarkdownTaskEmbedParser.standaloneTaskReference(in: suggestion.markdown) != nil else {
            return false
        }

        guard textView.shouldChangeText(in: range, replacementString: suggestion.markdown) else {
            return true
        }
        textView.textStorage?.replaceCharacters(in: range, with: suggestion.markdown)
        if let titleRange = MarkdownTaskEmbedParser.referenceTitleRange(in: suggestion.markdown, lineStart: range.location) {
            textView.setSelectedRange(titleRange)
        } else {
            textView.setSelectedRange(NSRange(location: range.location + (suggestion.markdown as NSString).length, length: 0))
        }
        cadenceTextView.queueInlineTaskTitleEdit(id: suggestion.targetID)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func createEmbeddedTaskIfNeeded(in textView: NSTextView, lineRange: NSRange, line: String) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0,
              selection.location >= lineRange.location + (line as NSString).length,
              let cadenceTextView = textView as? CadenceTextView,
              let title = MarkdownTaskEmbedParser.draftTitle(in: line),
              let suggestion = cadenceTextView.onCreateEmbeddedMarkdownTask?(title),
              suggestion.kind == .task,
              MarkdownTaskEmbedParser.standaloneTaskReference(in: suggestion.markdown) != nil else {
            return false
        }

        let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
        let replacement = suggestion.markdown + "\n"
        guard textView.shouldChangeText(in: contentRange, replacementString: replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: contentRange, with: replacement)
        textView.setSelectedRange(NSRange(location: contentRange.location + (replacement as NSString).length, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    /// `shouldChangeText` opens an undo group and text-checking state that `didChangeText` is
    /// contractually required to close — leaving it open here left the typing-transform hot path
    /// accumulating unclosed groups.
    private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String, selection: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(selection)
        textView.didChangeText()
    }
}

// MARK: - Styling

extension MarkdownEditorCoordinator {
    private func applyStyling(to textView: NSTextView, in scrollView: NSScrollView?) {
        if let scrollView {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: textView)
            }
        } else {
            MarkdownStylist.apply(to: textView)
        }

        if let cadenceTextView = textView as? CadenceTextView {
            cadenceTextView.snapCaretAwayFromHiddenMarkdown(preferringForward: true)
        }
        if let scrollView {
            MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        }
        if let cadenceTextView = textView as? CadenceTextView {
            cadenceTextView.performPendingInlineTaskTitleEditIfNeeded()
        }
    }
}

// MARK: - List Normalization

extension MarkdownEditorCoordinator {
    private func normalizeMarkdownListPrefixes(in textView: NSTextView) {
        apply(
            MarkdownListSupport.normalizedMarkdownListPrefixes(in: textView.string, selection: textView.selectedRange()),
            to: textView
        )
    }

    private func normalizeOrderedListMarkers(in textView: NSTextView) {
        apply(
            MarkdownListSupport.normalizedOrderedListMarkers(in: textView.string, selection: textView.selectedRange()),
            to: textView
        )
    }

    /// Applies a whole-document normalization through the AppKit text-mutation contract.
    ///
    /// Both normalizers run from `textDidChange` — *after* NSTextView has closed the undo group
    /// for the keystroke that triggered them. Assigning `textView.string` there rewrites text the
    /// registered undo record already describes by offset, so Cmd+Z would replay that record
    /// against text that had since shifted underneath it. Going through
    /// `shouldChangeText` / `replaceCharacters` / `didChangeText` registers the rewrite as its own
    /// undoable edit instead.
    private func apply(_ result: MarkdownListNormalizationResult, to textView: NSTextView) {
        let originalText = textView.string
        guard result.text != originalText else { return }

        let fullRange = NSRange(location: 0, length: (originalText as NSString).length)
        guard textView.shouldChangeText(in: fullRange, replacementString: result.text) else { return }
        textView.textStorage?.replaceCharacters(in: fullRange, with: result.text)
        textView.setSelectedRange(result.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
    }
}

// MARK: - Pickers

extension MarkdownEditorCoordinator {
    private func updateSlashCommandPicker(for textView: NSTextView) {
        slashCommandPicker.update(
            for: textView,
            context: currentSlashCommandContext(in: textView),
            commands: parent.slashCommands
        ) { [weak self] command, context in
            self?.applySlashCommand(command, context: context, in: textView)
        }
    }

    private func scheduleSlashCommandPickerUpdate(for textView: NSTextView) {
        pendingSlashCommandTextView = textView
        guard !slashCommandUpdateIsScheduled else { return }
        slashCommandUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            slashCommandUpdateIsScheduled = false
            guard let textView = pendingSlashCommandTextView else {
                slashCommandPicker.close()
                return
            }
            pendingSlashCommandTextView = nil
            updateSlashCommandPicker(for: textView)
        }
    }

    private func updateReferencePicker(for textView: NSTextView) {
        let context = currentReferenceCompletionContext(in: textView)
        if context != nil {
            slashCommandPicker.close()
            tagPicker.close()
        }
        referencePicker.update(
            for: textView,
            context: context,
            suggestions: parent.referenceSuggestions
        ) { [weak self] suggestion, context in
            self?.applyReferenceSuggestion(suggestion, context: context, in: textView)
        }
    }

    private func updateTagPicker(for textView: NSTextView) {
        let context = currentTagCompletionContext(in: textView)
        if context != nil {
            slashCommandPicker.close()
            referencePicker.close()
        }
        tagPicker.update(
            for: textView,
            context: context,
            suggestions: parent.tagSuggestions
        ) { [weak self] choice, context in
            self?.applyTagCompletion(choice, context: context, in: textView)
        }
    }

    private func scheduleTagPickerUpdate(for textView: NSTextView) {
        pendingTagTextView = textView
        guard !tagUpdateIsScheduled else { return }
        tagUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            tagUpdateIsScheduled = false
            guard let textView = pendingTagTextView else {
                tagPicker.close()
                return
            }
            pendingTagTextView = nil
            updateTagPicker(for: textView)
        }
    }

    private func scheduleReferencePickerUpdate(for textView: NSTextView) {
        pendingReferenceTextView = textView
        guard !referenceUpdateIsScheduled else { return }
        referenceUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            referenceUpdateIsScheduled = false
            guard let textView = pendingReferenceTextView else {
                referencePicker.close()
                return
            }
            pendingReferenceTextView = nil
            updateReferencePicker(for: textView)
        }
    }

    private func currentSlashCommandContext(in textView: NSTextView) -> MarkdownSlashCommandContext? {
        MarkdownSlashCommandTokenSupport.context(in: textView.string, selection: textView.selectedRange())
    }

    private func applySlashCommand(_ command: MarkdownSlashCommand, context: MarkdownSlashCommandContext, in textView: NSTextView) {
        let mutation = MarkdownSlashCommandMutationSupport.mutation(for: command, context: context)
        guard textView.shouldChangeText(in: mutation.replacementRange, replacementString: mutation.replacement) else {
            slashCommandPicker.close()
            return
        }

        textView.textStorage?.replaceCharacters(in: mutation.replacementRange, with: mutation.replacement)
        textView.setSelectedRange(mutation.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()

        if mutation.followUp == .chooseImage {
            DispatchQueue.main.async { [parent] in
                if let cadenceTextView = textView as? CadenceTextView {
                    cadenceTextView.chooseMarkdownImages()
                } else {
                    parent.onChooseImages()
                }
            }
        }
        slashCommandPicker.close()
    }

    private func currentReferenceCompletionContext(in textView: NSTextView) -> MarkdownReferenceCompletionContext? {
        MarkdownReferenceCompletionSupport.context(in: textView.string, selection: textView.selectedRange())
    }

    private func applyReferenceSuggestion(_ suggestion: MarkdownReferenceSuggestion, context: MarkdownReferenceCompletionContext, in textView: NSTextView) {
        guard textView.shouldChangeText(in: context.range, replacementString: suggestion.markdown) else {
            referencePicker.close()
            return
        }
        textView.textStorage?.replaceCharacters(in: context.range, with: suggestion.markdown)
        textView.setSelectedRange(NSRange(location: context.range.location + (suggestion.markdown as NSString).length, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        referencePicker.close()
    }

    private func currentTagCompletionContext(in textView: NSTextView) -> MarkdownTagCompletionContext? {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return nil }
        let nsText = textView.string as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        return MarkdownTagCompletionTokenSupport.token(in: nsText, cursor: safeCursor)
    }

    private func applyTagCompletion(_ choice: MarkdownTagPickerChoice, context: MarkdownTagCompletionContext, in textView: NSTextView) {
        let suggestion: MarkdownTagSuggestion
        switch choice {
        case .existing(let existing):
            if existing.isArchived, let restored = parent.onCreateTag(existing.name) {
                suggestion = restored
            } else {
                suggestion = existing
            }
        case .create(let name):
            guard let created = parent.onCreateTag(name) else {
                tagPicker.close()
                return
            }
            suggestion = created
        }

        let replacement = "#\(suggestion.slug)"
        guard textView.shouldChangeText(in: context.range, replacementString: replacement) else {
            tagPicker.close()
            return
        }
        textView.textStorage?.replaceCharacters(in: context.range, with: replacement)
        textView.setSelectedRange(NSRange(location: context.range.location + (replacement as NSString).length, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        tagPicker.close()
    }
}
#endif
