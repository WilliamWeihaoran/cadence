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

    /// Settings → Calendar, before anyone has been asked. **T-694/T-777.** Used to be
    /// `accessRequiredTitle`, phrased as a demand nobody had earned yet — the same defect T-543
    /// already fixed for this card's glyph and sentence, left open for the title until the
    /// Notifications pane's split (T-694) gave it a name to mirror. `accessDeniedTitle` above is
    /// unchanged: that state genuinely is a fault the reader has to go and fix.
    static let connectOfferTitle = "Connect Apple Calendar"

    /// The sentence under `connectOfferTitle` — **the same one on both surfaces since T-543.**
    ///
    /// T-524 found the two panes disagreeing here and deliberately did not converge them: macOS
    /// said "Allow Cadence to create and sync calendar events.", iOS said the sentence below, both
    /// were true of both platforms, and picking one is a copy decision rather than a
    /// de-duplication. T-543 made the pick, and this is the reasoning rather than the outcome
    /// alone: this card gates *reading* the calendar list and connecting a calendar to an area or
    /// project, which is what the screen around it is for. Writing events is real but happens in
    /// the quick-create and event sheets, so naming it here described a different screen.
    ///
    /// It is an **offer**, not a fault report, and that is the other half of T-543: the Mac drew an
    /// amber warning triangle beside this sentence in the state where nobody has been asked yet.
    /// Both surfaces now draw a neutral `calendar.badge.plus` there and keep the triangle for
    /// `accessDeniedTitle`, whose sentence still lives at each call site because it names where the
    /// reader has to go and that is a different place on each platform.
    static let accessRequiredDetail =
        "Allow Cadence to show events and connect Apple calendars to areas or projects."

    /// The connect menu on a calendar row with no active area or project to offer.
    static let noConnectableListsLabel = "No active areas or projects"

    /// A calendar row that no list mirrors. The row prints the connected list names when there are
    /// any, so this is the whole line rather than a prefix.
    static let unconnectedSummary = "Not connected to any area or project"

    /// The work-hours row's title, on Settings > Calendar at both widths.
    ///
    /// **Only the title is shared**, and the sentence under it still differs — deliberately, and
    /// now for a stated reason rather than by accident. T-524 left the pair undecided; T-544 read
    /// the code and decided macOS's half: it said "Weekly calendar views gently highlight …" while
    /// the band is drawn per **day column** by `TimelineDayCanvas`, at exactly two call sites, one
    /// of which is the **Timeline** panel and not a calendar view. macOS now says "Calendar and
    /// Timeline day columns gently highlight …" and iOS says "Calendar day columns gently
    /// highlight …", because mobile draws the band on the Calendar's day columns and nowhere else:
    /// iPad's Timeline pane reads the same two preference keys but spends them on
    /// `ReadyScheduleContext`'s slot suggestions, not on a band. The two sentences name their own
    /// surfaces and cannot be converged without one of them becoming false.
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

    /// Settings → Notifications, with permission explicitly denied. Kept as a demand — T-694's
    /// urgency call — because that state genuinely is a fault the reader has to go and fix.
    static let accessRequiredTitle = "Notification access required"

    /// Settings → Notifications, before anyone has been asked. **T-694.** `accessRequiredTitle`
    /// used to head this state too, phrased as a demand nobody had earned yet — the same defect
    /// [[T-543]] fixed for the calendar card's glyph and sentence, still open for this title.
    static let connectOfferTitle = "Connect Notifications"

    static let accessRequiredDetail = "Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders."

    /// The button under `accessRequiredDetail`. Names the thing it turns on rather than the
    /// permission dialog it opens, so it still reads correctly on the second press, when the
    /// system will not prompt again and both surfaces fall through to system settings.
    static let enableNotificationsAction = "Enable Notifications"
}

/// The settings cards that can be empty, on both surfaces.
///
/// **T-600(b).** Four of them said one thing on the Mac and two on the phone: macOS drew a single
/// line naming what is absent — "No open reminders." — and iOS drew that line plus a sentence
/// saying what would put something there. An empty state that reports only absence leaves the
/// reader deciding between "this is broken", "I am in the wrong place" and "there is something I
/// was supposed to do", which is what T-469 and T-473 found one screen over. iOS was right in all
/// four, so all four sentences are iOS's.
///
/// **Titles carry no full stop and subtitles do.** macOS's four disagreed with each other about
/// that — "No templates available" beside "No active contexts." — and iOS's did not.
///
/// *Extends [[T-545]]*, which named the empty-calendar row; these are four more of one shape.
nonisolated enum CadenceSettingsEmptyStateCopy {

    /// Settings → Apple Reminders, connected, with nothing open. Says what the list would hold and
    /// how it would be arranged, which is the part that tells a reader the screen is working.
    static let remindersTitle = "No open reminders"
    static let remindersSubtitle = "Reminders you have not completed yet will be summarised here by list."

    /// Settings → Contexts.
    ///
    /// "here" is load-bearing and true on both platforms — the **New Context** control is inside
    /// this same card on the Mac and directly above it on the phone. That is the T-469 test this
    /// sentence has to pass before it can be shared: copy naming a control that is not on the
    /// screen is worse than no copy.
    static let contextsTitle = "No active contexts"
    static let contextsSubtitle = "Create one here, then use it when making areas and projects."

    /// Settings → Lists.
    ///
    /// The eyebrow is part of the pair rather than chrome: every other branch of that pane names
    /// the group it is showing ("Completed Areas", "Archived Projects"), and macOS's empty branch —
    /// the only one a reader with no inactive lists ever sees — named nothing at all.
    static let inactiveListsSectionTitle = "Inactive Lists"
    static let inactiveListsTitle = "No completed or archived lists"
    static let inactiveListsSubtitle = "Areas and projects you complete or archive will appear here."

    /// Settings → Note Templates with no library at all.
    ///
    /// The odd one of the four, and the reason the subtitle matters most here: the templates ship
    /// with the app, so this is not "you have not made one yet" — it is the stored definitions
    /// failing to load. macOS said "No templates available" in a bare `Text` and stopped, which
    /// reads as a state the reader could fix by creating something.
    static let templatesTitle = "No templates available"
    static let templatesSubtitle = "Template definitions could not be loaded."

    /// Settings → Calendar, authorized, with EventKit vending no calendars at all.
    ///
    /// **T-545, and the fifth of T-600(b)'s four.** It was missed because it is not "you have made
    /// none yet": access has been granted and the answer came back empty, so the only useful thing
    /// to say is what would appear here if it were not. macOS said "No Apple calendars found." in a
    /// private glyph-plus-`Text` row — one line, and carrying the full stop a title does not take —
    /// while the phone already said both lines. The repo rule that page headers do not describe the
    /// page is not in play: an empty state may keep its subtitle, and this is the reason why.
    static let appleCalendarsTitle = "No Apple calendars found"
    static let appleCalendarsSubtitle = "Calendars available to this device will appear here."
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

/// Settings → Contexts and Settings → Lists: the eyebrow over each lifecycle group, on both
/// surfaces.
///
/// **T-546.** Six labels, twelve call sites, byte-identical across the two Settings trees —
/// `SettingsListManagementSections.swift` on the Mac against `iOSSettingsView.swift` and
/// `iOSSettingsTemplateAndListSections.swift` on the phone. T-524's pass converged everything
/// around them and left these alone only because a sibling agent might have owned those files.
///
/// **Every title is `"<status> <plural noun>"`, and the status word is the one
/// `CadenceListSearchLifecycle.statusLabel` already vends** — which is what left room for the
/// sections that did not exist yet. `ProjectStatus` has five cases and Settings showed only two of
/// them (T-690): a `.paused` or `.cancelled` project reached no group here at all, so it could be
/// neither reopened nor deleted from this screen. `pausedProjects` and `cancelledProjects` close
/// that gap, in the voice the rule above already decided —
/// `CadenceSettingsSectionCopyTests.everyLifecycleSectionTitleFollowsTheStatusThenNounRule` pins
/// them against the same five-case vocabulary, so the seventh and eighth titles could not be
/// invented in a different one.
///
/// They are eight plain literals rather than one `sectionTitle(_:of:)` composer on purpose. An
/// interpolated title is invisible to `cadenceSharedStringConstants`, which harvests
/// `static let x = "…"` only — that is the recorded gap behind `CadenceEmptyStateCopy.goalsTitle`,
/// a converged string a *ninth* call site could re-type with nothing to catch it. Eight declared
/// literals stay inside the sweep; a composer with no caller would be dead code that also left the
/// sweep blind. (T-703 proposed exactly that composer once a `static func` could be harvested —
/// this file is why the answer is still no: the harvest that would need to see through it reads
/// literal declarations, not interpolated ones.)
///
/// There is no `activeAreas`/`activeProjects` here because Settings → Lists is the inactive
/// screen: active areas and projects live on the Lists page, and only contexts show their active
/// group here.
nonisolated enum CadenceListLifecycleSectionCopy {

    /// Settings → Contexts. `Context` carries `isArchived` and nothing else, so it has two groups
    /// and no completed one.
    static let activeContexts = "Active Contexts"
    static let archivedContexts = "Archived Contexts"

    /// Settings → Lists, "Inactive Lists". `AreaStatus` has three cases and the active one is not
    /// shown here, so an area has exactly these two groups.
    static let completedAreas = "Completed Areas"
    static let archivedAreas = "Archived Areas"

    /// Settings → Lists. Two of the four inactive `ProjectStatus` cases; see the pair below for
    /// the other two.
    static let completedProjects = "Completed Projects"
    static let archivedProjects = "Archived Projects"

    /// Settings → Lists (T-690). The remaining two inactive `ProjectStatus` cases. `Area` has no
    /// paused or cancelled status, so these are project-only — there is no `pausedAreas` /
    /// `cancelledAreas` to pair them with.
    static let pausedProjects = "Paused Projects"
    static let cancelledProjects = "Cancelled Projects"
}
