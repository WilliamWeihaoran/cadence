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
    /// Three of thirty-seven commit, and all three are task-row chips. `iOSTaskDetailSheet`'s time
    /// picker is a fourth site of the same defect and is **not** fixed here: its setter lives in a
    /// file another agent held in this batch. [[T-761]].
    @Test func everyChoicePopoverCallSiteIsCountedAndOnlyTheCommittingOnesAnswer() throws {
        let expected: [String: (calls: Int, committing: Int)] = [
            "Cadence/Shared/Components/CadenceStartTimeFieldRow.swift": (1, 0),
            "Cadence/iOS/iOSCalendarEventEditSheet.swift": (2, 0),
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift": (3, 0),
            "Cadence/iOS/iOSCalendarSettingsSection.swift": (1, 0),
            "Cadence/iOS/iOSCreateTaskSheetSupportViews.swift": (3, 0),
            "Cadence/iOS/iOSListEditorViews.swift": (2, 0),
            "Cadence/iOS/iOSSettingsOverviewSections.swift": (4, 0),
            "Cadence/iOS/iOSTaskDetailComponents.swift": (2, 0),
            "Cadence/iOS/iOSTaskDetailSheetSections.swift": (6, 0),
            "Cadence/iOS/iOSTaskRowActionViews.swift": (3, 3),
            "Cadence/iOS/iOSTaskViews.swift": (1, 0),
            "Cadence/iOS/iOSTrackingEditorComponents.swift": (2, 0),
            "Cadence/iOS/iOSTrackingEditorSheets.swift": (5, 0),
            "Cadence/macOS/Views/SettingsCalendarWorkHoursSection.swift": (1, 0),
            "Cadence/macOS/Views/SettingsSectionViews.swift": (1, 0),
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
        #expect(found.values.map(\.calls).reduce(0, +) == 37)
        #expect(found.values.map(\.committing).reduce(0, +) == 3)
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

    /// The row's milestone chip. The same defect two declarations below the repeat chip's, and
    /// found by counting the class rather than by reading the ticket.
    @Test func therowsMilestonePickerCommitsTheGoalAndUndoesItWhenTheStoreRefuses() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.rowActionsPath)
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "selectGoal", in: source)

        #expect(body.contains("let previous = task.goal"), "the milestone edit captures no undo")
        #expect(source.contains("try CadencePendingChangePersistence.commitEdit(in: modelContext) {"))
        #expect(source.contains("task.goal = previous"), "a refused milestone is not put back")
        #expect(source.contains("failureNotice: goalFailure,"))
        #expect(
            CadenceSourceScan.matchCount(#"task\.goal = goalID\.flatMap"#, in: source) == 0,
            "the milestone picker still writes through the binding setter"
        )
    }

    /// **What is left in the file, exactly and by name.** Two swallowed saves were removed and
    /// **one** stays: `iOSTaskRowSubtaskRow` ticks a subtask done and reports nothing, which is the
    /// case the rule allows — an in-place field edit whose only witness is the row that redraws.
    ///
    /// An exact count rather than "fewer than before": the population here is one this batch
    /// shrank, and a floor over a shrinking population cannot tell a site that was fixed from one
    /// that was added.
    @Test func exactlyOneSwallowedSaveIsLeftInTheTaskRowActionsAndItReportsNothing() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.rowActionsPath)
        #expect(
            CadenceSourceScan.matchCount(#"try\? modelContext\.save\(\)"#, in: source) == 1,
            "the set of swallowed saves in the task-row actions moved"
        )
        let subtaskRow = try #require(source.range(of: "struct iOSTaskRowSubtaskRow: View {"))
        let swallow = try #require(source.range(of: "try? modelContext.save()"))
        #expect(
            swallow.lowerBound > subtaskRow.upperBound,
            "the one remaining swallow is not the subtask row's"
        )
        // Non-vacuity for the needle: the file is full of the committing spellings too.
        #expect(CadenceSourceScan.matchCount(#"modelContext"#, in: source) > 5)
        #expect(source.contains("struct iOSTaskRowContainerChip: View"))
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
