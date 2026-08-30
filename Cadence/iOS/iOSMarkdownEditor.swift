#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownEditor: UIViewRepresentable {
    @Environment(\.openURL) private var openURL
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var selectedRange: NSRange
    var imageAssets: [MarkdownImageAsset]
    var taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    var onToggleChecklistLine: ((Int) -> Void)?
    var onToggleEmbeddedTask: ((UUID) -> MarkdownTaskEmbedRenderInfo?)?
    var onToggleEmbeddedSubtask: ((UUID, UUID) -> MarkdownTaskEmbedRenderInfo?)?
    var onCreateEmbeddedTask: ((String) -> String?)?
    var onOpenEmbeddedTask: ((UUID) -> Void)?
    var onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?
    var onCreatePastedImages: (([UIImage]) -> [MarkdownImageAsset])?
    var onResizeImage: ((UUID, CGFloat) -> Void)?
    /// `iOSMarkdownEditingSurface.allowsImageInsertion`, carried down to the text view so the edit
    /// menu can refuse in the same breath as the toolbar button, the `/` strip and the creator
    /// (T-504). The macOS twin is `MarkdownEditorView.allowsImageInsertion`.
    ///
    /// A separate value rather than `onCreatePastedImages == nil`: the handler is assigned
    /// unconditionally in `makeUIView` on purpose, and passing `nil` for a refusing host would make
    /// the paste *swallowed* instead of merely unoffered.
    var allowsImageInsertion = true

    init(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        selectedRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0)),
        imageAssets: [MarkdownImageAsset] = [],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        onToggleChecklistLine: ((Int) -> Void)? = nil,
        onToggleEmbeddedTask: ((UUID) -> MarkdownTaskEmbedRenderInfo?)? = nil,
        onToggleEmbeddedSubtask: ((UUID, UUID) -> MarkdownTaskEmbedRenderInfo?)? = nil,
        onCreateEmbeddedTask: ((String) -> String?)? = nil,
        onOpenEmbeddedTask: ((UUID) -> Void)? = nil,
        onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)? = nil,
        onCreatePastedImages: (([UIImage]) -> [MarkdownImageAsset])? = nil,
        onResizeImage: ((UUID, CGFloat) -> Void)? = nil,
        allowsImageInsertion: Bool = true
    ) {
        _text = text
        _isFocused = isFocused
        _selectedRange = selectedRange
        self.imageAssets = imageAssets
        self.taskEmbeds = taskEmbeds
        self.onToggleChecklistLine = onToggleChecklistLine
        self.onToggleEmbeddedTask = onToggleEmbeddedTask
        self.onToggleEmbeddedSubtask = onToggleEmbeddedSubtask
        self.onCreateEmbeddedTask = onCreateEmbeddedTask
        self.onOpenEmbeddedTask = onOpenEmbeddedTask
        self.onOpenReference = onOpenReference
        self.onCreatePastedImages = onCreatePastedImages
        self.onResizeImage = onResizeImage
        self.allowsImageInsertion = allowsImageInsertion
    }

    func makeUIView(context: UIViewRepresentableContext<iOSMarkdownEditor>) -> UITextView {
        let textView = iOSMarkdownTextView()
        textView.delegate = context.coordinator
        textView.allowsMarkdownImageInsertion = allowsImageInsertion
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
        // A single tap on a rendered table cell opens that cell, the way a single click does on the
        // Mac. Gated in `gestureRecognizerShouldBegin` exactly like the recognizer above, and
        // `cancelsTouchesInView` is true here for a reason the reference tap does not have: every
        // character of a rendered table is hidden, so letting the text view also see the touch would
        // drop a caret into invisible markdown and raise the keyboard behind the cell field.
        let tableCellTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTableCellTap(_:))
        )
        tableCellTap.name = Coordinator.tableCellTapName
        tableCellTap.cancelsTouchesInView = true
        tableCellTap.delaysTouchesBegan = false
        tableCellTap.delegate = context.coordinator

        referenceTap.require(toFail: renderedBlockTap)
        referenceTap.require(toFail: tableCellTap)
        textView.addGestureRecognizer(renderedBlockTap)
        textView.addGestureRecognizer(tableCellTap)
        textView.addGestureRecognizer(referenceTap)

        // Rows and columns change from the table's own long-press menu, and so does the raw-source
        // escape. Same decision as the Mac's right-click menu and for the same reasons: hover-style
        // chrome would be a second hit-testing surface over a canvas that already has one, it has
        // to be discovered, and on a touch screen there is no hover to reveal it with. The delegate
        // returns nil anywhere off a grid, so ordinary prose keeps the text view's own menu.
        textView.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))

        let imageResize = iOSMarkdownImageResizeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleImageResize(_:))
        )
        imageResize.name = Coordinator.imageResizeName
        imageResize.maximumNumberOfTouches = 1
        imageResize.delaysTouchesBegan = false
        // The touch belongs to the handle once this recognizer has taken it; letting the text view
        // also see it would place a caret under the finger mid-drag.
        imageResize.cancelsTouchesInView = true
        imageResize.delegate = context.coordinator
        imageResize.handleHitTest = { [weak textView, weak coordinator = context.coordinator] point in
            guard let textView, let coordinator else { return nil }
            return coordinator.imageResizeHit(at: point, in: textView)
        }
        // Safe precisely because the recognizer above fails inside `touchesBegan` for every touch
        // that is not on a handle: the requirement is satisfied in the same event, so scrolling is
        // not delayed anywhere else in the note.
        textView.panGestureRecognizer.require(toFail: imageResize)
        textView.addGestureRecognizer(imageResize)

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
        // Set on every pass, not only at creation: quick create flips its image policy with the
        // sheet's mode (`kind != .event`) while the same text view stays alive, so a value written
        // once in `makeUIView` would leave the edit menu offering whichever mode the sheet opened in.
        (textView as? iOSMarkdownTextView)?.allowsMarkdownImageInsertion = allowsImageInsertion

        if textView.text != text {
            let selection = textView.selectedRange
            context.coordinator.applyMarkdownStyle(to: textView, text: text)
            textView.selectedRange = context.coordinator.clamped(selection, in: textView.textStorage)
            context.coordinator.publishSelectedRange(from: textView)
        } else {
            context.coordinator.refreshStylingIfNeeded(on: textView)
        }

        // No `pendingCommand` binding here. There were two ways to reach `Coordinator.apply` and
        // only one of them was ever used: the hardware keyboard's shortcuts, which arrive through
        // `iOSMarkdownTextView.formatCommandHandler` in `makeUIView` above. The SwiftUI side never
        // injected a command — `iOSMarkdownEditingSurface` runs the same
        // `MarkdownFormatCommandSupport.apply` against its own draft (`applyCommandToDraft`) and
        // lets the text change flow back down through `text`, which is what the toolbar, the slash
        // strip and the reference pickers all do. The binding was a second transport to a
        // destination that was already reachable, not a feature routed around.
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

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate, UITextFieldDelegate {
        private static let markdownStyleRefreshDelay: TimeInterval = 0.08

        var parent: iOSMarkdownEditor
        private var isApplyingStyle = false
        private var styleSignature = MarkdownStyleSignature.current(revealedBlockRange: nil, imageAssets: [], taskEmbeds: [:])
        private var pendingStyleWorkItem: DispatchWorkItem?

        // MARK: - Rendered tables (T-221)

        /// The tables whose markdown is deliberately on screen, by each one's first character.
        ///
        /// A **command**, never an accident of caret position — that is the whole ticket. Anchored
        /// to a storage location rather than a line index so an edit *inside* a revealed table keeps
        /// it revealed, while an edit above it drops back to the grid.
        var tableSourceAnchors: Set<Int> = []
        var tableCellEditor: iOSMarkdownTableCellField?
        var tableCellEditAddress: MarkdownTableCellAddress?
        var tableCellEditAnchor: Int?
        var isEndingTableCellEdit = false
        /// Set across a table mutation so the delegate callback `replace(_:withText:)` raises does
        /// not also publish and schedule a debounced restyle behind one this path already ran.
        var isApplyingTableEdit = false
        /// The write currently in flight through `replaceProgrammatically`, and `nil` the rest of
        /// the time.
        ///
        /// Read by `shouldChangeTextIn` to tell Cadence's own write from the substitutions UIKit
        /// proposes around it — see `MarkdownProgrammaticEditSupport` for the measurement that made
        /// this necessary and for why the smart-punctuation traits are not the lever.
        var pendingProgrammaticEdit: MarkdownProgrammaticEdit?

        init(parent: iOSMarkdownEditor) {
            self.parent = parent
            styleSignature = MarkdownStyleSignature.current(
                revealedBlockRange: nil,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds
            )
        }

        /// **The one programmatic write into the text view.**
        ///
        /// `UITextView.replace(_:withText:)` and not `textView.text = …` or a reach into
        /// `textStorage`: only the `UITextInput` route registers the change on the view's own undo
        /// manager, which is what keeps every markdown mutation an ordinary undo away.
        ///
        /// It is also the route UIKit runs its smart-punctuation pass through, over the words
        /// either side of the range written — which rewrote a table's `---` delimiter to an em dash
        /// on every cell commit until this window existed. Announcing the write is what lets
        /// `shouldChangeTextIn` refuse everything that is not it; the traits do not, measured.
        /// Every call site here goes through this function, and
        /// `MarkdownTableMobileEditingTests` fails if a second raw `replace(_:withText:)` appears.
        @discardableResult
        func replaceProgrammatically(
            _ range: NSRange,
            with replacement: String,
            in textView: UITextView
        ) -> Bool {
            guard let textRange = textView.textRange(from: range) else { return false }
            pendingProgrammaticEdit = MarkdownProgrammaticEdit(range: range, replacement: replacement)
            defer { pendingProgrammaticEdit = nil }
            textView.replace(textRange, withText: replacement)
            return true
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
            guard !isApplyingStyle, !isApplyingTableEdit else { return }
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

        /// The fenced code block the caret is inside, which the styler leaves as source instead of
        /// drawing its canvas.
        ///
        /// **`.table` used to be in here beside `.code`, and removing it is T-221.** A table that
        /// un-renders the moment you touch it is a table you edit by typing pipes, which is the
        /// complaint the ticket opened with; its source is reachable by the **Show Table Source**
        /// command instead (`tableSourceAnchors`), never by caret position. A code fence keeps the
        /// caret rule because its content *is* text you type — there is no cell to host.
        ///
        /// Nil while the editor is unfocused, so a note at rest always shows finished blocks.
        private func revealedBlockRange(in textView: UITextView) -> NSRange? {
            guard textView.isFirstResponder else { return nil }
            guard let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
                atUTF16Location: textView.selectedRange.location,
                in: textView.text ?? ""
            ) else { return nil }
            switch block.kind {
            case .code:
                return block.storageRange
            case .image, .task, .divider, .table:
                // These are reachable without their source: images come from the picker, task
                // embeds open their own sheet, a divider is one keystroke to retype, and a table is
                // edited cell by cell where it is drawn.
                return nil
            }
        }

        /// Every block currently showing its own markdown, by whichever route.
        ///
        /// The two routes are deliberately different shapes — a code fence reveals by caret, a table
        /// only by command — and every rule that protects a reader from editing text they cannot see
        /// has to stand down for both. Passed to `MarkdownRenderedBlockDeletionSupport`, which is
        /// where those rules live.
        func sourceRevealedRanges(in textView: UITextView) -> [NSRange] {
            var ranges: [NSRange] = []
            if let revealed = revealedBlockRange(in: textView) {
                ranges.append(revealed)
            }
            guard !tableSourceAnchors.isEmpty else { return ranges }
            let markdown = textView.text ?? ""
            ranges.append(contentsOf: MarkdownTableEditor.grids(in: markdown)
                .filter { tableSourceAnchors.contains($0.storageRange.location) }
                .map(\.storageRange))
            return ranges
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
            // Answered first and returned from directly, before any of the editor's own rules. A
            // proposal that *is* the write in flight has already been decided on by the caller that
            // asked for it, and re-entering the line-break and deletion rules underneath it would
            // ask them to reason about a document mid-edit. Everything else arriving in that window
            // is UIKit's, and is refused.
            if let pending = pendingProgrammaticEdit {
                return MarkdownProgrammaticEditSupport.acceptsDelegateChange(
                    range: range,
                    replacement: replacement,
                    whileWriting: pending
                )
            }

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

            guard replaceProgrammatically(
                mutation.replacementRange,
                with: mutation.replacement,
                in: textView
            ) else { return true }
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
            let replacement = taskReference + "\n"
            guard replaceProgrammatically(contentRange, with: replacement, in: textView) else { return false }
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
                selection: range,
                sourceRevealedRanges: sourceRevealedRanges(in: textView)
            ), deletionRange != range else {
                return false
            }

            guard replaceProgrammatically(deletionRange, with: "", in: textView) else {
                return false
            }
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

            guard replaceProgrammatically(
                mutation.replacementRange,
                with: mutation.replacement,
                in: textView
            ) else {
                return false
            }
            textView.selectedRange = clamped(mutation.selection, in: textView.textStorage)
            textViewDidChange(textView)
            return true
        }

        func refreshStylingIfNeeded(on textView: UITextView) {
            guard !isApplyingStyle else { return }
            let current = MarkdownStyleSignature.current(
                revealedBlockRange: revealedBlockRange(in: textView),
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds,
                contentWidth: textView.markdownContentWidth,
                tableSourceAnchors: tableSourceAnchors
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
                contentWidth: textView.markdownContentWidth,
                tableSourceAnchors: tableSourceAnchors
            )
            storage.setAttributedString(styled)
            textView.typingAttributes = iOSMarkdownStyler.baseTypingAttributes
            styleSignature = MarkdownStyleSignature.current(
                revealedBlockRange: revealed,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds,
                contentWidth: textView.markdownContentWidth,
                tableSourceAnchors: tableSourceAnchors
            )
            // Every restyle rebuilds the grids, so an open cell field is now framed against rects
            // that no longer exist. Reposition rather than tear down: a keyboard appearing resizes
            // the view, and closing the field there would close it the instant it opened.
            repositionTableCellEditor(in: textView)
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
                in: textView.text ?? "",
                sourceRevealedRanges: sourceRevealedRanges(in: textView)
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

        /// Double-tapping a rendered code fence puts the caret in it.
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
            _ hit: (task: MarkdownTaskEmbedRenderInfo, target: iOSMarkdownTaskEmbedHitTarget),
            in textView: UITextView
        ) {
            guard !hit.task.isMissing else { return }
            let refreshed: MarkdownTaskEmbedRenderInfo?
            switch hit.target {
            case .checkbox:
                refreshed = parent.onToggleEmbeddedTask?(hit.task.id)
            case .subtaskCheckbox(let subtaskID):
                refreshed = parent.onToggleEmbeddedSubtask?(hit.task.id, subtaskID)
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // A resize owns its touch outright. Recognising alongside the text view's selection
            // press or its scroll pan would mean two gestures acting on one finger — the picture
            // resizing while a loupe follows the same drag.
            if gestureRecognizer.name == Self.imageResizeName || otherGestureRecognizer.name == Self.imageResizeName {
                return false
            }
            return true
        }

        static let renderedBlockTapName = "cadence.markdown.renderedBlockTap"
        static let tableCellTapName = "cadence.markdown.tableCellTap"
        static let imageResizeName = "cadence.markdown.imageResize"

        // MARK: - Image resize

        /// Live width of the picture when the current drag started.
        private var imageResizeStartWidth: CGFloat = 0

        @objc func handleImageResize(_ recognizer: UIPanGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView,
                  let hit = (recognizer as? iOSMarkdownImageResizeGestureRecognizer)?.hit
            else { return }

            switch recognizer.state {
            case .began:
                imageResizeStartWidth = hit.startWidth
            case .changed:
                let width = MarkdownImageAssetService.resolvedDisplayWidth(
                    startWidth: imageResizeStartWidth,
                    translation: recognizer.translation(in: textView).x
                )
                parent.onResizeImage?(hit.id, width)
                restyleForImageResize(textView)
            default:
                break
            }
        }

        /// Re-lays the note at the new width without the caret or the scroll position moving.
        ///
        /// The paragraph style reserves the card's height, so a resize changes the document's
        /// layout — `UITextView` would otherwise keep its content offset against a document that
        /// grew or shrank above it and the note would appear to slide under the finger.
        private func restyleForImageResize(_ textView: UITextView) {
            let offset = textView.contentOffset
            refreshStylingIfNeeded(on: textView)
            if textView.contentOffset != offset {
                textView.setContentOffset(offset, animated: false)
            }
        }

        /// The image whose resize handle is under `point`, and the width it is drawn at now.
        ///
        /// Measured against the rect the block canvas was actually painted into
        /// (`iOSMarkdownBlockCanvas.blockRect`, the same function the layout manager draws from),
        /// then converted to card-local coordinates and asked of `MarkdownImageBlockLayout` — the
        /// same value that produced the handle in the rendered canvas. Drawing and hit testing
        /// therefore cannot disagree about where the grip is.
        func imageResizeHit(at point: CGPoint, in textView: UITextView) -> iOSMarkdownImageResizeGestureRecognizer.Hit? {
            guard textView.bounds.contains(point), textView.textStorage.length > 0 else { return nil }

            let layoutManager = textView.layoutManager
            layoutManager.ensureLayout(for: textView.textContainer)

            var textPoint = point
            textPoint.x -= textView.textContainerInset.left
            textPoint.y -= textView.textContainerInset.top

            let contentWidth = textView.markdownContentWidth
            var result: iOSMarkdownImageResizeGestureRecognizer.Hit?
            let fullRange = NSRange(location: 0, length: textView.textStorage.length)
            textView.textStorage.enumerateAttribute(.cadenceMarkdownImage, in: fullRange, options: []) { value, range, stop in
                guard let info = value as? iOSMarkdownImageLayoutInfo,
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

                let layout = info.layout(maxWidth: contentWidth)
                let localPoint = CGPoint(x: textPoint.x - cardRect.minX, y: textPoint.y - cardRect.minY)
                guard layout.isResizeHandle(localPoint: localPoint) else { return }

                result = iOSMarkdownImageResizeGestureRecognizer.Hit(
                    id: info.id,
                    startWidth: layout.imageRect.width
                )
                stop.pointee = true
            }
            return result
        }

        /// Keeps the rendered-block double tap from beginning anywhere it has nothing to do.
        ///
        /// The same test `handleRenderedBlockEditTap` runs, moved one step earlier. Running it in
        /// the handler was too late: by then the recognizer had begun and taken the touch, so the
        /// text view never saw the double tap that was meant for it.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return true }
            if gestureRecognizer.name == Self.tableCellTapName {
                return markdownTableCellHit(at: gestureRecognizer.location(in: textView), in: textView) != nil
            }
            guard gestureRecognizer.name == Self.renderedBlockTapName else { return true }
            return revealableBlock(at: gestureRecognizer.location(in: textView), in: textView) != nil
        }

        /// The one definition of "a double tap here reveals source": a rendered **code fence**.
        /// Read by the gate above and by the handler, so the two cannot disagree about which taps
        /// this recognizer owns.
        ///
        /// A table is deliberately not here any more (T-221). A double tap on a grid used to put the
        /// caret in it and un-render it; a single tap now opens the cell under the finger, and the
        /// source is a menu command.
        private func revealableBlock(
            at point: CGPoint,
            in textView: UITextView
        ) -> MarkdownRenderedBlock? {
            guard let hit = characterHit(at: point, in: textView, hitPadding: 18),
                  let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
                    atUTF16Location: hit.characterIndex,
                    in: textView.text ?? ""
                  ),
                  block.kind == .code else {
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
        ) -> (task: MarkdownTaskEmbedRenderInfo, target: iOSMarkdownTaskEmbedHitTarget)? {
            guard textView.bounds.contains(point), textView.textStorage.length > 0 else { return nil }

            let textContainer = textView.textContainer
            let layoutManager = textView.layoutManager
            var textPoint = point
            textPoint.x -= textView.textContainerInset.left
            textPoint.y -= textView.textContainerInset.top
            layoutManager.ensureLayout(for: textContainer)

            var result: (task: MarkdownTaskEmbedRenderInfo, target: iOSMarkdownTaskEmbedHitTarget)?
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

                let localPoint = CGPoint(x: textPoint.x - cardRect.minX, y: textPoint.y - cardRect.minY)
                let target = iOSMarkdownTaskEmbedLayoutInfo(task: embed.task).hitTarget(
                    at: localPoint,
                    maxWidth: textView.markdownContentWidth
                )
                result = (embed.task, target)
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
