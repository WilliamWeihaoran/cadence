import SwiftUI
import Testing
@testable import Cadence

@Suite("Capture card preserves record editing")
@MainActor
struct CadenceCaptureEditorTests {
    @Test func anExistingCaptureRecordCannotChangeKind() {
        for subject in [CadenceScheduleDraft.Subject.editingTask(UUID()), .editingEvent("fixture")] {
            var draft = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
            draft.subject = subject
            let opened = draft
            var memory = CadenceCaptureKindMemory()
            memory.select(.event, draft: &draft)
            #expect(draft == opened)
        }
        var creating = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
        var memory = CadenceCaptureKindMemory()
        memory.select(.event, draft: &creating)
        #expect(creating.kind == .event)
    }

    @Test func captureEditorsOfferOnlyFieldsTheirHostsCanWrite() {
        let task = CadenceCaptureFieldInventory.fields(for: .task, offersTaskRepeat: false)
        #expect(!task.contains(.repeatRule))
        #expect(task.contains(.dueDate))
        #expect(task.contains(.estimate))
        let event = CadenceCaptureFieldInventory.fields(for: .event, offersEventRepeat: false)
        #expect(!event.contains(.repeatRule))
        #expect(event.contains(.location))
        #expect(event.contains(.calendar))
        #expect(CadenceCaptureFieldInventory.fields(for: .event).contains(.repeatRule))
    }

    @Test func clearingAnEditedEstimateMeansNoneWithoutRewritingTheTitle() {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
        draft.subject = .editingTask(UUID())
        draft.title = "!! Keep this literal title"
        #expect(TaskTitleSupport.priorityShortcut(in: draft.title) != nil)
        draft.setEstimate(20)
        draft.estimateIsExplicit = true
        #expect(CadenceCaptureFieldInventory.isSet(.estimate, draft: draft, tagIDs: []))
        CadenceCaptureFieldInventory.clear(.estimate, draft: &draft)
        #expect(draft.estimateMinutes == 0)
        #expect(!draft.estimateIsExplicit)
        CadenceCaptureFieldInventory.clear(.priority, draft: &draft)
        #expect(draft.title == "!! Keep this literal title")
        #expect(CadenceCaptureFieldInventory.priority(for: draft) == .none)
        #expect(!CadenceCaptureFieldInventory.isSet(.priority, draft: draft, tagIDs: []))
        draft.subject = .creating
        CadenceCaptureFieldInventory.clear(.estimate, draft: &draft)
        #expect(draft.estimateMinutes == CadenceTaskComposerSupport.defaultEstimatedMinutes)
    }

    private func source(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 1_000)
        return CadenceSourceScan.strippingComments(raw)
    }

    @Test func bothRecordEditorsPresentTheCaptureCard() throws {
        for name in ["iOSTaskDetailSheet", "iOSCalendarEventEditSheet"] {
            let host = CadenceSourceScan.codeOnly(try source("Cadence/iOS/\(name).swift"))
            #expect(host.contains(".capturePresentation(CadenceScheduleCaptureOptions())"))
            #expect(host.contains(".presentationBackground(.clear)"))
            #expect(host.contains(".interactiveDismissDisabled(draft != openedDraft)"))
            #expect(!host.contains("NavigationStack {"))
        }
        let task = CadenceSourceScan.codeOnly(try source("Cadence/iOS/iOSTaskDetailSheet.swift"))
        let sections = try #require(CadenceSourceScan.declarationBody("private var recordSections: some View", in: task))
        #expect(sections.contains("statusActionsSection"))
        let status = try #require(CadenceSourceScan.declarationBody("private var statusActionsSection: some View", in: task))
        #expect(status.contains("onToggleCompletion: toggleCompletion"))
        #expect(task.contains("showDeleteConfirmation = true"))
        #expect(task.contains("notesText: $draft.notes"))
    }

    @Test func captureForwardsAndEnforcesReadOnlyAndStatus() throws {
        let panel = CadenceSourceScan.codeOnly(try source("Cadence/Shared/Components/CadenceSchedulePanel.swift"))
        let cardSource = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        let card = CadenceSourceScan.codeOnly(cardSource)
        let route = try #require(CadenceSourceScan.declarationBody("var body: some View", in: panel))
        for parameter in ["readOnlyNotice", "titleStatus", "offersTaskRepeat", "offersEventRepeat"] {
            #expect(route.contains("\(parameter): \(parameter)"))
        }
        #expect(card.contains("isEditing: draft.subject.isEditing"))
        #expect(card.contains("if !isReadOnly, let delete = actions.delete"))
        #expect(cardSource.contains("Text(\"Save\")"))
        #expect(card.contains(".strikethrough(titleStatus?.isSettled == true)"))
        #expect(card.contains("if notesField == nil || !draft.subject.isEditing"))
        #expect(card.contains("if draft.subject.isEditing, let notesField { notesField }"))
        let fieldEditor = try #require(CadenceSourceScan.functionBody(named: "editor", in: card))
        #expect(fieldEditor.contains("if draft.kind == .task, !isAllDay"))
        #expect(fieldEditor.contains("draft.addTime()"))
        #expect(fieldEditor.contains("DateFormatters.date(from: draft.dueDateKey)"))
        #expect(card.contains("if fields.contains(.repeatRule)"))
        #expect(card.contains(".cadenceFont(.editorTitle)"))
        let commit = try #require(CadenceSourceScan.functionBody(named: "commit", in: card))
        #expect(commit.contains("guard !isReadOnly else"))
        let titleGate = try #require(commit.range(of: "guard draft.hasCommittableTitle else"))
        let hostGate = try #require(commit.range(of: "guard canCommit else"))
        #expect(titleGate.lowerBound < hostGate.lowerBound)
        #expect(commit.contains("guard draft.hasCommittableTitle else"))
        let commitCopy = try #require(CadenceSourceScan.functionBody(named: "commit", in: cardSource))
        #expect(commitCopy.contains("actionError = \"Add a title first.\""))
        let readOnlyPattern = #"\.disabled\(isReadOnly\)"#
        #expect(CadenceSourceScan.matchCount(readOnlyPattern, in: ".disabled(isReadOnly)") == 1)
        #expect(CadenceSourceScan.matchCount(readOnlyPattern, in: ".disabled(false)") == 0)
        #expect(CadenceSourceScan.matchCount(readOnlyPattern, in: card) >= 5)
    }

    /// **The seven-day cutoff, which [[T-3237]] item (3) left to the implementer and asked to have
    /// stated** — so it is stated here, in the one place a change to it turns red.
    ///
    /// `DateFormatters.relativeDate(from:)`'s own backward arm is UNBOUNDED, which is right for a
    /// lateness summary and wrong on a chip: a chip states a day, and `30 days ago` makes the
    /// reader do the arithmetic that `Sep 21` would have saved them. The card therefore calls the
    /// symmetric overload, and the last two expectations are the non-vacuity — at eight days the
    /// two spellings genuinely disagree, so this cannot pass by accidentally reading the old one.
    ///
    /// The reference instant is stated rather than taken from the clock: `relativeTo:` exists, and
    /// a test that said `Date()` would both straddle midnight and join the bare-`Date()` ledger in
    /// `CadenceTimeZoneIndependenceTests` for no gain.
    @Test func theCaptureCardsDateChipsReadAsWordsOnlyWithinSevenDaysEachWay() throws {
        let cutoff = CadenceCaptureFieldInventory.relativeDateCutoffDays
        #expect(cutoff == 7)
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
        var keys: [Int: String] = [:]
        var days: [Int: Date] = [:]
        for offset in [0, 1, -1, cutoff, -cutoff, cutoff + 1, -(cutoff + 1)] {
            let day = try #require(calendar.date(byAdding: .day, value: offset, to: reference))
            days[offset] = day
            keys[offset] = DateFormatters.dateKey(from: day)
        }
        func chipLabel(_ offset: Int) throws -> String {
            DateFormatters.relativeDate(from: try #require(keys[offset]), relativeTo: reference, withinDays: cutoff)
        }

        #expect(try chipLabel(0) == "Today")
        #expect(try chipLabel(1) == "Tomorrow")
        #expect(try chipLabel(-1) == "Yesterday")
        #expect(try chipLabel(cutoff) == "in \(cutoff) days")
        #expect(try chipLabel(-cutoff) == "\(cutoff) days ago")
        for offset in [cutoff + 1, -(cutoff + 1)] {
            let absolute = DateFormatters.shortDate.string(from: try #require(days[offset]))
            #expect(try chipLabel(offset) == absolute)
        }

        let behind = try #require(keys[-(cutoff + 1)])
        let ahead = try #require(keys[cutoff + 1])
        #expect(DateFormatters.relativeDate(from: behind, relativeTo: reference) == "\(cutoff + 1) days ago")
        #expect(DateFormatters.relativeDate(from: ahead, relativeTo: reference) == "in \(cutoff + 1) days")
    }

    /// **The owner's four capture-card complaints, pinned** ([[T-3237]]).
    ///
    /// Three of the four landed as single modifiers or a layout split and `CadenceTests` asserted
    /// none of them: the landing commit touched `CadenceScheduleCaptureCard.swift` and
    /// `DateFormatters.swift` and no test file at all, so any of them could have been undone by a
    /// later edit without a run noticing. The chip-row split itself is pinned in
    /// `CadenceCodexCaptureSectionBatchTests`; the rest of the shape is pinned here.
    ///
    /// Source shape rather than behaviour because each of these IS a modifier on a private view —
    /// `chipTint`, `chipSymbol` and `priorityChip` are not reachable from this target. The cutoff,
    /// which is reachable, is exercised for real in the test above instead. Two assertions read
    /// `cardSource` rather than `card` because `codeOnly` blanks string literals, which is where
    /// the notes placeholder and the `·` between a date and its duration live.
    @Test func theCaptureCardKeepsTheFourThingsTheOwnerAskedFor() throws {
        let cardSource = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        let card = CadenceSourceScan.codeOnly(cardSource)

        // (1) A long title takes a second and a third line before it truncates.
        let title = try #require(card.range(of: "TextField(draft.kind.titlePlaceholder, text: $draft.title, axis: .vertical)"))
        #expect(card[title.upperBound...].contains(".lineLimit(1...3)"))

        // (2) An empty notes field is ONE line whether it is focused or not, so focus cannot grow
        // the card. A limit that consults the focus state at all is the bug that was reported.
        let notes = try #require(cardSource.range(of: "TextField(\"Notes\", text: $draft.notes, axis: .vertical)"))
        #expect(cardSource[notes.upperBound...].contains(".lineLimit(1...6)"))
        #expect(!card.contains("notesIsFocused ?"))
        #expect(!card.contains("notesIsFocused ||"))

        // (3) Colour, on the glyph: the do date red and amber on today, the due date's flag red,
        // the list its own, priority the shared tint, and nothing borrowed for the rest.
        let tint = try #require(CadenceSourceScan.functionBody(named: "chipTint", in: card))
        #expect(tint.contains("return doDateIsToday ? Theme.amber : Theme.red"))
        #expect(tint.contains("case .dueDate: return Theme.red"))
        #expect(tint.contains("Theme.priorityColor(CadenceCaptureFieldInventory.priority(for: draft))"))
        #expect(tint.contains("case .tags, .repeatRule, .estimate, .calendar, .location: return Theme.dim"))
        let symbol = try #require(CadenceSourceScan.functionBody(named: "chipSymbol", in: card))
        #expect(symbol.contains("CadenceBoardCardMetadata.doDateIcon"))
        #expect(symbol.contains("doDateIsToday"))
        #expect(card.contains("Image(systemName: chipSymbol(field)).foregroundStyle(chipTint(field))"))

        // (4) Placement: priority is the shared bare mark and never the word, and the duration
        // rides the do-date chip rather than taking a row of its own.
        let priority = try #require(CadenceSourceScan.declarationBody("private var priorityChip: some View", in: card))
        #expect(priority.contains("TaskPriorityMarkControl(priority: CadenceCaptureFieldInventory.priority(for: draft))"))
        #expect(!priority.contains("Text("))
        let chipTitle = try #require(CadenceSourceScan.functionBody(named: "chipTitle", in: cardSource))
        #expect(chipTitle.contains("CadenceTaskPresentationSupport.estimateLabel(minutes: draft.estimateMinutes)"))
        #expect(chipTitle.contains("\\(doDayText) \u{00B7} \\(draft.doTimeLabel)"))
        let carries = try #require(CadenceSourceScan.functionBody(named: "restCarriesChip", in: card))
        #expect(carries.contains("case .doDate, .dueDate, .tags, .priority: return false"))
        #expect(carries.contains("case .estimate: return isSet(.estimate) && !isSet(.doDate)"))
    }
}
