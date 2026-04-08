#if os(macOS)
import SwiftUI

enum TaskSurfaceFreezeOverloadSupport {
    static func captureSingleSnapshot<PrimarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot]
    ) {
        var secondarySnapshot: [Never]? = nil
        TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            secondarySnapshot: &secondarySnapshot,
            naturalTasks: naturalTasks,
            sourcePrimarySnapshot: sourcePrimarySnapshot,
            sourceSecondarySnapshot: []
        )
    }

    static func releaseSingleSnapshot<PrimarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?
    ) {
        var secondarySnapshot: [Never]? = nil
        TaskSurfaceFreezeCoordinator.release(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            secondarySnapshot: &secondarySnapshot
        )
    }
}
#endif
