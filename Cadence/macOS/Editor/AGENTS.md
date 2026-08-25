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
- `MarkdownEditorTextViewDecorations.swift` - the **three** decoration passes that need
  `CadenceTextView` state (task-embed card, standalone image, rendered table), run from
  `drawBackground(in:)`.
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
- `MarkdownTableCanvasDrawing.swift` - draws the rendered table grid, and declares
  `MarkdownTableHitInfo`, the cache the draw pass writes and a click reads.
- `MarkdownTableInteractionSupport.swift` - the hosted cell editor: click / Tab / Shift-Tab /
  Return, the row and column context menu, and the "Show Table Source" escape.

These thirteen Swift files were six until T-105 and eleven until T-221; `MarkdownEditorInteractionSupport.swift` was 1,996
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

**Three of `MarkdownStylist`'s constants are `static var` and not `static let`, and that is not an
oversight to tidy up.** `blueColor`, `greenColor` and `redColor` are accents, and the six accents
are user-selectable since T-15 (`Cadence/Shared/AGENTS.md`). A stored `static let` there
initialises once and then paints whichever palette happened to be active the first time a note was
styled — silently, for the life of the process. The eleven neutral ones beside them stay stored,
because the neutral ramp cannot vary. Reading one is still a stored-property load, not an
`NSColor(Color)` conversion: `CadenceAccentResolution` resolves the three mirrors eagerly per
palette. This layer is AppKit, so it sits outside SwiftUI's observation of the selection and
repaints on its next restyle rather than instantly — which is exactly why the accessors have to be
computed for that restyle to be right.

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

## Rendered tables are edited in place (T-221, macOS only)

A table is drawn as a real grid and edited cell by cell. The rule that makes that safe is one
sentence: **the markdown source never leaves the text storage.** `MarkdownStylist.applyRenderedTables`
only collapses the table's glyphs — `hide` plus a 0.1pt line height on every line but the first,
and the whole grid's height reserved on that first one — and a hosted `NSTextField` writes cell
values back through `shouldChangeText` / `replaceCharacters` / `didChangeText`.

Three of the four things a hosted view usually breaks therefore need no mechanism at all, and
`MarkdownTableHostedEditingTests` measures each on a real offscreen `CadenceTextView`:

- **Selection and copy/paste** work because the characters are still there, in their real range.
- **Undo** works because a committed cell is an ordinary text-view edit on the view's own stack —
  which is why `applyMarkdownTableEdit` is the single write path and must never be replaced by a
  bare `replaceCharacters` or by assigning `string`.
- **Invalidation** is the ordinary `textDidChange` restyle. There is no signature gate on this
  platform: `MarkdownStyleSignature` is read only by `Cadence/iOS/iOSMarkdownEditor.swift`.

Two consequences worth knowing before you touch this:

- The raw source is reachable **by command** — "Show Table Source" in the table's context menu,
  held in `CadenceTextView.revealedTableAnchor` — and never by caret position. A revealed table
  falls back to `applyTableRow`, the banded per-row styling that predates all of this, so that
  path has to keep working.
- `MarkdownTableParser` distinguishes opening a table from continuing one. An all-blank row like
  `|  |  |` continues a table and cannot start one, because Return inserts exactly that.

The markdown decisions are `Services/MarkdownTableEditSupport.swift`; the rects are
`Services/MarkdownTableLayoutSupport.swift`. Nothing here re-derives either.

**iOS has none of this.** `iOSMarkdownStylingBlockSupport` still draws a table as a canvas and
un-renders it when the caret lands inside, which is the behaviour T-221 exists to remove.

## Working Rules

- Preserve per-note/document `NSTextView` identity and undo behavior.
- Preserve hidden markdown marker caret traversal rules.
- Do not block UI with save/export panels from editor paths.
- Avoid rewriting parsing or attributed-string logic with ad hoc string operations unless the scope is tiny and well tested.
- Keep AppKit imperative behavior isolated inside editor support/coordinator types.
- Test keyboard navigation, undo/redo, slash commands, links, and task embeds after meaningful changes.

## Refactor Guidance

Split by editor responsibility, not by arbitrary line count. Behavior here is coupled through NSTextView lifecycle and selection state, so prefer small extraction steps with a build after each one.
