import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **The two owner-decided Focus parity fixes of 2026-10-31**, under [[T-8201]]'s rule that a
/// macOS/iOS difference must name a hardware constraint or it is drift.
///
/// - [[T-8732]]: the Focus check control did two different things. On the Mac it is "Log session"
///   and opens a form — editable hours and minutes, an optional "Mark task as complete", Discard.
///   On iOS it was "Log session and mark done" and completed the task in one tap, so a session
///   started on a phone or an iPad could **never** be logged without finishing the task, nor its
///   logged time corrected. The owner chose the Mac's model for iOS.
/// - [[T-8734]]: the Mac draws a titled, live "Task notes" editor under the timer in every session;
///   iOS drew a read-only preview, and nothing at all when the note was empty. The owner chose
///   editable, with the prompt, shown for an empty note too.
///
/// This suite is deliberately **not** `#if os(macOS)`: the helpers both forms read moved into
/// `CadenceFocusSupport` for this, so the iOS leg must be able to see them. `Cadence/iOS/` is
/// behind `#if os(iOS)`, so the iOS screen's own wiring is read from source on both legs; the
/// shared write under it is exercised for real.
@MainActor
struct CadenceFocusLogFormParityTests {

    private struct CommitRefused: Error {}

    private static let iosViewPath = "Cadence/iOS/iOSFocusView.swift"
    private static let iosSheetPath = "Cadence/iOS/iOSFocusLogSessionSheet.swift"
    private static let macPopoverPath = "Cadence/macOS/Views/FocusLogSessionPopovers.swift"
    private static let macViewPath = "Cadence/macOS/Views/FocusView.swift"

    /// Comment-stripped, **not** `codeOnly`: several needles below are string literals the forms
    /// draw ("0" in a field, "h" and "min" beside them), and `codeOnly` blanks string bodies, so a
    /// literal needle read through it can only ever fail.
    private static func code(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped.count == raw.count, "\(path): the stripper changed the length")
        return stripped
    }

    private func makeTask(title: String = "Reconcile invoices") throws -> (AppTask, ModelContext) {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = AppTask(title: title)
        context.insert(task)
        try context.save()
        return (task, context)
    }

    // MARK: - T-8732, the shared write

    /// **The whole point of the ticket, as behaviour:** a session can be logged *without* finishing
    /// the task. Before this, the only iOS path banked the minutes and marked the task done in the
    /// same act, so this state — time logged, task still open — was unreachable from a phone.
    @Test func loggingWithoutCompletingBanksTheMinutesAndLeavesTheTaskOpen() throws {
        let (task, context) = try makeTask()

        try CadenceFocusSupport.logSession(
            hours: 0,
            minutes: 25,
            complete: false,
            task: task,
            modelContext: context,
            reconciler: .inert
        )

        #expect(task.actualMinutes == 25)
        #expect(task.isDone == false, "logging a session finished the task")
        #expect(context.hasChanges == false, "the bank was left pending")
    }

    /// The other half of the choice: ticking the toggle banks the same minutes **and** settles the
    /// task, in one commit.
    @Test func loggingWithCompletingBanksTheMinutesAndFinishesTheTask() throws {
        let (task, context) = try makeTask()

        try CadenceFocusSupport.logSession(
            hours: 1,
            minutes: 5,
            complete: true,
            task: task,
            modelContext: context,
            reconciler: .inert
        )

        #expect(task.actualMinutes == 65, "the hours field was dropped")
        #expect(task.isDone)
        #expect(context.hasChanges == false)
    }

    /// **The corrected figure is what is banked, not the stopwatch.** The form exists so a reading
    /// can be fixed before it becomes a record, so a logged total that ignored the fields would
    /// make the whole surface a lie.
    @Test func theTypedFieldsAreWhatIsBankedNotTheElapsedClock() throws {
        let (task, context) = try makeTask()
        let typed = CadenceFocusSupport.logFieldValues(hoursText: "0", minutesText: "40")

        try CadenceFocusSupport.logSession(
            hours: typed.hours,
            minutes: typed.minutes,
            complete: false,
            task: task,
            modelContext: context,
            reconciler: .inert
        )

        #expect(task.actualMinutes == 40)
    }

    /// T-654's rule on both branches: a refused commit leaves the counters exactly where they were.
    /// `CadenceFocusLedger.bank` writes with `+=` and inserts a `FocusSessionLog` per counter, so
    /// "the next fetch corrects it" is no reading at all here.
    @Test(arguments: [false, true])
    func arefusedLogUnbanksTheMinutes(completing: Bool) throws {
        let (task, context) = try makeTask()
        task.actualMinutes = 7
        try context.save()

        #expect(throws: CommitRefused.self) {
            try CadenceFocusSupport.logSession(
                hours: 0,
                minutes: 25,
                complete: completing,
                task: task,
                modelContext: context,
                reconciler: .inert,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(task.actualMinutes == 7, "a refused log left minutes the store does not hold")
        #expect(task.isDone == false)
        #expect((task.focusSessions ?? []).isEmpty, "a refused log left a ledger row behind")
    }

    /// The form's seed and its confirm label are one definition, reachable from **both** targets —
    /// which is the part that was macOS-only before this ticket. The values themselves are pinned
    /// by `FocusSessionSeedTests`; what is new here is that the iOS leg can ask at all.
    @Test func bothPlatformsReadOneSeedOneParseAndOneConfirmLabel() {
        func seed(_ seconds: Int) -> [Int] {
            let value = CadenceFocusSupport.logFieldSeed(elapsedSeconds: seconds)
            return [value.hours, value.minutes]
        }
        func parsed(_ hours: String, _ minutes: String) -> [Int] {
            let value = CadenceFocusSupport.logFieldValues(hoursText: hours, minutesText: minutes)
            return [value.hours, value.minutes]
        }
        #expect(seed(1_500) == [0, 25])
        #expect(seed(3_660) == [1, 1])
        #expect(parsed(" 1 ", "-5") == [1, 0])
        #expect(parsed("", "abc") == [0, 0])
        #expect(CadenceFocusSupport.logButtonTitle(hours: 1, minutes: 75) == "Log 2h\u{00A0}15m")
        #expect(CadenceFocusSupport.logButtonTitle(hours: 0, minutes: 0) == "Log")
    }

    // MARK: - T-8732, the two forms are one form

    /// Every word the form says is read from the shared vocabulary by **both** presenters, so the
    /// popover and the sheet cannot word the same choice differently. The containers differ on
    /// purpose — a pointer-anchored popover has no meaning under a finger — and that is the only
    /// thing [[T-8201]] lets differ here.
    @Test func thePopoverAndTheSheetSayTheSameWords() throws {
        let popover = try Self.code(Self.macPopoverPath)
        let sheet = try Self.code(Self.iosSheetPath)

        for form in [popover, sheet] {
            for needle in [
                "CadenceFocusSupport.logFormTitle",
                "CadenceFocusSupport.logFormFieldsLabel",
                "CadenceFocusSupport.logFormCompleteLabel",
                "CadenceFocusSupport.logFormDiscardTitle",
                "CadenceFocusSupport.logFieldSeed(elapsedSeconds:",
                "CadenceFocusSupport.logFieldValues(hoursText:",
                "CadenceFocusSupport.logButtonTitle(hours:"
            ] {
                #expect(form.contains(needle), "a Log Session form spells its own \(needle)")
            }
        }

        // Non-vacuity: both files are the forms, not something the reader mis-pointed at.
        #expect(popover.contains("struct LogSessionPopover: View"))
        #expect(sheet.contains("struct iOSFocusLogSessionSheet: View"))
    }

    /// **The iOS form offers the two choices the ticket is about.** Either one missing and the
    /// screen is back to one-tap complete-and-log in a nicer box: an editable pair of fields, a
    /// toggle that is **off** when the form opens, and a Discard.
    @Test func theIOSFormOffersEditableFieldsAnUntickedCompletionAndADiscard() throws {
        let sheet = try Self.code(Self.iosSheetPath)

        #expect(CadenceSourceScan.matchCount(#"TextField\("0", text: text\)"#, in: sheet) == 1)
        #expect(sheet.contains("timeField(label: \"h\", text: $logHoursText"))
        #expect(sheet.contains("timeField(label: \"min\", text: $logMinutesText"))
        #expect(
            sheet.contains("@State private var markComplete = false"),
            "the iOS form opens with the task already set to be completed"
        )
        #expect(sheet.contains("Toggle(isOn: $markComplete)"))
        #expect(sheet.contains("action: onDiscard"))
        #expect(sheet.contains("onLog(logValues.hours, logValues.minutes, markComplete)"))

        // Both fields take the keyboard that can type them, and each is named for VoiceOver — the
        // glyph beside it ("h", "min") is not a label, it is a unit.
        #expect(CadenceSourceScan.matchCount(#"\.keyboardType\(\.numberPad\)"#, in: sheet) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.accessibilityLabel\(accessibilityLabel\)"#, in: sheet) == 1)
    }

    /// The control that opens it: one label on both platforms, and the Mac's muted-at-zero rule.
    /// iOS's said "Log session and mark done" and was green at zero elapsed, which was honest about
    /// a control that completed the task and is wrong about one that opens a form.
    @Test func theIOSCheckControlOpensTheFormUnderTheSharedLabelAndMutesAtZero() throws {
        let view = try Self.code(Self.iosViewPath)
        let controls = try #require(CadenceSourceScan.declarationBody("private func focusControls(", in: view))

        #expect(controls.contains("accessibilityLabel: CadenceFocusSupport.logFormControlLabel"))
        #expect(
            !controls.contains("Log session and mark done"),
            "the iOS control still promises to finish the task"
        )
        #expect(controls.contains("foreground: elapsedSeconds > 0 ? Theme.green : Theme.muted"))
        // The clock is paused before the form reads it, as the Mac pauses before its popover.
        #expect(controls.contains("if timerState.isRunning { timerState.toggle() }"))
        #expect(controls.contains("loggingTask = task"))
        #expect(!controls.contains("complete(task)"), "the control still completes in one tap")

        // The Mac's own control is the same label and the same rule, read out of its own file so
        // this is a parity claim rather than one platform asserted twice.
        let macView = try Self.code(Self.macViewPath)
        #expect(macView.contains("accessibilityLabel: CadenceFocusSupport.logFormControlLabel"))
        #expect(macView.contains("foreground: focusManager.elapsed > 0 ? Theme.green : Theme.muted"))
    }

    /// Both screens perform the same write, and neither spells the bank itself.
    @Test func bothScreensLogThroughTheOneSharedWrite() throws {
        for path in [Self.iosViewPath, "Cadence/macOS/Views/FocusSessionSupport.swift"] {
            let code = try Self.code(path)
            #expect(code.contains("CadenceFocusSupport.logSession("), "\(path) does not use the shared write")
            #expect(
                CadenceSourceScan.matchCount(#"CadenceFocusLedger\.bank\("#, in: code) == 0,
                "\(path) banks focus minutes itself"
            )
        }
    }

    /// **Only a finished task stops being the session**, on iOS as on the Mac
    /// (`FocusLogSessionAndQuitTests.loggingWithoutCompletingKeepsTheSession`). Logging without
    /// completing leaves the picker on the same task; the advance sits inside `if complete`.
    @Test func theIOSScreenMovesOnOnlyWhenTheLogCompletedTheTask() throws {
        let view = try Self.code(Self.iosViewPath)
        let body = try #require(CadenceSourceScan.declarationBody("private func logSession(", in: view))
        let gate = try #require(body.range(of: "if complete {"), "the iOS screen moves on after every log")
        let advance = try #require(body.range(of: "adopt(next)"))
        let ended = try #require(body.range(of: "selectedTarget = nil"))
        #expect(gate.upperBound <= advance.lowerBound)
        #expect(gate.upperBound <= ended.lowerBound)
        #expect(CadenceSourceScan.matchCount(#"adopt\(next\)"#, in: body) == 1)
    }

    // MARK: - T-8734, the notes panel

    /// The heading and the prompt are one pair of strings, read by both panels. Pinned as a
    /// relation on the shared symbol rather than on the literals, so changing the words changes
    /// both panels by construction.
    @Test func bothFocusNotePanelsReadOneHeadingAndOnePrompt() throws {
        for path in [Self.iosViewPath, "Cadence/macOS/Views/FocusNotesPanel.swift"] {
            let code = try Self.code(path)
            #expect(code.contains("CadenceFocusSupport.taskNotesTitle"), "\(path)")
            #expect(code.contains("CadenceFocusSupport.taskNotesPrompt"), "\(path)")
            #expect(
                !code.contains("Capture the details you need while working."),
                "\(path) spells the prompt itself"
            )
        }
        #expect(CadenceFocusSupport.taskNotesTitle == "Task notes")
        #expect(CadenceFocusSupport.taskNotesPrompt == "Capture the details you need while working.")
    }
}
