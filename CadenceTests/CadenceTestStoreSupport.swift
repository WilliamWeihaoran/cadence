import Foundation
import SwiftData
@testable import Cadence

/// The one way a test in this target builds a store.
///
/// **Why it is a shared helper and not thirteen copies (T-560).** Thirteen suites each declared
/// their own `makeContainer()`, and all thirteen spelled the configuration
/// `ModelConfiguration(isStoredInMemoryOnly: true)` — leaving `cloudKitDatabase` at its default.
/// The two in-memory configurations in the *shipped* app do not: `PersistenceController`'s
/// in-memory recovery fallback and `CadenceModelContainerFactory.makeInMemoryContainer()` both
/// pass `cloudKitDatabase: .none`. So the test target was the only place in the repository that
/// attached a CloudKit mirroring delegate to a throwaway store.
///
/// That is wrong on its own terms before any leak is argued: a mirroring delegate is network I/O
/// and cross-process nondeterminism inside a unit test that wants neither, and it is why a
/// `ModelContainer` built here reaches for the host app's real container directory at all.
///
/// It is also the only mechanism that fits T-560's residue. `<app container>/tmp/<UUID>/`
/// `inMemory_store_ckAssets` is the asset-staging directory CloudKit mirroring creates for a store
/// named `inMemory_store`; 3,652 of them had accumulated in the user's real container by
/// 2026-09-02, all empty, arriving in bursts whose sizes matched the test counts of the suites
/// being run. **Stated precisely because it was not reproduced on the day it was fixed:** two runs
/// covering 21 tests, 19 of which built and saved through an in-memory container in the old shape,
/// created zero directories. The residue is real and its shape is unambiguous; the gate that
/// decides whether mirroring initialises on a given run is not established. See T-704.
///
/// The invariant — every in-memory store in the repository disables mirroring — is enforced by
/// `CadenceInMemoryStoreHygieneTests`, so a fourteenth suite cannot reintroduce the old spelling.
enum CadenceTestStore {

    /// An empty in-memory container over the app's real schema, with CloudKit mirroring off.
    static func container() throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
