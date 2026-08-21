# Markdown Editor Guide

This is a high-risk AppKit/SwiftUI bridge. Read the relevant files before editing and keep changes narrow.

**Most markdown logic is not here.** The 27 `Markdown*.swift` files in
`Cadence/Services/` own parsing, attributed-string construction, list/quote/checklist rules,
typing transforms, backspace/line-break behavior, slash-command definitions, links, references,
task embeds, inline preview, and image assets — and they are the ones with test coverage in
`CadenceTests/`. The files here are the AppKit surface that calls into them. Behavior fixes
usually belong in `Services/`; only NSTextView lifecycle, drawing, and event handling belong here.

## File Roles

- `MarkdownEditorView.swift` - SwiftUI wrapper and editor setup.
- `MarkdownEditorSupport.swift` - markdown styling, parsing, list rules, hidden marker attributes.
- `MarkdownEditorInteractionSupport.swift` - the `CadenceTextView` subclass: caret behavior, hit
  testing, keyboard/mouse interaction, inline task-title editing, image insert/resize.
- `MarkdownEditorTextViewDecorations.swift` - the two decoration passes that need `CadenceTextView`
  state (task-embed card, standalone image), run from `drawBackground(in:)`.
- `MarkdownEditorLayoutManager.swift` - `CadenceLayoutManager`: the six decoration passes that need
  only colours and geometry, plus the hidden-glyph range arithmetic.
- `MarkdownEditorDecorationGeometry.swift` - the rect math those passes draw with. Pure, macOS-only,
  and unit tested from `CadenceTests` (`MarkdownDecorationGeometryTests`).
- `MarkdownEditorCoordinator.swift` - the `NSTextViewDelegate`: styling on change, slash commands,
  reference and tag pickers.
- `MarkdownEditorTextEditDiff.swift` - minimal single-edit diff used to apply a rewritten document
  without losing caret, scroll position or undo.
- `MarkdownSlashCommandSupport.swift` - slash command model, filtering, positioning, and actions.
- `MarkdownTaskEmbedDrawingSupport.swift` - embedded task rendering/drawing support.
- `MarkdownKeyboardShortcutSupport.swift` - editor-specific shortcuts.

These eleven Swift files were six until T-105; `MarkdownEditorInteractionSupport.swift` was 1,996
lines and the largest file in the repo, and is now 843. Split by responsibility (layout manager /
text view / decorations / coordinator / geometry / diff), not by line count. (This paragraph said
"seven ... were four" while the list directly above it named eleven — the count is the list.)

## Concurrency

`CadenceLayoutManager` is fully `nonisolated`, including `drawBackground(forGlyphRange:at:)`, and
must stay that way: `NSLayoutManager`'s members are nonisolated while the project default is
`MainActor`, so a main-actor override there is a hard error under Swift 6. That is why the two
view-touching decoration passes live on `CadenceTextView` instead. Do **not** "fix" a future
isolation error here with `nonisolated(unsafe)`, `@preconcurrency import AppKit`, or by moving the
view's hit-rect and hover caches into a nonisolated holder — the last one compiles and changes no
z-order, and it removes the diagnostic without removing the hazard.

`Theme` and `MarkdownStylist`'s palette constants are `nonisolated` for the same reason: a
nonisolated `static let` cannot initialize from a main-actor one. `Theme.swift` also compiles into
`CadenceWidgets`, so changes there need that scheme built too.

## Draw order

`CadenceTextView.drawBackground(in:)` runs before everything the layout manager draws — text
backgrounds and glyphs — which is where the task-embed card and the standalone image sit relative
to the glyph pass, and where they sat before they moved.

Measured on macOS 26, the selection highlight and the insertion point are **not** painted inside
the view's `draw(_:)`: a full-view `cacheDisplay` with `shouldDrawInsertionPoint == true` is
pixel-identical to one with the caret off, and running these passes after `super.draw(_:)` instead
changes no pixel. Both are composited above everything the view draws, so no hook choice here can
occlude either. Do not take that as licence to move them — the current hook is also correct if
AppKit goes back to drawing selection inside `draw(_:)`; the other one is not.

`MarkdownEditorDrawOrderTests` renders the view offscreen and asserts the passes still run, that a
selection spanning an embed still washes out the card, that the same selection does not reach a
drawn image, and that a band redrawn on its own matches the same band of a full redraw. Run it
after touching any draw path.

## Working Rules

- Preserve per-note/document `NSTextView` identity and undo behavior.
- Preserve hidden markdown marker caret traversal rules.
- Do not block UI with save/export panels from editor paths.
- Avoid rewriting parsing or attributed-string logic with ad hoc string operations unless the scope is tiny and well tested.
- Keep AppKit imperative behavior isolated inside editor support/coordinator types.
- Test keyboard navigation, undo/redo, slash commands, links, and task embeds after meaningful changes.

## Refactor Guidance

Split by editor responsibility, not by arbitrary line count. Behavior here is coupled through NSTextView lifecycle and selection state, so prefer small extraction steps with a build after each one.
