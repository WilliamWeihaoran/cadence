# Markdown Editor Guide

This is a high-risk AppKit/SwiftUI bridge. Read the relevant files before editing and keep changes narrow.

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
