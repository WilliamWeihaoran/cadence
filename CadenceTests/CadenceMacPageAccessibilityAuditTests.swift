#if os(macOS)
import AppKit
import SwiftData
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
        /// Named accessibility actions ([[T-7092]]), read as `accessibilityCustomActions` names.
        var actions: [String] = []
        var description: String {
            "[\(role) label:'\(label)' value:'\(value)'\(isSelected ? " selected" : "")\(actions.isEmpty ? "" : " actions:\(actions)")]"
        }
    }

    /// `perform`, when given, runs the first custom action of that name while the window is still
    /// up, so a test can watch what an assistive client's action does ([[T-7258]]).
    private func allNodes<V: View>(
        in view: V,
        size: NSSize = NSSize(width: 900, height: 120),
        perform actionName: String? = nil
    ) -> [Node] {
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
        var performed = false
        func customActionNames(_ object: AnyObject) -> [String] {
            let selector = NSSelectorFromString("accessibilityCustomActions")
            guard object.responds(to: selector),
                  let actions = object.perform(selector)?.takeUnretainedValue() as? [NSAccessibilityCustomAction]
            else { return [] }
            if let actionName, !performed, let action = actions.first(where: { $0.name == actionName }) {
                performed = true
                if let handler = action.handler {
                    _ = handler()
                } else if let target = action.target as? NSObject, let selector = action.selector {
                    _ = target.perform(selector, with: action)
                }
            }
            return actions.map(\.name)
        }
        func walk(_ element: Any, depth: Int) {
            guard depth < 24 else { return }
            let object = element as AnyObject
            nodes.append(Node(
                role: string(object, "accessibilityRole"),
                label: string(object, "accessibilityLabel"),
                value: string(object, "accessibilityValue"),
                isSelected: isSelected(object),
                actions: customActionNames(object)
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

    // MARK: - T-7068: the Notes page's note rows

    /// Every note list on the Mac Notes page drew `…NoteListRow(...).onTapGesture { select }`: one
    /// `AXGroup` of loose texts, no button, and nothing that said which note was open. Hosted the
    /// way the four tabs host them, each row is one button and the open one reads selected.
    @Test func aNotesPageRowIsAButtonThatSaysWhichNoteIsOpen() {
        let closed = Note(kind: .permanent, title: "Grocery list")
        let open = Note(kind: .permanent, title: "Trip plan")
        let nodes = allNodes(in: VStack(spacing: 0) {
            NoteListRowButton(action: {}) { NotepadNoteListRow(note: closed, isSelected: false) }
            NoteListRowButton(action: {}) { NotepadNoteListRow(note: open, isSelected: true) }
        }, size: NSSize(width: 320, height: 160))
        let rows = nodes.filter { $0.role == Self.buttonRole }
        #expect(rows.count == 2, "a note row is not one button on the tree: \(nodes)")
        let selected = rows.filter(\.isSelected)
        #expect(selected.count == 1, "the open note is not the one selected row: \(rows)")
        #expect(
            selected.first.map { $0.label.contains("Trip plan") || $0.value.contains("Trip plan") } == true,
            "the selected row is not the open note: \(rows)"
        )
    }

    /// The list-detail Notes tab's event and task sections, hosted as the page draws them.
    @Test func theListNotesSectionRowsAreButtonsThatSayWhichIsOpen() {
        let first = Note(kind: .meeting, title: "Standup")
        let second = Note(kind: .meeting, title: "Retro")
        let events = allNodes(
            in: VStack(spacing: 0) {
                ListEventNoteSectionRows(notes: [first, second], selectedNoteID: second.id, onSelect: { _ in })
            },
            size: NSSize(width: 320, height: 160)
        ).filter { $0.role == Self.buttonRole }
        #expect(events.count == 2, "an event-note row is not one button: \(events)")
        #expect(events.filter(\.isSelected).count == 1, "the open event note is not marked selected: \(events)")

        let taskA = AppTask(title: "Draft agenda")
        let taskB = AppTask(title: "Send minutes")
        let tasks = allNodes(
            in: VStack(spacing: 0) {
                ListTaskNoteSectionRows(tasks: [taskA, taskB], todayKey: "2026-10-26", selectedTaskID: taskA.id, onSelect: { _ in })
            },
            size: NSSize(width: 320, height: 160)
        ).filter { $0.role == Self.buttonRole }
        #expect(tasks.count == 2, "a task-note row is not one button: \(tasks)")
        #expect(tasks.filter(\.isSelected).count == 1, "the open task is not marked selected: \(tasks)")
    }

    /// The four tab pages are `private` and need a store, so their call sites are scanned: each
    /// draws its row inside `NoteListRowButton`, and none is a bare tap gesture any more.
    @Test func everyNotesTabDrawsItsRowsAsButtons() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NotesView.swift")
        )
        for page in ["DailyNotesPage", "WeeklyNotesPage", "NotepadPage", "MeetingNotesPage"] {
            let body = try CadenceControlAccessibilityLabelTests.bodyOfStruct(page, in: source)
            #expect(body.contains("NoteListRowButton("), "\(page) no longer draws its rows as buttons")
            #expect(!body.contains(".onTapGesture"), "\(page) selects a row with a tap gesture again")
        }
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

    // MARK: - T-7338: the note's "N mentions" disclosure says whether it is open

    /// Hosted collapsed (its first state; opening it takes a click on a private view), so the
    /// "Expanded" half is the source scan below.
    @Test func theUnlinkedMentionsDisclosureStatesItsState() throws {
        let nodes = allNodes(in: NoteUnlinkedMentionsFooter(
            mentions: [Note(kind: .permanent, title: "Weekly Review"), Note(kind: .permanent, title: "Retro")],
            onLink: { _ in }
        ))
        let toggle = nodes.filter { $0.label == "2 mentions" }
        #expect(toggle.count == 1, "non-vacuity: the footer's disclosure is on the tree: \(nodes)")
        #expect(toggle.first?.value == "Collapsed", "the disclosure states no Collapsed value: \(nodes)")

        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorAccessoryViews.swift")
        )
        let body = try CadenceControlAccessibilityLabelTests.bodyOfStruct("NoteUnlinkedMentionsToggle", in: mac)
            .filter { !$0.isWhitespace }
        #expect(body.contains(".accessibilityValue(TaskListGroupHeaderAccessibility.value(isCollapsed:!isExpanded))"),
                "the disclosure's value no longer follows isExpanded")
    }

    // MARK: - T-7092: a board card and a list task row open their task without a pointer

    private static let openTask = CadenceTaskControlAccessibility.openTaskActionName

    /// The control for the two below: a named action on a plain element is on the tree. If this
    /// ever reads empty, an absence below is the harness going blind, not the view.
    @Test func theHarnessSeesANamedAccessibilityAction() {
        let nodes = allNodes(in: Text("Probe").accessibilityAction(named: "Probe action") {})
        #expect(nodes.contains { $0.actions.contains("Probe action") }, "the harness cannot read a named action: \(nodes)")
    }

    private func hostedTaskSurface<V: View>(_ view: V, container: ModelContainer) -> some View {
        view
            .retainingModelContainerForProcessLifetime(container)
            .environment(CadenceDeepLinkManager.shared)
            .environment(DeleteConfirmationManager.shared)
            .environment(HoveredTaskManager.shared)
            .environment(HoveredEditableManager.shared)
            .environment(FocusManager.shared)
            .environment(TaskCompletionAnimationManager.shared)
    }

    /// A card opened its detail only on click or right-click, neither of which an assistive client
    /// can send. Exactly one element on the card's tree offers "Open task" — the card's own.
    @Test func aBoardCardOffersOpenTaskAsAnAccessibilityAction() throws {
        let container = try CadenceTestStore.container()
        let task = AppTask(title: "Board card task")
        ModelContext(container).insert(task)
        let nodes = allNodes(
            in: hostedTaskSurface(KanbanCard(task: task, todayKey: DateFormatters.todayKey()).frame(width: 260), container: container),
            size: NSSize(width: 300, height: 200)
        )
        #expect(nodes.contains { $0.label.contains("Board card task") || $0.value.contains("Board card task") },
                "non-vacuity: the card is not on the tree: \(nodes)")
        let offering = nodes.filter { $0.actions.contains(Self.openTask) }
        #expect(offering.count == 1, "the card does not offer Open task exactly once: \(nodes)")
    }

    @Test func aListTaskRowOffersOpenTaskAsAnAccessibilityAction() throws {
        let container = try CadenceTestStore.container()
        let task = AppTask(title: "List row task")
        ModelContext(container).insert(task)
        let nodes = allNodes(
            in: hostedTaskSurface(MacTaskRow(task: task, todayKey: DateFormatters.todayKey()).frame(width: 520), container: container),
            size: NSSize(width: 560, height: 120)
        )
        #expect(nodes.contains { $0.label.contains("List row task") || $0.value.contains("List row task") },
                "non-vacuity: the row is not on the tree: \(nodes)")
        let offering = nodes.filter { $0.actions.contains(Self.openTask) }
        #expect(offering.count == 1, "the row does not offer Open task exactly once: \(nodes)")
    }

    /// The action is the click's path, not a second one: each surface routes tap, right-click or
    /// menu, and the action through one function that raises the detail popover.
    @Test func theOpenTaskActionRunsTheSameOpenDetailPathAsTheClick() throws {
        let card = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanCardView.swift")
        ).filter { !$0.isWhitespace }
        #expect(card.contains(".accessibilityAction(named:CadenceTaskControlAccessibility.openTaskActionName,openTaskInspector)"))
        // [[T-8062]]: the card's right-click is the task menu now; its Edit is this same path.
        #expect(card.contains("openDetail:openTaskInspector,"))
        #expect(card.contains("privatefuncopenTaskInspector(){showTaskInspector=true}"))

        let row = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        ).filter { !$0.isWhitespace }
        #expect(row.contains(".accessibilityAction(named:CadenceTaskControlAccessibility.openTaskActionName,openDetail)"))
        #expect(row.contains(".onTapGesture(perform:openDetail)"))
        #expect(row.contains("openDetail:openDetail,"))
        #expect(row.contains("privatefuncopenDetail(){showTaskInspector=true}"))
    }
    // MARK: - T-7258: a saved link opens, copies and deletes without hovering

    private func hostedLinks(titled title: String, url: String) throws -> some View {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let area = Area(name: "Links area")
        let link = SavedLink(title: title, url: url)
        link.area = area
        context.insert(area)
        context.insert(link)
        try context.save()
        return LinksView(area: area)
            .frame(width: 520, height: 300)
            .retainingModelContainerForProcessLifetime(container)
            .environment(DeleteConfirmationManager.shared)
    }

    /// The hover buttons are not built until the pointer is over the row, so with no pointer the
    /// row's own actions are the only Open and Delete on the tree, and each is offered once.
    @Test func aSavedLinkRowOffersOpenAndDeleteWithoutHovering() throws {
        let nodes = allNodes(in: try hostedLinks(titled: "Roadmap doc", url: "https://example.com/roadmap"),
                             size: NSSize(width: 560, height: 340))
        #expect(nodes.contains { $0.label.contains("Roadmap doc") || $0.value.contains("Roadmap doc") },
                "non-vacuity: the link row is not on the tree: \(nodes)")
        #expect(nodes.filter { $0.actions.contains(MacSavedLinkRowActions.openActionName) }.count == 1,
                "the row does not offer Open link exactly once: \(nodes)")
        #expect(nodes.filter { $0.actions.contains(MacSavedLinkRowActions.deleteActionName) }.count == 1,
                "the row does not offer Delete link exactly once: \(nodes)")
    }

    /// The Delete action asks first, through the same manager and the same words the hover
    /// button uses; it does not delete on its own.
    @Test func theDeleteLinkActionAsksThroughTheDeleteConfirmationManager() throws {
        let manager = DeleteConfirmationManager.shared
        manager.request = nil
        defer { manager.request = nil }
        let title = "Delete-action probe \(UUID().uuidString)"
        _ = allNodes(in: try hostedLinks(titled: title, url: "https://example.com/probe"),
                     size: NSSize(width: 560, height: 340),
                     perform: MacSavedLinkRowActions.deleteActionName)
        let request = try #require(manager.request, "the Delete link action presented no confirmation")
        #expect(request.title == CadenceSavedLinkPersistence.deleteConfirmationTitle)
        #expect(request.message == CadenceSavedLinkPersistence.deleteConfirmationMessage(title: title))
    }

    /// Copy Link puts the stored URL, as plain text, on the pasteboard it is given.
    @Test func copyLinkPutsTheStoredURLOnThePasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cadence.tests.links.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("stale", forType: .string)
        MacSavedLinkRowActions.copy("https://example.com/a?b=c", to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "https://example.com/a?b=c")
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    /// The menu is not on the accessibility tree until it opens, so its items are read off the
    /// source: Open and Copy run the row's own functions, and Delete is the hover button's
    /// `onDelete`, which `LinksView` wires to `deleteConfirmationManager.present`.
    @Test func theLinkRowMenuOpensCopiesAndDeletesThroughTheHoverButtonsPaths() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        )
        let row = try CadenceControlAccessibilityLabelTests.bodyOfStruct("LinkRow", in: source)
            .filter { !$0.isWhitespace }
        let menu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: row), "the link row has no context menu")
        #expect(menu.contains("Button(MacSavedLinkRowActions.openMenuTitle,action:openLink)"))
        #expect(menu.contains("Button(MacSavedLinkRowActions.copyMenuTitle,action:copyLink)"))
        #expect(menu.contains("Button(role:.destructive){onDelete()}"))
        #expect(menu.contains("Label(MacSavedLinkRowActions.deleteMenuTitle,systemImage:"))
        #expect(row.contains(".onTapGesture(perform:openLink)"), "the row's click no longer opens the link")
        #expect(row.contains("Button(action:openLink)"), "the hover Open button no longer runs openLink")
        #expect(row.contains("Button(role:.destructive){onDelete()}label:"), "the hover Delete button is gone")
        #expect(row.contains("privatefunccopyLink(){MacSavedLinkRowActions.copy(link.url)}"))
        #expect(row.contains("privatefuncopenLink(){MacSavedLinkRowActions.open(link.url)}"))

        let view = source.filter { !$0.isWhitespace }
        #expect(view.contains("LinkRow(link:link){deleteConfirmationManager.present("),
                "the row's onDelete no longer asks through deleteConfirmationManager")
        #expect(MacSavedLinkRowActions.openMenuTitle == "Open Link")
        #expect(MacSavedLinkRowActions.copyMenuTitle == "Copy Link")
    }

    // MARK: - T-7067: a Mac month-grid cell names its day and opens it without a pointer

    /// iOS's month-cell words ([[T-573]]), over the sum iOS counts: tasks plus the events the cell
    /// would draw. The cell itself needs `CalendarManager`, the navigation manager and a store, so
    /// the words are pinned as values here and the wiring by the scan below.
    @Test func aMacMonthCellSaysTheIOSMonthCellsWords() throws {
        let date = try #require(DateFormatters.date(from: "2026-08-31"))
        let day = DateFormatters.longDate.string(from: date)
        #expect(MonthDayCell.accessibilityLabel(date: date, taskCount: 2, visibleEventCount: 1) == "\(day), 3 scheduled items")
        #expect(MonthDayCell.accessibilityLabel(date: date, taskCount: 0, visibleEventCount: 1) == "\(day), 1 scheduled item")
        #expect(MonthDayCell.accessibilityLabel(date: date, taskCount: 1, visibleEventCount: 0) == "\(day), 1 scheduled item")
        #expect(
            MonthDayCell.accessibilityLabel(date: date, taskCount: 0, visibleEventCount: 0)
                == "\(day), \(CadenceCalendarDayAccessibility.emptyPhrase)"
        )
        #expect(
            MonthDayCell.accessibilityLabel(date: date, taskCount: 4, visibleEventCount: 2)
                == CadenceCalendarDayAccessibility.countedDayLabel(date: date, itemCount: 6),
            "the Mac month cell drifted from iOS's wording"
        )
    }

    /// The cell's label reads the counts it draws chips from, and its accessibility actions are
    /// the click's own `openDay()`, not a second path.
    @Test func aMacMonthCellOpensItsDayThroughTheClicksOwnPath() throws {
        let month = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        )
        let cell = try #require(CadenceSourceScan.declarationBody("struct MonthDayCell", in: month))
            .filter { !$0.isWhitespace }
        #expect(cell.contains(".onTapGesture{openDay()}"), "non-vacuity: the cell's click no longer opens the day")
        #expect(cell.contains(".accessibilityElement(children:.contain)"), "the cell's chips are no longer their own elements")
        #expect(
            cell.contains(".accessibilityLabel(Self.accessibilityLabel(date:date,taskCount:tasks.count,visibleEventCount:events.count))"),
            "the cell does not name its day from the counts its chips are drawn from"
        )
        #expect(cell.contains(".accessibilityAction{openDay()}"), "the cell has no default accessibility action to open its day")
        #expect(cell.contains(".accessibilityAction(named:Self.openDayActionName,openDay)"), "the cell does not list Open day")
        #expect(cell.contains("privatefuncopenDay(){"))
        #expect(MonthDayCell.openDayActionName == "Open day")
    }

    // MARK: - T-7077: the list-detail Notes tab's folder-grouped rows

    /// Hosted as `NoteFolderGroupList` hands them out: each row is one button, the open note reads
    /// selected, and the double-click rename has a named action. Still a tap gesture underneath —
    /// see `ListNoteRow.accessibilityTraits` for why a `Button` would break rename.
    @Test func aFolderGroupedNoteRowIsAButtonThatSaysWhichNoteIsOpen() {
        let closed = Note(kind: .permanent, title: "Grocery list")
        let open = Note(kind: .permanent, title: "Trip plan")
        func row(_ note: Note, _ isSelected: Bool) -> ListNoteFolderRow {
            ListNoteFolderRow(
                note: note, isSelected: isSelected, folderNames: [],
                onSelect: { _ in }, onCopyLink: { _ in }, onMoveToFolder: { _ in },
                onNewFolder: {}, onDelete: { _ in }
            )
        }
        let nodes = allNodes(in: VStack(spacing: 0) {
            row(closed, false)
            row(open, true)
        }, size: NSSize(width: 320, height: 160))
        let rows = nodes.filter { $0.role == Self.buttonRole }
        #expect(rows.count == 2, "a folder-grouped note row is not one button on the tree: \(nodes)")
        let selected = rows.filter(\.isSelected)
        #expect(selected.count == 1, "the open note is not the one selected row: \(rows)")
        #expect(
            selected.first.map { $0.label.contains("Trip plan") || $0.value.contains("Trip plan") } == true,
            "the selected row is not the open note: \(rows)"
        )
        #expect(
            rows.filter { $0.actions.contains(ListNoteRow.renameActionName) }.count == 2,
            "a row does not offer its double-click rename as an action: \(rows)"
        )
    }

    /// The renaming state, which the harness cannot reach without a double-click: the row stops
    /// being a button so its text field is not folded into a button label.
    @Test func aRenamingNoteRowIsNotAButton() {
        typealias Row = ListNoteRow
        #expect(Row.accessibilityTraits(isEditing: false, isSelected: false) == .isButton)
        #expect(Row.accessibilityTraits(isEditing: false, isSelected: true) == [.isButton, .isSelected])
        #expect(Row.accessibilityTraits(isEditing: true, isSelected: true) == .isSelected)
        #expect(Row.accessibilityTraits(isEditing: true, isSelected: false) == [])
    }

    /// Pointer behaviour is the tap gestures it was; the accessibility action calls the same
    /// `onSelect` the single click does, and the children fold only while not renaming.
    @Test func aFolderGroupedNoteRowKeepsItsGesturesAndOpensThroughOnSelect() throws {
        let folder = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesViewSupportViews.swift")
        )
        let outer = try CadenceControlAccessibilityLabelTests.bodyOfStruct("ListNoteFolderRow", in: folder)
            .filter { !$0.isWhitespace }
        #expect(outer.contains("ListNoteRow(note:note,isSelected:isSelected,onOpen:{onSelect(note)})"))
        #expect(outer.contains(".onTapGesture{onSelect(note)}"), "the row's single click no longer opens the note")
        #expect(!outer.contains("NoteListRowButton("), "a Button wrapper takes the rename's clicks (T-7068)")

        let list = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesListSupportViews.swift")
        )
        let inner = try CadenceControlAccessibilityLabelTests.bodyOfStruct("ListNoteRow", in: list)
            .filter { !$0.isWhitespace }
        #expect(inner.contains(".onTapGesture(count:2){isEditingTitle=true}"), "the double-click rename is gone")
        #expect(inner.contains(".accessibilityElement(children:isEditingTitle?.contain:.combine)"))
        #expect(inner.contains(".accessibilityAction{onOpen()}"))
        #expect(inner.contains(".accessibilityAction(named:Self.renameActionName){isEditingTitle=true}"))
    }
}
#endif
