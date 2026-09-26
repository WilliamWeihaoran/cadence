#!/bin/sh
# Replay the OTHER direction of the ledger lag check over every closure this repository ever wrote
# (T-1342).
#
#   ./scripts/replay-closure-code-lag.sh                 # the table
#   ./scripts/replay-closure-code-lag.sh --list          # ...and name every flagged closure
#   ./scripts/replay-closure-code-lag.sh --era 300       # ...the parallel-agent scope only
#   ./scripts/replay-closure-code-lag.sh --root <dir>    # read a checkout other than this script's
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. The same reason as
# `scripts/replay-partial-reading.sh`, `scripts/replay-closure-reading.sh` and
# `scripts/replay-message-vs-ledger.sh`: no guard in this family may refuse until it has answered
# *how many commits this repository actually made would this have stopped*, and no widening ships
# on a number quoted in prose, because prose rots with the next commit and cannot be re-derived by
# whoever wants to widen the rule again. [[T-1300]] answered its version with 191 in 274 and took a
# warning; [[T-1304]] answered its with 4 in 511 and earned a refusal.
#
# THE QUESTION, and it is `scripts/ledger-lag-check.sh`'s mirror image. That check asks whether a
# commit that LANDS CODE left the ids it names open -- a commit that closed nothing it claimed.
# [[T-1342]] is the other direction: an id that reads CLOSED with nothing landed. It happens
# because `agent-commit.sh` stages WHOLE FILES and `docs/TODO.md` is the one file every agent
# edits, so any agent naming the ledger carries whatever else is sitting in it -- a sibling's
# closure lines for work that sibling has not committed yet. The spill is correct behaviour and
# must not be repaired by reverting; what is wrong is that nothing says it happened.
#
# WHAT A CLOSURE EVENT IS. A commit's own diff to either ledger ADDS a `- [T-n]` first line that
# carries the T-1335 closure run, or adds a `- [T-n]` entry to `docs/TODO_DONE.md` (archival is a
# closure). An entry MOVED under `## Done` without gaining a marker is not visible in an added
# line and is not counted; that undercounts the population and never invents one.
#
# WHAT "THE CODE FOR AN ID" IS, borrowed rather than invented: a commit whose SUBJECT names the id
# -- `ledger-lag-check.sh`'s `subject_ids`, both range spellings expanded -- and which touches a
# path outside `docs/**`, `**/AGENTS.md`, `CLAUDE.md` and `README.md`, which is `ci.yml`'s
# `paths-ignore`. Same two readings the shipped check already uses, so this measures the guard
# rather than a fourth opinion.
#
# THE READINGS, all of which would NEWLY REFUSE something (today this direction refuses nothing):
#
#   here          flag a closure event whose own commit lands no code naming that id.
#   hereorbefore  ...unless such a commit is already an ANCESTOR -- code first, closure later, which
#                 is the direction `ledger-lag-check.sh` already guards and is not this ticket.
#   unnamed       ...and the closure's own commit does not NAME that id in its subject. This is the
#                 spill shape itself: `agent-commit.sh` stages the whole ledger, so the closure an
#                 agent carries for a sibling is a closure its subject never mentions. Every one of
#                 [[T-1342]]'s founding cases has it.
#   anywhere      flag only when NO commit in the whole history lands code naming the id. The
#                 strictest possible excuse, and it is the disqualifying column made into a reading.
#
# THE FOUNDING CASES, checked by name rather than in aggregate, because this family has already
# adopted a reading that looked good in aggregate and was blind to the incident it was proposed for
# ([[T-1356]]'s `wholeactive`, disqualified by `988d7cb`). The four are `b358aa3`/T-1334,
# `b358aa3`/T-1339 and `e28bc87`/T-1348, `e28bc87`/T-1349. Note that [[T-1342]]'s own prose put two
# of them on `cd81288` and read `e28bc87` as carrying T-1351; the replay says otherwise, and the
# replay is reading the diffs -- `cd81288` closed T-1337 and T-1341, both its own, and the
# `- [T-1351]` line `e28bc87` added carries no closure run at all. That is the whole argument for
# a script over a number in prose, made by the ticket that asked for the script.
#
# THE DISQUALIFYING COLUMN is `...that never needed code`: a flagged closure whose id has no
# code-landing commit anywhere in history. Those are the ledger's decision, park, duplicate and
# documentation tickets, and there are hundreds of them; a REFUSAL over that population blocks
# correct commits to prevent a window nobody read. That column is why this ships as a warning.
#
# THE DURATION COLUMN is what [[T-1342]] actually asked for, and it is the quantity the harm
# depends on. For every closure flagged by `here` whose code DID land in some other commit, the gap
# is signed: `code after` is the harmful direction (the ledger claims work that is not in the tree
# and the next agent reads it), `code before` is the harmless one (the work was already in, the
# closure was merely written late). The table reports the count, the median, the p90, the max, how
# many ran past 30 and 60 minutes and a day, and how many are STILL unresolved at HEAD.
#
# NON-VACUITY. A replay that reads nothing reports a clean sweep, so this refuses below floors --
# the shape `ledger-lag-check.sh` and every other replay in this family already carries ([[T-1282]],
# [[T-1291]]).
set -u

LIST=0
ERA=300
ROOT_OVERRIDE=
MIN_COMMITS=${CADENCE_REPLAY_LAG_MIN_COMMITS:-200}
MIN_CLOSURES=${CADENCE_REPLAY_LAG_MIN_CLOSURES:-120}
MIN_CODE_IDS=${CADENCE_REPLAY_LAG_MIN_CODE_IDS:-100}

while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=1 ;;
        --era) shift; ERA=${1:-300} ;;
        --root) shift; ROOT_OVERRIDE=${1:-} ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) printf 'REFUSED (REPLAY-UNKNOWN-ARG): %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

case "$0" in
    /*) SELF_PATH=$0 ;;
    *)  SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
esac
# `--root` exists for one reason and it is not convenience: an agent developing this reads a
# `scripts/agent-scratch.sh` extract, which is a `git archive` and has no `.git` at all, so the
# script's own directory cannot answer the question it is being asked. The floors below decide
# whether whatever root it got was worth reading.
if [ -n "$ROOT_OVERRIDE" ]; then
    ROOT=$(cd "$ROOT_OVERRIDE" && pwd) || exit 2
else
    ROOT=$(cd "$(dirname "$SELF_PATH")/.." && pwd) || exit 2
fi
cd "$ROOT" || exit 2

TODO=docs/TODO.md
DONE=docs/TODO_DONE.md

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-lag-XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

READING='
function closure_visible(s,   bq) {
    bq = sprintf("%c", 96)
    while (match(s, bq "[^" bq "]*" bq)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
    return s
}
function first_line_closed(s) {
    return closure_visible(s) ~ /\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/
}
function entry_id(line,   id) { id = line; sub(/^- \[/, "", id); sub(/\].*$/, "", id); return id }
function is_code(p) {
    if (p == "") return 0
    if (p ~ /^docs\//) return 0
    if (p ~ /(^|\/)AGENTS\.md$/) return 0
    if (p == "CLAUDE.md" || p == "README.md") return 0
    return 1
}
function subject_ids(s,   tok, sep, prevnum, a, b, i, rest) {
    delete SID
    rest = s; prevnum = -1
    while (match(rest, /T-[0-9]+/)) {
        tok = substr(rest, RSTART, RLENGTH); sep = substr(rest, 1, RSTART - 1)
        b = substr(tok, 3) + 0
        if (prevnum >= 0 && sep ~ /^ *\.\.+ *$/) {
            a = prevnum
            if (b > a && b - a <= 64) for (i = a + 1; i < b; i++) SID["T-" i] = 1
        }
        SID[tok] = 1; prevnum = b; rest = substr(rest, RSTART + RLENGTH)
    }
}
'

# --- pass A: every commit that LANDS CODE under an id, oldest first ----------
git log --reverse --format='%x01%H%x1f%ct%x1f%s' --name-only HEAD > "$tmp/log.txt" || exit 2
ncommits=$(grep -c '^' "$tmp/log.txt")

awk "$READING"'
function flush(   id) {
    if (c_sha == "") return
    seq[c_sha] = ++order
    if (c_code == 0) return
    for (id in c_ids) printf "%s\t%s\t%s\t%s\n", id, c_sha, c_time, order
}
substr($0,1,1) == "\001" {
    flush()
    n = split(substr($0, 2), f, "\037")
    c_sha = f[1]; c_time = f[2]; c_subj = (n >= 3) ? f[3] : ""
    c_code = 0
    subject_ids(c_subj); delete c_ids
    for (k in SID) c_ids[k] = 1
    next
}
$0 != "" && is_code($0) { c_code++ }
END { flush() }
' "$tmp/log.txt" > "$tmp/code.tsv"

# commit -> ordinal, so "ancestor" is a comparison rather than a merge-base call per pair. This
# history is linear (no merges appear under --name-only and none are examined), which is the same
# assumption ledger-lag-check.sh already makes.
awk 'substr($0,1,1) == "\001" { n = split(substr($0,2), f, "\037"); printf "%s\t%d\t%s\n", f[1], ++i, f[2] }' \
    "$tmp/log.txt" > "$tmp/order.tsv"

ncodeids=$(cut -f1 "$tmp/code.tsv" | sort -u | grep -c '^' || true)

# --- pass B: every closure event, from each commit's OWN ledger diff ---------
git log --reverse --format='%x01%H%x1f%ct%x1f%s' -p --unified=0 -- "$TODO" "$DONE" > "$tmp/ledgerlog.txt" || exit 2

awk "$READING"'
substr($0,1,1) == "\001" {
    n = split(substr($0, 2), f, "\037")
    c_sha = f[1]; c_time = f[2]; c_subj = (n >= 3) ? f[3] : ""
    subject_ids(c_subj); delete c_ids
    for (k in SID) c_ids[k] = 1
    file = ""
    next
}
/^\+\+\+ b\// { file = substr($0, 7); next }
substr($0,1,1) != "+" { next }
{
    line = substr($0, 2)
    if (line !~ /^- \[T-[0-9]+\]/) next
    id = entry_id(line)
    # Archival into TODO_DONE.md is a closure; in TODO.md it must carry the T-1335 run.
    if (file == "'"$DONE"'") ok = 1
    else ok = first_line_closed(line)
    if (!ok) next
    k = c_sha "\036" id
    if (k in seen) next
    seen[k] = 1
    printf "%s\t%s\t%s\t%s\t%s\n", id, c_sha, c_time, ((id in c_ids) ? "named" : "unnamed"), substr(c_subj, 1, 70)
}
' "$tmp/ledgerlog.txt" > "$tmp/closures.tsv"

nclosures=$(grep -c '^' "$tmp/closures.tsv" || true)

if [ "$ncommits" -lt "$MIN_COMMITS" ] || [ "$nclosures" -lt "$MIN_CLOSURES" ] || [ "$ncodeids" -lt "$MIN_CODE_IDS" ]; then
    printf 'REFUSED (REPLAY-LAG-VACUOUS): read %d log lines (floor %d), %d closure events (floor %d), %d ids with code (floor %d).\n  A shallow checkout, a renamed ledger or the wrong --root all look like a clean sweep here.\n' \
        "$ncommits" "$MIN_COMMITS" "$nclosures" "$MIN_CLOSURES" "$ncodeids" "$MIN_CODE_IDS" >&2
    exit 4
fi

# --- the table ---------------------------------------------------------------
awk -F'\t' -v list="$LIST" -v era="$ERA" -v ncommits_total="$(grep -c '' "$tmp/order.tsv")" '
FILENAME ~ /order\.tsv$/ { ord[$1] = $2 + 0; ctime[$1] = $3 + 0; next }
FILENAME ~ /code\.tsv$/  {
    id = $1; sha = $2; t = $3 + 0; o = $4 + 0
    ncode[id]++
    codesha[id, ncode[id]] = sha; codet[id, ncode[id]] = t; codeo[id, ncode[id]] = o
    next
}
{
    id = $1; sha = $2; t = $3 + 0; named = $4; subj = $5
    o = ord[sha]
    inera = (ncommits_total - o < era) ? 1 : 0

    here = 0; before = 0; anyw = (id in ncode) ? 1 : 0
    unnamed = (named == "unnamed") ? 1 : 0
    nearest_t = 0; nearest_sha = ""; best = -1
    for (i = 1; i <= ncode[id]; i++) {
        if (codesha[id, i] == sha) here = 1
        if (codeo[id, i] < o) before = 1
        d = codet[id, i] - t; ad = (d < 0) ? -d : d
        if (best < 0 || ad < best) { best = ad; nearest_t = d; nearest_sha = codesha[id, i] }
    }

    for (s = 0; s <= 1; s++) {
        if (s == 1 && !inera) continue
        tot[s]++
        if (!here)            { f[s, "here"]++;         if (!anyw) fn[s, "here"]++ }
        if (!here && !before) { f[s, "hereorbefore"]++; if (!anyw) fn[s, "hereorbefore"]++ }
        if (!here && !before && unnamed) { f[s, "unnamed"]++; if (!anyw) fn[s, "unnamed"]++ }
        if (!anyw)            { f[s, "anywhere"]++;     fn[s, "anywhere"]++ }
    }

    fk = substr(sha, 1, 7) "/" id
    if (fk == "b358aa3/T-1334" || fk == "b358aa3/T-1339" || fk == "e28bc87/T-1348" || fk == "e28bc87/T-1349") {
        founding[fk] = (!here ? "here" : "-") " " ((!here && !before) ? "hereorbefore" : "-") " " \
                       ((!here && !before && unnamed) ? "unnamed" : "-") " " (!anyw ? "anywhere" : "-")
        nfound++
    }

    if (!here) {
        if (!anyw) { nocode++ }
        else if (nearest_t > 0) {
            mins = int(nearest_t / 60)
            gaps[++ng] = mins
            if (mins > 30)    g30++
            if (mins > 60)    g60++
            if (mins > 1440)  g1440++
            if (list) printf "  FLAGGED  code-after  %6dm  %s  %s  %s  (code in %s)\n", mins, substr(sha,1,7), id, subj, substr(nearest_sha,1,7) > "/dev/stderr"
        } else {
            codebefore++
            if (list) printf "  flagged  code-before %6dm  %s  %s  %s\n", int(-nearest_t/60), substr(sha,1,7), id, subj > "/dev/stderr"
        }
    }
}
END {
    printf "replay-closure-code-lag: %d closure events over %d commits; %d in the last %d commits.\n\n", tot[0], ncommits_total, tot[1], era
    split("here hereorbefore unnamed anywhere", order2, " ")
    for (s = 0; s <= 1; s++) {
        printf "  scope: %s\n", (s == 0) ? "WHOLE HISTORY" : ("PARALLEL-AGENT ERA (last " era " commits)")
        printf "    %-14s %-22s %s\n", "reading", "newly refuses", "...that never needed code"
        for (c = 1; c <= 4; c++) { r = order2[c]
            printf "    %-14s %5d of %-6d        %5d   %s\n", r, f[s,r]+0, tot[s]+0, fn[s,r]+0,
                (fn[s,r]+0 == 0) ? "could refuse" : "WARNING ONLY" }
        printf "\n"
    }
    printf "  gap duration, for the closures `here` flags whose code landed in another commit:\n"
    printf "    code AFTER the closure (the harmful direction): %d\n", ng+0
    if (ng > 0) {
        # An insertion sort, written out rather than called: `asort` is a gawk extension and the
        # awk on this Mac is the one-true-awk, which has no such function and dies at RUN time
        # rather than at parse time -- after the table above has already printed, which is exactly
        # what a half-finished measurement looks like. Measured while writing this.
        for (i = 2; i <= ng; i++) {
            v = gaps[i]
            for (j = i - 1; j >= 1 && gaps[j] > v; j--) gaps[j + 1] = gaps[j]
            gaps[j + 1] = v
        }
        med = gaps[int((ng + 1) / 2)]
        pi = int(ng * 0.9 + 0.5); if (pi < 1) pi = 1; if (pi > ng) pi = ng
        printf "      median %dm, p90 %dm, max %dm; over 30m: %d, over 60m: %d, over 24h: %d\n",
            med, gaps[pi], gaps[ng], g30+0, g60+0, g1440+0
    }
    printf "    code BEFORE the closure (already guarded by ledger-lag-check.sh): %d\n", codebefore+0
    printf "    no code in any commit, ever (the disqualifying population): %d\n", nocode+0
    printf "\n  founding cases (T-1342), by name and not in aggregate:\n"
    split("b358aa3/T-1334 b358aa3/T-1339 e28bc87/T-1348 e28bc87/T-1349", fl, " ")
    for (i = 1; i <= 4; i++)
        printf "    %-16s caught by: %s\n", fl[i], (fl[i] in founding) ? founding[fl[i]] : "NOT SEEN AT ALL -- the replay lost the case it was built for"
    if (nfound + 0 != 4) {
        printf "REFUSED (REPLAY-LAG-FOUNDING-LOST): %d of 4 founding closure events were read; this checkout cannot answer the question.\n", nfound + 0 > "/dev/stderr"
        exit 4
    }
}
' "$tmp/order.tsv" "$tmp/code.tsv" "$tmp/closures.tsv"
