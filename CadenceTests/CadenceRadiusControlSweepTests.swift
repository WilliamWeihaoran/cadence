import Foundation
import Testing
@testable import Cadence

/// T-754: 42 sites spelled `Theme.radiusControl` (10) as the bare literal `cornerRadius: 10`
/// (40 SwiftUI call sites plus two `NSBezierPath(xRadius:yRadius:)` call sites), and one more
/// named constant — `kanbanColumnCornerRadius` in `KanbanBoardSupport.swift` — declared itself as
/// the same bare `10` right beside the `kanbanCardCornerRadius` that T-616 already converted onto
/// `Theme.radiusControlCompact`.
///
/// **Unlike T-616's `7`, no naming decision was needed here.** `Theme.radiusControl` already
/// existed and is the right token; these were call sites that retyped its value rather than read
/// it. So the sweep below is purely mechanical — every remaining `10` that means the control
/// radius reads the token, and the two that do not are named exemptions rather than silent misses.
///
/// **Two sites are excluded, and each is a case of "10" arriving by coincidence, not by copying
/// the control radius:**
///
/// - `TimelineMetrics.swift`'s `TimelineBlockStyle.schedule` declares `cornerRadius: 10` beside a
///   sibling `TimelineBlockStyle.calendar` that declares `cornerRadius: 9` — a deliberately-tuned
///   per-density pair (also distinct in `minHeight`, `horizontalPadding`, `verticalPadding`), the
///   same shape T-616's own sweep excluded `WidgetChrome.elevationRadius` for. Converging
///   `.schedule`'s `10` onto `Theme.radiusControl` would sever it from the tuning relationship its
///   own sibling shows it belongs to, and every `style.cornerRadius` call site downstream (in
///   `TimelineEventBlock.swift`, `TimelineBundleBlock.swift`, `TimelineTaskBlockSupportViews.swift`,
///   etc.) already reads the field rather than a literal, so nothing there is a spelling of `10`
///   to convert in the first place.
/// - `MarkdownEditorTextViewDecorations.swift`'s image-selection ring draws
///   `NSBezierPath(roundedRect: imageRect.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)` —
///   one member of a concentric-inset family in the same function: the image itself clips at `8`,
///   the surface wash insets by `-1` at radius `9`, and the selection ring insets by `-2` at radius
///   `10`. Each `+1pt` of inset pairs with `+1pt` of radius to stay concentric; the `10` here is
///   `8 + 2`, not `Theme.radiusControl` copied a 42nd time. Converting it alone would decouple it
///   from that arithmetic the next time `Theme.radiusControl` moves.
struct CadenceRadiusControlSweepTests {

    static let themeDefinitionFile = "Cadence/Shared/Theme.swift"

    /// The two sites that legitimately spell a `10` unrelated to `Theme.radiusControl`, reasoned
    /// through in the type's own doc comment above. Held as file+line so a *different* line in the
    /// same file — a genuine control-radius site added later — is not swept under the same excuse.
    static let exemptions: Set<ExemptSite> = [
        ExemptSite(file: "Cadence/macOS/Views/TimelineMetrics.swift", line: 280),
        ExemptSite(file: "Cadence/macOS/Editor/MarkdownEditorTextViewDecorations.swift", line: 221),
    ]

    struct ExemptSite: Hashable {
        let file: String
        let line: Int
    }

    /// Every `cornerRadius: 10` / `xRadius: 10` / `yRadius: 10` **call-site** literal, and every
    /// `someRadius(: CGFloat)? = 10` **declaration** of a named constant — the same two shapes
    /// `CadenceRadiusControlCompactSweepTests` swept for the `7` family. Word-bounded so `100`,
    /// `210` etc. do not match, and read from `codeOnly` text so a string literal or comment cannot
    /// be counted as code.
    static func remainingLiteralRadiusTenSites() throws -> [(file: String, line: Int, text: String)] {
        var hits: [(String, Int, String)] = []
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
            + CadenceSourceScan.swiftFiles(under: "CadenceMCPServer")
        let pattern = "\\b(?:\\w*[Cc]ornerRadius|[xy][Rr]adius|[Rr]adius)\\s*[:=]\\s*10\\b"
        for path in paths where path != themeDefinitionFile {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let lineNumber = index + 1
                guard CadenceSourceScan.matchCount(pattern, in: line) > 0 else { continue }
                guard !exemptions.contains(ExemptSite(file: path, line: lineNumber)) else { continue }
                hits.append((path, lineNumber, line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return hits
    }

    /// Self-checked instrument: fires on the literal spelling, not on the token, and not on a
    /// neighbouring two-digit radius.
    static let literalRadiusTenInstrument = try! CadenceScanInstrument(
        "literalCornerRadiusTen",
        fires: "RoundedRectangle(cornerRadius: 10)",
        andNotOn: "RoundedRectangle(cornerRadius: Theme.radiusControl)"
    ) { text in
        CadenceSourceScan.matchCount("cornerRadius: *10\\b", in: text) > 0
    }

    @Test
    func literalRadiusTenInstrumentStillDiscriminates() throws {
        #expect(Self.literalRadiusTenInstrument.fires(on: "cornerRadius: 10"))
        #expect(!Self.literalRadiusTenInstrument.fires(on: "cornerRadius: Theme.radiusControl"))
        // A neighbouring longer number must not false-positive a word-bounded detector.
        #expect(!Self.literalRadiusTenInstrument.fires(on: "cornerRadius: 100"))
        #expect(!Self.literalRadiusTenInstrument.fires(on: "cornerRadius: 210"))
    }

    @Test
    func noFileOutsideTheExemptionsSpellsALiteralCornerRadiusOfTen() throws {
        let hits = try Self.remainingLiteralRadiusTenSites()
        #expect(hits.isEmpty, "literal corner-radius-10 site(s) found outside the exemption list: \(hits)")
    }

    /// Each exemption still exists and still holds the literal it was excused for — so a rewrite
    /// that moves the exempted line, or converts it after all, does not leave a stale entry in
    /// `exemptions` quietly protecting nothing.
    @Test
    func eachExemptionStillHoldsTheLiteralItWasExcusedFor() throws {
        for site in Self.exemptions.sorted(by: { $0.file < $1.file }) {
            let source = try CadenceSourceScan.sourceFile(site.file)
            let lines = source.components(separatedBy: "\n")
            #expect(site.line - 1 < lines.count, "\(site.file) is shorter than line \(site.line)")
            guard site.line - 1 < lines.count else { continue }
            let line = lines[site.line - 1]
            #expect(
                CadenceSourceScan.matchCount("\\b(?:\\w*[Cc]ornerRadius|[xy][Rr]adius|[Rr]adius)\\s*[:=]\\s*10\\b", in: line) > 0,
                "\(site.file):\(site.line) no longer holds the literal-10 spelling the exemption excuses: \(line)"
            )
        }
    }

    /// Named spot-pins on a handful of the converted sites: the shared hover style (T-289's own
    /// file), the one named constant that moved rather than a call site, and the one
    /// `NSBezierPath` site with two literal replacements on the same line.
    @Test
    func namedControlRadiusConversionsReadTheToken() throws {
        let sites: [(file: String, pattern: String)] = [
            (
                "Cadence/Shared/CadenceHoverStyles.swift",
                "RoundedRectangle\\(cornerRadius: Theme\\.radiusControl\\)"
            ),
            (
                "Cadence/macOS/Views/GoalTimelineView.swift",
                "RoundedRectangle\\(cornerRadius: Theme\\.radiusControl\\)\\.strokeBorder"
            ),
        ]
        for site in sites {
            let source = try CadenceSourceScan.sourceFile(site.file)
            #expect(
                CadenceSourceScan.matchCount(site.pattern, in: source) > 0,
                "expected \(site.file) to read the radiusControl token"
            )
        }

        let kanbanSource = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanBoardSupport.swift")
        #expect(CadenceSourceScan.matchCount(
            "let kanbanColumnCornerRadius: CGFloat = Theme\\.radiusControl\\b",
            in: kanbanSource
        ) == 1)

        let bezierSource = try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift")
        #expect(CadenceSourceScan.matchCount(
            "NSBezierPath\\(roundedRect: blockRect, xRadius: Theme\\.radiusControl, yRadius: Theme\\.radiusControl\\)",
            in: bezierSource
        ) == 1)
    }
}
