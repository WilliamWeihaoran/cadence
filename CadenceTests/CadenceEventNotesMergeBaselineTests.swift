import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-8162]] and [[T-8163]] rules (2) and (3) — the event note's synced merge baseline.**
///
/// Both owner decisions of 2026-10-31 needed per-event metadata that syncs, and rode ONE additive
/// CloudKit schema change: three fields on `Note` (`eventNotesMergedAt`,
/// `eventNotesMergedNativeHash`, `eventNotesMergedContentHash`). The decision itself is
/// `CadenceEventNotesMerge.resolvedContent(noteContent:nativeNotes:baseline:…)`, a pure function,
/// so it is tested here as behaviour; the hosts that call it are source-scanned in
/// `CadenceEventNotesMergeTests`.
///
/// The invariant every test below keeps: **no resolution ever loses a word** — "newest wins" was
/// rejected by the owner because it can.
struct CadenceEventNotesMergeBaselineTests {

    private let mergedAt = Date(timeIntervalSince1970: 1_793_000_000)

    private func imageReference() -> String {
        "![A picture](cadence-image://\(UUID().uuidString))"
    }

    /// The baseline a host records the moment the note holds Apple's text.
    private func baseline(note: String, native: String) throws -> CadenceEventNotesMerge.MergeBaseline {
        try #require(
            CadenceEventNotesMerge.baselineToRecord(noteContent: note, nativeNotes: native, current: nil, now: mergedAt),
            "no baseline was recorded for a note that holds Apple's text"
        )
    }

    // MARK: - [[T-8162]]: a deleted Apple paragraph stays deleted

    /// **The ticket's reproduction.** A read-only event: the note took Apple's paragraph under a
    /// divider, the user deleted it, Apple Calendar cannot be written so it still holds the text.
    /// Containment alone re-appends it on the next open; the baseline does not.
    @Test func aDeletedAppleParagraphIsNotReappendedOnceTheNoteHasTakenIt() throws {
        let native = "Dial-in: 123"
        let taken = "# Standup\n\nAgenda\n\n---\n\nDial-in: 123"
        let recorded = try baseline(note: taken, native: native)
        let afterDeletion = "# Standup\n\nAgenda"

        // What it did before the baseline, kept visible so the fix is measured against the bug.
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: afterDeletion, nativeNotes: native) != nil)

        #expect(CadenceEventNotesMerge.resolvedContent(
            noteContent: afterDeletion,
            nativeNotes: native,
            baseline: recorded
        ) == nil)
        #expect(CadenceEventNotesMerge.displayText(
            noteContent: afterDeletion,
            nativeNotes: native,
            baseline: recorded
        ) == afterDeletion)
        // Trailing whitespace Apple adds or drops is not a new text.
        #expect(CadenceEventNotesMerge.resolvedContent(
            noteContent: afterDeletion,
            nativeNotes: "  Dial-in: 123\n",
            baseline: recorded
        ) == nil)
    }

    /// The deletion must not record a NEW baseline — the old one is the marker. A baseline may
    /// only be taken while the note holds Apple's text.
    @Test func aBaselineIsOnlyRecordedWhileTheNoteHoldsAppleText() throws {
        #expect(CadenceEventNotesMerge.baselineToRecord(
            noteContent: "Agenda",
            nativeNotes: "Dial-in: 123",
            current: nil,
            now: mergedAt
        ) == nil)
        // Equal, contained and empty all count as holding it.
        #expect(CadenceEventNotesMerge.baselineToRecord(noteContent: "Dial-in: 123", nativeNotes: "Dial-in: 123", current: nil, now: mergedAt) != nil)
        #expect(CadenceEventNotesMerge.baselineToRecord(noteContent: "Agenda\n\n---\n\nDial-in: 123", nativeNotes: "Dial-in: 123", current: nil, now: mergedAt) != nil)
        #expect(CadenceEventNotesMerge.baselineToRecord(noteContent: "Agenda", nativeNotes: nil, current: nil, now: mergedAt) != nil)

        // Recording the same baseline twice writes nothing the second time.
        let first = try baseline(note: "Agenda\n\n---\n\nDial-in: 123", native: "Dial-in: 123")
        #expect(CadenceEventNotesMerge.baselineToRecord(
            noteContent: "Agenda\n\n---\n\nDial-in: 123",
            nativeNotes: "Dial-in: 123",
            current: first,
            now: mergedAt.addingTimeInterval(60)
        ) == nil)
    }

    /// New Apple text after a dismissal is not the dismissed text, so it is offered — labelled,
    /// because the note changed too. A dismissal never swallows text Apple gains later.
    @Test func newAppleTextAfterADismissalIsStillOffered() throws {
        let recorded = try baseline(note: "Agenda\n\n---\n\nDial-in: 123", native: "Dial-in: 123")
        let resolved = try #require(CadenceEventNotesMerge.resolvedContent(
            noteContent: "Agenda",
            nativeNotes: "Dial-in: 456",
            baseline: recorded
        ))
        #expect(resolved.hasPrefix("Agenda"))
        #expect(resolved.hasSuffix("Dial-in: 456"))
    }

    /// The fingerprint syncs, so it has to be the same digest on every device and every launch —
    /// a published SHA-256 vector rather than a value this process happened to compute.
    @Test func theFingerprintIsAStableSHA256OfTheTrimmedText() {
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(CadenceEventNotesMerge.fingerprint("abc") == abc)
        #expect(CadenceEventNotesMerge.fingerprint("\n abc \n") == abc)
        #expect(CadenceEventNotesMerge.fingerprint("abd") != abc)
    }

    // MARK: - [[T-8163]] rule (2): only Apple changed -> refresh in place

    /// The writable steady state: after a mirror the note IS Apple's text, so Apple's edit
    /// replaces it whole, with no divider.
    @Test func anAppleOnlyEditReplacesANoteThatWasAppleText() throws {
        let recorded = try baseline(note: "Room 4B", native: "Room 4B")
        #expect(CadenceEventNotesMerge.resolvedContent(
            noteContent: "Room 4B",
            nativeNotes: "Room 5C",
            baseline: recorded
        ) == "Room 5C")
    }

    /// The read-only steady state: Apple's text is the block under the last divider, so only that
    /// block is replaced and the Cadence half above it is untouched.
    @Test func anAppleOnlyEditReplacesOnlyTheBlockUnderTheDivider() throws {
        let note = "# Standup\n\nAgenda\n\n---\n\nRoom 4B"
        let recorded = try baseline(note: note, native: "Room 4B")
        #expect(CadenceEventNotesMerge.resolvedContent(
            noteContent: note,
            nativeNotes: "Room 5C",
            baseline: recorded
        ) == "# Standup\n\nAgenda\n\n---\n\nRoom 5C")
    }

    /// A picture is never in Apple's copy, so replacing a note "whole" would drop it. The refresh
    /// declines and the lossless append takes over.
    @Test func anAppleOnlyEditNeverDropsAPicture() throws {
        let picture = imageReference()
        let note = "Room 4B\n\n\(picture)"
        let recorded = try baseline(note: note, native: CadenceEventNotesMerge.mirrorText(noteContent: note))
        let resolved = try #require(CadenceEventNotesMerge.resolvedContent(
            noteContent: note,
            nativeNotes: "Room 5C",
            baseline: recorded
        ))
        #expect(resolved.contains(picture), "the refresh dropped the note's picture")
        #expect(resolved.hasSuffix("Room 5C"))
    }

    // MARK: - [[T-8163]] rule (3): both changed -> keep the divider, label each side

    @Test func aTwoSidedEditKeepsBothHalvesAndLabelsWhichIsNewer() throws {
        let recorded = try baseline(note: "Agenda\n\n---\n\nRoom 4B", native: "Room 4B")
        let noteEditedAt = mergedAt.addingTimeInterval(60)
        let nativeEditedAt = mergedAt.addingTimeInterval(120)
        let resolved = try #require(CadenceEventNotesMerge.resolvedContent(
            noteContent: "Agenda, revised\n\n---\n\nRoom 4B",
            nativeNotes: "Room 5C",
            baseline: recorded,
            noteEditedAt: noteEditedAt,
            nativeEditedAt: nativeEditedAt,
            dateText: { $0 == noteEditedAt ? "T+60" : "T+120" }
        ))
        #expect(resolved == """
            Agenda, revised

            ---

            Room 4B

            *Above: Cadence note — older, edited T+60*

            ---

            *Below: Apple Calendar — newer, edited T+120*

            Room 5C
            """)
    }

    /// The labels follow the clocks, not the side: whichever edited later is "newer".
    @Test func theNewerLabelFollowsTheLaterEdit() {
        let early = mergedAt
        let late = mergedAt.addingTimeInterval(3600)
        let cadenceLater = CadenceEventNotesMerge.conflictLabels(noteEditedAt: late, nativeEditedAt: early, dateText: { _ in "t" })
        #expect(cadenceLater.cadence.contains("newer"))
        #expect(cadenceLater.apple.contains("older"))
        let appleLater = CadenceEventNotesMerge.conflictLabels(noteEditedAt: early, nativeEditedAt: late, dateText: { _ in "t" })
        #expect(appleLater.cadence.contains("older"))
        #expect(appleLater.apple.contains("newer"))
        // An unknown Apple time claims neither, rather than guessing.
        let unknown = CadenceEventNotesMerge.conflictLabels(noteEditedAt: late, nativeEditedAt: nil, dateText: { _ in "t" })
        #expect(!unknown.cadence.contains("newer") && !unknown.apple.contains("older"))
        #expect(unknown.apple == "*Below: Apple Calendar*")
    }

    /// **Never newest-wins**, stated as a relation over every rule: whichever path a pair takes,
    /// every word of the note and every word of Apple's new text survives.
    @Test func noResolutionEverLosesAWord() throws {
        let cases: [(taken: String, takenNative: String, note: String, native: String)] = [
            ("Agenda\n\n---\n\nRoom 4B", "Room 4B", "Agenda, revised\n\n---\n\nRoom 4B", "Room 5C"),
            ("Agenda\n\n---\n\nRoom 4B", "Room 4B", "Agenda", "Room 5C"),
            ("Room 4B", "Room 4B", "Room 4B and snacks", "Room 5C"),
            ("Agenda\n\n---\n\nRoom 4B", "Room 4B", "Agenda\n\n---\n\nRoom 4B", "Room 5C, moved")
        ]
        for item in cases {
            let recorded = try baseline(note: item.taken, native: item.takenNative)
            let resolved = try #require(CadenceEventNotesMerge.resolvedContent(
                noteContent: item.note,
                nativeNotes: item.native,
                baseline: recorded
            ))
            for word in item.native.split(whereSeparator: \.isWhitespace) {
                #expect(resolved.contains(word), "Apple's new text lost \(word) in \(item)")
            }
            // Rule (2) may replace Apple's OLD block, which is Apple's text, never the Cadence half.
            let cadenceHalf = item.note.components(separatedBy: "\n\n---\n\n")[0]
            for word in cadenceHalf.split(whereSeparator: \.isWhitespace) {
                #expect(resolved.contains(word), "the note lost \(word) in \(item)")
            }
        }
    }

    /// With no baseline — every note older than the fields — the decision is exactly rule (6)'s.
    @Test func withNoBaselineTheDecisionIsTheContainmentMerge() {
        for (note, native) in [("Agenda", "Room 4B"), ("Agenda\n\n---\n\nRoom 4B", "Room 4B"), ("", "Room 4B"), ("Agenda", "")] {
            #expect(
                CadenceEventNotesMerge.resolvedContent(noteContent: note, nativeNotes: native, baseline: nil)
                    == CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: native)
            )
        }
    }

    // MARK: - The Note fields

    /// `recordBaseline` writes the three synced fields, reads back as the same baseline, and leaves
    /// `updatedAt` alone — rule (3) prints `updatedAt` as the time the user last wrote.
    @MainActor @Test func recordingABaselineWritesTheSyncedFieldsAndNotUpdatedAt() throws {
        let edited = Date(timeIntervalSince1970: 1_792_000_000)
        let note = Note(kind: .meeting, content: "Agenda\n\n---\n\nDial-in: 123", updatedAt: edited)
        #expect(CadenceEventNotesMerge.baseline(of: note) == nil)

        #expect(CadenceEventNotesMerge.recordBaseline(note, nativeNotes: "Dial-in: 123", now: mergedAt))
        #expect(note.updatedAt == edited)
        #expect(note.eventNotesMergedAt == mergedAt)
        let read = try #require(CadenceEventNotesMerge.baseline(of: note))
        #expect(read.nativeFingerprint == CadenceEventNotesMerge.fingerprint("Dial-in: 123"))
        #expect(!CadenceEventNotesMerge.recordBaseline(note, nativeNotes: "Dial-in: 123"), "an unchanged baseline was written again")

        // The user deletes the paragraph: no new baseline, so the old one keeps it deleted.
        note.content = "Agenda"
        #expect(!CadenceEventNotesMerge.recordBaseline(note, nativeNotes: "Dial-in: 123"))
        #expect(CadenceEventNotesMerge.resolvedContent(note: note, nativeNotes: "Dial-in: 123", nativeEditedAt: nil) == nil)
    }

    /// **The schema half.** The fields persist through an on-disk store and come back on a fresh
    /// container — the same path a synced row takes into another device's store — and a second
    /// device holding only the persisted row keeps the paragraph deleted. Fixture under this test's
    /// own temp directory, CloudKit off.
    @MainActor @Test func theBaselineSurvivesAStoreRoundTripAndKeepsTheDeletionOnAnotherDevice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceEventNotesMergeBaselineTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(CadenceStoreSupport.storeFilename)
        let id = UUID()

        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(allowsSave: true, cloudKitDatabase: .none, storeURL: storeURL)
            let context = ModelContext(container)
            let note = Note(id: id, kind: .meeting, content: "Agenda\n\n---\n\nDial-in: 123", calendarEventID: "event-1")
            context.insert(note)
            #expect(CadenceEventNotesMerge.recordBaseline(note, nativeNotes: "Dial-in: 123", now: mergedAt))
            note.content = "Agenda"
            try context.save()
        }

        let reopened = try CadenceStoreSupport.makePrimaryContainer(allowsSave: true, cloudKitDatabase: .none, storeURL: storeURL)
        let notes = try ModelContext(reopened).fetch(FetchDescriptor<Note>())
        let note = try #require(notes.first { $0.id == id })
        #expect(note.eventNotesMergedAt == mergedAt)
        #expect(note.eventNotesMergedNativeHash == CadenceEventNotesMerge.fingerprint("Dial-in: 123"))
        #expect(!note.eventNotesMergedContentHash.isEmpty)
        #expect(CadenceEventNotesMerge.displayText(note: note, nativeNotes: "Dial-in: 123", nativeEditedAt: nil) == "Agenda")
    }

    // MARK: - The sync point after a mirror

    /// A mirror is where the two sides agree, so it is a baseline — but only once Apple Calendar
    /// has TAKEN it. Recorded before, a refused mirror would leave a baseline claiming Apple holds
    /// text it does not, and rule (2) would replace the user's note with Apple's older text.
    @Test func theSyncPointIsRecordedOnlyAfterTheMirrorLandsAndIsSaved() {
        var events: [String] = []
        let landed = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { events.append("save") },
            syncToNativeEvent: { events.append("mirror"); return true },
            recordSyncPoint: { events.append("baseline"); return true }
        )
        #expect(landed == .saved)
        #expect(events == ["save", "mirror", "baseline", "save"])

        events = []
        let refused = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { events.append("save") },
            syncToNativeEvent: { events.append("mirror"); return false },
            recordSyncPoint: { events.append("baseline"); return true }
        )
        #expect(refused == .savedButNotSynced)
        #expect(events == ["save", "mirror"], "a refused mirror recorded a baseline")

        events = []
        _ = CadenceEventNoteSupport.commitNote(
            syncToCalendar: false,
            save: { events.append("save") },
            syncToNativeEvent: { events.append("mirror"); return true },
            recordSyncPoint: { events.append("baseline"); return true }
        )
        #expect(events == ["save"])

        // Nothing recorded, nothing more to save.
        events = []
        _ = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { events.append("save") },
            syncToNativeEvent: { events.append("mirror"); return true },
            recordSyncPoint: { events.append("baseline"); return false }
        )
        #expect(events == ["save", "mirror", "baseline"])
    }

    /// Every commit path that mirrors an event note records the sync point, on both platforms
    /// ([[T-8201]]): the two shared helpers and the Mac's two Notes-page editors.
    @Test func everyMirroringCommitRecordsTheSyncPoint() throws {
        let sites: [(path: String, call: String)] = [
            ("Cadence/iOS/iOSEventNoteEditorSheet.swift", "recordSyncPoint(note, event: event, calendarManager: calendarManager)"),
            ("Cadence/macOS/Views/EventNoteSupportViews.swift", "EventNoteSupport.recordSyncPoint(note, event: nativeEvent, calendarManager: calendarManager)"),
            ("Cadence/macOS/Views/NotesView.swift", "EventNoteSupport.recordSyncPoint(note, event: nil, calendarManager: calendarManager)"),
            ("Cadence/macOS/Views/ListNotesView.swift", "EventNoteSupport.recordSyncPoint(note, event: nil, calendarManager: calendarManager)")
        ]
        for site in sites {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(site.path))
            #expect(code.contains("CadenceEventNoteSupport.commitNote("), "\(site.path) no longer commits through the helper")
            #expect(code.contains("recordSyncPoint: {"), "\(site.path) mirrors without recording the sync point")
            #expect(code.contains(site.call), "\(site.path) records the sync point some other way")
        }
        // Both platforms' recorders read Apple's text back from the event, and through the one writer.
        for path in ["Cadence/iOS/iOSEventNoteEditorSheet.swift", "Cadence/macOS/Views/EventNoteSupportViews.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let body = try #require(CadenceSourceScan.functionBody(named: "recordSyncPoint", in: code))
            #expect(body.contains("CadenceEventNotesMerge.recordBaseline(note, nativeNotes: target.notes)"))
        }
    }
}
