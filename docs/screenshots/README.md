# App Store screenshots

Candidate screenshots for the macOS App Store listing live in this directory, together with the two
scripts that make them reproducible. Nothing here is uploaded automatically; the user picks the
final set and uploads it in App Store Connect.

The five candidates in this directory were captured on 2026-09-05 (T-798) from
`52edd7c`, at **2560 x 1600**, RGB, no alpha. Regenerating them takes about twenty minutes and
needs an unlocked screen.

## What App Store Connect accepts

- 1 to 10 screenshots per macOS localisation.
- Exactly one of these pixel sizes: **1280 x 800**, **1440 x 900**, **2560 x 1600**, **2880 x 1800**.
- PNG or JPEG, RGB, flattened. **No alpha channel** — a raw `screencapture` of a window has
  transparent rounded corners and is rejected.

On a 2x display a window sized to **1440 x 900 points** captures as **2880 x 1800 pixels**, which is
the largest accepted size and the one to aim for. `Cadence/CadenceApp.swift` sets a
`minWidth: 960, minHeight: 600` floor, so 1440 x 900 is comfortably above it.

## Safety rules for anyone regenerating these

- Launch only through `scripts/run-macos-app.sh`, which forces `CADENCE_LOCAL_STORE_ONLY=1` and a
  throwaway `CADENCE_UI_TEST_STORE_ID` store. **Never** launch `/Applications/Cadence.app`; that is
  the user's own installed copy with their real data.
- Never point a seed or a capture at `~/Library/Containers/com.haoranwei.Cadence/Data/`.
  `seed-screenshot-data.py` refuses that path outright.
- Capture by window id (`screencapture -o -l<id>`), never full screen. Other windows on the display
  are not yours to capture.
- Terminate only the pid you launched. `scripts/run-macos-app.sh stop <id>` does this and removes the
  private store; pair every start with a stop in the same session.
- A **locked screen blocks this entirely**. `loginwindow` owns the foreground, the launched app never
  activates, and `screencapture -l` answers `could not create image from window`. This is the same
  condition `scripts/xcb.sh` refuses UI-test runs under (T-563). Unlock first.

## Procedure

1. Build the app and the MCP server into private DerivedData:

   ```sh
   ./scripts/xcb.sh shots build -scheme Cadence -destination 'platform=macOS' -configuration Debug
   ./scripts/xcb.sh shotsmcp build -scheme CadenceMCPServer -destination 'platform=macOS' -configuration Debug
   ```

2. Seed the private store **before** launching the app, so the app opens an already-populated store
   rather than racing a second writer:

   ```sh
   python3 docs/screenshots/seed-screenshot-data.py \
     --server "$TMPDIR/cadence-dd-shotsmcp/Build/Products/Debug/CadenceMCPServer" \
     --store  "$TMPDIR/CadenceUITestStores/shots/default.store"
   ```

3. Launch against that same store id:

   ```sh
   ./scripts/run-macos-app.sh start "$TMPDIR/cadence-dd-shots/Build/Products/Debug/Cadence.app" shots
   ```

4. Size the window to 1440 x 900 points and bring it forward:

   ```sh
   osascript -e 'tell application "System Events" to tell (first process whose unix id is PID)
       set frontmost to true
       set position of window 1 to {36, 37}
       set size of window 1 to {1440, 900}
   end tell'
   ```

5. Capture each angle by window id. The id is the `kCGWindowNumber` of the app's window; read it from
   `CGWindowListCopyWindowInfo` filtered on the launched pid.

   ```sh
   screencapture -x -o -l<windowid> raw-today.png
   python3 docs/screenshots/flatten-for-app-store.py raw-today.png docs/screenshots/01-today.png
   ```

6. Stop the app and delete the DerivedData trees:

   ```sh
   ./scripts/run-macos-app.sh stop shots
   rm -rf "$TMPDIR/cadence-dd-shots" "$TMPDIR/cadence-dd-shotsmcp"
   ```

## The five angles

`docs/app-store-submission-packet.md` asks for these, and they map onto sidebar destinations in
`CadenceFeatureDestination`:

| File | Destination | Seeded by |
| --- | --- | --- |
| `01-today.png` | Today | `seed-screenshot-data.py` — timed tasks across the working day, two already done |
| `02-calendar.png` | Calendar | `seed-screenshot-data.py` — tasks spread over the next four weeks |
| `03-lists-kanban.png` | Lists, board mode | **manual** — see below |
| `04-notes.png` | Notes, daily note open | `seed-screenshot-data.py` — a markdown daily note with headings, a quote, and checkboxes |
| `05-settings.png` | Settings, Privacy / Data Safety | nothing to seed |

### Why the Kanban angle is manual

The MCP write surface (`CadenceMCPServer/CadenceMCPToolDefinitions.swift`) can create tasks and
append to daily/weekly/permanent notes. It has no tool that creates a context, area or project, and
Kanban columns are `TaskSectionConfig` values stored on an `Area` or `Project`
(`Cadence/Models/AppTask.swift`). `create_task` will only accept a `sectionName` that already exists
on the target list.

So before capturing angle 3, create one project in the running app — Lists, new project, add two or
three sections — and then either drag a few of the seeded inbox tasks onto it or add cards from the
board's own composer. Everything else in this set needs no manual step.
