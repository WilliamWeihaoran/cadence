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

    /// The work-hours row's **title** is one string; its subtitle deliberately is not.
    ///
    /// The pair was found by the same sweep as the rest and is converged only as far as the check
    /// justified. macOS's sentence says "Weekly calendar views gently highlight …" and iOS's says
    /// "Calendar day columns gently highlight …" — so this asserts the title converged *and* that
    /// the two subtitles are still each spelled at their own call site, which is what stops a later
    /// pass reading this test as "the row is fully shared" and collapsing the sentences too.
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

        // The unresolved half, pinned as *different* rather than as either spelling. If a later
        // pass converges them, this fails and the decision gets made in the open.
        let mac = try Self.strippedSource(at: Self.workHoursSurfaces[0])
        let phone = try Self.strippedSource(at: Self.workHoursSurfaces[1])
        #expect(mac.contains("Weekly calendar views gently highlight"))
        #expect(phone.contains("Calendar day columns gently highlight"))
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

        let expected: [(name: String, literal: String, declaredIn: String)] =
            [
                ("brokenLinksSectionTitle", "Broken Calendar Links", "Cadence/Shared/CadenceCalendarLinkHealth.swift"),
                ("noRelinkTargetsLabel", "No Apple calendars available", "Cadence/Shared/CadenceCalendarLinkHealth.swift"),
            ]
            + Self.calendarPairs
                .filter { $0.expression.hasPrefix("CadenceCalendarSettingsCopy.") }
                .map {
                    (
                        String($0.expression.dropFirst("CadenceCalendarSettingsCopy.".count)),
                        $0.literal,
                        "Cadence/Shared/CadenceSettingsSectionCopy.swift"
                    )
                }
            + [(
                "workdayBoundaryTitle",
                "Workday boundary",
                "Cadence/Shared/CadenceSettingsSectionCopy.swift"
            )]
            + Self.notificationPairs.map {
                (
                    String($0.expression.dropFirst("CadenceNotificationSettingsCopy.".count)),
                    $0.literal,
                    "Cadence/Shared/CadenceSettingsSectionCopy.swift"
                )
            }

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
    }

    // MARK: - Non-vacuity

    /// The scans above reach real files, and the reader they use keeps literals.
    ///
    /// The second half is the specific trap: `codeOnly` blanks string literals as well as comments,
    /// so every `contains("\"…\"")` assertion in this file would be vacuously false against it and
    /// every `!contains` vacuously true. Pinning that the two readers genuinely differ is what
    /// stops the pairing collapsing into one.
    @Test func theSettingsCopyScanReadsLiteralsRatherThanBlankingThem() throws {
        for path in Self.calendarSurfaces + Self.notificationSurfaces + Self.workHoursSurfaces {
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
