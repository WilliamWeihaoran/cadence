import Foundation
import Testing
@testable import Cadence

// [[T-5170]] and [[T-5171]], held by what the iOS types DO.
//
// `iOSMarkdownEditorFlush` is the held-back write behind `iOSMarkdownEditingSurface`'s 2.5 s
// debounce; a host flushes it before it commits. `iOSCalendarEventNoteReload` decides whether an
// EventKit store change may replace the event sheet's draft note. Both are iOS-only, so this suite
// runs on an iOS destination; the hosts' call sites are pinned in
// `iOSMarkdownEditorFlushWiringTests`, which runs on both legs.
#if os(iOS)

@Suite @MainActor
struct iOSMarkdownEditorFlushTests {
    /// What a host's binding received, in order.
    private final class Binding {
        var writes: [String] = []
        var value: String { writes.last ?? "" }
    }

    /// The host's commit: it reads the binding synchronously, the way `save()` reads `draft.notes`.
    private func commitAfterFlush(_ flush: iOSMarkdownEditorFlush, reading binding: Binding) -> String {
        flush.flush()
        return binding.value
    }

    @Test func aCommitMadeRightAfterTypingCarriesTheTypedText() {
        let flush = iOSMarkdownEditorFlush()
        let binding = Binding()
        flush.schedule(after: 60) { binding.writes.append("Buy milk and eggs") }
        #expect(binding.writes.isEmpty, "the write is held, as the debounce intends")
        #expect(flush.hasPendingEdit)

        #expect(commitAfterFlush(flush, reading: binding) == "Buy milk and eggs")
        #expect(binding.writes.count == 1)
        #expect(!flush.hasPendingEdit, "nothing is held once it has been written")
    }

    @Test func aFlushedWriteDoesNotRunAgainWhenItsTimerWouldHaveFired() async throws {
        let flush = iOSMarkdownEditorFlush()
        let binding = Binding()
        flush.schedule(after: 0.01) { binding.writes.append("typed") }
        flush.flush()
        try await Task.sleep(for: .milliseconds(200))
        #expect(binding.writes == ["typed"])
    }

    @Test func anUnflushedWriteStillLandsOnItsTimer() async throws {
        let flush = iOSMarkdownEditorFlush()
        let binding = Binding()
        flush.schedule(after: 0.01) { binding.writes.append("typed") }
        for _ in 0..<50 where binding.writes.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(binding.writes == ["typed"])
        #expect(!flush.hasPendingEdit)
    }

    @Test func onlyTheLatestHeldWriteRuns() {
        let flush = iOSMarkdownEditorFlush()
        let binding = Binding()
        flush.schedule(after: 60) { binding.writes.append("Buy") }
        flush.schedule(after: 60) { binding.writes.append("Buy milk") }
        flush.flush()
        #expect(binding.writes == ["Buy milk"])
    }

    @Test func aCancelledWriteNeverRunsAndAFlushWithNothingHeldWritesNothing() {
        let flush = iOSMarkdownEditorFlush()
        let binding = Binding()
        flush.flush()
        #expect(binding.writes.isEmpty)

        flush.schedule(after: 60) { binding.writes.append("typed") }
        flush.cancel()
        #expect(!flush.hasPendingEdit)
        flush.flush()
        #expect(binding.writes.isEmpty)
    }

    // MARK: - T-5171

    @Test func aStoreChangeDoesNotOverwriteAnEditedEventNote() {
        #expect(iOSCalendarEventNoteReload.reloadedNotes(
            draft: "Old note, and what I am typing",
            lastLoaded: "Old note",
            fresh: "Old note"
        ) == nil)
        #expect(iOSCalendarEventNoteReload.reloadedNotes(
            draft: "Old note, and what I am typing",
            lastLoaded: "Old note",
            fresh: "Mirrored from the event note"
        ) == nil)
    }

    @Test func aStoreChangeStillRefreshesAnUntouchedEventNote() {
        #expect(iOSCalendarEventNoteReload.reloadedNotes(
            draft: "Old note",
            lastLoaded: "Old note",
            fresh: "Mirrored from the event note"
        ) == "Mirrored from the event note")
    }
}

#endif
