import Foundation
import Testing

// MARK: - T-11491: a compact page with its navigation bar hidden still backs the status bar

/// **The iPhone's status bar has no backing of its own, and the navigation bar was it.**
///
/// Every compact page hides its navigation bar through `iOSHidesCompactNavigationBar()` and heads
/// itself instead. Where the page's top element is a `ScrollView` — Settings and its categories,
/// the More tab, Focus, a pushed Today, All Tasks or Inbox — the scrolled content rises into the
/// top safe-area inset, and with the bar gone nothing sat between it and the clock. Seen on
/// `Cadence-iPhone15` on Settings > Tags: a row's title through the clock, its archive button
/// through the battery. Pages whose header is pinned above their scroll view (Calendar, Notes, the
/// Tasks tab index, the Tasks page, a list's detail) never scroll into the strip.
///
/// **A source scan, because it has to be.** `CadenceTests` builds for macOS and
/// `iOSDesignSystem.swift` is a whole-file `#if os(iOS)`, so the modifier cannot be evaluated here.
@MainActor
struct CadenceIOSStatusBarFillTests {

    private let designSystemPath = "Cadence/iOS/iOSDesignSystem.swift"

    /// The compact branch of the modifier — the text between `if horizontalSizeClass == .compact`
    /// and its `else`. Regular width is the iPad, hosted with no stack, and is left alone.
    private func compactBranch() throws -> String {
        let source = try CadenceSourceScan.sourceFile(designSystemPath)
        let body = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCompactNavigationBarHidden", in: source),
            "the modifier behind iOSHidesCompactNavigationBar() is gone or renamed"
        )
        let branchStart = try #require(body.range(of: "if horizontalSizeClass == .compact"))
        let tail = body[branchStart.upperBound...]
        let elseMark = try #require(tail.range(of: "} else {"))
        return String(tail[..<elseMark.lowerBound])
    }

    /// Hiding the bar and backing the strip happen together: the compact branch that hides the bar
    /// also lays a fill through the top safe-area edge, and the fill is the caller's colour.
    @Test func theCompactBranchThatHidesTheBarAlsoFillsTheStatusBarStrip() throws {
        let branch = try compactBranch()

        #expect(branch.contains(".toolbar(.hidden, for: .navigationBar)"), "the compact branch no longer hides the bar")
        #expect(
            branch.contains(".safeAreaInset(edge: .top, spacing: 0)"),
            "nothing is laid along the top safe-area edge, so scrolled content runs under the clock"
        )
        #expect(
            branch.contains(".background(statusBarFill, ignoresSafeAreaEdges: .top)"),
            "the strip's fill does not reach up through the status bar, or is not the caller's colour"
        )
        // The inset must not push any page down: unscrolled, these pages are already right.
        #expect(branch.contains(".frame(height: 0)"), "the inset takes height, which moves every compact page down")
    }

    /// Every caller's strip is the colour that page paints behind itself, so the scrolled page looks
    /// like the unscrolled one. A page painted in anything but `Theme.bg` names its colour.
    @Test func everyCallerFillsTheStripWithItsOwnPageColour() throws {
        var callers = 0
        var mismatches: [String] = []

        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/iOS") where path != designSystemPath {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let lines = code.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(".iOSHidesCompactNavigationBar(") {
                callers += 1
                // The nearest page background above the call, within the same modifier chain.
                let window = lines[max(0, index - 40)..<index].reversed()
                let backing = window.lazy.compactMap { candidate -> String? in
                    guard let open = candidate.range(of: ".background(Theme."),
                          let close = candidate.range(of: ".ignoresSafeArea()", range: open.upperBound..<candidate.endIndex)
                    else { return nil }
                    return String(candidate[open.upperBound..<close.lowerBound])
                }.first ?? "bg"
                let expected = backing == "bg"
                    ? ".iOSHidesCompactNavigationBar()"
                    : ".iOSHidesCompactNavigationBar(statusBarFill: Theme.\(backing))"
                if !line.contains(expected) {
                    mismatches.append("\(path):\(index + 1) paints Theme.\(backing), calls `\(line.trimmingCharacters(in: .whitespaces))`")
                }
            }
        }

        // Non-vacuity: eleven call sites under Cadence/iOS when this was written.
        #expect(callers >= 10, "found only \(callers) callers of iOSHidesCompactNavigationBar")
        #expect(mismatches.isEmpty, "status-bar strip differs from the page colour: \(mismatches.joined(separator: "; "))")
    }
}
