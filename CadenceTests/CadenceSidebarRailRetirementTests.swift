import Foundation
import Testing

/// **The sidebar rail is deleted, and this is what keeps it deleted (T-3079).**
///
/// `iOSSidebarStyle` had two cases. `.rail` was an icon-rail spelling of the iPad column for a
/// narrow window, and nothing could reach it: `iOSSidebar` is constructed in exactly one place and
/// always with `.expanded`, `iOSTasksTabView` holds `private let style: iOSSidebarStyle =
/// .expanded`, and the `style(for:)` that computed `.rail` below
/// `CadenceRootShellLayout.expandedMinWindowWidth` had no callers at all. Reachable it would still
/// not have drawn a rail: the narrow-window answer is a *drawer* whose width is
/// `min(expandedWidth, width)`, so the column would have been 264pt wide with rail-width glyphs in
/// it. The owner's decision was to delete rather than deprecate — a genuine icon rail gets designed
/// against the real narrow-window layout if it is ever wanted.
///
/// So this is an **absence** pin, which is the kind that is worthless without a non-vacuity claim:
/// "no file declares it" and "no file was read" look identical in a green run. Both halves are
/// supplied by `CadenceScanInstrument` — the constructor refuses a detector that has stopped
/// discriminating between its two literal witnesses, and `sweep(atLeast:including:)` refuses a walk
/// that reached too few files or missed the one file the rule is about.
///
/// The witnesses are literals rather than repo files on purpose: a fixture read out of the tree can
/// be retuned by the same edit that breaks the rule.
struct CadenceSidebarRailRetirementTests {

    // MARK: - The style

    /// Nothing declares `iOSSidebarStyle.rail`, as a case or at a call site.
    ///
    /// Two instruments rather than one disjunction, because an `||` detector fires on its positive
    /// witness while half of it is blind. The call-site needle is the one that would catch the
    /// cheap mistake — a `style: .rail` added before anyone notices the case is gone — and the case
    /// needle catches the case coming back.
    @Test func noProductFileDeclaresTheRetiredSidebarRailStyle() throws {
        let caseArm = try CadenceScanInstrument(
            "a rail case inside enum iOSSidebarStyle",
            fires: Self.railCaseWitness,
            andNotOn: Self.railFreeWitness
        ) { code in
            guard let body = CadenceSourceScan.declarationBody("enum iOSSidebarStyle", in: code) else {
                return false
            }
            return CadenceSourceScan.matchCount(#"\bcase\s+rail\b"#, in: body) > 0
        }

        let callSite = try CadenceScanInstrument(
            "a call site naming the rail style",
            fires: Self.railCallSiteWitness,
            andNotOn: Self.railFreeWitness
        ) { code in
            Self.namesTheRailStyle(code)
        }

        let paths = try Self.productSwiftFiles()
        let read = Self.codeReader()

        for instrument in [caseArm, callSite] {
            let offenders = try instrument.sweep(
                paths,
                atLeast: Self.knownProductFileFloor,
                including: Self.sidebarPath,
                read: read
            )
            #expect(
                offenders.isEmpty,
                """
                iOSSidebarStyle.rail is back — \(instrument.name) fires in: \
                \(offenders.joined(separator: ", "))
                """
            )
        }
    }

    // MARK: - The labels it drew

    /// Nothing declares a `railLabel`. Both of them — `iOSSidebarButton`'s glyph-and-badge stack
    /// and `iOSSidebarListRow`'s single initial — existed only to be the `else` of a
    /// `style == .expanded`, so the name going is the deletion being complete rather than hidden
    /// behind a branch that is now unreachable for a second reason.
    @Test func noProductFileDeclaresASidebarRailLabel() throws {
        let instrument = try CadenceScanInstrument(
            "a railLabel declaration",
            fires: Self.railLabelWitness,
            andNotOn: Self.railLabelFreeWitness
        ) { code in
            CadenceSourceScan.matchCount(#"\brailLabel\b"#, in: code) > 0
        }

        let offenders = try instrument.sweep(
            try Self.productSwiftFiles(),
            atLeast: Self.knownProductFileFloor,
            including: Self.sidebarPath,
            read: Self.codeReader()
        )

        #expect(
            offenders.isEmpty,
            """
            a sidebar railLabel is back — \(instrument.name) fires in: \
            \(offenders.joined(separator: ", "))
            """
        )
    }

    /// The deletion's positive half, so the suite is not three absence assertions in a row: the
    /// one surviving case is still spelled, still carries the padding the column draws with, and
    /// the two hosts still hand it over.
    ///
    /// This is also what would notice the other way to make the pins above vacuous — deleting
    /// `iOSSidebarStyle` outright, which would leave every needle with nothing to match and every
    /// sweep green.
    @Test func theSurvivingSidebarStyleIsStillTheOneBothTouchHostsPass() throws {
        let sidebar = try Self.codeReader()(Self.sidebarPath)
        #expect(sidebar.count > 400, "the sidebar read as \(sidebar.count) characters")
        let body = try #require(
            CadenceSourceScan.declarationBody("enum iOSSidebarStyle", in: sidebar),
            "enum iOSSidebarStyle is gone, which would make every absence pin in this suite vacuous"
        )
        #expect(body.contains("case expanded"), "the one surviving style case is gone")
        #expect(body.contains("var horizontalPadding: CGFloat"),
                "the column's horizontal padding left the style, so the pins above guard a shell")

        #expect(sidebar.contains("let style: iOSSidebarStyle"),
                "the iPad column stopped taking a style")

        let tasksTab = try Self.codeReader()("Cadence/iOS/iOSTasksTabView.swift")
        #expect(tasksTab.count > 400, "the Tasks index read as \(tasksTab.count) characters")
        #expect(tasksTab.contains("private let style: iOSSidebarStyle = .expanded"),
                "the phone's Tasks index stopped naming the expanded style")
    }

    // MARK: - The walk

    static let sidebarPath = "Cadence/iOS/iOSRootSidebar.swift"

    /// A floor, not a count: the tree grows, and a sweep that had to be re-tuned on every added
    /// file would be re-tuned by the change that breaks it. 615 Swift files existed when this was
    /// written.
    static let knownProductFileFloor = 550

    static func productSwiftFiles() throws -> [String] {
        try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
    }

    /// `codeOnly`, not `strippingComments`: every needle here is a declaration shape, and a scan
    /// that does not blank string literals counts prose and fixtures as code.
    static func codeReader() -> (String) throws -> String {
        var cache: [String: String] = [:]
        return { path in
            if let hit = cache[path] { return hit }
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            cache[path] = code
            return code
        }
    }

    private static func namesTheRailStyle(_ code: String) -> Bool {
        CadenceSourceScan.matchCount(#"iOSSidebarStyle\s*\.\s*rail\b(?!\()"#, in: code) > 0
            || CadenceSourceScan.matchCount(#"\bstyle\b\s*(?:==|!=|:)\s*\.rail\b(?!\()"#, in: code) > 0
    }

    // MARK: - Witnesses

    static let railCaseWitness = """
    enum iOSSidebarStyle: Equatable {
        case rail
        case expanded
    }
    """

    static let railCallSiteWitness = """
    iOSSidebarHeader(style: .rail, onSearch: onSearch, onCollapse: onCollapse)
    """

    /// The nearest rail-free source, and it carries the decoy deliberately:
    /// `CadenceCalendarPlanningSupport.CalendarBoardDropTarget` has a `case rail` of its own, with a
    /// payload, about a calendar board's Overdue/Unscheduled columns. A needle that caught it would
    /// be red on a tree that obeys this rule perfectly.
    static let railFreeWitness = """
    enum CalendarBoardDropTarget: Equatable {
        case rail(CalendarBoardRail)
        case day(String)
    }

    func accepts(_ target: CalendarBoardDropTarget) -> Bool {
        if case .rail(let rail) = target { return rail.acceptsDrops }
        return true
    }

    enum iOSSidebarStyle: Equatable {
        case expanded

        var horizontalPadding: CGFloat {
            switch self {
            case .expanded: return 10
            }
        }
    }

    private let style: iOSSidebarStyle = .expanded
    """

    static let railLabelWitness = """
    private var railLabel: some View {
        Text(initial)
    }
    """

    /// Nearest again: the word "rail" survives in this file as a *divider's* name, and "Label" is in
    /// half the view code in the repo. Neither is `railLabel`.
    static let railLabelFreeWitness = """
    struct iOSSidebarRailDivider: View {
        var body: some View { Rectangle() }
    }

    private var expandedLabel: some View {
        Text(title)
    }
    """
}
