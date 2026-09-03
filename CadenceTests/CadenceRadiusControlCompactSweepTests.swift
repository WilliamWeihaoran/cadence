import Foundation
import Testing
@testable import Cadence

/// T-616: 55 call sites drew a corner radius of exactly `7` with no token — `Theme`'s scale held
/// only 10/18/22 — and two more spelled the same number a third way, as `Theme.radiusControl - 3`.
/// One origin copied 55 times is not 55 independent design choices, so the coordinator's decision
/// was to name the de-facto step **descriptively** and sweep every spelling onto it, rather than
/// converge it onto `radiusControl` (10) — a visible change to 55 places nobody reviewed.
///
/// `Theme.radiusControlCompact` is defined as `radiusControl - 3`, the same relationship the two
/// pre-existing sites already assumed, so this sweep changes no rendered pixel: every one of these
/// call sites drew `7` before and draws `10 - 3` (still `7`) after.
///
/// **Failing-first.** `noFileOutsideThemeSpellsALiteralCornerRadiusOfSeven` and
/// `noCallSiteOutsideThemeSpellsRadiusControlMinusThree` sweep the whole tree, so reverting any one
/// of the converted sites turns the matching test red: 54 `cornerRadius: 7` call sites, one
/// `NSBezierPath` call with both `xRadius:` and `yRadius:` at `7`, the 3 `Theme.radiusControl - 3`
/// call sites (one more than the ticket's own count of 2, which it invited re-measuring), and 3
/// more the ticket's own framing did not name — `kanbanCardCornerRadius`, `SidebarMetrics
/// .appMarkCornerRadius`, and a private `TaskInspectorContentSupportViews.cornerRadius` — each a
/// *named* constant whose own declaration was still the bare literal `7`, one more spelling of the
/// same accidental copy one level removed from a direct call site. Their many call sites (28+ for
/// `kanbanCardCornerRadius` alone) keep their existing names; only the constants' own RHS moved
/// onto the shared token, so this, too, changes no rendered pixel.
struct CadenceRadiusControlCompactSweepTests {

    /// `Theme.swift` itself: the token's declaration is `radiusControl - 3`, and its doc comment
    /// quotes both `7` and `radiusControl - 3` in prose. Excluded from the call-site sweep below —
    /// scanning it would make the test fail on the very fix it exists to describe.
    static let themeDefinitionFile = "Cadence/Shared/Theme.swift"

    /// Every `cornerRadius: 7` / `xRadius: 7` / `yRadius: 7` **call-site** literal, and every
    /// `someRadius(: CGFloat)? = 7` **declaration** of a named constant (the shape
    /// `kanbanCardCornerRadius`, `appMarkCornerRadius`, and the private
    /// `TaskInspectorContentSupportViews.cornerRadius` all had before this sweep — one more
    /// spelling of the same accidental copy, one level removed from a direct call site). Both
    /// forms are word-bounded, so `70`, `17` etc. do not match. Read from `codeOnly` text so a
    /// string literal or comment cannot be counted as code.
    static func remainingLiteralRadiusSevenSites() throws -> [(file: String, line: Int, text: String)] {
        var hits: [(String, Int, String)] = []
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
            + CadenceSourceScan.swiftFiles(under: "CadenceMCPServer")
        // Anchored so an unrelated `*Radius` name cannot false-positive: `CadenceWidgets
        // /WidgetChrome.swift` scales a *shadow blur* radius (`elevationRadius`) through
        // 5/6/7/8 across four widget sizes — real scatter, a deliberate per-tier value, not
        // "one origin copied N times" — and a bare `[Rr]adius\w*` pattern matched its `7` tier
        // as if it were a corner radius. Matching only `cornerRadius` (bare or as any
        // `*CornerRadius` name), bare `radius`, and `xRadius`/`yRadius` keeps the sweep scoped
        // to what T-616 is actually about.
        let pattern = "\\b(?:\\w*[Cc]ornerRadius|[xy][Rr]adius|[Rr]adius)\\s*[:=]\\s*7\\b"
        for path in paths where path != themeDefinitionFile {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                guard CadenceSourceScan.matchCount(pattern, in: line) > 0 else { continue }
                hits.append((path, index + 1, line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return hits
    }

    /// Every remaining `Theme.radiusControl - 3` spelling outside `Theme.swift`'s own definition.
    static func remainingRadiusControlMinusThreeSites() throws -> [(file: String, line: Int)] {
        var hits: [(String, Int)] = []
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
            + CadenceSourceScan.swiftFiles(under: "CadenceMCPServer")
        for path in paths where path != themeDefinitionFile {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                guard line.contains("radiusControl - 3") else { continue }
                hits.append((path, index + 1))
            }
        }
        return hits
    }

    /// Self-checked instrument: fires on the literal spelling, not on the token.
    static let literalRadiusSevenInstrument = try! CadenceScanInstrument(
        "literalCornerRadiusSeven",
        fires: "RoundedRectangle(cornerRadius: 7)",
        andNotOn: "RoundedRectangle(cornerRadius: Theme.radiusControlCompact)"
    ) { text in
        CadenceSourceScan.matchCount("cornerRadius: *7\\b", in: text) > 0
    }

    @Test
    func literalRadiusSevenInstrumentStillDiscriminates() throws {
        #expect(Self.literalRadiusSevenInstrument.fires(on: "cornerRadius: 7"))
        #expect(!Self.literalRadiusSevenInstrument.fires(on: "cornerRadius: Theme.radiusControlCompact"))
        // A neighbouring two-digit radius must not false-positive a word-bounded detector.
        #expect(!Self.literalRadiusSevenInstrument.fires(on: "cornerRadius: 17"))
    }

    @Test
    func noFileOutsideThemeSpellsALiteralCornerRadiusOfSeven() throws {
        let hits = try Self.remainingLiteralRadiusSevenSites()
        #expect(hits.isEmpty, "literal corner-radius-7 site(s) found outside Theme.swift: \(hits)")
    }

    @Test
    func noCallSiteOutsideThemeSpellsRadiusControlMinusThree() throws {
        let hits = try Self.remainingRadiusControlMinusThreeSites()
        #expect(hits.isEmpty, "`radiusControl - 3` site(s) found outside Theme.swift: \(hits)")
    }

    @Test
    func theTokenIsDefinedRelativeToRadiusControlNotAsANewLiteral() throws {
        // Pins the *relationship*, not just the value: a future edit to `radiusControl` should
        // move this token with it, the same assumption the two pre-existing
        // `radiusControl - 3` sites already made. A literal `7` here would sever that link
        // silently.
        let source = try CadenceSourceScan.sourceFile(Self.themeDefinitionFile)
        #expect(CadenceSourceScan.matchCount(
            "static let radiusControlCompact: CGFloat = radiusControl - 3",
            in: source
        ) == 1)
        #expect(Theme.radiusControlCompact == 7)
        #expect(Theme.radiusControlCompact == Theme.radiusControl - 3)
    }

    @Test
    func theTokensDocCommentNamesItAsDescriptiveNotChosen() throws {
        // The user's decision text is explicit that this is not a new design tier — it is an
        // existing copied value getting one name. Pin that the doc comment actually says so,
        // not just that the token compiles to the right number.
        let source = try CadenceSourceScan.sourceFile(Self.themeDefinitionFile)
        #expect(source.contains("Descriptive, not a chosen tier"))
        #expect(source.contains("Do not converge this onto `radiusControl` or `10`"))
    }

    /// Named spot-pins on a handful of the 58 converted sites, including the ticket's own
    /// motivating file (shared with T-489's SettingsListManagementSections example) and the one
    /// site that needed two literal replacements on a single line.
    @Test
    func namedConversionsReadTheToken() throws {
        let sites: [(file: String, pattern: String)] = [
            (
                "Cadence/macOS/Views/SettingsListManagementSections.swift",
                "RoundedRectangle\\(cornerRadius: Theme\\.radiusControlCompact\\)"
            ),
            (
                "Cadence/iOS/iOSDesignSystem.swift",
                "RoundedRectangle\\(cornerRadius: Theme\\.radiusControlCompact, style: \\.continuous\\)"
            ),
            (
                "Cadence/iOS/iOSTodaySchedulePanel.swift",
                "cornerRadius: Theme\\.radiusControlCompact, style: \\.continuous"
            ),
        ]
        for site in sites {
            let source = try CadenceSourceScan.sourceFile(site.file)
            #expect(
                CadenceSourceScan.matchCount(site.pattern, in: source) > 0,
                "expected \(site.file) to read the radiusControlCompact token"
            )
        }

        // The one site with two literal replacements on the same line.
        let bezierSource = try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift")
        #expect(CadenceSourceScan.matchCount(
            "NSBezierPath\\(roundedRect: backgroundRect, xRadius: Theme\\.radiusControlCompact, yRadius: Theme\\.radiusControlCompact\\)",
            in: bezierSource
        ) == 1)
    }
}
