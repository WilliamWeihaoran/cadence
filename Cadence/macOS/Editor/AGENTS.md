# Markdown Editor Guide

This is a high-risk AppKit/SwiftUI bridge. Read the relevant files before editing and keep changes narrow.

**Most markdown logic is not here.** The ~21 `Markdown*Support.swift` files in
`Cadence/Services/` own parsing, attributed-string construction, list/quote/checklist rules,
typing transforms, backspace/line-break behavior, slash-command definitions, links, references,
task embeds, inline preview, and image assets — and they are the ones with test coverage in
`CadenceTests/`. The six files here are the AppKit surface that calls into them. Behavior fixes
usually belong in `Services/`; only NSTextView lifecycle, drawing, and event handling belong here.

## File Roles

- `MarkdownEditorView.swift` - SwiftUI wrapper and editor setup.
- `MarkdownEditorSupport.swift` - markdown styling, parsing, list rules, hidden marker attributes.
- `MarkdownEditorInteractionSupport.swift` - NSTextView subclass/coordinator, custom drawing, caret behavior, keyboard/mouse interaction.
- `MarkdownSlashCommandSupport.swift` - slash command model, filtering, positioning, and actions.
- `MarkdownTaskEmbedDrawingSupport.swift` - embedded task rendering/drawing support.
- `MarkdownKeyboardShortcutSupport.swift` - editor-specific shortcuts.

## Working Rules

- Preserve per-note/document `NSTextView` identity and undo behavior.
- Preserve hidden markdown marker caret traversal rules.
- Do not block UI with save/export panels from editor paths.
- Avoid rewriting parsing or attributed-string logic with ad hoc string operations unless the scope is tiny and well tested.
- Keep AppKit imperative behavior isolated inside editor support/coordinator types.
- Test keyboard navigation, undo/redo, slash commands, links, and task embeds after meaningful changes.

## Refactor Guidance

Split by editor responsibility, not by arbitrary line count. Behavior here is coupled through NSTextView lifecycle and selection state, so prefer small extraction steps with a build after each one.
