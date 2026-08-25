#if os(iOS)
import SwiftUI
import UIKit

/// **The hosted cell field: the one place in the iOS markdown editor where a rendered block is
/// edited as itself rather than as its source.**
///
/// The design is the Mac's, ported whole, because it is the design that makes the hard part
/// disappear: **the table's markdown never leaves the text storage.** The styler collapses its
/// glyphs and reserves the grid's height; this field writes cell values back through
/// `UITextView.replace(_:withText:)`, the view's own editing path. Because the characters are still
/// in their real range:
///
/// - **Selection** — a drag from the prose above to the prose below still covers the pipes, and a
///   caret arrowed at the table steps over it (`MarkdownHiddenRangeSupport.snappedCaretLocation`)
///   rather than vanishing inside.
/// - **Copy/paste** — the storage's string *is* the note, so copying a range spanning the table
///   yields markdown, and pasting it anywhere renders a table again.
/// - **Undo** — a commit is an ordinary text-view edit, registered on the text view's own undo
///   manager, which is why `applyMarkdownTableEdit` is the single write path and why nothing here
///   assigns `textView.text` or reaches into `textStorage`. A commit whose value did not change
///   registers **no** edit at all (`MarkdownTableEditor.commit` returns nil), so tabbing across five
///   cells does not cost five undos.
///
/// - **The render gate — the one concern that has no macOS counterpart.** `MarkdownStyleSignature`
///   has exactly one reader in the repo and it is this editor; the Mac re-runs its styler from
///   `textDidChange` and never needed one. The signature carries **no digest of the note's text**,
///   so a committed cell leaves it untouched and `refreshStylingIfNeeded` would compare equal and
///   skip — the grid would keep showing the old value with the new one already in the storage.
///   Two things follow, and both are deliberate: every table mutation restyles *synchronously*
///   through `applyMarkdownStyle` rather than asking the gate, and **Show Table Source**, which has
///   no text edit behind it at all, is in the signature as `tableSourceAnchors`.
///
/// Everything about *markdown* is `MarkdownTableEditor`'s; everything about *rects* is
/// `MarkdownTableLayout`'s. What is left here is UIKit lifecycle.
extension iOSMarkdownEditor.Coordinator {
    // MARK: - Hit testing

    /// The rendered table under a point, and which cell of it.
    ///
    /// Measured against the rect the grid was actually drawn in — `iOSMarkdownTableRenderInfo`'s
    /// own `gridRect`, the same value `iOSMarkdownBlockCanvasLayoutManager` paints from, over the
    /// same `MarkdownTableLayout` — so the cell you touch is the cell you see.
    func markdownTableCellHit(
        at point: CGPoint,
        in textView: UITextView
    ) -> (anchor: Int, address: MarkdownTableCellAddress)? {
        var result: (anchor: Int, address: MarkdownTableCellAddress)?
        enumerateMarkdownTables(in: textView) { info, fragment, stop in
            guard let address = info.address(
                atTextPoint: self.textPoint(from: point, in: textView),
                inLineFragment: fragment
            ) else { return }
            result = (info.anchor, address)
            stop()
        }
        return result
    }

    func markdownTableRenderInfo(anchor: Int, in textView: UITextView) -> (info: iOSMarkdownTableRenderInfo, fragment: CGRect)? {
        var result: (iOSMarkdownTableRenderInfo, CGRect)?
        enumerateMarkdownTables(in: textView) { info, fragment, stop in
            guard info.anchor == anchor else { return }
            result = (info, fragment)
            stop()
        }
        return result
    }

    private func enumerateMarkdownTables(
        in textView: UITextView,
        _ body: (iOSMarkdownTableRenderInfo, CGRect, () -> Void) -> Void
    ) {
        let storage = textView.textStorage
        guard storage.length > 0 else { return }
        let layoutManager = textView.layoutManager
        layoutManager.ensureLayout(for: textView.textContainer)

        storage.enumerateAttribute(
            .cadenceMarkdownTable,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, stop in
            guard let info = value as? iOSMarkdownTableRenderInfo, range.location < storage.length else { return }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            body(info, fragment) { stop.pointee = true }
        }
    }

    private func textPoint(from point: CGPoint, in textView: UITextView) -> CGPoint {
        CGPoint(
            x: point.x - textView.textContainerInset.left,
            y: point.y - textView.textContainerInset.top
        )
    }

    private func viewRect(from textRect: CGRect, in textView: UITextView) -> CGRect {
        textRect.offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
    }

    // MARK: - Tap

    @objc func handleTableCellTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let textView = recognizer.view as? UITextView,
              let hit = markdownTableCellHit(at: recognizer.location(in: textView), in: textView) else {
            return
        }
        beginTableCellEdit(anchor: hit.anchor, address: hit.address, in: textView)
    }

    // MARK: - Cell editing

    func beginTableCellEdit(anchor: Int, address: MarkdownTableCellAddress, in textView: UITextView) {
        endTableCellEdit(commit: true, in: textView)
        guard let (info, fragment) = markdownTableRenderInfo(anchor: anchor, in: textView),
              info.grid.isValid(address),
              let cellRect = info.cellRect(address, inLineFragment: fragment) else { return }

        let field = iOSMarkdownTableCellField(frame: viewRect(from: cellRect, in: textView).insetBy(dx: 2, dy: 3))
        field.text = info.grid.cell(at: address) ?? ""
        field.font = iOSMarkdownTableGridMetrics.font(isHeader: address.row == 0)
        field.textColor = UIColor(Theme.text)
        // Opaque, so the cell drawn underneath it does not read through the value being typed. The
        // Mac passes an `editingAddress` into its draw pass instead; here the grid is painted from a
        // value the styler built and cannot know about a field that opened after it.
        field.backgroundColor = UIColor(Theme.surfaceElevated)
        field.borderStyle = .none
        field.layer.cornerRadius = 6
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor(Theme.blue).cgColor
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.clearButtonMode = .never
        field.delegate = self
        field.textAlignment = iOSMarkdownTableGridMetrics.textAlignment(
            info.grid.alignments[min(address.column, info.grid.alignments.count - 1)]
        )
        field.onMoveFocus = { [weak self, weak textView] movingForward in
            guard let self, let textView else { return }
            self.moveTableCellFocus(movingForward: movingForward, in: textView)
        }
        field.onCancel = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.endTableCellEdit(commit: false, in: textView)
        }

        textView.addSubview(field)
        tableCellEditor = field
        tableCellEditAddress = address
        tableCellEditAnchor = anchor
        field.becomeFirstResponder()
        field.selectAll(nil)
    }

    @discardableResult
    func endTableCellEdit(commit: Bool, in textView: UITextView) -> Bool {
        guard !isEndingTableCellEdit,
              let field = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return false }
        isEndingTableCellEdit = true
        let text = field.text ?? ""
        field.delegate = nil
        field.removeFromSuperview()
        tableCellEditor = nil
        tableCellEditAddress = nil
        tableCellEditAnchor = nil
        isEndingTableCellEdit = false
        guard commit else { return false }
        return applyTableCellText(text, at: address, anchor: anchor, in: textView)
    }

    /// Writes one cell back into the note, and does nothing at all when the value did not change.
    ///
    /// The trim and the no-op rule are `MarkdownTableEditor.commit`'s — the same function the Mac's
    /// hosted field calls, so "did this cell actually change" is one decision with tests rather than
    /// two hand-written copies. What is checked here is the part that is about *this* text view: the
    /// anchor must still name the table it named when the field opened.
    @discardableResult
    func applyTableCellText(
        _ text: String,
        at address: MarkdownTableCellAddress,
        anchor: Int,
        in textView: UITextView
    ) -> Bool {
        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: textView.text ?? ""),
              grid.storageRange.location == anchor,
              let edit = MarkdownTableEditor.commit(text, at: address, in: grid) else { return false }
        return applyMarkdownTableEdit(edit, in: textView)
    }

    /// **The one write path for every table mutation, cell / row / column alike.**
    ///
    /// `UITextView.replace(_:withText:)` and not `textView.text = …` or a reach into `textStorage`:
    /// only the `UITextInput` route registers the change on the view's own undo manager, which is
    /// what keeps a committed cell an ordinary `Cmd+Z` away and keeps the editor's existing
    /// pass-through undo working with nothing added.
    ///
    /// The restyle at the end is **not** `refreshStylingIfNeeded`. That gate compares a
    /// `MarkdownStyleSignature`, and the signature carries no digest of the note's text — so after a
    /// cell commit it compares equal, skips, and the grid silently keeps drawing the old value.
    @discardableResult
    func applyMarkdownTableEdit(_ edit: MarkdownTableEdit, in textView: UITextView) -> Bool {
        let storage = textView.textStorage
        guard edit.replacementRange.location >= 0,
              NSMaxRange(edit.replacementRange) <= storage.length,
              let range = textView.textRange(from: edit.replacementRange) else { return false }

        isApplyingTableEdit = true
        textView.replace(range, withText: edit.replacement)
        isApplyingTableEdit = false

        let updated = textView.text ?? ""
        if parent.text != updated {
            parent.text = updated
        }
        applyMarkdownStyle(to: textView, text: updated)
        let caret = edit.replacementRange.location + (edit.replacement as NSString).length
        textView.selectedRange = clamped(NSRange(location: caret, length: 0), in: textView.textStorage)
        publishSelectedRange(from: textView)
        return true
    }

    /// Keeps an open field over the cell it belongs to after a restyle rebuilt the grids.
    ///
    /// Called from `applyMarkdownStyle`, which every table mutation goes through. When the cell has
    /// stopped existing — a column deleted out from under it, the table gone — the field commits and
    /// closes rather than floating over nothing.
    func repositionTableCellEditor(in textView: UITextView) {
        guard let field = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return }
        guard let (info, fragment) = markdownTableRenderInfo(anchor: anchor, in: textView),
              info.grid.isValid(address),
              let cellRect = info.cellRect(address, inLineFragment: fragment) else {
            endTableCellEdit(commit: true, in: textView)
            return
        }
        field.frame = viewRect(from: cellRect, in: textView).insetBy(dx: 2, dy: 3)
    }

    // MARK: - Keys

    /// Tab and Shift-Tab. Which cell each reaches is
    /// `MarkdownTableEditor.focus(after:movingForward:in:)` — a tested pure function over the grid —
    /// so the spreadsheet rule (left to right, wrapping to the next row, a new row off the end) is
    /// stated once and not re-derived here.
    func moveTableCellFocus(movingForward: Bool, in textView: UITextView) {
        guard let field = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return }
        let text = field.text ?? ""
        endTableCellEdit(commit: false, in: textView)
        applyTableCellText(text, at: address, anchor: anchor, in: textView)

        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: textView.text ?? "") else {
            return
        }
        switch MarkdownTableEditor.focus(after: address, movingForward: movingForward, in: grid) {
        case .cell(let next):
            beginTableCellEdit(anchor: anchor, address: next, in: textView)
        case .appendRow:
            guard let edit = MarkdownTableEditor.insertingRow(below: grid.rowCount - 1, in: grid),
                  applyMarkdownTableEdit(edit, in: textView),
                  let focus = edit.focus else { return }
            beginTableCellEdit(anchor: anchor, address: focus, in: textView)
        case .leaveTable:
            break
        }
    }

    /// Return adds a row below the cell being edited and moves into it.
    func insertTableRowBelowEditingCell(in textView: UITextView) {
        guard let field = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return }
        let text = field.text ?? ""
        endTableCellEdit(commit: false, in: textView)
        applyTableCellText(text, at: address, anchor: anchor, in: textView)

        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: textView.text ?? ""),
              let edit = MarkdownTableEditor.insertingRow(below: address.row, in: grid),
              applyMarkdownTableEdit(edit, in: textView),
              let focus = edit.focus else { return }
        beginTableCellEdit(anchor: anchor, address: focus, in: textView)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let textView = textField.superview as? UITextView else { return true }
        insertTableRowBelowEditingCell(in: textView)
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === tableCellEditor,
              let textView = textField.superview as? UITextView else { return }
        endTableCellEdit(commit: true, in: textView)
    }

    // MARK: - Menu

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let textView = interaction.view as? UITextView else { return nil }

        if let hit = markdownTableCellHit(at: location, in: textView) {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self, weak textView] _ in
                guard let self, let textView else { return nil }
                return self.markdownTableMenu(anchor: hit.anchor, address: hit.address, in: textView)
            }
        }

        guard let anchor = revealedTableAnchor(at: location, in: textView) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self, weak textView] _ in
            guard let self, let textView else { return nil }
            return UIMenu(children: [self.tableSourceAction(anchor: anchor, in: textView)])
        }
    }

    /// The revealed table under a point, found by character rather than by grid — a revealed table
    /// has no grid to hit, which is the whole point of the mode.
    private func revealedTableAnchor(at point: CGPoint, in textView: UITextView) -> Int? {
        guard !tableSourceAnchors.isEmpty, textView.textStorage.length > 0 else { return nil }
        let layoutManager = textView.layoutManager
        let glyphIndex = layoutManager.glyphIndex(for: textPoint(from: point, in: textView), in: textView.textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return MarkdownTableEditor.grids(in: textView.text ?? "")
            .first { tableSourceAnchors.contains($0.storageRange.location) && $0.contains(utf16Location: character) }?
            .storageRange.location
    }

    private func markdownTableMenu(
        anchor: Int,
        address: MarkdownTableCellAddress,
        in textView: UITextView
    ) -> UIMenu {
        let grid = markdownTableRenderInfo(anchor: anchor, in: textView)?.info.grid

        func action(
            _ title: String,
            _ image: String,
            enabled: Bool = true,
            _ build: @escaping (MarkdownTableGrid, MarkdownTableCellAddress) -> MarkdownTableEdit?
        ) -> UIAction {
            let item = UIAction(title: title, image: UIImage(systemName: image)) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.applyTableMenuEdit(anchor: anchor, address: address, in: textView, build)
            }
            // Stated, not left to UIKit: without it "Delete Row" stays live on the header row and
            // "Delete Column" on a single-column table — the two edits the editor refuses to make,
            // which would then read as a menu item that does nothing.
            item.attributes = enabled ? [] : [.disabled]
            return item
        }

        let rows = UIMenu(title: "", options: .displayInline, children: [
            action("Insert Row Above", "arrow.up.to.line", enabled: address.row > 0) {
                MarkdownTableEditor.insertingRow(below: $1.row - 1, in: $0)
            },
            action("Insert Row Below", "arrow.down.to.line") {
                MarkdownTableEditor.insertingRow(below: $1.row, in: $0)
            },
            action("Delete Row", "trash", enabled: address.row > 0) {
                MarkdownTableEditor.deletingRow($1.row, in: $0)
            }
        ])
        let columns = UIMenu(title: "", options: .displayInline, children: [
            action("Insert Column Before", "arrow.left.to.line") {
                MarkdownTableEditor.insertingColumn(at: $1.column, in: $0)
            },
            action("Insert Column After", "arrow.right.to.line") {
                MarkdownTableEditor.insertingColumn(at: $1.column + 1, in: $0)
            },
            action("Delete Column", "trash", enabled: (grid?.columnCount ?? 1) > 1) {
                MarkdownTableEditor.deletingColumn($1.column, in: $0)
            }
        ])
        let source = UIMenu(title: "", options: .displayInline, children: [
            tableSourceAction(anchor: anchor, in: textView)
        ])
        return UIMenu(children: [rows, columns, source])
    }

    /// The raw-markdown escape, and it is a **command** rather than a caret position.
    ///
    /// The behaviour it replaces is the one T-221 exists to remove: a table that un-rendered the
    /// moment the caret landed in it un-rendered itself while you were editing it. Here the source
    /// appears only when asked for, stays until asked to go away, and while it is showing the table
    /// falls back to the banded per-row styling `styleLine` has always drawn.
    private func tableSourceAction(anchor: Int, in textView: UITextView) -> UIAction {
        let isRevealed = tableSourceAnchors.contains(anchor)
        return UIAction(
            title: isRevealed ? "Hide Table Source" : "Show Table Source",
            image: UIImage(systemName: isRevealed ? "tablecells" : "chevron.left.forwardslash.chevron.right")
        ) { [weak self, weak textView] _ in
            guard let self, let textView else { return }
            self.endTableCellEdit(commit: true, in: textView)
            if isRevealed {
                self.tableSourceAnchors.remove(anchor)
            } else {
                self.tableSourceAnchors.insert(anchor)
            }
            // Through the gate on purpose. Revealing a table changes what the styler draws with no
            // text edit behind it, exactly like moving the caret into a code fence — which is why
            // `tableSourceAnchors` is part of `MarkdownStyleSignature`. Without that entry this call
            // compares equal and does nothing at all.
            self.refreshStylingIfNeeded(on: textView)
        }
    }

    private func applyTableMenuEdit(
        anchor: Int,
        address: MarkdownTableCellAddress,
        in textView: UITextView,
        _ build: (MarkdownTableGrid, MarkdownTableCellAddress) -> MarkdownTableEdit?
    ) {
        endTableCellEdit(commit: true, in: textView)
        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: textView.text ?? ""),
              grid.storageRange.location == anchor,
              let edit = build(grid, address) else { return }
        applyMarkdownTableEdit(edit, in: textView)
    }
}

/// The hosted field itself. It exists as a subclass for one reason: `Tab` and `Shift-Tab`.
///
/// A software keyboard has no Tab key, so on a phone the way to the next cell is to touch it — which
/// is the primary gesture anyway, and the same one the Mac offers with a click. These commands are
/// what a hardware keyboard gets, on an iPad or a Mac running the iPad build, and they are the keys
/// the ticket decided on.
final class iOSMarkdownTableCellField: UITextField {
    var onMoveFocus: ((Bool) -> Void)?
    var onCancel: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(moveToNextCell)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(moveToPreviousCell)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelCellEdit))
        ]
    }

    @objc private func moveToNextCell() { onMoveFocus?(true) }
    @objc private func moveToPreviousCell() { onMoveFocus?(false) }
    @objc private func cancelCellEdit() { onCancel?() }
}
#endif
