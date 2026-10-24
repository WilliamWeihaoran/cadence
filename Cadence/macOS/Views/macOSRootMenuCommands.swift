#if os(macOS)
import SwiftUI

/// **[[T-5953]] — Cmd+N is New Task everywhere, and the app's one menu replacement.**
///
/// Before this existed there was no `.commands` anywhere in `Cadence/`, so an unclaimed Cmd+N
/// reached SwiftUI's own File ▸ New Window. Off a Kanban column — Today, Inbox, Notes, anywhere
/// the pointer rests on no column — that is what the key did, and the root monitor's
/// `case 45` arm handed it on (`macOSRootCommandEventSupport.handleCommandKeyEvent`).
///
/// **A second window is a correctness hazard here, not only a surprise.** The New Task panel,
/// Cmd+K search and the delete confirmation are driven by app-wide `.shared` managers injected
/// once in `CadenceApp`, so each of them draws in *both* windows at once and dismissing it in one
/// dismisses both; and the app is a single SwiftData store behind CloudKit, so two windows are
/// two writers on one store. `macOSRootStateSupport.configureMainWindow()` styles only
/// `NSApp.windows.first(where:)`, which is the same assumption from the other side.
///
/// **New Window stays as an item and loses its key equivalent.** It is not removed: [[T-3186]]
/// recorded that a `scripts/run-macos-app.sh` launch on this Mac can come up with ZERO windows,
/// and the one recipe that recovers from that is an AppleScript which opens the File menu and
/// clicks this item. The owner's decision was the item without the shortcut.
struct macOSRootMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(CadenceNewItemMenu.newTask.title) {
                TaskCreationManager.shared.present()
            }
            .keyboardShortcut(KeyEquivalent(CadenceNewItemMenu.newTaskShortcut), modifiers: .command)

            Button(CadenceNewItemMenu.newWindow.title) {
                openWindow(id: CadenceWindowGroupID.main)
            }
        }
    }
}

/// **The File ▸ New group as data, so a test can read it.** The group itself is a `Commands`
/// value: nothing in `CadenceTests` can build a main menu and press a key against it, and a
/// shortcut that silently went missing is exactly the regression this ticket is about.
nonisolated enum CadenceNewItemMenu {
    struct Item: Equatable {
        let title: String
        /// The item's Cmd-key equivalent, or `nil` when it deliberately has none.
        let commandShortcut: Character?
    }

    /// The one character the group binds. Read by the menu itself, so a test that asserts it is
    /// asserting what the item actually carries rather than a second copy of it.
    static let newTaskShortcut: Character = "n"

    /// Cmd+N, from anywhere. Over a Kanban column the root key monitor still claims the key first
    /// and creates the card in that column; everywhere else it falls through to this.
    static let newTask = Item(title: "New Task", commandShortcut: newTaskShortcut)

    /// No key equivalent, on the owner's decision — the item exists for [[T-3186]]'s zero-window
    /// recovery, and Cmd+N belongs to New Task.
    static let newWindow = Item(title: "New Window", commandShortcut: nil)

    static let items: [Item] = [newTask, newWindow]
}
#endif
