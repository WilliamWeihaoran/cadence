import Foundation
import Testing
@testable import Cadence

/// **The seam that makes "this resolver answers the app-group store" assertable on a host that
/// cannot reach one — [[T-1850]].**
///
/// `CadenceStoreSupport.sharedStoreDirectoryURL` does two things that can fail, and only the second
/// one is what CI hits. It asks `containerURL(forSecurityApplicationGroupIdentifier:)`, throwing
/// `CocoaError(.fileNoSuchFile)` when that answers `nil` — and then it **creates** the store
/// directory under whatever it did answer. On a hosted GitHub runner the lookup does *not* answer
/// `nil`: it hands back `/Users/runner/Library/Group Containers/group.com.haoranwei.Cadence`, the
/// conventional path, because macOS derives that from the identifier rather than from an
/// entitlement. The `createDirectory` under it is what is refused, and the refusal measured in the
/// `test-log` artifact of run `36759839618` is:
///
/// ```
/// Error Domain=NSCocoaErrorDomain Code=513 "You don't have permission to save the file "Cadence"…"
///   NSFilePath=/Users/runner/Library/Group Containers/group.com.haoranwei.Cadence/Library/Application Support/Cadence
///   NSUnderlyingError={Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"}
/// ```
///
/// `.github/ci.entitlements` grants only `com.apple.security.get-task-allow`, deliberately — a
/// hosted runner has no signing identity and no provisioning profile, so the shipping entitlements
/// cannot be used there and an app group cannot be granted. Four consecutive tickets — [[T-1448]],
/// [[T-1530]], [[T-1532]], [[T-1680]] — each shipped an assertion spelled
/// `resolver == try primaryStoreDirectoryURL()`, each passed on the owner's Mac, and all five of
/// them went red together the first time CI ran them: the `try` threw before any assertion was
/// reached. The tests were host-dependent, and the host they were written on was the only one that
/// could run them.
///
/// The property those tickets are about is **not** "the resolver returns a path". It is *"the
/// resolver agrees with `CadenceStoreSupport`"* — and where `CadenceStoreSupport` refuses, the
/// resolver must refuse in the same way. That reading holds on every host, so nothing here is
/// skipped, gated on a hostname, or wrapped in a known issue.
///
/// A *floor* is one reading of "what does this process's app-group lookup do", and the resolvers
/// under test all take a `fileManager:` precisely so a test can choose. There are four, and every
/// floor-driven assertion runs on all four on every host:
///
/// - `.thisHost` — the real `FileManager`. A directory on a Mac with the container, a refusal on a
///   runner without it. This is the reading CI takes and the only one that was ever exercised
///   before T-1850.
/// - `.standIn` — an injected container under the test's own temporary directory, which can be
///   created. It **always** resolves, so the exact-path claim ("unset resolves to the app-group
///   store, precisely") is asserted on every host, including one that has no usable app group.
///   This is what keeps the suite non-vacuous on CI rather than merely green there.
/// - `.unwritableContainer` — an injected container that is **answered and cannot be created**,
///   refusing with the `NSCocoaErrorDomain` 513 / `NSPOSIXErrorDomain` 1 pair quoted above. This is
///   CI's floor, reproduced exactly, and it runs here on a machine that does have a container
///   instead of being reasoned about.
/// - `.noContainer` — an injected `nil`, the other refusal `sharedStoreDirectoryURL` can produce.
///   Not what CI takes, and kept because it is the branch the function's own `else` is written for.
///
/// The stand-in floor is why this is stronger than what it replaces and not weaker: before T-1850
/// the exact-path half was asserted on one host and unreachable on the other; now it is asserted on
/// both, and the refusing half is asserted on both too.
enum CadenceAppGroupFloorKind: String, CaseIterable, Sendable {
    /// The real `FileManager`: whatever this host's app-group lookup does.
    case thisHost
    /// An injected, creatable container under the test's own temporary directory. Always resolves.
    case standIn
    /// An injected container that is answered and cannot be created. Always refuses, the way a
    /// hosted runner does.
    case unwritableContainer
    /// An injected `nil`. Always refuses, through the other branch.
    case noContainer
}

/// What `CadenceStoreSupport.primaryStoreDirectoryURL` — or a resolver claiming to agree with it —
/// answered. A refusal is a **result** here, never an absence: comparing two of these is what makes
/// "they agree" mean something on a host where both refuse.
///
/// The refusal carries `domain` and `code` rather than the error itself so two refusals can be
/// compared. That is a relation between two readings taken in the same run, not a pinned figure.
enum CadenceAppGroupStoreOutcome: Equatable, CustomStringConvertible {
    /// A directory, by standardized path.
    case directory(String)
    /// A refusal, by error domain and code.
    case refused(domain: String, code: Int)

    init(_ resolve: () throws -> URL) {
        do {
            self = .directory(try resolve().standardizedFileURL.path)
        } catch {
            let nsError = error as NSError
            self = .refused(domain: nsError.domain, code: nsError.code)
        }
    }

    /// The directory, when there is one. `nil` is "this floor has no reachable app group", never
    /// "this assertion did not matter".
    var url: URL? {
        guard case .directory(let path) = self else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Whether this is a refusal at all — the reading that decides which half of a floor-driven
    /// assertion applies, and the only thing in this file that varies by host.
    var isRefusal: Bool { url == nil }

    /// The same outcome one path component further down — for the callers whose reference is a
    /// child of the store directory (`Recovery`, `Cadence Store Backups`). A refusal stays a
    /// refusal: there is no child of a directory that does not exist.
    func appending(_ component: String) -> CadenceAppGroupStoreOutcome {
        guard case .directory(let path) = self else { return self }
        return .directory(
            URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent(component, isDirectory: true)
                .standardizedFileURL
                .path
        )
    }

    var description: String {
        switch self {
        case .directory(let path):
            return path
        case .refused(let domain, let code):
            return "refused(\(domain) \(code))"
        }
    }
}

/// A `FileManager` whose app-group lookup answers what the test says, and which refuses to create
/// anything under that answer when the test says that too.
///
/// Both halves are needed because both halves of `sharedStoreDirectoryURL` can fail, and the one CI
/// takes is the second: the lookup succeeds and the `createDirectory` under it is denied. A stub
/// that only returned `nil` would model the branch this repository's CI has never reached.
///
/// `nonisolated` for the reason `InterruptingFileManager` in `CadenceStoreRestoreTests` is: under
/// this target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` an isolated subclass cannot override
/// `FileManager`'s nonisolated members.
nonisolated final class CadenceAppGroupContainerStub: FileManager {
    private let container: URL?
    private let containerIsWritable: Bool

    /// - Parameters:
    ///   - container: the directory this stub reports for Cadence's app group, or `nil` to report
    ///     none at all.
    ///   - isWritable: `false` makes every `createDirectory` at or under `container` fail with the
    ///     `NSCocoaErrorDomain` 513 over `NSPOSIXErrorDomain` 1 pair a hosted runner produces.
    ///     Paths outside the container are unaffected, so a test's own fixtures still work.
    init(container: URL?, isWritable: Bool = true) {
        self.container = container
        self.containerIsWritable = isWritable
        super.init()
    }

    override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        guard groupIdentifier == CadenceStoreSupport.appGroupIdentifier else {
            return super.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        }
        return container
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if !containerIsWritable,
           let container,
           url.standardizedFileURL.path.hasPrefix(container.standardizedFileURL.path) {
            throw CocoaError(
                .fileWriteNoPermission,
                userInfo: [
                    NSFilePathErrorKey: url.path,
                    NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
                ]
            )
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}

/// One floor, with the reference reading already taken.
///
/// The reference is resolved once at construction rather than on each access: resolving it *creates*
/// the store directory, and for `.thisHost` on a Mac with a container that directory is the owner's
/// real one. Taking the reading once is the same single `createDirectory(withIntermediateDirectories:)`
/// against an already-existing path that these tests have always made, and nothing here ever writes
/// below it.
struct CadenceAppGroupFloor {
    let kind: CadenceAppGroupFloorKind
    let fileManager: FileManager
    /// What `CadenceStoreSupport` itself answers on this floor. The thing every resolver under test
    /// has to agree with.
    let reference: CadenceAppGroupStoreOutcome

    var name: String { kind.rawValue }

    /// All four floors. `root` must be the test's own temporary directory: the injected containers
    /// are placed inside it, never beside the value under test and never under the real container.
    static func all(in root: URL) -> [CadenceAppGroupFloor] {
        CadenceAppGroupFloorKind.allCases.map { kind in
            let fileManager: FileManager
            switch kind {
            case .thisHost:
                fileManager = .default
            case .standIn:
                fileManager = CadenceAppGroupContainerStub(
                    container: root.appendingPathComponent("StandInGroupContainer", isDirectory: true)
                )
            case .unwritableContainer:
                fileManager = CadenceAppGroupContainerStub(
                    container: root.appendingPathComponent("UnwritableGroupContainer", isDirectory: true),
                    isWritable: false
                )
            case .noContainer:
                fileManager = CadenceAppGroupContainerStub(container: nil)
            }
            return CadenceAppGroupFloor(
                kind: kind,
                fileManager: fileManager,
                reference: CadenceAppGroupStoreOutcome {
                    try CadenceStoreSupport.primaryStoreDirectoryURL(fileManager: fileManager)
                }
            )
        }
    }

    /// The floors whose app group resolves, for the assertions that need a *real other directory*
    /// rather than an expectation. Never empty — `.standIn` is always in it — so a loop over this
    /// cannot quietly become a loop over nothing on a host with no usable container.
    static func resolvable(in root: URL) -> [CadenceAppGroupFloor] {
        all(in: root).filter { !$0.reference.isRefusal }
    }
}

/// **The assertion this whole file exists for: the resolver agrees with `CadenceStoreSupport`.**
///
/// Both sides are taken on the *same* floor and compared as outcomes, so:
///
/// - where the app group resolves, this is the old exact-path claim, unweakened — a resolver that
///   answered any other directory, or that threw, is red;
/// - where it does not, this is "refuses identically" — a resolver that invented a path, fell back
///   to `Application Support`, or threw a different error is red.
///
/// What it is **not** is `try?` on both sides: `.refused` is a value, so two refusals are only equal
/// when they are the same refusal, and a refusal never equals a directory.
func expectResolvesLikeTheAppGroupStore(
    _ resolve: (FileManager) throws -> URL,
    on floor: CadenceAppGroupFloor,
    _ reason: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let actual = CadenceAppGroupStoreOutcome { try resolve(floor.fileManager) }
    #expect(
        actual == floor.reference,
        "[\(floor.name)] \(reason): resolved \(actual), CadenceStoreSupport resolved \(floor.reference)",
        sourceLocation: sourceLocation
    )
}

/// The other direction: the resolver must **not** answer the app-group store.
///
/// A redirected launch resolving a private directory is "not the app group" on a host that has one
/// *and* on a host that does not — on the latter the reference is a refusal, and a directory is
/// never equal to a refusal, which is the honest reading rather than a vacuous one: the claim
/// "this launch is not writing into the owner's store" is exactly as true when the owner's store is
/// unreachable.
func expectDiffersFromTheAppGroupStore(
    _ url: URL,
    on floor: CadenceAppGroupFloor,
    _ reason: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let actual = CadenceAppGroupStoreOutcome.directory(url.standardizedFileURL.path)
    #expect(
        actual != floor.reference,
        "[\(floor.name)] \(reason): resolved \(actual), which is the app-group store",
        sourceLocation: sourceLocation
    )
}

/// **The floors themselves, asserted — because a harness that silently stopped producing the sharp
/// floor would make every test above it green for the wrong reason.**
///
/// This is the "counted and visible" half. The gate on the exact-path assertions is the *container's
/// unreachability* and never a hostname, and the count is fixed at build time rather than discovered
/// at run time: of the four floors, exactly one always resolves by construction, exactly two always
/// refuse by construction, and `.thisHost` is whichever of the two this machine is.
@MainActor
struct CadenceAppGroupFloorSupportTests {

    /// A temporary root of this test's own. Nothing here is ever planted under a value being tested.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1850-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func theFourFloorsAreTheFourReadingsTheyClaimToBe() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let floors = CadenceAppGroupFloor.all(in: root)
        #expect(floors.count == CadenceAppGroupFloorKind.allCases.count)
        let byKind = Dictionary(uniqueKeysWithValues: floors.map { ($0.kind, $0) })

        // The stand-in always resolves, and resolves *inside this test's own directory* — that is
        // what lets the exact-path claim be made on a host whose app group is unreachable, and what
        // keeps it away from the owner's real container.
        let standIn = try #require(byKind[.standIn]?.reference.url)
        #expect(
            standIn.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path),
            "the stand-in container escaped the test's own directory: \(standIn.path)"
        )
        #expect(
            standIn.lastPathComponent == CadenceStoreSupport.storeDirectoryName,
            "the stand-in did not resolve through CadenceStoreSupport's own layout"
        )

        // The unwritable floor is **CI's**, reproduced: the lookup answers a path and the
        // `createDirectory` under it is denied. Asserted as the domain/code pair taken from
        // `CocoaError` in the same expression, not as a pinned literal.
        #expect(
            byKind[.unwritableContainer]?.reference == .refused(
                domain: CocoaError.errorDomain,
                code: CocoaError.Code.fileWriteNoPermission.rawValue
            ),
            "the unwritable floor answered \(byKind[.unwritableContainer]?.reference.description ?? "nothing")"
        )
        // ...and it is a *different* refusal from the nil-container one, or the floor would be
        // modelling the branch CI does not take.
        #expect(
            byKind[.unwritableContainer]?.reference != byKind[.noContainer]?.reference,
            "the two refusing floors collapsed into one reading"
        )

        // The nil-container floor: the other branch `sharedStoreDirectoryURL` writes an `else` for.
        #expect(
            byKind[.noContainer]?.reference == .refused(
                domain: CocoaError.errorDomain,
                code: CocoaError.Code.fileNoSuchFile.rawValue
            ),
            "the no-container floor answered \(byKind[.noContainer]?.reference.description ?? "nothing")"
        )

        // `.thisHost` is a directory or one of those two refusals and nothing else. Which one it is
        // *is* the CI/local split, and it is the only thing in this file that varies by host.
        let thisHost = try #require(byKind[.thisHost]?.reference)
        switch thisHost {
        case .directory:
            // A Mac whose app-group container exists and can be written: the reading four tickets
            // shipped against, and the only one any of them could ever take.
            #expect(thisHost != byKind[.standIn]?.reference, "the real container is the stand-in")
        case .refused(let domain, let code):
            // A hosted runner. Measured on run 36759839618: NSCocoaErrorDomain 513 over
            // NSPOSIXErrorDomain 1, from the `createDirectory`, not from a nil container.
            #expect(
                domain == CocoaError.errorDomain
                    && (code == CocoaError.Code.fileWriteNoPermission.rawValue
                        || code == CocoaError.Code.fileNoSuchFile.rawValue),
                "this host refused with \(domain) \(code), which is neither app-group refusal"
            )
        }

        // At least one floor resolves on every host, so no loop over `resolvable` is ever empty.
        #expect(!CadenceAppGroupFloor.resolvable(in: root).isEmpty)
    }

    /// The two helpers do what they say on a refusing floor, which is the case no host could
    /// previously exhibit and the one the fix rests on.
    @Test func agreementAndDifferenceAreBothDecidableWithoutAReachableContainer() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let refusing = try #require(
            CadenceAppGroupFloor.all(in: root).first { $0.kind == .unwritableContainer }
        )

        // A resolver that forwards to CadenceStoreSupport agrees, refusal and all.
        let forwarded = CadenceAppGroupStoreOutcome {
            try CadenceStoreSupport.primaryStoreDirectoryURL(fileManager: refusing.fileManager)
        }
        #expect(forwarded == refusing.reference)

        // A resolver that invented a path does **not** agree — this is the assertion that would be
        // thrown away by `try?` on both sides, and it is the whole reason the outcome is a value.
        let invented = CadenceAppGroupStoreOutcome { root.appendingPathComponent("Invented") }
        #expect(invented != refusing.reference)

        // Nor does one that refused differently. A resolver that swallowed the permission error and
        // rethrew "no such file" would be reporting the wrong cause, and this is what says so.
        let wrongRefusal = CadenceAppGroupStoreOutcome { throw CocoaError(.fileNoSuchFile) }
        #expect(wrongRefusal != refusing.reference)

        // ...and a directory is never the app-group store on a floor that cannot reach one.
        #expect(
            CadenceAppGroupStoreOutcome.directory(root.standardizedFileURL.path) != refusing.reference
        )
    }

    /// **The stub is a stub of the right thing**: it denies exactly what the runner denies and
    /// nothing else, so a fixture a test plants in its own directory still works while the app group
    /// is unreachable. Without this, the unwritable floor could be passing tests for the wrong
    /// reason — every write failing rather than only the container's.
    @Test func theUnwritableStubDeniesTheContainerAndNothingElse() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let container = root.appendingPathComponent("UnwritableGroupContainer", isDirectory: true)
        let stub = CadenceAppGroupContainerStub(container: container, isWritable: false)

        #expect(throws: CocoaError.self) {
            try stub.createDirectory(
                at: container.appendingPathComponent("Library/Application Support", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        #expect(
            !FileManager.default.fileExists(atPath: container.path),
            "the denied create left something behind"
        )

        // A path outside the container is an ordinary create, which is what keeps this stub usable
        // as the `fileManager:` of a resolver that also writes its own redirected directory.
        let elsewhere = root.appendingPathComponent("Fixture", isDirectory: true)
        try stub.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }
}
