import Foundation
import SwiftData
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **[[T-1481]]'s macOS half: the task panel opens in the note's text flow.**
///
/// Measured on a real offscreen `CadenceTextView`, with a fixed-height view standing in for the
/// shared panel so every figure is exact. The claims are the ticket's first two forced decisions:
/// the note reflows by the panel's height while the embedded task's card stays where it was, and
/// the panel goes away — giving the space back — on Close, on Escape, and when its embed leaves
/// the note.
@MainActor
struct MarkdownInlineTaskPanelTests {
    nonisolated private static let embedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    nonisolated private static let otherID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
    nonisolated private static let panelHeight: CGFloat = 300

    private static let markdown = """
    Prose above the embed.

    [[task:11111111-2222-3333-4444-555555555555|Write the release notes]]

    Prose below the embed.

    [[task:99999999-2222-3333-4444-555555555555|Another task]]
    """

    private static func embedInfo(id: UUID, title: String) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: id,
            title: title,
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "",
            containerName: "Cadence",
            containerColorHex: Theme.blueHex,
            dueDate: "2030-04-18",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 45,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: []
        )
    }

    private func makeTextView() -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let containerWidth: CGFloat = 560 - 36
        let container = NSTextContainer(
            containerSize: NSSize(width: containerWidth, height: .greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 1200),
            textContainer: container
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.markdownTaskEmbeds = [
            Self.embedID: Self.embedInfo(id: Self.embedID, title: "Write the release notes"),
            Self.otherID: Self.embedInfo(id: Self.otherID, title: "Another task")
        ]
        textView.string = Self.markdown
        MarkdownStylist.apply(to: textView)
        textView.layoutManager?.ensureLayout(for: container)
        return textView
    }

    private func open(_ textView: CadenceTextView, id: UUID = embedID, height: CGFloat = panelHeight) {
        textView.presentInlineTaskPanel(taskID: id) { _ in
            AnyView(Color.clear.frame(height: height))
        }
    }

    /// The top of the line fragment holding the first character of `needle`, in view coordinates.
    private func lineTop(of needle: String, in textView: CadenceTextView) throws -> CGFloat {
        let range = (textView.string as NSString).range(of: needle)
        try #require(range.location != NSNotFound)
        let layoutManager = try #require(textView.layoutManager)
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            + textView.textContainerOrigin.y
    }

    private func cardTop(in textView: CadenceTextView) throws -> CGFloat {
        try lineTop(of: "[[task:11111111", in: textView)
    }

    // MARK: - Decision 1: the note reflows, the task stays put

    @Test func openingThePanelPushesTheNoteDownByThePanelAndLeavesTheCardWhereItWas() throws {
        let textView = makeTextView()
        let cardBefore = try cardTop(in: textView)
        let belowBefore = try lineTop(of: "Prose below", in: textView)
        let aboveBefore = try lineTop(of: "Prose above", in: textView)

        open(textView)

        #expect(textView.openInlineTaskPanelID == Self.embedID)
        #expect(try cardTop(in: textView) == cardBefore)
        #expect(try lineTop(of: "Prose above", in: textView) == aboveBefore)
        let pushed = try lineTop(of: "Prose below", in: textView) - belowBefore
        #expect(pushed == MarkdownInlineTaskPanelLayout.reservedSpacing(panelHeight: Self.panelHeight))
    }

    @Test func thePanelSitsUnderItsCardAndClearOfTheNextLine() throws {
        let textView = makeTextView()
        open(textView)

        let geometry = try #require(textView.inlineTaskPanelGeometry())
        let host = try #require(textView.inlineTaskPanel?.host)
        #expect(host.superview === textView)
        #expect(!host.isHidden)
        #expect(geometry.panel.height == Self.panelHeight)
        #expect(geometry.panel.minY >= geometry.card.maxY)
        #expect(geometry.panel.minX == geometry.card.minX.rounded())
        #expect(geometry.panel.maxY <= (try lineTop(of: "Prose below", in: textView)))
    }

    @Test func aTallerPanelReservesMoreRoomAndTheNoteFollowsIt() throws {
        let textView = makeTextView()
        let belowBefore = try lineTop(of: "Prose below", in: textView)
        open(textView)

        textView.updateInlineTaskPanelHeight(450, for: Self.embedID)

        #expect(try lineTop(of: "Prose below", in: textView) - belowBefore
            == MarkdownInlineTaskPanelLayout.reservedSpacing(panelHeight: 450))
        #expect(textView.inlineTaskPanelGeometry()?.panel.height == 450)
        // A report for a task whose panel is not the open one changes nothing.
        textView.updateInlineTaskPanelHeight(900, for: Self.otherID)
        #expect(textView.inlineTaskPanelGeometry()?.panel.height == 450)
    }

    @Test func onlyTheOpenTasksEmbedReservesRoom() throws {
        let textView = makeTextView()
        open(textView)
        #expect(textView.inlineTaskPanelReservedSpacing(forTaskID: Self.otherID) == 0)
        #expect(textView.inlineTaskPanelReservedSpacing(forTaskID: Self.embedID) > Self.panelHeight)
    }

    // MARK: - Decision 2: dismissal

    @Test func closingGivesTheSpaceBackAndRemovesTheView() throws {
        let textView = makeTextView()
        let belowBefore = try lineTop(of: "Prose below", in: textView)
        open(textView)
        let host = try #require(textView.inlineTaskPanel?.host)

        textView.closeInlineTaskPanel()

        #expect(textView.openInlineTaskPanelID == nil)
        #expect(host.superview == nil)
        #expect(try lineTop(of: "Prose below", in: textView) == belowBefore)
    }

    @Test func escapeClosesAnOpenPanelAndPassesThroughWhenNoneIsOpen() throws {
        let textView = makeTextView()
        #expect(textView.cancelInlineTaskPanel() == false)

        open(textView)
        #expect(textView.cancelInlineTaskPanel() == true)
        #expect(textView.openInlineTaskPanelID == nil)
        #expect(textView.subviews.allSatisfy { !($0 is NSHostingView<MarkdownInlineTaskPanelFrame>) })
    }

    @Test func theCloseHandedToThePanelClosesIt() throws {
        let textView = makeTextView()
        var close: (() -> Void)?
        textView.presentInlineTaskPanel(taskID: Self.embedID) { handed in
            close = handed
            return AnyView(Color.clear.frame(height: Self.panelHeight))
        }
        try #require(close != nil)
        close?()
        #expect(textView.openInlineTaskPanelID == nil)
    }

    @Test func openingAnotherTasksPanelReplacesTheFirst() throws {
        let textView = makeTextView()
        open(textView)
        let first = try #require(textView.inlineTaskPanel?.host)

        open(textView, id: Self.otherID)

        #expect(textView.openInlineTaskPanelID == Self.otherID)
        #expect(first.superview == nil)
        #expect(textView.inlineTaskPanelReservedSpacing(forTaskID: Self.embedID) == 0)
        // Asking again for the open task keeps the same view, and with it the draft.
        let second = try #require(textView.inlineTaskPanel?.host)
        open(textView, id: Self.otherID)
        #expect(textView.inlineTaskPanel?.host === second)
    }

    @Test func deletingTheEmbedsLineClosesThePanel() throws {
        let textView = makeTextView()
        open(textView)
        let host = try #require(textView.inlineTaskPanel?.host)

        textView.string = "Prose above the embed.\n\nProse below the embed.\n"
        MarkdownStylist.apply(to: textView)

        #expect(textView.openInlineTaskPanelID == nil)
        #expect(host.superview == nil)
    }

    // MARK: - The pointer over the panel ([[T-3253]] (b))

    @Test func thePointerOverThePanelIsThePanelsAndNowhereElse() throws {
        let textView = makeTextView()
        open(textView)
        let geometry = try #require(textView.inlineTaskPanelGeometry())

        #expect(textView.inlineTaskPanelOwnsPointer(at: NSPoint(x: geometry.panel.midX, y: geometry.panel.midY)))
        #expect(!textView.inlineTaskPanelOwnsPointer(at: NSPoint(x: geometry.card.midX, y: geometry.card.midY)))
        let below = try lineTop(of: "Prose below", in: textView)
        #expect(!textView.inlineTaskPanelOwnsPointer(at: NSPoint(x: geometry.panel.midX, y: below + 4)))
        #expect(textView.inlineTaskPanel?.host is MarkdownInlineTaskPanelHostingView)

        textView.closeInlineTaskPanel()
        #expect(!textView.inlineTaskPanelOwnsPointer(at: NSPoint(x: geometry.panel.midX, y: geometry.panel.midY)))
    }

    /// The bug itself: leaving a hovered card for the panel used to set the I-beam (the embed
    /// hover's own "back to text" branch) and then hand the move to `NSTextView`, which sets it
    /// again. Over the panel the move drops the hover and sets nothing.
    @Test func movingFromACardOntoThePanelDropsTheHoverWithoutSettingTheIBeam() throws {
        let textView = makeTextView()
        let window = NSWindow(
            contentRect: textView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = textView
        defer { window.contentView = nil }
        open(textView)
        let geometry = try #require(textView.inlineTaskPanelGeometry())

        var unhovered: [UUID] = []
        textView.onHoverEmbeddedMarkdownTask = { id, isHovered in
            if !isHovered { unhovered.append(id) }
        }
        textView.hoveredMarkdownTaskEmbed = MarkdownTaskEmbedHover(id: Self.embedID, target: .card)
        NSCursor.pointingHand.set()

        let inWindow = textView.convert(NSPoint(x: geometry.panel.midX, y: geometry.panel.midY), to: nil)
        let move = try #require(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: inWindow,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
        try #require(textView.inlineTaskPanelOwnsPointer(at: textView.convert(move.locationInWindow, from: nil)))

        textView.mouseMoved(with: move)

        #expect(textView.hoveredMarkdownTaskEmbed == nil)
        #expect(unhovered == [Self.embedID])
        #expect(NSCursor.current !== NSCursor.iBeam)
    }

    // MARK: - Routing

    @Test func everyFieldChipButStatusOpensThePanel() {
        let panel: [MarkdownTaskEmbedField] = [.priority, .container, .section, .scheduledDate, .dueDate, .estimate, .recurrence]
        for field in panel {
            #expect(MarkdownInlineTaskPanelRouting.opensPanel(for: field), "\(field) should open the panel")
        }
        #expect(!MarkdownInlineTaskPanelRouting.opensPanel(for: .status))
        #expect(!MarkdownInlineTaskPanelRouting.opensPanel(for: .title))
    }

    /// The macOS note hosts each route a field chip to the inline panel, and keep the popover only
    /// as the status chip's editor and the no-text-view fallback. [[T-5120]]: the three task-notes
    /// editors share `TaskNotesEmbedHandlers`, whose context arrives in its `scope`.
    @Test func everyMacNoteHostOpensThePanelInline() throws {
        for path in [
            "Cadence/macOS/Views/NoteEditorPane.swift",
            "Cadence/macOS/Views/NotePanel.swift",
            "Cadence/macOS/Views/TaskNotesEmbedHandlers.swift"
        ] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let body = try #require(CadenceSourceScan.functionBody(named: "editEmbeddedTask", in: source), "\(path)")
            #expect(body.contains("MarkdownInlineTaskPanelRouting.opensPanel(for: field)"), "\(path)")
            #expect(body.contains(".presentInlineTaskPanel(for:"), "\(path)")
            // The clicked chip travels with the request, so its row can open expanded (T-3253 (a)).
            #expect(
                CadenceSourceScan.matchCount(#"field: field, in: (scope\.)?modelContext"#, in: body) == 1,
                "\(path)"
            )
        }
    }

    // MARK: - The clicked chip's row opens expanded ([[T-3253]] (a))

    @Test func theClickedChipNamesTheRowThatOpensExpanded() {
        #expect(MarkdownInlineTaskPanelRouting.expandedRow(for: .scheduledDate) == .doDate)
        #expect(MarkdownInlineTaskPanelRouting.expandedRow(for: .dueDate) == .dueDate)
        let closed: [MarkdownTaskEmbedField] = [.status, .title, .priority, .container, .section, .estimate, .recurrence]
        for field in closed {
            #expect(MarkdownInlineTaskPanelRouting.expandedRow(for: field) == nil, "\(field) should open no row")
        }
    }

    /// Through the real path a chip click takes: the text view opens the real shared panel over a
    /// real task, and the height it reserves is what the panel measured on opening. A Due click
    /// opens the date grid, so it is TALLER than a Priority click, which opens nothing; a Do click
    /// opens the grid plus the time and repeat rows, so it is taller still. Relations, not figures.
    @Test func aDueOrDoClickOpensThePanelWithThatRowAlreadyExpanded() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Write the release notes")
        // The embed the note holds; a panel for a task the note does not embed closes at once.
        task.id = Self.embedID
        context.insert(task)
        try context.save()

        func openedHeight(_ field: MarkdownTaskEmbedField) throws -> CGFloat {
            let textView = makeTextView()
            textView.presentInlineTaskPanel(for: task, field: field, in: context, onSaved: { _ in })
            return try #require(textView.inlineTaskPanel?.height)
        }

        let closed = try openedHeight(.priority)
        let due = try openedHeight(.dueDate)
        let doDate = try openedHeight(.scheduledDate)
        #expect(closed > 0)
        #expect(due > closed, "a Due click should open the Due grid (\(due) vs \(closed))")
        #expect(doDate > due, "a Do click should open the Do grid and its rows (\(doDate) vs \(due))")
        #expect(try openedHeight(.estimate) == closed)
    }
}
#endif

/// The shared panel's one decision of its own: when Save stops to ask how far a series edit
/// reaches. Platform-neutral, like the panel.
@MainActor
struct CadenceTaskInlinePanelSeriesScopeTests {
    @Test func onlyASeriesMemberWhoseRuleMovedIsAsked() {
        let single = AppTask(title: "Water plants")
        let opened = CadenceScheduleDraft(editing: single)
        var moved = opened
        moved.repeatRule = .weekly

        #expect(!CadenceTaskInlinePanel.asksSeriesScope(draft: opened, opened: opened, task: single))
        // No series to reach, so a new rule lands without the question.
        #expect(!CadenceTaskInlinePanel.asksSeriesScope(draft: moved, opened: opened, task: single))

        let member = AppTask(title: "Water plants")
        member.recurrenceRule = .daily
        let memberOpened = CadenceScheduleDraft(editing: member)
        var memberMoved = memberOpened
        memberMoved.repeatRule = .weekly
        #expect(member.isRecurrenceSeriesMember)
        #expect(CadenceTaskInlinePanel.asksSeriesScope(draft: memberMoved, opened: memberOpened, task: member))
        #expect(!CadenceTaskInlinePanel.asksSeriesScope(draft: memberOpened, opened: memberOpened, task: member))
    }

    /// The panel's half of [[T-3253]] (a): which of its rows a named opening row expands. `nil` —
    /// the iOS card tap, which has no chip — opens every row closed, as it always has.
    @Test func anOpeningRowExpandsThatRowAndNoOther() {
        #expect(CadenceSchedulePanelRow.initialExpansion(nil) == .init(isDoExpanded: false, isDueExpanded: false))
        #expect(CadenceSchedulePanelRow.initialExpansion(.doDate) == .init(isDoExpanded: true, isDueExpanded: false))
        #expect(CadenceSchedulePanelRow.initialExpansion(.dueDate) == .init(isDoExpanded: false, isDueExpanded: true))
    }
}
