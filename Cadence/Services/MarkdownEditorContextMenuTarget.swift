import Foundation

/// **[[T-18882]] — what a right-click (Mac) or long-press (iPad, iPhone) in the note editor is on.**
///
/// The editor's context menu answers four things, in this order: a rendered table cell (the
/// table's row/column menu), a table whose source is revealed (Hide Table Source over the text
/// menu), a task embedded as a `[[task:UUID|Title]]` card (the task menu every other task surface
/// opens -- row, board card, timeline block, Calendar chips, under [[T-1479]]'s ruling), and
/// otherwise the text view's own menu. Until T-18882 both editors knew only the first two, so the
/// one task surface left offered Cut / Copy / Paste.
///
/// Pure so both platforms decide the same way and a test can pin the precedence without a text
/// view: each probe is the platform's own geometric hit test, passed lazily, and is asked only
/// when every branch above it missed. Tables come first because they were first, and because a
/// probe that is never asked cannot be wrong.
enum MarkdownEditorContextMenuTarget<TableCell> {
    case tableCell(TableCell)
    case revealedTable(anchor: Int)
    case taskEmbed(UUID)
    case text

    static func classify(
        tableCell: () -> TableCell?,
        revealedTableAnchor: () -> Int?,
        taskEmbedID: () -> UUID?
    ) -> Self {
        if let cell = tableCell() { return .tableCell(cell) }
        if let anchor = revealedTableAnchor() { return .revealedTable(anchor: anchor) }
        if let id = taskEmbedID() { return .taskEmbed(id) }
        return .text
    }
}
