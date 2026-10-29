import Foundation
import Testing
@testable import Cadence

/// **[[T-8161]] — the event editor's one Notes field.**
///
/// The owner's ruling was that an event has a single Notes field, backed by the rich Cadence
/// `Note`, which mirrors a flattened plain-text copy into `EKEvent.notes`; images stay
/// Cadence-only. Four of the seven derived rules are decisions about text and live in
/// `CadenceEventNotesMerge`, so they are tested here as behaviour rather than as a source scan.
///
/// **Two of them can lose the owner's own data and are tested hardest:**
///
/// - **Rule (1), the anti-clobber gate.** The note is seeded from `EKEvent.notes` once and never
///   re-read, so a commit that mirrors unconditionally pushes a stale copy over an edit made in
///   Apple Calendar. `shouldMirror` is the gate; the four hosts that commit a note hold the
///   baseline.
/// - **Rule (6), the migration.** An event that already has a Cadence note *and* different text in
///   `EKEvent.notes` must keep both. Everything below that names "discard" is this rule.
///
/// The surfaces themselves are in `Cadence/iOS/` (invisible to this macOS-built target) and in a
/// SwiftUI view, so the last section is a source scan with its own non-vacuity anchors.
struct CadenceEventNotesMergeTests {

    private func scanned(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private func imageReference(_ id: UUID = UUID(), alt: String = "A picture") -> String {
        "![\(alt)](cadence-image://\(id.uuidString))"
    }

    // MARK: - Rule (1): mirror only when the Cadence note actually changed

    /// The gate itself. The baseline is the note as the editor opened it, so an untouched note
    /// never reaches Apple Calendar and a touched one always does.
    @Test func theMirrorFiresOnlyWhenTheNoteMovedAwayFromWhatWasLastMirrored() {
        #expect(CadenceEventNotesMerge.shouldMirror(content: "Agenda", lastMirrored: "Agenda") == false)
        #expect(CadenceEventNotesMerge.shouldMirror(content: "Agenda ", lastMirrored: "Agenda"))
        #expect(CadenceEventNotesMerge.shouldMirror(content: "Agenda\nRoom 4B", lastMirrored: "Agenda"))
        // The no-note case: the hosts open with `""`, so the first text a user types is a change.
        #expect(CadenceEventNotesMerge.shouldMirror(content: "First line", lastMirrored: ""))
        #expect(CadenceEventNotesMerge.shouldMirror(content: "", lastMirrored: "") == false)
    }

    /// **The clobber this rule exists to stop, stated as the scenario rather than as the call.**
    ///
    /// The note was written weeks ago and mirrored; someone then edited the event in Apple
    /// Calendar. Opening the Cadence editor and closing it — Done commits — must not write the
    /// note's text over that edit. Only a note the user has actually touched may.
    @Test func anEditMadeInAppleCalendarSurvivesAnUntouchedCadenceNote() {
        let asOpened = "# Standup\n\nAgenda: roadmap"
        let editedInAppleCalendar = "Moved to room 4B"

        // Done on an untouched note: no mirror, so Apple Calendar keeps its own words.
        #expect(CadenceEventNotesMerge.shouldMirror(content: asOpened, lastMirrored: asOpened) == false)

        // And the field still shows the Apple edit rather than hiding it — rule (6) folds it in.
        let shown = CadenceEventNotesMerge.displayText(
            noteContent: asOpened,
            nativeNotes: editedInAppleCalendar
        )
        #expect(shown.contains(editedInAppleCalendar), "the Apple Calendar edit is not on screen")
        #expect(shown.contains("Agenda: roadmap"), "the Cadence note was replaced rather than merged")

        // Touching the merged text is what releases the mirror, and what it would then send
        // carries both halves.
        let touched = shown + "\n\nBring the deck"
        #expect(CadenceEventNotesMerge.shouldMirror(content: touched, lastMirrored: asOpened))
        let mirrored = CadenceEventNotesMerge.mirrorText(noteContent: touched)
        #expect(mirrored.contains(editedInAppleCalendar))
        #expect(mirrored.contains("Agenda: roadmap"))
    }

    // MARK: - Rule (2): the flattened copy is the source minus image references

    @Test func theFlattenedCopyDropsImageReferencesAndNothingElse() {
        let reference = imageReference()
        let markdown = "# Standup\n\n\(reference)\n\nAgenda: see [[Roadmap]] and [[task:Ship it]]."
        let flattened = CadenceEventNotesMerge.flattenedForCalendar(markdown)

        #expect(!flattened.contains("cadence-image://"), "an image reference reached Apple Calendar")
        #expect(flattened.contains("[[Roadmap]]"), "a note link was rewritten")
        #expect(flattened.contains("[[task:Ship it]]"), "a task link was rewritten")
        #expect(flattened.contains("# Standup"), "the markdown was not kept as written")
        // The line that held nothing but the picture goes with it; the blank lines the user typed
        // around it stay, which is what "as written" means.
        #expect(flattened == "# Standup\n\n\nAgenda: see [[Roadmap]] and [[task:Ship it]].")
    }

    /// An image struck out of the middle of a sentence leaves the sentence, because the line held
    /// more than the picture.
    @Test func anInlineImageLeavesItsSentenceBehind() {
        let markdown = "Before \(imageReference(alt: "chart")) after."
        #expect(CadenceEventNotesMerge.flattenedForCalendar(markdown) == "Before  after.")
    }

    /// Text with no picture in it is handed over byte-identical — the mirror is not a formatter.
    @Test func textWithoutAPictureIsMirroredUnchanged() {
        let markdown = "# Standup\n\n- one\n- two\n\n\n  trailing spaces   \n"
        #expect(CadenceEventNotesMerge.flattenedForCalendar(markdown) == markdown)
        #expect(CadenceEventNotesMerge.mirrorText(noteContent: markdown) == markdown)
    }

    // MARK: - Rule (4): an event with no Cadence note shows the Apple Calendar text

    @Test func anEventWithNoCadenceNoteShowsItsAppleCalendarText() {
        #expect(CadenceEventNotesMerge.displayText(noteContent: nil, nativeNotes: "Dial-in: 123") == "Dial-in: 123")
        #expect(CadenceEventNotesMerge.displayText(noteContent: nil, nativeNotes: nil).isEmpty)
        // And the seed the first edit uses is the same text, which is the behaviour this rule
        // keeps rather than introduces.
        #expect(
            CadenceEventNoteSupport.initialContent(eventTitle: "Standup", nativeNotes: "Dial-in: 123")
                == "Dial-in: 123"
        )
    }

    // MARK: - Rule (6): the migration appends, and never discards

    /// **The data-loss case.** A note and a different `EKEvent.notes` both exist; the Apple text is
    /// appended under a divider, and every word of both halves survives.
    @Test func bothHalvesSurviveWhenACadenceNoteMeetsDifferentAppleCalendarText() throws {
        let note = "# Standup\n\nAgenda: roadmap"
        let native = "Moved to room 4B"
        let merged = try #require(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: native))

        #expect(merged.hasPrefix(note), "the Cadence note was rewritten rather than kept")
        #expect(merged.hasSuffix(native), "the Apple Calendar text was not appended")
        #expect(merged == "# Standup\n\nAgenda: roadmap\n\n---\n\nMoved to room 4B")
        #expect(merged.contains("\n\(CadenceEventNotesMerge.divider)\n"), "there is no divider between them")
    }

    /// The three ways the two sides already agree, each of which must NOT append — otherwise the
    /// note grows a copy of itself every time the editor opens.
    @Test func nothingIsAppendedWhenTheTwoSidesAlreadyAgree() {
        let note = "# Standup\n\nAgenda: roadmap"
        // Apple holds nothing.
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: nil) == nil)
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: "   \n ") == nil)
        // Apple holds exactly the mirror.
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: note) == nil)
        // Apple's text is already inside the note — the steady state after one mirror, and the
        // guard that makes a second open a no-op.
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: "Agenda: roadmap") == nil)
    }

    /// **Idempotence, which is what makes a display-time merge safe.** Merging twice is merging
    /// once: the appended text is now inside the note, so the second pass finds nothing to do.
    @Test func mergingTwiceAppendsOnce() throws {
        let note = "Agenda: roadmap"
        let native = "Moved to room 4B"
        let once = try #require(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: native))
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: once, nativeNotes: native) == nil)
        #expect(CadenceEventNotesMerge.displayText(noteContent: once, nativeNotes: native) == once)
        // One divider, not two.
        #expect(once.components(separatedBy: "\n\(CadenceEventNotesMerge.divider)\n").count == 2)
    }

    /// A note carrying a picture is compared against its **flattened** self, because that is what
    /// Apple Calendar was given. Comparing the raw note would find a difference every time and
    /// migrate the same paragraph on every open.
    @Test func aNoteCarryingAPictureDoesNotMigrateAgainstItsOwnMirror() {
        let note = "Agenda: roadmap\n\n\(imageReference())\n"
        let mirrored = CadenceEventNotesMerge.mirrorText(noteContent: note)
        #expect(mirrored.contains("Agenda: roadmap"))
        #expect(!mirrored.contains("cadence-image://"))
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: mirrored) == nil)
        #expect(CadenceEventNotesMerge.displayText(noteContent: note, nativeNotes: mirrored) == note)
    }

    /// An empty note takes the Apple text whole. A divider over the only paragraph in the field
    /// reads as damage, and there is nothing above it to divide from.
    @Test func anEmptyNoteAdoptsTheAppleCalendarTextWithoutADivider() {
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: "", nativeNotes: "Dial-in: 123") == "Dial-in: 123")
        #expect(CadenceEventNotesMerge.mergedContent(noteContent: "  \n\n ", nativeNotes: "Dial-in: 123") == "Dial-in: 123")
        #expect(CadenceEventNotesMerge.displayText(noteContent: "", nativeNotes: "Dial-in: 123") == "Dial-in: 123")
    }

    /// The merge never deletes. Stated as a relation over a handful of pairs rather than as one
    /// example, because "appended, never discarded" is the whole of rule (6).
    @Test func noPairOfSourcesEverLosesAWord() throws {
        let pairs: [(String, String)] = [
            ("Agenda", "Room 4B"),
            ("# Standup\n\nAgenda", "Dial-in: 123\nPasscode: 9"),
            ("Agenda\n\n", "Room 4B"),
            ("Agenda: roadmap\n\(imageReference())", "Room 4B")
        ]
        for (note, native) in pairs {
            let merged = try #require(
                CadenceEventNotesMerge.mergedContent(noteContent: note, nativeNotes: native),
                "\(note) + \(native) merged to nothing"
            )
            for word in note.split(whereSeparator: \.isWhitespace) {
                #expect(merged.contains(word), "the Cadence note lost \(word)")
            }
            for word in native.split(whereSeparator: \.isWhitespace) {
                #expect(merged.contains(word), "the Apple Calendar text lost \(word)")
            }
        }
    }

    /// **The fixture that makes rules (4) and (6) visible on screen.**
    ///
    /// An agent may not open a real `EKEventStore`, so the only way to *look at* an event whose
    /// Apple Calendar text came from outside Cadence is `CadenceCalendarFixtureEvents` — which is
    /// why that text is a fixture field rather than something the check types by hand. Pinned here
    /// so the scenario cannot quietly lose the one property the screen check depends on.
    @MainActor @Test func theCascadeFixtureCarriesAppleCalendarTextToLookAt() throws {
        let lunch = try #require(
            CadenceCalendarFixtureEvents.CascadeFixture.timed.first { $0.title == "Lunch with Sam" }
        )
        let native = try #require(lunch.nativeNotes)
        #expect(native == CadenceCalendarFixtureEvents.CascadeFixture.lunchNativeNotes)
        #expect(!native.isEmpty, "the fixture event has no Apple Calendar text to show")

        // With no Cadence note the field shows exactly that text (rule 4)…
        #expect(CadenceEventNotesMerge.displayText(noteContent: nil, nativeNotes: native) == native)
        // …and beside a note that says something else, both halves are on screen (rule 6).
        #expect(
            CadenceEventNotesMerge.displayText(noteContent: "Agenda: Q4 plan", nativeNotes: native)
                == "Agenda: Q4 plan\n\n---\n\nMoved to the room on the fourth floor."
        )
    }

    /// `isEdit` is what stops a repaint from minting a `Note` — and what stops the *shown* merge
    /// from being mistaken for one.
    @Test func onlyTextThatDiffersFromItsOwnSubjectCountsAsAnEdit() {
        // With a note, the subject is the note, not what the field is showing: the field may be
        // showing the merge while the note holds only its half.
        let note = "Agenda"
        let shown = CadenceEventNotesMerge.displayText(noteContent: note, nativeNotes: "Room 4B")
        #expect(shown != note)
        #expect(CadenceEventNotesMerge.isEdit(note, noteContent: note, nativeNotes: "Room 4B") == false)
        #expect(CadenceEventNotesMerge.isEdit(shown, noteContent: note, nativeNotes: "Room 4B"))

        // With no note, the subject is the Apple Calendar text the field is showing.
        #expect(CadenceEventNotesMerge.isEdit("Room 4B", noteContent: nil, nativeNotes: "Room 4B") == false)
        #expect(CadenceEventNotesMerge.isEdit("Room 4B!", noteContent: nil, nativeNotes: "Room 4B"))
        #expect(CadenceEventNotesMerge.isEdit("", noteContent: nil, nativeNotes: nil) == false)
    }

    /// **Rule (6) where it is persisted.** Showing the merge is not the same as storing it: the
    /// full note editor does not merge, so a note handed to it without the Apple half would push
    /// the Cadence half over Apple's text on its next commit. Both hosts write the merge into the
    /// note at the moment it is first needed — a keystroke, or Open — and before any mirror.
    @Test func bothHostsPersistTheMigrationBeforeHandingTheNoteToAnEditor() throws {
        for (path, native) in [
            ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "event.notes"),
            ("Cadence/macOS/Views/TimelineEventBlockSupportViews.swift", "item.ekEvent.notes")
        ] {
            let code = try scanned(path)
            let ensure = try #require(CadenceSourceScan.functionBody(named: "ensureEventNote", in: code))
            #expect(
                ensure.contains("if let merged = CadenceEventNotesMerge.mergedContent(noteContent: note.content, nativeNotes: \(native))"),
                "\(path) hands over a note that may be missing its Apple Calendar half"
            )
            #expect(ensure.contains("CadenceCoreNoteSupport.applyContent(note, content: merged, in: modelContext)"))
            // Before the commit, so one save carries it.
            let mergeIndex = try #require(ensure.range(of: "applyContent(note, content: merged"))
            let commitIndex = try #require(ensure.range(of: "CadencePendingChangePersistence.commitInsert"))
            #expect(mergeIndex.lowerBound < commitIndex.lowerBound, "\(path) commits before it merges")
        }
    }

    // MARK: - The surfaces

    /// Both event editors draw **one** Notes field and neither of the two surfaces it replaced.
    ///
    /// The counts are the claim: a file that draws the shared field twice, or draws it and keeps
    /// the old card, fails here. `CadenceEventNotesField` is the shared chrome, so the label and
    /// the read-only sentence cannot differ between the platforms (`AGENTS.md`, "macOS and iOS are
    /// one app").
    @Test func bothPlatformsDrawTheOneSharedNotesField() throws {
        for (path, marker) in [
            ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "struct iOSCalendarEventEditSheet: View"),
            ("Cadence/macOS/Views/TimelineEventBlockSupportViews.swift", "struct CalendarEventEditPopover: View")
        ] {
            let code = try scanned(path)
            #expect(code.contains(marker), "\(path) did not read as itself")
            #expect(
                CadenceSourceScan.matchCount(#"CadenceEventNotesField\("#, in: code) == 1,
                "\(path) does not draw exactly one merged Notes field"
            )
            #expect(code.contains("CadenceEventNotesMerge.displayText("), "\(path) does not read rules 4 and 6")
            #expect(code.contains("CadenceEventNotesMerge.shouldMirror("), "\(path) does not gate the mirror")
            #expect(!code.contains("Apple Calendar note"), "\(path) still draws a second notes surface")
        }

        // The retired surfaces, each named: the iOS Create/Open card and the Mac's notes row.
        let sheet = try scanned("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        #expect(!sheet.contains("eventNoteSection"))
        #expect(!sheet.contains("No linked note yet"))
        let popover = try scanned("Cadence/macOS/Views/TimelineEventBlockSupportViews.swift")
        #expect(!popover.contains("linkedNoteCard"))
        #expect(!popover.contains("CadenceSchedulePanelNotesRow("))
    }

    /// **Rule (1) at the three hosts that can write Apple Calendar on iOS**, which is where the
    /// gate is actually applied — `shouldMirror` is a pure function and would happily be ignored.
    ///
    /// The third is the one that was easiest to miss: the event sheet's **Save** writes
    /// `EKEvent.notes` through `updateEvent`, not through the note commit at all, and it used to
    /// write back the notes the sheet opened with.
    @Test func everyCommitPathOnTheEventSheetAsksTheGateBeforeMirroring() throws {
        let sheet = try scanned("Cadence/iOS/iOSCalendarEventEditSheet.swift")

        let commit = try #require(CadenceSourceScan.functionBody(named: "commitNotes", in: sheet))
        #expect(commit.contains("CadenceEventNotesMerge.shouldMirror(content: note.content, lastMirrored: mirroredNoteContent ?? \"\")"))
        #expect(commit.contains("syncToCalendar: mirrors"), "the gate is computed and then ignored")
        #expect(commit.contains("if outcome == .saved {"), "a refused mirror is recorded as done")

        let saved = try #require(CadenceSourceScan.declarationBody("private var savedEventNotes: String", in: sheet))
        #expect(saved.contains("CadenceEventNotesMerge.shouldMirror("), "Save mirrors whatever it opened with")
        #expect(saved.contains("else { return event.notes ?? \"\" }"), "Save does not leave an untouched event alone")
        #expect(sheet.contains("notes: savedEventNotes,"), "Save writes something other than the gated text")

        // And the note sheet, which commits on Done and on a swipe-dismiss whether or not anything
        // was typed — the two commits that carry no change by construction.
        let noteSheet = try scanned("Cadence/iOS/iOSEventNoteEditorSheet.swift")
        let persist = try #require(CadenceSourceScan.functionBody(named: "persistNote", in: noteSheet))
        #expect(persist.contains("CadenceEventNotesMerge.shouldMirror("))
        #expect(persist.contains("syncToCalendar: mirrors"))
    }

    /// **Rule (3): [[T-422]]'s image ban is retired, not extended.** The merged field writes a
    /// `Note` row, which is exactly what `CadenceMarkdownSourceInventory` reads, so the asset a
    /// picture mints is visible to the sweep and the door that protected it can open.
    @Test func theMergedFieldAcceptsImagesBecauseItIsARowTheSweepCanSee() throws {
        let sheet = try scanned("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        #expect(sheet.contains("iOSMarkdownEditingSurface("), "the sheet presents no editor; this scan measures nothing")
        #expect(!sheet.contains("allowsImageInsertion"), "the merged field still refuses images")
        // The premise the retirement rests on, asserted rather than assumed.
        #expect(CadenceMarkdownSourceInventory.Source.noteContent.propertyName == "content")
        #expect(
            CadenceMarkdownSourceInventory.Source.allCases.map(\.entityName).contains("Note"),
            "the inventory no longer reads the note body the merged field writes"
        )
    }

    /// **Rule (5): the mirror is skipped on a read-only calendar, and the field says so quietly.**
    /// Skipped rather than attempted-and-reported, because a refusal the user cannot act on is not
    /// a failure — their note is saved either way.
    @Test func aReadOnlyCalendarSkipsTheMirrorRatherThanFailingIt() throws {
        for path in [
            "Cadence/iOS/iOSEventNoteEditorSheet.swift",
            "Cadence/macOS/Views/EventNoteSupportViews.swift"
        ] {
            let code = try scanned(path)
            #expect(code.contains("updateEventNotes("), "\(path) writes no mirror; this scan measures nothing")
            #expect(
                code.contains("guard CadenceEventNoteSupport.canMirrorNotes("),
                "\(path) still offers a read-only calendar a write it must refuse"
            )
        }
        // And the field's own sentence is one string, so both platforms say the same thing.
        #expect(CadenceEventNotesMerge.readOnlyNotice.contains("read-only"))
        #expect(CadenceEventNotesMerge.readOnlyNotice.contains("Cadence"))
    }

    /// **Rule (7): the mirror stays per-occurrence.** Both platforms' note writes save
    /// `.thisEvent`, which is what the note's own `#occurrence=` key already scopes it to.
    @Test func theMirrorIsSavedForThisOccurrenceOnBothPlatforms() throws {
        let mac = try scanned("Cadence/macOS/Services/CalendarManager.swift")
        let ios = try scanned("Cadence/iOS/iOSCalendarManager.swift")
        let macWrite = try #require(CadenceSourceScan.functionBody(named: "updateEventNotes", in: mac))
        let iosWrite = try #require(CadenceSourceScan.functionBody(named: "updateEventNotes", in: ios))
        #expect(macWrite.contains("span: .thisEvent"))
        #expect(iosWrite.contains("span: .thisEvent"))
    }

    /// **Rule (2), as a relation over every mirror in the app.** Four commit paths write
    /// `EKEvent.notes` from a note; each must hand `updateEventNotes` a flattened copy, not raw
    /// content. A fifth path added without the call fails here.
    @Test func everyMirrorWritesTheFlattenedCopy() throws {
        let appRoot = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence").path
        let swiftFiles = try FileManager.default.subpathsOfDirectory(atPath: appRoot)
            .filter { $0.hasSuffix(".swift") }
            .map { "Cadence/" + $0 }
            .sorted()
        #expect(swiftFiles.count > 100, "walked \(swiftFiles.count) files; that is not the app source tree")

        // The two managers declare the write and are where `notes:` is a parameter rather than an
        // argument, so they are the definition sites rather than hosts.
        let definitionSites = [
            "Cadence/iOS/iOSCalendarManager.swift",
            "Cadence/macOS/Services/CalendarManager.swift"
        ]
        var callers: [String] = []
        for path in swiftFiles where !definitionSites.contains(path) {
            let code = try scanned(path)
            guard code.contains("updateEventNotes(") else { continue }
            callers.append(path)
            #expect(
                code.contains("CadenceEventNotesMerge.mirrorText(noteContent:"),
                "\(path) mirrors raw note content into Apple Calendar"
            )
        }
        #expect(
            callers == [
                "Cadence/iOS/iOSEventNoteEditorSheet.swift",
                "Cadence/macOS/Views/EventNoteSupportViews.swift"
            ],
            "the set of mirror call sites changed: \(callers)"
        )
    }

    /// The scan above reads files this target does not compile, so a reader that silently answers
    /// an empty string would satisfy every `!contains` in this suite.
    @Test func theSourceScanReadsRealFilesAndStripsThem() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEventNotesMerge.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(raw.count > 2000, "read \(raw.count) characters; the file is not that short")
        #expect(stripped != raw, "the comment stripper did not run")
        #expect(stripped.count == raw.count, "the stripper changed the length; offsets no longer point where they did")
        #expect(stripped.contains("static func shouldMirror(content: String, lastMirrored: String) -> Bool"))
    }
}
