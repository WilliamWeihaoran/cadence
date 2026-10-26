#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Cadence

/// **What the macOS Calendar, Focus and Notes pages publish to assistive tech** ([[T-7064]],
/// [[T-7065]], [[T-7066]]), read off a real accessibility tree where the view can be hosted bare.
///
/// The harness is `CadenceEyebrowAccessibilityTests`': an `NSHostingView` in an offscreen window,
/// with the application's *enhanced user interface* attribute set — what VoiceOver sets — so
/// SwiftUI builds its accessibility children. What it measures is the tree SwiftUI hands AppKit;
/// it does not claim what VoiceOver *speaks*, and no announcement was heard for any of these.
/// `theHarnessSeesAButtonLabelAndASelection` re-measures that the tree is reachable at all, so an
/// absence below is a measurement and not blindness.
///
/// Two halves are source scans instead, each saying why: the unlinked-mention row is `private` and
/// drawn only once its footer is expanded by a click, and iOS is not compiled by this target.
@MainActor
struct CadenceMacPageAccessibilityAuditTests {

    private struct Node: CustomStringConvertible {
        let role: String
        let label: String
        let value: String
        let isSelected: Bool
        var description: String { "[\(role) label:'\(label)' value:'\(value)'\(isSelected ? " selected" : "")]" }
    }

    private func allNodes<V: View>(in view: V, size: NSSize = NSSize(width: 900, height: 120)) -> [Node] {
        let app = NSApplication.shared
        let enhanced = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        _ = app.perform(enhanced, with: NSNumber(value: true))
        defer { _ = app.perform(enhanced, with: NSNumber(value: false)) }

        let host = NSHostingView(rootView: view.padding(8))
        host.frame = NSRect(origin: .zero, size: size)
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
        // SwiftUI's `AccessibilityNode` answers `isAccessibilitySelected` but does not cast to
        // `NSAccessibilityProtocol` from Swift (measured: the cast reads `false` for a node whose
        // key-value read is 1), so the property is read by key, and only where it is answered.
        func isSelected(_ object: AnyObject) -> Bool {
            guard let node = object as? NSObject,
                  node.responds(to: NSSelectorFromString("isAccessibilitySelected")) else { return false }
            return (node.value(forKey: "accessibilitySelected") as? NSNumber)?.boolValue ?? false
        }
        func walk(_ element: Any, depth: Int) {
            guard depth < 24 else { return }
            let object = element as AnyObject
            nodes.append(Node(
                role: string(object, "accessibilityRole"),
                label: string(object, "accessibilityLabel"),
                value: string(object, "accessibilityValue"),
                isSelected: isSelected(object)
            ))
            let childrenSelector = NSSelectorFromString("accessibilityChildren")
            guard object.responds(to: childrenSelector),
                  let children = object.perform(childrenSelector)?.takeUnretainedValue() as? [Any] else { return }
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(host, depth: 0)
        return nodes
    }

    private static let buttonRole = NSAccessibility.Role.button.rawValue

    /// **The control.** A labelled button, and the same button with `.isSelected`, both found by
    /// label and the second read as selected. If either half ever reads blank, every absence and
    /// every `isSelected == false` below is the harness going blind, not the view.
    @Test func theHarnessSeesAButtonLabelAndASelection() {
        let nodes = allNodes(in: HStack {
            Button("Plain") {}.accessibilityLabel("Plain control")
            Button("Chosen") {}.accessibilityLabel("Chosen control").accessibilityAddTraits(.isSelected)
        })
        let plain = nodes.filter { $0.label == "Plain control" }
        let chosen = nodes.filter { $0.label == "Chosen control" }
        #expect(plain.count == 1, "the harness cannot see a labelled button: \(nodes)")
        #expect(chosen.count == 1, "the harness cannot see a labelled button: \(nodes)")
        #expect(plain.first?.isSelected == false, "\(nodes)")
        #expect(chosen.first?.isSelected == true, "the harness cannot read .isSelected, so no selection test below means anything: \(nodes)")
    }

    // MARK: - T-7064: the Calendar page

    /// The toolbar's Week / Month / Board control draws the current mode in blue and announced none
    /// of it: three plain buttons. One is selected now, the one the plate marks, in each state.
    @Test func theCalendarModeControlAnnouncesWhichModeIsOn() {
        func toolbar(_ mode: CadenceCalendarViewMode, _ presentation: CadenceCalendarPresentation) -> [Node] {
            allNodes(in: CalendarPageToolbar(
                calendarTitleLabel: "October 2026",
                viewMode: mode,
                presentation: presentation,
                scrollToToday: {},
                setViewMode: { _ in },
                setPresentation: { _ in },
                moveBoardWindow: { _ in },
                canMoveBoardWindowBack: false,
                zoomLevel: .constant(1)
            ))
        }
        let modeTitles = CadenceCalendarViewMode.pickerCases.map(\.rawValue) + ["Board"]

        for (mode, presentation, expected) in [
            (CadenceCalendarViewMode.week, CadenceCalendarPresentation.timeline, CadenceCalendarViewMode.week.rawValue),
            (.month, .timeline, CadenceCalendarViewMode.month.rawValue),
            (.week, .board, "Board"),
        ] {
            let nodes = toolbar(mode, presentation)
            let segments = nodes.filter { node in
                modeTitles.contains { node.label == $0 || node.value == $0 }
                    && node.role == Self.buttonRole
            }
            #expect(segments.count == modeTitles.count, "non-vacuity: the mode buttons are not on the tree: \(nodes)")
            let selected = segments.filter(\.isSelected).map { $0.label.isEmpty ? $0.value : $0.label }
            #expect(selected == [expected], "\(presentation)/\(mode) announces \(selected) as the mode: \(segments)")
        }
    }

    /// The timeline day header said "Mon" and "26" as two loose words; iOS's says the day and what
    /// its band holds (T-573). The Mac header reads the same shared builder now, and its weekday
    /// text is still its own element underneath (the rule `CadenceEyebrowAccessibilityTests` pins).
    @Test func theTimelineDayHeaderNamesItsDay() throws {
        let date = try #require(DateFormatters.date(from: "2026-08-31"))
        let nodes = allNodes(in: CalDayHeaderView(date: date, todayKey: "2026-10-26"), size: NSSize(width: 160, height: 120))
        let expected = CadenceCalendarDayAccessibility.timelineDayLabel(date: date, allDayEventCount: 0, unscheduledCount: 0)
        #expect(expected == DateFormatters.longDate.string(from: date), "non-vacuity: the shared label changed shape")
        #expect(
            nodes.contains { $0.label == expected },
            "the Mac timeline day header does not name its day: \(nodes)"
        )
        #expect(
            nodes.contains { $0.value == DateFormatters.dayOfWeek.string(from: date) },
            "the header's weekday is no longer its own element: \(nodes)"
        )
    }

    /// The Board's collapsed rail is one button, "Expand Overdue". The column around it carries
    /// "Overdue, 0 tasks" on a stack that was not an accessibility element — the shape [[T-7034]]
    /// suspected hands a label to every child. Measured here: the button keeps its own verb.
    @Test func theCollapsedBoardRailKeepsItsOwnButtonName() {
        let nodes = allNodes(in: CalendarBoardRailColumn(
            rail: .overdue,
            tasks: [],
            todayKey: "2026-10-26",
            add: nil,
            form: .collapsed,
            onToggleForm: {},
            onDrop: { _ in false }
        ), size: NSSize(width: 120, height: 360))
        #expect(
            nodes.contains { $0.role == Self.buttonRole && $0.label == "Expand Overdue" },
            "the collapsed rail's button lost its own name to the column's: \(nodes)"
        )
        #expect(
            nodes.contains { $0.label == "Overdue, 0 tasks" },
            "the rail column no longer names itself: \(nodes)"
        )
    }

    // MARK: - T-7065: the Focus page

    /// "Next up" rows were named "Focus this task", the tooltip's words, so every row announced the
    /// same three words. Each names the task it starts now, with its detail line as the value.
    @Test func aNextUpRowNamesTheTaskItStarts() {
        let task = AppTask(title: "Write report")
        let nodes = allNodes(in: FocusSidebarTaskRow(task: task, action: {}), size: NSSize(width: 340, height: 80))
        let row = nodes.filter { $0.role == Self.buttonRole }
        #expect(row.count == 1, "non-vacuity: the row is not one button on the tree: \(nodes)")
        #expect(row.first?.label == CadenceFocusSupport.focusTaskControlLabel(title: "Write report"), "\(row)")
        #expect(row.first?.label == "Focus Write report", "\(row)")
        #expect(
            row.first?.value == CadenceFocusSupport.sidebarDetail(for: task, todayKey: DateFormatters.todayKey()),
            "the row's detail line is not its value: \(row)"
        )
        #expect(nodes.contains { $0.label == "Focus this task" } == false, "\(nodes)")
    }

    /// The Log Session popover printed `task.title` raw, so an untitled task's popover had an empty
    /// line where the session header behind it says "Untitled Task".
    @Test func theLogSessionPopoverNamesAnUntitledTaskAsTheHeaderDoes() {
        let nodes = allNodes(
            in: LogSessionPopover(task: AppTask(title: "   "), elapsedSeconds: 600, onLog: { _, _, _ in }, onDiscard: {}),
            size: NSSize(width: 280, height: 260)
        )
        #expect(nodes.contains { $0.value == "Log Session" }, "non-vacuity: the popover is not on the tree: \(nodes)")
        #expect(
            nodes.contains { $0.value == TaskTitleSupport.defaultDisplayTitle },
            "the popover does not name an untitled task \"\(TaskTitleSupport.defaultDisplayTitle)\": \(nodes)"
        )
    }

    // MARK: - T-7066: the Notes page

    @Test func anUnlinkedMentionLinkControlIsNamedForItsNote() throws {
        #expect(NoteUnlinkedMentionCopy.linkControlLabel(noteTitle: "Weekly Review") == "Link Weekly Review")

        // A scan: `NoteUnlinkedMentionRow` is private, and drawn only once its footer is expanded.
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorAccessoryViews.swift")
        )
        let row = try CadenceControlAccessibilityLabelTests.bodyOfStruct("NoteUnlinkedMentionRow", in: mac)
            .filter { !$0.isWhitespace }
        #expect(row.contains("Button(action:action)"), "non-vacuity: the row no longer draws its Link button")
        #expect(
            row.contains(".accessibilityLabel(NoteUnlinkedMentionCopy.linkControlLabel(noteTitle:title))"),
            "the Mac unlinked-mention Link button is not named for its note"
        )

        // iOS, which is not compiled here, reads the same spelling.
        let ios = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        ).filter { !$0.isWhitespace }
        #expect(ios.contains(".accessibilityLabel(NoteUnlinkedMentionCopy.linkControlLabel(noteTitle:note.displayTitle))"))
    }
}
#endif
