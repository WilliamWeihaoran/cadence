import Foundation
import Testing
@testable import Cadence

/// **[[T-17081]]: the task inspector's Do and Due rows name the day the way the task's row does.**
///
/// The shared schedule panel is the task inspector on both platforms (the Mac inspector, the iOS
/// task sheet, the note embed's inline panel). Its collapsed Do and Due rows read
/// `DateFormatters.shortDateString` -- `Nov 12` -- for a task whose row, board card and capture
/// chip all say `Today`, and a project's own Due row has read the relative date since
/// [[T-10982]]. Opening a task the row calls "Tomorrow" showed `Nov 13` and made the reader do the
/// arithmetic. The rows now read `DateFormatters.relativeDate(from:withinDays:)` inside the capture
/// card's seven-day window ([[T-3237]]), so the card that wrote the day and the inspector that
/// reads it back use one rule.
@Suite("Schedule draft relative Do/Due labels")
@MainActor
struct CadenceScheduleDraftRelativeDayLabelTests {

    /// Noon, so no zone's midnight is anywhere near the reference.
    private let reference: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 12
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    private func key(_ offset: Int) -> String {
        DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: offset, to: reference)!)
    }

    private func taskDraft(doKey: String, dueKey: String) -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: doKey, startMin: 9 * 60, kind: .task)
        draft.dueDateKey = dueKey
        return draft
    }

    @Test("Today and tomorrow are named on the Do and Due rows, as the row names them")
    func nearDaysAreNamed() {
        let draft = taskDraft(doKey: key(0), dueKey: key(1))
        #expect(draft.doRowLabel(relativeTo: reference) == "Today")
        #expect(draft.dueRowLabel(relativeTo: reference) == "Tomorrow")
        #expect(taskDraft(doKey: key(-1), dueKey: key(3)).doRowLabel(relativeTo: reference) == "Yesterday")
        #expect(taskDraft(doKey: key(-1), dueKey: key(3)).dueRowLabel(relativeTo: reference) == "in 3 days")
    }

    @Test("Past the capture card's window the rows spell the date")
    func farDaysAreDated() {
        let window = CadenceCaptureFieldInventory.relativeDateCutoffDays
        let draft = taskDraft(doKey: key(window + 1), dueKey: key(-(window + 1)))
        #expect(draft.doRowLabel(relativeTo: reference)
            == DateFormatters.shortDateString(from: key(window + 1), relativeTo: reference))
        #expect(draft.dueRowLabel(relativeTo: reference)
            == DateFormatters.shortDateString(from: key(-(window + 1)), relativeTo: reference))
    }

    @Test("An unset Do or Due still reads its empty value")
    func unsetRowsKeepTheirEmptyValue() {
        var draft = taskDraft(doKey: key(0), dueKey: "")
        draft.clearDoDate()
        #expect(draft.doRowLabel(relativeTo: reference) == "No date")
        #expect(draft.dueRowLabel(relativeTo: reference) == "No due date")
    }

    /// The capture card's chips read the same labels, so the card that set the day and the
    /// inspector that reads it back cannot word one day two ways.
    @Test("The row label agrees with the capture card's chip rule inside the window")
    func rowLabelMatchesTheChipRule() {
        for offset in -7...7 {
            let draft = taskDraft(doKey: key(offset), dueKey: key(offset))
            let chip = DateFormatters.relativeDate(
                from: key(offset),
                relativeTo: reference,
                withinDays: CadenceCaptureFieldInventory.relativeDateCutoffDays
            )
            #expect(draft.doRowLabel(relativeTo: reference) == chip, "offset \(offset)")
            #expect(draft.dueRowLabel(relativeTo: reference) == chip, "offset \(offset)")
        }
    }

    /// **[[T-18092]]: the task's row and its inspector say the same words for its do date, at
    /// every distance.** The rows (Mac task chip, iOS task row, rollover offer, board card, note
    /// embed chip, Cmd+K, iOS search) read the window-less `relativeDate(from:relativeTo:)`, which
    /// went relative a fortnight forward and without limit backward, while this panel used the
    /// capture card's seven days -- so a task ten days out read "in 10 days" on its row and
    /// "Nov 22" here. The range runs well past both old turnovers (13 forward, unbounded back), and
    /// the two named offsets are the non-vacuity: they are dates now, and were words before.
    @Test("The task row's do-date words match the inspector's Do row at every distance")
    func taskRowAndInspectorAgreeAtEveryDistance() {
        for offset in -40...40 {
            let draft = taskDraft(doKey: key(offset), dueKey: key(offset))
            let task = AppTask(title: "Distance \(offset)")
            task.scheduledDate = key(offset)
            let row = CadenceTaskPresentationSupport.scheduledDayLabel(for: task, override: nil, realNow: reference)
            #expect(row == draft.doRowLabel(relativeTo: reference), "offset \(offset)")
            #expect(DateFormatters.relativeDate(from: key(offset), relativeTo: reference) == row, "offset \(offset)")
        }
        for offset in [10, -30] {
            let task = AppTask(title: "Named \(offset)")
            task.scheduledDate = key(offset)
            #expect(CadenceTaskPresentationSupport.scheduledDayLabel(for: task, override: nil, realNow: reference)
                == DateFormatters.shortDateString(from: key(offset), relativeTo: reference), "offset \(offset)")
        }
    }
}
