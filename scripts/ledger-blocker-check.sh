#!/bin/sh
# Ask whether a ledger entry's STATED BLOCKER is still true (T-3321).
#
#   ./scripts/ledger-blocker-check.sh [<rev>]    # default: the working tree's ledger; exit 0
#   ./scripts/ledger-blocker-check.sh --strict   # same reading, exit 3 on a finding
#   ./scripts/ledger-blocker-check.sh selftest   # prove every finding and every refusal still fires
#
# WHY THIS EXISTS, AND WHY IT IS A SIBLING RATHER THAN A FOURTH ARM OF ledger-lag-check.sh
#
# `scripts/ledger-lag-check.sh` asks whether a commit that landed code closed anything, and every
# one of its arms is keyed on a COMMIT: it walks `git log`, computes one verdict per commit, and
# its three non-vacuity floors count commits, entries and commits EXAMINED. This check reads no log
# at all. Its unit is an ENTRY and its evidence is the repository's present state -- which refs
# exist, which paths are dirty, what the fence says, which ids are closed. Folding it in would mean
# a second pass with its own floors, its own exit contract and its own vocabulary inside a file
# whose 1376 lines are one argument about closure lag; the two would share the ledger reading and
# nothing else. So the ledger reading is what is shared (copied character for character below, the
# same way that script shares it with `agent-commit.sh` and `scripts/ledger-view.sh`), and the
# check is its own file. It is also the only guard here that must do GLOB matching, and the house
# rule for that is Python `fnmatch` and never a shell loop -- `#!/bin/sh` globs an unquoted `$pat`
# in a `case` and zsh does not, and `CadenceGuardScriptSelftestTests` runs these scripts under the
# shell their shebang names precisely because that difference has changed a reading before.
#
# THE DEFECT, MEASURED. `docs/AGENT_BRIEF.md` already states the failure mode -- *"a ticket names a
# live agent or a dirty file, that work lands, and the ticket stays parked on a condition that no
# longer exists"* -- and nothing in the repository detected it. On 2026-10-21, 33 of the 64 PARTIAL
# entries named a lease, grant or fence as what they were waiting on, and `b537dd50` had released
# EVERY fenced path to local agents the day before. Agent `staleswep` swept 133 entries by hand and
# found 13 expired blockers, 11 of them that one release. Separately, two tickets sat parked on
# agent `dragcreate` being mid-edit in a file for hours after that work landed in `db52ebbd`, and
# of five defects the owner reported, three needed no code at all. Each one cost a reader time
# before anybody checked. The sweep is the expensive way to find them; this is the cheap one.
#
# WHAT IS READ, AND THE TWO NARROWINGS THAT DO ALL THE WORK
#
# Only ACTIVE entries (`ledger-view.sh`'s OPEN / PARTIAL / PARKED). A blocker clause inside a
# CLOSED entry is history, not a claim, and 835 of this ledger's 1089 entries are closed -- so this
# narrowing alone removes 87% of the text before any pattern runs.
#
# Only the entry's LIVE text: everything before its first `**Earlier:**` / `**Originally:**` /
# `**Previously:**` / `**Superseded` bold marker, which is how this ledger demotes prose a later
# pass has overtaken. 21 of the 138 active entries carry one. [[T-3109]] is the case that proves it
# matters: its first line is a current PARTIAL and its `**BLOCKED ON THE CODEX LEASE**` paragraph
# sits under `**Earlier:**`, so a whole-entry reading flags an entry whose own author already
# retired the claim. `staleswep`'s hand sweep counted T-3109; this does not, deliberately.
#
# THE FOUR ARMS, in the order they have bitten, each with the command that disproves it:
#
#   BLOCKER-LEASE-RELEASED  a lease / fence / grant blocker, against `docs/CODEX_WORKTREE.md`'s
#                           2026-10-20 release. THE SUBTLE ONE -- see below.
#   BLOCKER-BRANCH-GONE     a named branch that `git rev-parse --verify` cannot resolve.
#   BLOCKER-PATH-CLEAN      a path called dirty that `git status --porcelain -- <path>` says is not.
#   BLOCKER-TICKET-CLOSED   a blocking ticket id that now reads CLOSED.
#
# THE LEASE ARM, AND IT IS WHERE A CONFIDENT WRONG ANSWER LIVES. The fenced block in
# `docs/CODEX_WORKTREE.md` governs **Codex**; the 2026-10-20 prose entry beside it released every
# fenced path to **LOCAL agents** and left the block deliberately untouched, because
# `codex-land.sh:62` refuses on an empty lease ("an empty lease reads exactly like a lease that
# allows everything; it allows nothing"). So a NON-EMPTY FENCE DOES NOT MEAN A LOCAL AGENT IS
# BLOCKED, and reading the fence alone gives exactly the wrong answer on all eleven of the entries
# this arm is for. Two things follow, and both are enforced rather than commented:
#
#   * the release is VERIFIED IN THE DOCUMENT on every run, not hardcoded. If that prose is ever
#     removed -- a Codex agent resuming is the case the release entry itself names -- the arm
#     DISABLES ITSELF and says so, because the claims it flags would be true again.
#   * where the clause names paths, they are matched against the fence with Python `fnmatch` so the
#     printed reason is the right one: a fenced path is freed BY THE RELEASE, while a path the
#     fence does not match was never Codex's to hold and the claim is wrong for a different reason.
#     That distinction is the whole of the arm's output and is why the glob matching is here at all.
#
# AN ENTRY THAT CITES THE RELEASE IS EXEMPT FROM THIS ARM ENTIRELY -- `b537dd50`, or the release
# section's own words. Such an entry has already been checked by a human, and [[T-3171]] and
# [[T-3296]] are both of that shape: T-3171 records the fence being released in the clause itself,
# and T-3296 is `staleswep`'s sweep, which is eleven blocker clauses quoted in order to retire them.
# Without this, the one entry that did the work is the loudest finding on the run.
#
# THE DIRTY ARM CANNOT RUN IN CI AND SAYS SO RATHER THAN PASSING. A GitHub Actions checkout is a
# fresh clone with one worktree and no local edits, so `git status --porcelain` is empty for EVERY
# path and every "X is dirty under agent Y" clause would flag. That is a check that answers a
# cheaper question than the one being asked -- `docs/CODEX_WORKTREE.md`'s own table of six failures
# is a list of exactly that mistake -- so the arm is SKIPPED when `GITHUB_ACTIONS` or `CI` is set,
# and the skip is printed with its denominator on every run. Locally it reads the MAIN checkout,
# not this worktree: the claim is about the shared tree `agent-commit.sh` stages whole files from.
#
# IT REPORTS; IT DOES NOT FAIL. A ledger entry is prose written by many hands over months, and a
# check that reddens CI on a phrasing it does not understand is a check somebody disables inside a
# week. Two more reasons, both specific to this reading: a finding here is AMBIENT -- it is not
# caused by the commit under test, so it would be red for every agent until an unrelated one
# repaired a ticket they do not own -- and the repair is editing a sentence, which no code gate
# should be able to demand. `--strict` exists for the day the owner decides otherwise and refuses
# BLOCKER-STALE with exit 3; the selftest proves both exits, so adopting it is a workflow edit and
# not a rewrite. The precedent is in the sibling: LEDGER-CLOSURE-UNLANDED is a NOTICE for the same
# reason and prints its denominator on every run, green or not (T-1343).
#
# FALSE POSITIVES ARE THE WHOLE RISK, AND THE NUMBER IS MEASURED RATHER THAN HOPED FOR. Run against
# the real 3.8 MB ledger at `961971ec`: 1089 entries, 138 active, 38 blocker clauses scanned, 13
# findings, all 13 hand-checked and agreed -- 100% precision on that run, and 7 of them are among
# the 11 `staleswep` found by hand, 3 more are entries that sweep did not reach ([[T-168]],
# [[T-3170]], [[T-3249]]), and 2 post-date the sweep ([[T-3250]], [[T-3260]]). The honest caveat is
# that the guards below were TUNED against this ledger: the first draft flagged 13 and two were
# wrong -- [[T-3152]], where a path from the NEXT sentence was read as the object of an
# "uncommitted in someone else's checkout" clause, and [[T-2020]], whose *"blocked by [[T-117]]
# while the owner's Xcode may be open"* names a CLOSED ticket that records a STANDING RULE rather
# than work to wait for. The same-sentence object rule and the conditional guard are those two
# cases; a third ledger would find a third shape. The denominators printed on every run are what
# makes the next one visible.
set -u

MIN_ENTRIES=${CADENCE_BLOCKER_MIN_ENTRIES:-300}
MIN_ACTIVE=${CADENCE_BLOCKER_MIN_ACTIVE:-40}
MIN_SCANNED=${CADENCE_BLOCKER_MIN_SCANNED:-8}
MIN_FENCE=${CADENCE_BLOCKER_MIN_FENCE:-20}

TODO_PATH=${CADENCE_BLOCKER_TODO:-docs/TODO.md}
DONE_PATH=${CADENCE_BLOCKER_DONE:-docs/TODO_DONE.md}
FENCE_DOC=${CADENCE_BLOCKER_FENCE_DOC:-docs/CODEX_WORKTREE.md}

# T-1343, copied from `scripts/ledger-view.sh`. `#!/bin/sh` writes here-documents under $TMPDIR;
# zsh writes them to $TMPPREFIX, which it sets to `/tmp/zsh` itself, and on the App-Sandboxed test
# host /tmp is unwritable -- so every document becomes an EMPTY file and the run refuses against a
# fixture that exists and is blank. Harmless under the right shell; the wrong one needs it.
_tmp_base="${TMPDIR:-/tmp/}"; case "$_tmp_base" in */) ;; *) _tmp_base="$_tmp_base/" ;; esac
export TMPPREFIX="${CADENCE_TMPPREFIX:-${_tmp_base}zsh}"

# `/usr/bin/git` and `/usr/bin/python3` are xcrun shims and xcrun REFUSES to run inside an App
# Sandbox, which is where `CadenceGuardScriptSelftestTests` calls the selftest below from. Every
# call then fails with that on stderr and nothing else, which reads like a broken repository. Same
# probe, same order and the same reason as `scripts/agent-commit.sh` (T-719) and
# `scripts/ledger-lag-check.sh`; duplicated rather than shared because a guard script that needs
# another file to start is a guard with a new way to stop running.
_rehome() {  # $1 = tool name
    "$1" --version >/dev/null 2>&1 && return 0
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin /usr/bin; do
        [ -x "$_candidate/$1" ] || continue
        "$_candidate/$1" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; export PATH; return 0
    done
    return 1
}
_rehome git || :
_rehome python3 || :

refuse() { printf 'REFUSED (%s): %s\n' "$1" "$2" >&2; exit "$3"; }

# The lease, parsed exactly as `scripts/codex-land.sh`'s `read_lease` parses it -- one line, copied
# rather than reimplemented, so the two cannot answer differently about what the fence holds.
read_fence() {  # $1 = the document to read; stdout: one glob per line
    [ -f "$1" ] || return 1
    awk '/^```lease$/ { inb = 1; next } inb && /^```$/ { exit } inb && NF { print }' "$1"
}


# ---------------------------------------------------------------------------
# THE READING, as one Python pass over: the ledger, the archive, the fence, the refs, the dirty
# paths. Python rather than awk for one reason that is not taste -- fnmatch. The house rule is that
# a lease pattern is matched with Python fnmatch and NEVER a shell glob loop, because /bin/sh
# expands an unquoted $pat inside a case and zsh does not, and that difference has produced three
# confident wrong answers about this very fence in one day.
#
# Held in a variable and piped to python3 -I -: -I so the interpreter adds neither the current
# directory nor PYTHONPATH to sys.path, which matters because this runs from a repository root
# where a stray json.py would be imported ahead of the standard library.
#
# NOT ONE LITERAL BACKTICK BELOW, and it is the same constraint ledger-lag-check.sh records at its
# own awk programs: this whole block is carried inside a command substitution, where a run of
# backticks opens a NESTED substitution and an odd number of them ends the outer one early. So the
# fence character is built with chr(96) and composed in, exactly as that script builds it with
# sprintf("%c", 96). Measured here: written out, /bin/sh (bash 3.2) refused the file at the first
# regex holding one.
# ---------------------------------------------------------------------------
PY_PROG=$(cat <<'PY'
import collections, fnmatch, re, sys

todo_f, done_f, fence_f, refs_f, dirty_f, release_f, dirty_mode, granted_f = sys.argv[1:9]
US = "\x1f"
BQ = chr(96)

# --- the ledger reading, scripts/ledger-view.sh's status_of in Python -------------------------
# One rule, four files (T-1335, T-1359). A marker inside inline code is a QUOTATION, not a
# closure; "## Done" / "## Cancelled" and the archive close an entry with no marker at all.
def closure_visible(s):
    return re.sub(BQ + "[^" + BQ + "]*" + BQ, " ", s)

def first_line_closed(s):
    return re.search(r"\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)", closure_visible(s)) is not None

def first_line_partial(s):
    return re.match(r"^- \[T-\d+\] \*\*PARTIAL([^A-Za-z]|$)", s) is not None

ENTRY = re.compile(r"^- \[(T-\d+)\] ")

def read_entries(path, archived):
    out, sec, cur = [], "", None
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    for ln in text.split("\n"):
        if ln.startswith("## "):
            sec = ln[3:]
        m = ENTRY.match(ln)
        if m:
            if cur:
                out.append(cur)
            cur = {"id": m.group(1), "sec": sec, "first": ln, "body": [], "archived": archived}
        elif cur:
            cur["body"].append(ln)
    if cur:
        out.append(cur)
    return out

entries = read_entries(todo_f, False) + read_entries(done_f, True)
for e in entries:
    if e["archived"] or e["sec"].startswith(("Done", "Cancelled")):
        e["st"] = "ARCHIVED"
    elif first_line_closed(e["first"]):
        e["st"] = "CLOSED"
    elif first_line_partial(e["first"]):
        e["st"] = "PARTIAL"
    else:
        e["st"] = "OPEN"

ACTIVE = ("OPEN", "PARTIAL", "PARKED")
# An id is closed only while NO entry of it is active -- ledger_closed_ids' SET reading (T-1303).
# Two concurrent agents have double-allocated an id twice in one day here, and reading the status
# off whichever entry happened to be last lets the duplicate decide.
open_ids = {e["id"] for e in entries if e["st"] in ACTIVE}
closed_ids = {e["id"] for e in entries if e["st"] not in ACTIVE} - open_ids

def lines_of(path):
    try:
        return [l.strip() for l in open(path, encoding="utf-8", errors="replace") if l.strip()]
    except OSError:
        return []

fence = lines_of(fence_f)
refs = set(lines_of(refs_f))
# origin/codex/foo resolves the bare name too, which is how the ledger writes it.
refs |= {r.split("/", 1)[1] for r in list(refs) if r.startswith("origin/")}
dirty = set(lines_of(dirty_f))
release = open(release_f, encoding="utf-8", errors="replace").read().strip()
# The paths a post-release grant handed back to Codex, by full path AND by basename stem: the
# grant writes CadenceTests/CadencePendingChangePersistenceTests.swift and the ledger writes
# CadencePendingChangePersistenceTests:218, and neither spelling may be the only one that matches.
granted = set(lines_of(granted_f))
granted_stems = {p.rsplit("/", 1)[-1].rsplit(".", 1)[0] for p in granted} | granted

# --- the clause readings ----------------------------------------------------------------------
# Everything after the first of these is prose a later pass has overtaken; this ledger demotes
# rather than deletes, so the markers are the only thing that says which half is current.
DEMOTE = re.compile(r"\*\*(Earlier|EARLIER|Originally|ORIGINALLY|Previously|PREVIOUSLY|Superseded|SUPERSEDED)\b")

# A clause that RETIRES its own blocker, in every shape this ledger writes one. Read over a window
# around the match rather than over the whole entry: an entry may retire one blocker and still hold
# another, and T-3229 is both in one sentence -- "(2) was blocked by the lease, and the 2026-10-18
# coordinator grant unblocked it".
RETIRED = re.compile(
    r"(?i)(not blocked|never been blocked|no longer|unblocked|was blocked|were blocked"
    r"|not what stopped|not a blocker|rather than a blocked|is gone|b537dd50"
    r"|\breleased\b|\blifted\b|does not block|not by the fence|already describes)")

# A blocker stated as a STANDING CONDITION rather than as work to wait for. T-2020 is the measured
# case: "blocked by [[T-117]] while the owner's Xcode may be open" -- T-117 is closed, and the rule
# it records is permanent, so the id's state says nothing at all about the claim.
CONDITIONAL = re.compile(r"(?i)\b(while|whenever|if |as long as|unless)\b")

BRANCHY = r"(?:codex|claude|heartbeat|post\d*|worktree-agent)[-/]"
REF_TOKEN = re.compile(BQ + "(" + BRANCHY + r"[A-Za-z0-9._/-]+)" + BQ)
PATH_TOKEN = re.compile(
    BQ + r"([A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:swift|md|txt|yml|yaml|plist|pbxproj|json))" + BQ)
TICKET_TOKEN = re.compile(r"\[\[(T-\d+)\]\]|\b(T-\d+)\b")

ARMS = [
    ("BLOCKER-LEASE-RELEASED", re.compile(
        r"(?i)(?:LEASE-BLOCKED"
        r"|blocked (?:by|on) the (?:codex )?lease|parked on the (?:codex )?lease"
        r"|waiting on grants?|needs? (?:a|the) (?:grant|lease)|not granted"
        r"|is FENCED|awaiting a grant|no prose grant"
        r"|(?:inside|in) the fenced[^.;]{0,24}?lease|outside (?:Codex.s|the) lease"
        r"|(?:once|until|when) the lease (?:lifts|is lifted|is released)"
        r"|(?:is|are|stays?) still leased|blocks it is only the lease"
        r"|STOPPED on the (?:codex )?lease)")),
    ("BLOCKER-BRANCH-GONE", re.compile(
        r"(?i)\b(?:blocked|parked|waiting|stalled|gated|held)\b[^.;]{0,50}?"
        r"\b(?:on|by|for|until)\b[^.;]{0,50}?(?=" + BQ + BRANCHY + ")")),
    ("BLOCKER-PATH-CLEAN", re.compile(
        r"(?i)(?:is still dirty|is dirty|are dirty|dirty with|dirty under|mid-edit in"
        r"|holds? (?:that |the )?file dirty|held uncommitted|held an uncommitted"
        r"|uncommitted in (?:someone else.s|another)"
        r"|blocked by a live writer|a live writer holds)")),
    # THE ID MUST BE THE DIRECT OBJECT OF THE PREPOSITION, not an id anywhere after one. T-1117 is
    # the measured case: "the portable-link branch stays blocked on its own GROUNDS (T-390, plus
    # CloudKit Production since 2026-09-05)" cites a landed ticket as the RECORD OF THE REASONING,
    # and a second, non-ticket ground sits in the same parenthesis. A gap-tolerant reading calls
    # that a finding; it is the same shape as T-2020's standing condition one clause further out.
    ("BLOCKER-TICKET-CLOSED", re.compile(
        r"(?i)\b(?:blocked|parked|waiting|gated|stalled)\b[^.;]{0,40}?"
        r"\b(?:on|by|until)\s+(?:the\s+|a\s+)?(?=\[\[T-\d+\]\]|T-\d+\b)")),
]

# An entry that CITES the release has been checked by a human already; see the header.
CITES_RELEASE = re.compile(r"(?i)(b537dd50|released (?:every fenced path|to LOCAL agents))")

scanned = collections.Counter()
skipped = collections.Counter()
findings = {}            # (id, arm) -> record; one finding per entry per arm, the reader's unit
n_active = 0

for e in entries:
    if e["st"] not in ACTIVE:
        continue
    n_active += 1
    text = re.sub(r"\s+", " ", " ".join([e["first"]] + e["body"]))
    cut = DEMOTE.search(text)
    live = text[: cut.start()] if cut else text
    cites = CITES_RELEASE.search(live) is not None
    for arm, pat in ARMS:
        for m in pat.finditer(live):
            scanned[arm] += 1
            if (e["id"], arm) in findings:
                skipped[arm + "/same-entry"] += 1
                continue
            window = live[max(0, m.start() - 70): m.start() + 200]
            if RETIRED.search(window):
                skipped[arm + "/retired-in-the-clause"] += 1
                continue
            tail = live[m.start(): m.start() + 200]
            # The clause the object must be named in: from the match to the end of its sentence or
            # the next bold run, whichever comes first. T-3152 is why -- "uncommitted in someone
            # else's checkout." names no path, and the NEXT sentence's Cadence/Info.plist is a
            # different subject entirely, which the first draft of this read as the object.
            sentence = re.split(r"(?<=[.;])\s|\*\*", tail)[0]
            if arm == "BLOCKER-LEASE-RELEASED":
                if not release:
                    skipped[arm + "/no-release-recorded"] += 1
                    continue
                if cites:
                    skipped[arm + "/entry-cites-the-release"] += 1
                    continue
                # A path a post-release grant handed back to Codex is held by a LIVE WRITER, not by
                # a fence nobody is behind, so the entry waiting on it is right and must not be
                # flagged. This is the arm the release entry itself asks for.
                if any(stem in window for stem in granted_stems):
                    skipped[arm + "/granted-to-codex-after-the-release"] += 1
                    continue
                # A FENCED path near a lease clause corroborates it, so it may be read from the
                # wider tail -- T-3051 names its path in the sentence AFTER the blocker. An
                # UNFENCED one is a claim ABOUT that path and is only quotable as the clause's
                # subject when it is in the same sentence: T-3250's clause is "(c) is still leased
                # and untouched", whose real subject is a fenced doc two sentences earlier, and a
                # tail-wide loose reading printed a Cadence/Shared/AGENTS.md from the NEXT sentence
                # as the thing the fence does not match. True finding, wrong path, which is the
                # kind of output that gets a check switched off.
                fenced = [p for p in PATH_TOKEN.findall(tail)
                          if any(fnmatch.fnmatch(p, g) for g in fence)]
                loose = [p for p in PATH_TOKEN.findall(sentence) if p not in fenced]
                if fenced:
                    why = ("the fence matches " + ", ".join(fenced) + ", and " + release +
                           " freed every fenced path to LOCAL agents")
                    obj = ", ".join(fenced)
                elif loose:
                    why = ("the fence matches none of " + ", ".join(loose) + "; " + release +
                           " freed every fenced path to LOCAL agents besides")
                    obj = "(none of the named paths is fenced)"
                else:
                    why = release + " freed every fenced path to LOCAL agents"
                    obj = "(no path named in the clause)"
                findings[(e["id"], arm)] = (e["id"], e["st"], arm, obj, why,
                                            "./scripts/codex-land.sh lease", window)
            elif arm == "BLOCKER-BRANCH-GONE":
                mo = REF_TOKEN.search(sentence)
                if not mo:
                    skipped[arm + "/no-branch-named"] += 1
                    continue
                branch = mo.group(1)
                if branch in refs:
                    skipped[arm + "/branch-still-exists"] += 1
                    continue
                findings[(e["id"], arm)] = (
                    e["id"], e["st"], arm, branch,
                    "no ref of that name exists, local or remote",
                    "git rev-parse --verify refs/heads/" + branch, window)
            elif arm == "BLOCKER-PATH-CLEAN":
                if dirty_mode != "read":
                    skipped[arm + "/not-evaluated-here"] += 1
                    continue
                mo = PATH_TOKEN.search(live[max(0, m.start() - 70): m.start() + len(sentence)])
                if not mo:
                    skipped[arm + "/no-path-named"] += 1
                    continue
                path = mo.group(1)
                if path in dirty:
                    skipped[arm + "/still-dirty"] += 1
                    continue
                findings[(e["id"], arm)] = (
                    e["id"], e["st"], arm, path,
                    "the main checkout has no uncommitted change to it",
                    "git status --porcelain -- " + path, window)
            else:
                mo = TICKET_TOKEN.search(tail)
                if not mo:
                    skipped[arm + "/no-ticket-named"] += 1
                    continue
                tid = mo.group(1) or mo.group(2)
                if tid == e["id"]:
                    skipped[arm + "/names-itself"] += 1
                    continue
                if tid in open_ids or tid not in closed_ids:
                    skipped[arm + "/blocker-still-open"] += 1
                    continue
                if CONDITIONAL.search(tail[mo.end(): mo.end() + 60]):
                    skipped[arm + "/standing-condition"] += 1
                    continue
                findings[(e["id"], arm)] = (
                    e["id"], e["st"], arm, tid, "that entry now reads CLOSED",
                    "./scripts/ledger-view.sh head " + tid, window)

total_scanned = sum(scanned.values())
out = []
for key in sorted(findings, key=lambda k: (k[1], int(k[0][2:]))):
    r = findings[key]
    out.append(US.join(["F", r[0], r[1], r[2], r[3], r[4], r[5], r[6][:200]]))
for arm, _ in ARMS:
    out.append(US.join(["S", arm, str(scanned[arm])]))
for k in sorted(skipped):
    out.append(US.join(["K", k, str(skipped[k])]))
out.append(US.join(["N", str(len(entries)), str(n_active), str(total_scanned),
                    str(len(fence)), str(len(findings))]))
sys.stdout.write("\n".join(out) + "\n")
PY
)

# ---------------------------------------------------------------------------
# The evidence the reading above is given, gathered ONCE by the shell so the Python pass shells out
# to nothing. Every one of these is a command a reader can run by hand, and the finding lines print
# the per-finding form of it.
# ---------------------------------------------------------------------------
run_check() {  # $1 = rev or empty (working tree), $2 = strict|report
    rev=$1; mode=$2
    root=$(git rev-parse --show-toplevel 2>/dev/null) \
        || refuse BLOCKER-NOT-REPO-ROOT "not inside a git repository" 3
    cd "$root" || refuse BLOCKER-NOT-REPO-ROOT "cannot enter $root" 3

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ledger-blocker-XXXXXX") || exit 3
    trap 'rm -rf "$tmp"' EXIT INT TERM

    if [ -n "$rev" ]; then
        git show "$rev:$TODO_PATH" > "$tmp/todo.md" 2>/dev/null \
            || refuse BLOCKER-CHECK-VACUOUS "$rev has no $TODO_PATH to read" 4
        git show "$rev:$DONE_PATH" > "$tmp/done.md" 2>/dev/null || : > "$tmp/done.md"
        git show "$rev:$FENCE_DOC" > "$tmp/fence_doc.md" 2>/dev/null || : > "$tmp/fence_doc.md"
        _fence_src="$tmp/fence_doc.md"
    else
        [ -f "$TODO_PATH" ] || refuse BLOCKER-CHECK-VACUOUS "$TODO_PATH is not there to read" 4
        cp "$TODO_PATH" "$tmp/todo.md"
        if [ -f "$DONE_PATH" ]; then cp "$DONE_PATH" "$tmp/done.md"; else : > "$tmp/done.md"; fi
        _fence_src=$FENCE_DOC
    fi

    # The fence, read exactly as codex-land.sh reads it. An UNREADABLE document and an EMPTY block
    # are different failures and neither may pass as "nothing is fenced": the second is
    # codex-land.sh:62's argument restated here, because a lease arm handed an empty fence would
    # call every fenced-path claim unfenced and print the wrong reason for every one of them.
    if [ ! -f "$_fence_src" ]; then
        refuse BLOCKER-FENCE-UNREADABLE "$FENCE_DOC is missing; the lease arm has nothing to match against" 4
    fi
    read_fence "$_fence_src" > "$tmp/fence.txt" 2>/dev/null || : > "$tmp/fence.txt"
    if [ ! -s "$tmp/fence.txt" ]; then
        refuse BLOCKER-FENCE-EMPTY "the lease block in $FENCE_DOC names no path.
  An empty lease reads exactly like a lease that allows everything; it allows nothing
  (scripts/codex-land.sh:62), and a lease arm reading one calls every fenced path unfenced." 4
    fi

    # THE RELEASE, VERIFIED IN THE DOCUMENT RATHER THAN HARDCODED. The lease arm's whole disproof
    # is this section existing; if a Codex agent resumes and it is withdrawn -- which the release
    # entry itself names as the case -- every claim the arm flags becomes true again, so the arm
    # must go quiet rather than keep printing. An empty file here disables it, and the banner says
    # so on every run.
    # Set BEFORE the branch, not inside it: `set -u` turns an unset `_rel` into a hard error on the
    # withdrawn-release path, which is the one path where this check must keep working. Its own
    # selftest found that -- mode 6 is the only caller that reaches it.
    _rel=
    if grep -q 'EVERY fenced path released to LOCAL agents' "$_fence_src" 2>/dev/null; then
        _rel=$(grep -o '2026-[0-9][0-9]-[0-9][0-9] — EVERY fenced path released to LOCAL agents' "$_fence_src" 2>/dev/null | head -1 | cut -c1-10)
        [ -n "$_rel" ] || _rel='an undated'
        printf '%s' "$FENCE_DOC's $_rel release" > "$tmp/release.txt"
    else
        : > "$tmp/release.txt"
    fi

    # THE POST-RELEASE CODEX GRANTS, and they are the one thing that makes a fenced path LIVE
    # again. The release entry says so itself: it "says nothing about Codex resuming -- if a Codex
    # agent starts work again, the fenced block still governs it and a fresh conflict must be
    # re-measured rather than assumed from this entry." A grant written AFTER the release is that
    # fresh conflict, so a ledger entry waiting on one of those paths is waiting on a LIVE WRITER
    # and is not stale. Measured the day after this shipped: `993cc30a` granted
    # CadenceTests/CadencePendingChangePersistenceTests.swift to Codex for T-3260, which this
    # check had flagged the hour before; without this arm it stays flagged and is wrong.
    # Sections are dated `### <date> — ... granted to Codex ...`; every backticked path inside one
    # dated at or after the release is collected, and the Python pass matches a clause against
    # their basenames as well as their paths, because the ledger writes
    # `CadencePendingChangePersistenceTests:218` where the grant writes the full path.
    # Read off the BULLET LINES of a grant section and nothing else -- `- \`<path>\` -- <why>`,
    # which is the house format for a GRANTED list. A first draft read every backticked token in
    # the section that held a slash and collected 19, among them `codex/block-removal-finish`,
    # `docs/TODO.md` and `claude/*` out of the surrounding prose; suppressing on those silenced 15
    # of 13 findings, which is the shape of a guard that has quietly switched itself off.
    awk -v rel="$_rel" '
        /^### / { d = ""
                  if (match($0, /20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) d = substr($0, RSTART, RLENGTH)
                  ing = (($0 ~ /granted to Codex/ || $0 ~ /granted RETROACTIVELY/) \
                         && rel != "" && d != "" && d >= rel)
                  next }
        ing && /^- / { n = split($0, part, "`")
                       for (i = 2; i <= n; i += 2)
                           if (part[i] ~ /^[A-Za-z0-9_][A-Za-z0-9_.\/-]*\.(swift|txt|md|plist|yml)$/) print part[i] }
    ' "$_fence_src" 2>/dev/null | sort -u > "$tmp/granted.txt" || : > "$tmp/granted.txt"

    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes > "$tmp/refs.txt" 2>/dev/null \
        || : > "$tmp/refs.txt"

    # THE DIRTY SET, and WHICH TREE it is read from. The claim a ledger entry makes is about the
    # SHARED checkout that `agent-commit.sh` stages whole files from -- not about this worktree,
    # which is one agent's private copy and clean by construction for anybody else's file. So the
    # main worktree is the one asked, and `git worktree list --porcelain` names it first.
    : > "$tmp/dirty.txt"
    dirty_mode=read
    if [ -n "${GITHUB_ACTIONS:-}${CI:-}" ]; then
        dirty_mode=skipped-in-ci
    elif [ -n "$rev" ]; then
        dirty_mode=skipped-for-a-rev
    else
        _main=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
        [ -n "$_main" ] || _main=$root
        git -C "$_main" status --porcelain 2>/dev/null | sed 's/^...//' | sed 's/^.* -> //' > "$tmp/dirty.txt" \
            || : > "$tmp/dirty.txt"
    fi

    printf '%s\n' "$PY_PROG" | python3 -I - \
        "$tmp/todo.md" "$tmp/done.md" "$tmp/fence.txt" "$tmp/refs.txt" "$tmp/dirty.txt" \
        "$tmp/release.txt" "$dirty_mode" "$tmp/granted.txt" > "$tmp/records.txt" || exit 3

    report "$tmp/records.txt" "$mode" "$dirty_mode" "$tmp/release.txt"
}

report() {  # $1 = records, $2 = strict|report, $3 = dirty mode, $4 = the release file
    _mode=$2; _dirty=$3
    _entries=0; _active=0; _scanned=0; _fence=0; _findings=0
    _body=""; _arms=""; _skips=""
    _us=$(printf '\037')
    while IFS="$_us" read -r _k _a _b _c _d _e _f _g; do
        case "$_k" in
            F) _body="$_body$(printf '  %-22s %-8s %-10s %s\n      why:      %s\n      command:  %s\n      clause:   ...%s...' \
                   "$_c" "$_b" "$_a" "$_d" "$_e" "$_f" "$_g")
" ;;
            S) _arms="$_arms$(printf '  %-24s %s clause(s) scanned' "$_a" "$_b")
" ;;
            K) _skips="$_skips$(printf '  %-52s %s' "$_a" "$_b")
" ;;
            N) _entries=$_a; _active=$_b; _scanned=$_c; _fence=$_d; _findings=$_e ;;
        esac
    done < "$1"

    [ -n "$_body" ] && printf '%s' "$_body"

    # NON-VACUITY, and it is the reason the floors exist at all. A rotted regex, a renamed ledger
    # and a shallow checkout all look exactly like a clean ledger from here: zero findings, exit 0.
    # So a run that READ too little refuses rather than reassuring -- the same shape
    # ledger-lag-check.sh's LEDGER-LAG-VACUOUS has, and T-1282's iOS gate that compiled nothing and
    # T-1291's canary that had stopped guarding are the two this repository has already paid for.
    # The third floor, clauses SCANNED, is the one that catches a pattern that stopped matching,
    # which neither of the first two would.
    if [ "$_entries" -lt "$MIN_ENTRIES" ] || [ "$_active" -lt "$MIN_ACTIVE" ] \
       || [ "$_scanned" -lt "$MIN_SCANNED" ] || [ "$_fence" -lt "$MIN_FENCE" ]; then
        printf 'ledger-blocker: %d entries, %d active, %d clause(s) scanned, %d fence pattern(s), %d finding(s)\n' \
            "$_entries" "$_active" "$_scanned" "$_fence" "$_findings"
        refuse BLOCKER-CHECK-VACUOUS "this run read too little to mean anything -- $_entries entries (floor $MIN_ENTRIES), $_active active (floor $MIN_ACTIVE), $_scanned clauses scanned (floor $MIN_SCANNED), $_fence fence patterns (floor $MIN_FENCE).
  A renamed ledger, a rotted clause pattern or an emptied fence all look like a clean sweep here." 4
    fi

    # THE DENOMINATORS, PRINTED ON EVERY RUN, GREEN OR NOT. T-1343 is the whole reason: a check
    # whose evidence only a FAILURE produces proves nothing when it is quiet, and T-1350's
    # toleration went 13 days unread because nothing reported what it had tolerated. A run that
    # scanned no clause is then visibly different from a run that scanned 38 and agreed with them.
    printf 'ledger-blocker: %d entries, %d active, %d clause(s) scanned, %d fence pattern(s), %d finding(s)\n' \
        "$_entries" "$_active" "$_scanned" "$_fence" "$_findings"
    [ -n "$_arms" ] && printf '%s' "$_arms"
    if [ -s "$4" ]; then
        printf '  lease arm reads:         %s\n' "$(cat "$4")"
    else
        printf '  lease arm DISABLED:      %s records no release of the fenced paths to local agents,\n                           so a lease blocker in the ledger may well still be true.\n' "$FENCE_DOC"
    fi
    case "$_dirty" in
        read) printf '  dirty arm read:          the main checkout, via git status --porcelain\n' ;;
        skipped-in-ci) printf '  dirty arm SKIPPED:       GITHUB_ACTIONS/CI is set and a fresh clone is clean for EVERY\n                           path, so every dirty claim would flag. It is not evaluated here.\n' ;;
        skipped-for-a-rev) printf '  dirty arm SKIPPED:       a <rev> was given; a past tree has no working-copy state to read.\n' ;;
    esac
    [ -n "$_skips" ] && { printf 'declined:\n'; printf '%s' "$_skips"; }

    [ "$_findings" -gt 0 ] || return 0

    printf 'NOTICE (LEDGER-BLOCKER-EXPIRED): %d ledger entry/entries name a blocker that no longer holds.\n' "$_findings" >&2
    printf '  Each line above names the entry, the clause and the command that disproves it. This is a\n' >&2
    printf '  NOTICE: nothing is failing and the run still passes. A ledger entry is prose written by many\n' >&2
    printf '  hands, the finding is AMBIENT rather than caused by the commit under test, and the repair is\n' >&2
    printf '  editing a sentence -- three reasons a code gate should not be able to demand it. Repair it by\n' >&2
    printf '  rewriting the blocker clause on the entry, or by recording why it still holds; --strict\n' >&2
    printf '  refuses BLOCKER-STALE with exit 3 for a caller that wants the harder contract.\n' >&2
    [ "$_mode" = strict ] || return 0
    printf 'REFUSED (BLOCKER-STALE): %d entry/entries parked on a condition that no longer exists.\n' "$_findings" >&2
    return 3
}

# The dispatch, as a function ABOVE the selftest marker and called from the file's last line.
# `CadenceGuardScriptSelftestTests.everyRefusalTheScriptsMakeIsStillInducedByTheirOwnSelftest`
# splits this file on that marker and demands every refusal name appear in BOTH halves; a refusal
# written inline in a trailing dispatch is below the split and would be counted as named by the
# selftest alone, which is the exact hollowness that test exists to catch.
main() {
    _mode=report
    _rev=
    for _arg in "$@"; do
        case "$_arg" in
            --strict) _mode=strict ;;
            -h|--help) sed -n '2,6p' "$SELF_PATH"; return 0 ;;
            -*) refuse BLOCKER-UNKNOWN-OPTION "no such option: $_arg" 2 ;;
            *) _rev=$_arg ;;
        esac
    done
    run_check "$_rev" "$_mode"
}

# --- selftest ----------------------------------------------------------------
# A throwaway repository under $TMPDIR, so this says nothing about -- and does nothing to -- the
# checkout it is run from, and is safe alongside siblings committing in it. Under two seconds.
pass=0; fail=0
# $1 = actual exit, $2 = expected exit, $3 = the output, $4 = label, $5.. = substrings the output
# must contain. Both halves are required: an exit code alone would pass a refusal that fired for
# the wrong reason, and a needle alone would pass a script that printed it and exited 0. Needles
# arrive as separate words rather than as one glob because this file is run by /bin/sh here and
# could be handed to /bin/zsh -f, and zsh does not word-split or re-expand an unquoted parameter --
# a `case $pattern` reading passed under sh and matched nothing under zsh.
check() {
    _rc=$1; _exp=$2; _out=$3; _label=$4
    shift 4
    ok=1
    [ "$_rc" = "$_exp" ] || ok=0
    for _needle in "$@"; do
        case "$_out" in *"$_needle"*) ;; *) ok=0 ;; esac
    done
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); printf '   ok   %s\n' "$_label"
    else fail=$((fail + 1)); printf '   FAIL %s\n        wanted exit %s containing [%s]; got exit %s:\n        %s\n' "$_label" "$_exp" "$*" "$_rc" "$_out"; fi
}
# The inverse: the output must NOT contain the needle. Every arm here is only worth having if it
# stays QUIET on the controls, so half this selftest is absences and they are asserted, not assumed.
check_absent() {
    _rc=$1; _exp=$2; _out=$3; _label=$4
    shift 4
    ok=1
    [ "$_rc" = "$_exp" ] || ok=0
    for _needle in "$@"; do
        case "$_out" in *"$_needle"*) ok=0 ;; *) ;; esac
    done
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); printf '   ok   %s\n' "$_label"
    else fail=$((fail + 1)); printf '   FAIL %s\n        wanted exit %s WITHOUT [%s]; got exit %s:\n        %s\n' "$_label" "$_exp" "$*" "$_rc" "$_out"; fi
}

cmd_selftest() {
    ws=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ledger-blocker-selftest-XXXXXX") || exit 3
    trap 'rm -rf "$ws"' EXIT INT TERM
    echo "== ledger-blocker-check.sh selftest =="

    # Floors scaled to a fixture rather than to this repository. The SHIPPED floors are proved in
    # mode 8 with the overrides removed, which is the half that would otherwise go untested.
    CADENCE_BLOCKER_MIN_ENTRIES=1
    CADENCE_BLOCKER_MIN_ACTIVE=1
    CADENCE_BLOCKER_MIN_SCANNED=1
    CADENCE_BLOCKER_MIN_FENCE=1
    export CADENCE_BLOCKER_MIN_ENTRIES CADENCE_BLOCKER_MIN_ACTIVE CADENCE_BLOCKER_MIN_SCANNED CADENCE_BLOCKER_MIN_FENCE
    # The dirty arm reads a real working tree, and GITHUB_ACTIONS/CI would skip it -- so it is
    # cleared for the fixture runs and set back deliberately in mode 6, where the SKIP is the
    # property under test. A selftest that silently lost an arm in CI is the hollow shape this
    # whole family of tests exists to refuse.
    unset GITHUB_ACTIONS CI 2>/dev/null || :

    repo="$ws/repo"; mkdir -p "$repo/docs" "$repo/Cadence"
    (
        cd "$repo" || exit 1
        git init -q .
        git config user.name selftest
        git config user.email selftest@example.com
        git config commit.gpgsign false
    ) || { echo "   FAIL could not create the fixture repository"; exit 1; }

    ledger() { printf '%s\n' "$@" > "$repo/docs/TODO.md"; }
    fence_doc() { printf '%s\n' "$@" > "$repo/docs/CODEX_WORKTREE.md"; }
    commit() { ( cd "$repo" && git add -A . && git commit -q -m "$1" ); }
    run() { ( cd "$repo" && sh "$SELF_PATH" "$@" 2>&1 ); }

    # The fence and the release, in the two halves this check must never confuse: a machine-read
    # block that governs CODEX, and prose beside it admitting LOCAL agents.
    FENCED_RELEASED='# Codex Worktree Protocol
```lease
Cadence/Leased*.swift
Cadence/Shared/LeasedHelper.swift
```
### 2026-10-19 — one path granted to Codex BEFORE the release below

**GRANTED:**

- `Cadence/Shared/LeasedHelper.swift` — granted the day before the blanket release superseded it.

### 2026-10-20 — EVERY fenced path released to LOCAL agents, on the owner'"'"'s decision
A local agent may now write ANY path the fenced block matches, without asking for a per-path grant.
The fenced block itself is deliberately UNTOUCHED: it governs CODEX, not a local agent.

### 2026-10-21 — one path granted to Codex for a resumed pass, after the release above

**GRANTED, scoped to that pass and nothing else:**

- `Cadence/LeasedGranted.swift` — Codex is writing it right now.'
    FENCED_NOT_RELEASED='# Codex Worktree Protocol
```lease
Cadence/Leased*.swift
Cadence/Shared/LeasedHelper.swift
```
No release of the fenced paths has been recorded.'
    printf '%s\n' "$FENCED_RELEASED" > "$repo/docs/CODEX_WORKTREE.md"

    # A branch the ledger can legitimately name, and a dirty path it can legitimately hold.
    printf 'let seed = 0\n' > "$repo/Cadence/Seed.swift"
    ledger '# ledger' '' '## Open — decided, not started' '' '- [T-1] **A seed entry.**'
    commit "seed: the fixture"
    ( cd "$repo" && git branch codex/live-branch ) >/dev/null 2>&1

    # --- mode 1: the lease arm ----------------------------------------------
    # EVERY REFUSAL AND NOTICE THIS SCRIPT MAKES IS NAMED IN A MODE BANNER, printed on a GREEN run.
    # T-1343: `complaints(requiring:)` reads needles out of the selftest's OUTPUT, and `check` only
    # echoes its needles when a check FAILS -- so a passing run that named its modes nowhere would
    # satisfy the test while proving almost nothing. The banners are what make the reading honest.
    echo; echo " mode 1 (BLOCKER-LEASE-RELEASED, LEDGER-BLOCKER-EXPIRED) -- a lease blocker, against the release"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **PARTIAL 2026-10-10 (agent `a`) — the macOS half is LEASE-BLOCKED and was not touched.** `Cadence/Shared/LeasedHelper.swift` is still on the lease.' \
        '- [T-11] **An entry with no blocker clause at all.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a LEASE-BLOCKED clause on an active entry is a finding" \
        BLOCKER-LEASE-RELEASED T-10 "Cadence/Shared/LeasedHelper.swift"
    check "$rc" 0 "$out" "and the fence is matched with fnmatch, so the printed reason is the right one" \
        "the fence matches Cadence/Shared/LeasedHelper.swift"
    check "$rc" 0 "$out" "it is a NOTICE and the run still passes" LEDGER-BLOCKER-EXPIRED

    # A NON-EMPTY FENCE IS NOT A BLOCKER FOR A LOCAL AGENT, and the glob is the thing that says so.
    # A path the fence does not match was never Codex'"'"'s to hold, so the claim is wrong for a
    # DIFFERENT reason and must print a different sentence -- otherwise the arm is a slogan.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-12] **OPEN 2026-10-10 (agent `b`) — LEASE-BLOCKED on `Cadence/Unfenced.swift`, which is what it waits on.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a path the fence does not match is flagged with its own reason" \
        BLOCKER-LEASE-RELEASED T-12 "the fence matches none of Cadence/Unfenced.swift"

    # --- mode 2: the branch arm ---------------------------------------------
    echo; echo " mode 2 (BLOCKER-BRANCH-GONE) -- a named branch that no ref resolves"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-20] **OPEN 2026-10-10 (agent `c`) — blocked on `codex/no-such-branch` landing first.**' \
        '- [T-21] **OPEN 2026-10-10 (agent `d`) — blocked on `codex/live-branch` landing first.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a blocker naming a branch no ref resolves is a finding" \
        BLOCKER-BRANCH-GONE T-20 codex/no-such-branch
    check_absent "$rc" 0 "$out" "and a branch that still exists is not" T-21

    # --- mode 3: the dirty arm ----------------------------------------------
    echo; echo " mode 3 (BLOCKER-PATH-CLEAN) -- a path called dirty that git status says is clean"
    printf 'let dirty = 1\n' >> "$repo/Cadence/Seed.swift"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-30] **OPEN 2026-10-10 (agent `e`) — `Cadence/Clean.swift` is dirty under agent `f`, so it was left alone.**' \
        '- [T-31] **OPEN 2026-10-10 (agent `g`) — `Cadence/Seed.swift` is dirty under agent `h`, so it was left alone.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a path called dirty with no uncommitted change is a finding" \
        BLOCKER-PATH-CLEAN T-30 Cadence/Clean.swift
    check_absent "$rc" 0 "$out" "and a path that really is dirty in the main checkout is not" T-31
    ( cd "$repo" && git checkout -q -- Cadence/Seed.swift )

    # --- mode 4: the ticket arm ---------------------------------------------
    echo; echo " mode 4 (BLOCKER-TICKET-CLOSED) -- a blocking ticket that has since closed"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-40] **OPEN 2026-10-10 (agent `i`) — waiting on [[T-900]] before anything can be built here.**' \
        '- [T-41] **OPEN 2026-10-10 (agent `j`) — waiting on [[T-901]] before anything can be built here.**' \
        '- [T-42] **OPEN 2026-10-10 (agent `k`) — blocked by [[T-900]] while the owner'"'"'s Xcode may be open.**' \
        '- [T-900] **CLOSED 2026-10-11 (`abc1234`) — done.**' \
        '- [T-901] **Still open, and nothing closes it.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a blocker naming a ticket that now reads CLOSED is a finding" \
        BLOCKER-TICKET-CLOSED T-40 T-900
    check_absent "$rc" 0 "$out" "and one naming a ticket that is still open is not" T-41
    check_absent "$rc" 0 "$out" "nor is a CLOSED ticket cited as a STANDING CONDITION (T-2020)" T-42

    # --- mode 5: the controls -----------------------------------------------
    # Every way a blocker clause is legitimately NOT a finding. This is the half that decides
    # whether anybody still has this check switched on in a week.
    echo; echo " mode 5 (the controls) -- every way a blocker clause is legitimately not a finding"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-10-11 (`abc1234`) — it was LEASE-BLOCKED while it was open.** `Cadence/Shared/LeasedHelper.swift`' \
        '- [T-51] **PARTIAL 2026-10-21 (agent `l`) — the current state, with no blocker.** **Earlier:** **OPEN 2026-10-10 — LEASE-BLOCKED on `Cadence/Shared/LeasedHelper.swift`.**' \
        '- [T-52] **OPEN 2026-10-10 (agent `m`) — it was LEASE-BLOCKED, and the coordinator grant unblocked it.**' \
        '- [T-53] **OPEN 2026-10-21 (agent `n`) — LEASE-BLOCKED, but `b537dd50` released every fenced path to local agents, so this is already retired.**' \
        '- [T-54] **OPEN 2026-10-10 (agent `o`) — LEASE-BLOCKED and still waiting.**' \
        '- [T-57] **OPEN 2026-10-21 (agent `x`) — LEASE-BLOCKED on `Cadence/LeasedGranted.swift`, which Codex holds.**' \
        '- [T-56] **OPEN 2026-10-21 (agent `w`) — a sweep. First: [[T-54]] is LEASE-BLOCKED on `Cadence/Shared/LeasedHelper.swift`, filed 2026-10-10 by an agent that stopped, re-read here against the fence, the branch inventory and the four worktrees that could plausibly still hold the path, none of which does, and none of which has an unlanded commit touching it either, so the only thing left to say about it is the one sentence that follows. Every one of them is retired by `b537dd50`, which released every fenced path to LOCAL agents.**' \
        '' '## Done' '' '- [T-55] **A done entry that says it is LEASE-BLOCKED and carries no marker.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "the live entry among the controls is still found, so this mode is not vacuous" \
        BLOCKER-LEASE-RELEASED T-54
    check_absent "$rc" 0 "$out" "a CLOSED entry's blocker clause is history, not a claim" T-50
    check_absent "$rc" 0 "$out" "a clause demoted under **Earlier:** is prose a later pass overtook" T-51
    check_absent "$rc" 0 "$out" "a clause that retires its own blocker in the same sentence is not one" T-52
    check_absent "$rc" 0 "$out" "an entry that CITES the release NEXT TO the clause is retired by that" T-53
    # The same suppression, with the citation OUT OF REACH of the clause window -- which is
    # T-3296's real shape: a sweep that quotes eleven blocker clauses in order to retire them, and
    # names the release once, at the end. The window-local RETIRED reading cannot see that far, so
    # this check is the only thing holding the entry-wide CITES_RELEASE suppression up. Without it
    # the one entry that did the work is the loudest finding on the run.
    check_absent "$rc" 0 "$out" "nor one that cites it BEYOND the clause window (T-3296's shape)" T-56
    check_absent "$rc" 0 "$out" "and an entry under ## Done is not active" T-55
    # THE ARM THE RELEASE ENTRY ITSELF ASKS FOR. That entry says it "says nothing about Codex
    # resuming -- if a Codex agent starts work again, the fenced block still governs it and a fresh
    # conflict must be re-measured rather than assumed from this entry." A grant written AFTER the
    # release is that fresh conflict: the path is held by a LIVE WRITER, not by a fence nobody is
    # behind, so the entry waiting on it is RIGHT. Measured the day this shipped -- `993cc30a`
    # granted CadenceTests/CadencePendingChangePersistenceTests.swift to Codex for [[T-3260]],
    # which this check had flagged an hour earlier.
    check_absent "$rc" 0 "$out" "a path granted to Codex AFTER the release is held by a live writer" T-57
    # And the DATE is what makes that arm narrow rather than a blanket silence: this document has
    # 2026-10-17 and 2026-10-19 grant sections too, and every one of them is SUPERSEDED by the
    # blanket release for a local agent. `Cadence/Shared/LeasedHelper.swift` is granted to Codex
    # in a PRE-release section of the fixture and is the path T-54 above waits on -- so a grant arm
    # that ignored the date would silence T-54, which is the only live finding in this mode. The
    # mutation is the proof: deleting the date comparison turns the T-54 check red, and nothing
    # else in the suite notices.
    check "$rc" 0 "$out" "but a PRE-release grant is superseded by it and silences nothing" \
        BLOCKER-LEASE-RELEASED T-54

    # --- mode 6: the two arms that must DISABLE rather than guess ------------
    echo; echo " mode 6 (BLOCKER-LEASE-RELEASED, BLOCKER-PATH-CLEAN) -- the arms that DISABLE rather than guess"
    # If the release prose is ever withdrawn -- which the release entry itself names as the case
    # when Codex resumes -- every claim the lease arm flags becomes TRUE again. It must go quiet,
    # and it must SAY it has gone quiet, or a silent run reads as a clean ledger.
    printf '%s\n' "$FENCED_NOT_RELEASED" > "$repo/docs/CODEX_WORKTREE.md"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-60] **OPEN 2026-10-10 (agent `p`) — LEASE-BLOCKED on `Cadence/Shared/LeasedHelper.swift`.**' \
        '- [T-61] **OPEN 2026-10-10 (agent `q`) — blocked on `codex/no-such-branch` landing first.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a withdrawn release DISABLES the lease arm and says so" \
        "lease arm DISABLED" "may well still be true"
    check_absent "$rc" 0 "$out" "so the lease claim is not flagged" T-60
    check "$rc" 0 "$out" "and the other arms keep working over the same ledger" BLOCKER-BRANCH-GONE T-61
    printf '%s\n' "$FENCED_RELEASED" > "$repo/docs/CODEX_WORKTREE.md"

    # A GitHub Actions checkout is a fresh clone: clean for EVERY path, so every dirty claim would
    # flag. The arm must skip and print its skip rather than answer a cheaper question than the
    # one being asked.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-62] **OPEN 2026-10-10 (agent `r`) — `Cadence/Clean.swift` is dirty under agent `s`.**' \
        '- [T-63] **OPEN 2026-10-10 (agent `t`) — LEASE-BLOCKED on `Cadence/Shared/LeasedHelper.swift`.**'
    out=$( cd "$repo" && GITHUB_ACTIONS=true sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 0 "$out" "in CI the dirty arm SKIPS and prints why" "dirty arm SKIPPED" GITHUB_ACTIONS
    check_absent "$rc" 0 "$out" "so a fresh clone cannot flag every dirty claim at once" T-62
    check "$rc" 0 "$out" "and the arms that CAN run in CI still do" BLOCKER-LEASE-RELEASED T-63

    # --- mode 7: the refusals -----------------------------------------------
    echo; echo " mode 7 (BLOCKER-NOT-REPO-ROOT, BLOCKER-UNKNOWN-OPTION, BLOCKER-FENCE-UNREADABLE,"
    echo "         BLOCKER-FENCE-EMPTY, BLOCKER-CHECK-VACUOUS) -- refuse rather than reassure"
    out=$( cd "$ws" && sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 3 "$out" "outside a repository it refuses rather than reading nothing" BLOCKER-NOT-REPO-ROOT

    out=$(run --no-such-flag); rc=$?
    check "$rc" 2 "$out" "an unknown option is refused rather than read as a rev" BLOCKER-UNKNOWN-OPTION

    mv "$repo/docs/CODEX_WORKTREE.md" "$repo/docs/CODEX_WORKTREE.md.away"
    out=$(run); rc=$?
    check "$rc" 4 "$out" "a missing protocol document is a refusal, not an empty fence" \
        BLOCKER-FENCE-UNREADABLE
    mv "$repo/docs/CODEX_WORKTREE.md.away" "$repo/docs/CODEX_WORKTREE.md"

    # codex-land.sh:62'"'"'s argument restated: an empty lease reads exactly like a lease that allows
    # everything, and it allows nothing. Handed one, this arm would call every fenced path unfenced
    # and print the wrong sentence for every finding it made.
    fence_doc '# Codex Worktree Protocol' '```lease' '```' \
        '### 2026-10-20 — EVERY fenced path released to LOCAL agents'
    out=$(run); rc=$?
    check "$rc" 4 "$out" "an EMPTY lease block is refused, never read as nothing fenced" BLOCKER-FENCE-EMPTY
    printf '%s\n' "$FENCED_RELEASED" > "$repo/docs/CODEX_WORKTREE.md"

    mv "$repo/docs/TODO.md" "$repo/docs/TODO.md.away"
    out=$(run); rc=$?
    check "$rc" 4 "$out" "a missing ledger is a refusal, not a clean sweep" BLOCKER-CHECK-VACUOUS
    mv "$repo/docs/TODO.md.away" "$repo/docs/TODO.md"

    # --- mode 8: the SHIPPED floors, with the overrides removed -------------
    # The half that would otherwise go untested. A rotted clause pattern, a renamed ledger and a
    # shallow checkout all look identical from here -- zero findings, exit 0 -- so the floors are
    # what tells a quiet run from a blind one, and they are proved at their real values.
    echo; echo " mode 8 (BLOCKER-CHECK-VACUOUS, BLOCKER-STALE) -- the shipped floors, and the strict contract"
    out=$( cd "$repo" && env -u CADENCE_BLOCKER_MIN_ENTRIES -u CADENCE_BLOCKER_MIN_ACTIVE \
             -u CADENCE_BLOCKER_MIN_SCANNED -u CADENCE_BLOCKER_MIN_FENCE \
             sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 4 "$out" "the SHIPPED floors refuse this fixture, so they are not decoration" \
        BLOCKER-CHECK-VACUOUS "floor 300"

    # The exit contract, both halves. The default REPORTS -- a ledger entry is prose and an ambient
    # finding must not redden an unrelated agent'"'"'s run -- and --strict is there for the day the
    # owner decides otherwise, so adopting it is a workflow edit rather than a rewrite.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-80] **OPEN 2026-10-10 (agent `u`) — LEASE-BLOCKED on `Cadence/Shared/LeasedHelper.swift`.**'
    out=$(run); rc=$?
    check "$rc" 0 "$out" "the default REPORTS: a finding does not fail the run" \
        LEDGER-BLOCKER-EXPIRED "1 finding(s)"
    out=$(run --strict); rc=$?
    check "$rc" 3 "$out" "--strict refuses the same finding with exit 3" BLOCKER-STALE

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-81] **OPEN 2026-10-10 (agent `v`) — blocked on `codex/live-branch`, which still exists.**'
    out=$(run --strict); rc=$?
    check "$rc" 0 "$out" "and --strict is silent when every blocker still holds" "0 finding(s)"

    # --- mode 9: the denominator is printed on a run with nothing to report --
    # T-1343. A check whose evidence only a FAILURE produces proves nothing when it is quiet, and a
    # run that scanned NO clause must look different from one that scanned some and agreed.
    echo; echo " mode 9 (the denominator) -- printed whether or not anything is found"
    check "$rc" 0 "$out" "the clause count is printed on a clean run" "clause(s) scanned"
    check "$rc" 0 "$out" "and so is every arm's own share of it" \
        BLOCKER-LEASE-RELEASED BLOCKER-BRANCH-GONE BLOCKER-PATH-CLEAN BLOCKER-TICKET-CLOSED
    check "$rc" 0 "$out" "with the tree the dirty arm actually read" "dirty arm read"

    echo
    # The vocabulary `CadenceGuardScriptSelftestTests` reads. A tally is what a selftest gutted to
    # `return 0` cannot produce, which is why exit 0 alone is not the pin.
    echo "checks: $pass passed, $fail failed"
    [ "$fail" = 0 ] || exit 1
}

# ---------------------------------------------------------------------------
case "$0" in
    /*) SELF_PATH=$0 ;;
    *)  SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
esac

case "${1:-}" in
    selftest) cmd_selftest; exit $? ;;
esac

main "$@"
