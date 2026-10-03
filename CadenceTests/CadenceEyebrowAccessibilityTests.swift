#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Cadence

/// **What an uppercase label publishes to assistive tech, read off a real accessibility tree**
/// (T-2022).
///
/// T-2022 was filed because the Edit Area sheet's one static text carried an *empty label* in
/// XCUITest, and `.kerning` at the end of `cadenceUppercaseLabel` was the suspect. Measured here,
/// on an `NSHostingView`'s own accessibility nodes: **a macOS SwiftUI `Text` publishes its string
/// as the static text's value and leaves the label empty — kerned or not, eyebrow or not.** So the
/// heading was never gone; XCUITest's `.label` was reading the one field macOS static text does not
/// fill. What the eyebrow *did* publish was its glyphs, `EDIT AREA`, which is what a screen reader
/// is likeliest to spell out. The fix is `cadenceUppercaseLabel(reading:size:kerning:)`, which
/// publishes the words in natural case — and on macOS a `Text`'s `.accessibilityLabel` lands in
/// that same value, which is what these tests read.
///
/// **Why this is not a source scan.** `CadenceControlAccessibilityLabelTests` records that a
/// modifier's accessibility attachment is not queryable headlessly, and with a bare hosting view it
/// is not: SwiftUI builds no accessibility children until something asks as an assistive client
/// would. Setting the application's *enhanced user interface* attribute — what VoiceOver sets — is
/// that ask, and afterwards the nodes answer. The control test below is what keeps that honest: if
/// the tree ever comes back empty again, it fails before the eyebrow assertions mean anything.
@MainActor
struct CadenceEyebrowAccessibilityTests {

    private struct Node: CustomStringConvertible {
        let role: String
        let label: String
        let value: String
        var description: String { "[\(role) label:'\(label)' value:'\(value)']" }
    }

    /// The static texts a view publishes, in tree order.
    private func staticTexts<V: View>(in view: V) -> [Node] {
        allNodes(in: view).filter { $0.role == NSAccessibility.Role.staticText.rawValue }
    }

    /// AppKit declares no `NSAccessibility.Role` constant for it; `AXHeading` is the role string
    /// SwiftUI publishes for `.isHeader` on macOS, as the control in
    /// `theEyebrowIsAHeadingAndTheWeekdayRailIsNot` re-measures on every run.
    private static let headingRole = "AXHeading"

    /// The headings a view publishes, in tree order. On macOS SwiftUI turns `.isHeader` into a
    /// change of ROLE — `AXHeading` in place of `AXStaticText` — and moves the string from the
    /// value to the label (measured for T-2035), so a heading is found by role and read by label.
    private func headings<V: View>(in view: V) -> [Node] {
        allNodes(in: view).filter { $0.role == Self.headingRole }
    }

    private func allNodes<V: View>(in view: V) -> [Node] {
        let app = NSApplication.shared
        let enhanced = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        _ = app.perform(enhanced, with: NSNumber(value: true))
        defer { _ = app.perform(enhanced, with: NSNumber(value: false)) }

        let host = NSHostingView(rootView: view.padding(8))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 80)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
        _ = host.accessibilityChildren()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        var nodes: [Node] = []
        func string(_ object: AnyObject, _ name: String) -> String {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector), let result = object.perform(selector)?.takeUnretainedValue() else {
                return ""
            }
            return "\(result)"
        }
        func walk(_ element: Any, depth: Int) {
            guard depth < 16 else { return }
            let object = element as AnyObject
            nodes.append(Node(
                role: string(object, "accessibilityRole"),
                label: string(object, "accessibilityLabel"),
                value: string(object, "accessibilityValue")
            ))
            let childrenSelector = NSSelectorFromString("accessibilityChildren")
            guard object.responds(to: childrenSelector),
                  let children = object.perform(childrenSelector)?.takeUnretainedValue() as? [Any] else { return }
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(host, depth: 0)
        return nodes
    }

    /// **The control, and the root cause.** A plain `Text` and the same `Text` kerned publish
    /// identically: one static text, its string in the value, no label. If this ever reads zero
    /// static texts the harness has stopped reaching the tree, and nothing below is a measurement.
    @Test func aMacTextPublishesItsStringAsTheValueWhetherOrNotItIsKerned() {
        let plain = staticTexts(in: Text(verbatim: "Plain Words"))
        let kerned = staticTexts(in: Text(verbatim: "Plain Words").kerning(0.8))

        #expect(plain.count == 1, "the harness read no static text from a bare Text: \(plain)")
        #expect(plain.first?.value == "Plain Words", "\(plain)")
        #expect(plain.first?.label.isEmpty == true, "macOS static text started carrying a label: \(plain)")
        #expect(kerned.map(\.value) == plain.map(\.value), "kerning changed what a Text publishes: \(kerned)")
        #expect(kerned.map(\.label) == plain.map(\.label), "kerning changed what a Text publishes: \(kerned)")
    }

    /// The Edit Area sheet's own heading: the eyebrow publishes the words, once, in natural case —
    /// not the uppercased glyphs it draws. Since T-2035 it is a heading, and a macOS heading carries
    /// its string as the label rather than the value, so that is the field read here.
    @Test func theSectionEyebrowPublishesItsWordsInNaturalCase() {
        let found = headings(in: SectionEyebrowLabel(text: "Edit Area"))
        #expect(found.count == 1, "the eyebrow should publish exactly one heading: \(found)")
        #expect(found.first?.label == "Edit Area", "the eyebrow publishes its glyphs, not its words: \(found)")

        let compact = headings(in: SectionEyebrowLabel(text: "Unassigned", size: .compact))
        #expect(compact.map(\.label) == ["Unassigned"], "the compact tier publishes something else: \(compact)")
    }

    /// **The eyebrow is a heading; a weekday rail is not (T-2035).** VoiceOver's heading navigation
    /// walks `AXHeading` nodes, so an eyebrow without the trait was a section VO-Cmd-H skipped. The
    /// trait is the eyebrow's own, not the shared `cadenceUppercaseLabel` modifier's, because that
    /// modifier also draws the calendar weekday rails, and `Mon` labels a day column — it does not
    /// head a section. Both halves are read off the same tree, beside a control that proves the
    /// harness can see a heading at all, so an absence below is a measurement and not blindness.
    @Test func theEyebrowIsAHeadingAndTheWeekdayRailIsNot() {
        let control = headings(in: Text(verbatim: "Plain Words").accessibilityAddTraits(.isHeader))
        #expect(control.count == 1, "the harness cannot see a heading at all, so nothing below is measured: \(control)")

        let eyebrow = allNodes(in: SectionEyebrowLabel(text: "Edit Area"))
        let eyebrowHeadings = eyebrow.filter { $0.role == Self.headingRole }
        let eyebrowTexts = eyebrow.filter { $0.role == NSAccessibility.Role.staticText.rawValue }
        #expect(eyebrowHeadings.count == 1, "the section eyebrow is not a heading: \(eyebrow)")
        #expect(eyebrowTexts.isEmpty, "the eyebrow also publishes a plain static text: \(eyebrow)")

        let date = Date()
        let weekday = DateFormatters.dayOfWeek.string(from: date)
        let rail = allNodes(in: CalDayHeaderView(date: date))
        let railHeadings = rail.filter { $0.role == Self.headingRole }
        let railTexts = rail.filter { $0.role == NSAccessibility.Role.staticText.rawValue }
        #expect(railTexts.map(\.value).contains(weekday), "the weekday rail is not on the tree, so its absence proves nothing: \(rail)")
        #expect(railHeadings.isEmpty, "a weekday letter became a heading: \(rail)")
    }

    /// The same modifier draws the board column header, so the fix is the modifier's and reaches it
    /// without that site doing anything of its own.
    @Test func theBoardColumnTitlePublishesItsWordsInNaturalCase() {
        let row = CadenceBoardColumnTitleRow(dotColor: Theme.blue, title: "In Progress", count: 3)
        let values = staticTexts(in: row).map(\.value)
        #expect(values.contains("In Progress"), "the column title is not published in natural case: \(values)")
        #expect(!values.contains("IN PROGRESS"), "the column title still publishes its glyphs: \(values)")
    }
}
#endif
