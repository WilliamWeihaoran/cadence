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
    /// through in the type's own doc comment above.
    ///
    /// **Held as file + enclosing declaration, not file + line (T-1297).** The line number was
    /// never the point — the point is that a *different* site in the same file, a genuine
    /// control-radius `10` added later, must not be swept under the same excuse. But a line number
    /// is the one property of a line that every unrelated edit above it changes, and this list had
    /// already gone stale twice that way: [[T-1293]] added seven comment lines above
    /// `TimelineBlockStyle.schedule` and turned **both** tests below red, on a site they had
    /// already excused and on a line that no longer held a `10`.
    ///
    /// The declaration path is the same claim with a longer shelf life. It survives any number of
    /// lines inserted above the site; it still refuses a `10` in a different declaration of the
    /// same file, which is `theDeclarationAnchorStillRefusesADifferentSiteInTheSameFile`; and a
    /// *second* `10` inside the same declaration is a failure rather than a free ride, because
    /// `eachExemptionStillHoldsExactlyTheOneLiteralItWasExcusedFor` requires the anchor to resolve
    /// to exactly one line. That count is what makes the coarser anchor no coarser in practice.
    ///
    /// The alternative the ticket named — pinning the excused line's own **text** — was rejected
    /// for the first exemption specifically. `TimelineMetrics.swift`'s excused line reads
    /// `cornerRadius: 10,` and nothing else, which is exactly the text a `TimelineBlockStyle`
    /// added next year would spell, so that anchor forgives the case the line number was there to
    /// catch. It is also brittle in the other direction: it breaks on a reflow of the excused line
    /// itself, and the second exemption's line is 110 characters long.
    static let exemptions: Set<ExemptSite> = [
        ExemptSite(
            file: "Cadence/macOS/Views/TimelineMetrics.swift",
            declaration: "TimelineBlockStyle.schedule"
        ),
        ExemptSite(
            file: "Cadence/macOS/Editor/MarkdownEditorTextViewDecorations.swift",
            declaration: "CadenceTextView.drawMarkdownImages"
        ),
    ]

    struct ExemptSite: Hashable {
        let file: String
        /// Dotted path of the declarations enclosing the excused literal, outermost first, as
        /// `CadenceSourceScan.enclosingDeclarationPath` reads it.
        let declaration: String
    }

    /// One line that spells the literal, with the declaration it sits in — so a failure names the
    /// site the way the exemption list does rather than by a number the next edit invalidates.
    struct LiteralSite: Hashable, CustomStringConvertible {
        let file: String
        let line: Int
        let declaration: String
        let text: String

        var description: String {
            "\(file):\(line) in \(declaration.isEmpty ? "<file scope>" : declaration) — \(text)"
        }
    }

    /// Every `cornerRadius: 10` / `xRadius: 10` / `yRadius: 10` **call-site** literal, and every
    /// `someRadius(: CGFloat)? = 10` **declaration** of a named constant — the same two shapes
    /// `CadenceRadiusControlCompactSweepTests` swept for the `7` family, spelled once in
    /// `CadenceSourceScan.radiusLiteralPattern` and shared by both rather than typed twice.
    /// Word-bounded so `100`, `210` etc. do not match.
    ///
    /// **It did not count the declaration shape until [[T-1316]]**, though this file said it did
    /// ([[T-1315]]): the old needle was `…\s*[:=]\s*10\b`, and in
    /// `let cornerRadius: CGFloat = 10` the type annotation sits between the colon and the value.
    /// `theNeedleThatWasBlindIsPinnedBesideTheOneThatIsNot` holds both spellings side by side.
    static let literalRadiusTenPattern = CadenceSourceScan.radiusLiteralPattern(10)

    /// The needle as it stood before [[T-1316]], kept as a literal so the blindness is a measured
    /// fact in this file rather than a claim about a deleted string.
    static let supersededLiteralRadiusTenPattern =
        "\\b(?:\\w*[Cc]ornerRadius|[xy][Rr]adius|[Rr]adius)\\s*[:=]\\s*10\\b"

    /// The sweep over **text**, so the fixtures below can be swept exactly as a file is rather
    /// than by a second copy of the rule. Read from `codeOnly` text so a string literal or a
    /// comment cannot be counted as code, and so the declaration walk is not stopped by a doc
    /// comment standing at a declaration's own indent.
    ///
    /// Matched over the whole text rather than line by line ([[T-1316]]): a line-wise loop cannot
    /// see a site a formatter wrapped — `cornerRadius:` with its `10` on the next line — and the
    /// `\s*` in the needle silently means "spaces on this line" there. The line reported is the
    /// one the match *starts* on, which is the one the declaration walk wants.
    ///
    /// **One site per line, which is what `LiteralSite` has always meant.** The excused
    /// `NSBezierPath(… xRadius: 10, yRadius: 10)` is two matches on one line, and counting it as
    /// two would make `eachExemptionStillHoldsExactlyTheOneLiteralItWasExcusedFor` — whose whole
    /// job is to refuse a *second* literal riding in on an existing excuse — fail on the site it
    /// already excused. Deduplicating by start line keeps that count meaning what it meant while
    /// the needle underneath it widens.
    static func literalRadiusTenSites(in source: String, file: String) -> [LiteralSite] {
        let lines = CadenceSourceScan.codeOnly(source).components(separatedBy: "\n")
        var seen: Set<Int> = []
        return CadenceSourceScan
            .matchLines(literalRadiusTenPattern, in: lines.joined(separator: "\n"))
            .filter { seen.insert($0.line).inserted }   // one site per line, as `LiteralSite` says
            .map { hit in
                LiteralSite(
                    file: file,
                    line: hit.line + 1,
                    declaration: CadenceSourceScan.enclosingDeclarationPath(ofLine: hit.line, in: lines),
                    text: hit.matched
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .joined(separator: " ")
                )
            }
    }

    /// The same sweep with the exemptions applied, which is the part a fixture has to exercise:
    /// asserting that an exemption *matches* proves nothing about what it refuses.
    static func unexemptedLiteralRadiusTenSites(in source: String, file: String) -> [LiteralSite] {
        literalRadiusTenSites(in: source, file: file).filter { site in
            !exemptions.contains(ExemptSite(file: site.file, declaration: site.declaration))
        }
    }

    static func remainingLiteralRadiusTenSites() throws -> [LiteralSite] {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
            + CadenceSourceScan.swiftFiles(under: "CadenceMCPServer")
        return try paths.filter { $0 != themeDefinitionFile }.flatMap { path in
            unexemptedLiteralRadiusTenSites(in: try CadenceSourceScan.sourceFile(path), file: path)
        }
    }

    /// Self-checked instrument: fires on the literal spelling, not on the token, and not on a
    /// neighbouring two-digit radius.
    static let literalRadiusTenInstrument = try! CadenceScanInstrument(
        "literalCornerRadiusTen",
        fires: "RoundedRectangle(cornerRadius: 10)",
        andNotOn: "RoundedRectangle(cornerRadius: Theme.radiusControl)"
    ) { text in
        // The needle the sweep runs, not a third spelling of it: an instrument that self-checks a
        // *different* pattern proves that other pattern discriminates and says nothing about the
        // one doing the work.
        CadenceSourceScan.matchCount(CadenceRadiusControlSweepTests.literalRadiusTenPattern, in: text) > 0
    }

    @Test
    func literalRadiusTenInstrumentStillDiscriminates() throws {
        #expect(Self.literalRadiusTenInstrument.fires(on: "cornerRadius: 10"))
        #expect(!Self.literalRadiusTenInstrument.fires(on: "cornerRadius: Theme.radiusControl"))
        // A neighbouring longer number must not false-positive a word-bounded detector.
        #expect(!Self.literalRadiusTenInstrument.fires(on: "cornerRadius: 100"))
        #expect(!Self.literalRadiusTenInstrument.fires(on: "cornerRadius: 210"))
    }

    // MARK: - T-1316: the needle was blind to two shapes ordinary code writes

    /// A `CadenceHoverStyles`-shaped declaration and a formatter-wrapped call site: the two shapes
    /// the sweep's own doc comment promised to count and could not.
    ///
    /// Neither spelling exists at `10` anywhere in the tree today, which is the reason this is a
    /// **fixture** and not a census: a guard is proved blind by writing the shape it cannot see,
    /// not by waiting for someone to write it. The house style is real at other values —
    /// `CadenceHoverStyles.swift:59`, `MarkdownTableLayoutSupport.swift:20` and
    /// `EstimatePickerControl.swift:461` all declare a typed radius constant — so what was missing
    /// was only the literal `10`.
    static let declaredRadiusFixture = """
    enum FixtureMetrics {
        static let cardCornerRadius: CGFloat = 10
        static let wrappedBadge = RoundedRectangle(
            cornerRadius:
                10
        )
        static let tunedSibling: CGFloat = 9
        static let tokenised: CGFloat = Theme.radiusControl
    }
    """

    /// **Direction one: the needle fires on what it used to miss.** Both spellings are read now,
    /// and the superseded needle — pinned as a literal beside the live one — reads neither, so the
    /// blindness is a measurement in this file rather than a claim about a string that was deleted.
    @Test
    func theNeedleThatWasBlindIsPinnedBesideTheOneThatIsNot() throws {
        let file = "CadenceTests/fixture.swift"
        let hits = Self.literalRadiusTenSites(in: Self.declaredRadiusFixture, file: file)
        #expect(hits.count == 2, "expected the typed declaration and the wrapped call site: \(hits)")
        #expect(hits.allSatisfy { $0.declaration.hasPrefix("FixtureMetrics") },
                "the declaration anchor no longer resolves for either shape: \(hits)")

        // The two defects are separable, and the four readings below separate them. The needle was
        // blind to the typed declaration; the SWEEP, which ran that needle one line at a time, was
        // blind to the wrapped call site as well — `\s*` cannot cross a line break it never sees.
        // Repairing either alone would have left the other, which is why both moved.
        let code = CadenceSourceScan.codeOnly(Self.declaredRadiusFixture)
        func lineWise(_ pattern: String) -> Int {
            code.components(separatedBy: "\n")
                .filter { CadenceSourceScan.matchCount(pattern, in: $0) > 0 }
                .count
        }
        #expect(
            CadenceSourceScan.matchCount(Self.supersededLiteralRadiusTenPattern, in: code) == 1,
            "the superseded needle reads the wrapped site over whole text and never the declaration"
        )
        #expect(lineWise(Self.supersededLiteralRadiusTenPattern) == 0,
                "as the sweep actually ran it — line by line — the old needle saw neither site")
        #expect(lineWise(Self.literalRadiusTenPattern) == 1,
                "and the widened needle run line by line still reaches only the declaration")
    }

    /// **Direction two: it still does not fire on what it correctly ignored.** A widened needle
    /// that cries wolf on correct code is suppressed, and then it guards nothing — which is the
    /// reasoning that stopped [[T-1299]] widening a different one.
    @Test
    func theWidenedNeedleStillIgnoresEverythingItIgnoredBefore() throws {
        let file = "CadenceTests/fixture.swift"
        let quiet = """
        enum FixtureMetrics {
            static let tokenised: CGFloat = Theme.radiusControl
            static let declaredElsewhere: CGFloat = 12
            static let tuned: CGFloat = 9
            static let hundred = RoundedRectangle(cornerRadius: 100)
            static let twoTen = RoundedRectangle(cornerRadius: 210)
            // A shadow blur, not a corner: WidgetChrome scales this through 5/6/7/8 on purpose.
            static let elevationRadius: CGFloat = 10
            static let note = "cornerRadius: 10 in a string literal"
            // cornerRadius: 10 in a comment
            static let annotationOnly: CGFloat
        }
        """
        #expect(Self.literalRadiusTenSites(in: quiet, file: file).isEmpty)

        // And the tree itself, which is the only negative witness with real coverage: every file
        // under `Cadence/`, `CadenceWidgets/` and `CadenceMCPServer/` read with the widened needle.
        // `noFileOutsideTheExemptionsSpellsALiteralCornerRadiusOfTen` asserts this too; the point
        // of saying it here is that the widening is what is on trial.
        #expect(try Self.remainingLiteralRadiusTenSites().isEmpty)
    }

    @Test
    func noFileOutsideTheExemptionsSpellsALiteralCornerRadiusOfTen() throws {
        let hits = try Self.remainingLiteralRadiusTenSites()
        #expect(hits.isEmpty, "literal corner-radius-10 site(s) found outside the exemption list: \(hits)")
    }

    /// Each exemption still resolves, and resolves to **exactly one** line — so a rewrite that
    /// converts the excused literal after all, or renames the declaration around it, does not
    /// leave a stale entry quietly protecting nothing, and a *second* literal added inside the
    /// same declaration is a failure rather than a free ride.
    ///
    /// That count is the whole of what the line number used to buy and this anchor has to keep.
    /// It is the same shape `CadenceEmptyTitleFallbackSweepTests` gives its own file-level
    /// exemptions: a named spelling plus an exact count, so the excuse cannot widen in place.
    @Test
    func eachExemptionStillHoldsExactlyTheOneLiteralItWasExcusedFor() throws {
        for site in Self.exemptions.sorted(by: { $0.file < $1.file }) {
            let held = Self.literalRadiusTenSites(
                in: try CadenceSourceScan.sourceFile(site.file),
                file: site.file
            ).filter { $0.declaration == site.declaration }
            #expect(
                held.count == 1,
                """
                \(site.file): the exemption anchored to \(site.declaration) now covers \
                \(held.count) literal-10 site(s) rather than the one it was granted for — \(held). \
                Zero means the declaration was renamed or the literal converted, so the exemption \
                protects nothing; more than one means a second literal has been added inside that \
                declaration and would ride in on this excuse.
                """
            )
        }
    }

    // MARK: - T-1297: the anchor, demonstrated in both directions

    /// A `TimelineMetrics.swift` in miniature: the excused `10` in `TimelineBlockStyle.schedule`,
    /// and the deliberately-tuned sibling `9` the doc comment above says it belongs beside.
    static let timelineBlockStyleFixture = """
    struct TimelineBlockStyle {
        let minHeight: CGFloat
        let cornerRadius: CGFloat

        static let schedule = TimelineBlockStyle(
            minHeight: 24,
            cornerRadius: 10,
            horizontalPadding: 8
        )

        static let calendar = TimelineBlockStyle(
            minHeight: 22,
            cornerRadius: 9,
            horizontalPadding: 6
        )
    }
    """

    /// The shape of `drawMarkdownImages`: the excused ring literal nested inside a closure and an
    /// `if`, with a `guard let`, an `if let` and a local `let` standing above it that a naive
    /// "nearest binding" walk would name instead of the function.
    static let markdownImageDecorationFixture = """
    extension CadenceTextView {
        private func drawMarkdownImages(in rect: NSRect) {
            textStorage.enumerateAttribute(.cadenceMarkdownImage, in: characterRange) { value, range, _ in
                guard let info = value as? MarkdownImageLayoutInfo else { return }
                let imageRect = MarkdownDecorationGeometry.imageRect(lineRect: lineRect)
                if let image = info.image {
                    NSBezierPath(roundedRect: imageRect, xRadius: 8, yRadius: 8).fill()
                }
                if self.selectedMarkdownImageID == info.id {
                    let selectionPath = NSBezierPath(roundedRect: imageRect, xRadius: 10, yRadius: 10)
                }
            }
        }
    }
    """

    static func declarationPath(ofLineContaining needle: String, in fixture: String) -> String? {
        let lines = CadenceSourceScan.codeOnly(fixture).components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.contains(needle) }) else { return nil }
        return CadenceSourceScan.enclosingDeclarationPath(ofLine: index, in: lines)
    }

    /// The walk steps **out** of statements rather than naming what they bind. `if let image`,
    /// `guard let info` and the local `let imageRect` all introduce names, and a scanner that read
    /// any of them as the enclosing declaration would answer a path that changes whenever the
    /// branch around the site is rewritten — a second anchor with the first one's shelf life.
    @Test
    func theDeclarationPathScannerStepsOutOfStatementsRatherThanNamingThem() throws {
        #expect(
            Self.declarationPath(ofLineContaining: "xRadius: 10", in: Self.markdownImageDecorationFixture)
                == "CadenceTextView.drawMarkdownImages"
        )
        // Nested one scope deeper again, inside the `if let` — same answer, which is the claim.
        #expect(
            Self.declarationPath(ofLineContaining: "xRadius: 8", in: Self.markdownImageDecorationFixture)
                == "CadenceTextView.drawMarkdownImages"
        )
        #expect(
            Self.declarationPath(ofLineContaining: "cornerRadius: 10", in: Self.timelineBlockStyleFixture)
                == "TimelineBlockStyle.schedule"
        )
        #expect(
            Self.declarationPath(ofLineContaining: "cornerRadius: 9", in: Self.timelineBlockStyleFixture)
                == "TimelineBlockStyle.calendar"
        )
    }

    /// **Direction one: it still excuses the real site after lines are inserted above it.** This is
    /// the failure of 2026-09-19 replayed — seven lines pushed in above the excused literal — with
    /// the line number shown moving and the exemption shown not caring.
    @Test
    func theDeclarationAnchorSurvivesLinesInsertedAboveTheSiteItExcuses() throws {
        let file = "Cadence/macOS/Views/TimelineMetrics.swift"
        let pushed = String(repeating: "// an unrelated edit, seven lines of it\n", count: 7)
            + Self.timelineBlockStyleFixture

        let before = Self.literalRadiusTenSites(in: Self.timelineBlockStyleFixture, file: file)
        let after = Self.literalRadiusTenSites(in: pushed, file: file)
        #expect(before.count == 1 && after.count == 1)
        // Non-vacuity: the line really did move, which is what used to break the exemption.
        #expect(after.first?.line == (before.first.map { $0.line + 7 }))
        #expect(before.first?.declaration == after.first?.declaration)

        #expect(Self.unexemptedLiteralRadiusTenSites(in: Self.timelineBlockStyleFixture, file: file).isEmpty)
        #expect(
            Self.unexemptedLiteralRadiusTenSites(in: pushed, file: file).isEmpty,
            "the exemption stopped matching its own site because unrelated lines moved it"
        )
    }

    /// **Direction two: it still catches a different literal `10` in the same file.** The sibling
    /// `TimelineBlockStyle.calendar` is converged onto `10` — the "genuine control-radius site
    /// added later" the original file+line pair existed to refuse — and the sweep must still
    /// report it while the excused sibling stays excused.
    @Test
    func theDeclarationAnchorStillRefusesADifferentSiteInTheSameFile() throws {
        let file = "Cadence/macOS/Views/TimelineMetrics.swift"
        let copied = Self.timelineBlockStyleFixture
            .replacingOccurrences(of: "cornerRadius: 9", with: "cornerRadius: 10")
        let hits = Self.unexemptedLiteralRadiusTenSites(in: copied, file: file)
        #expect(hits.count == 1, "expected exactly the unexcused sibling, got \(hits)")
        #expect(hits.first?.declaration == "TimelineBlockStyle.calendar")

        // And the same `10` copied into the *excused* declaration is not absorbed silently
        // either: it is what `eachExemptionStillHoldsExactlyTheOneLiteralItWasExcusedFor`
        // refuses, so the coarser anchor does not quietly widen in place.
        let doubled = Self.timelineBlockStyleFixture
            .replacingOccurrences(
                of: "    minHeight: 24,",
                with: "    minHeight: 24,\n        badgeCornerRadius: 10,"
            )
        let held = Self.literalRadiusTenSites(in: doubled, file: file)
            .filter { $0.declaration == "TimelineBlockStyle.schedule" }
        #expect(held.count == 2, "the fixture did not gain a second literal, so the count proves nothing")
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
