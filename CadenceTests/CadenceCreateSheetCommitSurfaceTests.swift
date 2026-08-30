import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-503: the four screens that inserted and never committed at all.**
///
/// T-322 wrote the `try? save()` rule and T-497 applied it, and applying it is what found the hole:
/// **both halves key on the presence of a `try? …save()`**, so a function that inserts and commits
/// nothing whatsoever passed both sweeps. Re-measured over the same 552 files under `Cadence/`:
/// **21 declarations call `modelContext.insert(…)` and reach neither a `save()` nor any
/// `CadencePendingChangePersistence.commit*`.** Seventeen of those are helpers whose *caller* owns
/// the unit of work; `CadenceSaveCommitRule.commitReachOffenders` subtracts them by rule rather
/// than by name, and `CadenceSaveCommitDisciplineTests` states that rule.
///
/// The other four also **report success in the same function**, which makes them [[T-471]]'s defect
/// with the save missing entirely rather than swallowed:
///
/// - `CreateContextSheet.create` — `insert(ctx); dismiss()`.
/// - `CreateListSheet.create` — the same, over whichever of `Area`/`Project` the switch took.
/// - `CreateHabitSheet.create` — `insert(habit)`, then a notification reconcile *and* a dismiss.
/// - `CalendarEventEditPopover.openEventNote` — the macOS twin of the site T-497 fixed on iOS, one
///   platform behind and worse: iOS at least attempted a save. Presenting the editor is itself the
///   report that the note exists.
///
/// Cost is the one T-322 measured: this app has a single `ModelContext`, so the row stayed
/// *pending* in it — committed by the next unrelated save from any screen, or discarded by the next
/// unrelated `rollback()`.
///
/// **Why the assertions are shaped the way they are.** All four are `private func`s on SwiftUI
/// `View`s, so nothing here can call them; the instrument is a source scan, exactly as for six of
/// T-497's seven. The one behavioural assertion below is about the *trap* T-497 found, which the
/// macOS twin inherits because both platforms call the same `CadenceEventNoteSupport.noteForEditing`.
@MainActor
struct CadenceCreateSheetCommitSurfaceTests {

    // MARK: - Source shape: the three creation sheets

    /// **Source shape.** Closing the sheet is this screen's only report of success, so it sits
    /// below the `catch`, and the notice it sets is one the sheet actually draws.
    @Test func theContextCreatorClosesOnlyOnACommittedInsert() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Sheets/CreateContextSheet.swift")
        let create = try CadenceCommitSurfaceScan.declarationBody(named: "create", in: sheet)

        #expect(create.contains("modelContext.insert(ctx)"))
        #expect(create.contains("CadencePendingChangePersistence.commitInsert(of: ctx, in: modelContext)"))
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0, "create still swallows its commit")
        #expect(create.contains("createFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: create),
            "the sheet closes above its failure branch"
        )
        #expect(
            sheet.contains("CadenceInlineFailureNotice(text: createFailureNotice)"),
            "the sheet sets a notice it never draws"
        )
    }

    /// **Source shape.** The list creator is a two-armed switch, so the assertion that matters
    /// beyond the ordering is that the commit is handed **the object the arm actually made**:
    /// `inserted` is assigned in both arms, and `commitInsert` is passed it rather than a name
    /// scoped to one of them.
    @Test func theListCreatorClosesOnlyOnACommittedInsertOfTheArmItTook() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Sheets/CreateListSheet.swift")
        let create = try CadenceCommitSurfaceScan.declarationBody(named: "create", in: sheet)

        #expect(create.contains("modelContext.insert(area)"))
        #expect(create.contains("modelContext.insert(project)"))
        // One per arm; a single assignment would mean one of the two branches commits the other's
        // object, or nothing at all.
        #expect(CadenceSourceScan.matchCount(#"inserted = (area|project)\b"#, in: create) == 2)
        #expect(create.contains("CadencePendingChangePersistence.commitInsert(of: [inserted], in: modelContext)"))
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0, "create still swallows its commit")
        #expect(create.contains("createFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: create),
            "the sheet closes above its failure branch"
        )
        #expect(sheet.contains("CadenceInlineFailureNotice(text: createFailureNotice)"))
    }

    /// **Source shape.** This sheet reports success twice, and both reports have to move below the
    /// `catch`. The reconcile is the one that is easy to miss and the one that reaches furthest:
    /// it fetches the habit table back out of the context, so running it over an insert that is
    /// about to be un-inserted schedules a reminder for a habit nothing holds.
    @Test func theHabitCreatorReconcilesAndClosesOnlyOnACommittedInsert() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/HabitsFormSheets.swift")
        let create = try CadenceCommitSurfaceScan.declarationBody(named: "create", in: sheet)

        #expect(create.contains("modelContext.insert(habit)"))
        #expect(create.contains("CadencePendingChangePersistence.commitInsert(of: habit, in: modelContext)"))
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0, "create still swallows its commit")
        #expect(create.contains("createFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch(
                "HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)",
                in: create
            ),
            "the reminder reconcile runs above the failure branch"
        )
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: create),
            "the sheet closes above its failure branch"
        )
        #expect(sheet.contains("CadenceInlineFailureNotice(text: createFailureNotice)"))
    }

    // MARK: - Source shape: the macOS twin of T-497's sharpest site

    /// **Source shape.** Presenting the editor is the success report, so `presentedEventNote = note`
    /// sits below the `catch` — which is also the spelling T-503 added to the rule's report
    /// vocabulary, so this site is visible to half 2 from now on as well as to half 3.
    ///
    /// `inserted` records what the closure actually inserted rather than assuming, because
    /// `noteForEditing` returns an existing note as often as it makes one. That is T-497's trap,
    /// and it applies unchanged here: both platforms call the same shared function.
    @Test func theTimelineEventNoteButtonOpensTheEditorOnlyOnACommittedInsert() throws {
        let views = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/TimelineEventBlockSupportViews.swift")
        let open = try CadenceCommitSurfaceScan.declarationBody(named: "openEventNote", in: views)

        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: open) == 0, "openEventNote still swallows its commit")
        #expect(open.contains("var inserted: [any PersistentModel] = []"))
        #expect(open.contains("inserted.append($0)"), "the undo would reach a note it did not insert")
        #expect(open.contains("CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)"))
        #expect(open.contains("noteFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("presentedEventNote = note", in: open),
            "the popover presents the note above its failure branch"
        )
        #expect(views.contains("CadenceInlineFailureNotice(text: noteFailureNotice)"))
    }

    /// **Behavioural**, and the reason the scan above insists on `inserted.append($0)`: reopening
    /// an event note the user already has must insert nothing, so there is nothing for a refused
    /// commit to delete.
    ///
    /// Asserted through the **macOS** wrapper rather than the shared function. The wrapper is a
    /// forwarder, and a forwarder that dropped or defaulted its `insert` closure is exactly the way
    /// this platform could inherit the shape without inheriting the behaviour;
    /// `CalendarBehaviorRegressionTests` already pins the shared function itself.
    @Test func themacOSEventNoteWrapperInsertsNothingWhenItReopensANoteTheUserAlreadyHad() throws {
        let existing = Note(
            kind: .meeting,
            title: "Kickoff",
            content: "Existing notes",
            calendarEventID: "event-1",
            calendarID: "calendar-1",
            eventDateKey: "2026-08-10",
            eventStartMin: 540,
            eventEndMin: 570
        )

        var inserted: [Note] = []
        let reopened = try #require(EventNoteSupport.noteForEditing(
            calendarEventID: "event-1",
            eventTitle: "Kickoff",
            calendarID: "calendar-1",
            eventDateKey: "2026-08-10",
            eventStartMin: 540,
            eventEndMin: 570,
            notes: [existing],
            insert: { inserted.append($0) }
        ))

        #expect(reopened.id == existing.id)
        #expect(inserted.isEmpty, "reopening an existing event note inserted something to un-insert")

        // The other arm, so the emptiness above is a property of *reopening* rather than of a
        // wrapper that forgot to forward the closure at all.
        var created: [Note] = []
        let made = try #require(EventNoteSupport.noteForEditing(
            calendarEventID: "event-2",
            eventTitle: "Retro",
            calendarID: "calendar-1",
            eventDateKey: "2026-08-11",
            eventStartMin: 600,
            eventEndMin: 630,
            notes: [existing],
            insert: { created.append($0) }
        ))
        #expect(created.map(\.id) == [made.id], "creating an event note did not report what it inserted")
    }

    // MARK: - Non-vacuity

    /// Non-vacuity for every scan above: the reader really opened these four files, the ordering
    /// helper really distinguishes the two orders it is asked about, the stripper really strips,
    /// and each needle matches the spelling it hunts and nothing else.
    @Test func thesourceScanActuallyReadsTheseCreateSheets() throws {
        for (path, marker) in [
            ("Cadence/macOS/Sheets/CreateContextSheet.swift", "struct CreateContextSheet: View"),
            ("Cadence/macOS/Sheets/CreateListSheet.swift", "struct CreateListSheet: View"),
            ("Cadence/macOS/Views/HabitsFormSheets.swift", "struct CreateHabitSheet: View"),
            ("Cadence/macOS/Views/TimelineEventBlockSupportViews.swift", "struct CalendarEventEditPopover: View")
        ] {
            #expect(try CadenceCommitSurfaceScan.scanned(path).contains(marker), "\(path) did not read as itself")
        }

        let broken = """
        dismiss()
        do { try commit() } catch { notice = text; return }
        """
        let fixed = """
        do { try commit() } catch { notice = text; return }
        dismiss()
        """
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: broken))
        #expect(CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: fixed))
        #expect(
            !CadenceCommitSurfaceScan.reportFollowsTheCatch("dismiss()", in: "dismiss()"),
            "a body with no catch is not ordered"
        )

        let commented = "let a = 1 // note\n"
        let blanked = CadenceSourceScan.strippingComments(commented)
        #expect(blanked != commented, "the comment stripper removed nothing")
        #expect(blanked.count == commented.count, "the comment stripper changed the length")
        #expect(blanked.contains("let a = 1"), "the comment stripper blanked live code")

        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try? modelContext.save()") == 1)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try CadencePendingChangePersistence.commitInsert(of: t, in: c)") == 0)
        #expect(CadenceSourceScan.matchCount(#"inserted = (area|project)\b"#, in: "inserted = area\ninserted = project") == 2)
        #expect(CadenceSourceScan.matchCount(#"inserted = (area|project)\b"#, in: "inserted = areas") == 0)
    }
}
