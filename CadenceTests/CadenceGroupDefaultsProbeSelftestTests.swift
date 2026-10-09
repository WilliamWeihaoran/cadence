import Testing

/// T-1176. `scripts/group-defaults-probe.sh`'s own checks, run inside this target.
///
/// **A separate file rather than a test appended to `CadenceGuardScriptSelftestTests`**, which is
/// where every other script selftest is run from and is where this belongs: that file was being
/// edited by a sibling agent in the shared checkout while this landed, and `agent-commit.sh` stages
/// WHOLE files (T-1385), so adding four lines to it would have committed whatever half-finished
/// state the sibling happened to be in. Fold it back in when the file is free; nothing here depends
/// on being its own suite, and it reuses `CadenceSelftestRun` unchanged.
///
/// **Why the reading itself is a script and not a test.** What T-1176 asks to be measured is the
/// owner's real app-group suite at
/// `~/Library/Group Containers/group.com.haoranwei.Cadence/Library/Preferences/`, and no test in
/// this target may read a path outside its own temporary directory. So the measurement is a command
/// a person runs with the owner's knowledge, and what this target can hold — all it can hold — is
/// the proof that the command reads correctly, taken against throwaway plists under `$TMPDIR`.
struct CadenceGroupDefaultsProbeSelftestTests {

    /// The three verdicts of `scripts/group-defaults-probe.sh`, its one refusal, and the two
    /// non-claims it must keep printing.
    ///
    /// The verdicts are the easy half. The other names are what keep this instrument from quietly
    /// becoming a weaker one:
    ///
    /// - `REFUSING-TO-WRITE` is the probe declining to put its own record inside a group container,
    ///   a `Cadence Store Backups` folder or the Recovery store. A probe that writes what it
    ///   measures is not a probe, and the owner's real data is what is on the other side of it.
    /// - `NOT AN ATTRIBUTION` is on every verdict. `MOVED` says this file differs between two
    ///   readings and nothing more: cfprefsd, the owner's own `Cadence.app` and an agent's launched
    ///   build all write this suite, and the file records none of them. T-1176 asks what an *agent
    ///   launch* writes, and no comparison of two file states answers that on its own.
    /// - `ATTRIBUTION WITHHELD` is that non-claim made concrete. A sample taken while the owner's
    ///   copy was up — or while whether it was up could not be read — cannot be the measurement,
    ///   and says so in the verdict instead of passing for one.
    static let groupDefaultsProbeVerdicts = [
        "group-defaults: UNMOVED",
        "group-defaults: MOVED",
        "group-defaults: NO-SAMPLE",
        "REFUSING-TO-WRITE",
        "NOT AN ATTRIBUTION",
        "ATTRIBUTION WITHHELD",
        "FLOAT32-TRUNCATION",
        "owner-app=unknown",
        "CREATED",
    ]

    /// Runs entirely against throwaway XML plists under `$TMPDIR`, and must stay that way.
    ///
    /// Two of the checks it requires are controls rather than assertions, and they are the ones
    /// worth knowing about.
    ///
    /// **§2 is the cfprefsd trap.** Two byte-identical fixtures whose mtimes are thirty years apart
    /// must compare `UNMOVED`, and the same pair with one value changed and *identical* mtimes must
    /// compare `MOVED`. Measured twice on the real file — 2026-10-06 and again 2026-10-09 — its
    /// mtime moves while its 135 bytes and its sha256 do not, because cfprefsd rewrites it without
    /// changing its content. A verdict taken off mtimes passes neither direction here.
    ///
    /// **§4 is `FLOAT32-TRUNCATION`.** `PlistBuddy -c Print` renders that file's
    /// `cadence.widgets.lastReloadAt` as `1791260160.000000` where `plutil -p` renders the same
    /// bytes as `1791260184.86859`: PlistBuddy prints the stored double through a single-precision
    /// float, 24.87 seconds early — so T-1176's own recorded baseline figure is 25 seconds early,
    /// and a small write to that key would be invisible to it. The fixture's value is one no
    /// float32 can reproduce, so swapping the reader back reddens here rather than in six months'
    /// prose.
    ///
    /// **§6 is both directions of `REFUSING-TO-WRITE`, and it is here because the one-directional
    /// form was already wrong once.** The probe refuses to write its record into the owner's data,
    /// and the first spelling of that refusal named `com.haoranwei.Cadence/Data` whole — which is
    /// correct everywhere except the place this test runs, since the App-Sandboxed host's own
    /// `$TMPDIR` is `~/Library/Containers/com.haoranwei.Cadence/Data/tmp/`. It refused the
    /// selftest's workspace and failed 9 of its own checks (measured 2026-10-09) while appearing to
    /// protect something. So §6 now requires a record in the container's `Library` to be refused
    /// *and* one in the same container's `tmp` to be written: a guard that refuses everything
    /// protects nothing, and only the second half can tell the two apart.
    ///
    /// `owner-app=unknown` is pinned beside the verdicts for the T-1152 reason: inside this host
    /// `pgrep` runs but is denied the process list and exits 3, and reading that as "the owner's app
    /// was not running" is exactly the sentence that would let a worthless sample pass for the
    /// measurement.
    @Test func theGroupDefaultsProbesOwnChecksStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/group-defaults-probe.sh")
        let complaints = run.complaints(requiring: Self.groupDefaultsProbeVerdicts)
        #expect(complaints.isEmpty, "./scripts/group-defaults-probe.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }
}
