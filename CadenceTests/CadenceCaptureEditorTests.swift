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

    /// T-9202: the estimate's own chip spells its length the way the do-date chip beside it does.
    @Test func theEstimateChipSpellsItsLengthInTheSharedDurationSpelling() {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
        draft.setEstimate(90)
        #expect(CadenceCaptureFieldInventory.estimateChipTitle(for: draft) == "1h\u{00A0}30m")
        draft.setEstimate(45)
        #expect(CadenceCaptureFieldInventory.estimateChipTitle(for: draft) == "45m")
        for minutes in [15, 60, 125] {
            draft.setEstimate(minutes)
            #expect(
                CadenceCaptureFieldInventory.estimateChipTitle(for: draft)
                    == CadenceTaskPresentationSupport.estimateLabel(minutes: draft.estimateMinutes)
            )
        }
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

    // T-3260 retention review: a path reference is not itself a convertible behaviour pin.
    // - The source-size check below guards against a wrong/truncated input to the wiring scans;
    //   running a capture helper cannot validate which file those scans read.
    // - Presentation/background/dismissal/navigation checks hold private SwiftUI host composition;
    //   constructing a draft cannot observe the presented sheet or its dismissal interaction.
    // - Status/delete/notes checks hold private host callbacks and bindings; the public field
    //   inventory tests above cannot prove that the hosts connect them to the card.
    // - Forwarding, title styling, notes-slot, time/due-date and repeat checks hold private view
    //   composition; testing the called helpers alone would still pass if the call were removed.
    // - Commit/read-only/title-notice checks hold private view actions and their ordering; there
    //   is no callable action seam here, and inspecting a constructed View is not a UI flow.
    // - Font, line limits, tints, glyphs, priority and chip placement are rendering constraints;
    //   the date-label test below holds the reachable formatter but cannot prove the card uses it.
    // - Source-parser and regex controls stay because they validate the retained scans rather
    //   than a product behaviour. No replacement is claimed without a rendering/action seam.
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
            // T-5170: the guard also sees notes the well has not yet written to the draft. The task
            // sheet routes the same inputs through `CadenceTaskSheetUnsavedWork` ([[T-5359]]).
            #expect(
                host.contains(".interactiveDismissDisabled(draft != openedDraft || notesFlush.hasPendingEdit)")
                    || (host.contains(".interactiveDismissDisabled(hasUnsavedWork)")
                        && host.contains("notesHavePendingEdit: notesFlush.hasPendingEdit"))
                    // [[T-8572]]: the event sheet ignores committed notes, through the shared rule.
                    || (host.contains("CadenceEventEditDismissGuard.blocksSwipe(")
                        && host.contains("notesHavePendingEdit: notesFlush.hasPendingEdit"))
            )
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
        // T-9202: the riding duration and the estimate's own chip read one helper, so the same
        // estimate cannot be "1h 30m" on the do-date chip and "90 min" once the date is cleared.
        #expect(chipTitle.components(separatedBy: "CadenceCaptureFieldInventory.estimateChipTitle(for: draft)").count == 3)
        #expect(!chipTitle.contains(" min\""))
        #expect(chipTitle.contains("\\(doDayText) \u{00B7} \\(draft.doTimeLabel)"))
        let carries = try #require(CadenceSourceScan.functionBody(named: "restCarriesChip", in: card))
        #expect(carries.contains("case .doDate, .dueDate, .tags, .priority: return false"))
        #expect(carries.contains("case .estimate: return isSet(.estimate) && !isSet(.doDate)"))
    }

    /// **[[T-8463]] — at phone width the field editor is a sheet, not a forced popover.**
    ///
    /// Seen on `Cadence-iPhone15` (393x852): opening the schedule chip on the iOS task inspector
    /// drew the Do panel with its LEFT edge at x≈210 and the rest off the right of the screen —
    /// `er 2026` for the month heading, `sday, October 1` for a day row, `ut time` for the
    /// `Without time` toggle. The card carried `.presentationCompactAdaptation(.popover)`, which
    /// overrides the adaptation SwiftUI would otherwise make in a compact horizontal size class,
    /// and the inspector's host sheet sits at a detent tall enough that UIKit had no room above or
    /// below the full-width card to put a 320pt panel. The same card inside quick-add escaped it
    /// only because that host's `.height(cardHeight)` detent is short.
    ///
    /// **Two halves, because either alone is weak.**
    ///
    /// The first is the rule itself: one adaptation in the file, and it is `.sheet`. One, because
    /// the inspector and quick-add share this card — a second adaptation would be the two hosts
    /// diverging again, which is the shape the defect had. `.sheet` rather than no modifier at
    /// all, so the intent is legible at the call site and a later `.popover` is a diff, not a
    /// deletion. The modifier does nothing outside a compact size class, so the iPad and the Mac
    /// are untouched by it.
    ///
    /// The second is the arithmetic that says a popover could not have fitted, read off the app's
    /// own `gridWidth`: a full-width sheet on the owner's phone ([[T-3147]], 393pt) clears the
    /// grid, and the sliver the clipped popover left on screen does not — which is why the grid
    /// had already fallen back to its narrow row layout in the screenshot, and why that fallback
    /// is evidence of the placement rather than a second defect.
    ///
    /// **Failing-first:** putting `.popover` back fails the first half; narrowing the sheet to the
    /// sliver, or widening the grid past the phone, fails the second.
    @Test func theCapturePanelIsASheetWhereThereIsNoRoomForAPopover() throws {
        let card = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        #expect(CadenceSourceScan.matchCount(#"\.presentationCompactAdaptation\("#, in: card) == 1)
        #expect(card.contains(".presentationCompactAdaptation(.sheet)"))
        #expect(!card.contains(".presentationCompactAdaptation(.popover)"))

        // The owner's handset, and the card's own horizontal padding either side of the panel.
        let phoneWidth: CGFloat = 393
        let cardPadding: CGFloat = 12
        // Where the clipped panel's left edge landed, so `phoneWidth - clippedLeftEdge` is the
        // width the grid actually had to draw itself in.
        let clippedLeftEdge: CGFloat = 210
        let grid = CadenceDateSelectionMetrics.gridWidth(at: .large)
        #expect(grid <= phoneWidth - cardPadding * 2)
        #expect(grid > phoneWidth - clippedLeftEdge)
        #expect(!CadenceDateSelectionMetrics.usesDateRows(
            at: .large, availableWidth: phoneWidth - cardPadding * 2
        ))
        #expect(CadenceDateSelectionMetrics.usesDateRows(
            at: .large, availableWidth: phoneWidth - clippedLeftEdge
        ))
    }

    /// **[[T-10121]] — "Custom…" opens only what the frequency list above it cannot express.**
    ///
    /// The repeat editor drew `TaskRecurrenceRule.allCases` twice on one 393pt screen: once in the
    /// `.repeatRule` case's own list, and again inside `customRepeat` under a second "Frequency"
    /// eyebrow, with the same row ticked in each copy and nothing between them but the button that
    /// opened the second one. The owner chose option (a) — the custom panel "drops its own
    /// FREQUENCY eyebrow and list" — over hiding the top list or leaving it, so both the eyebrow
    /// and the list are asserted gone here, not just the list. What the panel keeps is Ends, and
    /// the frequency chosen above is carried in and **shown** rather than silently reset.
    ///
    /// **Two halves, because either alone is weak.** The source half is the only way to see
    /// *which* view draws a list: `customRepeat` is a private computed property on a `View` this
    /// target cannot construct, so there is no rendering seam to read. The behavioural half is the
    /// round trip the ruling is actually about — a frequency chosen in the first list has to
    /// survive every write the custom panel makes, and the panel's readout is the rule's own
    /// `label`, which is what the second list used to spell for it.
    ///
    /// The eyebrow and readout are read off the comment-stripped text rather than `codeOnly`,
    /// because both live in string literals that `codeOnly` blanks; the structural assertions are
    /// read off `codeOnly`, so a needle cannot be answered by a comment or a literal.
    ///
    /// **Failing-first:** restoring the second `CadenceChoicePopoverList` over
    /// `TaskRecurrenceRule.allCases`, or its "Frequency" eyebrow, fails the assertions above the
    /// round trip; making any Ends control put `repeatRule` back fails the round trip itself.
    @Test func theCustomRepeatPanelCarriesTheChosenFrequencyAndNeverOffersItASecondTime() throws {
        let cardSource = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        let card = CadenceSourceScan.codeOnly(cardSource)

        // Exactly one frequency list in the whole card, and `customRepeat` is not where it is.
        #expect(card.components(separatedBy: "TaskRecurrenceRule.allCases").count == 2)
        let custom = try #require(
            CadenceSourceScan.declarationBody("private var customRepeat: some View", in: card)
        )
        #expect(!custom.contains("TaskRecurrenceRule.allCases"))
        // ...and keeps the half it alone offers: the Ends mode, its date and its count.
        #expect(custom.contains("TaskRecurrenceEndMode.allCases"))
        #expect(custom.contains("draft.selectSeriesEnd("))
        #expect(custom.contains("draft.setSeriesEndCount("))
        #expect(custom.contains("recurrenceEndBinding"))

        // The copy, over the text that still carries string literals.
        let customText = try #require(
            CadenceSourceScan.declarationBody("private var customRepeat: some View", in: cardSource)
        )
        #expect(!customText.contains("SectionEyebrowLabel(text: \"Frequency\")"), "the duplicate eyebrow is back")
        #expect(customText.contains("SectionEyebrowLabel(text: \"Ends\")"))
        // It states the frequency it was opened on instead of offering it again.
        #expect(customText.contains("draft.repeatRule.label"))
        // Non-vacuity for the un-blanked read: the one eyebrow it keeps is a literal, so a text
        // with its literals blanked could not satisfy the line above it.
        #expect(!card.contains("SectionEyebrowLabel(text: \"Ends\")"))

        // The round trip, driven the way the two controls drive it: the first list writes
        // `repeatRule`, the panel reads it back, and the Ends controls write beside it.
        let calendar = Calendar.current
        let reference = try #require(DateFormatters.date(from: "2026-10-21", in: calendar))
        var draft = CadenceScheduleDraft(dateKey: "2026-10-21", startMin: 600, kind: .event)

        draft.repeatRule = .weekly
        #expect(draft.repeatRule.label == "Weekly", "the custom panel's readout is this label")

        draft.selectSeriesEnd(.onDate, reference: reference, calendar: calendar)
        #expect(draft.repeatRule == .weekly)
        #expect(draft.effectiveSeriesEndMode == .onDate)

        draft.setSeriesEndCount(6)
        #expect(draft.repeatRule == .weekly, "choosing an occurrence count reset the frequency")
        #expect(draft.effectiveSeriesEndMode == .afterCount)

        draft.selectSeriesEnd(.never, reference: reference, calendar: calendar)
        #expect(draft.repeatRule == .weekly, "choosing Ends: Never reset the frequency")
        #expect(draft.repeatRule.label == "Weekly")

        // And the one write that *does* clear the frequency is the first list's own Never row,
        // which is why the panel reads `.none` as "Never" and shows no Ends half at all.
        CadenceCaptureFieldInventory.clear(.repeatRule, draft: &draft)
        #expect(draft.repeatRule == .none)
        #expect(draft.repeatRule.label == "Never")
        #expect(draft.effectiveSeriesEndMode == .never)
    }

    /// **[[T-16251]] — a frequency picked under "Custom…" leaves the Ends rows on screen.**
    ///
    /// Since [[T-10121]] the Repeat panel's one frequency list is also the custom panel's, and the
    /// custom panel says "Choose a frequency above to set when the series ends." The list closed
    /// the whole panel on a pick, so that instruction took the panel away the moment it was
    /// followed. Behavioural half: the list's `isPresented:` refuses the pick's close while the
    /// custom panel is open, and performs it otherwise. Wiring half: the `.repeatRule` case hands
    /// the list that binding over `showsCustomRepeat`, not the bare `editorIsOpen`.
    ///
    /// **Failing-first:** handing the list `editorIsOpen` again, or `pickClosesPanel` answering
    /// `true` under the custom panel, fails the close assertions below.
    @Test func aFrequencyPickedUnderCustomRepeatKeepsTheEndsRowsOnScreen() throws {
        var panelOpen = true
        let panel = Binding(get: { panelOpen }, set: { panelOpen = $0 })

        // Custom… open: the pick's close is refused, so Ends stays drawn.
        let underCustom = CadenceCaptureRepeatFrequencyList.presentation(customPanelIsOpen: true, panelIsOpen: panel)
        #expect(underCustom.wrappedValue)
        underCustom.wrappedValue = false
        #expect(panelOpen, "a frequency picked under Custom… closed the panel and took the Ends rows with it")
        #expect(!CadenceCaptureRepeatFrequencyList.pickClosesPanel(customPanelIsOpen: true))

        // The list alone: a pick still closes the panel, as every draft picker does.
        let plain = CadenceCaptureRepeatFrequencyList.presentation(customPanelIsOpen: false, panelIsOpen: panel)
        plain.wrappedValue = false
        #expect(!panelOpen, "the plain frequency list stopped closing on a pick")
        #expect(CadenceCaptureRepeatFrequencyList.pickClosesPanel(customPanelIsOpen: false))

        // Wiring: the card's one frequency list reads the helper over the custom panel's state.
        let card = CadenceSourceScan.codeOnly(try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift"))
        // From the card's one `TaskRecurrenceRule.allCases` (the editor's list, pinned to one by the
        // T-10121 test above) to the next case: `case .repeatRule:` alone also names the chip label.
        let caseStart = try #require(card.range(of: "TaskRecurrenceRule.allCases"))
        let caseEnd = try #require(card.range(of: "case .priority:", range: caseStart.upperBound..<card.endIndex))
        let repeatCase = String(card[caseStart.upperBound..<caseEnd.lowerBound])
        #expect(repeatCase.contains("CadenceCaptureRepeatFrequencyList.presentation("))
        #expect(repeatCase.contains("customPanelIsOpen: showsCustomRepeat"))
        #expect(!repeatCase.contains("isPresented: editorIsOpen"), "the frequency list closes the panel under Custom… again")
    }

    /// **[[T-9662]]. A button's hit frame belongs INSIDE its label.** The card applies
    /// `.buttonStyle(.cadencePlain)`, and on iOS that style lays its `contentShape` on
    /// `configuration.label` -- so a `.frame` written as a modifier on the `Button` reserves the
    /// space and takes none of the taps. The close (X) and Delete buttons were laid out in 44pt
    /// and tappable only on the ~17pt glyph and on the word; the field icons, the overflow menu
    /// and Save already framed inside their labels and were the ones that worked.
    ///
    /// Source shape because the defect IS the position of a modifier in a private view: no
    /// constructible draft can report where a `contentShape` landed, and a hit test needs the
    /// simulator. The scan is validated against a synthetic good/bad pair below so that a change
    /// that stops it seeing anything fails rather than passes.
    @Test func everyCaptureCardButtonKeepsItsHitFrameInsideItsLabel() throws {
        let cardSource = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        let card = CadenceSourceScan.codeOnly(cardSource)
        let lines = card.components(separatedBy: "\n")
        let scan = Self.buttonsFramedOutsideTheirLabel(in: lines)
        #expect(scan.scanned >= 6, "non-vacuity: only \(scan.scanned) buttons scanned in the capture card")
        #expect(scan.offenders.isEmpty, "a hit frame outside the button's label: \(scan.offenders)")

        // The two that were wrong, spelled the way the fix spells them.
        #expect(cardSource.contains(
            "Button(action: actions.cancel) { Image(systemName: \"xmark\").frame(width: 44, height: 44) }"
        ))
        let delete = try #require(
            cardSource.range(of: "Button(role: .destructive) { actionError = delete() } label: {")
        )
        #expect(cardSource[delete.upperBound...].prefix(120).contains("Text(\"Delete\").frame(minHeight: 44)"))
    }

    /// The scan sees a frame written on the button and does not see one written in its label.
    @Test func theHitFrameScanSeparatesALabelFrameFromAButtonFrame() {
        let bad = [
            "        Button(action: cancel) { Image(systemName: \"xmark\") }",
            "            .accessibilityLabel(\"Cancel\")",
            "            .frame(width: 44, height: 44)",
        ]
        let badScan = Self.buttonsFramedOutsideTheirLabel(in: bad)
        #expect(badScan.scanned == 1)
        #expect(badScan.offenders.count == 1)

        let good = [
            "        Button(action: cancel) { Image(systemName: \"xmark\").frame(width: 44, height: 44) }",
            "            .accessibilityLabel(\"Cancel\")",
            "        Button(role: .destructive) { remove() } label: {",
            "            Text(\"Delete\").frame(minHeight: 44)",
            "        }",
            "        .foregroundStyle(Theme.red)",
        ]
        let goodScan = Self.buttonsFramedOutsideTheirLabel(in: good)
        #expect(goodScan.scanned == 2)
        #expect(goodScan.offenders.isEmpty, "\(goodScan.offenders)")
    }

    /// **[[T-12261]].** Adding subtasks in the iOS task inspector scrolled the card's whole header
    /// -- the Task/Event switcher, the `x` and the title -- above the sheet's top edge, and nothing
    /// brought it back. The inspector now asks the card to pin its header as a section header of
    /// its scroll view, and the pinned half holds exactly those controls while the record sections
    /// stay in the half that scrolls.
    ///
    /// A STRUCTURAL pin, not a behavioural proof: where a pinned header is drawn is layout, and no
    /// unit seam reaches a `ScrollView`'s offset. `Cadence/iOS/` does not build on this target's
    /// macOS leg either, so the wiring is read from source. The on-screen sighting is owed.
    @Test func theTaskInspectorPinsTheCardHeaderWhileTheRecordScrolls() throws {
        let task = CadenceSourceScan.codeOnly(try source("Cadence/iOS/iOSTaskDetailSheet.swift"))
        let scroll = try #require(CadenceSourceScan.declarationBody("private var editorScrollView: some View", in: task))
        #expect(CadenceSourceScan.matchCount(#"\.pinningCaptureHeader\(\)"#, in: scroll) == 1,
                "the task inspector no longer pins the capture card's header")
        #expect(scroll.contains("ScrollView {"), "the header is pinned to a scroll view that is gone")
        // Opt-in: the hosts whose card does not grow under it keep the plain stack.
        for host in ["iOSCalendarEventEditSheet", "iOSCreateTaskSheet", "iOSCalendarQuickCreateSheet"] {
            let code = CadenceSourceScan.codeOnly(try source("Cadence/iOS/\(host).swift"))
            #expect(!code.contains(".pinningCaptureHeader()"), "\(host) pins a header nobody measured")
        }

        let panel = CadenceSourceScan.codeOnly(try source("Cadence/Shared/Components/CadenceSchedulePanel.swift"))
        let route = try #require(CadenceSourceScan.declarationBody("var body: some View", in: panel))
        #expect(route.contains("pinsHeader: pinsCaptureHeader"), "the panel drops the pin on the way to the card")

        // Comments blanked, literals kept: the controls are found by their accessibility ids.
        let card = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        let layout = try #require(CadenceSourceScan.declarationBody("private var cardLayout: some View", in: card))
        #expect(layout.contains("if pinsHeader {"))
        #expect(layout.contains("LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders])"))
        #expect(layout.contains(".background(Theme.surfaceElevated)"), "rows would show through the pinned header")
        let header = try #require(CadenceSourceScan.declarationBody("private var cardHeader: some View", in: card))
        let body = try #require(CadenceSourceScan.declarationBody("private var cardBody: some View", in: card))
        for control in ["\"capture-kind\"", "\"capture-cancel\"", "\"capture-title\""] {
            #expect(header.contains(control), "\(control) is not in the pinned header")
            #expect(!body.contains(control), "\(control) scrolls with the body")
        }
        // The editing host's sections -- the subtask composer among them -- scroll.
        #expect(body.contains("if draft.subject.isEditing, let notesField { notesField }"))
        #expect(!header.contains("notesField"))
    }

    /// [[T-12272]]: the Do panel overflows its popover on the iPad. An edge with content past it
    /// fades; an edge with nothing past it, and every edge of a panel that fits, does not.
    @Test func theFieldPopoverFadesOnlyTheEdgesWithContentPastThem() {
        // Fits: 400pt of content in a 520pt popover.
        #expect(CadenceScrollEdgeOverflow(offset: 0, visibleHeight: 520, contentHeight: 400) == .init())
        // Exactly fits, and a settled offset a fraction off zero, still fade nothing.
        #expect(CadenceScrollEdgeOverflow(offset: 0.4, visibleHeight: 520, contentHeight: 520.5) == .init())
        // Overflows, at rest: only the bottom has content past it.
        #expect(CadenceScrollEdgeOverflow(offset: 0, visibleHeight: 520, contentHeight: 700) == .init(top: false, bottom: true))
        // Scrolled part way: both edges.
        #expect(CadenceScrollEdgeOverflow(offset: 90, visibleHeight: 520, contentHeight: 700) == .init(top: true, bottom: true))
        // Scrolled to the end: only the top.
        #expect(CadenceScrollEdgeOverflow(offset: 180, visibleHeight: 520, contentHeight: 700) == .init(top: true, bottom: false))
        // Insets move the resting offsets, not the answer.
        #expect(CadenceScrollEdgeOverflow(offset: -12, visibleHeight: 520, contentHeight: 700, topInset: 12, bottomInset: 12)
                == .init(top: false, bottom: true))
        #expect(CadenceScrollEdgeOverflow(offset: 192, visibleHeight: 520, contentHeight: 700, topInset: 12, bottomInset: 12)
                == .init(top: true, bottom: false))
    }

    /// [[T-12272]]: the card's one field popover -- Do among its panels -- sits in the scroll view
    /// that flashes its indicator and fades a cut edge, not in a bare `ScrollView`.
    @Test func theFieldPopoverScrollsWithAVisibleAffordance() throws {
        let card = CadenceSourceScan.codeOnly(try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift"))
        let popover = try #require(card.range(of: ".popover(item: $activeField) { field in"))
        let opening = card[popover.upperBound...].prefix(200)
        #expect(opening.contains("CadenceCapturePopoverScroll {"), "the field popover is back in a bare scroll view")
        let wrapper = try #require(CadenceSourceScan.declarationBody("struct CadenceCapturePopoverScroll<Content: View>: View", in: card))
        #expect(wrapper.contains(".scrollIndicatorsFlash(onAppear: true)"), "the indicator no longer shows as the panel opens")
        #expect(wrapper.contains(".scrollIndicators(.visible)"))
        #expect(CadenceSourceScan.matchCount(#"overflow\.(top|bottom) \? \.clear : \.black"#, in: wrapper) == 2,
                "an overflowing edge is cut instead of faded")
    }

    /// Every `Button` in `lines`, with the `.frame(` modifiers applied to the button itself rather
    /// than inside its label. A button's expression ends on the line where the braces its own
    /// closures opened close again; the lines after it that begin with `.` are its modifiers.
    static func buttonsFramedOutsideTheirLabel(in lines: [String]) -> (scanned: Int, offenders: [String]) {
        var scanned = 0
        var offenders: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Button(") || trimmed.hasPrefix("Button {") else {
                index += 1
                continue
            }
            scanned += 1
            var depth = 0
            var opened = false
            var end = index
            for cursor in index..<lines.count {
                depth += lines[cursor].filter { $0 == "{" }.count
                depth -= lines[cursor].filter { $0 == "}" }.count
                end = cursor
                if depth > 0 { opened = true }
                if depth <= 0 { break }
            }
            _ = opened
            var cursor = end + 1
            while cursor < lines.count {
                let modifier = lines[cursor].trimmingCharacters(in: .whitespaces)
                guard modifier.hasPrefix(".") else { break }
                if modifier.hasPrefix(".frame(") {
                    offenders.append("line \(cursor + 1): \(modifier)")
                }
                cursor += 1
            }
            index = end + 1
        }
        return (scanned, offenders)
    }
}
