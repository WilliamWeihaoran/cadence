#if os(macOS)
import SwiftUI

enum TaskSurfaceFreezeCoordinator {
    static func capture<PrimarySnapshot, SecondarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        secondarySnapshot: inout [SecondarySnapshot]?,
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot],
        sourceSecondarySnapshot: [SecondarySnapshot]
    ) {
        if frozenOrder == nil {
            frozenOrder = naturalTasks
        }
        if primarySnapshot == nil && !sourcePrimarySnapshot.isEmpty {
            primarySnapshot = sourcePrimarySnapshot
        }
        if secondarySnapshot == nil && !sourceSecondarySnapshot.isEmpty {
            secondarySnapshot = sourceSecondarySnapshot
        }
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
