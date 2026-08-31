import Foundation

/// Settings copy that the Mac pane and the phone section both show.
///
/// **T-524.** Settings is the one screen the app draws twice from scratch: `Cadence/macOS/Views/`
/// holds one pane per category and `Cadence/iOS/` holds a section per category, and the two were
/// written from the same words rather than from the same string. That is the shape
/// `CadenceEmptyStateCopy` was created for one screen over, and the same drift followed it here —
/// the calendar access card already differs by a whole sentence between the two surfaces, which is
/// recorded on `calendarAccess…Title` below rather than papered over.
///
/// Only wording **both** surfaces show is here. Copy that is true on one platform and false on the
/// other — "Allow Cadence from the iOS Settings app…" against "…from System Settings, Privacy &
/// Security, Calendars." — stays at its own call site, because a constant would invite exactly the
/// substitution that makes it wrong.
///
/// `nonisolated` for the reason `CadenceEmptyStateCopy` carries the same keyword: the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a bare enum here is main-actor isolated and
/// reading it from a `nonisolated` context warns today and is an error under Swift 6. Constants
/// have no state to protect.
nonisolated enum CadenceCalendarSettingsCopy {

    /// Settings → Calendar, with EventKit access refused. The **title** is one string across both
    /// surfaces; the sentence under it deliberately is not, because it names where the reader has
    /// to go and that is a different place on each platform.
    static let accessDeniedTitle = "Calendar access denied"

    /// Settings → Calendar, before anyone has been asked.
    ///
    /// **The two surfaces disagree under this title and the disagreement is not resolved here**
    /// (see T-543): macOS says "Allow Cadence to create and sync calendar events." while iOS says
    /// "Allow Cadence to show events and connect Apple calendars to areas or projects." Both are
    /// true of both platforms, so one of them is the right sentence for both — but picking it is a
    /// copy decision, not a de-duplication, and converging the two subtitles by fiat would hide the
    /// choice inside a refactor.
    static let accessRequiredTitle = "Calendar access required"

    /// The connect menu on a calendar row with no active area or project to offer.
    static let noConnectableListsLabel = "No active areas or projects"

    /// A calendar row that no list mirrors. The row prints the connected list names when there are
    /// any, so this is the whole line rather than a prefix.
    static let unconnectedSummary = "Not connected to any area or project"

    /// The work-hours row's title, on Settings > Calendar at both widths.
    ///
    /// **Only the title is shared.** The sentence under it differs on purpose-or-by-accident and
    /// this refactor does not decide which (T-544): macOS says "Weekly calendar views gently
    /// highlight …" and iOS says "Calendar day columns gently highlight …". Both surfaces read the
    /// same `CalendarWorkHoursPreferences.highlightFrame`, so at most one of those sentences
    /// describes where the band is actually drawn — that is a copy decision with a behavioural
    /// question under it, not a de-duplication, and converging it here would bury the choice.
    static let workdayBoundaryTitle = "Workday boundary"

    /// The accessible name of the calendar row's link menu — an icon-only control on both
    /// surfaces, so nothing else on the row says what it does.
    ///
    /// macOS reaches it through `cadenceControlLabel(_:)`, which sets the name *and* the tooltip;
    /// it used to set `.help` alone, which is the T-472 defect (a pointer gets a sentence and
    /// assistive technology gets the SF Symbol name) two screens away from where T-472 fixed it.
    static let connectMenuLabel = "Connect to areas and projects"

    /// The eyebrow over the list of Apple calendars, **inside the authorized branch**.
    ///
    /// **T-599(e).** macOS said "Apple Calendars" and iOS said "Apple Calendar", and the singular
    /// was wrong twice over. It is a list of every calendar EventKit vends, so the plural is the
    /// accurate noun; and iOS drew the label *above* the authorization branch, so the same word
    /// also headed the access-denied card — an eyebrow announcing a list that is not there and
    /// cannot be. Both surfaces now draw it only where the list is.
    ///
    /// *Extends [[T-547]]*, which is the same noun serving two concepts one screen over.
    static let appleCalendarsSectionTitle = "Apple Calendars"
}

/// Settings → Tags, on both surfaces.
nonisolated enum CadenceTagSettingsCopy {

    /// The Active Tags card with nothing in it.
    ///
    /// **T-599(a).** macOS said "Create a tag or add the default set." and iOS said "Create one or
    /// add the default set." — and "one" only resolves against the title above it, which is
    /// exactly the referent an empty state cannot rely on a reader having just parsed. The noun
    /// wins.
    ///
    /// The **title** converged the other way: macOS's had a full stop and iOS's did not, and every
    /// other settings empty-state title on the phone — "No open reminders", "No active contexts",
    /// "No completed or archived lists" — is a noun phrase without one. A title is not a sentence.
    static let emptyCatalogTitle = "No active tags"
    static let emptyCatalogSubtitle = "Create a tag or add the default set."
}

/// Settings → Note Templates, on both surfaces.
nonisolated enum CadenceTemplateSettingsCopy {

    /// What editing a template does and does not touch.
    ///
    /// **T-599(b), and only the second sentence.** macOS's footnote opened "Templates appear in
    /// the note sidebar for matching note types." — a true statement about a real macOS surface
    /// and a false one on a phone, which has no note sidebar. That clause stays spelled at the
    /// macOS call site rather than being hoisted into a constant a phone could read; what both
    /// surfaces genuinely say is the scope of the edit, and iOS's spelling of it is the one that
    /// stands alone without the sidebar clause in front of it. Same family as [[T-544]].
    static let editScopeFootnote = "Templates affect future insertions only. Existing notes keep their current content."
}

/// Settings → AI, on both surfaces.
///
/// **T-599(c) and (d).** The card is byte-identical between the two trees except for one sentence
/// and three button labels, which is drift rather than a pair of platform decisions.
nonisolated enum CadenceAISettingsCopy {

    /// **Privacy copy, so accuracy is the bar rather than brevity.**
    ///
    /// macOS's sentence ended "…only when you run an AI action, such as summarizing a note or
    /// extracting task drafts."; iOS's stopped at "AI action". The examples are what make "an AI
    /// action" a thing the reader can recognise when they are about to take one, and the reader is
    /// being told what leaves their device. The longer sentence wins on both.
    static let keyPrivacyDisclosure = "Stored in Keychain. Cadence sends selected note content to OpenAI only when you run an AI action, such as summarizing a note or extracting task drafts."

    /// The three buttons under the key field. Verbosity was **inverted** between the surfaces —
    /// macOS said "Save API Key"/"Test Connection"/"Delete Key" and iOS said "Save Key"/"Test"/
    /// "Delete API Key" — so neither tree was simply the terser one and there was nothing to
    /// prefer wholesale.
    ///
    /// Resolved per button, on what each one has to say:
    ///
    /// - **Save/Delete name the whole noun.** A destructive control gets no second chance to
    ///   explain itself, and "Delete Key" beside a Model ID field is one glance from ambiguous.
    ///   Both now say "API Key", so the pair reads as one object with two verbs.
    /// - **Test names what is tested.** "Test" alone is a verb with no object on a card that holds
    ///   a key, a model id and a network call.
    ///
    /// The in-flight label is deliberately *not* here: macOS says "Testing..." and iOS "Testing",
    /// which is a third divergence T-599 did not name and is under the sweep's 12-character floor.
    static let saveAPIKeyAction = "Save API Key"
    static let testConnectionAction = "Test Connection"
    static let deleteAPIKeyAction = "Delete API Key"
}

/// Settings → Notifications, which is one row in two states on both surfaces.
///
/// Every string here was spelled twice — the Mac's `SettingsNotificationsSection` and the phone's
/// `iOSNotificationsSettingsSection` are the same four sentences in two card vocabularies. Nothing
/// about the *words* differs by platform: both surfaces schedule the same local notifications
/// through the same `NotificationManager`, and only the route into system settings differs, which
/// is code rather than copy.
nonisolated enum CadenceNotificationSettingsCopy {

    /// The row title **and** the switch's accessible name, which is why it is one constant rather
    /// than two: T-484 named the toggle after its own row precisely so the two could not drift, and
    /// spelling them separately is how that drift starts. Pinned by
    /// `CadenceControlAccessibilityLabelTests.theFiveNamedTogglesTakeTheirNameFromTheirOwnRow`.
    static let remindersToggleTitle = "Enable reminders"

    /// Says what is scheduled and that it stays on the device. "Locally" is load-bearing: nothing
    /// here goes through a push server, and the reader has just been asked for a system permission.
    static let remindersToggleDetail = "A task's scheduled start and due date, and a habit's reminder time, notify you locally."

    static let accessRequiredTitle = "Notification access required"
    static let accessRequiredDetail = "Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders."

    /// The button under `accessRequiredDetail`. Names the thing it turns on rather than the
    /// permission dialog it opens, so it still reads correctly on the second press, when the
    /// system will not prompt again and both surfaces fall through to system settings.
    static let enableNotificationsAction = "Enable Notifications"
}

/// Settings → Lists, on both surfaces: the "Inactive Lists" rows, which are the only place a
/// completed or archived area or project can still be reached.
///
/// **T-577.** The two surfaces drew the same row from two different rules, and the Mac's was the
/// broken one: it printed `project.name` and `area.name` raw, and built the project's second line
/// as `[context, area].compactMap { $0 }.joined(separator: " • ")` — which is the **empty string**
/// for a project with neither. A context-less list is reachable (T-558/T-559), so Settings → Lists
/// could show a row with no name over a blank line. iOS fell back to
/// `CadenceTitleNormalization.default*Name` and to the sentence below, and the Mac's own *area*
/// branch twelve lines above already fell back to "No context" — the file disagreed with itself.
///
/// The subtitle rule lives here rather than at either call site so the two cannot drift again. It
/// takes the two names rather than a `Project` to keep this file free of model coupling; the
/// titles themselves read `CadenceTitleNormalization.display(_:fallback:)`, which is stronger than
/// the `.isEmpty` check iOS had — a whitespace-only name is blank too (T-569).
nonisolated enum CadenceListSettingsCopy {

    /// A project filed under neither a context nor an area. The whole line, not a prefix.
    static let noParentListSubtitle = "No parent list"

    /// The second line of a project row: its context and its area, or `noParentListSubtitle`.
    static func parentSubtitle(contextName: String?, areaName: String?) -> String {
        let parts = [contextName, areaName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? noParentListSubtitle : parts.joined(separator: " • ")
    }
}
