import Foundation
import Testing
@testable import Cadence

// MARK: - What these tests claim, and what they cannot

/// **T-524: the Settings half.** Settings is the one screen this app draws twice from scratch —
/// `Cadence/macOS/Views/` holds a pane per category, `Cadence/iOS/` holds a section per category —
/// and the two were written from the same *words* rather than from the same string. Twelve
/// sentences were spelled in both trees.
///
/// **Most of what is below is a source scan, and it has to be.** `Cadence/iOS/` is not compiled by
/// this target at all, so no test here can ask the phone's section what it renders; and even on the
/// Mac an empty-state title is a `String` argument to a `View` initialiser inside a `body`, with no
/// seam to call. So the pairing claims — "both surfaces read this constant, and neither types the
/// literal any more" — are read as text. Only `theCompiledSettingsCopyStillSaysWhatBothSurfacesUsedToSpell`
/// is a value assertion against compiled code.
///
/// **The scans read `strippingComments`, not `codeOnly`.** `codeOnly` blanks string literals along
/// with comments, so `code.contains("\"Enable reminders\"")` against it is permanently, silently
/// true-for-nobody — the single most repeated scan mistake in this repo. Every assertion here is
/// about the *contents* of a literal, so the comment-only reader is the correct one, and
/// `theSettingsCopyScanReadsLiteralsRatherThanBlankingThem` pins that the two readers still differ.
@MainActor
struct CadenceSettingsSectionCopyTests {

    /// Each converged string, as the expression both surfaces must now read and the literal neither
    /// may still type. Stated as pairs rather than counted: a count stays green when one call site
    /// reverts and another is added.
    private static let calendarPairs: [(expression: String, literal: String)] = [
        ("CadenceCalendarLinkHealth.brokenLinksSectionTitle", "Broken Calendar Links"),
        ("CadenceCalendarLinkHealth.noRelinkTargetsLabel", "No Apple calendars available"),
        ("CadenceCalendarSettingsCopy.accessDeniedTitle", "Calendar access denied"),
        ("CadenceCalendarSettingsCopy.accessRequiredTitle", "Calendar access required"),
        ("CadenceCalendarSettingsCopy.noConnectableListsLabel", "No active areas or projects"),
        ("CadenceCalendarSettingsCopy.unconnectedSummary", "Not connected to any area or project"),
        ("CadenceCalendarSettingsCopy.connectMenuLabel", "Connect to areas and projects"),
        ("CadenceCalendarSettingsCopy.appleCalendarsSectionTitle", "Apple Calendars"),
        // **T-543.** The one sentence the access card says before anybody has been asked.
        // T-524 left this pair diverged on purpose — both sentences were true of both
        // platforms, so picking one was a copy decision rather than a de-duplication — and
        // T-543 made the decision: the phone's, because it names what this card actually
        // gates (showing events, and connecting a calendar to an area or project) rather
        // than the writing path a reader on this screen is not using.
        (
            "CadenceCalendarSettingsCopy.accessRequiredDetail",
            "Allow Cadence to show events and connect Apple calendars to areas or projects."
        ),
    ]

    /// **T-599.** Four more sentences that were spelled in both trees and had already drifted —
    /// three of them in ways that changed what the sentence meant rather than only how long it
    /// was. Same pair shape as the calendar and notification lists above: read the constant, do
    /// not still type the literal.
    private static let tagPairs: [(expression: String, literal: String)] = [
        ("CadenceTagSettingsCopy.emptyCatalogTitle", "No active tags"),
        ("CadenceTagSettingsCopy.emptyCatalogSubtitle", "Create a tag or add the default set."),
    ]

    private static let templatePairs: [(expression: String, literal: String)] = [
        (
            "CadenceTemplateSettingsCopy.editScopeFootnote",
            "Templates affect future insertions only. Existing notes keep their current content."
        ),
    ]

    private static let aiPairs: [(expression: String, literal: String)] = [
        (
            "CadenceAISettingsCopy.keyPrivacyDisclosure",
            "Stored in Keychain. Cadence sends selected note content to OpenAI only when you run an AI action, such as summarizing a note or extracting task drafts."
        ),
        ("CadenceAISettingsCopy.saveAPIKeyAction", "Save API Key"),
        ("CadenceAISettingsCopy.testConnectionAction", "Test Connection"),
        ("CadenceAISettingsCopy.deleteAPIKeyAction", "Delete API Key"),
    ]

    private static let tagSurfaces = [
        "Cadence/macOS/Views/SettingsTagsSection.swift",
        "Cadence/iOS/iOSSettingsTagsSection.swift",
    ]

    private static let templateSurfaces = [
        "Cadence/macOS/Views/SettingsTemplatesSection.swift",
        "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
    ]

    /// The phone keeps its AI card in the same file as its templates and lists sections; the Mac
    /// gives it a shared file with several other panes. Neither is the other's twin by filename.
    private static let aiSurfaces = [
        "Cadence/macOS/Views/SettingsSectionViews.swift",
        "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
    ]

    private static let notificationPairs: [(expression: String, literal: String)] = [
        ("CadenceNotificationSettingsCopy.remindersToggleTitle", "Enable reminders"),
        (
            "CadenceNotificationSettingsCopy.remindersToggleDetail",
            "A task's scheduled start and due date, and a habit's reminder time, notify you locally."
        ),
        ("CadenceNotificationSettingsCopy.accessRequiredTitle", "Notification access required"),
        (
            "CadenceNotificationSettingsCopy.accessRequiredDetail",
            "Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders."
        ),
        ("CadenceNotificationSettingsCopy.enableNotificationsAction", "Enable Notifications"),
    ]

    private static let calendarSurfaces = [
        "Cadence/macOS/Views/SettingsListManagementSections.swift",
        "Cadence/iOS/iOSCalendarSettingsSection.swift",
    ]

    private static let notificationSurfaces = [
        "Cadence/macOS/Views/SettingsNotificationsSection.swift",
        "Cadence/iOS/iOSNotificationsSettingsSection.swift",
    ]

    /// The work-hours row is a third file pair, not a third file in the pair above: iOS keeps it
    /// inside `iOSCalendarSettingsSection` and macOS gives it a file of its own.
    private static let workHoursSurfaces = [
        "Cadence/macOS/Views/SettingsCalendarWorkHoursSection.swift",
        "Cadence/iOS/iOSCalendarSettingsSection.swift",
    ]

    /// Settings → Lists, "Inactive Lists": the two files that draw a completed or archived area or
    /// project. The only screen either list can still be reached from, which is why an unreadable
    /// row there is worse than one anywhere else.
    private static let inactiveListSurfaces = [
        "Cadence/macOS/Views/SettingsListManagementSections.swift",
        "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
    ]

    // MARK: - Both surfaces read each converged string

    /// Settings → Calendar says one thing on two devices.
    ///
    /// Both halves of each claim matter and neither implies the other: a file can read the constant
    /// in one branch and still spell the literal in another (the access card has two arms), and a
    /// file can have deleted the literal without reading anything shared.
    @Test func bothCalendarSettingsSurfacesReadEveryConvergedCalendarString() throws {
        for path in Self.calendarSurfaces {
            let code = try Self.strippedSource(at: path)
            for pair in Self.calendarPairs {
                #expect(
                    code.contains(pair.expression),
                    "\(path) does not read \(pair.expression)"
                )
                #expect(
                    !code.contains("\"\(pair.literal)\""),
                    "\(path) still spells \"\(pair.literal)\" beside the constant that holds it"
                )
            }
        }
    }

    /// Settings → Notifications, the same claim.
    ///
    /// The extra assertion is T-484's, kept honest by construction rather than by two matching
    /// literals: the switch takes its accessible name from `remindersToggleTitle`, which is the
    /// *same* constant the row's visible title reads. There is no longer a spelling of this pane in
    /// which the name and the title can disagree.
    @Test func bothNotificationsSettingsSurfacesReadEveryConvergedNotificationString() throws {
        for path in Self.notificationSurfaces {
            let code = try Self.strippedSource(at: path)
            for pair in Self.notificationPairs {
                #expect(
                    code.contains(pair.expression),
                    "\(path) does not read \(pair.expression)"
                )
                #expect(
                    !code.contains("\"\(pair.literal)\""),
                    "\(path) still spells \"\(pair.literal)\" beside the constant that holds it"
                )
            }
            #expect(
                code.contains(
                    "Toggle(CadenceNotificationSettingsCopy.remindersToggleTitle, isOn: $notificationsEnabled)"
                ),
                "\(path) no longer names its switch after its own row title"
            )
            #expect(code.contains(".labelsHidden()"), "\(path) would now draw the name twice")
        }
    }

    /// **T-599's four, each read as a pair on both surfaces.**
    ///
    /// Split from the calendar and notification tests above only because the file pairs differ;
    /// the claim is identical, and so is the reason it is two assertions rather than one — a file
    /// can read the constant in one branch and still spell the literal in another.
    ///
    /// The templates footnote is the interesting member: macOS still spells a **first clause**
    /// this does not touch ("Templates appear in the note sidebar for matching note types."),
    /// because the note sidebar is a real macOS surface and a false one on a phone. So the
    /// assertion below is deliberately about the shared second sentence only, and the clause that
    /// stays macOS-only is pinned by `theTemplatesFootnoteKeepsItsSidebarClauseOnMacOSAlone`.
    @Test func bothSurfacesOfEachTaggedTemplateAndAICardReadTheConvergedString() throws {
        for (surfaces, pairs) in [
            (Self.tagSurfaces, Self.tagPairs),
            (Self.templateSurfaces, Self.templatePairs),
            (Self.aiSurfaces, Self.aiPairs),
        ] {
            for path in surfaces {
                let code = try Self.strippedSource(at: path)
                for pair in pairs {
                    #expect(
                        code.contains(pair.expression),
                        "\(path) does not read \(pair.expression)"
                    )
                    #expect(
                        !code.contains("\"\(pair.literal)\""),
                        "\(path) still spells \"\(pair.literal)\" beside the constant that holds it"
                    )
                }
            }
        }
    }

    /// **T-599(b)'s decision, held as a difference rather than as a convergence.**
    ///
    /// The obvious "fix" for a footnote written twice is one constant read twice. That would have
    /// shipped a sentence telling an iPhone reader to look in the note sidebar, which is not a
    /// surface that phone has. So only the second sentence is shared, and this pins both halves:
    /// the Mac keeps the clause, and the phone must never grow it.
    @Test func theTemplatesFootnoteKeepsItsSidebarClauseOnMacOSAlone() throws {
        let clause = "Templates appear in the note sidebar for matching note types."
        let mac = try Self.strippedSource(at: Self.templateSurfaces[0])
        let phone = try Self.strippedSource(at: Self.templateSurfaces[1])

        #expect(mac.contains("struct SettingsTemplatesSection"), "non-vacuity: wrong file")
        #expect(mac.contains(clause), "the Mac's footnote lost the surface it is describing")
        #expect(
            phone.contains("note sidebar") == false,
            "the phone's templates footnote now names a surface the phone does not have"
        )
    }

    /// **T-599(e): the calendar list's eyebrow is inside the authorized branch on both surfaces.**
    ///
    /// The plural was half of the finding. The other half is placement: iOS drew the label above
    /// `if calendarManager.isAuthorized`, so "Apple Calendars" also headed the access-denied card
    /// — an eyebrow over a list of calendars the app has just said it cannot read. macOS already
    /// had it in the branch, which is why macOS is the one that did not move.
    ///
    /// Asserted as ordering within the file rather than as presence, because presence is what was
    /// already true and wrong.
    @Test func bothCalendarPanesHeadOnlyTheAuthorizedBranchWithTheCalendarList() throws {
        for path in Self.calendarSurfaces {
            let code = try Self.strippedSource(at: path)
            let branch = try #require(
                code.range(of: "calendarManager.isAuthorized"),
                "\(path) no longer branches on calendar authorization"
            )
            let label = try #require(
                code.range(of: "CadenceCalendarSettingsCopy.appleCalendarsSectionTitle"),
                "\(path) does not read the shared Apple Calendars eyebrow"
            )
            #expect(
                label.lowerBound > branch.upperBound,
                "\(path) heads its access card with the name of the list it cannot show"
            )
        }
    }

    /// **T-543: the access card draws one glyph per state, and the states are not both errors.**
    ///
    /// macOS drew an **amber warning triangle unconditionally** — including in the state where
    /// nobody has been asked yet, which is the default a fresh install is in and not a problem the
    /// reader has caused. Beside it sat a button offering access. So the card said two things at
    /// once, and the one it said loudest was wrong.
    ///
    /// Asserted as the ternary rather than as presence, because presence is what was already true:
    /// the warning glyph is still in both files, and the whole finding is *which arm* it is on.
    /// The exact counts are the other half — a second, unconditional triangle elsewhere in the card
    /// would satisfy a `contains` check and re-create the defect beside the fix.
    @Test func theCalendarAccessCardDrawsOneGlyphPerStateOnBothSurfaces() throws {
        for path in Self.calendarSurfaces {
            let code = try Self.strippedSource(at: path)

            #expect(
                CadenceSourceScan.matchCount("\"exclamationmark.triangle.fill\"", in: code) == 1,
                "\(path) spells the warning glyph more than once, so one of them is unconditional"
            )
            #expect(
                CadenceSourceScan.matchCount("\"calendar.badge.plus\"", in: code) == 1,
                "\(path) does not offer exactly one neutral not-yet-asked glyph"
            )
            #expect(
                code.contains(
                    "calendarManager.isDenied ? \"exclamationmark.triangle.fill\" : \"calendar.badge.plus\""
                ),
                "\(path) draws a warning triangle in a state nobody has been asked about yet"
            )
            #expect(
                code.contains("calendarManager.isDenied ? Theme.amber : Theme.blue"),
                "\(path) tints the not-yet-asked glyph as a warning"
            )
        }
    }

    // MARK: - T-600: one empty-row component, and four cards that say two lines on both surfaces

    /// **The duplicate empty row is gone from the tree, not merely unused.**
    ///
    /// `iOSSettingsEmptyRow` and `iOSSettingsEmptyInlineRow` were the same card row twice — same
    /// glyph tile, same two-line stack, same trailing `Spacer` — and had already drifted a point
    /// (13pt title against 14) plus a `Theme.dim`/`Theme.subdued` subtitle. The fixed one hardcoded
    /// its glyph to `tray`, which is what settles which survives: the parameterised row already
    /// serves four cards passing four different symbols, and the fixed one could not have taken
    /// any of them.
    ///
    /// Swept over the whole app rather than the two known call sites, because the failure this
    /// guards is the component being *moved* rather than removed — the same claim shape
    /// `theFifthPrivateSettingsRowIsRetiredRatherThanRelocated` makes one suite over.
    @Test func theFixedGlyphSettingsEmptyRowIsDeletedRatherThanLeftUnused() throws {
        var scanned = 0
        var offenders: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            scanned += 1
            let code = try Self.strippedSource(at: path)
            if code.range(
                of: "(?<![A-Za-z0-9_])iOSSettingsEmptyRow(?![A-Za-z0-9_])",
                options: .regularExpression
            ) != nil {
                offenders.append(path)
            }
        }
        #expect(scanned >= 300, "scanned only \(scanned) files")
        #expect(offenders.isEmpty, "the retired iOSSettingsEmptyRow is still named in: \(offenders)")

        // The survivor, and where it lives now: the shared iOS settings component file, beside the
        // rest of that vocabulary rather than three hundred lines into a feature section.
        let components = try Self.strippedSource(at: "Cadence/iOS/iOSSettingsComponents.swift")
        #expect(components.contains("struct iOSSettingsEmptyInlineRow: View"))
        #expect(
            components.contains("Image(systemName: systemImage)"),
            "the surviving row hardcodes its glyph again, which is why the other one lost"
        )
        let oldHome = try Self.strippedSource(at: "Cadence/iOS/iOSSettingsTemplateAndListSections.swift")
        #expect(
            oldHome.contains("struct iOSSettingsEmptyInlineRow") == false,
            "the row is declared twice again"
        )
    }

    /// **The four cards that can be empty say what is missing *and* what would fill it, on both.**
    ///
    /// macOS drew one line and iOS drew two, in four places. Asserted as the pairing this file
    /// exists for — each surface reads the constant, neither still spells the literal — which is
    /// strictly more than "macOS gained a subtitle": a second hand-typed sentence beside the first
    /// would satisfy a looser check and re-create the drift on the next edit.
    ///
    /// `Cadence/iOS/` is not compiled by this target, so the phone's half can only be read as text;
    /// the values themselves are asserted in
    /// `theCompiledSettingsCopyStillSaysWhatBothSurfacesUsedToSpell`.
    @Test func bothSurfacesOfEveryEmptySettingsCardReadOneTitleAndOneSubtitle() throws {
        let pairs: [(surfaces: [String], expressions: [String], literals: [String])] = [
            (
                [
                    "Cadence/macOS/Views/SettingsRemindersSection.swift",
                    "Cadence/iOS/iOSRemindersSettingsSection.swift",
                ],
                ["CadenceSettingsEmptyStateCopy.remindersTitle", "CadenceSettingsEmptyStateCopy.remindersSubtitle"],
                ["No open reminders", "No open reminders."]
            ),
            (
                [
                    "Cadence/macOS/Views/SettingsListManagementSections.swift",
                    "Cadence/iOS/iOSSettingsView.swift",
                ],
                ["CadenceSettingsEmptyStateCopy.contextsTitle", "CadenceSettingsEmptyStateCopy.contextsSubtitle"],
                ["No active contexts", "No active contexts."]
            ),
            (
                [
                    "Cadence/macOS/Views/SettingsListManagementSections.swift",
                    "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
                ],
                [
                    "CadenceSettingsEmptyStateCopy.inactiveListsSectionTitle",
                    "CadenceSettingsEmptyStateCopy.inactiveListsTitle",
                    "CadenceSettingsEmptyStateCopy.inactiveListsSubtitle",
                ],
                ["Inactive Lists", "No completed or archived lists", "No completed or archived lists."]
            ),
            (
                [
                    "Cadence/macOS/Views/SettingsTemplatesSection.swift",
                    "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
                ],
                ["CadenceSettingsEmptyStateCopy.templatesTitle", "CadenceSettingsEmptyStateCopy.templatesSubtitle"],
                ["No templates available", "No templates available."]
            ),
            // **T-545, the fifth.** Missed by T-600(b) because it is not a "you have made none
            // yet" card: EventKit has granted access and vended nothing. macOS said
            // "No Apple calendars found." — one line, with the full stop a title does not take —
            // where the phone already said what would fill the card. The macOS literal carries
            // that stray full stop, which is why it is listed as its own forbidden spelling.
            (
                [
                    "Cadence/macOS/Views/SettingsListManagementSections.swift",
                    "Cadence/iOS/iOSCalendarSettingsSection.swift",
                ],
                [
                    "CadenceSettingsEmptyStateCopy.appleCalendarsTitle",
                    "CadenceSettingsEmptyStateCopy.appleCalendarsSubtitle",
                ],
                ["No Apple calendars found", "No Apple calendars found."]
            ),
        ]

        for entry in pairs {
            for path in entry.surfaces {
                let code = try Self.strippedSource(at: path)
                for expression in entry.expressions {
                    #expect(code.contains(expression), "\(path) does not read \(expression)")
                }
                for literal in entry.literals {
                    #expect(
                        !code.contains("\"\(literal)\""),
                        "\(path) still spells \"\(literal)\" beside the constant that holds it"
                    )
                }
            }
        }
    }

    /// **Neither pane still draws one of these as a private one-liner.**
    ///
    /// The pairing above is satisfiable by a pane that reads the constants *and* keeps its old
    /// hand-built row somewhere else in the file. What the four macOS sites had in common was not
    /// a missing sentence but a private spelling of a row the app already owns — a bare `HStack`
    /// of glyph-plus-`Text`, or in the templates pane a naked `Text` in no row at all. So this
    /// asserts the replacement: every one of them is a `CadenceSettingsNoticeRow` now.
    ///
    /// Counts rather than presence, for the reason `theSevenPanesReadTheSharedFieldVocabulary`
    /// gives: a presence check stays green when one of several call sites reverts.
    @Test func theEmptySettingsCardsAreEachDrawnOnTheSharedNoticeRow() throws {
        for (path, expected) in [
            // The access verdict and the empty Reminder Lists card.
            ("Cadence/macOS/Views/SettingsRemindersSection.swift", 2),
            // Contexts and Inactive Lists — plus, since T-543 and T-545, the calendar access
            // verdict and the empty Apple-calendars card, which were the last two hand-built rows
            // in this file. Four, exactly: an aggregate that still totals four cannot tell you the
            // four are where you left them, so the shapes they replaced are named below.
            ("Cadence/macOS/Views/SettingsListManagementSections.swift", 4),
            ("Cadence/macOS/Views/SettingsTemplatesSection.swift", 1),
        ] {
            let code = try Self.strippedSource(at: path)
            let actual = code.components(separatedBy: "CadenceSettingsNoticeRow(").count - 1
            #expect(actual == expected, "\(path) draws \(actual) shared notice rows, expected \(expected)")
        }

        // And the shapes they replaced are gone from those files, so the count above is a
        // substitution rather than an addition. The templates pane's was the starkest: a `Text` in
        // no row at all, which is why its needle is the literal it used to hold.
        let templates = try Self.strippedSource(at: "Cadence/macOS/Views/SettingsTemplatesSection.swift")
        #expect(templates.contains("Text(\"No templates available\")") == false)
        let lists = try Self.strippedSource(at: "Cadence/macOS/Views/SettingsListManagementSections.swift")
        #expect(lists.contains("Image(systemName: \"archivebox\")") == false)
        #expect(lists.contains("Image(systemName: \"square.stack.3d.up\")") == false)
        // T-545's, and T-543's: the empty calendars card drew a bare glyph-plus-`Text` HStack and
        // the access card drew a private near-copy of the notice row, both in this same file.
        #expect(lists.contains("Image(systemName: \"calendar\")") == false)
        #expect(lists.contains("Image(systemName: \"exclamationmark.triangle.fill\")") == false)
    }

    /// The work-hours row's **title** is one string; its subtitle deliberately is not.
    ///
    /// The pair was found by the same sweep as the rest and is converged only as far as the check
    /// justified. macOS's sentence says "Calendar and Timeline day columns gently highlight …" and
    /// iOS's says "Calendar day columns gently highlight …" — so this asserts the title converged
    /// *and* that the two subtitles are still each spelled at their own call site, which is what
    /// stops a later pass reading this test as "the row is fully shared" and collapsing the
    /// sentences too. They name different surfaces because the surfaces differ (T-544): the phone
    /// draws the band on the Calendar's day columns and nowhere else.
    @Test func bothWorkHoursRowsReadOneWorkdayBoundaryTitle() throws {
        for path in Self.workHoursSurfaces {
            let code = try Self.strippedSource(at: path)
            #expect(
                code.contains("CadenceCalendarSettingsCopy.workdayBoundaryTitle"),
                "\(path) does not read the shared workday-boundary title"
            )
            #expect(
                !code.contains("\"Workday boundary\""),
                "\(path) still spells \"Workday boundary\" beside the constant that holds it"
            )
            #expect(
                code.contains("gently highlight \\(workHoursLabel)."),
                "\(path) no longer states the window under the title, so the pair below is moot"
            )
        }

        // The half that stays *different*, pinned as different rather than as either spelling. If
        // a later pass converges them, this fails and the decision gets made in the open. T-544
        // decided the Mac's wording — see `theMacWorkHoursSentenceNamesEverySurfaceThatDrawsTheBand`
        // for why it names two surfaces and the phone's names one.
        let mac = try Self.strippedSource(at: Self.workHoursSurfaces[0])
        let phone = try Self.strippedSource(at: Self.workHoursSurfaces[1])
        #expect(mac.contains("Calendar and Timeline day columns gently highlight"))
        #expect(phone.contains("Calendar day columns gently highlight"))
        #expect(
            mac.contains("Weekly calendar views") == false,
            "the Mac's work-hours sentence is back to naming a surface that does not draw the band"
        )
    }

    // MARK: - The sweep is what stops a thirteenth spelling

    /// **Every converged string is visible to `CadenceSharedConstantReuseSweepTests`.**
    ///
    /// This is the point of declaring them rather than pinning the pair with a test: the sweep
    /// harvests `Cadence/Shared/` and `Cadence/Models/` for `static let`s of 12 characters or more
    /// and fails on any file outside the declaration that types one, so a *third* surface spelling
    /// "Enable reminders" is caught by machinery that already exists. A constant the harvest cannot
    /// see is guarded only by the two tests above, which say nothing about a file they do not name.
    ///
    /// The harvest is asked for name, literal **and** declaring file: the file is what the sweep
    /// subtracts when it excludes the declaration from its own hit list, so a constant harvested
    /// from the wrong path would be a sweep that forgives the wrong call site.
    @Test func everyConvergedSettingsStringIsHarvestedByTheSharedConstantSweep() throws {
        let harvested = try cadenceSharedStringConstants()
        #expect(harvested.count >= 60, "non-vacuity: the harvest returned \(harvested.count) constants")

        // Built by accumulation rather than as one `+`-chained literal: the chained form
        // type-checked for minutes and then failed with "unable to type-check this expression in
        // reasonable time" once T-599 added a fourth term.
        typealias Registration = (name: String, literal: String, declaredIn: String)
        let settingsCopy = "Cadence/Shared/CadenceSettingsSectionCopy.swift"
        let linkHealth = "Cadence/Shared/CadenceCalendarLinkHealth.swift"

        // The constant's *name* is read off the expression the surfaces are asserted to call, so
        // a rename cannot leave this list describing constants that no longer exist.
        func registrations(
            of pairs: [(expression: String, literal: String)],
            declaredIn path: String
        ) -> [Registration] {
            pairs.compactMap { pair in
                let parts = pair.expression.split(separator: ".")
                guard parts.count == 2 else { return nil }
                return (name: String(parts[1]), literal: pair.literal, declaredIn: path)
            }
        }

        var expected: [Registration] = [
            (name: "brokenLinksSectionTitle", literal: "Broken Calendar Links", declaredIn: linkHealth),
            (name: "noRelinkTargetsLabel", literal: "No Apple calendars available", declaredIn: linkHealth),
            (name: "workdayBoundaryTitle", literal: "Workday boundary", declaredIn: settingsCopy),
            // T-577's. It was typed in `iOSSettingsTemplateAndListSections` alone, so macOS
            // getting the same fallback would have made it a second inline copy — the shape this
            // file exists to remove — rather than a shared rule. Harvested, so a third surface
            // spelling it out is a sweep hit rather than a re-read of the same audit.
            (name: "noParentListSubtitle", literal: "No parent list", declaredIn: settingsCopy)
        ]
        expected += registrations(
            of: Self.calendarPairs.filter { $0.expression.hasPrefix("CadenceCalendarSettingsCopy.") },
            declaredIn: settingsCopy
        )
        expected += registrations(of: Self.notificationPairs, declaredIn: settingsCopy)
        // T-599's four. The registration is the point of the ticket rather than a formality: each
        // of these is now spelled once, so a *third* surface typing one out is a sweep hit instead
        // of the next audit's finding.
        expected += registrations(
            of: Self.tagPairs + Self.templatePairs + Self.aiPairs,
            declaredIn: settingsCopy
        )
        // T-600(b)'s, for the same reason. The literals are read off the compiled constants rather
        // than restated: what this asserts is that the harvest *sees* each name, and the values
        // are pinned by `theCompiledSettingsCopyStillSaysWhatBothSurfacesUsedToSpell`.
        expected += [
            (name: "remindersTitle", literal: CadenceSettingsEmptyStateCopy.remindersTitle, declaredIn: settingsCopy),
            (
                name: "remindersSubtitle",
                literal: CadenceSettingsEmptyStateCopy.remindersSubtitle,
                declaredIn: settingsCopy
            ),
            (name: "contextsTitle", literal: CadenceSettingsEmptyStateCopy.contextsTitle, declaredIn: settingsCopy),
            (
                name: "contextsSubtitle",
                literal: CadenceSettingsEmptyStateCopy.contextsSubtitle,
                declaredIn: settingsCopy
            ),
            (
                name: "inactiveListsSectionTitle",
                literal: CadenceSettingsEmptyStateCopy.inactiveListsSectionTitle,
                declaredIn: settingsCopy
            ),
            (
                name: "inactiveListsTitle",
                literal: CadenceSettingsEmptyStateCopy.inactiveListsTitle,
                declaredIn: settingsCopy
            ),
            (
                name: "inactiveListsSubtitle",
                literal: CadenceSettingsEmptyStateCopy.inactiveListsSubtitle,
                declaredIn: settingsCopy
            ),
            (name: "templatesTitle", literal: CadenceSettingsEmptyStateCopy.templatesTitle, declaredIn: settingsCopy),
            (
                name: "templatesSubtitle",
                literal: CadenceSettingsEmptyStateCopy.templatesSubtitle,
                declaredIn: settingsCopy
            )
        ]
        // T-546's six. Declared as plain literals rather than composed from a `sectionTitle(_:of:)`
        // helper precisely so this registration is possible: the harvest reads
        // `static let x = "…"` and cannot see an interpolated title, which is the recorded gap
        // behind `CadenceEmptyStateCopy.goalsTitle`.
        expected += registrations(of: Self.lifecyclePairs, declaredIn: settingsCopy)

        for entry in expected {
            #expect(
                harvested.contains(
                    CadenceSharedStringConstant(
                        name: entry.name,
                        literal: entry.literal,
                        declaredIn: entry.declaredIn
                    )
                ),
                """
                the shared-constant harvest does not see `\(entry.name)` in \(entry.declaredIn), so \
                the sweep would not catch a third surface typing "\(entry.literal)" out again.
                """
            )
        }
    }

    /// The sweep's detector, checked against these constants specifically rather than trusted.
    ///
    /// Harvest membership alone would be satisfied by a detector that had stopped discriminating —
    /// a clean repo and a blind scan look identical from outside, which is the reason the sweep
    /// runs through `CadenceScanInstrument` in the first place. The witnesses here are the nearest
    /// possible miss: the same row, once typed and once read off the constant, with the constant's
    /// text also present in the negative witness as prose.
    @Test func theSweepDetectorStillSeparatesAConvergedConstantFromItsLiteral() throws {
        let literal = Self.notificationPairs[0].literal
        let instrument = try CadenceScanInstrument(
            "converged settings string re-typed: \(literal)",
            fires: """
            struct Pane {
                let title = "\(literal)"
            }
            """,
            andNotOn: """
            struct Pane {
                // Says "\(literal)", from CadenceNotificationSettingsCopy.
                let title = CadenceNotificationSettingsCopy.remindersToggleTitle
            }
            """,
            by: { CadenceSourceScan.strippingComments($0).contains("\"\(literal)\"") }
        )

        // Against the tree, not only against the fixtures: the declaring file must fire (it is the
        // one place the literal is written) and both converged surfaces must not.
        #expect(instrument.fires(on: try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceSettingsSectionCopy.swift")))
        for path in Self.notificationSurfaces {
            #expect(
                instrument.fires(on: try CadenceSourceScan.sourceFile(path)) == false,
                "\(path) still types the literal the sweep would now report"
            )
        }
    }

    // MARK: - The divergence the pairing exposed

    /// **The Mac's calendar link menu had a tooltip and no accessible name; the phone's had a name.**
    ///
    /// Found by converging `connectMenuLabel`: both surfaces passed the same sentence to different
    /// modifiers. On iOS it was `.accessibilityLabel`; on macOS it was `.help`, which is the pointer
    /// only — so the one control on the row that says what the row's link *does* announced its SF
    /// Symbol name to assistive technology. That is exactly the T-472 defect, two screens away from
    /// where T-472 fixed it and outside the sweep that guards it (that sweep is scoped to the
    /// markdown toolbar and `LinksView`). The phone was right; macOS now reads the shared helper.
    ///
    /// **What this claims is that the label is set**, in the shape SwiftUI reads it from — the same
    /// caveat `CadenceControlAccessibilityLabelTests` states in its own header. Nothing in this target can
    /// launch the app, so what VoiceOver announces is not measured here.
    @Test func theMacCalendarConnectMenuIsNamedRatherThanOnlyTooltipped() throws {
        let mac = try Self.strippedSource(at: "Cadence/macOS/Views/SettingsListManagementSections.swift")
        #expect(
            mac.contains(".cadenceControlLabel(CadenceCalendarSettingsCopy.connectMenuLabel)"),
            "the Mac's calendar link menu is back to a tooltip with no accessible name"
        )
        #expect(
            CadenceSourceScan.matchCount("\\.help\\(CadenceCalendarSettingsCopy", in: mac) == 0,
            "the Mac's link menu names itself to the pointer only again"
        )

        // The helper really does set both, from one string — without this the assertion above pins
        // a spelling whose meaning lives in another file.
        let buttons = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CadenceButtons.swift")
        )
        let body = try #require(
            CadenceSourceScan.functionBody(named: "cadenceControlLabel", in: buttons),
            "cadenceControlLabel(_:) is gone"
        )
        #expect(body.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(body.contains(".help(accessibilityLabel)"))

        // The phone's half, which was already right and is the reason macOS changed rather than
        // iOS. `cadenceControlLabel` is macOS-only — there is no pointer on a phone — so the two
        // surfaces reach the same name through different modifiers on purpose.
        let phone = try Self.strippedSource(at: "Cadence/iOS/iOSCalendarSettingsSection.swift")
        #expect(phone.contains(".accessibilityLabel(CadenceCalendarSettingsCopy.connectMenuLabel)"))
    }

    // MARK: - Settings → Notifications heads itself with nothing

    /// **T-578.** The phone headed Settings → Notifications **"Reminders"** — which on iOS is the
    /// name of the *Apple Reminders* category two rows away in the same settings list, whose own
    /// section is headed "Apple Reminders". One word, two meanings, two rows apart.
    ///
    /// macOS drew no heading there at all (`CadenceFieldSection(title: nil)`), and that is the one
    /// that is right rather than the one that is missing something: the pane holds a single card,
    /// and `iOSSettingsPageHeader` directly above it already reads "Notifications". Renaming the
    /// heading to "Notifications" would have put the category title on the screen twice, which is
    /// the standing rule about a page header describing the page you are already on.
    @Test func theIOSNotificationsPaneDrawsNoHeadingOfItsOwn() throws {
        let phone = try Self.strippedSource(at: Self.notificationSurfaces[1])
        #expect(phone.contains("struct iOSNotificationsSettingsSection"), "non-vacuity: wrong file")
        #expect(
            CadenceSourceScan.matchCount("CadenceSettingsSectionLabel\\(", in: phone) == 0,
            "Settings → Notifications heads itself again (T-578)"
        )

        // The word is returned to the category it names rather than banished. Without this, the
        // assertion above is satisfiable by deleting both headings, which loses the distinction
        // instead of drawing it.
        let reminders = try Self.strippedSource(at: "Cadence/iOS/iOSRemindersSettingsSection.swift")
        #expect(reminders.contains("CadenceSettingsSectionLabel(text: \"Apple Reminders\")"))

        // The shape the phone now matches, asserted rather than assumed — this is the whole of the
        // ticket's judgement that macOS was right.
        let mac = try Self.strippedSource(at: Self.notificationSurfaces[0])
        #expect(mac.contains("CadenceFieldSection(title: nil)"))
    }

    // MARK: - Settings → Lists: a row with a name and a second line

    /// **T-577.** A project filed under neither a context nor an area got a subtitle of `""`,
    /// because macOS built the line as `[context, area].compactMap { $0 }.joined(separator: " • ")`
    /// and an empty array joins to the empty string. Not a hypothetical: T-558/T-559 establish that
    /// context-less lists exist, and this is the screen a completed or archived one is reached from.
    ///
    /// A value test rather than a scan, because the defect was in the *rule* and not in which words
    /// the rule was given. The empty-string cases are the ones that matter: `compactMap` alone
    /// drops `nil` and keeps `""`, so a named area under an unnamed context read " • Launch".
    @Test func aParentlessProjectRowSaysSoRatherThanShowingABlankLine() {
        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: nil, areaName: nil) == "No parent list")
        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: "", areaName: "") == "No parent list")
        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: "", areaName: nil) == "No parent list")

        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: "Work", areaName: nil) == "Work")
        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: nil, areaName: "Launch") == "Launch")
        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: "", areaName: "Launch") == "Launch")
        #expect(CadenceListSettingsCopy.parentSubtitle(contextName: "Work", areaName: "") == "Work")

        #expect(
            CadenceListSettingsCopy.parentSubtitle(contextName: "Work", areaName: "Launch") == "Work • Launch"
        )
    }

    /// The other half of T-577, and the half the file contradicted itself about: macOS passed
    /// `area.name` and `project.name` to the row raw, twelve lines under an *area* subtitle branch
    /// that already knew to fall back to "No context". An unnamed list drew a row with no title.
    ///
    /// A scan, because a row title is a `String` argument to a `View` initialiser inside a `body`
    /// with no seam to call — and because `Cadence/iOS/` is not compiled by this target at all, so
    /// the phone's half can only be read as text. Both directions per file: reading the fallback
    /// and no longer passing the name through.
    @Test func neitherInactiveListSurfaceDrawsARowTitledWithARawName() throws {
        for path in Self.inactiveListSurfaces {
            let code = try Self.strippedSource(at: path)
            #expect(code.contains("lifecycleCard"), "non-vacuity: \(path) draws no inactive-list card")

            #expect(
                code.contains("CadenceTitleNormalization.defaultAreaName"),
                "\(path) draws an unnamed area with no fallback again"
            )
            #expect(
                code.contains("CadenceTitleNormalization.defaultProjectName"),
                "\(path) draws an unnamed project with no fallback again"
            )
            #expect(
                code.contains("CadenceListSettingsCopy.parentSubtitle"),
                "\(path) builds the project subtitle itself again"
            )

            for raw in ["area", "project"] {
                #expect(
                    CadenceSourceScan.matchCount("title: \(raw)\\.name", in: code) == 0,
                    "\(path) titles a lifecycle row with \(raw).name raw"
                )
            }
            // The join lives in one place now, so neither surface may spell it. This is the exact
            // expression that produced the blank line.
            #expect(
                CadenceSourceScan.matchCount("joined\\(separator: \" • \"\\)", in: code) == 0,
                "\(path) joins a parent subtitle itself again"
            )
        }
    }

    // MARK: - Values, not source shape

    /// The one assertion here that is not a scan: the constants the Mac target **compiles** still
    /// hold the strings both surfaces used to spell.
    ///
    /// Everything above would stay green if a constant's value were edited, because a call site
    /// reading `accessRequiredTitle` reads it whatever it says. This is what makes the convergence
    /// a de-duplication rather than a rewrite: these are the strings that shipped.
    @Test func theCompiledSettingsCopyStillSaysWhatBothSurfacesUsedToSpell() {
        #expect(CadenceCalendarLinkHealth.brokenLinksSectionTitle == "Broken Calendar Links")
        #expect(CadenceCalendarLinkHealth.noRelinkTargetsLabel == "No Apple calendars available")
        #expect(CadenceCalendarSettingsCopy.accessDeniedTitle == "Calendar access denied")
        #expect(CadenceCalendarSettingsCopy.accessRequiredTitle == "Calendar access required")
        #expect(CadenceCalendarSettingsCopy.noConnectableListsLabel == "No active areas or projects")
        #expect(CadenceCalendarSettingsCopy.unconnectedSummary == "Not connected to any area or project")
        #expect(CadenceCalendarSettingsCopy.connectMenuLabel == "Connect to areas and projects")
        #expect(CadenceCalendarSettingsCopy.workdayBoundaryTitle == "Workday boundary")
        #expect(CadenceCalendarSettingsCopy.appleCalendarsSectionTitle == "Apple Calendars")
        // T-543. The sentence that won, and the reason to assert it by value: every scan
        // above stays green if this string is quietly rewritten back to the Mac's old
        // "Allow Cadence to create and sync calendar events."
        #expect(
            CadenceCalendarSettingsCopy.accessRequiredDetail
                == "Allow Cadence to show events and connect Apple calendars to areas or projects."
        )

        // T-599. Each of these is the spelling that *won*, not the one that happened to be first
        // alphabetically: the phone said "Create one or add the default set.", stopped the privacy
        // sentence at "an AI action", and called the destructive button "Delete API Key" while
        // calling the test button "Test". Editing any of these values silently changes what the
        // ticket decided, which is what a value assertion is for.
        #expect(CadenceTagSettingsCopy.emptyCatalogTitle == "No active tags")
        #expect(CadenceTagSettingsCopy.emptyCatalogSubtitle == "Create a tag or add the default set.")
        #expect(
            CadenceTemplateSettingsCopy.editScopeFootnote
                == "Templates affect future insertions only. Existing notes keep their current content."
        )
        #expect(
            CadenceAISettingsCopy.keyPrivacyDisclosure
                == """
                Stored in Keychain. Cadence sends selected note content to OpenAI only when you \
                run an AI action, such as summarizing a note or extracting task drafts.
                """
        )
        #expect(CadenceAISettingsCopy.saveAPIKeyAction == "Save API Key")
        #expect(CadenceAISettingsCopy.testConnectionAction == "Test Connection")
        #expect(CadenceAISettingsCopy.deleteAPIKeyAction == "Delete API Key")

        #expect(CadenceNotificationSettingsCopy.remindersToggleTitle == "Enable reminders")
        #expect(
            CadenceNotificationSettingsCopy.remindersToggleDetail
                == "A task's scheduled start and due date, and a habit's reminder time, notify you locally."
        )
        #expect(CadenceNotificationSettingsCopy.accessRequiredTitle == "Notification access required")
        #expect(
            CadenceNotificationSettingsCopy.accessRequiredDetail
                == "Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders."
        )
        #expect(CadenceNotificationSettingsCopy.enableNotificationsAction == "Enable Notifications")

        #expect(CadenceListSettingsCopy.noParentListSubtitle == "No parent list")

        // T-600(b). The four titles carry no full stop and the four subtitles do — macOS's
        // one-liners disagreed with each other about that, and the shape assertion is the reason
        // to write these as values rather than only scanning for the expression.
        #expect(CadenceSettingsEmptyStateCopy.remindersTitle == "No open reminders")
        #expect(
            CadenceSettingsEmptyStateCopy.remindersSubtitle
                == "Reminders you have not completed yet will be summarised here by list."
        )
        #expect(CadenceSettingsEmptyStateCopy.contextsTitle == "No active contexts")
        #expect(
            CadenceSettingsEmptyStateCopy.contextsSubtitle
                == "Create one here, then use it when making areas and projects."
        )
        #expect(CadenceSettingsEmptyStateCopy.inactiveListsSectionTitle == "Inactive Lists")
        #expect(CadenceSettingsEmptyStateCopy.inactiveListsTitle == "No completed or archived lists")
        #expect(
            CadenceSettingsEmptyStateCopy.inactiveListsSubtitle
                == "Areas and projects you complete or archive will appear here."
        )
        #expect(CadenceSettingsEmptyStateCopy.templatesTitle == "No templates available")
        #expect(CadenceSettingsEmptyStateCopy.templatesSubtitle == "Template definitions could not be loaded.")
        // T-545. The fifth pair, and the one whose macOS spelling carried the stray full
        // stop the shape loops below exist to catch.
        #expect(CadenceSettingsEmptyStateCopy.appleCalendarsTitle == "No Apple calendars found")
        #expect(
            CadenceSettingsEmptyStateCopy.appleCalendarsSubtitle
                == "Calendars available to this device will appear here."
        )

        for title in [
            CadenceSettingsEmptyStateCopy.remindersTitle,
            CadenceSettingsEmptyStateCopy.contextsTitle,
            CadenceSettingsEmptyStateCopy.inactiveListsTitle,
            CadenceSettingsEmptyStateCopy.templatesTitle,
            CadenceSettingsEmptyStateCopy.appleCalendarsTitle,
            CadenceTagSettingsCopy.emptyCatalogTitle
        ] {
            #expect(title.hasSuffix(".") == false, "\"\(title)\" is a title, not a sentence")
        }
        for subtitle in [
            CadenceSettingsEmptyStateCopy.remindersSubtitle,
            CadenceSettingsEmptyStateCopy.contextsSubtitle,
            CadenceSettingsEmptyStateCopy.inactiveListsSubtitle,
            CadenceSettingsEmptyStateCopy.templatesSubtitle,
            CadenceSettingsEmptyStateCopy.appleCalendarsSubtitle,
            CadenceTagSettingsCopy.emptyCatalogSubtitle
        ] {
            #expect(subtitle.hasSuffix("."), "\"\(subtitle)\" is a sentence and needs its full stop")
        }
    }

    // MARK: - T-544: the work-hours sentence names the surfaces that draw the band

    /// The macOS files that switch the work-hours band on. Named, not counted in aggregate: the
    /// sentence in Settings claims exactly this set, so the set is what has to be pinned.
    private static let workHoursHighlightCallSites = [
        "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
        "Cadence/macOS/Views/SchedulePanelShellViews.swift",
    ]

    /// **The Mac's subtitle said "Weekly calendar views gently highlight …" and no part of it was
    /// true.**
    ///
    /// The band is `TimelineWorkHoursHighlightLayer`, drawn inside `TimelineDayCanvas` — once, per
    /// **day column** — and only where a caller passes `showWorkHoursHighlight: true`. Exactly two
    /// callers do: `CalDayColumn`, the Calendar page's day column, and
    /// `SchedulePanelTimelineViewport`, the panel the app titles **Timeline**, which is not a
    /// calendar view at all. "Weekly" was wrong a second way: the Calendar page draws day columns
    /// at Week *and* 2 Weeks, and its Month presentation draws neither a column nor a band.
    ///
    /// This is the sentence's evidence rather than its echo. Asserting only the new wording would
    /// pin a claim about behaviour against nothing, and the old wording was wrong precisely because
    /// the code moved out from under it — so the call-site **set** is asserted exactly, and a third
    /// surface switching the band on fails here rather than making the sentence stale again.
    @Test func theMacWorkHoursSentenceNamesEverySurfaceThatDrawsTheBand() throws {
        let enablesTheBand = try CadenceScanInstrument(
            "a macOS surface switches the work-hours band on",
            fires: """
            TimelineDayCanvas(
                style: .calendar,
                showWorkHoursHighlight: true,
                showHalfHourMarks: false
            )
            """,
            andNotOn: """
            TimelineDayCanvas(
                style: .calendar,
                showWorkHoursHighlight: false,
                showHalfHourMarks: false
            )
            """,
            by: { CadenceSourceScan.codeOnly($0).contains("showWorkHoursHighlight: true") }
        )

        let hits = try enablesTheBand.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence/macOS"),
            atLeast: 200,
            including: "Cadence/macOS/Views/TimelineDayCanvas.swift",
            read: CadenceSourceScan.sourceFile
        )
        #expect(
            hits == Self.workHoursHighlightCallSites.sorted(),
            "the work-hours band is drawn by \(hits), which is not the set the Settings sentence names"
        )

        // Exact per-file counts, not a total: an aggregate of two stays green when one call site
        // reverts and the other gains a duplicate.
        for path in Self.workHoursHighlightCallSites {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount("showWorkHoursHighlight: true", in: code) == 1,
                "\(path) no longer switches the band on exactly once"
            )
        }

        // Per day column, and only there: the layer has one declaration and one call site, both in
        // the day canvas's own files.
        let canvas = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDayCanvas.swift"))
        #expect(CadenceSourceScan.matchCount("TimelineWorkHoursHighlightLayer\\(", in: canvas) == 1)
        let layers = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift")
        )
        #expect(CadenceSourceScan.matchCount("struct TimelineWorkHoursHighlightLayer", in: layers) == 1)

        // The sentence itself, whole, at its one call site.
        let mac = try Self.strippedSource(at: Self.workHoursSurfaces[0])
        #expect(
            mac.contains("Text(\"Calendar and Timeline day columns gently highlight \\(workHoursLabel).\")"),
            "the Mac's work-hours subtitle no longer names both day-column surfaces"
        )
        #expect(CadenceSourceScan.matchCount("gently highlight", in: mac) == 1)
    }

    /// The band is the same shared rule on both platforms, and neither subtitle mentions the half
    /// of it that hides the band two days a week.
    ///
    /// Recorded rather than fixed (T-696): `shouldShowHighlight(on:)` is the weekend rule, both
    /// surfaces call it, and both sentences read as unconditional. This pins the behaviour so the
    /// copy ticket has something to point at.
    @Test func theWorkHoursBandIsSuppressedAtTheWeekendOnBothSurfaces() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 29 // Saturday
        let calendar = Calendar(identifier: .gregorian)
        let saturday = try #require(calendar.date(from: components))
        let monday = try #require(calendar.date(byAdding: .day, value: 2, to: saturday))

        #expect(CalendarWorkHoursPreferences.shouldShowHighlight(on: saturday, calendar: calendar) == false)
        #expect(CalendarWorkHoursPreferences.shouldShowHighlight(on: monday, calendar: calendar))

        for path in ["Cadence/macOS/Views/TimelineDayCanvas.swift", "Cadence/iOS/iOSCalendarTimelineViews.swift"] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount("CalendarWorkHoursPreferences.shouldShowHighlight", in: code) == 1,
                "\(path) no longer gates the band on the shared weekend rule exactly once"
            )
        }
    }

    // MARK: - T-546: six lifecycle eyebrows, spelled once

    /// The six lifecycle section titles, as the expression every call site must read and the
    /// literal no surface may still type.
    private static let lifecyclePairs: [(expression: String, literal: String)] = [
        ("CadenceListLifecycleSectionCopy.activeContexts", "Active Contexts"),
        ("CadenceListLifecycleSectionCopy.archivedContexts", "Archived Contexts"),
        ("CadenceListLifecycleSectionCopy.completedAreas", "Completed Areas"),
        ("CadenceListLifecycleSectionCopy.archivedAreas", "Archived Areas"),
        ("CadenceListLifecycleSectionCopy.completedProjects", "Completed Projects"),
        ("CadenceListLifecycleSectionCopy.archivedProjects", "Archived Projects"),
    ]

    /// Which file draws which group, and how many times. Settings → Contexts and Settings → Lists
    /// are one pane on the Mac and two files on the phone, so the split is not symmetric.
    private static let lifecycleSurfaces: [(path: String, expressions: [String])] = [
        (
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            [
                "CadenceListLifecycleSectionCopy.activeContexts",
                "CadenceListLifecycleSectionCopy.archivedContexts",
                "CadenceListLifecycleSectionCopy.completedAreas",
                "CadenceListLifecycleSectionCopy.archivedAreas",
                "CadenceListLifecycleSectionCopy.completedProjects",
                "CadenceListLifecycleSectionCopy.archivedProjects",
            ]
        ),
        (
            "Cadence/iOS/iOSSettingsView.swift",
            [
                "CadenceListLifecycleSectionCopy.activeContexts",
                "CadenceListLifecycleSectionCopy.archivedContexts",
            ]
        ),
        (
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
            [
                "CadenceListLifecycleSectionCopy.completedAreas",
                "CadenceListLifecycleSectionCopy.archivedAreas",
                "CadenceListLifecycleSectionCopy.completedProjects",
                "CadenceListLifecycleSectionCopy.archivedProjects",
            ]
        ),
    ]

    /// **The twelve call sites read the six names.**
    ///
    /// A *seventh* surface typing one of the six out again is caught by machinery that already
    /// exists — `CadenceSharedConstantReuseSweepTests.noCallSiteRetypesASharedStringConstant`
    /// sweeps all of `Cadence/` for every harvested constant, and
    /// `everyConvergedSettingsStringIsHarvestedByTheSharedConstantSweep` below is what proves the
    /// harvest sees these six. This test is the other half: the call sites that exist today.
    ///
    /// Asserting the constants merely *exist* and hold the right words would stay green over a
    /// tree where every call site had gone back to typing the literal, which is the state this
    /// ticket found. So each file is checked for the exact expression an exact number of times —
    /// once where it draws the group, **zero** where it does not — and for the literal being gone.
    @Test func everyLifecycleSectionLabelIsReadRatherThanTypedAtAllTwelveCallSites() throws {
        for surface in Self.lifecycleSurfaces {
            let code = try Self.strippedSource(at: surface.path)
            for pair in Self.lifecyclePairs {
                let expected = surface.expressions.contains(pair.expression) ? 1 : 0
                let pattern = NSRegularExpression.escapedPattern(for: pair.expression)
                #expect(
                    CadenceSourceScan.matchCount(pattern, in: code) == expected,
                    "\(surface.path) reads \(pair.expression) \(CadenceSourceScan.matchCount(pattern, in: code)) times, not \(expected)"
                )
                #expect(
                    code.contains("\"\(pair.literal)\"") == false,
                    "\(surface.path) still types \"\(pair.literal)\" beside the constant that holds it"
                )
            }
        }
    }

    /// The six titles, read off the compiled constants, and the rule that decides what a seventh
    /// would say.
    ///
    /// **This is the room T-690 needs.** `ProjectStatus` has five cases; Settings shows two of
    /// them, so a `.paused` or `.cancelled` project reaches no group on either platform and can be
    /// neither reopened nor deleted from the only screen that lists inactive lists. Every title
    /// here is `"<status> <plural noun>"` with the status word taken from
    /// `CadenceListSearchLifecycle` — the type that already carries all five spellings — so
    /// `pausedProjects` and `cancelledProjects` are two more constants in one voice rather than two
    /// more copy decisions.
    @Test func everyLifecycleSectionTitleFollowsTheStatusThenNounRule() {
        #expect(CadenceListLifecycleSectionCopy.activeContexts == "\(CadenceListSearchLifecycle.active.statusLabel) Contexts")
        #expect(CadenceListLifecycleSectionCopy.archivedContexts == "\(CadenceListSearchLifecycle.archived.statusLabel) Contexts")
        #expect(CadenceListLifecycleSectionCopy.completedAreas == "\(CadenceListSearchLifecycle.completed.statusLabel) Areas")
        #expect(CadenceListLifecycleSectionCopy.archivedAreas == "\(CadenceListSearchLifecycle.archived.statusLabel) Areas")
        #expect(CadenceListLifecycleSectionCopy.completedProjects == "\(CadenceListSearchLifecycle.completed.statusLabel) Projects")
        #expect(CadenceListLifecycleSectionCopy.archivedProjects == "\(CadenceListSearchLifecycle.archived.statusLabel) Projects")

        // The two the rule already decides and Settings does not yet show (T-690).
        #expect(CadenceListSearchLifecycle.paused.statusLabel == "Paused")
        #expect(CadenceListSearchLifecycle.cancelled.statusLabel == "Cancelled")
    }

    // MARK: - Non-vacuity

    /// The scans above reach real files, and the reader they use keeps literals.
    ///
    /// The second half is the specific trap: `codeOnly` blanks string literals as well as comments,
    /// so every `contains("\"…\"")` assertion in this file would be vacuously false against it and
    /// every `!contains` vacuously true. Pinning that the two readers genuinely differ is what
    /// stops the pairing collapsing into one.
    @Test func theSettingsCopyScanReadsLiteralsRatherThanBlankingThem() throws {
        var readable = Self.calendarSurfaces + Self.notificationSurfaces + Self.workHoursSurfaces
        readable += Self.tagSurfaces + Self.templateSurfaces + Self.aiSurfaces
        readable += Self.lifecycleSurfaces.map(\.path)
        for path in readable {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path) lost no comment text; the stripper did not run")
            #expect(stripped.count == raw.count, "the stripper no longer blanks in place")
        }

        // The helper every scan above goes through, pinned on a literal it must keep. Swapping it
        // to `codeOnly` would turn each `!contains("\"…\"")` assertion vacuously true and leave
        // this suite green over a file that had reverted every one of them.
        //
        // The witness was `"Reminders"` until T-578, which was that file's section heading — the
        // name of the *Apple Reminders* category two rows away — and is now deleted rather than
        // renamed, because the pane holds one card under a page header that already says
        // Notifications. The glyph is the replacement: still a literal in that file, and one no
        // copy decision can take away.
        #expect(
            try Self.strippedSource(at: Self.notificationSurfaces[1]).contains("\"bell.fill\""),
            "the shared reader blanks literals, so every literal assertion in this file is vacuous"
        )

        // The readers, side by side on one line, so the claim does not depend on which file it was
        // measured over.
        let sample = "let title = \"Enable reminders\" // says \"Enable reminders\""
        #expect(CadenceSourceScan.strippingComments(sample).contains("\"Enable reminders\""))
        #expect(CadenceSourceScan.codeOnly(sample).contains("\"Enable reminders\"") == false)
    }

    private static func strippedSource(at path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }
}
