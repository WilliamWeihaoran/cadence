#if os(macOS)
import SwiftUI

enum TaskSurfaceFreezeCoordinator {
    /// Returns `true` only when something was actually captured. Callers write the result back
    /// into SwiftUI `@State` bindings, and a binding write always invalidates the owning view
    /// whether or not the value changed — so an unconditional write-back rebuilt the whole task
    /// surface every time the pointer crossed a row boundary while already frozen.
    @discardableResult
    static func capture<PrimarySnapshot, SecondarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        secondarySnapshot: inout [SecondarySnapshot]?,
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot],
        sourceSecondarySnapshot: [SecondarySnapshot]
    ) -> Bool {
        var didCapture = false
        if frozenOrder == nil {
            frozenOrder = naturalTasks
            didCapture = true
        }
        if primarySnapshot == nil && !sourcePrimarySnapshot.isEmpty {
            primarySnapshot = sourcePrimarySnapshot
            didCapture = true
        }
        if secondarySnapshot == nil && !sourceSecondarySnapshot.isEmpty {
            secondarySnapshot = sourceSecondarySnapshot
            didCapture = true
        }
        return didCapture
    }

    static func release<PrimarySnapshot, SecondarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        secondarySnapshot: inout [SecondarySnapshot]?
    ) {
        frozenOrder = nil
        primarySnapshot = nil
        secondarySnapshot = nil
    }
}
#endif
