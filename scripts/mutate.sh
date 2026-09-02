#!/bin/zsh
# A mutation-test runner that cannot report a survivor it did not earn (T-530).
#
#   ./scripts/mutate.sh <id> <plan-file> [options]     # run a mutation plan
#   ./scripts/mutate.sh selftest                       # prove the guards still fire
#
# WHY THIS EXISTS
#
# "Mutate the source, re-run the suite, and if it still passes your test is blind" is only sound
# while every step that can fail says so. Four times in one session a hand-written runner reported
# a SURVIVOR it had not earned, and each time the shape was the same: something upstream failed
# quietly and a green run over nothing read as a green run over a mutation.
#
#   1. STALE NEEDLE (T-530, the original). The `old` text no longer occurs -- a rename, a reflow --
#      so the edit never lands. The suite passes because the tree is unmodified. Indistinguishable
#      from a survivor unless the runner checks that the file actually changed.
#   2. A SELF-CHECK THAT PASSES WHEN IT SHOULD FAIL. The post-write check was `old in text`, i.e.
#      "the needle is gone". When the replacement CONTAINS its own anchor -- `return x` becoming
#      `return x + 1` -- the needle is still there after a perfectly successful apply, so the
#      runner declared failure, SKIPPED THE RESTORE, and ran the next mutation on a doubly-mutated
#      tree. A substring test cannot answer "did this file change"; only a byte comparison against
#      the backup can. That is why every check here is `==` against bytes, never `in`.
#   3. AN AMBIGUOUS NEEDLE. The `old` text also occurs in a comment or a second case arm, so the
#      apply either aborts or silently mutates two places. Two mutations "survived" for no reason.
#   4. A MUTATION THAT NEVER COMPILED, or a run that crashed the test host. A non-compiling
#      mutation is not a survivor -- nothing was tested. And a crashed host emits NO
#      `.swift:line:col: error:` lines at all, so the strict error count reads zero and the run
#      looks like a clean green over nothing.
#   5. A SURVIVAL THAT ARGUES NOTHING. Loosening `#expect(count == 3)` to `>= 1` survives in any
#      tree where the count really is 3 -- both spellings pass, so the mutation changes nothing a
#      passing tree can observe. That is INCONCLUSIVE, not a hole in the suite. It is settled by
#      mutating in PAIRS: one mutation introduces the violation the tight form exists to catch
#      (it must be KILLED), and its partner introduces the same violation PLUS the loosening (it
#      survives, and that survival is the evidence). This runner will not print SURVIVED over an
#      unpaired weakening.
#
# So a verdict of SURVIVED is issued only when all of these are true, each measured rather than
# assumed: the needle occurred exactly as many times as the plan said; the file's bytes differ
# from the backup afterwards and equal the expected replacement; the file's bytes matched the
# baseline BEFORE the edit (so no earlier mutation is stranded in it); the build produced zero
# compile errors and no toolchain crash; a non-zero number of test results was actually printed;
# the suite named in the plan appears in the log as something that ran; and the run exited 0.
# Anything else is INVALID -- reported by name, never rounded to "survived".
#
# A verdict of KILLED additionally requires at least one failing test line, and reports the failing
# tests BY NAME, because "the run went red" is not the same claim as "my test caught it".
#
# ISOLATION IS THE DEFAULT, NOT THE DISCIPLINE
#
# A runner that mutates the working tree can strand a mutation in the user's repository: `SIGKILL`
# does not run traps and `SIGTERM` cannot be trusted to finish one, so neither signal is a restore.
# With no `--tree`, this runner builds its own `git archive HEAD | tar -x` tree under
# /private/tmp/cadence-mut-<id>/ and mutates THAT, where a stranded mutation dies with the scratch
# directory. Mutating the repository working tree requires `--in-place` and says so loudly.
#
# OPTIONS
#   --tree DIR       mutate this already-prepared tree (e.g. your own archive tree, with your
#                    uncommitted tests in it) instead of a fresh archive of HEAD
#   --in-place       allow the repository working tree as the target. Say it out loud or it is refused.
#   --no-lock        do not take the test-host lock (only if the caller already holds it)
#   --no-build       apply and restore each mutation, run nothing. For dry-running a plan.
#   --scheme NAME    default: Cadence
#   --destination D  default: platform=macOS
#   --keep-tree      do not delete the scratch tree on the way out
#
# THE PLAN FILE
#
#   # comments outside a block start with #
#   mutation: M1
#   file: Cadence/Models/ModelEnums.swift      # repository-relative
#   suite: HabitFrequencyLabelTests            # a SUITE name; -only-testing: takes nothing else
#   tests: theFullLabelIsUnchanged             # optional, comma-separated; asserted to have run
#   count: 1                                   # optional; expected occurrences of `old`, default 1
#   expect: killed                             # optional; killed|survived|inconclusive
#   weakens: yes                               # optional; this mutation only loosens an assertion
#   pair: M5                                   # optional; the companion mutation that must be KILLED
#   note: what this mutation is arguing about
#   --- old
#   case .daily:        return "Daily"
#   --- new
#   case .daily:        return "Every Day"
#   --- end
#
# `weakens:` is inferred for any mutation of a file under CadenceTests/ -- mutating a test is
# almost always weakening one -- so the pairing rule applies whether or not you remember it. Say
# `weakens: no` on a test-file mutation that genuinely tightens or breaks something instead.
#
# The text between the markers is taken literally, byte for byte, with no trailing newline. It is
# NOT a regex and NOT a patch: `patch` fuzzes, and it leaves `.orig` files, which this repository's
# synchronised file group then tries to compile.
#
# RUN IT IN THE BACKGROUND. A plan of any size outlives the 10-minute foreground tool cap, and a
# runner cut off mid-mutation is the hazard this whole script is about. `nohup ./scripts/mutate.sh
# ... > log 2>&1 &`, then poll the log. The runner writes its pid to <scratch>/runner.pid; kill
# THAT, not a `pkill -f` pattern, and never with -9.
set -uo pipefail
ROOT_DIR="${0:A:h:h}"
# exec, so the pid you see IS the python process: a signal sent to this script has to reach the
# handler that restores the tree, and a zsh parent waiting on a child does not forward it.
exec /usr/bin/python3 - "$ROOT_DIR" "$@" <<'PY'
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = sys.argv[1]
ARGV = sys.argv[2:]

# The same evidence scripts/xcb.sh counts: swift-testing's per-test lines and XCTest's, in both the
# serial (`Test Case`) and parallel (`Test case`) spellings. The `Executed N tests` summary is
# deliberately not the signal -- a run that died before reaching a test never prints it at all.
TEST_RESULT = re.compile(r"(?:✔|✘) Test [A-Za-z0-9_]+\(\)|Test [Cc]ase .*(?:passed|failed)")
FAILED_SWIFT_TESTING = re.compile(r"✘ Test ([A-Za-z0-9_]+)\(\)")
FAILED_XCTEST = re.compile(r"Test [Cc]ase '-\[[^ ]+ ([A-Za-z0-9_]+)\]' failed")
COMPILE_ERROR = re.compile(r"\.swift:[0-9]+:[0-9]+: error:")
# Strict, for the same reason the error count is (AGENTS.md): a loose `warning:` count picks up
# `appintentsmetadataprocessor ... warning: Metadata extraction skipped`, which every clean build of
# this project prints, and reports a zero-warning baseline as a regression.
COMPILE_WARNING = re.compile(r"\.swift:[0-9]+:[0-9]+: warning:")

# Verdicts an agent may quote. Everything else is a refusal.
KILLED = "KILLED"
SURVIVED = "SURVIVED"
INCONCLUSIVE = "INCONCLUSIVE"


def say(*parts):
    print(*parts, flush=True)


def read_bytes(path):
    with open(path, "rb") as handle:
        return handle.read()


def write_bytes(path, data):
    with open(path, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


# --- the plan ----------------------------------------------------------------

class PlanError(Exception):
    pass


class Hunk:
    """One literal replacement in one file. A mutation may need more than one: the pairing rule
    (failure mode 5) asks for the loosened assertion AND the violation it should catch, applied
    together, and those are two edits in two different files."""

    def __init__(self, path, old, new, count=1):
        self.file = path
        self.old = old
        self.new = new
        self.count = count


class Mutation:
    def __init__(self, ident):
        self.ident = ident
        self.file = None        # the file subsequent hunks attach to, while parsing
        self.suite = None
        self.tests = []
        self.expect = None
        self.note = ""
        self.pair = None
        self.weakens = None     # None = infer from the files being mutated
        self.hunks = []

    @property
    def files(self):
        seen = []
        for hunk in self.hunks:
            if hunk.file not in seen:
                seen.append(hunk.file)
        return seen

    @property
    def weakening(self):
        """Whether a survival of this mutation could be inconclusive rather than a finding.

        Inferred rather than only declared: a mutation of a file under CadenceTests/ is a mutation
        of an assertion, and a loosened assertion survives in every tree that does not violate the
        tight form. Agents have been *told* to mutate weakened assertions in pairs; being told has
        already failed once, so the default is mechanical.
        """
        if self.weakens is not None:
            return self.weakens
        return any(f.startswith("CadenceTests/") for f in self.files)

    def validate(self):
        if not self.hunks:
            raise PlanError("mutation %s declares no --- old / --- new block" % self.ident)
        for hunk in self.hunks:
            if not hunk.file:
                raise PlanError("mutation %s has a hunk with no file:" % self.ident)
            if hunk.old == hunk.new:
                raise PlanError("mutation %s replaces text with itself; it can never be applied"
                                % self.ident)
        if self.expect not in (None, KILLED.lower(), SURVIVED.lower(), INCONCLUSIVE.lower()):
            raise PlanError("mutation %s: expect: takes killed, survived or inconclusive" % self.ident)
        if self.pair == self.ident:
            raise PlanError("mutation %s is paired with itself" % self.ident)


def parse_plan(text):
    """Literal blocks, scanned line by line.

    Deliberately not a regex over the whole document: the mutation bodies are arbitrary source,
    and a regex that pairs the wrong two markers produces a plausible-looking mutation nobody
    wrote. Same failure family as pairing quotes across a Swift interpolation.
    """
    mutations = []
    current = None
    mode = None       # None | "old" | "new"
    buffer = []
    old_text = None
    pending_count = 1

    for number, raw in enumerate(text.split("\n"), start=1):
        line = raw.rstrip("\r")
        stripped = line.strip()
        if mode is None and (stripped == "" or stripped.startswith("#")):
            continue
        if stripped in ("--- old", "--- new", "--- end"):
            if current is None:
                raise PlanError("line %d: %s before any `mutation:` header" % (number, stripped))
            if stripped == "--- old":
                if mode is not None:
                    raise PlanError("line %d: `--- old` inside another block" % number)
                mode, buffer = "old", []
                continue
            if stripped == "--- new":
                if mode != "old":
                    raise PlanError("line %d: `--- new` with no `--- old` above it" % number)
                old_text, mode, buffer = "\n".join(buffer), "new", []
                continue
            if mode != "new":
                raise PlanError("line %d: `--- end` with no `--- new` above it" % number)
            current.hunks.append(Hunk(current.file, old_text, "\n".join(buffer), pending_count))
            mode, buffer, old_text, pending_count = None, [], None, 1
            continue
        if mode is not None:
            buffer.append(line)
            continue
        if ":" not in stripped:
            raise PlanError("line %d: expected `key: value`, got %r" % (number, stripped))
        key, _, value = stripped.partition(":")
        key = key.strip().lower()
        value = value.strip()
        if key == "mutation":
            current = Mutation(value)
            pending_count = 1
            mutations.append(current)
            continue
        if current is None:
            raise PlanError("line %d: `%s:` before any `mutation:` header" % (number, key))
        if key == "file":
            current.file = value
        elif key == "suite":
            current.suite = value
        elif key == "tests":
            current.tests = [t.strip() for t in value.split(",") if t.strip()]
        elif key == "count":
            pending_count = int(value)
        elif key == "expect":
            current.expect = value.lower()
        elif key == "pair":
            current.pair = value
        elif key == "weakens":
            current.weakens = value.lower() in ("yes", "true", "1")
        elif key == "note":
            current.note = value
        else:
            raise PlanError("line %d: unknown key `%s:`" % (number, key))
    if mode is not None:
        raise PlanError("the plan ends inside a `--- %s` block" % mode)
    if not mutations:
        raise PlanError("the plan declares no mutations")
    for mutation in mutations:
        mutation.validate()
    return mutations


# --- the two things a substring test cannot answer ---------------------------

def occurrence_lines(text, needle):
    """Every line number at which `needle` starts, so an ambiguous needle can be reported as the
    specific ambiguity it is rather than as `2 != 1`."""
    lines = []
    start = 0
    while True:
        index = text.find(needle, start)
        if index < 0:
            return lines
        lines.append(text.count("\n", 0, index) + 1)
        start = index + 1


class Applied:
    def __init__(self, ok, reason="", detail=""):
        self.ok = ok
        self.reason = reason
        self.detail = detail


def apply_hunk(path, before, hunk):
    """One replacement, and the two questions a substring test cannot answer."""
    text = before.decode("utf-8")
    found = occurrence_lines(text, hunk.old)
    if not found:
        return Applied(False, "NEEDLE-ABSENT",
                       "the `old` text occurs 0 times in %s -- it went stale (a rename? a reflow?), "
                       "so nothing would have been mutated" % hunk.file)
    if len(found) != hunk.count:
        return Applied(False, "NEEDLE-AMBIGUOUS",
                       "the `old` text occurs %d times in %s (lines %s), and the plan says %d. "
                       "Anchor it on more context, or set `count:` if every occurrence is meant"
                       % (len(found), hunk.file, ", ".join(str(n) for n in found), hunk.count))
    expected = text.replace(hunk.old, hunk.new).encode("utf-8")
    write_bytes(path, expected)

    # The verification, and the only one that is sound. `old not in after` is NOT this test: a
    # replacement that contains its own anchor leaves the needle in place after a successful apply,
    # which is failure mode 2 -- the check that reports failure over a success and then skips the
    # restore.
    after = read_bytes(path)
    if after == before:
        return Applied(False, "NOT-APPLIED",
                       "%s is byte-identical to what it was before the write" % hunk.file)
    if after != expected:
        return Applied(False, "WRITE-MISMATCH",
                       "%s on disk is not the replacement text this runner computed" % hunk.file)
    return Applied(True)


def apply_mutation(tree, backups, baselines, mutation):
    """Apply every hunk, and answer whether the tree really changed -- by comparing bytes with the
    backups on disk, never by asking whether some substring is still present.

    Every failure below used to read as `the mutation survived`. All-or-nothing: a mutation whose
    third hunk goes stale must not leave its first two in the tree.
    """
    for name in mutation.files:
        path = os.path.join(tree, name)
        if read_bytes(path) != baselines[path]:
            return Applied(False, "NOT-PRISTINE",
                           "%s does not match its baseline before this mutation was applied; an "
                           "earlier mutation is stranded in it and every verdict after it is void"
                           % name)
    touched = []
    for hunk in mutation.hunks:
        path = os.path.join(tree, hunk.file)
        outcome = apply_hunk(path, read_bytes(path), hunk)
        if not outcome.ok:
            for done in touched:
                restore(done, backups[done], baselines[done])
            return outcome
        if path not in touched:
            touched.append(path)
    for path in touched:
        if read_bytes(path) == read_bytes(backups[path]):
            for done in touched:
                restore(done, backups[done], baselines[done])
            return Applied(False, "NOT-APPLIED",
                           "%s is byte-identical to its backup after every hunk was written"
                           % os.path.relpath(path, tree))
    return Applied(True)


def restore(path, backup_path, baseline):
    """Put the file back, and prove it. A restore nobody verified is how a mutation reaches the
    next run."""
    shutil.copyfile(backup_path, path)
    after = read_bytes(path)
    return after == baseline and after == read_bytes(backup_path)


def restore_mutation(tree, backups, baselines, mutation):
    ok = True
    for name in mutation.files:
        path = os.path.join(tree, name)
        ok = restore(path, backups[path], baselines[path]) and ok
    return ok


# --- reading a run ------------------------------------------------------------

class RunVerdict:
    def __init__(self, verdict, reason="", detail="", tests_ran=0, failed=(), warnings=0):
        self.verdict = verdict
        self.reason = reason
        self.detail = detail
        self.tests_ran = tests_ran
        self.failed = list(failed)
        self.warnings = warnings

    @property
    def earned(self):
        return self.verdict in (KILLED, SURVIVED)


def classify_run(exit_code, log, suite=None, tests=()):
    """Turn one run into a verdict, from the log text and the exit code together.

    Pure, and separately exercised by `selftest` against real log shapes, because this is where
    failure mode 4 lives: the two ways a build fails without printing an `error:` line.
    """
    lowered = log.lower()
    tests_ran = len(TEST_RESULT.findall(log))
    warnings = len(COMPILE_WARNING.findall(log))
    compile_errors = len(COMPILE_ERROR.findall(log))

    if "please submit a bug report" in lowered:
        return RunVerdict("INVALID", "TOOLCHAIN-CRASH",
                          "the compiler crashed. A crash prints no `.swift:line:col: error:` line, "
                          "so the strict error count reads 0 over a build that failed",
                          tests_ran, (), warnings)
    if compile_errors:
        return RunVerdict("INVALID", "DID-NOT-COMPILE",
                          "%d compile error(s). A mutation that does not build was never tested, so "
                          "it is not a survivor" % compile_errors,
                          tests_ran, (), warnings)
    if tests_ran == 0:
        return RunVerdict("INVALID", "NO-TESTS-RAN",
                          "the log carries 0 per-test result lines. A green run over zero tests is "
                          "character for character what a surviving mutation looks like (T-552): a "
                          "misspelled suite, a crashed host, or a build that failed silently",
                          0, (), warnings)
    if suite:
        # The suite name is on xcodebuild's own `Command line invocation` line whether or not
        # anything ran, so that line is dropped before looking for evidence.
        body = "\n".join(l for l in log.split("\n") if "-only-testing:" not in l)
        if suite not in body:
            return RunVerdict("INVALID", "SUITE-ABSENT",
                              "%d tests ran but none of them was in %s -- the run was scoped "
                              "somewhere else" % (tests_ran, suite),
                              tests_ran, (), warnings)
    failed = FAILED_SWIFT_TESTING.findall(log) + FAILED_XCTEST.findall(log)
    missing = [t for t in tests if ("Test %s()" % t) not in log and ("%s]" % t) not in log]
    if missing:
        return RunVerdict("INVALID", "TEST-ABSENT",
                          "the plan names %s, and no result line for %s appears in the log"
                          % (", ".join(tests), ", ".join(missing)),
                          tests_ran, failed, warnings)
    if exit_code == 0:
        if failed:
            return RunVerdict("INVALID", "GREEN-WITH-A-FAILING-TEST",
                              "exit 0, yet %s recorded an issue" % ", ".join(sorted(set(failed))),
                              tests_ran, failed, warnings)
        return RunVerdict(SURVIVED, "", "", tests_ran, (), warnings)
    if not failed:
        return RunVerdict("INVALID", "RED-WITHOUT-A-FAILING-TEST",
                          "exit %d with %d tests run and no test recorded an issue -- the run went "
                          "red for a reason other than your mutation" % (exit_code, tests_ran),
                          tests_ran, (), warnings)
    return RunVerdict(KILLED, "", "", tests_ran, failed, warnings)


def settle_weakenings(results):
    """Re-read every SURVIVED verdict that could be inconclusive, once the whole batch is in.

    Failure mode 5. Loosening `#expect(occurrences == 3)` to `>= 1` survives in any tree where the
    count really is 3: both spellings pass, so nothing a passing tree can observe has changed. Read
    as SURVIVED that looks like a hole in the suite, and it is not -- it is an experiment that had
    no control. The control is the paired mutation: the violation ALONE, which the tight form must
    kill. Only then does the loosened form's survival mean "the exact count is doing work".

    Runs after the loop rather than inside it, because a plan may name its partner in either order.
    """
    by_id = {row[0].ident: row for row in results}
    for row in results:
        mutation, verdict = row[0], row[1]
        if verdict != SURVIVED or not mutation.weakening:
            continue
        if not mutation.pair:
            row[1], row[2] = INCONCLUSIVE, "UNPAIRED-WEAKENING"
            row[3] = ("this mutation only loosens an assertion, and a loosened assertion cannot be "
                      "killed by a tree that does not violate the tight form -- so its survival "
                      "argues nothing either way. Add `pair: <id>` naming the mutation that "
                      "introduces the violation the tight form exists to catch; that one must be "
                      "KILLED for this survival to be evidence")
            continue
        partner = by_id.get(mutation.pair)
        if partner is None:
            row[1], row[2] = INCONCLUSIVE, "PAIR-MISSING"
            row[3] = "`pair: %s` names no mutation in this plan" % mutation.pair
        elif partner[1] != KILLED:
            row[1], row[2] = INCONCLUSIVE, "PAIR-NOT-KILLED"
            row[3] = ("%s was %s, not KILLED. The pair only settles anything when the violation "
                      "alone is caught by the tight form" % (partner[0].ident, partner[1]))
        else:
            row[3] = ("paired with %s, which %s killed. The same violation with the assertion "
                      "loosened survives -- so the exact form is what catches it"
                      % (partner[0].ident, ", ".join(sorted(set(partner[5])))))
    return results


# --- the tree ----------------------------------------------------------------

def prepare_tree(scratch, ident):
    """A `git archive HEAD | tar -x` copy: 910 files, and it IS HEAD, so there is no dirty-path
    restore step to forget. `rsync` would drag in 464 MB and every other agent's in-flight edits."""
    tree = os.path.join(scratch, "tree")
    os.makedirs(tree, exist_ok=True)
    archive = subprocess.Popen(["git", "archive", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE)
    extract = subprocess.Popen(["tar", "-x", "-C", tree], stdin=archive.stdout)
    archive.stdout.close()
    extract.communicate()
    if archive.wait() != 0 or extract.returncode != 0:
        raise SystemExit("could not build an isolated tree from `git archive HEAD`")
    return tree


def run_suite(tree, ident, mutation, scheme, destination, log_dir, tag):
    """One scoped run, through the tree's OWN scripts/xcb.sh.

    Its own, not the repository's: xcb.sh derives `-project` from its own location, so calling the
    repository copy would build the repository -- and every mutation would then be applied to one
    tree and tested against another, which is a survivor for every single mutation.

    `raw test` rather than `test`, because this runner already holds the test-host lock for the
    whole batch. `xcb.sh test` takes the lock itself, and wrapping it deadlocks against our own
    lease; `raw` keeps the zero-test guard and the counters and skips only the lock.
    """
    xcb = os.path.join(tree, "scripts", "xcb.sh")
    command = [xcb, ident, "raw", "test", "-scheme", scheme, "-destination", destination]
    if mutation.suite:
        command += ["-only-testing:CadenceTests/%s" % mutation.suite]
    started = time.time()
    finished = subprocess.run(command, cwd=tree, capture_output=True, text=True)
    stdout = finished.stdout + finished.stderr
    log_path = None
    for line in stdout.split("\n"):
        if line.strip().startswith("log:"):
            log_path = line.split(":", 1)[1].strip()
    log = ""
    if log_path and os.path.exists(log_path):
        with open(log_path, "r", errors="replace") as handle:
            log = handle.read()
        shutil.copyfile(log_path, os.path.join(log_dir, "%s.log" % tag))
    return finished.returncode, log + "\n" + stdout, time.time() - started


# --- the driver ---------------------------------------------------------------

class Runner:
    def __init__(self, ident, options):
        self.ident = ident
        self.options = options
        self.scratch = os.path.join("/private/tmp", "cadence-mut-%s" % ident)
        self.tree = None
        self.baselines = {}      # absolute path -> bytes at runner start
        self.backups = {}        # absolute path -> backup file
        self.live = []           # the files a mutation is currently applied to
        self.lock_id = "mut-%s" % ident
        self.lock_held = False

    # -- restore is the only thing that must happen no matter how we leave --
    def emergency_restore(self, why):
        if not self.live:
            return
        say("")
        say("!! %s -- restoring %d file(s) from backup before exiting." % (why, len(self.live)))
        for path in self.live:
            ok = restore(path, self.backups[path], self.baselines[path])
            say("   %s: %s" % (os.path.relpath(path, self.tree or "/"),
                               "restored" if ok else "NOT RESTORED -- THE MUTATION IS STILL IN THE TREE"))
        self.live = []

    def release_lock(self):
        if not self.lock_held:
            return
        subprocess.run([os.path.join(ROOT, "scripts", "test-host-lock.sh"), "release", self.lock_id])
        self.lock_held = False

    def on_signal(self, signum, _frame):
        # A handler that restores and then returns lets the runner carry on mutating, which is how
        # a tree ends up mutated by a runner you believe you stopped. End with an explicit exit.
        self.emergency_restore("signal %d" % signum)
        self.release_lock()
        sys.exit(128 + signum)


def main():
    if not ARGV or ARGV[0] in ("-h", "--help"):
        say("usage: ./scripts/mutate.sh <id> <plan-file> [--tree DIR] [--in-place] [--no-lock]")
        say("       ./scripts/mutate.sh selftest")
        return 2
    if ARGV[0] == "selftest":
        return selftest()
    if len(ARGV) < 2:
        say("usage: ./scripts/mutate.sh <id> <plan-file> [options]")
        return 2

    ident, plan_path = ARGV[0], ARGV[1]
    options = {"tree": None, "in_place": False, "lock": True, "build": True,
               "scheme": "Cadence", "destination": "platform=macOS", "keep_tree": False}
    rest = ARGV[2:]
    while rest:
        flag = rest.pop(0)
        if flag == "--tree":
            options["tree"] = rest.pop(0)
        elif flag == "--in-place":
            options["in_place"] = True
        elif flag == "--no-lock":
            options["lock"] = False
        elif flag == "--no-build":
            options["build"] = False
        elif flag == "--scheme":
            options["scheme"] = rest.pop(0)
        elif flag == "--destination":
            options["destination"] = rest.pop(0)
        elif flag == "--keep-tree":
            options["keep_tree"] = True
        else:
            say("unknown option %r" % flag)
            return 2

    if not os.path.exists(plan_path):
        plan_path = os.path.join(ROOT, plan_path)
    if not os.path.exists(plan_path):
        say("no such plan file: %s" % ARGV[1])
        return 2
    with open(plan_path, "r") as handle:
        try:
            mutations = parse_plan(handle.read())
        except (PlanError, ValueError) as problem:
            say("plan error: %s" % problem)
            return 2

    runner = Runner(ident, options)
    os.makedirs(runner.scratch, exist_ok=True)
    log_dir = os.path.join(runner.scratch, "logs")
    os.makedirs(log_dir, exist_ok=True)
    with open(os.path.join(runner.scratch, "runner.pid"), "w") as handle:
        handle.write("%d\n" % os.getpid())

    # Report before you probe: everything the run depends on, printed before the first thing that
    # can fail. A diagnostic that dies before its own header turns a known problem into a mystery.
    say("== cadence mutation runner (%s) ==" % ident)
    say("  plan:        %s  (%d mutations)" % (plan_path, len(mutations)))
    say("  scratch:     %s" % runner.scratch)
    say("  pid:         %d   (kill THAT, and never with -9: -9 skips the restore)" % os.getpid())

    if options["tree"]:
        tree = os.path.abspath(options["tree"])
        if os.path.realpath(tree) == os.path.realpath(ROOT) and not options["in_place"]:
            say("")
            say("!! REFUSING: --tree names the repository working tree. A runner that mutates it")
            say("   can strand a mutation in the user's checkout, because SIGKILL does not run")
            say("   traps and SIGTERM cannot be trusted to finish one. Pass --in-place if you")
            say("   really mean it, or drop --tree and get an isolated `git archive HEAD` copy.")
            return 2
    elif options["in_place"]:
        tree = ROOT
        say("")
        say("!! --in-place: mutating the repository working tree at %s." % ROOT)
        say("   If this runner is killed with -9 the mutation stays in the user's checkout.")
    else:
        tree = prepare_tree(runner.scratch, ident)
    runner.tree = tree
    say("  tree:        %s%s" % (tree, "" if options["tree"] or options["in_place"] else "  (git archive HEAD)"))
    say("  scheme:      %s   destination: %s" % (options["scheme"], options["destination"]))
    say("  builds:      %s" % ("yes" if options["build"] else "NO (--no-build: apply/restore only)"))
    say("")

    # Baselines and backups, taken before anything is edited. The baseline is the file as this run
    # found it -- not `git show HEAD:`, because a prepared --tree legitimately carries the agent's
    # own uncommitted tests, and those are part of what is being tested.
    backup_dir = os.path.join(runner.scratch, "backups")
    os.makedirs(backup_dir, exist_ok=True)
    for mutation in mutations:
        for name in mutation.files:
            path = os.path.join(tree, name)
            if not os.path.exists(path):
                say("plan error: %s names %s, which does not exist in the tree" % (mutation.ident, name))
                return 2
            if path not in runner.baselines:
                runner.baselines[path] = read_bytes(path)
                backup = os.path.join(backup_dir, name.replace("/", "__"))
                shutil.copyfile(path, backup)
                runner.backups[path] = backup

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, runner.on_signal)

    results = []
    try:
        if options["lock"] and options["build"]:
            lock = os.path.join(ROOT, "scripts", "test-host-lock.sh")
            say("acquiring the test-host lock as %s (one lease for the whole batch) ..." % runner.lock_id)
            taken = subprocess.run([lock, "acquire", os.environ.get("CADENCE_LOCK_TIMEOUT", "5400"), runner.lock_id])
            if taken.returncode != 0:
                say("could not acquire the test-host lock; refusing to run tests without it")
                return 1
            runner.lock_held = True

        if options["build"]:
            # The baseline run. Every mutation verdict is relative to it: in a tree whose suite is
            # already red, or which does not build, KILLED means nothing at all.
            say("")
            say("-- baseline (unmutated) --")
            probe = mutations[0]
            code, log, seconds = run_suite(tree, ident, probe, options["scheme"],
                                           options["destination"], log_dir, "baseline")
            base = classify_run(code, log, probe.suite, probe.tests)
            say("   exit=%d  test result lines=%d  swift warnings=%d  %.0fs"
                % (code, base.tests_ran, base.warnings, seconds))
            if base.verdict != SURVIVED:
                say("")
                say("!! REFUSING: the unmutated tree is not green over a non-zero test count.")
                say("   %s: %s" % (base.reason or base.verdict, base.detail))
                say("   Nothing downstream of this is evidence about anything.")
                return 1
            say("   baseline green over %d tests." % base.tests_ran)

        for index, mutation in enumerate(mutations, start=1):
            paths = [os.path.join(tree, name) for name in mutation.files]
            say("")
            say("-- %s (%d/%d)  %s" % (mutation.ident, index, len(mutations), mutation.note))
            say("   %s  suite=%s%s" % (", ".join(mutation.files), mutation.suite or "<none>",
                                       "  [weakening]" if mutation.weakening else ""))
            applied = apply_mutation(tree, runner.backups, runner.baselines, mutation)
            if not applied.ok:
                say("   VERDICT: INVALID (%s)" % applied.reason)
                say("   %s" % applied.detail)
                say("   NOT a survivor: nothing was tested.")
                results.append([mutation, "INVALID", applied.reason, applied.detail, 0, []])
                # Not applied means nothing to restore -- but say so from a byte comparison, not
                # from the assumption.
                for path in paths:
                    if read_bytes(path) != runner.baselines[path]:
                        say("   !! %s differs from its baseline anyway; restoring."
                            % os.path.relpath(path, tree))
                        restore(path, runner.backups[path], runner.baselines[path])
                continue
            runner.live = list(paths)
            say("   applied: %d hunk(s); every file differs from its backup and matches the"
                % len(mutation.hunks))
            say("   replacement this runner computed.")
            if not options["build"]:
                verdict = RunVerdict("INVALID", "NOT-RUN", "--no-build: applied and restored only")
            else:
                code, log, seconds = run_suite(tree, ident, mutation, options["scheme"],
                                               options["destination"], log_dir, mutation.ident)
                verdict = classify_run(code, log, mutation.suite, mutation.tests)
                say("   run: exit=%d  test result lines=%d  swift warnings=%d  %.0fs"
                    % (code, verdict.tests_ran, verdict.warnings, seconds))
            ok = restore_mutation(tree, runner.backups, runner.baselines, mutation)
            runner.live = []
            if not ok:
                say("   !! RESTORE FAILED for %s. Stopping: every later verdict would be void."
                    % ", ".join(mutation.files))
                results.append([mutation, "INVALID", "RESTORE-FAILED", "", verdict.tests_ran, verdict.failed])
                return 3
            say("   restored: every mutated file is byte-identical to its backup again.")
            if verdict.earned:
                detail = ""
                if verdict.verdict == KILLED:
                    detail = "killed by: %s" % ", ".join(sorted(set(verdict.failed)))
                    say("   VERDICT: KILLED -- %s" % detail)
                elif mutation.weakening:
                    detail = "%d tests ran and all passed" % verdict.tests_ran
                    say("   VERDICT: SURVIVED, provisionally -- %s." % detail)
                    say("   This mutation weakens an assertion, so the pairing pass below decides")
                    say("   whether that survival is evidence or is inconclusive.")
                else:
                    detail = "%d tests ran and all passed" % verdict.tests_ran
                    say("   VERDICT: SURVIVED -- %s. This one is earned." % detail)
                results.append([mutation, verdict.verdict, "", detail, verdict.tests_ran, verdict.failed])
            else:
                say("   VERDICT: INVALID (%s)" % verdict.reason)
                say("   %s" % verdict.detail)
                say("   NOT a survivor.")
                results.append([mutation, "INVALID", verdict.reason, verdict.detail, verdict.tests_ran, verdict.failed])
    finally:
        runner.emergency_restore("finishing")
        runner.release_lock()
        # The last word is always about the tree, verified rather than assumed.
        say("")
        say("== tree check ==")
        clean = True
        for path, baseline in runner.baselines.items():
            same = os.path.exists(path) and read_bytes(path) == baseline
            clean = clean and same
            say("  %s %s" % ("OK  " if same else "DIRTY", os.path.relpath(path, tree)))
        say("  %s" % ("every mutated file is back at its baseline." if clean
                      else "!! A MUTATION IS STILL IN THE TREE. Restore it by hand from %s." % os.path.join(runner.scratch, "backups")))

    # --- the summary --------------------------------------------------------
    settle_weakenings(results)
    say("")
    say("== summary (%s) ==" % ident)
    invalid = 0
    unsettled = 0
    unexpected = 0
    for mutation, verdict, reason, detail, ran, _failed in results:
        flag = ""
        if verdict == "INVALID":
            invalid += 1
        elif verdict == INCONCLUSIVE:
            unsettled += 1
        if mutation.expect and mutation.expect != verdict.lower():
            unexpected += 1
            flag = "   <-- plan expected %s" % mutation.expect
        say("  %-6s %-13s %-26s %s%s" % (mutation.ident, verdict, reason or detail, mutation.note, flag))
        if verdict in (INCONCLUSIVE, "INVALID") and detail:
            say("         %s" % detail)
    say("")
    say("  %d mutation(s): %d killed, %d survived, %d inconclusive, %d refused as invalid."
        % (len(results),
           sum(1 for r in results if r[1] == KILLED),
           sum(1 for r in results if r[1] == SURVIVED),
           unsettled,
           invalid))
    if invalid:
        say("  An INVALID verdict is not a survivor and not a kill. Fix the mutation and re-run it.")
    if unsettled:
        say("  An INCONCLUSIVE verdict is not a survivor either: the experiment had no control.")
    if unexpected:
        say("  %d mutation(s) did not match the plan's `expect:`." % unexpected)
    say("  logs: %s" % log_dir)
    if not options["keep_tree"] and not options["tree"] and not options["in_place"]:
        say("  scratch tree kept at %s (delete it when you are done)" % runner.tree)
    return 1 if (invalid or unsettled or unexpected) else 0


# --- selftest -----------------------------------------------------------------
#
# Every guard here exists because a real runner reported a survivor it had not earned. A guard
# nobody exercises is the same hollow instrument one layer up, so these induce all four failure
# modes deliberately and assert the runner refuses each. The apply/restore modes run against real
# files; the run-reading modes run against real log shapes, which is where mode 4 lives.

def selftest():
    failures = []

    def check(name, condition, detail=""):
        say("  %-4s %s%s" % ("ok" if condition else "FAIL", name, "" if condition else "  <- " + detail))
        if not condition:
            failures.append(name)

    say("== mutate.sh selftest ==")
    workspace = tempfile.mkdtemp(prefix="cadence-mutate-selftest-")
    try:
        source = os.path.join(workspace, "Fixture.swift")
        original = ('// returns "Daily" for the daily case\n'
                    'var label: String {\n'
                    '    switch self {\n'
                    '    case .daily: return "Daily"\n'
                    '    }\n'
                    '}\n').encode("utf-8")
        write_bytes(source, original)
        backup = os.path.join(workspace, "Fixture.swift.bak")
        shutil.copyfile(source, backup)

        backups = {source: backup}
        baselines = {source: original}

        def plan_for(old, new, count=1):
            mutation = Mutation("T")
            mutation.file = "Fixture.swift"
            mutation.hunks = [Hunk("Fixture.swift", old, new, count)]
            return mutation

        def apply(mutation):
            return apply_mutation(workspace, backups, baselines, mutation)

        say("")
        say(" mode 1 -- a stale needle must not read as a survivor")
        stale = apply(plan_for('return "Weekly"', 'return "X"'))
        check("stale needle is refused", not stale.ok and stale.reason == "NEEDLE-ABSENT", stale.reason)
        check("the file was left alone", read_bytes(source) == original)

        say("")
        say(" mode 2 -- a replacement containing its own anchor is an APPLY, not a failure")
        prefix = apply(plan_for('return "Daily"', 'return "Daily" + "!"'))
        after = read_bytes(source).decode("utf-8")
        check("the apply is reported as applied", prefix.ok, prefix.reason)
        check("the old substring is still present (which is why `old in text` was wrong)",
              'return "Daily"' in after)
        check("a substring check would have called this a failure",
              'return "Daily"' in after and read_bytes(source) != original)
        check("restore is verified", restore(source, backup, original))
        check("the file is byte-identical again", read_bytes(source) == original)

        say("")
        say(" mode 2b -- a stranded earlier mutation must void the next mutation, not survive it")
        write_bytes(source, original.replace(b'"Daily"', b'"Doubly"'))
        stranded = apply(plan_for('case .daily:', 'case .daily :'))
        check("a non-pristine file is refused", not stranded.ok and stranded.reason == "NOT-PRISTINE",
              stranded.reason)
        restore(source, backup, original)

        say("")
        say(" mode 3 -- a needle that also occurs in a comment is ambiguous, not a survivor")
        ambiguous = apply(plan_for('"Daily"', '"Weekly"'))
        check("an ambiguous needle is refused",
              not ambiguous.ok and ambiguous.reason == "NEEDLE-AMBIGUOUS", ambiguous.reason)
        check("both occurrences are named", "1, 4" in ambiguous.detail, ambiguous.detail)
        check("the file was left alone", read_bytes(source) == original)
        say("")
        say(" mode 3b -- the same needle passes once the plan says it means both")
        both = apply(plan_for('"Daily"', '"Weekly"', count=2))
        check("count: 2 applies", both.ok, both.reason)
        check("restore is verified", restore(source, backup, original))

        say("")
        say(" mode 4 -- a mutation that never compiled, and a run that took the host with it")
        compile_log = ("CompileSwift normal arm64\n"
                       "/x/Cadence/Models/ModelEnums.swift:459:29: error: cannot find 'Daily' in scope\n"
                       "** TEST FAILED **\n")
        did_not_compile = classify_run(65, compile_log, "HabitFrequencyLabelTests")
        check("a non-compiling mutation is INVALID",
              did_not_compile.verdict == "INVALID" and did_not_compile.reason == "DID-NOT-COMPILE",
              did_not_compile.reason)

        crash_log = ("Please submit a bug report (https://swift.org/contributing/#reporting-bugs)\n"
                     "Abort trap: 6\n")
        crashed = classify_run(1, crash_log, "HabitFrequencyLabelTests")
        check("a toolchain crash is INVALID, though it prints 0 error: lines",
              crashed.verdict == "INVALID" and crashed.reason == "TOOLCHAIN-CRASH", crashed.reason)
        check("and the strict error count really is 0 on it",
              len(COMPILE_ERROR.findall(crash_log)) == 0)

        empty_log = ("Test Suite 'Selected tests' passed at 2026-09-02 10:00:00.001.\n"
                     "\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds\n"
                     "** TEST SUCCEEDED **\n")
        empty = classify_run(0, empty_log, "HabitFrequencyLabelTests")
        check("a green run over zero tests is INVALID, not SURVIVED",
              empty.verdict == "INVALID" and empty.reason == "NO-TESTS-RAN", empty.reason)

        # The warning count is strict for the same reason the error count is. Measured on this
        # project's own clean baseline build, 2026-09-02: exactly one line matches a loose
        # `warning:` count, and it is not a Swift warning.
        noisy = ("appintentsmetadataprocessor[71338] warning: Metadata extraction skipped.\n"
                 "✔ Test theFullLabelIsUnchanged() passed after 0.001 seconds.\n")
        check("a clean build's appintents note is not counted as a warning",
              classify_run(0, noisy, None).warnings == 0)
        real = noisy + "/x/Foo.swift:3:9: warning: unused variable\n"
        check("a real Swift warning is", classify_run(0, real, None).warnings == 1)

        say("")
        say(" the earned verdicts must still be reachable")
        killed_log = ("◇ Test theFullLabelIsUnchanged() started.\n"
                      "✘ Test theFullLabelIsUnchanged() recorded an issue at Foo.swift:12:5\n"
                      "✔ Test everyFrequencyHasANameAndNoTwoShareIt() passed after 0.001 seconds.\n"
                      "Test Suite 'HabitFrequencyLabelTests' failed\n"
                      "** TEST FAILED **\n")
        killed = classify_run(65, killed_log, "HabitFrequencyLabelTests", ["theFullLabelIsUnchanged"])
        check("a real failure is KILLED", killed.verdict == KILLED, killed.reason)
        check("and the killing test is named", killed.failed == ["theFullLabelIsUnchanged"])

        survivor_log = ("◇ Test theFullLabelIsUnchanged() started.\n"
                        "✔ Test theFullLabelIsUnchanged() passed after 0.001 seconds.\n"
                        "✔ Test everyFrequencyHasANameAndNoTwoShareIt() passed after 0.001 seconds.\n"
                        "Test Suite 'HabitFrequencyLabelTests' passed\n"
                        "** TEST SUCCEEDED **\n")
        survivor = classify_run(0, survivor_log, "HabitFrequencyLabelTests", ["theFullLabelIsUnchanged"])
        check("a genuine survivor is still SURVIVED", survivor.verdict == SURVIVED, survivor.reason)

        say("")
        say(" a run scoped to somebody else's suite is not evidence about yours")
        wrong_scope = ("Command line invocation: xcodebuild -only-testing:CadenceTests/HabitFrequencyLabelTests\n"
                       "✔ Test somethingElse() passed after 0.001 seconds.\n"
                       "** TEST SUCCEEDED **\n")
        scoped = classify_run(0, wrong_scope, "HabitFrequencyLabelTests")
        check("the suite name on the invocation line is not evidence that it ran",
              scoped.verdict == "INVALID" and scoped.reason == "SUITE-ABSENT", scoped.reason)

        say("")
        say(" a red run with no failing test is not a kill")
        red = classify_run(70, "✔ Test somethingElse() passed after 0.001 seconds.\n** TEST FAILED **\n")
        check("red without a failing test is INVALID",
              red.verdict == "INVALID" and red.reason == "RED-WITHOUT-A-FAILING-TEST", red.reason)

        say("")
        say(" a multi-hunk mutation is all-or-nothing")
        two_hunks = Mutation("T2")
        two_hunks.file = "Fixture.swift"
        two_hunks.hunks = [Hunk("Fixture.swift", 'case .daily:', 'case .daily :'),
                           Hunk("Fixture.swift", 'return "Nope"', 'return "X"')]
        partial = apply(two_hunks)
        check("a mutation whose second hunk is stale is refused",
              not partial.ok and partial.reason == "NEEDLE-ABSENT", partial.reason)
        check("and its first hunk is rolled back rather than left in the tree",
              read_bytes(source) == original)
        good_pair = Mutation("T3")
        good_pair.file = "Fixture.swift"
        good_pair.hunks = [Hunk("Fixture.swift", 'case .daily:', 'case .daily :'),
                           Hunk("Fixture.swift", 'var label', 'var name'),]
        check("two good hunks apply together", apply(good_pair).ok)
        check("both landed", b'case .daily :' in read_bytes(source) and b'var name' in read_bytes(source))
        check("restore is verified", restore_mutation(workspace, backups, baselines, good_pair))

        say("")
        say(" mode 5 -- a weakened assertion that survives is inconclusive until it is paired")

        def weakening(ident, path, pair=None, verdict=SURVIVED, failed=()):
            mutation = Mutation(ident)
            mutation.file = path
            mutation.hunks = [Hunk(path, "a", "b", 1)]
            mutation.pair = pair
            return [mutation, verdict, "", "", 2, list(failed)]

        lone = weakening("M6", "CadenceTests/SomeTests.swift")
        settle_weakenings([lone])
        check("an unpaired weakening is INCONCLUSIVE, not SURVIVED",
              lone[1] == INCONCLUSIVE and lone[2] == "UNPAIRED-WEAKENING", lone[2])

        control = weakening("M5", "Cadence/Models/ModelEnums.swift", verdict=KILLED,
                            failed=["theExactCountHolds"])
        paired = weakening("M6", "CadenceTests/SomeTests.swift", pair="M5")
        settle_weakenings([control, paired])
        check("a weakening paired with a KILLED control stays SURVIVED", paired[1] == SURVIVED, paired[2])
        check("and the control is named in the evidence", "M5" in paired[3] and "theExactCountHolds" in paired[3],
              paired[3])

        limp = weakening("M5", "Cadence/Models/ModelEnums.swift", verdict=SURVIVED)
        limp_pair = weakening("M6", "CadenceTests/SomeTests.swift", pair="M5")
        settle_weakenings([limp, limp_pair])
        check("a pair whose control was not killed settles nothing",
              limp_pair[1] == INCONCLUSIVE and limp_pair[2] == "PAIR-NOT-KILLED", limp_pair[2])

        orphan = weakening("M6", "CadenceTests/SomeTests.swift", pair="M9")
        settle_weakenings([orphan])
        check("a pair naming no mutation is refused",
              orphan[1] == INCONCLUSIVE and orphan[2] == "PAIR-MISSING", orphan[2])

        source = weakening("M7", "Cadence/Models/ModelEnums.swift")
        settle_weakenings([source])
        check("a source-file survivor is a finding, not an inconclusive", source[1] == SURVIVED)

        inferred = Mutation("M8")
        inferred.hunks = [Hunk("CadenceTests/SomeTests.swift", "a", "b", 1)]
        check("weakening is inferred for a test-file mutation", inferred.weakening)
        inferred.weakens = False
        check("and `weakens: no` overrides the inference", not inferred.weakening)

        say("")
        say(" the plan parser")
        parsed = parse_plan('mutation: M1\nfile: A.swift\nsuite: S\nexpect: killed\n'
                            '--- old\nalpha\nbeta\n--- new\ngamma\n--- end\n')
        check("one mutation parsed", len(parsed) == 1)
        check("the old text is literal and multi-line", parsed[0].hunks[0].old == "alpha\nbeta")
        check("the new text is literal", parsed[0].hunks[0].new == "gamma")
        multi = parse_plan('mutation: M8\nfile: Cadence/A.swift\n--- old\na\n--- new\nb\n--- end\n'
                           'file: CadenceTests/B.swift\n--- old\nc\n--- new\nd\n--- end\n')
        check("one mutation may span two files",
              [h.file for h in multi[0].hunks] == ["Cadence/A.swift", "CadenceTests/B.swift"])
        check("and a hunk in CadenceTests/ makes the whole mutation a weakening", multi[0].weakening)
        paired_plan = parse_plan('mutation: M5\nfile: A.swift\nexpect: killed\n--- old\na\n--- new\nb\n--- end\n'
                                 'mutation: M6\nfile: CadenceTests/B.swift\npair: M5\nweakens: yes\n'
                                 '--- old\nc\n--- new\nd\n--- end\n')
        check("pair: and weakens: parse", paired_plan[1].pair == "M5" and paired_plan[1].weakening)
        try:
            parse_plan('mutation: M1\nfile: A.swift\n--- old\na\n--- new\nb\n')
            check("a plan ending inside a block is refused", False, "it was accepted")
        except PlanError:
            check("a plan ending inside a block is refused", True)
        try:
            parse_plan('mutation: M1\nfile: A.swift\npair: M1\n--- old\na\n--- new\nb\n--- end\n')
            check("a mutation paired with itself is refused", False, "it was accepted")
        except PlanError:
            check("a mutation paired with itself is refused", True)
        try:
            parse_plan('mutation: M1\nfile: A.swift\n--- old\nx\n--- new\nx\n--- end\n')
            check("a no-op mutation is refused", False, "it was accepted")
        except PlanError:
            check("a no-op mutation is refused", True)
    finally:
        shutil.rmtree(workspace, ignore_errors=True)

    say("")
    if failures:
        say("SELFTEST FAILED: %s" % ", ".join(failures))
        return 1
    say("SELFTEST PASSED")
    return 0


sys.exit(main())
PY
