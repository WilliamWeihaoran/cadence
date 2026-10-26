import Foundation
import Testing
@testable import Cadence

/// [[T-7006]]: the macOS "Order" pill is drawn only beside a sort field that a direction changes.
///
/// The Tasks page (Inbox and All Tasks) and a list's Tasks and Kanban tabs drew "Order: Ascending"
/// beside every sort field, including Custom -- the Inbox's default. Custom is the drag order, and
/// `TaskOrdering.sortKeyOrder` answers `.tie` for it in both directions, so flipping the pill
/// re-rendered the same list: a control that did nothing. The behaviour half below proves which
/// fields a direction really changes, so `honorsDirection` cannot drift from the comparator; the
/// source half proves every Order pill asks it.
@MainActor
struct CadenceSortOrderPillTests {

    /// The rule, read off the comparator rather than restated: a field honours a direction exactly
    /// when reversing the direction reorders a fixture whose keys all differ.
    @Test func honorsDirectionIsTrueExactlyWhenTheDirectionReordersTasks() {
        let tasks = distinctKeyTasks()
        for field in TaskSortField.allCases {
            let ascending = tasks.taskSorted(by: field, direction: .ascending).map(\.title)
            let descending = tasks.taskSorted(by: field, direction: .descending).map(\.title)
            #expect(
                field.honorsDirection == (ascending != descending),
                "\(field.rawValue): honorsDirection says \(field.honorsDirection), the comparator says \(ascending != descending)"
            )
        }
        #expect(!TaskSortField.custom.honorsDirection, "Custom grew a direction pill again")
        #expect(TaskSortField.date.honorsDirection && TaskSortField.priority.honorsDirection)
    }

    /// Every macOS Order pill sits inside an `honorsDirection` gate. Counted per file so a new
    /// ungated pill, or a gate deleted from one of the three, is caught.
    @Test func everyOrderPillIsGatedOnTheSortField() throws {
        let expected: [(path: String, gate: String, pills: Int)] = [
            ("Cadence/macOS/Views/macOSRootSupportViews.swift", "if sortField.wrappedValue.honorsDirection {", 1),
            ("Cadence/macOS/Views/ListDetailView.swift", "if taskSortField.honorsDirection {", 1),
            ("Cadence/macOS/Views/ListDetailView.swift", "if kanbanSortField.honorsDirection {", 1),
        ]
        for entry in expected {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(entry.path))
            let pill = "CadenceEnumPickerBadge(title: \"Order\""
            guard let gate = source.range(of: entry.gate) else {
                Issue.record("\(entry.path) lost its \(entry.gate) gate")
                continue
            }
            // The pill is the first statement inside the gate.
            let after = source[gate.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(after.hasPrefix(pill), "\(entry.path): the pill under \(entry.gate) moved out of it")
        }

        // No Order pill anywhere in the Mac tree outside those three gates.
        var total = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/macOS") {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            total += source.components(separatedBy: "CadenceEnumPickerBadge(title: \"Order\"").count - 1
        }
        #expect(total == expected.count, "found \(total) Order pills; every one needs an honorsDirection gate")
    }

    private func distinctKeyTasks() -> [AppTask] {
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let rows: [(String, String, TaskPriority)] = [
            ("a", "2026-10-01", .high),
            ("b", "2026-10-02", .medium),
            ("c", "2026-10-03", .low),
        ]
        return rows.enumerated().map { index, row in
            let task = AppTask(title: row.0)
            task.scheduledDate = row.1
            task.priority = row.2
            task.order = index
            task.createdAt = base.addingTimeInterval(Double(index))
            return task
        }
    }
}
