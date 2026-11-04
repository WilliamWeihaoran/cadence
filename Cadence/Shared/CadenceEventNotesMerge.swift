import CryptoKit
import Foundation

/// **[[T-8161]] — the event editor has ONE Notes field, and this is what it is made of.**
///
/// The owner's ruling: "Keep the rich Cadence note as the single Notes field — it mirrors a
/// flattened copy to Apple Calendar, and images stay Cadence-only." Before it, an event had two
/// notes surfaces that could hold different text and never agreed: the Cadence `Note`
/// (`kind == .meeting`), reached through a Create/Open card, and a plain markdown well bound
/// straight to `EKEvent.notes`.
///
/// Four of the ticket's seven rules are decisions about *text*, so they live here as pure
/// functions rather than inside two view bodies that would drift:
///
/// - **(1) `shouldMirror`** — Apple Calendar is written only when the Cadence note actually
///   changed. The note is seeded from `EKEvent.notes` once, at creation, and never re-read
///   ([[T-8161]] leaves the read-back out deliberately), so an unconditional mirror on every
///   commit pushes a stale copy over an edit made in Apple Calendar. The gate is what stops that:
///   the baseline is the note as the editor opened it, advanced only when a mirror lands.
/// - **(2) `flattenedForCalendar`** — the markdown source **as written, minus image references**.
///   `[[note]]` and `[[task:…]]` spans stay literal text: they read acceptably in Apple Calendar
///   and come back unharmed. Only `![alt](cadence-image://…)` is dropped, because the bytes it
///   names live in this store and nothing outside it can resolve them.
/// - **(4) `displayText` with no note** — an event that has no Cadence note but does have
///   `EKEvent.notes` shows that text, and the first edit seeds the `Note` from it. That was
///   already true through `CadenceEventNoteSupport.initialContent(eventTitle:nativeNotes:)`; the
///   merged field is where the user now sees it.
/// - **(6) `mergedContent`** — the migration, and the one place this change could lose the
///   owner's own data. An event that already has a Cadence note **and** different text in
///   `EKEvent.notes` must keep both: the Apple text is appended under a divider, never discarded.
///
/// **Why the merge is a display rule rather than a write performed on open.** Appending at open
/// would have to be exactly once, and nothing on `Note` records that it happened — so on a
/// read-only calendar, where the mirror can never converge the two sides, every open would append
/// again and the note would grow without bound. Merging into what the field *shows* is idempotent
/// by construction (it is recomputed from the two sources each time), loses nothing, and persists
/// the moment the user edits: the text they edit already contains the Apple half, so the note they
/// save holds it too. On a writable calendar the first edit then mirrors the merged text back and
/// the two sides agree from then on, which is why the containment guard below settles.
nonisolated enum CadenceEventNotesMerge {
    /// The field's label on both platforms. One name, so neither surface can call it something else.
    static let fieldTitle = "Notes"

    /// The markdown rule between the Cadence half and the appended Apple Calendar half.
    static let divider = "---"

    /// Rule (5)'s quiet half. The note itself stays editable on a read-only calendar — it is our
    /// own data — so this says where the writing goes rather than refusing it. The panel's own
    /// `CadenceCalendarEventEditingSupport.readOnlyNotice` already says the *event* cannot be
    /// edited; this says the narrower thing about this one field.
    static let readOnlyNotice = "This calendar is read-only, so these notes stay in Cadence."

    /// Rule (1). `lastMirrored` is the note's content as the editor opened it, advanced only when
    /// Apple Calendar has accepted a copy — so a failed mirror is retried and an untouched note is
    /// never pushed over an edit made on the other side.
    static func shouldMirror(content: String, lastMirrored: String) -> Bool {
        content != lastMirrored
    }

    /// Rule (2). The copy Apple Calendar is given: the markdown source as written, with every
    /// image reference removed, and a line that held nothing but images removed with them.
    ///
    /// Line by line rather than over the whole string, so a reference struck out of a sentence
    /// leaves the sentence alone and a reference on its own line does not leave a blank one behind.
    /// Nothing else is reflowed — a blank line the user typed is a blank line in Apple Calendar.
    static func flattenedForCalendar(_ markdown: String) -> String {
        guard markdown.contains("](\(MarkdownImageAssetService.urlScheme)://") else { return markdown }
        var lines: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let stripped = removingImageReferences(from: line)
            if stripped == line {
                lines.append(line)
            } else if !stripped.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(stripped)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Rule (6). The note's content with the Apple Calendar text appended under a divider, or
    /// `nil` when there is nothing to append.
    ///
    /// `nil` covers the three ways the two sides are already in agreement: Apple holds nothing,
    /// Apple holds exactly the flattened note, or Apple's text is already somewhere inside the
    /// flattened note (which is what the steady state looks like after one mirror, and what stops
    /// a second open from appending the same paragraph twice).
    ///
    /// The comparison is against the **flattened** note, not the raw one: the mirror strips images,
    /// so a note carrying a picture never equals its own copy in Apple Calendar and would otherwise
    /// migrate on every open.
    ///
    /// An empty note takes the Apple text whole rather than under a divider — there is nothing to
    /// divide it from, and a note that opens with a rule above its only paragraph reads as damage.
    static func mergedContent(noteContent: String, nativeNotes: String?) -> String? {
        let native = (nativeNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !native.isEmpty else { return nil }
        let flattened = flattenedForCalendar(noteContent)
        let trimmedFlattened = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFlattened.isEmpty else { return native }
        guard trimmedFlattened != native else { return nil }
        guard !flattened.contains(native) else { return nil }
        let base = noteContent.replacingOccurrences(
            of: #"\s+$"#,
            with: "",
            options: .regularExpression
        )
        return "\(base)\n\n\(divider)\n\n\(native)"
    }

    /// What the one Notes field shows: the Apple Calendar text alone when no Cadence note exists
    /// yet (rule 4), and otherwise the note — merged with any Apple text it does not already carry
    /// (rule 6).
    static func displayText(noteContent: String?, nativeNotes: String?) -> String {
        guard let noteContent else { return nativeNotes ?? "" }
        return mergedContent(noteContent: noteContent, nativeNotes: nativeNotes) ?? noteContent
    }

    /// Whether what the field now holds is an **edit** — the question both hosts ask before
    /// creating a `Note` out of a keystroke.
    ///
    /// Two different comparisons, and the difference is the whole point. With a note, the subject
    /// is the note's own content: the field may be *showing* the merged text (rule 6) while the
    /// note still holds only its half, and writing the merge back on nothing but a repaint would
    /// be a commit the user never asked for. Without a note, the subject is what the field is
    /// showing — the event's own `EKEvent.notes` — because that is the text the first keystroke
    /// seeds the new note from, and typing nothing must mint nothing.
    static func isEdit(_ content: String, noteContent: String?, nativeNotes: String?) -> Bool {
        if let noteContent { return content != noteContent }
        return content != displayText(noteContent: nil, nativeNotes: nativeNotes)
    }

    /// **[[T-8163]] rule (1): an untouched field refreshes IN PLACE when Apple Calendar changes.**
    /// Asked on every `EKEventStoreChanged` while an event editor is open. `shown` is what the
    /// field holds now, `lastLoaded` what it held when the editor last read the two sources, and
    /// `fresh` the same read made again. `nil` keeps the field: it differs from what was loaded, so
    /// it carries the user's typing and a refresh would throw that away.
    ///
    /// One function for both platforms ([[T-8201]]): iOS made this decision in
    /// `iOSCalendarEventNoteReload` ([[T-5171]]) and the Mac made none, so an Apple Calendar edit
    /// reached an open iOS sheet and never an open Mac popover.
    ///
    /// Rules (2) and (3) -- only Apple changed since the LAST MERGE, and both changed -- are not
    /// this function: they are `resolvedContent(noteContent:nativeNotes:baseline:…)`, which reads
    /// the note's synced merge baseline.
    static func refreshedText(shown: String, lastLoaded: String, fresh: String) -> String? {
        guard shown == lastLoaded else { return nil }
        return fresh
    }

    // MARK: - [[T-8162]] / [[T-8163]] rules (2) and (3): the synced merge baseline

    /// The moment a note last held Apple Calendar's text, as `Note` stores it
    /// (`eventNotesMergedAt`, `eventNotesMergedNativeHash`, `eventNotesMergedContentHash`). A value
    /// so the decision below stays a pure function both platforms and the tests call alike.
    struct MergeBaseline: Equatable, Sendable {
        var mergedAt: Date
        /// `fingerprint` of Apple's text at `mergedAt` — [[T-8162]]'s dismissal marker.
        var nativeFingerprint: String
        /// `fingerprint` of the note's flattened content at `mergedAt`.
        var contentFingerprint: String
    }

    /// A stable digest of text with its outer whitespace trimmed. SHA-256 rather than `hashValue`,
    /// which Swift seeds per process: the baseline syncs, so a Mac and an iPhone must compute the
    /// same digest for the same words.
    static func fingerprint(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(data: Data(trimmed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// **The one merge decision, with the baseline.** What the note should hold now, or `nil` when
    /// it already holds the right thing. With no baseline (every note older than the fields) it is
    /// exactly rule (6)'s `mergedContent`.
    ///
    /// - **[[T-8162]] — dismissal.** Apple's text still hashes to what the note last took: nothing
    ///   new arrived from Apple, so whatever the note holds stands — including a note whose user
    ///   deleted the appended paragraph. On a read-only calendar that deletion can never mirror,
    ///   and before the baseline the containment test re-appended it on every open, on every device.
    /// - **[[T-8163]] rule (2) — only Apple changed.** The note's own text is what it was at the
    ///   baseline, so Apple's new text replaces Apple's old text IN PLACE: the whole note when the
    ///   note *was* Apple's text, or the block under the last divider when that block was. When the
    ///   old text cannot be located (a picture in the note, a labelled block) it falls back to
    ///   appending under a divider — never to replacing a block it cannot prove was Apple's.
    /// - **[[T-8163]] rule (3) — both changed.** A real conflict: KEEP the divider and LABEL each
    ///   side with which is newer and when. "Newest wins" was considered and REJECTED by the owner
    ///   on 2026-10-31: it can silently discard text the user typed.
    ///
    /// `noteEditedAt` is `Note.updatedAt` and `nativeEditedAt` is `EKEvent.lastModifiedDate`; they
    /// only label rule (3), and either may be unknown.
    static func resolvedContent(
        noteContent: String,
        nativeNotes: String?,
        baseline: MergeBaseline?,
        noteEditedAt: Date? = nil,
        nativeEditedAt: Date? = nil,
        dateText: (Date) -> String = conflictDateText
    ) -> String? {
        let native = (nativeNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !native.isEmpty else { return nil }
        guard let baseline else {
            return mergedContent(noteContent: noteContent, nativeNotes: nativeNotes)
        }
        // [[T-8162]]: the note has taken this exact text once already.
        guard fingerprint(native) != baseline.nativeFingerprint else { return nil }

        let flattened = flattenedForCalendar(noteContent)
        let trimmedFlattened = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFlattened.isEmpty else { return native }
        guard trimmedFlattened != native, !flattened.contains(native) else { return nil }

        if fingerprint(flattened) == baseline.contentFingerprint {
            // Rule (2): only Apple moved.
            return refreshedInPlace(noteContent: noteContent, native: native, baseline: baseline)
                ?? appended(native, to: noteContent)
        }
        // Rule (3): both moved.
        return labelledConflict(
            noteContent: noteContent,
            native: native,
            noteEditedAt: noteEditedAt,
            nativeEditedAt: nativeEditedAt,
            dateText: dateText
        )
    }

    /// `displayText` with the baseline: the Apple text alone with no note (rule 4), and otherwise
    /// the note resolved against Apple's current text.
    static func displayText(
        noteContent: String?,
        nativeNotes: String?,
        baseline: MergeBaseline?,
        noteEditedAt: Date? = nil,
        nativeEditedAt: Date? = nil
    ) -> String {
        guard let noteContent else { return nativeNotes ?? "" }
        return resolvedContent(
            noteContent: noteContent,
            nativeNotes: nativeNotes,
            baseline: baseline,
            noteEditedAt: noteEditedAt,
            nativeEditedAt: nativeEditedAt
        ) ?? noteContent
    }

    /// The baseline to record now, or `nil` when none may be recorded or the stored one is already
    /// right. **A baseline may only be taken while the note holds Apple's text** (empty, equal, or
    /// contained): that is what it asserts. So a note whose user deleted the appended paragraph
    /// keeps its OLD baseline — which is precisely what makes the deletion stick ([[T-8162]]).
    static func baselineToRecord(
        noteContent: String,
        nativeNotes: String?,
        current: MergeBaseline?,
        now: Date
    ) -> MergeBaseline? {
        guard mergedContent(noteContent: noteContent, nativeNotes: nativeNotes) == nil else { return nil }
        let nativeFingerprint = fingerprint(nativeNotes ?? "")
        let contentFingerprint = fingerprint(flattenedForCalendar(noteContent))
        if let current,
           current.nativeFingerprint == nativeFingerprint,
           current.contentFingerprint == contentFingerprint {
            return nil
        }
        return MergeBaseline(mergedAt: now, nativeFingerprint: nativeFingerprint, contentFingerprint: contentFingerprint)
    }

    /// How rule (3) prints a time. English-only for v1, like the rest of the copy.
    static func conflictDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Rule (3)'s labels, one per side, worded from where each sits relative to the divider.
    static func conflictLabels(
        noteEditedAt: Date?,
        nativeEditedAt: Date?,
        dateText: (Date) -> String = conflictDateText
    ) -> (cadence: String, apple: String) {
        func label(_ side: String, _ editedAt: Date?, versus other: Date?) -> String {
            var words = side
            if let editedAt, let other, editedAt != other {
                words += editedAt > other ? " — newer" : " — older"
            }
            if let editedAt { words += ", edited \(dateText(editedAt))" }
            return "*\(words)*"
        }
        return (
            label("Above: Cadence note", noteEditedAt, versus: nativeEditedAt),
            label("Below: Apple Calendar", nativeEditedAt, versus: noteEditedAt)
        )
    }

    private static let dividerBlock = "\n\n\(divider)\n\n"

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }

    private static func appended(_ native: String, to noteContent: String) -> String {
        "\(trimmingTrailingWhitespace(noteContent))\(dividerBlock)\(native)"
    }

    /// Rule (2)'s replacement, or `nil` when Apple's old text cannot be located exactly.
    private static func refreshedInPlace(noteContent: String, native: String, baseline: MergeBaseline) -> String? {
        // The whole note was Apple's text — the writable steady state after a mirror. Only when the
        // note carries no picture: a picture is not in Apple's copy, and replacing the note whole
        // would drop it.
        if baseline.contentFingerprint == baseline.nativeFingerprint,
           flattenedForCalendar(noteContent) == noteContent {
            return native
        }
        // Apple's text was the block under the last divider — the read-only steady state.
        guard let range = noteContent.range(of: dividerBlock, options: .backwards),
              fingerprint(String(noteContent[range.upperBound...])) == baseline.nativeFingerprint
        else { return nil }
        return String(noteContent[..<range.upperBound]) + native
    }

    private static func labelledConflict(
        noteContent: String,
        native: String,
        noteEditedAt: Date?,
        nativeEditedAt: Date?,
        dateText: (Date) -> String
    ) -> String {
        let labels = conflictLabels(noteEditedAt: noteEditedAt, nativeEditedAt: nativeEditedAt, dateText: dateText)
        return "\(trimmingTrailingWhitespace(noteContent))\n\n\(labels.cadence)\(dividerBlock)\(labels.apple)\n\n\(native)"
    }

    /// The text a mirror writes. Spelled once so the three commit paths — the iOS event sheet, the
    /// iOS note sheet and the Mac's two note editors — cannot disagree about what Apple Calendar
    /// is given, and so a sweep can ask whether any of them still passes raw content.
    static func mirrorText(noteContent: String) -> String {
        flattenedForCalendar(noteContent)
    }

    private static func removingImageReferences(from line: String) -> String {
        let references = MarkdownImageAssetService.allReferences(in: line)
        guard !references.isEmpty else { return line }
        var result = line as NSString
        for reference in references.reversed() {
            result = result.replacingCharacters(in: reference.range, with: "") as NSString
        }
        return result as String
    }
}

/// The `Note` side of the merge baseline: the three synced fields read into a `MergeBaseline` and
/// written back from one. Kept apart from the pure decisions above because `Note` is main-actor
/// state, and so every host — the iOS sheet, the Mac popover and both platforms' mirror commit —
/// reads and writes the fields through these and nowhere else.
extension CadenceEventNotesMerge {
    @MainActor static func baseline(of note: Note) -> MergeBaseline? {
        guard let mergedAt = note.eventNotesMergedAt else { return nil }
        return MergeBaseline(
            mergedAt: mergedAt,
            nativeFingerprint: note.eventNotesMergedNativeHash,
            contentFingerprint: note.eventNotesMergedContentHash
        )
    }

    /// What the note should hold now against Apple's current text, or `nil` when it already does.
    @MainActor static func resolvedContent(note: Note, nativeNotes: String?, nativeEditedAt: Date?) -> String? {
        resolvedContent(
            noteContent: note.content,
            nativeNotes: nativeNotes,
            baseline: baseline(of: note),
            noteEditedAt: note.updatedAt,
            nativeEditedAt: nativeEditedAt
        )
    }

    /// What the one Notes field shows for this event.
    @MainActor static func displayText(note: Note?, nativeNotes: String?, nativeEditedAt: Date?) -> String {
        displayText(
            noteContent: note?.content,
            nativeNotes: nativeNotes,
            baseline: note.flatMap { baseline(of: $0) },
            noteEditedAt: note?.updatedAt,
            nativeEditedAt: nativeEditedAt
        )
    }

    /// Records that the note holds Apple's current text, when it does. Returns whether a field
    /// changed, so a caller that has already saved knows whether there is anything left to save.
    /// Leaves `updatedAt` alone: the baseline is bookkeeping, not an edit, and `updatedAt` is what
    /// rule (3) prints as the time the user last wrote.
    @MainActor @discardableResult
    static func recordBaseline(_ note: Note, nativeNotes: String?, now: Date = Date()) -> Bool {
        guard let recorded = baselineToRecord(
            noteContent: note.content,
            nativeNotes: nativeNotes,
            current: baseline(of: note),
            now: now
        ) else { return false }
        note.eventNotesMergedAt = recorded.mergedAt
        note.eventNotesMergedNativeHash = recorded.nativeFingerprint
        note.eventNotesMergedContentHash = recorded.contentFingerprint
        return true
    }
}
