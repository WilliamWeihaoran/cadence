import Foundation
import Testing
@testable import Cadence

/// The ~100pt black band between the iPad list-detail tab strip (`Tasks / Kanban / Notes / Links /
/// Completed`) and the page under it — measured at exactly 100pt on an iPad Pro 13-inch, in **all
/// five** tabs.
///
/// **What it was.** `iOSListDetailView` takes `.iOSFloatingCreateTaskButton(seed:)`, which writes
/// `.contentMargins(.bottom, iOSCircularAddButton.scrollClearance, for: .scrollContent)` — 56 + 22×2
/// = 100pt — so the page's bottom-reaching list can always be brought out from under the corner `+`.
/// `contentMargins` is inherited through the environment, so it also landed on
/// `iOSListDetailPagePicker`, whose tab strip is a **horizontal** `ScrollView`. A `.bottom` margin on
/// a horizontal scroll view grows its *cross* axis: the 44pt tab row became a 144pt strip with 100pt
/// of empty content region under the tabs. The band therefore sat above `pageBody`, which is why one
/// defect presented as five — it was in front of Tasks, Kanban, Notes, Links and Completed alike.
/// Removing the button modifier moved the hairline under the strip from 230pt back to 130pt, which is
/// the measurement that named the cause.
///
/// Compact width was never affected: the host passes `0` there, because the iPhone tab bar's centre
/// `+` is the capture affordance and no compact page floats one.
///
/// **This is the third instance of `D-104`.** The two markdown accessory strips hit the same
/// inheritance and carry the same reset; their count is pinned by
/// `CadenceNoteReferencePanelSurfaceTests`, and is deliberately not restated here.
///
/// **A layout gap is not directly pinnable by this target.** The band's *height* is a SwiftUI
/// measurement on a real iPad, and `Cadence/iOS/` is inside `#if os(iOS)` so there is not even a
/// symbol to instantiate from a macOS test host. What is pinnable is the pair of lines that produce
/// and cancel it, which is what these scans read: the reset is inside the strip, the strip is the
/// only thing in its file that carries one, and the page-level clearance the reset gives back is
/// still written once and still gated on size class — so "fixing" the band by deleting the clearance
/// (and re-burying the last row under the button) fails here too.
///
/// Source-text assertions are the only tool available, following `CadenceSharedBoardChromeTests` and
/// `CadenceNoteReferencePanelSurfaceTests`: exact per-file counts, comment-stripping rather than
/// allowlisting, a non-vacuity guard, and a self-check on the declaration slicer so a typo in it
/// cannot make every scan pass silently.
struct CadenceListDetailTabStripMarginTests {

    // MARK: - The band, and the line that closes it

    /// **The fix, where it has to be.** The reset is scoped to the `iOSListDetailPagePicker`
    /// declaration rather than to the file, so a reset that drifted onto the kanban board's scroll
    /// view — which *is* the page's bottom-reaching content and must keep the clearance — could not
    /// satisfy this.
    ///
    /// The needles are loose on purpose. `ScrollView(.horizontal` matches the
    /// `showsIndicators:` spelling the rest of the app also uses, and `, 0, for: .scrollContent)`
    /// accepts `.vertical`, `.bottom` or `.top` — any zero reset scoped to scroll content is the
    /// fix; only the absence of one is the bug.
    @Test func theListDetailTabStripCancelsTheScrollMarginsItInherits() throws {
        let picker = try declaration(
            named: "iOSListDetailPagePicker",
            in: try strippingComments(sourceFile("Cadence/iOS/iOSListSupportViews.swift"))
        )

        #expect(picker.contains("ScrollView(.horizontal"))
        #expect(picker.contains("contentMargins("))
        #expect(picker.contains(", 0, for: .scrollContent)"))
    }

    /// **One reset in the file, and none at the host.** The strip owns the reset because a
    /// single-row horizontal scroll view is never a page's bottom-reaching content; the kanban
    /// board's horizontal scroll view in the same file is, so it must go on inheriting the
    /// clearance. And `iOSListDetailView` must not carry a `contentMargins` of its own: per-screen
    /// compensation for the button's footprint is exactly what
    /// `iOSFloatingCreateTaskLayer` exists to prevent.
    @Test func theResetIsTheStripsAloneAndTheHostCompensatesForNothing() throws {
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSListSupportViews.swift"))
        #expect(support.components(separatedBy: "contentMargins(").count - 1 == 1)

        let host = try strippingComments(sourceFile("Cadence/iOS/iOSListDetailView.swift"))
        #expect(host.components(separatedBy: "contentMargins(").count - 1 == 0)
        #expect(host.components(separatedBy: ".iOSFloatingCreateTaskButton(").count - 1 == 1)
    }

    /// **The clearance the reset gives back is still there.** Deleting the page-level margin would
    /// also close the band, and would re-bury the last row of every regular-width task list under
    /// the 56pt button. It is written once, in the modifier rather than at the four call sites, and
    /// it is still `0` at compact width.
    @Test func thePageClearanceForTheFloatingButtonSurvivesAndStaysSizeClassGated() throws {
        let button = try strippingComments(sourceFile("Cadence/iOS/iOSFloatingCreateTaskButton.swift"))

        #expect(button.components(separatedBy: "contentMargins(").count - 1 == 1)
        #expect(button.contains(".contentMargins(.bottom, isRegularWidth ? iOSCircularAddButton.scrollClearance : 0, for: .scrollContent)"))

        // 100pt — the band's measured height is the button's whole footprint, so the two numbers are
        // the same number and a change to either should be a change made on purpose.
        #expect(button.contains("floatingDiameter: CGFloat = 56"))
        #expect(button.contains("edgeInset: CGFloat = 22"))
        #expect(button.contains("floatingDiameter + edgeInset * 2"))
    }

    // MARK: - Guards on the scans above

    /// **Non-vacuity.** Every `contains` and every zero-count above passes against an empty string,
    /// which is what a missing file or a `/tmp` against `/private/tmp` path mismatch produces on an
    /// isolated build tree. So: the files were read, and the comment stripper stripped.
    @Test func theScansReadRealSourceThroughARealStripper() throws {
        let raw = try sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        #expect(raw.count > 3_000)
        #expect(raw.contains("struct iOSListDetailPagePicker"))

        let stripped = try strippingComments(raw)
        #expect(stripped.count == raw.count)
        #expect(stripped.contains("struct iOSListDetailPagePicker"))
        // The explanatory comment above the reset names the modifier it cancels; the stripper must
        // remove that mention, or the scans are reading prose.
        #expect(raw.contains("iOSCircularAddButton.scrollClearance"))
        #expect(!stripped.contains("iOSCircularAddButton.scrollClearance"))
    }

    /// **Self-check on the slicer.** A scoped scan is only as good as the scope: if `declaration`
    /// silently returned the whole file, the first test would pass on a reset written anywhere at
    /// all. Run it against literals that must and must not be included.
    @Test func theDeclarationSlicerStopsAtTheNextTopLevelDeclaration() throws {
        let source = """
        struct Wanted: View {
            var body: some View { inside }
        }

        struct Unwanted: View {
            var body: some View { outside }
        }
        """

        let sliced = try declaration(named: "Wanted", in: source)
        #expect(sliced.contains("inside"))
        #expect(!sliced.contains("outside"))
        #expect(throws: DeclarationSliceError.self) {
            try declaration(named: "Absent", in: source)
        }
    }
}

// MARK: - Helpers

private enum DeclarationSliceError: Error {
    case notFound(String)
}

/// The body of one top-level `struct … : View {` declaration, up to the next top-level `struct`.
///
/// Throwing rather than returning the whole file when the name is absent is the point: a rename
/// should fail the scan loudly, not widen its scope to everything.
private func declaration(named name: String, in source: String) throws -> String {
    guard let start = source.range(of: "struct \(name): View {") else {
        throw DeclarationSliceError.notFound(name)
    }
    let rest = source[start.upperBound...]
    guard let end = rest.range(of: "\nstruct ") else { return String(rest) }
    return String(rest[..<end.lowerBound])
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make these
/// checks stricter about what counts as a comment, never looser about live code. Length-preserving,
/// which is what lets `theScansReadRealSourceThroughARealStripper` prove it ran at all.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
