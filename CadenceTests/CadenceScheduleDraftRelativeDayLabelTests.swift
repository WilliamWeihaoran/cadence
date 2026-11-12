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
}
