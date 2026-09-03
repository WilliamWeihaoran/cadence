import Foundation

/// Recorded once, only when `PersistenceController.shared.container` is `nil`: the CloudKit
/// store, an on-disk recovery store, and a fully in-memory container all failed to open.
///
/// This is a different shape of problem from `CadenceStartupIssue`, deliberately not folded into
/// that enum. Every `CadenceStartupIssueKind` describes a **running** app whose store is degraded
/// — local-only, in-memory, a maintenance pass that did not save — and is drawn as a banner over
/// the normal root view. There is no normal root view here: no `ModelContainer` means no
/// `ModelContext`, no `@Query`, nothing any ordinary screen assumes exists. `CadenceApp` reads
/// this instead of building `macOSRootView`/`iOSRootView` at all, and shows
/// `CadenceTerminalRecoveryView` in their place.
struct CadenceStartupTerminalFailure: Equatable {
    /// What actually failed, in the order it was tried — CloudKit, then the on-disk recovery
    /// store, then a fully in-memory one. Technical, and shown only as a secondary detail;
    /// `CadenceTerminalRecoveryView` carries the plain-language explanation itself so that
    /// wording is not this type's job to get right.
    let message: String
}
