import Darwin
import Foundation
import Testing

/// What `CadenceTests`' App-Sandboxed host can and cannot do (T-959), measured rather than
/// described — because the prose version of this has been generalised twice, and both
/// generalisations were wrong in ways that changed decisions.
///
/// The claim on record was *"cannot spawn `ps` or `pgrep` at all — EPERM at `posix_spawn`"*, later
/// generalised in `scripts/mutate.sh` to *"ps/pgrep are not special cases; an unrecognised exec
/// target is"*. Measured 2026-09-12 on macOS 26.6 / Xcode 26.6, neither holds:
///
/// * `/usr/bin/pgrep` **spawns and runs**. It exits 3 saying *"sysmond service not found /
///   pgrep: Cannot get process list"* — it is denied the process list, not the exec. That is a
///   worse failure than a refusal, not a milder one: `test-host-lock.sh`'s `live_test_hosts`
///   pipes it into `wc -l` and gets a perfectly plausible **0**.
/// * `/bin/ps` really is EPERM at spawn, and so is `/usr/bin/top` — because both are **setuid
///   root** (`4755`, `4555`). `pgrep`, `zsh` and `ls` are `755` and all spawn. The rule is the
///   setuid bit, not the identity of the tool.
/// * "An unrecognised exec target" is not the rule either: `scripts/xcb.sh`, exec'd **directly**
///   from here, runs and prints its usage. What cannot be exec'd is a file **this process wrote**
///   — including a byte-for-byte, non-setuid copy of `/bin/ls`.
///
/// The practical conclusions the old reading supported still stand; their *reasons* did not. This
/// suite pins the reasons, so the next OS that changes one says so here instead of somewhere a
/// ticket gets written about it.
@Suite(.serialized)
struct CadenceTestHostSandboxCapabilityTests {
    struct Outcome {
        /// nil means `posix_spawn` itself refused — `Process.run()` threw before a byte of output.
        let status: Int32?
        let output: String
        var spawned: Bool { status != nil }
    }

    static func spawn(_ tool: String, _ arguments: [String]) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Outcome(
                status: process.terminationStatus,
                output: String(decoding: o, as: UTF8.self) + String(decoding: e, as: UTF8.self)
            )
        } catch {
            return Outcome(status: nil, output: "\(error)")
        }
    }

    static func isSetuidOrSetgid(_ path: String) -> Bool {
        let mode = ((try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions]
            as? NSNumber)?.uint16Value ?? 0
        return (mode & 0o4000) != 0 || (mode & 0o2000) != 0
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Its own container's `tmp`, which is the one directory it may write to. NOT the app's real
    /// store: nothing here goes near `Data/Library/Application Support`.
    static func scratchDirectory(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-sandbox-\(name)-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - What it CAN do

    /// The half [[T-986]] already had right and the broad reading obscured: this host spawns
    /// ordinary, non-setuid tools freely, at any depth, and that is how
    /// `CadenceGuardScriptSelftestTests` runs six of this repository's guard scripts' selftests.
    @Test func itSpawnsOrdinaryToolsAndScriptsHandedToAShell() throws {
        // Arguments chosen so nothing can sit waiting on stdin if a spawn unexpectedly succeeds.
        let harmless: [(String, [String])] = [
            ("/bin/echo", ["ok"]), ("/bin/ls", ["/"]), ("/usr/bin/env", ["true"]),
            ("/bin/sh", ["-c", "exit 0"]), ("/bin/zsh", ["-f", "-c", "exit 0"]),
        ]
        for (tool, args) in harmless {
            #expect(Self.spawn(tool, args).spawned, "\(tool) could not be spawned at all")
        }
        let deep = Self.spawn("/bin/zsh", ["-f", "-c", "/bin/zsh -f -c '/bin/zsh -f -c \"echo ok\"'"])
        #expect(deep.status == 0 && deep.output.contains("ok"),
                "a zsh three levels down: \(deep.output)")

        // A script that was already on disk, handed to zsh — the shape every guard selftest uses.
        let script = Self.repositoryRoot.appendingPathComponent("scripts/xcb.sh").path
        let handed = Self.spawn("/bin/zsh", ["-f", script])
        #expect(handed.spawned && handed.output.contains("usage:"), "zsh <script>: \(handed.output)")

        // …and the same script exec'd DIRECTLY, which also works. `mutate.sh`'s comment blames "an
        // unrecognised exec target"; this is the counterexample to that reading.
        let direct = Self.spawn(script, [])
        #expect(direct.spawned && direct.output.contains("usage:"),
                "the repository's own script, exec'd directly: \(direct.output)")
    }

    /// `xcodebuild` at Xcode's own path runs here, exit 0. `.github/workflows/ci.yml` says this
    /// host "cannot spawn `xcodebuild`, ps or pgrep at all"; only `ps` is true. What refuses is
    /// the `/usr/bin` **xcrun shim** — `git`, `python3` and `/usr/bin/xcodebuild` all spawn fine
    /// and then print *"xcrun: error: cannot be used within an App Sandbox."*, which is a
    /// different failure with a different fix (T-1151).
    @Test func theXcrunShimsRefuseButTheRealToolsSpawn() throws {
        let real = Self.spawn("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", ["-version"])
        #expect(real.status == 0 && real.output.contains("Xcode"),
                "Xcode's own xcodebuild: \(real.output)")
        for shim in ["/usr/bin/git", "/usr/bin/python3", "/usr/bin/xcodebuild"] {
            let run = Self.spawn(shim, ["--version"])
            #expect(run.spawned, "\(shim) was refused at spawn, which is not what was measured")
            #expect(run.output.contains("cannot be used within an App Sandbox"),
                    "\(shim) said: \(run.output)")
        }
    }

    // MARK: - What it CANNOT do, and why

    /// The correction that matters most. A setuid binary cannot be exec'd — that is the rule, and
    /// `/bin/ps` is only its most-quoted instance. `pgrep` is NOT setuid and is NOT refused.
    @Test func itRefusesToExecASetuidBinaryAndOnlyThose() throws {
        for (tool, args) in [("/bin/ps", ["-p", "1"]), ("/usr/bin/top", ["-l", "1", "-n", "0"])] {
            #expect(Self.isSetuidOrSetgid(tool), "\(tool) is no longer setuid, so this probe moved")
            #expect(!Self.spawn(tool, args).spawned, "\(tool) spawned, so the setuid rule has changed")
        }
        for (tool, args) in [("/usr/bin/pgrep", ["-f", "nothing-matches-this"]),
                             ("/bin/zsh", ["-f", "-c", "exit 0"]), ("/bin/ls", ["/"])] {
            #expect(!Self.isSetuidOrSetgid(tool), "\(tool) became setuid, so this probe moved")
            #expect(Self.spawn(tool, args).spawned, "\(tool) was refused at spawn")
        }
    }

    /// `pgrep` spawns, runs, and answers **nothing** — so a caller that counts its lines reads a
    /// plausible zero. This is precisely `test-host-lock.sh`'s `live_test_hosts`, and it is why
    /// `no-reclaim` is TOLERATED in `CadenceGuardScriptSelftestTests` for a reason the ticket did
    /// not state: not "the call is refused", but "the call answers zero" (T-1152).
    @Test func pgrepRunsHereAndReportsNoProcessesAtAll() throws {
        let run = Self.spawn("/usr/bin/pgrep", ["-f", "xcodebuild"])
        #expect(run.spawned, "pgrep was refused at spawn; T-959's original reading would be right")
        #expect(run.status != 0, "pgrep succeeded here, so the process list is readable again")
        #expect(run.output.contains("Cannot get process list") || run.output.isEmpty,
                "pgrep said something new: \(run.output)")

        // In-process, the same wall by the same mechanism: no process list, EPERM.
        let sized = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        #expect(sized <= 0, "proc_listpids returned \(sized), so an in-host process sweep is possible now")
    }

    /// A file this process wrote cannot be exec'd, even with 0755 and even when it is a
    /// byte-for-byte copy of a binary that execs fine from its own path. Handing the same path to
    /// `/bin/zsh` works, which is the workaround `simulator-claim.sh selftest` already uses.
    @Test func itCannotExecAFileItWroteItself() throws {
        let dir = try Self.scratchDirectory("exec")
        defer { try? FileManager.default.removeItem(at: dir) }

        let script = dir.appendingPathComponent("fresh.sh")
        try "#!/bin/zsh\nprint fresh-ok\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        #expect(!Self.spawn(script.path, []).spawned, "a freshly written script exec'd directly")
        let handed = Self.spawn("/bin/zsh", ["-f", script.path])
        #expect(handed.status == 0 && handed.output.contains("fresh-ok"),
                "…but zsh must still be able to run it: \(handed.output)")

        // Not a property of being a script, and not of being unsigned-and-new either: a plain copy
        // of /bin/ls, 0755, no setuid bit, is refused the same way.
        let copy = dir.appendingPathComponent("ls-copy")
        try FileManager.default.copyItem(atPath: "/bin/ls", toPath: copy.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copy.path)
        #expect(!Self.isSetuidOrSetgid(copy.path))
        #expect(!Self.spawn(copy.path, ["/"]).spawned, "a copy of /bin/ls this process wrote exec'd")
    }

    /// Writes land in its own container and nowhere else — not `/tmp`, and **not the checkout it
    /// is testing**, which is what stops any in-host instrument from building or repairing a tree.
    /// Reads of the checkout are fine. zsh here-documents need `TMPPREFIX` moved into `$TMPDIR`
    /// (T-782/T-719); unset, they fail with *"can't create temp file for here document"*.
    @Test func itWritesOnlyInsideItsOwnContainer() throws {
        let dir = try Self.scratchDirectory("write")
        defer { try? FileManager.default.removeItem(at: dir) }
        let mine = dir.appendingPathComponent("ok.txt")
        #expect(throws: Never.self) { try "x".write(to: mine, atomically: true, encoding: .utf8) }

        let denied = Self.spawn("/bin/zsh", ["-f", "-c", "print x > /tmp/cadence-probe-$$.txt"])
        #expect(denied.status != 0, "/tmp is writable again: \(denied.output)")

        let intoCheckout = Self.repositoryRoot.appendingPathComponent(".cadence-sandbox-probe").path
        let write = Self.spawn("/bin/zsh", ["-f", "-c", "print x > \(intoCheckout)"])
        #expect(write.status != 0, "the checkout under test is writable from here: \(write.output)")
        #expect(Self.spawn("/bin/zsh", ["-f", "-c", "ls \(Self.repositoryRoot.path)/scripts"]).status == 0,
                "…while reading it must keep working")

        let bare = Self.spawn("/bin/zsh", ["-f", "-c", "cat <<'EOF'\nhi\nEOF"])
        #expect(bare.status != 0, "a here-document works without TMPPREFIX now: \(bare.output)")
        let prefixed = Self.spawn("/bin/zsh", [
            "-f", "-c",
            "TMPPREFIX=\(FileManager.default.temporaryDirectory.path)/zsh; cat <<'EOF'\nhi\nEOF",
        ])
        #expect(prefixed.status == 0 && prefixed.output.contains("hi"),
                "…and must work with it: \(prefixed.output)")
    }
}
