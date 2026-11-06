#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-8562]]: the iOS and macOS list editors draw one field set, the union.**
///
/// The two editors had drifted in both directions with no hardware or input reason ([[T-8201]]):
/// macOS carried the Apple Calendar link, Status, Archive and Delete, iOS did not; iOS carried the
/// Columns section, macOS does not yet (the SHIP-NOTE on T-8562). `CadenceListEditorFieldSet` is the
/// one list both read. The decision is tested as a value with plain booleans for calendar access —
/// nothing here, and nothing the editors do with it, reaches EventKit — and the editors are pinned
/// to *reading* it, since `Cadence/iOS/` compiles into no macOS test symbol.
struct CadenceListEditorFieldSetTests {
    private typealias FieldSet = CadenceListEditorFieldSet

    // MARK: - The decision

    @Test func anExistingListWithCalendarAccessCarriesTheLinkAndTheLifecycleRows() {
        for kind in [FieldSet.Kind.area, .project] {
            let fields = FieldSet.fields(kind: kind, isEditing: true, isCalendarAccessGranted: true)
            for field in [CadenceListEditorField.appleCalendar, .status, .archive, .delete, .columns, .context] {
                #expect(fields.contains(field), "\(kind) editor lacks \(field)")
            }
        }
    }

    /// The row is gated on access **already granted**: without it there is no row at all, so the
    /// editor has nothing that could ask for access.
    @Test func withoutCalendarAccessNoEditorDrawsTheCalendarRow() {
        for kind in [FieldSet.Kind.area, .project] {
            for isEditing in [true, false] {
                let fields = FieldSet.fields(kind: kind, isEditing: isEditing, isCalendarAccessGranted: false)
                #expect(!fields.contains(.appleCalendar), "\(kind) editing=\(isEditing) draws the calendar row with no access")
            }
        }
    }

    /// A list that does not exist yet has no status to move, nothing to delete, and — as on both
    /// platforms before this ticket — no calendar link offered at creation.
    @Test func aNewListCarriesNoLifecycleRowsAndNoCalendarLink() {
        for kind in [FieldSet.Kind.area, .project] {
            let fields = FieldSet.fields(kind: kind, isEditing: false, isCalendarAccessGranted: true)
            for field in [CadenceListEditorField.status, .archive, .delete, .appleCalendar] {
                #expect(!fields.contains(field), "a new \(kind) offers \(field)")
            }
            #expect(fields.contains(.columns), "a new \(kind) cannot set up its columns")
        }
    }

    @Test func onlyAProjectCarriesAnAreaAndADueDate() {
        for isEditing in [true, false] {
            let project = FieldSet.fields(kind: .project, isEditing: isEditing, isCalendarAccessGranted: true)
            let area = FieldSet.fields(kind: .area, isEditing: isEditing, isCalendarAccessGranted: true)
            #expect(project.contains(.area) && project.contains(.dueDate))
            #expect(!area.contains(.area) && !area.contains(.dueDate))
        }
    }

    @Test func theStatusRowWordsEveryStoredStatus() {
        #expect(FieldSet.statusLabel(AreaStatus.active) == "Active")
        #expect(FieldSet.statusLabel(AreaStatus.done) == "Completed")
        #expect(FieldSet.statusLabel(AreaStatus.archived) == "Archived")
        #expect(FieldSet.statusLabel(ProjectStatus.paused) == "Paused")
        #expect(FieldSet.statusLabel(ProjectStatus.cancelled) == "Canceled")
        #expect(FieldSet.statusLabel(ProjectStatus.done) == "Completed")
    }

    /// **[[T-11871]]: one blank-name rule for Save and for every lifecycle row.** Whitespace and
    /// newlines are blank, as `CadenceTitleNormalization.isBlank` says; anything else is a name.
    @Test func aBlankDraftNameIsRefusedAndAnyOtherIsAccepted() {
        for blank in ["", " ", "\n", " \t\n "] {
            #expect(!FieldSet.acceptsName(blank), "\(blank.debugDescription) was accepted")
        }
        for name in ["A", " Alpha Area ", "\nx"] {
            #expect(FieldSet.acceptsName(name), "\(name.debugDescription) was refused")
        }
    }

    // MARK: - Both editors read it

    private static let iOSEditorPath = "Cadence/iOS/iOSListEditorViews.swift"
    private static let macEditPath = "Cadence/macOS/Sheets/EditListSheet.swift"
    private static let macCreatePath = "Cadence/macOS/Sheets/CreateListSheet.swift"

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private static func body(of declaration: String, in code: String, length: Int = 600) throws -> String {
        let start = try #require(code.range(of: declaration), "no \(declaration)")
        return String(code[start.upperBound...].prefix(length))
    }

    @Test func everyEditorAsksTheSharedFieldSet() throws {
        for path in [Self.iOSEditorPath, Self.macEditPath, Self.macCreatePath] {
            let code = try Self.code(path)
            #expect(code.contains("CadenceListEditorFieldSet.fields("), "\(path) decides its own fields")
        }
        let mac = try Self.code(Self.macEditPath)
        #expect(CadenceSourceScan.matchCount("isCalendarAccessGranted: calendarManager\\.isAuthorized", in: mac) == 2)
        #expect(CadenceSourceScan.matchCount("if fields\\.contains\\(\\.appleCalendar\\)", in: mac) == 2)
        #expect(!mac.contains("if calendarManager.isAuthorized"), "a Mac sheet gates the calendar row on its own")
    }

    /// The iOS row exists, sits behind the shared gate, is fed the manager's `isAuthorized`, and the
    /// editor asks EventKit for nothing.
    @Test func theIOSEditorDrawsTheCalendarRowOnlyBehindGrantedAccess() throws {
        let code = try Self.code(Self.iOSEditorPath)
        #expect(code.contains("isCalendarAccessGranted: calendarManager.isAuthorized"))
        let gate = try #require(code.range(of: "if fields.contains(.appleCalendar) {"))
        #expect(String(code[gate.upperBound...].prefix(80)).contains("calendarRow"), "the gate does not hold the row")
        #expect(CadenceSourceScan.matchCount("\\bcalendarRow\\b", in: code) == 2, "the row is drawn outside the gate")
        for forbidden in ["EKEventStore(", "requestAccess", "requestFullAccess", "requestWriteOnlyAccess"] {
            #expect(!code.contains(forbidden), "the list editor reaches EventKit through \(forbidden)")
        }
        // T-624 evidence, as the Mac row declares it.
        let link = try Self.body(of: "private var calendarLink: CadenceCalendarLink {", in: code, length: 500)
        #expect(link.contains("evidence: .synced("))
    }

    /// T-624: a changed pick is recorded against the stored value, so the record precedes the write.
    @Test func theIOSEditorRecordsACalendarPickBeforeItWritesTheLink() throws {
        let code = try Self.code(Self.iOSEditorPath)
        for stored in ["area.linkedCalendarID", "project.linkedCalendarID"] {
            let record = try #require(code.range(of: "CadenceCalendarLinkObservations.recordPick(selectedCalendarID, replacing: \(stored))"))
            let write = try #require(code.range(of: "\(stored) = selectedCalendarID"))
            #expect(record.lowerBound < write.lowerBound, "\(stored) is written before the pick is recorded")
        }
        #expect(code.contains("selectedCalendarID = area.linkedCalendarID"))
        #expect(code.contains("selectedCalendarID = project.linkedCalendarID"))
    }

    /// Status, Archive and Delete go through the Lists page's own wind-down and cascade, and a
    /// lifecycle move writes the pending edits before it settles anything.
    @Test func theIOSEditorsLifecycleRowsReuseTheListPagesMachinery() throws {
        let code = try Self.code(Self.iOSEditorPath)
        #expect(code.contains("if fields.contains(.status) {"))
        #expect(code.contains("if fields.contains(.archive) {"))
        #expect(code.contains("if fields.contains(.delete), let target = deletionTarget {"))
        #expect(code.contains(".iOSListWindDown(target: $pendingListWindDown, perform: performListWindDown)"))
        #expect(code.contains(".iOSListDeletion(target: $pendingListDeletion, onDeleted: { dismiss() })"))
        #expect(CadenceSourceScan.matchCount("iOSListDeleteMenuButton\\(", in: code) == 1)

        // The move is handed to Save, never performed beside it ...
        let perform = try Self.body(of: "private func performListWindDown(_ target: iOSListWindDownTarget) {", in: code, length: 120)
        #expect(perform.contains("lifecycleStep = .windDown(target)\n        save()"))
        #expect(!perform.contains("windDownList"), "the wind-down runs outside the edit's commit")
        // ... and Save settles it only after its commit landed and no column name was refused.
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: code))
        let commit = try #require(save.range(of: "try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: undo.restore)", options: .backwards))
        let refused = try #require(save.range(of: "guard refusal == nil else { return }"))
        let settle = try #require(save.range(of: "modelContext.windDownList(target)"))
        #expect(commit.lowerBound < settle.lowerBound, "a wind-down settles before the pending edits are written")
        #expect(refused.lowerBound < settle.lowerBound, "a wind-down settles over a refused column name")
        #expect(save.contains("defer { lifecycleStep = nil }"))

        let request = try Self.body(of: "private func requestListWindDown(_ action: iOSListWindDownAction) {", in: code, length: 300)
        #expect(request.contains("guard target.summary.requiresConfirmation else {"))
    }

    /// **[[T-11871]] on iOS.** `save()` is the one door every row goes through -- Save, Return,
    /// Status, Archive / Unarchive, a confirmed wind-down -- so its guard is what refuses a blank
    /// name; the rows are also disabled on the same rule so the sheet does not offer what it
    /// refuses. Delete writes no name and stays live.
    @Test func theIOSEditorsLifecycleRowsRefuseABlankName() throws {
        let code = try Self.code(Self.iOSEditorPath)
        #expect(code.contains("CadenceListEditorFieldSet.acceptsName(name)"))
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: code))
        let guardRange = try #require(save.range(of: "guard acceptsName else { return }"), "save() writes a blank name")
        let firstWrite = try #require(save.range(of: "switch resolvedMode {"))
        #expect(guardRange.lowerBound < firstWrite.lowerBound, "the guard runs after the write")
        let section = try Self.body(of: "private var lifecycleSection: some View {", in: code, length: 3400)
        #expect(section.contains(".disabled(currentLifecycleChoice == .active || !acceptsName)"))
        #expect(section.contains(".disabled(currentLifecycleChoice == .completed || !acceptsName)"))
        #expect(section.contains(".disabled(!acceptsName)"), "the Archive row is offered on a blank name")
        let delete = try #require(section.range(of: "iOSListDeleteMenuButton("))
        let archive = try #require(section.range(of: ".disabled(!acceptsName)"))
        #expect(archive.lowerBound < delete.lowerBound, "the blank-name gate reached the Delete row")
    }

    /// **[[T-11871]] on the Mac.** Both sheets' Save and lifecycle doors are guarded and their
    /// Status row and Archive button disabled on the shared rule.
    @Test func theMacSheetsLifecycleRowsRefuseABlankName() throws {
        let code = try Self.code(Self.macEditPath)
        let rule = "CadenceListEditorFieldSet.acceptsName(name)"
        #expect(CadenceSourceScan.matchCount("isConfirmDisabled: !CadenceListEditorFieldSet\\.acceptsName\\(name\\)", in: code) == 2)
        #expect(CadenceSourceScan.matchCount("isDisabled: !CadenceListEditorFieldSet\\.acceptsName\\(name\\)", in: code) == 4,
                "a Status row or Archive button is offered on a blank name")
        for declaration in ["private func apply(_ choice: ListEditorLifecycleChoice) {", "private func saveEdits() {"] {
            var searched = Substring(code)
            var guards = 0
            while let range = searched.range(of: declaration) {
                let body = String(searched[range.upperBound...].prefix(400))
                if body.contains("guard \(rule) else { return }") { guards += 1 }
                searched = searched[range.upperBound...]
            }
            #expect(guards == 2, "\(declaration) is unguarded in \(2 - guards) sheet(s)")
        }
        let support = try Self.code("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        #expect(support.contains(".disabled(isDisabled)\n        .opacity(isDisabled ? 0.52 : 1)\n        .popover("))
        #expect(support.contains("isDisabled: isDisabled,\n            action: action"))
    }

    /// **[[T-11872]]: the iOS Status menu ticks what the Mac popover ticks.** It reads the shared
    /// `ListEditorLifecycleChoice` mapping, so a paused or cancelled project ticks neither row and
    /// leaves Active offered, rather than ticking Active and refusing it.
    @Test func theIOSStatusMenuTicksFromTheSharedLifecycleChoice() throws {
        let code = try Self.code(Self.iOSEditorPath)
        #expect(code.contains("if let editedArea { return ListEditorLifecycleChoice(editedArea.status) }"))
        #expect(code.contains("if let editedProject { return ListEditorLifecycleChoice(editedProject.status) }"))
        let section = try Self.body(of: "private var lifecycleSection: some View {", in: code, length: 3400)
        #expect(section.contains(#"Label("Active", systemImage: currentLifecycleChoice == .active ? "checkmark" : "circle")"#))
        #expect(section.contains(#"systemImage: currentLifecycleChoice == .completed ? "checkmark" : iOSListWindDownAction.complete.icon"#))
        #expect(!section.contains("editedIsDone"), "the menu ticks from its own Bool again")
        // The mapping is compiled for both platforms now, from the Shared folder.
        let shared = try Self.code("Cadence/Shared/CadenceListEditorFieldSet.swift")
        #expect(shared.contains("enum ListEditorLifecycleChoice: CaseIterable {"))
        #expect(shared.contains("case .paused, .cancelled: return nil"))
    }

    /// `onDeleted` runs after the cascade committed, never before it.
    @Test func theDeletionModifierReportsADeleteOnlyAfterItCommitted() throws {
        let code = try Self.code("Cadence/iOS/iOSListDeletionSupport.swift")
        let perform = try #require(code.range(of: "try perform(target)"))
        let report = try #require(code.range(of: "onDeleted?()"))
        #expect(perform.lowerBound < report.lowerBound)
    }
}
#endif
