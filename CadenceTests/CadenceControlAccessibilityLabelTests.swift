import Foundation
import Testing
@testable import Cadence

/// **Two controls whose accessible name was never set** (T-472, T-484), pinned as source shape.
///
/// What these tests claim, and the limit is the point: they assert that the *label is set*, in the
/// shape SwiftUI reads it from. They do **not** assert what VoiceOver announces. Nothing in this
/// target can launch the app, so an announcement is not a fact any test here has measured — the
/// audit that filed both tickets marked its own VoiceOver claims as inferred for the same reason,
/// and a test that restated the inference would be dressing a read as a measurement.
///
/// Both rules are source scans rather than view tests because both live on a SwiftUI modifier
/// chain. `.accessibilityLabel` writes into an `AccessibilityAttachmentModifier` that no headless
/// test can query, and half the offenders (`Cadence/iOS/`) are not even compiled by this target.
///
/// Each sweep runs through a `CadenceScanInstrument`, so a detector that has stopped discriminating
/// cannot reach the walk — "no offenders" is what a clean repo and a blind scan both look like.
/// The suite name matches this file's basename. It was `ControlAccessibilityLabelTests` —
/// dropping the `Cadence` prefix the file carries — which matters because `-only-testing:` takes
/// the **suite** name, not the file name, and a name that matches nothing is not an error:
/// xcodebuild reports `Executed 0 tests`, `** TEST SUCCEEDED **` and exits 0. Scoping a run by
/// this file's name therefore ran nothing and called it a pass (T-556).
struct CadenceControlAccessibilityLabelTests {

    // MARK: - T-472: the markdown toolbar's icon-only buttons

    private static let toolbarPath = "Cadence/macOS/Editor/MarkdownEditorView.swift"

    /// The three views that draw the markdown toolbar. Every one of them had a `.help(...)` and
    /// nothing else, so the pointer got a sentence and assistive tech got the SF Symbol name.
    private static let toolbarButtonTypes = [
        "MarkdownReferenceMenuButton",
        "MarkdownToolbarButton",
        "MarkdownToolbarTextButton",
    ]

    /// The sweep. Scoped to each button's own `struct` body: scoping it to the file would let one
    /// labelled view elsewhere in it answer for all three.
    @Test func everyMarkdownToolbarButtonPairsItsTooltipWithAnAccessibleName() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile(Self.toolbarPath)
        )
        let offenders = try tooltipWithoutNameInstrument().sweep(
            Self.toolbarButtonTypes,
            atLeast: 3,
            including: "MarkdownToolbarTextButton",
            read: { try Self.bodyOfStruct($0, in: source) }
        )
        #expect(
            offenders.isEmpty,
            "markdown toolbar view with a tooltip and no accessible name: \(offenders)"
        )
    }

    /// Non-vacuity for the sweep above: it is only worth running over views that actually carry a
    /// tooltip. If `.help` ever leaves these three, the sweep would pass by having nothing to say.
    @Test func allThreeMarkdownToolbarButtonsStillCarryATooltip() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile(Self.toolbarPath)
        )
        for name in Self.toolbarButtonTypes {
            let body = try Self.bodyOfStruct(name, in: source)
            #expect(body.contains(".help("), "\(name) no longer has a tooltip to pair")
            #expect(body.contains(".accessibilityLabel("), "\(name) has no accessible name")
        }
    }

    /// The fixture pair says the detector can still tell the two shapes apart; this says the shape
    /// it treats as correct is the one the repo already had. `CadenceIconButton` is the view both
    /// tickets point at as the pattern, and it does carry a `.help(...)`, so a detector that fired
    /// on any tooltip at all would fail here.
    @Test func theTooltipDetectorLeavesTheRepoPatternAlone() throws {
        let buttons = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CadenceButtons.swift")
        )
        let body = try Self.bodyOfStruct("CadenceIconButton", in: buttons)
        #expect(body.contains(".help("), "non-vacuity: CadenceIconButton no longer has a tooltip")
        let instrument = try tooltipWithoutNameInstrument()
        #expect(instrument.fires(on: body) == false)
    }

    /// The ticket's third point, which the sweep cannot see: `MarkdownToolbarTextButton` draws
    /// visible text, so it is not icon-only, but `H1` is not a name. `.accessibilityLabel`
    /// *replaces* a label's own text rather than appending to it, so naming it "Heading 1" is a
    /// substitution and not a double announcement.
    @Test func theTwoHeadingButtonsAreNamedForTheHeadingRatherThanForTheGlyph() throws {
        let text = try CadenceSourceScan.sourceFile(Self.toolbarPath)
        #expect(text.contains(#"MarkdownToolbarTextButton(title: "H1", accessibilityLabel: "Heading 1")"#))
        #expect(text.contains(#"MarkdownToolbarTextButton(title: "H2", accessibilityLabel: "Heading 2")"#))
    }

    /// True when a view applies a tooltip and never states an accessible name.
    ///
    /// The negative witness is the *nearest* miss on purpose: it is the same button, same tooltip,
    /// with the one modifier added. A detector keyed on anything else about these two — the symbol
    /// name, the button style — would separate them for the wrong reason.
    private func tooltipWithoutNameInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "tooltip without an accessible name",
            fires: """
            Button(action: action) {
                Image(systemName: systemName)
            }
            .buttonStyle(.cadencePlain)
            .help(accessibilityLabel)
            """,
            andNotOn: """
            Button(action: action) {
                Image(systemName: systemName)
            }
            .buttonStyle(.cadencePlain)
            .accessibilityLabel(accessibilityLabel)
            .help(accessibilityLabel)
            """,
            by: { $0.contains(".help(") && !$0.contains(".accessibilityLabel(") }
        )
    }

    // MARK: - The saved-links screen's icon-only buttons

    /// Same defect as T-472, one screen over: `macOS/Views/LinksView.swift` drew three icon-only
    /// buttons — add, open, delete — with **no `.accessibilityLabel` and no `.help` at all**, so
    /// there was not even a tooltip for the sweep above to pair a name with.
    ///
    /// The fix is `cadenceControlLabel(_:)`, declared beside `CadenceIconButton`, which is the one
    /// place in the repo that already passed a single string to both modifiers. Two claims here and
    /// no third: **the name is set**, and it is set on the button rather than somewhere in the file.
    /// What VoiceOver announces is not measured — see this suite's header.
    @Test func everyIconOnlyButtonInTheSavedLinksScreenCarriesAName() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.contains("struct LinksView: View"), "the scan read the wrong file")

        // The three buttons, by the symbol each draws and the name it now carries. Stated as pairs
        // rather than counted: a count stays green when two buttons share one name by accident.
        for (symbol, label) in [
            ("plus", #"showingAdd ? "Cancel adding a link" : "Add link""#),
            ("arrow.up.right.square", #""Open link""#),
            ("trash", #""Delete link""#),
        ] {
            #expect(
                source.contains(#"Image(systemName: "\#(symbol)")"#),
                "LinksView no longer draws the \(symbol) button"
            )
            #expect(
                source.contains(".cadenceControlLabel(\(label))"),
                "the \(symbol) button in LinksView has no accessible name"
            )
        }

        // Every icon-only *button* is named. The fourth `Image(systemName:)` in the file is the
        // row's leading "link" glyph, which is decorative — it sits beside the title and URL it
        // would otherwise repeat — so it is deliberately not in the list above.
        #expect(
            CadenceSourceScan.matchCount(#"Image\(systemName:"#, in: source) == 4,
            "LinksView's icon inventory changed; recheck which of them are buttons"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.cadenceControlLabel\("#, in: source) == 3,
            "a button in LinksView was added or unnamed"
        )
    }

    /// And the helper really does set both, from one string. Without this the test above pins a
    /// spelling whose meaning lives in another file and could quietly become `.help` alone —
    /// which is precisely the state T-472 found the markdown toolbar in.
    @Test func theSharedControlLabelHelperSetsTheNameAndTheTooltipFromOneString() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CadenceButtons.swift")
        )
        let body = try #require(
            CadenceSourceScan.functionBody(named: "cadenceControlLabel", in: source),
            "cadenceControlLabel(_:) is gone"
        )
        #expect(body.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(body.contains(".help(accessibilityLabel)"))
        // The parameter is named for the accessible name, not for the tooltip. That is the durable
        // half of T-472 rather than a style preference: `help:` is what told the previous author
        // the string was for the pointer only.
        #expect(
            source.contains("func cadenceControlLabel(_ accessibilityLabel: String)"),
            "the helper's parameter was renamed away from accessibilityLabel"
        )
        // Non-vacuity, and the tie back to the sweep above: this shape is one the T-472 detector
        // must *not* report.
        #expect(tooltipWithoutNameInstrumentFires(on: body) == false)
    }

    private func tooltipWithoutNameInstrumentFires(on source: String) -> Bool {
        (try? tooltipWithoutNameInstrument())?.fires(on: source) ?? true
    }

    // MARK: - T-484: visible settings toggles

    /// Every file the app compiles, both platforms. `Cadence/iOS/` is not built by this target, so
    /// a scan is the only thing in the repo that reads it at all.
    @Test func noVisibleToggleInTheAppIsLeftWithoutAnAccessibleName() throws {
        let offenders = try unnamedToggleInstrument().sweep(
            try Self.swiftFiles(under: "Cadence"),
            // 551 files at the time of writing; the floor only has to rule out a walk that found
            // a handful and called it the app.
            atLeast: 400,
            including: "Cadence/macOS/Views/SettingsNotificationsSection.swift",
            read: CadenceSourceScan.sourceFile
        )
        #expect(
            offenders.isEmpty,
            #"visible Toggle("", ...) with no accessible name: \#(offenders)"#
        )
    }

    /// The five the ticket listed, by the name each switch now carries. Stated as values rather
    /// than left to the sweep: the sweep only knows that *some* name is present, and a revert that
    /// swapped in the wrong one would keep it green.
    ///
    /// **The two notifications switches name themselves from a constant now** ([[T-524]]), and that
    /// is strictly stronger than the literal this used to pin: `remindersToggleTitle` is the *same*
    /// constant the row's visible `title:` reads, so "the switch takes its name from its own row"
    /// is true by construction rather than by two spellings agreeing. Both surfaces are still
    /// listed here — the claim is about each file, and the phone's is not compiled by this target.
    @Test func theFiveNamedTogglesTakeTheirNameFromTheirOwnRow() throws {
        let expected = [
            "Cadence/macOS/Views/SettingsNotificationsSection.swift":
                #"Toggle(CadenceNotificationSettingsCopy.remindersToggleTitle, isOn: $notificationsEnabled)"#,
            "Cadence/iOS/iOSNotificationsSettingsSection.swift":
                #"Toggle(CadenceNotificationSettingsCopy.remindersToggleTitle, isOn: $notificationsEnabled)"#,
            "Cadence/macOS/Views/HabitsFormSupportViews.swift": #"Toggle("Remind me", isOn: $hasReminder)"#,
            "Cadence/macOS/Views/NoteActionReviewSheets.swift": #"Toggle("Include this task", isOn: $isSelected)"#,
            "Cadence/macOS/Views/SettingsSupportViews.swift": #"Toggle("Visible in Sidebar", isOn: $isVisible)"#,
        ]
        for (path, declaration) in expected {
            let source = try CadenceSourceScan.sourceFile(path)
            #expect(source.contains(declaration), "\(path) no longer names its toggle")
            #expect(source.contains(".labelsHidden()"), "\(path) would now draw the name twice")
        }
    }

    /// Ties the fixtures to the tree: the file the ticket named first is the shape the rule must
    /// leave alone, and it is a *hidden-label* toggle — the case a cruder "any `.labelsHidden()` is
    /// a defect" rule would have flagged.
    @Test func theUnnamedToggleDetectorAgreesWithTheNotificationsPane() throws {
        let source = try CadenceSourceScan.sourceFile(
            "Cadence/macOS/Views/SettingsNotificationsSection.swift"
        )
        #expect(source.contains(".labelsHidden()"), "non-vacuity: the pane no longer hides a label")
        let instrument = try unnamedToggleInstrument()
        #expect(instrument.fires(on: source) == false)
    }

    /// True when the file holds a `Toggle("", ...)` whose modifier chain never states a name.
    ///
    /// Comments are stripped, not `codeOnly`: this rule reads the *contents* of a string literal —
    /// empty versus not — and `codeOnly` blanks literals quotes and all, which would make
    /// `Toggle("", ` and `Toggle("Active", ` the same text.
    ///
    /// Six lines is the chain window. Every toggle in the app is written one modifier per line, and
    /// the longest of them is four modifiers deep.
    private func unnamedToggleInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "visible toggle with no accessible name",
            fires: """
            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
            """,
            // The nearest miss: same empty label, same hidden label, one modifier more. Naming the
            // toggle outright is the fix used here, but a stated `.accessibilityLabel` is equally
            // a name and the rule must not call it a defect.
            andNotOn: """
            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .accessibilityLabel("Enable reminders")
                .toggleStyle(.switch)
            """,
            by: Self.hasUnnamedVisibleToggle
        )
    }

    private static func hasUnnamedVisibleToggle(_ source: String) -> Bool {
        // Cheap reject before the expensive strip. `strippingComments` rescans from the start of
        // the string after every match it replaces, so running it over 551 files unconditionally
        // is quadratic work to answer "no" 550 times.
        guard source.contains("Toggle(\"\",") else { return false }
        let lines = CadenceSourceScan.strippingComments(source).components(separatedBy: "\n")
        for index in lines.indices where lines[index].contains("Toggle(\"\",") {
            let chain = lines[index..<min(index + 6, lines.count)]
            if chain.contains(where: { $0.contains(".accessibilityLabel(") }) { continue }
            return true
        }
        return false
    }

    // MARK: - T-521: a shared control's hint may not name a touch gesture

    /// The offender, and the file the sweep below is anchored on.
    private static let notesListPath = "Cadence/Shared/CadenceNotesListSupport.swift"

    /// **A hint states the outcome of activating, not the gesture that activates.**
    ///
    /// `NotesMonthHeader` read "Double tap to expand" / "Double tap to collapse". It lives in
    /// `Cadence/Shared/` and `NotesFoldableListColumn` places it on **four macOS Notes pages** as
    /// well as the iPad pane and the iPhone list, so on the Mac the hint named a gesture that
    /// surface does not have — VoiceOver activates a control there with Control-Option-Space, and
    /// the `.onHover` on the same modifier chain is the tell that this is not a touch-only view.
    ///
    /// Swept over `Cadence/Shared` **and** `Cadence/macOS` rather than pinned to the one file, for
    /// the reason `CadenceRetiredCopyTests` gives: a per-screen guard finds the screen you were
    /// looking at. `Cadence/iOS/` is deliberately **out** of scope — a hint under `#if os(iOS)`
    /// can name a touch gesture, because touch is the only way to reach it, and
    /// `iOSCaptureRadialMenu` legitimately says "Double tap to capture a task."
    @Test func noSharedOrDesktopAccessibilityHintNamesATouchGesture() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/Shared")
            + CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
        let read = CadenceSourceScan.strippedSourceReader()

        let offenders = try gestureNamingHintInstrument().sweep(
            files,
            // 358 files across the two trees; the floor only rules out a walk that found one
            // folder and called it both.
            atLeast: 300,
            including: Self.notesListPath,
            read: read
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) set an accessibilityHint naming a touch gesture on a surface macOS \
            draws. State what activating does, the way CadenceStartupIssueBannerModel does.
            """
        )
    }

    /// The hint itself, by value and in both directions.
    ///
    /// The sweep only knows that no gesture is named; it would stay green if the hint were deleted
    /// outright or replaced with something that says nothing. These are the words, and they are the
    /// shape the app's *other* shared expand/collapse control already uses — asserted here too, so
    /// "match the banner" cannot quietly become two styles again.
    @Test func theNotesMonthHeaderHintStatesWhatActivatingDoes() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile(Self.notesListPath)
        )
        #expect(source.contains("struct NotesMonthHeader: View"), "non-vacuity: wrong file")

        let hint = try #require(
            Self.accessibilityHintSegments(in: source).first,
            "NotesMonthHeader no longer states a hint at all"
        )
        #expect(hint.contains("\"Expands to show this month's notes.\""))
        #expect(hint.contains("\"Collapses this month's notes.\""))
        #expect(hint.contains("isCollapsed ?"), "the hint no longer answers for both fold states")

        // The header really is the shared, hoverable control the rule is about — both halves of
        // the ticket's premise, read rather than assumed.
        #expect(source.contains(".onHover { isHovered = $0 }"))
        #expect(
            source.contains("#if os(iOS)") == false && source.contains("#if os(macOS)") == false,
            "the notes list column is no longer platform-neutral; recheck the scope of the sweep"
        )

        // The sibling it is modelled on, still worded the same way.
        let banner = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceStartupIssueBanner.swift")
        )
        #expect(banner.contains("\"Expands to show what went wrong.\""))
        #expect(banner.contains("\"Collapses to a compact badge.\""))
    }

    /// The detector against the tree, not only its own fixtures — and against the tree on **both**
    /// sides, which is what makes the scope choice a claim rather than an accident.
    ///
    /// The positive is `iOSCaptureRadialMenu`, a real file whose "Double tap to capture a task."
    /// is *correct* and which the sweep therefore must not walk. A detector that could not see it
    /// would make the sweep's silence meaningless; a sweep that walked it would report a
    /// non-defect. The negative is the shared banner, whose hint is the shape this rule wants.
    @Test func theGestureHintDetectorSeparatesATouchOnlySurfaceFromASharedOne() throws {
        let instrument = try gestureNamingHintInstrument()

        let touchOnly = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCaptureRadialMenu.swift")
        #expect(touchOnly.contains("Double tap to capture a task."), "non-vacuity: the copy moved")
        #expect(instrument.fires(on: touchOnly), "the detector cannot see a hint that names a gesture")

        let shared = try CadenceSourceScan.sourceFile(
            "Cadence/Shared/Components/CadenceStartupIssueBanner.swift"
        )
        #expect(instrument.fires(on: shared) == false, "an outcome-worded hint is read as a gesture")

        // And the scope: the walk the sweep runs must exclude the iOS tree, or the correct file
        // above would be reported as an offence.
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/Shared")
            + CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
        #expect(files.contains("Cadence/iOS/iOSCaptureRadialMenu.swift") == false)
        #expect(files.contains("Cadence/Shared/Components/CadenceStartupIssueBanner.swift"))
    }

    /// True when any accessibility hint in the file names a touch gesture.
    ///
    /// The negative witness is the nearest miss on purpose: the same control, the same fold, the
    /// same two-branch hint — worded as an outcome instead of a gesture. A detector keyed on
    /// anything else about these two would separate them for the wrong reason.
    private func gestureNamingHintInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "accessibility hint naming a touch gesture",
            fires: """
            Button(action: toggle) { header }
                .onHover { isHovered = $0 }
                .accessibilityHint(isCollapsed ? "Double tap to expand" : "Double tap to collapse")
            """,
            andNotOn: """
            Button(action: toggle) { header }
                .onHover { isHovered = $0 }
                .accessibilityHint(
                    isCollapsed ? "Expands to show this month's notes." : "Collapses this month's notes."
                )
            """,
            by: Self.namesAGestureInAHint
        )
    }

    /// A gesture verb, as a word, and the phrase "double tap" — which "tap" alone already covers
    /// but which is the exact spelling this rule was written for.
    private static let gestureVerbPattern =
        "(?i)\\b(double[ -]tap|tap|taps|tapped|tapping|swipe|swipes|swiped|pinch|pinches|touch and hold|long press)\\b"

    private static func namesAGestureInAHint(_ source: String) -> Bool {
        // Cheap reject before the expensive strip, the same guard `hasUnnamedVisibleToggle` uses:
        // `strippingComments` rescans from the start after every match it replaces.
        guard source.contains("accessibilityHint") else { return false }
        let code = CadenceSourceScan.strippingComments(source)
        return accessibilityHintSegments(in: code).contains { segment in
            stringLiterals(in: segment).contains {
                $0.range(of: gestureVerbPattern, options: .regularExpression) != nil
            }
        }
    }

    /// The text of every hint in `source`, in both shapes this repo writes them.
    ///
    /// Two shapes, because scoping to only the modifier would miss the app's other shared
    /// expand/collapse control: `CadenceStartupIssueBannerModel` computes its hint in a
    /// `var accessibilityHint: String` and the view passes that variable to the modifier, so a
    /// reader keyed on `.accessibilityHint(` alone sees an identifier and no copy at all.
    /// `theNotesMonthHeaderHintStatesWhatActivatingDoes` pins that this reader really does find
    /// the banner's sentences, so the second shape cannot rot into decoration.
    ///
    /// Expects comments to be stripped already. Depth counting skips string literals, so a hint
    /// containing a bracket cannot close its own segment early.
    static func accessibilityHintSegments(in source: String) -> [String] {
        segments(after: ".accessibilityHint(", open: "(", close: ")", in: source)
            + segments(after: "var accessibilityHint: String {", open: "{", close: "}", in: source)
    }

    private static func segments(
        after needle: String,
        open: Character,
        close: Character,
        in source: String
    ) -> [String] {
        var found: [String] = []
        var searchStart = source.startIndex
        while let hit = source.range(of: needle, range: searchStart..<source.endIndex) {
            searchStart = hit.upperBound
            var depth = 1
            var index = hit.upperBound
            var inLiteral = false
            while index < source.endIndex, depth > 0 {
                let character = source[index]
                if inLiteral {
                    if character == "\\" {
                        index = source.index(after: index)
                    } else if character == "\"" || character.isNewline {
                        inLiteral = false
                    }
                } else if character == "\"" {
                    inLiteral = true
                } else if character == open {
                    depth += 1
                } else if character == close {
                    depth -= 1
                    if depth == 0 { break }
                }
                guard index < source.endIndex else { break }
                index = source.index(after: index)
            }
            found.append(String(source[hit.upperBound..<min(index, source.endIndex)]))
        }
        return found
    }

    private static func stringLiterals(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"\\\\\\n]*)\"") else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[captured])
        }
    }

    // MARK: - T-573: the calendar's three day cells

    /// The three cells, the label each draws its words from, and whether it may claim selection.
    ///
    /// The trailing flag is the ticket's own defect: two cells in **one grid**, off one tap, one
    /// selection — and only the agenda one announced that it was selected.
    private static let calendarDayCells: [(path: String, declaration: String, label: String, announcesSelection: Bool)] = [
        (
            "Cadence/iOS/iOSCalendarMonthViews.swift",
            "struct iOSCalendarMonthDayCell: View {",
            "CadenceCalendarDayAccessibility.countedDayLabel(date:date,itemCount:itemCount)",
            true
        ),
        (
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
            "struct iOSCalendarMonthCompactDayCell: View {",
            "CadenceCalendarDayAccessibility.markedDayLabel(date:date,hasItems:hasItems)",
            true
        ),
        (
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "struct iOSCalendarTimelineDayHeader: View {",
            "CadenceCalendarDayAccessibility.timelineDayLabel(date:date,timedCount:timedCount,unscheduledCount:unscheduledTasks.count)",
            false
        ),
    ]

    /// **The words, as values.** The scan below only knows each cell calls the shared function; it
    /// would stay green if the function started returning the bare date it used to.
    @Test func aCalendarDayCellAnnouncesWhatIsOnTheDayAndNotOnlyTheDate() throws {
        let date = try #require(DateFormatters.date(from: "2026-08-31"))
        let day = DateFormatters.longDate.string(from: date)

        // The full month grid draws a count capsule, so it announces the count.
        #expect(
            CadenceCalendarDayAccessibility.countedDayLabel(date: date, itemCount: 3)
                == "\(day), 3 scheduled items"
        )
        #expect(
            CadenceCalendarDayAccessibility.countedDayLabel(date: date, itemCount: 1)
                == "\(day), 1 scheduled item"
        )

        // The compact agenda grid draws a binary dot, so it announces presence and not a figure it
        // does not show.
        #expect(
            CadenceCalendarDayAccessibility.markedDayLabel(date: date, hasItems: true)
                == "\(day), has scheduled items"
        )

        // The timeline band draws two figures, and says both. The unscheduled clause is dropped
        // rather than read as "0 unscheduled".
        #expect(
            CadenceCalendarDayAccessibility.timelineDayLabel(date: date, timedCount: 4, unscheduledCount: 2)
                == "\(day), 4 timed items, 2 unscheduled"
        )
        #expect(
            CadenceCalendarDayAccessibility.timelineDayLabel(date: date, timedCount: 1, unscheduledCount: 0)
                == "\(day), 1 timed item"
        )

        // One wording for an empty day across all three, by construction rather than by three
        // literals happening to match.
        let empty = "\(day), \(CadenceCalendarDayAccessibility.emptyPhrase)"
        #expect(CadenceCalendarDayAccessibility.countedDayLabel(date: date, itemCount: 0) == empty)
        #expect(CadenceCalendarDayAccessibility.markedDayLabel(date: date, hasItems: false) == empty)
        #expect(CadenceCalendarDayAccessibility.timelineDayLabel(date: date, timedCount: 0, unscheduledCount: 0) == empty)

        // And the date really is the long form the cells used to announce alone — so this suite
        // records that the fix *added* to the label rather than replacing it.
        #expect(empty.hasPrefix(day))
    }

    /// **The call sites**, including the one that must *not* claim selection.
    ///
    /// A scan, because all three cells are inside `#if os(iOS)` and this target builds for macOS.
    @Test func everyCalendarDayCellNamesItselfAndOnlyTheSelectableOnesSaySo() throws {
        for cell in Self.calendarDayCells {
            let raw = try CadenceSourceScan.sourceFile(cell.path)
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "non-vacuity: \(cell.path) carries no comments to strip")
            let dense = stripped.filter { !$0.isWhitespace }
            #expect(
                dense.contains(cell.declaration.filter { !$0.isWhitespace }),
                "non-vacuity: \(cell.path) no longer declares the cell this rule is about"
            )

            #expect(
                dense.contains(".accessibilityLabel(\(cell.label))"),
                "\(cell.path) no longer names its day cell from the shared calendar label"
            )
            // The bare date, which is what all three said before T-573.
            #expect(
                dense.contains(".accessibilityLabel(DateFormatters.longDate.string(from:date))") == false,
                "\(cell.path) is back to announcing the date and nothing on the day (T-573)"
            )

            let claimsSelection = dense.contains(".accessibilityAddTraits(isSelected?[.isSelected]:[])")
            #expect(
                claimsSelection == cell.announcesSelection,
                cell.announcesSelection
                    ? "\(cell.path) draws a selected state and does not announce it (T-573)"
                    : "\(cell.path) announces a selection its band deliberately does not draw"
            )
        }
    }

    /// Why the third cell is exempt, read from the tree rather than asserted from the ticket.
    ///
    /// T-573 listed the timeline day header as "a third instance" of the missing `.isSelected`
    /// trait. It is not: the header carries **no selection state at all** — it says so in its own
    /// doc, and its background keys on `isToday` alone, with no `isSelected` to key on because the
    /// grid never passes one. Adding the trait would have announced a state the screen was
    /// deliberately changed to stop showing.
    @Test func theTimelineDayHeaderHasNoSelectedStateToAnnounce() throws {
        let path = "Cadence/iOS/iOSCalendarTimelineViews.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.contains("It carries **no selection state**"), "the header's stated design changed")

        let header = try Self.bodyOfStruct(
            "iOSCalendarTimelineDayHeader",
            in: CadenceSourceScan.codeOnly(raw)
        )
        #expect(header.contains("isToday"), "non-vacuity: the header no longer marks today either")
        #expect(
            header.contains("isSelected") == false,
            "the timeline day header has a selected state now — give it the trait and drop this test"
        )
        // And the two that do announce it really do draw it, which is what makes the split above a
        // reading of the screen rather than a preference.
        for path in [
            "Cadence/iOS/iOSCalendarMonthViews.swift",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                source.contains("let isSelected: Bool"),
                "\(path) stopped taking a selection; recheck whether it should still claim the trait"
            )
        }
    }

    // MARK: - Reading Swift text

    enum ProbeFailure: Swift.Error, CustomStringConvertible {
        /// Deliberately not spelled "error": the root guide's compile-failure grep looks for that
        /// word, and a thrown scan failure is a kill rather than a build break.
        case noSuchType(String)
        case unbalancedBraces(String)

        var description: String {
            switch self {
            case .noSuchType(let name): return "no struct named '\(name)' in the scanned source"
            case .unbalancedBraces(let name): return "braces never balance for struct '\(name)'"
            }
        }
    }

    /// The text between the braces of `struct <name>`, by matching from the first `{` after the
    /// declaration. `CadenceSourceScan.functionBody` is the same walk keyed on `func <name>(`; this
    /// needs a type because each toolbar button *is* one control, so the control's own body is the
    /// scope the rule is about.
    ///
    /// Expects `source` to have been through `codeOnly` already — a `{` inside a comment or a
    /// string literal would otherwise move the depth count.
    static func bodyOfStruct(_ name: String, in source: String) throws -> String {
        guard let declaration = source.range(of: "struct \(name): View {") else {
            throw ProbeFailure.noSuchType(name)
        }
        var depth = 0
        var index = source.index(before: declaration.upperBound)
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    let start = source.index(after: source.index(before: declaration.upperBound))
                    return String(source[start..<index])
                }
            }
            index = source.index(after: index)
        }
        throw ProbeFailure.unbalancedBraces(name)
    }

    /// Repo-relative `.swift` paths under `relativeDirectory`, recursively.
    static func swiftFiles(under relativeDirectory: String) throws -> [String] {
        let directory = CadenceSourceScan.repositoryRoot().appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            return []
        }
        return enumerator.compactMap { element in
            guard let name = element as? String, name.hasSuffix(".swift") else { return nil }
            return "\(relativeDirectory)/\(name)"
        }
    }
}
