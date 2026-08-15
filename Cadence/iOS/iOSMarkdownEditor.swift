#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownEditor: UIViewRepresentable {
    @Environment(\.openURL) private var openURL
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var pendingCommand: MarkdownFormatCommand?
    @Binding var selectedRange: NSRange
    var hidesMarkdownMarkers: Bool
    var imageAssets: [MarkdownImageAsset]
    var taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    var onToggleChecklistLine: ((Int) -> Void)?
    var onToggleEmbeddedTask: ((UUID) -> MarkdownTaskEmbedRenderInfo?)?
    var onToggleEmbeddedSubtask: ((UUID, UUID) -> MarkdownTaskEmbedRenderInfo?)?
    var onCreateEmbeddedTask: ((String) -> String?)?
    var onOpenEmbeddedTask: ((UUID) -> Void)?
    var onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?
    var onEditRenderedBlock: ((NSRange) -> Void)?
    var onCreatePastedImages: (([UIImage]) -> [MarkdownImageAsset])?

    init(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        pendingCommand: Binding<MarkdownFormatCommand?> = .constant(nil),
        selectedRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0)),
        hidesMarkdownMarkers: Bool = true,
        imageAssets: [MarkdownImageAsset] = [],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:],
        onToggleChecklistLine: ((Int) -> Void)? = nil,
        onToggleEmbeddedTask: ((UUID) -> MarkdownTaskEmbedRenderInfo?)? = nil,
        onToggleEmbeddedSubtask: ((UUID, UUID) -> MarkdownTaskEmbedRenderInfo?)? = nil,
        onCreateEmbeddedTask: ((String) -> String?)? = nil,
        onOpenEmbeddedTask: ((UUID) -> Void)? = nil,
        onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)? = nil,
        onEditRenderedBlock: ((NSRange) -> Void)? = nil,
        onCreatePastedImages: (([UIImage]) -> [MarkdownImageAsset])? = nil
    ) {
        _text = text
        _isFocused = isFocused
        _pendingCommand = pendingCommand
        _selectedRange = selectedRange
        self.hidesMarkdownMarkers = hidesMarkdownMarkers
        self.imageAssets = imageAssets
        self.taskEmbeds = taskEmbeds
        self.onToggleChecklistLine = onToggleChecklistLine
        self.onToggleEmbeddedTask = onToggleEmbeddedTask
        self.onToggleEmbeddedSubtask = onToggleEmbeddedSubtask
        self.onCreateEmbeddedTask = onCreateEmbeddedTask
        self.onOpenEmbeddedTask = onOpenEmbeddedTask
        self.onOpenReference = onOpenReference
        self.onEditRenderedBlock = onEditRenderedBlock
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
        renderedBlockTap.cancelsTouchesInView = true
        renderedBlockTap.delaysTouchesBegan = false
        renderedBlockTap.delegate = context.coordinator
        referenceTap.require(toFail: renderedBlockTap)
        textView.addGestureRecognizer(renderedBlockTap)
        textView.addGestureRecognizer(referenceTap)
        textView.backgroundColor = .clear
        // Resigning is enough on its own: `textViewDidEndEditing` publishes the current text and
        // clears `isFocused`, which is exactly what the old (never-rendered) toolbar buttons did.
        textView.inputAccessoryView = iOSMarkdownKeyboardAccessoryView { [weak textView] in
            textView?.resignFirstResponder()
        }
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

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        private static let markdownStyleRefreshDelay: TimeInterval = 0.08

        var parent: iOSMarkdownEditor
        private var isApplyingStyle = false
        private var styleSignature = iOSMarkdownStyleSignature.current(hidesMarkdownMarkers: true, imageAssets: [], taskEmbeds: [:])
        private var pendingStyleWorkItem: DispatchWorkItem?

        init(parent: iOSMarkdownEditor) {
            self.parent = parent
            styleSignature = iOSMarkdownStyleSignature.current(
                hidesMarkdownMarkers: parent.hidesMarkdownMarkers,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds
            )
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            publishCurrentText(from: textView)
            parent.isFocused = false
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
               parent.hidesMarkdownMarkers,
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
            guard selection.location >= lineRange.location + (line as NSString).length,
                  let title = MarkdownTaskEmbedParser.draftTitle(in: line),
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
            let current = iOSMarkdownStyleSignature.current(
                hidesMarkdownMarkers: parent.hidesMarkdownMarkers,
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
            if createUntitledEmbeddedTaskIfNeeded(in: textView, text: text) {
                return true
            }

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

        private func createUntitledEmbeddedTaskIfNeeded(in textView: UITextView, text: String) -> Bool {
            guard let onCreateEmbeddedTask = parent.onCreateEmbeddedTask else { return false }
            let nsText = text as NSString
            let cursor = textView.selectedRange.location
            let candidates = [
                (snippet: "( ) ", length: 4),
                (snippet: "() ", length: 3)
            ]

            for candidate in candidates where cursor >= candidate.length {
                let range = NSRange(location: cursor - candidate.length, length: candidate.length)
                guard nsText.substring(with: range) == candidate.snippet,
                      MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
                      let taskReference = onCreateEmbeddedTask(MarkdownTaskEmbedRenderInfo.untitledTaskTitle),
                      MarkdownTaskEmbedParser.standaloneTaskReference(in: taskReference) != nil,
                      let textRange = textView.textRange(from: range) else {
                    continue
                }

                textView.replace(textRange, withText: taskReference)
                if let titleRange = MarkdownTaskEmbedParser.referenceTitleRange(
                    in: taskReference,
                    lineStart: range.location
                ) {
                    textView.selectedRange = clamped(titleRange, in: textView.textStorage)
                } else {
                    textView.selectedRange = clamped(
                        NSRange(location: range.location + (taskReference as NSString).length, length: 0),
                        in: textView.textStorage
                    )
                }
                textViewDidChange(textView)
                return true
            }

            return false
        }

        func applyMarkdownStyle(to textView: UITextView, text: String) {
            isApplyingStyle = true
            defer { isApplyingStyle = false }

            let storage = textView.textStorage
            let styled = iOSMarkdownStyler.attributedString(
                for: text,
                hidesMarkdownMarkers: parent.hidesMarkdownMarkers,
                imageAssets: parent.imageAssets,
                taskEmbeds: parent.taskEmbeds,
                contentWidth: textView.markdownContentWidth
            )
            storage.setAttributedString(styled)
            textView.typingAttributes = iOSMarkdownStyler.baseTypingAttributes
            styleSignature = iOSMarkdownStyleSignature.current(
                hidesMarkdownMarkers: parent.hidesMarkdownMarkers,
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
            if parent.hidesMarkdownMarkers, selection.length == 0 {
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
                  parent.hidesMarkdownMarkers,
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

        @objc func handleRenderedBlockEditTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  parent.hidesMarkdownMarkers,
                  let textView = recognizer.view as? UITextView,
                  let hit = characterHit(at: recognizer.location(in: textView), in: textView, hitPadding: 18),
                  let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(
                    atUTF16Location: hit.characterIndex,
                    in: textView.text ?? ""
                  ) else {
                return
            }

            publishCurrentText(from: textView)
            let selection = clamped(block.storageRange, in: textView.textStorage)
            textView.selectedRange = selection
            parent.selectedRange = selection
            parent.onEditRenderedBlock?(selection)
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
            true
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
                      range.location < textView.textStorage.length else { return }

                let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
                guard glyphIndex < layoutManager.numberOfGlyphs else { return }
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1),
                    in: textContainer
                )
                guard glyphRect.insetBy(dx: -8, dy: -8).contains(textPoint) else { return }

                let localPoint = CGPoint(x: textPoint.x - glyphRect.minX, y: textPoint.y - glyphRect.minY)
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
