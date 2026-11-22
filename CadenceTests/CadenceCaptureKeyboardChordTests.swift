import Foundation
import Testing
@testable import Cadence

/// **[[T-18540]]: the New Task composer's keyboard chords, on both platforms.**
///
/// The Mac's `CreateTaskSheet` answered Cmd+T / Cmd+D, Cmd+Shift+T / Cmd+Shift+D, Cmd+P and
/// Cmd+Shift+= / Cmd+Shift+- ([[T-13792]]); the same capture card on an iPad with a hardware
/// keyboard, opened by the same Cmd+N, answered only Cmd+Return and Escape ([[T-18083]]). The
/// draft edits (`CreateTaskKeyboardCommands`) moved to `Cadence/Shared/` unchanged and the iOS
/// keyboard layer binds them. The edits are pure, so they are tested on a draft here (these tests
/// were the Mac suite's and run ungated now); the iOS binding is `#if os(iOS)`, which
/// `CadenceTests` does not compile, so it is read from source, comments stripped.
@MainActor
struct CadenceCaptureKeyboardChordTests {
    private static func blankTask() -> CadenceScheduleDraft {
        CadenceTaskComposerSupport.captureDraft(seed: CadenceTaskComposerSeed())
    }

    // MARK: - The draft edits

    @Test func commandTSetsTodayThenClearsIt() {
        var draft = Self.blankTask()
        CreateTaskKeyboardCommands.toggleDoToday(&draft, today: "2026-11-08")
        #expect(draft.startDateKey == "2026-11-08")
        #expect(draft.endDateKey == "2026-11-08")
        #expect(draft.scheduledStartMin == -1, "a keyed do date adds no time")
        CreateTaskKeyboardCommands.toggleDoToday(&draft, today: "2026-11-08")
        #expect(draft.startDateKey.isEmpty)
    }

    @Test func commandDSetsTodayAsDueThenClearsIt() {
        var draft = Self.blankTask()
        CreateTaskKeyboardCommands.toggleDueToday(&draft, today: "2026-11-08")
        #expect(draft.dueDateKey == "2026-11-08")
        CreateTaskKeyboardCommands.toggleDueToday(&draft, today: "2026-11-08")
        #expect(draft.dueDateKey.isEmpty)
    }

    @Test func theNudgeStartsFromTodayAndMovesADay() {
        var draft = Self.blankTask()
        CreateTaskKeyboardCommands.nudgeDoDate(&draft, by: 1, today: "2026-11-08")
        #expect(draft.startDateKey == "2026-11-09")
        CreateTaskKeyboardCommands.nudgeDoDate(&draft, by: -2, today: "2026-11-08")
        #expect(draft.startDateKey == "2026-11-07")
        #expect(draft.endDateKey == draft.startDateKey)
    }

    @Test func commandPCyclesPriorityAndWraps() {
        var draft = Self.blankTask()
        let all = TaskPriority.allCases
        for step in 1...all.count {
            CreateTaskKeyboardCommands.cyclePriority(&draft)
            #expect(draft.priority == all[step % all.count])
        }
    }

    /// [[T-14041]]: with `!!` typed in the title the card shows medium, and Cmd+P has to move what
    /// the card shows -- and what the task will be created with -- rather than a `draft.priority`
    /// the title mark overrules on both.
    @Test func commandPStepsFromATitleMarkAndTakesItOut() {
        var draft = Self.blankTask()
        draft.title = "Call mom !!"
        #expect(CadenceCaptureFieldInventory.priority(for: draft) == .medium)

        CreateTaskKeyboardCommands.cyclePriority(&draft)

        #expect(draft.title == "Call mom")
        #expect(draft.priority == .high)
        #expect(CadenceCaptureFieldInventory.priority(for: draft) == .high)
        let creation = CadenceTaskComposerSupport.creationDraft(
            from: draft, container: .inbox, tags: [], subtaskTitles: []
        )
        #expect(creation.resolvedPriority == .high)
    }

    /// A title with no mark keeps its text exactly, trailing space included: the caret is in it.
    @Test func commandPLeavesAnUnmarkedTitleAsTyped() {
        var draft = Self.blankTask()
        draft.title = "Call mom "
        CreateTaskKeyboardCommands.cyclePriority(&draft)
        #expect(draft.title == "Call mom ")
        #expect(draft.priority == .low)
    }

    /// The date chords are the task's: an event's start is a range the card's Starts row moves.
    @Test func theChordsLeaveAnEventAlone() {
        var event = CadenceTaskComposerSupport.captureDraft(seed: CadenceTaskComposerSeed(), initialKind: .event)
        let opened = event
        CreateTaskKeyboardCommands.toggleDoToday(&event, today: "2026-01-01")
        CreateTaskKeyboardCommands.toggleDueToday(&event, today: "2026-01-01")
        CreateTaskKeyboardCommands.nudgeDoDate(&event, by: 3, today: "2026-01-01")
        CreateTaskKeyboardCommands.cyclePriority(&event)
        #expect(event == opened)
    }

    // MARK: - The iPad binding

    private static let iosLayerPath = "Cadence/iOS/iOSCreateTaskSheet.swift"
    private static let macSheetPath = "Cadence/macOS/Sheets/CreateTaskSheet.swift"

    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    /// Every `.keyboardShortcut(...)` argument list in `compact`, in order.
    private static func chords(in compact: String) -> [String] {
        var found: [String] = []
        var cursor = compact.startIndex
        while let open = compact.range(of: ".keyboardShortcut(", range: cursor..<compact.endIndex) {
            guard let close = compact.range(of: ")", range: open.upperBound..<compact.endIndex) else { break }
            found.append(String(compact[open.upperBound..<close.lowerBound]))
            cursor = close.upperBound
        }
        return found
    }

    /// Each of the seven chords is a titled button (so the Cmd-hold overlay lists it) calling the
    /// same shared edit, or the same card panel request, as the Mac's.
    @Test func theIPadLayerBindsTheSevenChordsToTheSharedEdits() throws {
        let layer = try Self.compactBody("func iOSCaptureKeyboardCommands(", in: Self.iosLayerPath)
        for binding in [
            #"Button("DoToday"){CreateTaskKeyboardCommands.toggleDoToday(&draft.wrappedValue)}.keyboardShortcut("t",modifiers:.command)"#,
            #"Button("DoDate"){fieldRequest.wrappedValue=.doDate}.keyboardShortcut("t",modifiers:[.command,.shift])"#,
            #"Button("DueToday"){CreateTaskKeyboardCommands.toggleDueToday(&draft.wrappedValue)}.keyboardShortcut("d",modifiers:.command)"#,
            #"Button("DueDate"){fieldRequest.wrappedValue=.dueDate}.keyboardShortcut("d",modifiers:[.command,.shift])"#,
            #"Button("NextPriority"){CreateTaskKeyboardCommands.cyclePriority(&draft.wrappedValue)}.keyboardShortcut("p",modifiers:.command)"#,
            #"Button("DoDateaDayLater"){CreateTaskKeyboardCommands.nudgeDoDate(&draft.wrappedValue,by:1)}.keyboardShortcut("=",modifiers:[.command,.shift])"#,
            #"Button("DoDateaDayEarlier"){CreateTaskKeyboardCommands.nudgeDoDate(&draft.wrappedValue,by:-1)}.keyboardShortcut("-",modifiers:[.command,.shift])"#,
        ] {
            #expect(layer.contains(binding), "missing from the iPad keyboard layer: \(binding)")
        }
        #expect(layer.contains(".opacity(0).frame(width:0,height:0).accessibilityHidden(true)"))
        #expect(!layer.contains(".hidden()"), "`.hidden()` can drop a button's shortcut")
    }

    /// The relation the ticket is about: the iPad composer answers exactly the Mac composer's keys.
    @Test func theIPadComposerAnswersExactlyTheMacComposersChords() throws {
        let ios = Self.chords(in: try Self.compactBody("func iOSCaptureKeyboardCommands(", in: Self.iosLayerPath))
        let mac = Self.chords(in: try Self.compactBody("private var keyboardShortcuts: some View", in: Self.macSheetPath))
        #expect(mac.count == 9, "non-vacuous: the Mac sheet's layer was read (\(mac))")
        #expect(ios.count == mac.count, "iPad \(ios) against Mac \(mac)")
        #expect(Set(ios) == Set(mac), "iPad \(ios) against Mac \(mac)")
    }

    /// Cmd+Shift+T is also the iPad markdown editor's checklist key (`iOSMarkdownTextView`). The
    /// capture card's notes there are its own plain `TextField`, not that editor: neither iOS host
    /// hands the panel a `notesField`, so the chord has one owner.
    @Test func theCaptureNotesFieldDoesNotAlsoClaimCommandShiftT() throws {
        for path in [Self.iosLayerPath, "Cadence/iOS/iOSCalendarQuickCreateSheet.swift"] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("CadenceSchedulePanel("), "non-vacuous: \(path) hosts the card")
            #expect(!source.contains("notesField"), "\(path) hands the card its own notes editor")
            #expect(!source.contains("iOSMarkdown"), "\(path) draws the markdown editor")
        }
        let card = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        )
        #expect(card.contains(#"TextField("Notes", text: $draft.notes, axis: .vertical)"#))
    }
}
