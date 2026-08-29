import Foundation
import Testing

/// T-367, decided: **global Cmd+Z on the model context is a hazard, and it is gone.**
///
/// The macOS root used to install an `UndoManager` on the app's one `ModelContext` and route
/// non-text Cmd+Z into it. The reasoning for removing it is on `macOSRootLifecycleSupport`; the
/// short form is that this app has a single context, so a whole-context undo reverts whatever that
/// context recorded last rather than what the user last did, and every destructive path in the app
/// is a store write *plus* effects — cancelled reminders, disposed bundles, repaired recurrence
/// links, torn-down focus state — that no undo stack ever saw. Two sheets tell the user "This
/// cannot be undone", and after this change that sentence is true.
///
/// Editor undo is untouched. `NSTextView` owns an `UndoManager` of its own and reaches it through
/// the responder chain; the root never had to do anything for that to work, which is why removing
/// the Cmd+Z case leaves it alone rather than breaking it.
///
/// **These are source scans and none of the evidence here is behavioural**, which is worth stating
/// rather than implying. What was removed is *wiring*: an assignment in an `onAppear` and a `case`
/// in an `NSEvent` table. There is no value to read back — the observable difference is an
/// `UndoManager` that no longer exists and a keystroke that reaches the responder chain instead of
/// being swallowed, and reaching either would mean driving a live `NSApp` key window.
///
/// The *decision* was measured even though these guards are not: what
/// `ModelContext.undoManager` actually reverts on this schema is recorded on
/// `macOSRootLifecycleSupport.handleAppear`. That measurement was a throwaway rather than a kept
/// test, because it pins SwiftData's undo semantics rather than anything Cadence owns, and those
/// are Apple's to change.
struct CadenceGlobalUndoSurfaceTests {

    /// The rule, swept over the whole app rather than over the two files that used to break it.
    ///
    /// It is stated as "nothing assigns an undo manager", not "the root does not", because the
    /// second is a claim about one call site and the mistake is a shape. The negative witness is a
    /// *read* of `undoManager`, which is how a text view is legitimately asked for its own.
    @Test func noAppSourceHandsAnUndoManagerToAnything() throws {
        let instrument = try CadenceScanInstrument(
            "undoManager assignment",
            fires: """
            if modelContext.undoManager == nil {
                modelContext.undoManager = UndoManager()
            }
            """,
            andNotOn: """
            if let manager = textView.undoManager, manager.canUndo {
                manager.undo()
            }
            """,
            by: { source in
                CadenceSourceScan.matchCount(
                    "\\.undoManager\\s*=(?!=)",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )

        let files = try cadenceAppSwiftFiles()
        let offenders = try instrument.sweep(
            files,
            // The app was 480-odd files when this was written; a walk that collapses is the way a
            // sweep like this passes forever.
            atLeast: 300,
            including: "Cadence/macOS/Views/macOSRootLifecycleSupport.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            "an undo manager is being installed on something: \(offenders)"
        )
    }

    /// The other half of the removal, scoped to the brace-matched body of the key table rather
    /// than to the file — a whole-file scan for `case 6:` would be satisfied by
    /// `handleModalConfirmations` growing one.
    ///
    /// Stated as an absence *plus* four presences: an absence on its own is equally happy with a
    /// body that was never read.
    @Test func theRootsCommandKeyTableNoLongerClaimsCommandZ() throws {
        let body = try cadenceFunctionBody(
            "static func handleCommandKeyEvent",
            in: CadenceSourceScan.codeOnly(
                try cadenceTestSource("Cadence/macOS/Views/macOSRootCommandEventSupport.swift")
            )
        )

        // Non-vacuity: this is the table, and it still claims the keys it should.
        #expect(body.contains("case 40:"), "non-vacuity: Cmd+Space is not in the body that was read")
        #expect(body.contains("case 51:"), "non-vacuity: Cmd+Delete is not in the body that was read")
        #expect(body.contains("case 36, 76:"), "non-vacuity: Cmd+Return is not in the body that was read")
        #expect(body.contains("case 31:"), "non-vacuity: Cmd+B is not in the body that was read")

        #expect(
            CadenceSourceScan.matchCount("case 6:", in: body) == 0,
            "the root is claiming Cmd+Z again"
        )
        #expect(body.contains("undoManager") == false)
    }

    /// "Leave editor undo alone" is a claim about code that still exists, so it is asserted
    /// positively rather than as the absence of something.
    @Test func theMarkdownEditorStillOwnsItsOwnUndoThroughTheTextView() throws {
        let editor = try cadenceTestSource("Cadence/macOS/Editor/MarkdownEditorView.swift")
        #expect(editor.contains("textView.allowsUndo = true"))
        // And it is the text view's own, never one handed to it from outside.
        #expect(
            CadenceSourceScan.matchCount(
                "undoManager\\s*=(?!=)",
                in: CadenceSourceScan.codeOnly(editor)
            ) == 0
        )
    }

    /// The copy the removal was measured against. If someone puts model undo back, these two
    /// sentences become false again — so the sentences are pinned next to the rule that makes them
    /// true, rather than in a suite that has never heard of it.
    @Test func theDestructiveSheetsStillPromiseTheDeleteIsFinal() throws {
        for path in [
            "Cadence/macOS/Sheets/CreateGoalSheet.swift",
            "Cadence/macOS/Views/HabitsFormSheets.swift"
        ] {
            let source = try cadenceTestSource(path)
            #expect(
                source.contains("This cannot be undone."),
                "\(path) no longer tells the user the delete is final"
            )
        }
    }
}

/// Every `.swift` file in the app target's source tree, repo-relative.
///
/// Named apart from `cadenceTestFiles()` on purpose: that one walks `CadenceTests`, this one walks
/// the thing under test, and a sweep that confused them would be green for the wrong reason.
func cadenceAppSwiftFiles() throws -> [String] {
    cadenceRepoSwiftFiles(under: "Cadence")
}
