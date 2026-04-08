#if os(macOS)
import SwiftUI

enum TaskSurfaceFreezeSupport {
    static let releaseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    static func captureIfNeeded<PrimarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot]
    ) {
        TaskSurfaceFreezeOverloadSupport.captureSingleSnapshot(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            naturalTasks: naturalTasks,
            sourcePrimarySnapshot: sourcePrimarySnapshot
        )
    }

    static func captureIfNeeded<PrimarySnapshot, SecondarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        secondarySnapshot: inout [SecondarySnapshot]?,
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot],
        sourceSecondarySnapshot: [SecondarySnapshot]
    ) {
        TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            secondarySnapshot: &secondarySnapshot,
            naturalTasks: naturalTasks,
            sourcePrimarySnapshot: sourcePrimarySnapshot,
            sourceSecondarySnapshot: sourceSecondarySnapshot
        )
    }

    static func releaseIfPossible<PrimarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?
    ) {
        TaskSurfaceFreezeOverloadSupport.releaseSingleSnapshot(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot
        )
    }

    static func releaseIfPossible<PrimarySnapshot, SecondarySnapshot>(
        frozenOrder: inout [AppTask]?,
        primarySnapshot: inout [PrimarySnapshot]?,
        secondarySnapshot: inout [SecondarySnapshot]?
    ) {
        TaskSurfaceFreezeCoordinator.release(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            secondarySnapshot: &secondarySnapshot
        )
    }
}

#endif
