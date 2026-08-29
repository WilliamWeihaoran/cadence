import Foundation
import Testing

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
struct ControlAccessibilityLabelTests {

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
    @Test func theFiveNamedTogglesTakeTheirNameFromTheirOwnRow() throws {
        let expected = [
            "Cadence/macOS/Views/SettingsNotificationsSection.swift": #"Toggle("Enable reminders", isOn: $notificationsEnabled)"#,
            "Cadence/iOS/iOSNotificationsSettingsSection.swift": #"Toggle("Enable reminders", isOn: $notificationsEnabled)"#,
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
