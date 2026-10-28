import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-7873]].** iOS's markdown editor commit is no longer a pure debounce.
///
/// `iOSMarkdownEditingSurface` held typing behind a 2.5 s debounce re-armed on every keystroke, so
/// typing that never paused reached its host's binding only at the pause, and a crash or OS kill
/// while the app was active (no scene hook runs, [[T-7871]]) lost all of it. The handle now arms
/// [[T-7810]]'s schedule with a ceiling measured from the first held keystroke.
///
/// The window logic (`MarkdownEditorCommitWindow`) and the timing are Shared, so they are proved
/// here with an injected clock on both legs; `iOSMarkdownEditorFlush` and the surface are iOS-only,
/// so their use of it is pinned from source, and the handle's own behaviour is in
/// `iOSMarkdownEditorFlushTests` (iOS destination). Not verified by a crash while typing on a
/// device or simulator.
@MainActor
@Suite
struct iOSMarkdownEditorCommitCeilingTests {
    private static let idle = MarkdownEditorSyncTiming.iOSContentCommitDelay
    private static let ceiling = MarkdownEditorSyncTiming.iOSContentCommitMaxWait

    /// Replays keystrokes through the window the way `iOSMarkdownEditorFlush` does: a keystroke
    /// made before the armed write runs re-arms it inside the open window; the write running closes
    /// the window. Returns when the writes run.
    private func writeTimes(
        keystrokesAt offsets: [TimeInterval],
        idleDelay: TimeInterval? = nil,
        maxWait: TimeInterval? = nil
    ) -> [TimeInterval] {
        let idleDelay = idleDelay ?? Self.idle
        let maxWait = maxWait ?? Self.ceiling
        var window = MarkdownEditorCommitWindow()
        var fires: [TimeInterval] = []
        var armedFire: TimeInterval?
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        for offset in offsets {
            if let fire = armedFire, fire <= offset {
                fires.append(fire)
                armedFire = nil
                window.close()
            }
            let delay = window.delay(forEditAt: origin.addingTimeInterval(offset), idleDelay: idleDelay, maxWait: maxWait)
            armedFire = offset + delay
        }
        if let armedFire { fires.append(armedFire) }
        return fires
    }

    private static let unbrokenTyping = stride(from: 0.0, through: 60.0, by: 0.5).map { $0 }

    @Test func unbrokenTypingReachesTheBindingWithinTheCeilingOfEachKeystroke() {
        let fires = writeTimes(keystrokesAt: Self.unbrokenTyping)
        // A pure debounce writes once, after the last keystroke; the ceiling writes during.
        #expect(fires.count >= 5, "a minute of unbroken typing was written only \(fires.count) times: \(fires)")
        for keystroke in Self.unbrokenTyping {
            let writtenBy = fires.first { $0 >= keystroke }
            #expect(writtenBy != nil)
            if let writtenBy {
                #expect(writtenBy - keystroke <= Self.ceiling + 0.001, "keystroke at \(keystroke)s held until \(writtenBy)s")
            }
        }
    }

    /// Hosts whose binding saves the store (`CadenceCoreNoteSupport.update`) must not save more
    /// often than the debounce already allowed: writes stay at least one idle delay apart.
    @Test func theCeilingDoesNotWriteMoreOftenThanOncePerIdleDelay() {
        #expect(Self.ceiling >= Self.idle)
        let fires = writeTimes(keystrokesAt: Self.unbrokenTyping)
        for (earlier, later) in zip(fires, fires.dropFirst()) {
            #expect(later - earlier >= Self.idle - 0.5, "writes closer together than the idle delay: \(fires)")
        }
    }

    @Test func aPauseStillWritesTheIdleDelayAfterTheLastKeystroke() {
        #expect(writeTimes(keystrokesAt: [0, 1, 2]) == [2 + Self.idle])
    }

    @Test func theWindowOpensAtTheFirstHeldKeystrokeAndOnlyClosingItReopensIt() {
        var window = MarkdownEditorCommitWindow()
        let first = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(window.delay(forEditAt: first, idleDelay: 2.5, maxWait: 10) == 2.5)
        #expect(window.start == first)
        // Nine seconds in, only one second of the ceiling is left.
        #expect(window.delay(forEditAt: first.addingTimeInterval(9), idleDelay: 2.5, maxWait: 10) == 1)
        #expect(window.start == first, "a later keystroke must not restart the window")
        // Past the ceiling: write at once.
        #expect(window.delay(forEditAt: first.addingTimeInterval(12), idleDelay: 2.5, maxWait: 10) == 0)
        window.close()
        #expect(window.start == nil)
        let next = first.addingTimeInterval(20)
        #expect(window.delay(forEditAt: next, idleDelay: 2.5, maxWait: 10) == 2.5)
        #expect(window.start == next)
    }

    // MARK: - T-7891's iOS half: a ceiling write must not mint a half-typed #tag

    @Test func theCaretIsTypingATagOnlyInsideOrAtTheEndOfAnInlineTagOnItsLine() {
        #expect(MarkdownInlineTagCaret.isTypingInlineTag(in: "x #pro", caret: 6))
        #expect(MarkdownInlineTagCaret.isTypingInlineTag(in: "x #pro", caret: 4))
        #expect(MarkdownInlineTagCaret.isTypingInlineTag(in: "x #pro", caret: 2), "the caret before the #")
        #expect(!MarkdownInlineTagCaret.isTypingInlineTag(in: "x #pro ", caret: 7), "the word is finished")
        #expect(!MarkdownInlineTagCaret.isTypingInlineTag(in: "x #pro", caret: 1))
        #expect(!MarkdownInlineTagCaret.isTypingInlineTag(in: "x #", caret: 3), "a bare # is not a tag yet")
        #expect(!MarkdownInlineTagCaret.isTypingInlineTag(in: "C#", caret: 2))
        #expect(!MarkdownInlineTagCaret.isTypingInlineTag(in: "#done\nnext", caret: 10), "a tag on another line")
        #expect(!MarkdownInlineTagCaret.isTypingInlineTag(in: "", caret: 5))
    }

    @Test func aDeferredCeilingKeepsTheWindowAndTheNextKeystrokeOutsideTheTagFiresAtOnce() {
        var window = MarkdownEditorCommitWindow()
        let first = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = window.delay(forEditAt: first, idleDelay: 2.5, maxWait: 10)
        let inTag = window.delay(forEditAt: first.addingTimeInterval(11), idleDelay: 2.5, maxWait: 10, deferringCeiling: true)
        #expect(inTag == 2.5)
        #expect(window.start == first)
        #expect(window.delay(forEditAt: first.addingTimeInterval(12), idleDelay: 2.5, maxWait: 10) == 0)
    }

    /// The surface's whole path on an injected clock, into an in-memory store through the note
    /// host's save-on-write `CadenceCoreNoteSupport.update`: one character every 0.5 s, so the
    /// ceiling falls due ten seconds in, while `#project` is half typed (`#pr`).
    @Test func unbrokenTypingThroughTheCeilingMintsOnlyTheFinishedTag() throws {
        let typed = Array("Some typing here #project and then a good deal more prose after it")
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let note = Note(kind: .list, title: "Note", content: "")
        context.insert(note)
        try context.save()

        var window = MarkdownEditorCommitWindow()
        var armed: (fire: TimeInterval, text: String)?
        var written: [String] = []
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        func write(_ text: String) {
            written.append(text)
            CadenceCoreNoteSupport.update(note, content: text, in: context)
        }
        for index in typed.indices {
            let offset = TimeInterval(index) * 0.5
            if let pending = armed, pending.fire <= offset {
                write(pending.text)
                armed = nil
                window.close()
            }
            let text = String(typed[...index])
            let delay = window.delay(
                forEditAt: origin.addingTimeInterval(offset),
                idleDelay: Self.idle,
                maxWait: Self.ceiling,
                deferringCeiling: MarkdownInlineTagCaret.isTypingInlineTag(in: text, caret: (text as NSString).length)
            )
            armed = (offset + delay, text)
        }
        if let pending = armed { write(pending.text) }

        #expect(written.count >= 3, "the ceiling never wrote during the burst: \(written)")
        #expect(written.first?.hasSuffix("#project ") == true, "the due ceiling fires on the first keystroke past the tag: \(written)")
        let names = try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>()).map(\.name).sorted()
        #expect(names == ["project"], "a half-typed tag was minted: \(names)")
    }

    // MARK: - The iOS call sites, which only the iOS leg compiles

    @Test func theSurfaceArmsItsWriteWithTheCeiling() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        let schedule = try #require(CadenceSourceScan.functionBody(named: "scheduleCommit", in: source))
        let compact = schedule.filter { !$0.isWhitespace }
        #expect(compact.contains(
            "pendingCommit.schedule(after:MarkdownEditorSyncTiming.iOSContentCommitDelay,ceiling:MarkdownEditorSyncTiming.iOSContentCommitMaxWait,deferringCeiling:MarkdownInlineTagCaret.isTypingInlineTag(in:nextText,caret:NSMaxRange(selectedRange)))"
        ))
    }

    @Test func theHandleMeasuresTheCeilingOnItsClockAndClosesTheWindowWithTheWrite() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        let schedule = try #require(CadenceSourceScan.declarationBody("func schedule(\n", in: source))
        #expect(schedule.contains("window.delay(forEditAt: now(), idleDelay: delay, maxWait: $0, deferringCeiling: deferringCeiling)"))
        #expect(schedule.contains("deadline: .now() + fireDelay"))
        // `flush()` runs through `cancel()`, so closing it there covers the write and the drop.
        let cancel = try #require(CadenceSourceScan.functionBody(named: "cancel", in: source))
        #expect(cancel.contains("window.close()"))
        let flush = try #require(CadenceSourceScan.functionBody(named: "flush", in: source))
        #expect(flush.contains("cancel()"))
    }
}
