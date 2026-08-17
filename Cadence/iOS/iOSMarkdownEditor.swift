#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownEditor: UIViewRepresentable {
    @Environment(\.openURL) private var openURL
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var pendingCommand: MarkdownFormatCommand?
    @Binding var selectedRange: NSRange
    var imageAssets: [MarkdownImageAsset]
    var taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    var onToggleChecklistLine: ((Int) -> Void)?
    var onToggleEmbeddedTask: ((UUID) -> MarkdownTaskEmbedRenderInfo?)?
    var onToggleEmbeddedSubtask: ((UUID, UUID) -> MarkdownTaskEmbedRenderInfo?)?
    var onCreateEmbeddedTask: ((String) -> String?)?
    var onRenameEmbeddedTask: ((UUID, String) -> Void)?
    var onOpenEmbeddedTask: ((UUID) -> Void)?
    var onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?
    var onCreatePastedImages: (([UIImage]) -> [MarkdownImageAsset])?

    init(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        pendingCommand: Binding<MarkdownFormatCommand?> = .constant(nil),
        selectedRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0)),
        imageAssets: [MarkdownImageAsset] = [],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        onToggleChecklistLine: ((Int) -> Void)? = nil,
        onToggleEmbeddedTask: ((UUID) -> MarkdownTaskEmbedRenderInfo?)? = nil,
        onToggleEmbeddedSubtask: ((UUID, UUID) -> MarkdownTaskEmbedRenderInfo?)? = nil,
        onCreateEmbeddedTask: ((String) -> String?)? = nil,
        onRenameEmbeddedTask: ((UUID, String) -> Void)? = nil,
        onOpenEmbeddedTask: ((UUID) -> Void)? = nil,
        onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)? = nil,
        onCreatePastedImages: (([UIImage]) -> [MarkdownImageAsset])? = nil
    ) {
        _text = text
        _isFocused = isFocused
        _pendingCommand = pendingCommand
        _selectedRange = selectedRange
        self.imageAssets = imageAssets
        self.taskEmbeds = taskEmbeds
        self.onToggleChecklistLine = onToggleChecklistLine
        self.onToggleEmbeddedTask = onToggleEmbeddedTask
        self.onToggleEmbeddedSubtask = onToggleEmbeddedSubtask
        self.onCreateEmbeddedTask = onCreateEmbeddedTask
        self.onRenameEmbeddedTask = onRenameEmbeddedTask
        self.onOpenEmbeddedTask = onOpenEmbeddedTask
        self.onOpenReference = onOpenReference
        self.onCreatePastedImages = onCreatePastedImages
    }

    func makeUIView(context: UIViewRepresentableContext<iOSMarkdownEditor>) -> UITextView {
        let textView = iOSMarkdownTextView()
        textView.delegate = context.coordinator
        textView.formatCommandHandler = { [weak textView, weak coordinator = context.coordinator] command in
            guard let textView else { return }
            coordinator?.apply(command, to: textView)
        }
        textView.indentationCommandHandler = { [weak textView, weak coordinator = context.coordinator] increase in
            guard let textView else { return }
            coordinator?.adjustListIndentation(increase: increase, in: textView)
        }
        textView.imagePasteHandler = { [weak textView, weak coordinator = context.coordinator] images in
            guard let textView else { return false }
            return coordinator?.insertPastedImages(images, in: textView) ?? false
        }
        textView.layoutInvalidationHandler = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.refreshStylingIfNeeded(on: textView)
        }
        let referenceTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleReferenceTap(_:))
        )
        referenceTap.cancelsTouchesInView = false
        referenceTap.delaysTouchesBegan = false
        referenceTap.delegate = context.coordinator

        let renderedBlockTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRenderedBlockEditTap(_:))
        )
        renderedBlockTap.numberOfTapsRequired = 2
        // Gated by `gestureRecognizerShouldBegin`, so on ordinary prose this recognizer never
        // begins at all.
        //
        // It used to begin on *every* double tap and act only on the ones landing in a rendered
        // code fence or table — while `cancelsTouchesInView` swallowed the touch for all of them.
        // So a double tap on plain text selected no word and placed no caret: the recognizer had
        // already eaten it before deciding it had nothing to do.
        //
        // Flipping `cancelsTouchesInView` to false would also have unblocked prose, but by relying
        // on cancellation semantics for a recognizer that still begins everywhere — and it would
        // have stopped suppressing the system's own selection *inside* a block, where this handler
        // sets `selectedRange` itself and the two would then race. Not beginning is the stronger
        // guarantee and needs no reasoning about ordering: where the gate says no, the recognizer
        // is inert and the text view behaves exactly as it does with no recognizer attached.
        renderedBlockTap.name = Coordinator.renderedBlockTapName
        renderedBlockTap.cancelsTouchesInView = true
        renderedBlockTap.delaysTouchesBegan = false
        renderedBlockTap.delegate = context.coordinator
        referenceTap.require(toFail: renderedBlockTap)
        textView.addGestureRecognizer(renderedBlockTap)
        textView.addGestureRecognizer(referenceTap)
        textView.backgroundColor = .clear
        // No `inputAccessoryView`. A "Done" bar used to sit above the keyboard here, and its only
        // job was to resign first responder — a permanent 44pt strip of chrome across every editor
        // surface, spending screen the note wants, for one action. What is left to put the keyboard
        // away is `keyboardDismissMode` below — the editor *is* the scroll view, so dragging the
        // text down should drag the keyboard with it. That is the only remaining dismissal on the
        // phone's Notes tab, which hides its navigation bar; every sheet-hosted editor still has
        // its own Done/Cancel above the keyboard. It has **not** been confirmed on a device with a
        // software keyboard up: the simulator suppresses it while a hardware keyboard is attached.
        // If a user reports a stuck keyboard, this line is the first thing to check.
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.isScrollEnabled = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = false
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 18, right: 14)
        textView.textContainer.lineFragmentPadding = 2
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.tintColor = UIColor(Theme.blue)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(Theme.blueLight),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.applyMarkdownStyle(to: textView, text: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: UIViewRepresentableContext<iOSMarkdownEditor>) {
        context.coordinator.parent = self

        if textView.text != text {
            let selection = textView.selectedRange
            context.coordinator.applyMarkdownStyle(to: textView, text: text)
            textView.selectedRange = context.coordinator.clamped(selection, in: textView.textStorage)
            context.coordinator.publishSelectedRange(from: textView)
        } else {
            context.coordinator.refreshStylingIfNeeded(on: textView)
        }

        if let pendingCommand {
            context.coordinator.apply(pendingCommand, to: textView)
            DispatchQueue.main.async {
                self.pendingCommand = nil
            }
        }

        context.coordinator.applyExternalSelectionIfNeeded(to: textView)

        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate {
        private static let markdownStyleRefreshDelay: TimeInterval = 0.08

        var parent: iOSMarkdownEditor
        private var inlineTaskTitleEditor: UITextField?
        private var inlineTaskTitleTaskID: UUID?
        private var isEndingInlineTaskTitleEdit = false
        private var isApplyingStyle = false
        private var styleSignature = iOSMarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], taskEmbeds: [:])
        private var pendingStyleWorkItem: DispatchWorkItem?

        init(parent: iOSMarkdownEditor) {
            self.parent = parent
            styleSignature = iOSMarkdownStyleSignature.current(
                revealedBlockRange: nil,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds
            )
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
            refreshStylingIfNeeded(on: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            publishCurrentText(from: textView)
            parent.isFocused = false
            refreshStylingIfNeeded(on: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingStyle else { return }
            let updatedText = textView.text ?? ""
            if applyTypingTransformIfNeeded(to: textView, text: updatedText) {
                return
            }
            publishSelectedRange(from: textView)
            if parent.text != updatedText {
                parent.text = updatedText
            }
            scheduleMarkdownStyleRefresh(on: textView, text: updatedText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            publishSelectedRange(from: textView)
            // A code fence or table renders as one flat canvas, so the only way to reach its source
            // is for the block holding the caret to un-render itself. Moving the caret in or out of
            // one is not a text edit, so nothing else here would trigger the restyle.
            refreshStylingIfNeeded(on: textView)
        }

        /// The fenced code block or table the caret is inside, which the styler leaves as source
        /// instead of drawing its canvas.
        ///
        /// This replaces the editor's old escape hatch. Both block kinds are drawn as a single
        /// `NSTextAttachment` with every character of the block hidden behind it, so before this
        /// they could only be edited by leaving live mode entirely — a double tap flipped the whole
        /// app to the raw `Edit` mode, which no longer exists. Nil while the editor is unfocused, so
        /// a note at rest always shows finished blocks.
        private func revealedBlockRange(in textView: UITextView) -> NSRange? {
            guard textView.isFirstResponder else { return nil }
            guard let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
                atUTF16Location: textView.selectedRange.location,
                in: textView.text ?? ""
            ) else { return nil }
            switch block.kind {
            case .code, .table:
                return block.storageRange
            case .image, .task, .divider:
                // These are reachable without their source: images come from the picker, task
                // embeds open their own sheet, and a divider is one keystroke to retype.
                return nil
            }
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content else {
                return defaultAction
            }

            return UIAction { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.openLink(url, in: textView)
            }
        }

        private func openLink(_ url: URL, in textView: UITextView) {
            publishCurrentText(from: textView)

            if let target = MarkdownReferenceDisplaySupport.target(from: url) {
                parent.isFocused = false
                textView.resignFirstResponder()
                parent.onOpenReference?(target)
                return
            }

            parent.openURL(url)
        }

        func applyExternalSelectionIfNeeded(to textView: UITextView) {
            let selection = clamped(parent.selectedRange, in: textView.textStorage)
            guard selection != textView.selectedRange else { return }
            textView.selectedRange = selection
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if replacement.isEmpty,
               expandRenderedBlockDeletionIfNeeded(range: range, in: textView) {
                return false
            }

            if replacement.isEmpty,
               deleteListPrefixIfNeeded(range: range, in: textView) {
                return false
            }

            guard replacement == "\n" else { return true }
            if createEmbeddedTaskIfNeeded(in: textView, selection: range) {
                return false
            }

            guard let mutation = MarkdownLineBreakSupport.mutation(
                in: textView.text ?? "",
                selection: range
            ) else { return true }

            guard let textRange = textView.textRange(from: mutation.replacementRange) else { return true }
            textView.replace(textRange, withText: mutation.replacement)
            textView.selectedRange = clamped(mutation.selection, in: textView.textStorage)
            textViewDidChange(textView)
            return false
        }

        /// Turns the `( ) …` line under the caret into a real task embed, on Return.
        ///
        /// Return is the only trigger. Typing the marker used to create an "Untitled Task" the
        /// instant the trailing space landed, and then put the selection on the reference's title —
        /// characters the styler hides behind the rendered card. So the caret was invisible, the
        /// title could not be typed where the user was looking, and typing anyway rewrote
        /// `[[task:UUID|Title]]` without renaming the task. Waiting for Return means the title is
        /// typed in plain visible text and the task is created already named.
        private func createEmbeddedTaskIfNeeded(in textView: UITextView, selection: NSRange) -> Bool {
            guard selection.length == 0,
                  let onCreateEmbeddedTask = parent.onCreateEmbeddedTask else {
                return false
            }

            let markdown = textView.text ?? ""
            let nsText = markdown as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: min(selection.location, nsText.length), length: 0))
            let rawLine = nsText.substring(with: NSRange(
                location: lineRange.location,
                length: min(lineRange.length, nsText.length - lineRange.location)
            ))
            let line = rawLine.trimmingCharacters(in: .newlines)
            let draftTitle = MarkdownTaskEmbedParser.draftTitle(in: line)
                ?? (MarkdownTaskEmbedParser.isUntitledDraftLine(line)
                    ? MarkdownTaskEmbedRenderInfo.untitledTaskTitle
                    : nil)

            guard selection.location >= lineRange.location + (line as NSString).length,
                  let title = draftTitle,
                  let taskReference = onCreateEmbeddedTask(title),
                  MarkdownTaskEmbedParser.standaloneTaskReference(in: taskReference) != nil else {
                return false
            }

            let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
            guard let textRange = textView.textRange(from: contentRange) else { return false }
            let replacement = taskReference + "\n"
            textView.replace(textRange, withText: replacement)
            textView.selectedRange = clamped(
                NSRange(location: contentRange.location + (replacement as NSString).length, length: 0),
                in: textView.textStorage
            )
            textViewDidChange(textView)
            return true
        }

        private func expandRenderedBlockDeletionIfNeeded(range: NSRange, in textView: UITextView) -> Bool {
            let markdown = textView.text ?? ""
            guard let deletionRange = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(
                in: markdown,
                selection: range
            ), deletionRange != range else {
                return false
            }

            guard let textRange = textView.textRange(from: deletionRange) else {
                return false
            }
            textView.replace(textRange, withText: "")
            textView.selectedRange = NSRange(location: deletionRange.location, length: 0)
            textViewDidChange(textView)
            return true
        }

        private func deleteListPrefixIfNeeded(range: NSRange, in textView: UITextView) -> Bool {
            guard let mutation = MarkdownBackspaceSupport.listPrefixMutation(
                in: textView.text ?? "",
                selection: range
            ) else {
                return false
            }

            guard let textRange = textView.textRange(from: mutation.replacementRange) else {
                return false
            }
            textView.replace(textRange, withText: mutation.replacement)
            textView.selectedRange = clamped(mutation.selection, in: textView.textStorage)
            textViewDidChange(textView)
            return true
        }

        func refreshStylingIfNeeded(on textView: UITextView) {
            guard !isApplyingStyle else { return }
            let current = iOSMarkdownStyleSignature.current(
                revealedBlockRange: revealedBlockRange(in: textView),
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds,
                contentWidth: textView.markdownContentWidth
            )
            guard current != styleSignature else { return }
            styleSignature = current
            let selection = textView.selectedRange
            applyMarkdownStyle(to: textView, text: textView.text ?? "")
            textView.selectedRange = clamped(selection, in: textView.textStorage)
        }

        func apply(_ command: MarkdownFormatCommand, to textView: UITextView) {
            let mutation = MarkdownFormatCommandSupport.apply(
                command,
                text: textView.text ?? "",
                selection: textView.selectedRange
            )
            parent.text = mutation.text
            applyMarkdownStyle(to: textView, text: mutation.text)
            textView.selectedRange = clamped(mutation.selection, in: textView.textStorage)
            publishSelectedRange(from: textView)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        func adjustListIndentation(increase: Bool, in textView: UITextView) {
            guard let result = MarkdownListSupport.adjustedListIndentation(
                in: textView.text ?? "",
                selection: textView.selectedRange,
                increase: increase
            ) else { return }

            parent.text = result.text
            applyMarkdownStyle(to: textView, text: result.text)
            textView.selectedRange = clamped(result.selection, in: textView.textStorage)
            publishSelectedRange(from: textView)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        func insertPastedImages(_ images: [UIImage], in textView: UITextView) -> Bool {
            guard !images.isEmpty,
                  let assets = parent.onCreatePastedImages?(images),
                  !assets.isEmpty else {
                return false
            }

            let markdown = assets
                .map { MarkdownImageAssetService.markdown(for: $0) }
                .joined(separator: "\n\n")
            let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
                markdown,
                in: textView.text ?? "",
                selection: textView.selectedRange
            )
            apply(.insertMarkdown(insertion), to: textView)
            return true
        }

        private func applyTypingTransformIfNeeded(to textView: UITextView, text: String) -> Bool {
            guard let mutation = MarkdownTypingTransformSupport.mutation(
                in: text,
                cursor: textView.selectedRange.location
            ) else {
                return false
            }

            parent.text = mutation.text
            applyMarkdownStyle(to: textView, text: mutation.text)
            textView.selectedRange = clamped(mutation.selection, in: textView.textStorage)
            publishSelectedRange(from: textView)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            return true
        }

        func applyMarkdownStyle(to textView: UITextView, text: String) {
            isApplyingStyle = true
            defer { isApplyingStyle = false }

            let storage = textView.textStorage
            let revealed = revealedBlockRange(in: textView)
            let styled = iOSMarkdownStyler.attributedString(
                for: text,
                revealedBlockRange: revealed,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds,
                contentWidth: textView.markdownContentWidth
            )
            storage.setAttributedString(styled)
            textView.typingAttributes = iOSMarkdownStyler.baseTypingAttributes
            styleSignature = iOSMarkdownStyleSignature.current(
                revealedBlockRange: revealed,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds,
                contentWidth: textView.markdownContentWidth
            )
        }

        private func scheduleMarkdownStyleRefresh(on textView: UITextView, text: String) {
            pendingStyleWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, !self.isApplyingStyle else { return }
                guard textView.text == text else { return }
                let selection = textView.selectedRange
                self.applyMarkdownStyle(to: textView, text: text)
                textView.selectedRange = self.clamped(selection, in: textView.textStorage)
            }
            pendingStyleWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.markdownStyleRefreshDelay, execute: workItem)
        }

        private func publishCurrentText(from textView: UITextView) {
            publishSelectedRange(from: textView)
            let currentText = textView.text ?? ""
            if parent.text != currentText {
                parent.text = currentText
            }
        }

        func publishSelectedRange(from textView: UITextView) {
            var selection = clamped(textView.selectedRange, in: textView.textStorage)
            // Same rule as the caret snap below, applied to a range: a selection that only covers
            // characters the editor draws a card, image or rule over is a selection of nothing, so
            // it collapses to the far edge of the block rather than showing handles over the canvas.
            if let collapsed = MarkdownRenderedBlockDeletionSupport.collapsedSelection(
                for: selection,
                in: textView.text ?? ""
            ) {
                selection = clamped(collapsed, in: textView.textStorage)
                textView.selectedRange = selection
            }
            if selection.length == 0 {
                let movingForward = selection.location >= parent.selectedRange.location
                let snapped = MarkdownHiddenRangeSupport.snappedCaretLocation(
                    selection.location,
                    in: textView.textStorage,
                    preferringForward: movingForward
                )
                if snapped != selection.location {
                    selection = NSRange(location: snapped, length: 0)
                    textView.selectedRange = selection
                }
            }
            guard parent.selectedRange != selection else { return }
            parent.selectedRange = selection
        }

        @objc func handleReferenceTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let textView = recognizer.view as? UITextView else {
                return
            }

            if let onToggleChecklistLine = parent.onToggleChecklistLine,
               let lineIndex = checklistLineIndex(at: recognizer.location(in: textView), in: textView) {
                publishCurrentText(from: textView)
                onToggleChecklistLine(lineIndex)
                return
            }

            let location = recognizer.location(in: textView)
            if let hit = taskEmbedHit(at: location, in: textView) {
                publishCurrentText(from: textView)
                handleTaskEmbedHit(hit, in: textView)
                return
            }

            if let onOpenReference = parent.onOpenReference,
               let target = referenceTarget(at: location, in: textView) {
                publishCurrentText(from: textView)
                parent.isFocused = false
                textView.resignFirstResponder()
                onOpenReference(target)
                return
            }

            if let url = markdownLinkURL(at: location, in: textView) {
                publishCurrentText(from: textView)
                parent.openURL(url)
            }
        }

        /// Double-tapping a rendered code fence or table puts the caret in it.
        ///
        /// `revealedBlockRange(in:)` then keeps that block as editable source for as long as the
        /// caret stays inside it. This used to flip the whole app into the raw `Edit` mode instead,
        /// which persisted app-wide and took every other editor with it.
        @objc func handleRenderedBlockEditTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let textView = recognizer.view as? UITextView,
                  let block = revealableBlock(at: recognizer.location(in: textView), in: textView) else {
                return
            }

            publishCurrentText(from: textView)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            let selection = clamped(block.storageRange, in: textView.textStorage)
            textView.selectedRange = selection
            parent.selectedRange = selection
            parent.isFocused = true
            refreshStylingIfNeeded(on: textView)
        }

        private func handleTaskEmbedHit(
            _ hit: (task: MarkdownTaskEmbedRenderInfo, target: iOSMarkdownTaskEmbedHitTarget, cardRect: CGRect),
            in textView: UITextView
        ) {
            guard !hit.task.isMissing else { return }
            let refreshed: MarkdownTaskEmbedRenderInfo?
            switch hit.target {
            case .checkbox:
                refreshed = parent.onToggleEmbeddedTask?(hit.task.id)
            case .subtaskCheckbox(let subtaskID):
                refreshed = parent.onToggleEmbeddedSubtask?(hit.task.id, subtaskID)
            case .title:
                beginInlineTaskTitleEdit(task: hit.task, cardRect: hit.cardRect, in: textView)
                return
            case .card:
                parent.isFocused = false
                textView.resignFirstResponder()
                parent.onOpenEmbeddedTask?(hit.task.id)
                return
            }

            if let refreshed {
                parent.taskEmbeds[refreshed.id] = refreshed
                let selection = textView.selectedRange
                applyMarkdownStyle(to: textView, text: textView.text ?? "")
                textView.selectedRange = clamped(selection, in: textView.textStorage)
            }
        }

        /// Renaming an embed: a text field over the card's title, mirroring macOS.
        ///
        /// Before this there was no way to change a task embed's title from iOS at all. The Mac
        /// puts an `NSTextField` over `MarkdownTaskEmbedDrawing.titleRect` and commits through
        /// `onRenameEmbeddedMarkdownTask` + `replaceEmbeddedTaskReferenceTitle`; this is the same
        /// two steps with the same two effects — rename the task, then rewrite the note's
        /// `[[task:UUID|Title]]` source so the card and the text it is drawn over do not drift
        /// apart.
        ///
        /// What differs from macOS, and why:
        /// - The Mac reaches this from a mouse-down on the title with a hover highlight already
        ///   telling you the title is a control. Touch has no hover, so the title's rect is simply
        ///   the tap target; everywhere else on the card still opens the task.
        /// - Committing returns first responder to the text view rather than to a window, because
        ///   the keyboard is already up and taking it away to put it straight back flickers.
        private func beginInlineTaskTitleEdit(
            task: MarkdownTaskEmbedRenderInfo,
            cardRect: CGRect,
            in textView: UITextView
        ) {
            endInlineTaskTitleEdit(commit: true, in: textView)

            let titleRect = iOSMarkdownTaskEmbedLayoutInfo(task: task)
                .titleRect(maxWidth: textView.markdownContentWidth)
                .offsetBy(dx: cardRect.minX, dy: cardRect.minY)
                .offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)

            let editor = UITextField(frame: titleRect.insetBy(dx: -4, dy: -2))
            editor.text = task.title == MarkdownTaskEmbedRenderInfo.untitledTaskTitle ? "" : task.title
            editor.placeholder = MarkdownTaskEmbedRenderInfo.untitledTaskTitle
            editor.font = .systemFont(ofSize: 14, weight: .semibold)
            editor.textColor = UIColor(Theme.text)
            editor.backgroundColor = UIColor(Theme.surfaceHighlight)
            editor.tintColor = UIColor(Theme.blue)
            editor.borderStyle = .none
            editor.layer.cornerRadius = 6
            editor.autocorrectionType = .no
            editor.autocapitalizationType = .none
            editor.returnKeyType = .done
            editor.clearButtonMode = .never
            editor.delegate = self
            textView.addSubview(editor)
            inlineTaskTitleEditor = editor
            inlineTaskTitleTaskID = task.id
            editor.becomeFirstResponder()
            editor.selectAll(nil)
        }

        private func endInlineTaskTitleEdit(commit: Bool, in textView: UITextView) {
            guard !isEndingInlineTaskTitleEdit,
                  let editor = inlineTaskTitleEditor,
                  let taskID = inlineTaskTitleTaskID else { return }
            isEndingInlineTaskTitleEdit = true
            let rawTitle = TaskTitleSupport.normalized(editor.text ?? "")
            let referenceTitle = TaskTitleSupport.priorityShortcut(in: rawTitle)?.title ?? rawTitle
            editor.delegate = nil
            editor.removeFromSuperview()
            inlineTaskTitleEditor = nil
            inlineTaskTitleTaskID = nil
            if commit {
                parent.onRenameEmbeddedTask?(taskID, rawTitle)
                replaceEmbeddedTaskReferenceTitle(id: taskID, title: referenceTitle, in: textView)
            }
            isEndingInlineTaskTitleEdit = false
        }

        /// The iOS half of the rename: the note's own source.
        ///
        /// Renaming the task alone is not enough — the title also lives in the note text, inside
        /// `[[task:UUID|Title]]`, and a card whose drawn title disagrees with the markdown under it
        /// is exactly the drift a task embed is supposed to avoid. Which runs to rewrite and what a
        /// title may look like inside a reference are `MarkdownTaskEmbedParser`'s, shared with the
        /// Mac; this is only the `UITextView` mutation, done through `replace(_:withText:)` so the
        /// edit lands on the text view's own undo stack.
        private func replaceEmbeddedTaskReferenceTitle(id: UUID, title: String, in textView: UITextView) {
            let displayTitle = MarkdownTaskEmbedParser.sanitizedReferenceTitle(
                title,
                fallback: MarkdownTaskEmbedRenderInfo.untitledTaskTitle
            )
            let markdown = textView.text ?? ""
            let nsMarkdown = markdown as NSString
            let titleRanges = MarkdownTaskEmbedParser.referenceTitleRanges(of: id, in: markdown)
            var didReplace = false
            // Back to front: every replacement shifts the ranges after it.
            for range in titleRanges.reversed() {
                guard nsMarkdown.substring(with: range) != displayTitle,
                      let textRange = textView.textRange(from: range) else { continue }
                textView.replace(textRange, withText: displayTitle)
                didReplace = true
            }
            guard didReplace, let anchor = titleRanges.first?.location else { return }

            // `replace(_:withText:)` leaves the caret at the end of what it inserted, which is in
            // the middle of `[[task:UUID|Title]]` — hidden characters with a card drawn over them.
            // Sitting there opens the `[[` completion strip against a reference the user never
            // typed ("No matching tasks"), and `snappedCaretLocation` cannot rescue it: the newly
            // inserted run does not carry the hidden attribute until the restyle lands 80ms later.
            // So the caret goes where `collapsedSelection` already sends anything that lands inside
            // a rendered block — the block's far edge — instead of a third rule about where a caret
            // may sit.
            if let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
                atUTF16Location: anchor,
                in: textView.text ?? ""
            ) {
                textView.selectedRange = clamped(
                    NSRange(location: NSMaxRange(block.storageRange), length: 0),
                    in: textView.textStorage
                )
            }
            textViewDidChange(textView)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField === inlineTaskTitleEditor,
                  let textView = textField.superview as? UITextView else { return true }
            endInlineTaskTitleEdit(commit: true, in: textView)
            textView.becomeFirstResponder()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard textField === inlineTaskTitleEditor,
                  let textView = textField.superview as? UITextView else { return }
            endInlineTaskTitleEdit(commit: true, in: textView)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        static let renderedBlockTapName = "cadence.markdown.renderedBlockTap"

        /// Keeps the rendered-block double tap from beginning anywhere it has nothing to do.
        ///
        /// The same test `handleRenderedBlockEditTap` runs, moved one step earlier. Running it in
        /// the handler was too late: by then the recognizer had begun and taken the touch, so the
        /// text view never saw the double tap that was meant for it.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer.name == Self.renderedBlockTapName,
                  let textView = gestureRecognizer.view as? UITextView else { return true }
            return revealableBlock(at: gestureRecognizer.location(in: textView), in: textView) != nil
        }

        /// The one definition of "a double tap here reveals source": a rendered code fence or
        /// table. Read by the gate above and by the handler, so the two cannot disagree about
        /// which taps this recognizer owns.
        private func revealableBlock(
            at point: CGPoint,
            in textView: UITextView
        ) -> MarkdownRenderedBlock? {
            guard let hit = characterHit(at: point, in: textView, hitPadding: 18),
                  let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
                    atUTF16Location: hit.characterIndex,
                    in: textView.text ?? ""
                  ),
                  block.kind == .code || block.kind == .table else {
                return nil
            }
            return block
        }

        private func referenceTarget(
            at point: CGPoint,
            in textView: UITextView
        ) -> MarkdownReferenceDisplayTarget? {
            guard let hit = characterHit(at: point, in: textView, hitPadding: 8) else { return nil }
            let markdown = textView.text ?? ""
            return MarkdownReferenceDisplaySupport.target(atUTF16Location: hit.characterIndex, in: markdown) ??
                MarkdownReferenceDisplaySupport.target(atUTF16Location: hit.characterIndex, in: markdown, includesHiddenSyntax: true)
        }

        private func markdownLinkURL(
            at point: CGPoint,
            in textView: UITextView
        ) -> URL? {
            guard let hit = characterHit(at: point, in: textView, hitPadding: 8) else { return nil }
            let markdown = textView.text ?? ""
            return MarkdownLinkSupport.linkURL(atUTF16Location: hit.characterIndex, in: markdown) ??
                MarkdownLinkSupport.linkURL(atUTF16Location: hit.characterIndex, in: markdown, includesHiddenSyntax: true)
        }

        /// The task-embed card under a touch, and which part of it was touched.
        ///
        /// The rect tested is the rect the card was drawn into — `iOSMarkdownBlockCanvas.blockRect`,
        /// the same function `iOSMarkdownBlockCanvasLayoutManager` paints from — rather than a
        /// second guess at the geometry.
        ///
        /// It used to test `boundingRect(forGlyphRange:in:)` over the run's first character. A
        /// rendered block hides every one of its characters at 0.1pt, so that rect was a tenth of a
        /// point wide even though the line fragment around it was a whole card tall. Padded by 8 it
        /// covered roughly the leading 8pt of the card and nothing else: everywhere else the tap
        /// missed, fell through to the text view, and placed a caret in hidden markdown instead of
        /// opening the task.
        private func taskEmbedHit(
            at point: CGPoint,
            in textView: UITextView
        ) -> (task: MarkdownTaskEmbedRenderInfo, target: iOSMarkdownTaskEmbedHitTarget, cardRect: CGRect)? {
            guard let card = taskEmbedCard(at: point, in: textView) else { return nil }
            let localPoint = CGPoint(x: card.textPoint.x - card.rect.minX, y: card.textPoint.y - card.rect.minY)
            let target = iOSMarkdownTaskEmbedLayoutInfo(task: card.task).hitTarget(
                at: localPoint,
                maxWidth: textView.markdownContentWidth
            )
            return (card.task, target, card.rect)
        }

        /// The drawn card under a touch, with the rect it occupies in text-container coordinates.
        ///
        /// Split out from `taskEmbedHit` because the inline title editor needs the rect as well as
        /// the hit — it has to be placed over the title it is replacing.
        private func taskEmbedCard(
            at point: CGPoint,
            in textView: UITextView
        ) -> (task: MarkdownTaskEmbedRenderInfo, rect: CGRect, textPoint: CGPoint, range: NSRange)? {
            guard textView.bounds.contains(point), textView.textStorage.length > 0 else { return nil }

            let textContainer = textView.textContainer
            let layoutManager = textView.layoutManager
            var textPoint = point
            textPoint.x -= textView.textContainerInset.left
            textPoint.y -= textView.textContainerInset.top
            layoutManager.ensureLayout(for: textContainer)

            var result: (task: MarkdownTaskEmbedRenderInfo, rect: CGRect, textPoint: CGPoint, range: NSRange)?
            let fullRange = NSRange(location: 0, length: textView.textStorage.length)
            textView.textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: fullRange, options: []) { value, range, stop in
                guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                      range.location < textView.textStorage.length,
                      let canvas = textView.textStorage.attribute(
                        .cadenceMarkdownBlockCanvas,
                        at: range.location,
                        effectiveRange: nil
                      ) as? iOSMarkdownBlockCanvas else { return }

                let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
                guard glyphIndex < layoutManager.numberOfGlyphs else { return }
                let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let cardRect = iOSMarkdownBlockCanvas.blockRect(
                    inLineFragment: fragment,
                    size: canvas.image.size,
                    leadingInset: canvas.leadingInset,
                    yOffset: canvas.yOffset
                )
                guard cardRect.insetBy(dx: -4, dy: -4).contains(textPoint) else { return }

                result = (embed.task, cardRect, textPoint, range)
                stop.pointee = true
            }
            return result
        }

        private func checklistLineIndex(
            at point: CGPoint,
            in textView: UITextView
        ) -> Int? {
            guard let hit = characterHit(at: point, in: textView, hitPadding: 14) else { return nil }
            let markdown = textView.text ?? ""
            let nsText = markdown as NSString
            guard nsText.length > 0 else { return nil }

            let location = min(hit.characterIndex, nsText.length - 1)
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            guard contentsEnd >= lineStart else { return nil }

            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = nsText.substring(with: lineRange)
            guard let markerRange = MarkdownChecklistSupport.lineInfo(in: line)?.markerRange else { return nil }
            let absoluteMarkerRange = NSRange(location: lineStart + markerRange.location, length: markerRange.length)
            let lineIndex = nsText.substring(to: lineStart).filter { $0 == "\n" }.count

            if NSLocationInRange(hit.characterIndex, absoluteMarkerRange) {
                return lineIndex
            }

            let markerGlyphIndex = textView.layoutManager.glyphIndexForCharacter(at: absoluteMarkerRange.location)
            guard markerGlyphIndex < textView.layoutManager.numberOfGlyphs else { return nil }
            let markerRect = textView.layoutManager.boundingRect(
                forGlyphRange: NSRange(location: markerGlyphIndex, length: 1),
                in: textView.textContainer
            )
            .insetBy(dx: -12, dy: -10)
            return markerRect.contains(hit.textPoint) ? lineIndex : nil
        }

        private func characterHit(
            at point: CGPoint,
            in textView: UITextView,
            hitPadding: CGFloat
        ) -> (characterIndex: Int, textPoint: CGPoint)? {
            guard textView.bounds.contains(point), textView.textStorage.length > 0 else { return nil }

            let textContainer = textView.textContainer
            let layoutManager = textView.layoutManager
            var textPoint = point
            textPoint.x -= textView.textContainerInset.left
            textPoint.y -= textView.textContainerInset.top

            let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            ).insetBy(dx: -hitPadding, dy: -hitPadding)
            guard glyphRect.contains(textPoint) else { return nil }

            return (layoutManager.characterIndexForGlyph(at: glyphIndex), textPoint)
        }

        func clamped(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
            let location = min(max(0, range.location), storage.length)
            let length = min(range.length, max(0, storage.length - location))
            return NSRange(location: location, length: length)
        }
    }
}

private extension UITextView {
    var markdownContentWidth: CGFloat {
        max(
            1,
            bounds.width - textContainerInset.left - textContainerInset.right - (textContainer.lineFragmentPadding * 2)
        )
    }
}

#endif
