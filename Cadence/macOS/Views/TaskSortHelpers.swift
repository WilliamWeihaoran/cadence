#if os(macOS)
import Foundation

// The comparator itself moved to `Cadence/Models/TaskOrdering.swift`.
//
// It had to: `Models/` is compiled by the app, `CadenceWidgets`, *and* `CadenceMCPServer`, while
// this file was `#if os(macOS)` inside `macOS/Views/`. So the app's canonical task ordering was
// the one place two of the three targets that order tasks could not call — which is how the
// Today widget ended up with its own priority-then-`order` sort and the MCP read service with a
// third. `TaskSortField` / `TaskSortDirection` moved with it.
//
// What survives here is the free-function spelling the macOS call sites read better with.

/// Free-function spelling of `TaskPriority.rank`.
func taskPriorityRank(_ priority: TaskPriority) -> Int { priority.rank }

/// Free-function spelling of `TaskOrdering.precedes(_:_:field:direction:)`.
func taskSortPrecedes(_ lhs: AppTask, _ rhs: AppTask, field: TaskSortField, direction: TaskSortDirection) -> Bool {
    TaskOrdering.precedes(lhs, rhs, field: field, direction: direction)
}

// `taskSorted(by:direction:)` is on `Array where Element == AppTask` in `TaskOrdering.swift`;
// every existing call site keeps working unchanged.

// Date bucketing deliberately does *not* live here. `TaskDateBuckets` / `classifyTasksByDate`
// used to sit below this line as a line-for-line twin of `CadenceTaskQuerySupport.dateBuckets`,
// with zero production callers — so the only test of the bucketing rule tested the copy nothing
// ran. Use `CadenceTaskQuerySupport.dateBuckets(for:todayKey:)` and `CadenceTaskDateBuckets`.
#endif
