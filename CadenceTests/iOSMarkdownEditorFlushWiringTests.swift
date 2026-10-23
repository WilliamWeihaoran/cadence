import Foundation
import Testing
@testable import Cadence

// [[T-5170]] and [[T-5171]]: the call sites, which only the iOS leg compiles.
//
// `iOSMarkdownEditorFlushTests` proves on an iOS destination that a flush puts held typing into the
// binding before a commit reads it. What it cannot reach is whether each host actually flushes
// FIRST — the commits live inside SwiftUI views' private functions and button closures. These pins
// read that order from source, comment-stripped (string literals kept, so `Button("Done")` anchors).
@Suite
struct iOSMarkdownEditorFlushWiringTests {
    private static func index(of needle: String, in text: String) -> String.Index? {
        text.range(of: needle)?.lowerBound
    }

    /// The surface's debounce goes through the handle, so a host's flush reaches it.
    @Test func theSurfaceHoldsItsDebouncedWriteInTheFlushHandle() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        let schedule = try #require(CadenceSourceScan.functionBody(named: "scheduleCommit", in: source))
        #expect(schedule.contains("pendingCommit.schedule(after:"))
        #expect(!schedule.contains("DispatchQueue"), "a private timer is one no host can flush")
        let immediate = try #require(CadenceSourceScan.functionBody(named: "commitDraftImmediately", in: source))
        #expect(immediate.contains("pendingCommit.cancel()"))
        #expect(source.contains("flush ?? ownFlush"))
    }

    /// Both panel sheets flush before `save()` reads the draft or stops at the scope question.
    @Test(arguments: [
        ("Cadence/iOS/iOSTaskDetailSheet.swift", "draft.changesRecurrence"),
        ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "applySave(scope:"),
    ])
    func eachPanelSaveFlushesTheNotesWellFirst(path: String, firstRead: String) throws {
        let source = try CadenceCommitSurfaceScan.scanned(path)
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: source))
        let flush = try #require(Self.index(of: "notesFlush.flush()", in: save), "\(path): save() does not flush")
        let read = try #require(Self.index(of: firstRead, in: save), "\(path): anchor \(firstRead) moved")
        #expect(flush < read, "\(path): save() reads the draft before flushing the well")
        #expect(source.contains("interactiveDismissDisabled(draft != openedDraft || notesFlush.hasPendingEdit)"))
    }

    /// The three record-backed sheets flush before Done saves.
    @Test(arguments: [
        ("Cadence/iOS/iOSEventNoteEditorSheet.swift", "persistNote().isSaved"),
        ("Cadence/iOS/iOSMarkdownReferenceSupport.swift", "flushBeforeDismissing()"),
        ("Cadence/iOS/iOSSearchSupportViews.swift", "flushBeforeDismissing()"),
    ])
    func eachNoteSheetsDoneFlushesTheWellFirst(path: String, commit: String) throws {
        let source = try CadenceCommitSurfaceScan.scanned(path)
        let done = try #require(CadenceSourceScan.declarationBody("Button(\"Done\")", in: source))
        let flush = try #require(Self.index(of: "editorFlush.flush()", in: done), "\(path): Done does not flush")
        let save = try #require(Self.index(of: commit, in: done), "\(path): anchor \(commit) moved")
        #expect(flush < save, "\(path): Done saves before flushing the well")
        #expect(source.contains("flush: editorFlush"), "\(path): the handle is not given to the surface")
    }

    /// [[T-5190]]: a swipe-dismiss skips Done, so each record-backed note sheet flushes the well
    /// and commits from its own `onDisappear`. Flush before the commit, and the event note mirrors
    /// through `persistNote()` (Apple Calendar) only when the context holds something.
    /// One test over the three, not a parameterised one, so `mutate.sh` can baseline it (T-3212).
    @Test func eachNoteSheetFlushesAndCommitsWhenSwipedAway() throws {
        for (path, commit) in [
            ("Cadence/iOS/iOSEventNoteEditorSheet.swift", "persistNote()"),
            ("Cadence/iOS/iOSMarkdownReferenceSupport.swift", "persistNote()"),
            ("Cadence/iOS/iOSSearchSupportViews.swift", "CadencePendingChangePersistence.commitTypedContent(in: modelContext)"),
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(source.contains(".onDisappear(perform: persistTypedTailOnDismissal)"), "\(path): a swipe commits nothing")
            let tail = try #require(
                CadenceSourceScan.functionBody(named: "persistTypedTailOnDismissal", in: source),
                "\(path): no dismissal commit"
            )
            let flush = try #require(Self.index(of: "editorFlush.flush()", in: tail), "\(path): the swipe does not flush")
            let save = try #require(Self.index(of: commit, in: tail), "\(path): the swipe does not commit")
            #expect(flush < save, "\(path): the swipe commits before flushing the well")
            if commit == "persistNote()" {
                let gate = try #require(Self.index(of: "guard modelContext.hasChanges else { return }", in: tail),
                                        "\(path): a dismissal with nothing pending still writes")
                #expect(flush < gate && gate < save)
            }
        }
    }

    /// Every surface host that flushes also hands the surface the handle it flushes.
    @Test func thePanelSheetsHandTheirFlushToTheWell() throws {
        let sections = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSTaskDetailSheetSections.swift")
        #expect(sections.contains("flush: flush"))
        let task = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSTaskDetailSheet.swift")
        #expect(task.contains("flush: notesFlush"))
        let event = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        #expect(event.contains("flush: notesFlush"))
    }

    /// [[T-5171]]: a store change goes through the untouched-draft decision, never straight over
    /// `draft.notes`.
    @Test func theEventSheetReloadsItsNoteOnlyThroughTheUntouchedCheck() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        let onStore = try #require(
            CadenceSourceScan.declarationBody(".onChange(of: calendarManager.storeVersion)", in: source)
        )
        #expect(onStore.contains("reloadEventNotesIfUntouched()"))
        #expect(!onStore.contains("draft.notes ="))
        let reload = try #require(CadenceSourceScan.functionBody(named: "reloadEventNotesIfUntouched", in: source))
        #expect(reload.contains("iOSCalendarEventNoteReload.reloadedNotes("))
        #expect(CadenceSourceScan.matchCount(#"draft\.notes\s*=\s*event\.notes"#, in: source) == 0)
        // The regex can see the old line at all.
        #expect(CadenceSourceScan.matchCount(#"draft\.notes\s*=\s*event\.notes"#, in: "draft.notes = event.notes ?? \"\"") == 1)
    }
}
