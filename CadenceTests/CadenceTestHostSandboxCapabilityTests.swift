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

        // T-1152 keys its repair on BOTH halves of this failure, so both are pinned rather than
        // left in prose. pgrep's documented statuses are 0 matched / 1 no match / 2 bad options /
        // 3 fatal error, and what the lock now depends on is that this is a 3 and NOT a 1: exit 1
        // with no output is the ordinary idle box and has to keep counting as a genuine zero.
        #expect(run.status == 3,
                "pgrep exited \(String(describing: run.status)) here, not 3 — and live_test_hosts reads >= 2 as \"cannot tell\", so a 1 would read as a real zero again")
        #expect(!run.output.isEmpty,
                "pgrep exited non-zero and said nothing, which is indistinguishable from an idle box on the second signal live_test_hosts reads")

        // In-process, the same wall by the same mechanism: no process list, EPERM.
        let sized = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        #expect(sized <= 0, "proc_listpids returned \(sized), so an in-host process sweep is possible now")
    }

    /// The repair itself, end to end, in the only place the failure it fixes can actually occur
    /// (T-1152). Everything else about it is argued from the measurements above; this runs the
    /// real `scripts/test-host-lock.sh`, in this real sandbox, and reads what it says out loud.
    ///
    /// Before the fix that line read `live test hosts: 0` from in here — the same three characters
    /// an idle developer machine prints, and the value the reclaim branch defers to before
    /// removing another agent's lock. `pgrep` is not refused (above), it answers nothing, so
    /// nothing anywhere in the script could tell the two apart.
    ///
    /// `status` is the safe subcommand to prove it with: it takes nothing and frees nothing. The
    /// lock it inspects is `${TMPDIR}cadence-macos-test-host.lock`, which in here resolves inside
    /// this host's own container — never the `/var/folders` lock sibling agents hold while this
    /// runs. And `zsh <script>` rather than the script directly, the workaround this file's own
    /// `itCannotExecAFileItWroteItself` explains.
    @Test func theTestHostLockKnowsItCannotSeeProcessesFromInHere() throws {
        let script = Self.repositoryRoot.appendingPathComponent("scripts/test-host-lock.sh").path
        let run = Self.spawn("/bin/zsh", ["-f", script, "status"])
        #expect(run.status == 0, "test-host-lock.sh status did not run here: \(run.output)")
        #expect(run.output.contains("live test hosts: unknown"),
                "the lock still reports a NUMBER of live test hosts from inside a host that cannot read the process list (T-1152): \(run.output)")
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

    /// **T-1151, and the honest attempt that ticket asked for: which step actually stops it.**
    ///
    /// `.github/workflows/ci.yml` justified keeping `scripts/real-tree-sweep-manifest.sh selftest`
    /// out of this target by saying the host *"cannot spawn `xcodebuild`, ps or pgrep at all"*.
    /// All three thirds are falsified by the cases above: Xcode's own `xcodebuild` exits 0
    /// (`theXcrunShimsRefuseButTheRealToolsSpawn`), `pgrep` spawns and runs and is merely denied
    /// the process list (`pgrepRunsHereAndReportsNoProcessesAtAll`), and only a setuid binary is
    /// refused at `posix_spawn` (`itRefusesToExecASetuidBinaryAndOnlyThose`). "The sandbox" is not
    /// a reason; a mechanism is, and the mechanism is the **write policy**.
    ///
    /// Walk that `selftest` mode in order, from in here:
    ///
    /// 1. read `CadenceTests/CadenceRealTreeSweepManifest.txt` out of the checkout — **works**;
    /// 2. `cp` it to a backup under `$TMPDIR`, which in here is this host's own container —
    ///    **works**, and so does the `sed -i ''` the next step is spelled with, against that copy;
    /// 3. `sed -i '' "<n>d"` the manifest **in the checkout** — the step that lays down the
    ///    deliberately stale tree the whole trial regenerates from — **refused**. `sed -i ''`
    ///    rewrites in place by laying a temporary beside the file and renaming it over, so it
    ///    needs the manifest's *directory* to be writable, and nothing in the checkout is.
    ///
    /// Steps 1 and 2 are measured here too, and not for symmetry. Without them a refusal at step 3
    /// is indistinguishable from a host on which nothing works at all — which is exactly the
    /// over-generalisation T-959 found and T-1153 made a rule about.
    ///
    /// The probe never touches the manifest. If this host's write policy ever changes, this test
    /// must go red leaving a stray dotfile in `CadenceTests/`, never a hole in the manifest — and
    /// the last expectation re-reads the committed bytes to say so.
    ///
    /// **There is a second objection and it is not a sandbox one**, so nothing here settles it:
    /// step 4 is `xcb.sh <id> test`, a real build, spawned from inside a test host that is already
    /// holding the FIFO test-host lock. That argument is about cost and re-entrancy and survives
    /// whatever the write policy does.
    @Test func theSweepManifestSelftestIsStoppedByTheWritePolicyAndNotBySomethingVaguer() throws {
        let directory = Self.repositoryRoot.appendingPathComponent("CadenceTests")
        let manifest = directory.appendingPathComponent("CadenceRealTreeSweepManifest.txt")

        // Step 1: the read the selftest opens with.
        let committed = try Data(contentsOf: manifest)
        #expect(!committed.isEmpty,
                "the manifest read as empty from in here, so step 1 is what fails and this test is aimed at the wrong step")

        // Step 2: the backup, and the in-place edit it is restored by — both against a file in
        // this host's own container, where both are allowed.
        let scratch = try Self.scratchDirectory("sweep-selftest")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let backup = scratch.appendingPathComponent("manifest-backup.txt")
        let copied = Self.spawn("/bin/zsh", ["-f", "-c", "cp '\(manifest.path)' '\(backup.path)'"])
        #expect(copied.status == 0,
                "the selftest's own `cp` of the manifest into $TMPDIR was refused: \(copied.output)")
        let inContainer = Self.spawn("/bin/zsh", ["-f", "-c", "sed -i '' '1d' '\(backup.path)'"])
        #expect(inContainer.status == 0,
                "`sed -i ''` cannot edit a file in this host's own container either, so step 3's refusal would not be about the checkout: \(inContainer.output)")
        #expect(try Data(contentsOf: backup).count < committed.count,
                "`sed -i ''` exited 0 against the container copy and removed nothing, so it proves nothing about step 3")

        // Step 3: the same edit, in the checkout. Probed by the file `sed -i ''` would have to
        // create — never the manifest, which must stay byte-identical whatever this measures.
        let probe = directory.appendingPathComponent(".cadence-sweep-selftest-write-probe")
        defer { try? FileManager.default.removeItem(at: probe) }
        let beside = Self.spawn("/bin/zsh", ["-f", "-c", "print x > '\(probe.path)'"])
        #expect(beside.status != 0,
                "the directory holding the sweep manifest is writable from in here, so T-1151's replacement reason has expired and the exclusion needs deciding again: \(beside.output)")
        #expect(!FileManager.default.fileExists(atPath: probe.path),
                "the shell reported a refusal and the file is there anyway")
        #expect(throws: (any Error).self) {
            try Data("x".utf8).write(to: probe, options: .atomic)
        }
        #expect(Self.spawn("/bin/zsh", ["-f", "-c", "head -1 '\(manifest.path)'"]).status == 0,
                "…while READING the manifest from the same directory must keep working, or this measured the checkout being gone")

        #expect(try Data(contentsOf: manifest) == committed,
                "this test changed the committed manifest, which it must never be able to do")
    }
}
