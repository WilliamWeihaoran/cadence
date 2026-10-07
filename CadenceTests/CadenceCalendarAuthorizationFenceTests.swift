import Foundation
import Testing

/// **T-3032 — the one flag that stands between a call and the owner's real Calendar, pinned so it
/// cannot quietly become settable again.**
///
/// `CalendarManager.isAuthorized` is the only guard on all six of that type's EventKit write paths:
/// `createStandaloneEvent`, both `updateEvent` overloads, `updateEventNotes`,
/// `convertAllDayEventToTimed` and `deleteEvent` each open with
/// `guard isAuthorized else { return record(.notAuthorized) }`, and nothing else stands between the
/// call and `store.save` / `store.remove`. Those writes land outside Cadence and are not undoable
/// from inside it.
///
/// It was a plain `var`, so anything in the module could mint that permission —
/// `CalendarManagerScenarioTests` did, on `shared`, which owns a real `EKEventStore`, and was safe
/// only because each such test then handed EventKit an event built from a throwaway store. The call
/// those tests happened not to make resolves `store.defaultCalendarForNewEvents` and writes for
/// real. `RemindersManager` had spelled the same flag `private(set)` all along.
///
/// **What enforces what.** The compiler is the real fence: with `private(set)`, every assignment
/// from outside the type is an error, so no test can be written that forges authorization. These
/// scans exist for the mutation the compiler is blind to — *deleting* `private(set)`, which
/// compiles cleanly and silently reopens the hole with every existing test still green. So the
/// first assertion is the declaration itself, the second is the regression shape that used to be in
/// the tree, and the third pins that the replacement seam is absent from a release build.
///
/// Scope, so a green run is not over-read: this says nothing about *when* Cadence may write to the
/// owner's calendar. That is [[T-3031]] and it is an open owner decision. `iOSCalendarManager`'s own
/// `isAuthorized` is still a plain `var` and is deliberately not covered here — it is a different
/// file behind `#if os(iOS)`, which a macOS build does not compile.
struct CadenceCalendarAuthorizationFenceTests {

    private static let managerPath = "Cadence/macOS/Services/CalendarManager.swift"

    // MARK: - 1. The declaration

    /// The mutation this file exists for. Removing `private(set)` from the declaration compiles,
    /// changes no behaviour a test can observe, and restores the forgeable flag — so the assertion
    /// has to be on the spelling.
    @Test func theCalendarManagerAuthorizationFlagIsDeclaredPrivateSet() throws {
        let code = try CadenceCommitSurfaceScan.scanned(Self.managerPath)

        let declarations = CadenceSourceScan.matchLines(
            #"(?:private\(set\)[ \t]+)?var[ \t]+isAuthorized\b"#,
            in: code
        )

        // Non-vacuity, three ways: the reader found the declaration at all, it found exactly one
        // (two would mean the assertion below is only ever about whichever came first), and the
        // file it read still holds the six write guards the whole argument rests on. A scan whose
        // needle rotted scores zero on all three rather than passing quietly.
        #expect(declarations.count == 1, "expected one `var isAuthorized` declaration in \(Self.managerPath), found \(declarations.count)")
        let guardCount = CadenceSourceScan.matchCount(
            #"guard isAuthorized else \{ return record\("#,
            in: code
        )
        #expect(guardCount >= 6, "expected at least six authorization-guarded write paths, found \(guardCount)")

        let declaration = try #require(declarations.first)
        #expect(
            declaration.matched.contains("private(set)"),
            """
            \(Self.managerPath):\(declaration.line + 1) declares `isAuthorized` without `private(set)`, \
            so anything in the module can forge the only guard on all six EventKit write paths and \
            reach the owner's real Calendar. Found: \(declaration.matched.trimmingCharacters(in: .whitespaces))
            """
        )
    }

    // MARK: - 2. The regression shape

    /// Belt and braces over the compiler: no file in the tree assigns the flag through a binding
    /// that holds a `CalendarManager`. This is the exact shape that was in
    /// `CalendarManagerScenarioTests` before T-3032, and it is what a reader would write again.
    @Test func nothingOutsideTheManagerAssignsCalendarManagersAuthorizationFlag() throws {
        var scannedFiles = 0
        var filesBindingAManager: [String] = []
        var offenders: [String] = []

        for directory in ["Cadence", "CadenceTests", "CadenceUITests"] {
            for path in try CadenceSourceScan.swiftFiles(under: directory) {
                guard let raw = try? CadenceSourceScan.sourceFile(path) else { continue }
                scannedFiles += 1
                guard raw.contains("CalendarManager") else { continue }
                let code = CadenceSourceScan.strippingComments(raw)

                var receivers: Set<String> = ["CalendarManager.shared"]
                for pattern in Self.bindingPatterns {
                    for name in CadenceSourceScan.captures(pattern, in: code).map(\.text) {
                        receivers.insert(name)
                    }
                }
                if receivers.count > 1 { filesBindingAManager.append(path) }

                for receiver in receivers {
                    let needle = "\(NSRegularExpression.escapedPattern(for: receiver))\\.isAuthorized[ \t]*=[^=]"
                    for hit in CadenceSourceScan.matchLines(needle, in: code) {
                        offenders.append("\(path):\(hit.line + 1)")
                    }
                }
            }
        }

        // Non-vacuity: the sweep read a whole tree, and the binding reader really does find the
        // receivers it is supposed to look through — including the suite that used to hold the
        // offence. Without this floor a regex that stopped matching would report a clean tree.
        #expect(scannedFiles > 300, "the sweep read \(scannedFiles) Swift files, which is not this repository")
        #expect(filesBindingAManager.count >= 5, "the binding reader found CalendarManager receivers in only \(filesBindingAManager.count) files")
        #expect(
            filesBindingAManager.contains("CadenceTests/CalendarManagerScenarioTests.swift"),
            "the binding reader no longer sees the suite that used to force the flag; found \(filesBindingAManager.sorted())"
        )

        #expect(
            offenders.isEmpty,
            """
            \(offenders.sorted().joined(separator: ", ")) assigns `isAuthorized` on a CalendarManager. \
            That flag is the only guard on six EventKit write paths; seed authorization through \
            `CalendarManager.init(testStore:authorizedForTesting:)` over a store the caller owns instead.
            """
        )
    }

    // MARK: - 3. The seam is absent from a release build

    /// The replacement seam may not weaken the product. `init(testStore:authorizedForTesting:)`
    /// must sit inside `#if DEBUG` — structural, not a comment asking people to behave — and its
    /// store parameter must have no default, so a caller cannot reach the singleton's real store by
    /// omission.
    @Test func theAuthorizationSeedingSeamIsDebugOnlyAndRequiresItsOwnStore() throws {
        let code = try CadenceCommitSurfaceScan.scanned(Self.managerPath)
        let lines = code.components(separatedBy: "\n")

        let seams = lines.enumerated().filter { $0.element.contains("init(testStore:") }
        #expect(seams.count == 1, "expected one authorization-seeding seam, found \(seams.count)")
        let seam = try #require(seams.first)

        // Walk upwards for the nearest `#if`/`#endif`: the seam is fenced only if the nearest one
        // above it is `#if DEBUG` and has not already been closed.
        var fence: String?
        var index = seam.offset - 1
        while index >= 0 {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#endif") || line.hasPrefix("#if") {
                fence = line
                break
            }
            index -= 1
        }
        #expect(
            fence == "#if DEBUG",
            """
            \(Self.managerPath):\(seam.offset + 1) — the authorization-seeding initializer is not \
            inside `#if DEBUG` (nearest directive above it: \(fence ?? "none")), so a release build \
            exposes a way to construct an authorized CalendarManager from outside the type.
            """
        )

        #expect(
            CadenceSourceScan.matchCount(#"init\(testStore: EKEventStore, authorizedForTesting: Bool\)"#, in: code) == 1,
            "the seam's signature changed; `testStore` must stay required and undefaulted so a caller cannot inherit the singleton's store"
        )
    }

    private static let bindingPatterns = [
        // `let manager = CalendarManager.shared` / `= CalendarManager(` / `= makeManager(`
        #"(?:let|var)[ \t]+(\w+)[ \t]*(?::[ \t]*CalendarManager[ \t]*)?=[ \t]*(?:CalendarManager[.(]|makeManager\()"#,
        // `calendarManager: CalendarManager` — a parameter or an annotated property.
        #"(\w+)[ \t]*:[ \t]*CalendarManager\b"#,
        // `@Environment(CalendarManager.self) private var calendarManager`
        #"@Environment\(CalendarManager\.self\)[^\n]*\bvar[ \t]+(\w+)"#,
    ]
}
