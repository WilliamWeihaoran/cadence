#!/bin/sh
# Ask the ledger the question `agent-commit.sh` never asks (T-1298).
#
#   ./scripts/ledger-lag-check.sh [<rev>]     # default HEAD; exit 3 on a finding
#   ./scripts/ledger-lag-check.sh selftest    # prove both refusals still fire
#
# WHY THIS EXISTS
#
# `agent-commit.sh`'s `LEDGER-ID-UNFILED` reads a commit message and demands a formal `- [T-n]`
# entry for every id it names, so the ledger cannot LOSE an id. Nothing ran the other direction.
# On 2026-09-19 three tickets -- T-1269 (`00d576f`), T-626 (`e4719e3`) and T-1129 (`44eced5`) --
# were sitting in the open sections with their code landed one and two days earlier, and T-626's
# entry still read *"BLOCKED ON iOS DISTRIBUTION -- do not implement until that changes"*, a park
# its own commit quotes the owner lifting. The reasoning was never lost; it went into the commit
# message. Only the index was wrong, and the index is what the next agent reads.
#
# THE RULE, AND WHY IT IS PER-COMMIT RATHER THAN PER-ID
#
# The hard part is not the grep, it is telling "this commit CLOSED T-n" from "this commit MENTIONED
# T-n". A commit that FILES a ticket names it in exactly the same place a commit that closes one
# does, and this repository files residue tickets out of the commit that closed their parent:
#
#   bc91b2c  "T-1135 + T-1163: the clock face the app draws is the one the user set, ..."
#            closed T-1135 and FILED T-1163, which is an open question for the owner to this day.
#   af2ead3  "T-1115 + T-1116: weekKey takes the caller's zone, ..."  closed T-1115, filed T-1116.
#
# Per-id, both of those read as "an id named by a landed commit is still open" and both are false
# refusals. Per-COMMIT they do not, because the question becomes:
#
#   A commit that lands code and names ticket ids must leave AT LEAST ONE of the ids it names
#   closed in the ledger.
#
# A residue filing rides along on a commit that closed its parent, so it is accounted for. A commit
# whose whole named set is still open closed nothing it claimed -- which is the shape all three of
# the tickets above have: `e4719e3` names T-626 alone, `44eced5` names T-1129 alone, `00d576f`
# names T-1269 alone (and filed it open in the same commit, which is why a "the commit that filed
# it is exempt" reading cannot see it -- measured, that reading catches two of the three).
#
# WHAT "LANDS CODE" MEANS, and it is borrowed rather than invented: any path outside `docs/**`,
# `**/AGENTS.md`, `CLAUDE.md` and `README.md`. That is exactly `ci.yml`'s `paths-ignore` and
# exactly `docs.yml`'s `paths`, so a ledger-only or guide-only commit -- a filing, a correction, a
# reword -- is out of scope by the same definition the two workflows already use to split the work
# between them. Merge commits name no files under `--name-only` and are skipped for the same reason.
#
# WHAT "CLOSED" MEANS is `ledger_closed_ids`' reading from `agent-commit.sh`, deliberately not a
# second opinion: `CLOSED` on the entry's OWN first line. Eighty lines of that script defend the
# narrowness (a body-wide reading marks sixteen open tickets closed; widening to RESOLVED/VERIFIED
# marks two open ones closed, because this ledger uses VERIFIED to mean "confirmed real"). Three
# things are added on top of it, all of which mean "not open" here:
#
#   * an entry under `## Done` or `## Cancelled` -- 112-plus Done entries carry no marker at all;
#   * an entry that has moved to `docs/TODO_DONE.md`, which is where closed items are archived;
#   * an id with no formal entry in either ledger, which is out of reach by construction, the same
#     carve-out `LEDGER-ID-UNFILED` makes. 162 of this repository's message-only ids are T-441 or
#     below, inside the deficit T-462 measured and decided not to backfill.
#
# `## In progress` counts as OPEN, which is the strict reading of the two available. It costs
# nothing: measured over the whole history at `454e778`, both readings flag zero.
#
# SCOPED, AND SAYING SO. Ids are read from the SUBJECT only, in every shape this repository writes:
# `T-1279: ...`, `T-1289, T-1287: ...`, `T-1206 + T-1207 + T-1209: ...`, `T-1271 .. T-1278: ...`
# and `T-996..T-999: ...` (both range spellings are expanded), `T-761(a): ...`, and an id anywhere
# else in the subject (`Renumber the second T-1119 to T-1122, ...`). A subject with no id at all --
# `Tidy: ...` -- is skipped, and that is the one real gap: a commit that lands a ticket's code
# without naming it in its subject is invisible here. Reading the body instead would sweep in every
# `[[T-n]]` an explanation cites. Measured rather than waved at: over the whole history 471 of the
# 749 code-landing commits name no id in their subject, and over the last 200 commits **6 of 128**
# do -- `Tidy:`, a build-number bump, a manifest registration and three censuses, none of which has
# a ticket to close. The gap is an artefact of the era before the convention, not a live hole.
#
# IT IS STICKY, AND THAT IS THE DESIGN. A finding does not expire: the flagged commit stays flagged
# until the ledger entry carries its closure, so every push after a lagging one is red too. Replayed
# over all 1133 commits at `454e778`, the backlog this reading would have shown peaked at 29 and was
# non-zero for most of the repository's life -- it is zero at HEAD only because `8ec7565` and
# `454e778` corrected the last four by hand. Like `LEDGER-CLOSURE-BURIED` before it, this ships
# enforceable at zero rather than baselined, and the cost of that is real: a batch that defers its
# ledger closure to a follow-up commit buys one red run in between. Write the closure in the commit
# that lands the code.
#
# NON-VACUITY, which is the whole reason the floors below exist. A GitHub Actions checkout defaults
# to `fetch-depth: 1`, and this check over one commit examines nothing and exits 0 -- the exact
# failure T-1282 found in an iOS gate that compiled nothing and T-1291 found in a canary that had
# stopped guarding. So the workflows pass `fetch-depth: 0` AND this script refuses a run that read
# too little: too few commits, too few ledger entries, or too few commits actually EXAMINED. The
# third is the one that catches a rotted path predicate or a renamed ledger, which the first two
# would not. The overrides exist for the selftest's throwaway repositories; no workflow sets them.
set -u

SELF_MIN_COMMITS=${CADENCE_LEDGER_LAG_MIN_COMMITS:-200}
SELF_MIN_ENTRIES=${CADENCE_LEDGER_LAG_MIN_ENTRIES:-300}
SELF_MIN_EXAMINED=${CADENCE_LEDGER_LAG_MIN_EXAMINED:-120}

TODO_PATH=${CADENCE_LEDGER_LAG_TODO:-docs/TODO.md}
DONE_PATH=${CADENCE_LEDGER_LAG_DONE:-docs/TODO_DONE.md}

refuse() { printf 'REFUSED (%s): %s\n' "$1" "$2" >&2; exit "$3"; }

# `/usr/bin/git` is an xcrun shim and xcrun REFUSES to run inside an App Sandbox, which is where
# `CadenceGuardScriptSelftestTests` calls the selftest below from. Every git call then fails with
# that on stderr and nothing else, which reads like a broken repository. Same probe, same order and
# the same reason as `scripts/agent-commit.sh` (T-719); duplicated rather than shared because a
# guard script that needs another file to start is a guard with a new way to stop running.
if ! git --version >/dev/null 2>&1; then
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin; do
        [ -x "$_candidate/git" ] || continue
        "$_candidate/git" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; export PATH; break
    done
fi

run_check() {  # $1 = rev
    rev=$1
    root=$(git rev-parse --show-toplevel 2>/dev/null) || refuse NOT-REPO-ROOT "not inside a git repository" 3
    cd "$root" || refuse NOT-REPO-ROOT "cannot enter $root" 3

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ledger-lag-XXXXXX") || exit 3
    trap 'rm -rf "$tmp"' EXIT INT TERM

    git show "$rev:$TODO_PATH" > "$tmp/todo.md" 2>/dev/null \
        || refuse LEDGER-LAG-VACUOUS "$rev has no $TODO_PATH to read" 4
    git show "$rev:$DONE_PATH" > "$tmp/done.md" 2>/dev/null || : > "$tmp/done.md"
    git log --format='%x01%H%x1f%ad%x1f%s' --date=short --name-only "$rev" > "$tmp/log.txt" || exit 3

    awk -v min_commits="$SELF_MIN_COMMITS" \
        -v min_entries="$SELF_MIN_ENTRIES" \
        -v min_examined="$SELF_MIN_EXAMINED" \
        -v todo="$TODO_PATH" \
        "$AWK_PROG" "$tmp/todo.md" "$tmp/done.md" "$tmp/log.txt"
}

# ---------------------------------------------------------------------------
# The reading itself, as one awk pass over: TODO.md, TODO_DONE.md, the log.
# Held in a variable rather than written to a temp file: the first draft wrote one and removed it
# only on the success path, so every exit 3 and every exit 4 leaked one -- and a guard whose
# refusal path is the one that litters is a guard that gets noticed for the wrong reason.
# ---------------------------------------------------------------------------
AWK_PROG=$(cat <<'AWK'
function entry_id(line,   id) {
    id = line; sub(/^- \[/, "", id); sub(/\].*$/, "", id); return id
}
# Every `T-n` the subject names, with both range spellings expanded. A range is two ids separated
# by nothing but dots and spaces -- `T-1271 .. T-1278` and `T-996..T-999` are both written here.
function subject_ids(s,   tok, sep, prevnum, a, b, i, rest) {
    delete SID
    rest = s; prevnum = -1
    while (match(rest, /T-[0-9]+/)) {
        tok = substr(rest, RSTART, RLENGTH)
        sep = substr(rest, 1, RSTART - 1)
        b = substr(tok, 3) + 0
        if (prevnum >= 0 && sep ~ /^ *\.\.+ *$/) {
            a = prevnum
            if (b > a && b - a <= 64) for (i = a + 1; i < b; i++) SID["T-" i] = 1
        }
        SID[tok] = 1
        prevnum = b
        rest = substr(rest, RSTART + RLENGTH)
    }
}
function is_code(p) {
    if (p == "") return 0
    if (p ~ /^docs\//) return 0
    if (p ~ /(^|\/)AGENTS\.md$/) return 0
    if (p == "CLAUDE.md" || p == "README.md") return 0
    return 1
}
# One commit's verdict. `known` is the subject ids that have a formal entry; a commit is flagged
# when it landed code, named at least one known id, and every one of them is still open.
function verdict(   id, known, openn, list) {
    if (c_sha == "") return
    commits++
    if (c_code == 0) return
    known = 0; openn = 0; list = ""
    for (id in c_ids) {
        if (!(id in filed)) continue
        known++
        if (id in openi) { openn++; list = list " " id }
    }
    if (known == 0) return
    examined++
    if (known == openn) {
        findings++
        printf "  %s  %s %-24s %s\n", substr(c_sha, 1, 7), c_date, substr(list, 2), c_subj
    }
}

FNR == 1 { part++ }

# An id is open only while NO entry of it is closed -- `ledger_closed_ids`' reading, which collects
# a SET of ids over every entry and is why the commit-path note T-1300 added never had this defect
# (T-1303). Reading "open" off whichever entry happened to be last made a DOUBLE-ALLOCATED id flag
# its own closing commit: at `dcb0a15`, `docs/TODO.md` held two formal `- [T-1043]` entries, one
# closed and one open (T-1072's concurrent-allocation residue), and that commit closed T-1043 on the
# entry's own first line -- the exact discipline this check exists to enforce -- and was flagged
# anyway, in both entry orders. It reads zero at HEAD only because the duplicate was renumbered by
# hand; LEDGER-ID-DUPLICATE makes new duplicates rare rather than impossible, and two ids were
# double-allocated by concurrent agents on 2026-09-20 alone. Two OPEN entries for one id are still
# open: this narrows nothing but the duplicate.
part == 1 {
    if ($0 ~ /^## /) sec = $0
    if ($0 ~ /^- \[T-[0-9]+\]/) {
        id = entry_id($0); filed[id] = 1; entries++
        if (sec ~ /^## (Done|Cancelled)/ || $0 ~ /CLOSED/) {   # the entry's OWN first line
            closedi[id] = 1; delete openi[id]; next
        }
        if (!(id in closedi)) openi[id] = 1
    }
    next
}

part == 2 {
    if ($0 ~ /^- \[T-[0-9]+\]/) { id = entry_id($0); filed[id] = 1; entries++; closedi[id] = 1; delete openi[id] }
    next
}

part == 3 {
    if (substr($0, 1, 1) == "\001") {
        verdict()
        n = split(substr($0, 2), f, "\037")
        c_sha = f[1]; c_date = f[2]; c_subj = (n >= 3) ? f[3] : ""
        c_code = 0
        subject_ids(c_subj)
        delete c_ids
        for (k in SID) c_ids[k] = 1
        next
    }
    if ($0 != "" && is_code($0)) c_code++
    next
}

END {
    verdict()
    printf "ledger-lag: %d commits, %d ledger entries, %d examined, %d findings\n",
        commits, entries, examined, findings
    if (commits < min_commits || entries < min_entries || examined < min_examined) {
        printf "REFUSED (LEDGER-LAG-VACUOUS): this run read too little to mean anything -- %d commits (floor %d), %d entries (floor %d), %d examined (floor %d).\n  A shallow checkout, a renamed ledger or a rotted path predicate all look like a pass here.\n",
            commits, min_commits, entries, min_entries, examined, min_examined > "/dev/stderr"
        exit 4
    }
    if (findings > 0) {
        printf "REFUSED (LEDGER-CLOSURE-LAGGED): %d commit(s) landed code under ticket ids and closed none of them in the ledger.\n  Every id each commit names is still open in %s. Either write the closure on the entry's own\n  first line (`- [T-n] **CLOSED <date> (`<sha>`) -- ...`), or, if the ticket is legitimately still\n  open, make the commit name an id it did close.\n",
            findings, todo > "/dev/stderr"
        exit 3
    }
    exit 0
}
AWK
)

# --- selftest ----------------------------------------------------------------
# A throwaway repository under $TMPDIR, so this says nothing about -- and does nothing to -- the
# checkout it is run from, and is safe alongside siblings committing in it. About a second.
pass=0; fail=0
# $1 = actual exit, $2 = expected exit, $3 = the output, $4 = label, $5.. = substrings the output
# must contain. Both halves are required: an exit code alone would pass a refusal that fired for the
# wrong reason, and a needle alone would pass a script that printed it and exited 0. Needles arrive
# as separate words rather than as one glob because this file is run by `/bin/sh` here and by
# `/bin/zsh -f` from `CadenceGuardScriptSelftestTests`, and zsh does not word-split or re-expand an
# unquoted parameter -- a `case $pattern` reading passed under sh and matched nothing under zsh.
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

cmd_selftest() {
    ws=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ledger-lag-selftest-XXXXXX") || exit 3
    trap 'rm -rf "$ws"' EXIT INT TERM
    echo "== ledger-lag-check.sh selftest =="

    # Floors scaled to a fixture rather than to this repository. The SHIPPED floors are proved in
    # mode 4 with the overrides removed, which is the half that would otherwise go untested.
    CADENCE_LEDGER_LAG_MIN_COMMITS=1
    CADENCE_LEDGER_LAG_MIN_ENTRIES=1
    CADENCE_LEDGER_LAG_MIN_EXAMINED=1
    export CADENCE_LEDGER_LAG_MIN_COMMITS CADENCE_LEDGER_LAG_MIN_ENTRIES CADENCE_LEDGER_LAG_MIN_EXAMINED

    repo="$ws/repo"; mkdir -p "$repo/docs" "$repo/Cadence"
    (
        cd "$repo" || exit 1
        git init -q .
        git config user.name selftest
        git config user.email selftest@example.com
        git config commit.gpgsign false
    ) || { echo "   FAIL could not create the fixture repository"; exit 1; }

    ledger() { printf '%s\n' "$@" > "$repo/docs/TODO.md"; }
    archive() { printf '%s\n' "$@" > "$repo/docs/TODO_DONE.md"; }
    land() {  # $1 = subject, $2 = path, $3 = content
        printf '%s\n' "$3" > "$repo/$2"
        ( cd "$repo" && git add -A . && git commit -q -m "$1" )
    }
    amend() { ( cd "$repo" && git commit -q --amend -m "$1" ); }
    run() { ( cd "$repo" && sh "$SELF_PATH" "${1:-HEAD}" 2>&1 ); }

    OPEN_LEDGER='- [T-10] **An open finding.**'
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **An open finding.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    archive '# archive' '' '- [T-14] **CLOSED 2026-09-01 (`def5678`).**'
    land "seed: the fixture ledger" docs/SEED.md seed

    # --- mode 1: the finding ------------------------------------------------
    echo; echo " mode 1 (LEDGER-CLOSURE-LAGGED) -- code lands under an id whose entry is still open"
    land "T-10: the finding is fixed" Cadence/A.swift "let a = 1"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "a code commit naming only an open id is refused" LEDGER-CLOSURE-LAGGED T-10

    # --- mode 2: the controls ----------------------------------------------
    echo; echo " mode 2 (the controls) -- every way an id is legitimately named and not closed"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    ( cd "$repo" && git add -A . && git commit -q -m "T-10: write the closure the commit above owed" )
    out=$(run); rc=$?
    check "$rc" 0 "$out" "the same history goes silent once the entry carries its closure" 0 findings

    land "T-11: an explanation that landed no code" docs/NOTE.md note
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a docs-only commit naming an open id is not a finding"

    land "T-12 + T-11: closed one, filed the other as residue" Cadence/B.swift "let b = 2"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a commit that closed ONE of the ids it names is not a finding"

    land "T-13: an entry in Done that never carried a marker" Cadence/C.swift "let c = 3"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "an entry under ## Done counts as closed without a marker"

    land "T-14: an entry that moved to the archive" Cadence/D.swift "let d = 4"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "an entry archived in TODO_DONE.md counts as closed"

    land "T-9001: an id this ledger has never heard of" Cadence/E.swift "let e = 5"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "an id with no formal entry anywhere is out of reach, not a finding"

    land "Tidy: a subject with no id at all" Cadence/F.swift "let f = 6"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a subject naming no id is skipped"

    # --- mode 2b: the double-allocated id (T-1303) --------------------------
    # The shape nothing else in this suite builds: ONE id with TWO formal entries. Measured on
    # `dcb0a15`, which closed T-1043 on the entry's own first line in the commit that landed the
    # fix and was flagged regardless, because a second open entry for the same id existed.
    echo; echo " mode 2b (double allocation) -- an id with a closed entry is closed, whichever twin is last"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-20] **A second entry two concurrent agents allocated for the same id.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "T-20: the fix, closed on the entry's own first line in the commit that landed it" \
        Cadence/H.swift "let h = 8"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a closed entry followed by an open twin is not a finding" 0 findings

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **A second entry two concurrent agents allocated for the same id.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "docs: the same two entries, written the other way round" docs/DUP.md dup
    out=$(run); rc=$?
    check "$rc" 0 "$out" "and not a finding in the other entry order either" 0 findings

    # The control, without which the line above would pass an id that is never open.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **One open entry for the double-allocated id.**' \
        '- [T-20] **And a second open one; neither carries a closure.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "docs: both twins open, so the id really is open" docs/DUP.md dup2
    out=$(run); rc=$?
    check "$rc" 3 "$out" "two OPEN entries for one id are still open" LEDGER-CLOSURE-LAGGED T-20

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-20] **A second entry two concurrent agents allocated for the same id.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "docs: restore the closure so the modes below start from a clean history" docs/DUP.md dup3
    out=$(run); rc=$?
    check "$rc" 0 "$out" "writing the closure back clears the finding again" 0 findings

    # --- mode 3: the subject shapes this repository actually writes ---------
    echo; echo " mode 3 (subject shapes) -- ranges and separators are read, not just the bare prefix"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '- [T-15] **Open.**' '- [T-16] **Open.**' '- [T-17] **Open.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "T-15 .. T-17: decisions written down before any of them is built" Cadence/G.swift "let g = 7"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "a spaced range names every id between its ends" T-15 T-16 T-17

    amend "T-15..T-17: the same range, written without spaces"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "the unspaced range spelling reads the same" T-16

    amend "T-15, T-12: one open, one closed"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a comma-separated pair is accounted for by the closed half"

    amend "T-15(a): a suffixed id still resolves"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "a suffixed id is read as the id" T-15

    amend "Renumber the second T-15 to T-12"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "an id away from the subject prefix is read too"

    amend "T-15 + T-16: neither one closed"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "a + separated pair with nothing closed is a finding" T-15 T-16
    amend "T-12: back to a clean history"

    # --- mode 4: the floors, with the SHIPPED defaults ----------------------
    echo; echo " mode 4 (LEDGER-LAG-VACUOUS) -- a run that read too little must not pass"
    out=$( cd "$repo" && env -u CADENCE_LEDGER_LAG_MIN_COMMITS -u CADENCE_LEDGER_LAG_MIN_ENTRIES \
        -u CADENCE_LEDGER_LAG_MIN_EXAMINED sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 4 "$out" "the shipped floors refuse this small fixture outright" LEDGER-LAG-VACUOUS

    out=$( cd "$repo" && CADENCE_LEDGER_LAG_MIN_EXAMINED=9999 sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 4 "$out" "the examined floor alone refuses a run the other two would pass" LEDGER-LAG-VACUOUS

    out=$( cd "$repo" && CADENCE_LEDGER_LAG_TODO=docs/NOT_A_LEDGER.md sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 4 "$out" "a ledger path that resolves to nothing is vacuous, not clean" LEDGER-LAG-VACUOUS

    out=$( cd "$repo" && git clone -q --depth 1 "file://$repo" "$ws/shallow" && cd "$ws/shallow" \
        && env -u CADENCE_LEDGER_LAG_MIN_COMMITS -u CADENCE_LEDGER_LAG_MIN_ENTRIES \
        -u CADENCE_LEDGER_LAG_MIN_EXAMINED sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 4 "$out" "a depth-1 checkout -- the Actions default -- is refused, not passed" LEDGER-LAG-VACUOUS

    # --- mode 5: a revision argument, which is how the proof is replayed ----
    echo; echo " mode 5 (<rev>) -- the check reads the ledger AND the history of the rev it is given"
    out=$(run "HEAD~1"); rc=$?
    check "$rc" 0 "$out" "an earlier revision is readable and answers about itself" ledger-lag:

    out=$( cd "$repo" && sh "$SELF_PATH" no-such-rev 2>&1 ); rc=$?
    check "$rc" 4 "$out" "an unresolvable revision refuses rather than passing" LEDGER-LAG-VACUOUS

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
    selftest)
        cmd_selftest
        exit $?
        ;;
    -h|--help)
        sed -n '2,8p' "$0"
        exit 0
        ;;
esac

run_check "${1:-HEAD}"
