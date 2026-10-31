import Foundation
import Testing

/// **[[T-656]] and [[T-727]]: one picker, one dismissal rule.**
///
/// `CadenceChoicePopoverList` — which `iOSChoicePopoverList` is a typealias for — and
/// `iOSContainerChoicePopover` are the app's two tap-to-select popovers, and both used to write
/// the selection and close in the same statement:
///
/// ```swift
/// Button { selection = row.value; isPresented = false }
/// ```
///
/// For the thirty-odd pickers whose selection is a **draft** field on a sheet that is exactly
/// right. The write cannot be refused, so closing claims nothing, and a picker that waited for an
/// answer nobody could give would be worse than the defect. T-727 is that half of the finding and
/// it is why this pair is one ticket rather than a sweep: a fix that made all the callers behave
/// like the committing ones would have been a regression in three places to fix it in one.
///
/// For the four whose selection setter **commits**, the close *is* the success report — the
/// popover is the only thing on screen that changes — and it was unconditional over a
/// `try? modelContext.save()`.
///
/// **Neither half of the `try? save()` rule could see it, and the reason is structural.** The
/// report (`isPresented = false`) is in `Shared/Components/`; the swallow is in the caller's file;
/// and the link between them is a `Binding`'s *setter*, which is not a call, so no call-graph
/// reading reaches from one to the other. Same family as [[T-657]], different mechanism.
///
/// **The shape chosen.** Each component keeps its ordinary initialiser and gains a committing one
/// that takes the current value — not a `Binding` — plus `select:`. The row hands the value to
/// `select` and closes only if it answers `true`; a refusal keeps the popover open and draws
/// `failureNotice` under the rows. Taking a value rather than a writable binding is the load-
/// bearing part: a binding beside a `select` closure would be two write paths, and a mutation
/// hidden in a binding's setter is precisely the thing that was invisible.
@MainActor
struct CadenceChoicePickerDismissalTests {

    private static let listPath = "Cadence/Shared/Components/CadenceChoicePicker.swift"
    private static let containerPath = "Cadence/iOS/iOSChoicePicker.swift"
    private static let rowActionsPath = "Cadence/iOS/iOSTaskRowActionViews.swift"
    private static let detailSheetPath = "Cadence/iOS/iOSTaskDetailSheet.swift"
    private static let detailSheetSectionsPath = "Cadence/iOS/iOSTaskDetailSheetSections.swift"

    // MARK: - The two components say the same thing

    /// One `pick(_:)` per component, and it is the **only** place either closes itself: a second
    /// `isPresented = false` anywhere else is a second dismissal rule by definition.
    @Test func eachChoicePopoverHasExactlyOnePlaceThatClosesItAndOneRuleForWhen() throws {
        for path in [Self.listPath, Self.containerPath] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            let pick = try CadenceCommitSurfaceScan.declarationBody(named: "pick", in: source)

            #expect(
                pick.contains("guard let select else {"),
                "\(path): the draft form is not the fallthrough"
            )
            #expect(
                CadenceSourceScan.matchCount(#"if select\("#, in: pick) == 1,
                "\(path): the committing form does not ask before closing"
            )
            #expect(
                CadenceSourceScan.matchCount(#"isPresented = false"#, in: source) == 2,
                "\(path) closes itself somewhere other than pick(_:)"
            )
            #expect(
                CadenceSourceScan.matchCount(#"isPresented = false"#, in: pick) == 2,
                "\(path): pick(_:) is not where both dismissals are"
            )
            #expect(
                source.contains("CadenceInlineFailureNotice(text: failureNotice)"),
                "\(path) has no place to say the write was refused"
            )
            #expect(
                source.contains("private let select: ((") ,
                "\(path) does not store the answering closure"
            )
        }
    }

    /// The committing initialiser takes the current **value**. A writable `Binding` beside
    /// `select:` would be two write paths, and the setter of one of them is where T-656 hid.
    @Test func thecommittingFormOfEachPopoverTakesAvalueRatherThanAwritableBinding() throws {
        let list = try CadenceCommitSurfaceScan.scanned(Self.listPath)
        #expect(list.contains("selection: Binding<T>,"), "the draft initialiser lost its binding")
        #expect(list.contains("selection: T,"), "the committing initialiser takes a binding")
        #expect(list.contains("select: @escaping (T) -> Bool"))
        #expect(list.contains("self._selection = .constant(selection)"))

        let container = try CadenceCommitSurfaceScan.scanned(Self.containerPath)
        #expect(container.contains("selection: Binding<String>,"), "the draft initialiser lost its binding")
        #expect(container.contains("selection: String,"), "the committing initialiser takes a binding")
        #expect(container.contains("select: @escaping (String) -> Bool"))
        #expect(container.contains("self._selection = .constant(selection)"))
    }

    // MARK: - The census

    /// **Every call site of both popovers, by file, exactly — not a floor.**
    ///
    /// The population this walks is one the repo keeps changing, and a floor over it is an
    /// assertion about the wrong thing: it cannot tell a picker that was deleted from one that
    /// quietly stopped answering. So the table names each file and both of its numbers, and a new
    /// picker anywhere lands here in the same change — which is the point, because the question
    /// "does this one's selection setter commit?" has to be asked at that moment and not later.
    ///
    /// Two of twenty-seven commit, both task-row chips. The two archive-import mode pickers do not: the
    /// mode is a view-state choice read at the moment Import is pressed, so its setter writes
    /// nothing to the store and a committing setter there would be wrong, not missing. The third
    /// committing site was `iOSTaskDetailSheetSections`' time picker [[T-761]]; [[T-3171]] made the
    /// task inspector the shared schedule panel, whose time is the draft's roller and whose one
    /// commit is Save, so no picker row on that sheet writes to the store at all.
    @Test func everyChoicePopoverCallSiteIsCountedAndOnlyTheCommittingOnesAnswer() throws {
        let expected: [String: (calls: Int, committing: Int)] = [
            // [[T-3169]]. The shared schedule panel's four draft pickers: list, section, calendar
            // and repeat. **None commits, and that is the right side of the line for all four** —
            // this panel holds a `CadenceScheduleDraft`, a value it copies on every keystroke, and
            // nothing it writes reaches the store until Add/Save is pressed. A committing setter
            // here would write a half-made task on the way past a picker row. It is the same
            // answer, for the same reason, as the three sheets above it. [[T-6901]] adds a fifth,
            // the Ends mode under Repeat, on the same side of the line: it writes the draft.
            "Cadence/Shared/Components/CadenceSchedulePanel.swift": (5, 0),
            "Cadence/Shared/Components/CadenceScheduleCaptureCard.swift": (7, 0),
            "Cadence/Shared/Components/CadenceStartTimeFieldRow.swift": (1, 0),
            "Cadence/iOS/iOSArchiveImportSettingsSection.swift": (1, 0),
            "Cadence/iOS/iOSCalendarSettingsSection.swift": (1, 0),
            "Cadence/iOS/iOSListEditorViews.swift": (2, 0),
            "Cadence/iOS/iOSSettingsOverviewSections.swift": (4, 0),
            // [[T-3171]]: the task inspector is the shared schedule panel. The components file's
            // three — the title card's priority, the breadcrumb's list and section — went with the
            // two views, onto the panel's own rows, so the file holds no picker. The sections
            // file keeps the series' draft pickers (Repeat, Ends), and none commits: they write
            // the draft, which Save commits once. [[T-8593]] made the occurrence count the standard
            // panel's Stepper, so the third (Occurrences) is no longer a popover list.
            "Cadence/iOS/iOSTaskDetailSheetSections.swift": (2, 0),
            "Cadence/iOS/iOSTaskRowActionViews.swift": (2, 2),
            "Cadence/iOS/iOSTaskViews.swift": (1, 0),
            "Cadence/iOS/iOSTrackingEditorComponents.swift": (2, 0),
            "Cadence/macOS/Views/SettingsArchiveImportCard.swift": (1, 0),
            "Cadence/macOS/Views/SettingsCalendarWorkHoursSection.swift": (1, 0),
            "Cadence/macOS/Views/SettingsSectionViews.swift": (1, 0),
            // [[T-5015]] (b): the Mac task row's repeat picker, the macOS twin of the committing
            // row chip in `iOSTaskRowActionViews.swift` two entries above. Committing, and for the
            // same reason that one is: its write reaches the store and can be refused, so the
            // close is the success report and a refusal keeps the popover open with the notice
            // under the rows.
            "Cadence/macOS/Views/MacTaskRowRepeatPickerPopover.swift": (1, 1),
            // [[T-9122]]: the note embed card's Repeat field, the row chip's list with the row
            // chip's writer. Committing for the same reason: the write reaches the store.
            "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift": (1, 1),
        ]

        let read = CadenceSourceScan.strippedSourceReader()
        var found: [String: (calls: Int, committing: Int)] = [:]
        var filesRead = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let source = CadenceSourceScan.codeOnly(try read(path))
            filesRead += 1
            // The declarations themselves are not call sites: `struct X: View {` has no `(`.
            let calls = CadenceSourceScan.matchCount(Self.callPattern, in: source)
            guard calls > 0 else { continue }
            found[path] = (calls, CadenceSourceScan.matchCount(#"\n\s+select: "#, in: source))
        }

        #expect(filesRead > 500, "the census walked \(filesRead) files")
        #expect(found.keys.sorted() == expected.keys.sorted(), "the set of files holding a picker moved")
        for (path, counts) in expected {
            #expect(found[path]?.calls == counts.calls, "\(path) holds \(found[path]?.calls ?? -1) pickers")
            #expect(
                found[path]?.committing == counts.committing,
                "\(path) has \(found[path]?.committing ?? -1) committing pickers"
            )
        }
        // The total is stated, not derived from `expected` — deriving it would make it agree with
        // the table by construction and stop being a second reading of the same population.
        // 39 since the two archive-import mode pickers; 37 before them. [[T-2079]] made it 34:
        // `iOSTrackingEditorSheets.swift` held five, none of them committing, and the file is
        // deleted with the goal and habit editors it contained. T-1466 removes the inspector's
        // milestone picker and the committing row chip, leaving 32 and 3 respectively. [[T-3169]]
        // adds the shared schedule panel's four draft pickers: 36, and the committing count does
        // not move, because a draft panel commits once at Add rather than row by row. [[T-3171]]
        // takes the event editor's two (its Days list and its calendar picker) with it onto the
        // panel, whose calendar picker serves it now and whose separate end date replaced the
        // Days list: 34, still 3 committing. The task editor's slice of the same ticket takes four
        // more (priority, list, section, time) and the one committing time picker: 30 and 2.
        // Its third slice takes the quick-create sheet's three (calendar, list, section) onto the
        // panel's own rows, none of them committing: 27 and 2.
        // T-3195 retires the capture tiles' three and adds the card's four draft pickers.
        // Landing T-3195 added three more to the same card: the Section list, and Frequency and
        // Ends inside `Custom…`. All three were written as native `Picker`s on the branch and are
        // this app's own vocabulary here instead, because `Cadence/iOS` and `Cadence/Shared` draw
        // no native picker — `SettingsSharedVocabularyTests.noMobileOrSharedSurfaceDrawsANativePicker`
        // caught them. Seven on the card, 31 in all; none commits, because the card commits once.
        // [[T-5015]] (b) adds the Mac row's repeat picker: 32, and 3 committing -- the first
        // committing count to move since T-1466, because this is a picker whose write reaches the
        // store from a row rather than a draft a Save commits later.
        // [[T-6901]] adds the standard panel's Ends picker: 33, still 3 committing.
        // [[T-8593]] makes the iOS task sheet's occurrence count the panel's Stepper: 32, still 3.
        // [[T-9122]] draws the embed card's Repeat field through the committing list: 33 and 4.
        #expect(found.values.map(\.calls).reduce(0, +) == 33)
        #expect(found.values.map(\.committing).reduce(0, +) == 4)
    }

    /// **The defect itself, as a detector rather than a list.**
    ///
    /// A picker handed `selection: Binding(` whose setter reaches a commit surface is T-656 exactly
    /// — the mutation is in the binding's setter, where nothing in the `try? save()` rule can
    /// follow it, and the row closes over it. The nearest negative is the shape that must stay
    /// legal: a `Binding` forwarding to a preference write, which commits nothing and is right to
    /// close on the tap.
    @Test func nochoicePopoverIsHandedAselectionBindingThatCommits() throws {
        let instrument = try CadenceScanInstrument(
            "a choice popover whose selection binding setter commits",
            fires: """
            iOSChoicePopoverList(
                rows: rows,
                selection: Binding(
                    get: { task.recurrenceRule },
                    set: { rule in
                        applyRecurrenceRule(rule, to: task)
                        try? modelContext.save()
                    }
                ),
                isPresented: $isPresented
            )
            """,
            andNotOn: """
            iOSChoicePopoverList(
                rows: rows,
                selection: Binding(get: { minute }, set: { set($0) }),
                isPresented: isPresented
            )
            """,
            by: { Self.committingSelectionBinding(in: $0) }
        )

        let offenders = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 500,
            including: Self.rowActionsPath,
            read: { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) hand a choice popover a `selection` binding whose setter commits. \
            The popover closes on the tap, so the dismissal is the success report and it is \
            unconditional. Use the committing initialiser: pass the current value and a `select` \
            that answers whether the write landed.
            """
        )
    }

    // MARK: - The three that answer

    /// The row's repeat chip. Its non-series branch was the site [[T-656]] was written from.
    @Test func therowsRepeatPickerCommitsTheRuleAndStaysOpenWhenTheStoreRefusesIt() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.rowActionsPath)
        let select = try CadenceCommitSurfaceScan.declarationBody(named: "select", in: source)

        #expect(select.contains("CadenceTaskFieldEditCommit.commit(task, in: modelContext)"))
        #expect(
            CadenceSourceScan.matchCount(#"try\? modelContext\.save\(\)"#, in: select) == 0,
            "the recurrence selection still swallows its commit"
        )
        // The series branch answers `true` deliberately: the popover has to close for the scope
        // dialog behind it to be seen, and that dialog does its own commit and its own report.
        #expect(
            CadenceSourceScan.matchCount(
                #"pendingRecurrenceRule\.wrappedValue = rule\s+return true"#,
                in: select
            ) == 1,
            "the series branch does not let the popover close for the scope dialog behind it"
        )
        #expect(
            select.contains("return CadenceTaskFieldEditCommit.commit"),
            "the committing branch does not answer with the commit"
        )
        #expect(source.contains("failureNotice: ruleFailure,"))
        #expect(source.contains("ruleFailure = landed ? nil : CadenceTaskFieldEditCommit.saveFailureNotice"))
    }

    /// T-1466 removes this edit path entirely; it must not return beside the surviving pickers.
    @Test func therowsRetiredMilestonePickerHasNoAssignmentOrCommitPath() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.rowActionsPath)
        #expect(source.contains("struct iOSTaskRowRepeatChip: View"), "non-vacuity: still the chip file")
        #expect(source.contains("failureNotice: ruleFailure,"))
        #expect(!source.contains("selectGoal"))
        #expect(!source.contains("iOSTaskRowGoalPickerContent"))
        #expect(!source.contains("task.goal"))
    }

    /// **The fourth site, [[T-761]] — retired by [[T-3171]], and what replaced it.** The inspector's
    /// time picker committed each minute it was handed, through a `select` closure that answered
    /// whether the write landed so the popover could stay open over a refusal. The inspector is the
    /// shared schedule panel now: the time is the panel's roller, writing the **draft**, and the
    /// store is reached once, by Save, through a commit that restores every field on a refusal. So
    /// the claim T-761 made — no time pick closes over a swallowed commit — holds by there being no
    /// commit under the pick at all, and this pins both halves.
    @Test func theDetailSheetsTimeIsADraftFieldCommittedOnlyBySave() throws {
        let sheetSource = try CadenceCommitSurfaceScan.scanned(Self.detailSheetPath)
        #expect(!sheetSource.contains("selectScheduledTime"), "the per-pick time commit is back")
        #expect(
            CadenceSourceScan.matchCount(#"try\? modelContext\.save\(\)"#, in: sheetSource) == 0,
            "the task editor swallows a commit"
        )
        let apply = try CadenceCommitSurfaceScan.declarationBody(named: "applySave", in: sheetSource)
        #expect(apply.contains("guard CadenceTaskEditDraftCommit.save("), "Save does not guard on the one commit")

        let sectionsSource = try CadenceCommitSurfaceScan.scanned(Self.detailSheetSectionsPath)
        #expect(!sectionsSource.contains("select: selectScheduledTime"), "the sections file still holds the old time picker")
        #expect(sectionsSource.contains("@Binding var draft: CadenceScheduleDraft"), "non-vacuity: the series rows draft too")

        let panel = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let time = try #require(CadenceSourceScan.declarationBody("private var doTimeRow: some View", in: panel))
        #expect(time.contains("CadenceTimeRoller(minutes: doStartMinuteBinding)"))
        let minute = try #require(CadenceSourceScan.declarationBody("private var doStartMinuteBinding: Binding<Int>", in: panel))
        #expect(minute.contains("draft.moveStart(toMinute: $0)"), "the roller writes somewhere other than the draft")
    }

    /// **What is left in the file, exactly: nothing.** Two swallowed saves were removed by this
    /// batch and the third, `iOSTaskRowSubtaskRow`'s tick, left with [[T-8592]] — it commits
    /// through `CadenceTaskInspectorSupport.completeSubtask` now, whose undo puts a refused tick
    /// back. An exact count: a floor over a population that shrank to zero cannot tell a site
    /// that was fixed from one that was added.
    @Test func noSwallowedSaveIsLeftInTheTaskRowActions() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.rowActionsPath)
        #expect(
            CadenceSourceScan.matchCount(#"try\? modelContext\.save\(\)"#, in: source) == 0,
            "a swallowed save is back in the task-row actions"
        )
        // Non-vacuity for the needle: the file is full of the committing spellings too.
        #expect(CadenceSourceScan.matchCount(#"modelContext"#, in: source) > 5)
        #expect(source.contains("struct iOSTaskRowSubtaskRow: View {"))
        #expect(source.contains("struct iOSTaskRowContainerChip: View"))
        #expect(CadenceSourceScan.matchCount(#"try\? modelContext\.save\(\)"#, in: "x\ntry? modelContext.save()\n") == 1)
    }

    // MARK: - Detector internals

    private static let callPattern =
        #"(?:CadenceChoicePopoverList|iOSChoicePopoverList|iOSContainerChoicePopover)\("#

    /// Fires when a choice-popover call is handed `selection: Binding(` whose setter text reaches a
    /// commit surface before the argument list closes with `isPresented:`.
    ///
    /// Crude and checkable on purpose — the window is "from the binding to the next `isPresented:`"
    /// rather than a brace match, so it cannot run away on malformed input, and a scan helper that
    /// traps takes the whole test host with it rather than failing a test.
    static func committingSelectionBinding(in source: String) -> Bool {
        var searchStart = source.startIndex
        while let call = source.range(of: callPattern, options: .regularExpression, range: searchStart..<source.endIndex) {
            searchStart = call.upperBound
            guard let binding = source.range(
                of: "selection: Binding(",
                range: call.upperBound..<source.endIndex
            ) else { continue }
            // A binding that belongs to the *next* call is not this call's.
            if let next = source.range(of: callPattern, options: .regularExpression, range: call.upperBound..<source.endIndex),
               next.lowerBound < binding.lowerBound {
                continue
            }
            let close = source.range(of: "isPresented:", range: binding.upperBound..<source.endIndex)
            let window = String(source[binding.upperBound..<(close?.lowerBound ?? source.endIndex)])
            if CadenceSourceScan.matchCount(commitSurface, in: window) > 0 { return true }
        }
        return false
    }

    private static let commitSurface = #"\.save\(\)|Cadence\w*Persistence\.commit\w*|CadenceTaskFieldEditCommit\.commit"#
}
