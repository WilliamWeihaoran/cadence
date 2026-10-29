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
