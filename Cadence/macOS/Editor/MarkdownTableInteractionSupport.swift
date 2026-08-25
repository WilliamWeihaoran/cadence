#if os(macOS)
import AppKit

/// **The hosted cell editor: the one place in the markdown editor where a rendered block is edited
/// as itself rather than as its source.**
///
/// The mechanism is the `NSTextField` subview `beginInlineTaskTitleEdit` already uses over a task
/// embed's title — an ordinary AppKit control added to the text view, made first responder, torn
/// down on commit. What is new is where the value goes. The task-title editor writes a *model*; a
/// table cell has no model, so this writes the note's own markdown back through
/// `shouldChangeText(in:replacementString:)` / `replaceCharacters` / `didChangeText`.
///
/// That one choice is what keeps the four things a hosted view usually breaks working:
///
/// - **Undo.** The commit is an ordinary `NSTextView` edit, registered on the text view's own undo
///   stack, so `Cmd+Z` reaches it through the existing "text view is first responder → pass the
///   event through" route with nothing added. While the field itself has focus, `Cmd+Z` undoes
///   typing *in the cell*, which is the granularity a cell editor should have.
/// - **Copy/paste.** The table's characters are never removed from the text storage — only their
///   glyphs are collapsed — so a selection spanning the table still copies the pipes, and pasting
///   markdown containing a table still produces one.
/// - **Selection.** Same reason: the source occupies its real character range, and a drag that
///   starts outside the table runs through it. A drag that *starts* on the grid opens a cell
///   instead, which is what clicking a task embed or an image already does.
/// - **Invalidation.** `didChangeText()` posts the notification the coordinator restyles from, so a
///   committed cell re-renders through the ordinary path. There is no second render gate on macOS
///   to keep in step — `MarkdownStyleSignature` is iOS-only and has no reader here.
///
/// Everything this file decides about *markdown* is in `MarkdownTableEditSupport`; everything it
/// decides about *rects* is in `MarkdownTableLayoutSupport`. What is left here is AppKit lifecycle.
extension CadenceTextView {
    // MARK: - Hit testing

    func markdownTableCellHit(at point: NSPoint) -> (anchor: Int, address: MarkdownTableCellAddress)? {
        for hit in markdownTableHits {
            if let address = hit.layout.address(at: point, in: hit.gridRect) {
                return (hit.anchor, address)
            }
        }
        return nil
    }

    func markdownTableHit(anchor: Int) -> MarkdownTableHitInfo? {
        markdownTableHits.first { $0.anchor == anchor }
    }

    /// The cell the hosted field currently covers, so the draw pass does not paint the old value
    /// underneath a control showing the new one.
    func editingMarkdownTableAddress(anchor: Int) -> MarkdownTableCellAddress? {
        guard tableCellEditAnchor == anchor else { return nil }
        return tableCellEditAddress
    }

    // MARK: - Cell editing

    func beginTableCellEdit(anchor: Int, address: MarkdownTableCellAddress, retryIfNeeded: Bool = true) {
        endTableCellEdit(commit: true)
        guard let hit = markdownTableHit(anchor: anchor),
              hit.grid.isValid(address),
              let cellRect = hit.layout.cellRect(row: address.row, column: address.column, in: hit.gridRect) else {
            // The hit cache is written by the draw pass, so the frame after a commit has none yet.
            // One hop, exactly as `beginInlineTaskTitleEdit` does it.
            guard retryIfNeeded else { return }
            DispatchQueue.main.async { [weak self] in
                self?.beginTableCellEdit(anchor: anchor, address: address, retryIfNeeded: false)
            }
            return
        }

        let editor = NSTextField(frame: cellRect.insetBy(dx: 2, dy: 3))
        editor.stringValue = hit.grid.cell(at: address) ?? ""
        editor.font = address.row == 0 ? MarkdownStylist.tableHeaderCellFont : MarkdownStylist.tableCellFont
        editor.textColor = MarkdownStylist.textColor
        editor.backgroundColor = Theme.nsSurfaceElevated
        editor.drawsBackground = true
        editor.isBordered = false
        editor.focusRingType = .default
        editor.lineBreakMode = .byTruncatingTail
        editor.delegate = self
        editor.target = self
        editor.action = #selector(commitTableCellEditor)
        editor.cell?.sendsActionOnEndEditing = false
        editor.alignment = {
            switch hit.grid.alignments[min(address.column, hit.grid.alignments.count - 1)] {
            case .leading: return .left
            case .center: return .center
            case .trailing: return .right
            }
        }()
        addSubview(editor)
        tableCellEditor = editor
        tableCellEditAddress = address
        tableCellEditAnchor = anchor
        window?.makeFirstResponder(editor)
        editor.selectText(nil)
        needsDisplay = true
    }

    @objc func commitTableCellEditor() {
        endTableCellEdit(commit: true)
    }

    func endTableCellEdit(commit: Bool) {
        guard !isEndingTableCellEdit,
              let editor = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return }
        isEndingTableCellEdit = true
        let text = editor.stringValue
        editor.delegate = nil
        editor.removeFromSuperview()
        tableCellEditor = nil
        tableCellEditAddress = nil
        tableCellEditAnchor = nil
        isEndingTableCellEdit = false
        if commit {
            applyTableCellText(text, at: address, anchor: anchor)
        }
        needsDisplay = true
    }

    /// Writes one cell back into the note, and does nothing at all when the value did not change.
    ///
    /// The no-op guard is load-bearing rather than an optimisation: Tab through five cells without
    /// typing and every one of them would otherwise register an undoable edit, so `Cmd+Z` five
    /// times would walk back through edits the user never made.
    @discardableResult
    func applyTableCellText(_ text: String, at address: MarkdownTableCellAddress, anchor: Int) -> Bool {
        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: string),
              grid.storageRange.location == anchor,
              grid.isValid(address) else { return false }
        let normalized = text.trimmingCharacters(in: .whitespaces)
        guard grid.cell(at: address) != normalized else { return false }
        guard let edit = MarkdownTableEditor.settingCell(address, to: normalized, in: grid) else { return false }
        return applyMarkdownTableEdit(edit)
    }

    /// The one write path for every table mutation, cell / row / column alike.
    ///
    /// Goes through the AppKit text-mutation contract rather than assigning `string`, for the reason
    /// `MarkdownEditorCoordinator.apply(_:to:)` records: an edit that bypasses it is not on the undo
    /// stack, and one that rewrites text an already-registered undo record describes by offset
    /// replays against text that has shifted underneath it.
    @discardableResult
    func applyMarkdownTableEdit(_ edit: MarkdownTableEdit) -> Bool {
        guard let textStorage,
              NSMaxRange(edit.replacementRange) <= textStorage.length,
              shouldChangeText(in: edit.replacementRange, replacementString: edit.replacement) else { return false }
        textStorage.replaceCharacters(in: edit.replacementRange, with: edit.replacement)
        let end = edit.replacementRange.location + (edit.replacement as NSString).length
        setSelectedRange(NSRange(location: min(end, textStorage.length), length: 0))
        didChangeText()
        return true
    }

    // MARK: - Keys

    /// Tab / Shift-Tab / Return / Escape inside a hosted cell.
    ///
    /// Which cell each of those reaches is `MarkdownTableEditor.focus(after:movingForward:in:)` —
    /// a tested pure function over the grid — so the spreadsheet rule (left to right, wrapping to
    /// the next row) is stated once and not re-derived here.
    func handleTableCellCommand(_ commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            moveTableCellFocus(movingForward: true)
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            moveTableCellFocus(movingForward: false)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            insertTableRowBelowEditingCell()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endTableCellEdit(commit: false)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func moveTableCellFocus(movingForward: Bool) {
        guard let editor = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return }
        let text = editor.stringValue
        endTableCellEdit(commit: false)
        applyTableCellText(text, at: address, anchor: anchor)

        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: string) else {
            window?.makeFirstResponder(self)
            return
        }
        switch MarkdownTableEditor.focus(after: address, movingForward: movingForward, in: grid) {
        case .cell(let next):
            reopenTableCellEdit(anchor: anchor, address: next)
        case .appendRow:
            guard let edit = MarkdownTableEditor.insertingRow(below: grid.rowCount - 1, in: grid),
                  applyMarkdownTableEdit(edit),
                  let focus = edit.focus else {
                window?.makeFirstResponder(self)
                return
            }
            reopenTableCellEdit(anchor: anchor, address: focus)
        case .leaveTable:
            window?.makeFirstResponder(self)
        }
    }

    private func insertTableRowBelowEditingCell() {
        guard let editor = tableCellEditor,
              let address = tableCellEditAddress,
              let anchor = tableCellEditAnchor else { return }
        let text = editor.stringValue
        endTableCellEdit(commit: false)
        applyTableCellText(text, at: address, anchor: anchor)

        guard let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: string),
              let edit = MarkdownTableEditor.insertingRow(below: address.row, in: grid),
              applyMarkdownTableEdit(edit),
              let focus = edit.focus else {
            window?.makeFirstResponder(self)
            return
        }
        reopenTableCellEdit(anchor: anchor, address: focus)
    }

    /// Redraws before reopening, because `markdownTableHits` is written by the draw pass and the
    /// edit that just landed invalidated it. Without this the reopen always takes the async retry
    /// path, and Tab visibly lags a frame behind the key.
    private func reopenTableCellEdit(anchor: Int, address: MarkdownTableCellAddress) {
        if let scrollView = enclosingScrollView {
            MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        }
        display()
        beginTableCellEdit(anchor: anchor, address: address)
    }
}

// MARK: - Context menu

extension CadenceTextView {
    /// Rows and columns are added and removed from the table's own context menu.
    ///
    /// Chosen over hover chrome (a `+` rail down the edges) deliberately: hover chrome is a second
    /// hit-testing surface over a canvas that already has one, it competes with the text view's own
    /// cursor rects, and it has to be discovered. A right-click on the thing you want to change is
    /// where every other table on the platform puts these, and it costs no pixels.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = markdownTableCellHit(at: point) {
            return markdownTableMenu(anchor: hit.anchor, address: hit.address)
        }
        if let anchor = revealedTableAnchor,
           let grid = MarkdownTableEditor.grid(containingUTF16Location: anchor, in: string),
           grid.storageRange.location == anchor,
           NSLocationInRange(characterIndexForInsertion(at: point), grid.storageRange) {
            let menu = super.menu(for: event) ?? NSMenu()
            let item = NSMenuItem(
                title: "Hide Table Source",
                action: #selector(toggleMarkdownTableSource(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = MarkdownTableMenuContext(anchor: anchor, address: MarkdownTableCellAddress(row: 0, column: 0))
            menu.insertItem(NSMenuItem.separator(), at: 0)
            menu.insertItem(item, at: 0)
            return menu
        }
        return super.menu(for: event)
    }

    private func markdownTableMenu(anchor: Int, address: MarkdownTableCellAddress) -> NSMenu {
        let context = MarkdownTableMenuContext(anchor: anchor, address: address)
        let grid = markdownTableHit(anchor: anchor)?.grid
        let menu = NSMenu()
        // Explicit enablement, not AppKit's. With `autoenablesItems` on, the text view's own
        // `validateMenuItem(_:)` decides, and it says yes to any selector the target responds to —
        // which would re-enable "Delete Row" on the header row and "Delete Column" on a
        // single-column table, the two things the editor refuses to do.
        menu.autoenablesItems = false

        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = context
            item.isEnabled = enabled
            menu.addItem(item)
        }

        add("Insert Row Above", #selector(insertMarkdownTableRowAbove(_:)), enabled: address.row > 0)
        add("Insert Row Below", #selector(insertMarkdownTableRowBelow(_:)))
        add("Delete Row", #selector(deleteMarkdownTableRow(_:)), enabled: address.row > 0)
        menu.addItem(.separator())
        add("Insert Column Before", #selector(insertMarkdownTableColumnBefore(_:)))
        add("Insert Column After", #selector(insertMarkdownTableColumnAfter(_:)))
        add("Delete Column", #selector(deleteMarkdownTableColumn(_:)), enabled: (grid?.columnCount ?? 1) > 1)
        menu.addItem(.separator())
        add("Show Table Source", #selector(toggleMarkdownTableSource(_:)))
        return menu
    }

    private func applyTableMenuEdit(_ sender: NSMenuItem, _ build: (MarkdownTableGrid, MarkdownTableCellAddress) -> MarkdownTableEdit?) {
        guard let context = sender.representedObject as? MarkdownTableMenuContext,
              let grid = MarkdownTableEditor.grid(containingUTF16Location: context.anchor, in: string),
              grid.storageRange.location == context.anchor,
              let edit = build(grid, context.address) else { return }
        endTableCellEdit(commit: false)
        _ = applyMarkdownTableEdit(edit)
    }

    @objc private func insertMarkdownTableRowAbove(_ sender: NSMenuItem) {
        applyTableMenuEdit(sender) { MarkdownTableEditor.insertingRow(below: $1.row - 1, in: $0) }
    }

    @objc private func insertMarkdownTableRowBelow(_ sender: NSMenuItem) {
        applyTableMenuEdit(sender) { MarkdownTableEditor.insertingRow(below: $1.row, in: $0) }
    }

    @objc private func deleteMarkdownTableRow(_ sender: NSMenuItem) {
        applyTableMenuEdit(sender) { MarkdownTableEditor.deletingRow($1.row, in: $0) }
    }

    @objc private func insertMarkdownTableColumnBefore(_ sender: NSMenuItem) {
        applyTableMenuEdit(sender) { MarkdownTableEditor.insertingColumn(at: $1.column, in: $0) }
    }

    @objc private func insertMarkdownTableColumnAfter(_ sender: NSMenuItem) {
        applyTableMenuEdit(sender) { MarkdownTableEditor.insertingColumn(at: $1.column + 1, in: $0) }
    }

    @objc private func deleteMarkdownTableColumn(_ sender: NSMenuItem) {
        applyTableMenuEdit(sender) { MarkdownTableEditor.deletingColumn($1.column, in: $0) }
    }

    /// The raw-markdown escape, and it is a command rather than a caret position.
    ///
    /// iOS reveals whichever block the caret happens to be inside (`MarkdownStyleRanges.isRevealed`)
    /// — which is the behaviour T-221 exists to remove, because it means the table un-renders itself
    /// while you are editing it. Here the source appears only when asked for, stays until asked to
    /// go away, and while it is showing the table falls back to the banded per-row styling
    /// `applyTableRow` has always drawn.
    @objc private func toggleMarkdownTableSource(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MarkdownTableMenuContext else { return }
        endTableCellEdit(commit: true)
        revealedTableAnchor = revealedTableAnchor == context.anchor ? nil : context.anchor
        if let scrollView = enclosingScrollView {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: self)
            }
            MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        } else {
            MarkdownStylist.apply(to: self)
        }
        needsDisplay = true
    }
}

struct MarkdownTableMenuContext {
    let anchor: Int
    let address: MarkdownTableCellAddress
}
#endif
