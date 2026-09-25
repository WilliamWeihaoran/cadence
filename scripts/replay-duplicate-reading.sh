#!/bin/sh
# Replay LEDGER-ID-DUPLICATE's reading over every commit that has ever touched a ledger (T-1356).
#
#   ./scripts/replay-duplicate-reading.sh            # the table
#   ./scripts/replay-duplicate-reading.sh --list     # ...and name every commit each reading moves
#   ./scripts/replay-duplicate-reading.sh --window 200   # ...over the last 200 ledger commits only
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. Same reason as
# `scripts/replay-closure-reading.sh`, `scripts/replay-message-vs-ledger.sh` and
# `scripts/replay-partial-reading.sh`: a guard in this family answers *how many commits this
# repository actually made would this have stopped* before it refuses, and *how many would it stop
# refusing* before it widens. [[T-1300]] answered its version with 191 in 274 and took a warning;
# [[T-1304]] answered its with 4 in 511 and earned a refusal. A number quoted in prose rots with
# the next commit and cannot be re-derived by whoever wants to widen the rule again.
#
# THE QUESTION. `ledger_duplicate_ids` in `scripts/agent-commit.sh` reads a DELTA: it refuses only
# ids that are duplicated in the STAGED ledger and were not duplicated in the same file at HEAD.
# [[T-1106]] argued for a whole-file reading and [[T-1072]] made it impossible, because HEAD
# carried standing duplicates that the ticket decided must not be renumbered -- a whole-file
# reading would then refuse every future commit staging that file, a permanent false refusal in the
# commit path, which is the one failure this family must not have.
#
# WHAT CHANGED, and why the question is open again. [[T-1136]] folded T-781's and T-974's stale
# open copies back into their closures, so the standing population is now exactly ONE id:
# `T-1043`, two genuinely different tickets under one number, permanent by [[T-1072]]'s decision.
# A whole-file reading is one named exemption away from being adoptable, and the delta reading's
# cost is real: it is blind to a duplicate that is already in HEAD, so the FIRST commit to file a
# collision is refused and every later one rides free.
#
# THE READINGS:
#
#   delta         what ships: an id refuses iff it is duplicated in the staged ledger file and was
#                 not duplicated in that same file at the parent. The baseline.
#   whole         any duplicated id in the staged file refuses, parent ignored. [[T-1106]]'s
#                 reading, and the one [[T-1072]] refused.
#   wholeexempt   `whole`, with `T-1043` named in the script as the one permanent exemption.
#   wholeactive   `whole`, restricted to ids with at least ONE entry that is not closed -- the
#                 [[T-1356]] ticket's own variant. An id whose entries are ALL closed cannot be
#                 picked up again by an agent scanning for work, which is the harm the guard is
#                 about. Needs no exemption: T-1043's two entries are both closed.
#   deltaactive   `delta` with the same active restriction. A NARROWING of what ships, measured to
#                 show what the active filter costs on its own.
#
# WHAT "INNOCENT" MEANS, and it is the column that decides. A commit is innocent if its own diff
# introduced no duplicate its parent did not already have -- it merely edited a ledger that was
# already carrying one. Refusing those is the permanent-false-refusal failure [[T-1072]] named, so
# any widening whose innocent count is non-zero at HEAD is disqualified no matter how good its
# catch count looks. The historical innocent count is reported too, and is NOT disqualifying on its
# own: it counts commits made while duplicates this repository has since repaired were standing.
#
# NON-VACUITY. A replay that reads nothing reports a clean sweep, so this refuses below floors --
# the shape `ledger-lag-check.sh`, `replay-closure-reading.sh` and `replay-partial-reading.sh
# already carry ([[T-1282]]). The third floor is on the BASELINE: if the shipped reading refuses
# nobody across the whole replay, the instrument read nothing useful and every column is a clean
# sweep by construction.
set -u

WINDOW=0
LIST=0
MIN_COMMITS=${CADENCE_REPLAY_DUP_MIN_COMMITS:-300}
MIN_BLOBS=${CADENCE_REPLAY_DUP_MIN_BLOBS:-300}
MIN_BASELINE=${CADENCE_REPLAY_DUP_MIN_BASELINE:-3}

while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=1 ;;
        --window) shift; WINDOW=${1:-0} ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) printf 'REFUSED (REPLAY-UNKNOWN-ARG): %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

case "$0" in
    /*) SELF_PATH=$0 ;;
    *)  SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
esac
ROOT=$(cd "$(dirname "$SELF_PATH")/.." && pwd)
cd "$ROOT" || exit 2

TODO=docs/TODO.md
DONE=docs/TODO_DONE.md
EXEMPT_ID=T-1043

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-dup-XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp/blob"

# The two readings, spelled once. `closure_visible` / `first_line_closed` are `agent-commit.sh`'s
# `$LEDGER_CLOSURE_READING` (T-1335) and the duplicate count is `ledger_duplicate_ids`, so this
# instrument measures the shipped readings rather than a third opinion of its own.
DUPREAD='
function closure_visible(s,   bq) {
    bq = sprintf("%c", 96)
    while (match(s, bq "[^" bq "]*" bq)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
    return s
}
function first_line_closed(s) {
    return closure_visible(s) ~ /\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/
}
function entry_id(line,   id) { id = line; sub(/^- \[/, "", id); sub(/\].*$/, "", id); return id }
'

# Duplicated ids in ONE ledger file, with whether any of that id entries is still active.
# Prints "<id>\t<0|1 active>". `archive` marks docs/TODO_DONE.md, where every entry is closed by
# file -- the reading `ledger-view.sh` and `ledger-lag-check.sh` both use.
dup_of_blob() {  # $1 = blob sha (may be empty), $2 = 1 when the file is the archive, $3 = out file
    if [ -z "$1" ]; then : > "$3"; return 0; fi
    cache="$tmp/blob/$1.$2"
    if [ ! -f "$cache" ]; then
        git cat-file -p "$1" 2>/dev/null | awk -v archive="$2" "$DUPREAD"'
            /^## / { sec = $0; next }
            /^- \[T-[0-9]+\]/ {
                id = entry_id($0)
                n[id]++
                closed = (archive == 1) || (sec ~ /^## (Done|Cancelled)/) || first_line_closed($0)
                if (!closed) active[id] = 1
            }
            END { for (id in n) if (n[id] > 1) printf "%s\t%d\n", id, (id in active) ? 1 : 0 }
        ' | sort > "$cache"
        blobs_read=$((blobs_read + 1))
    fi
    cp "$cache" "$3"
    return 0
}

blobs_read=0

# --- every commit that touched a ledger, newest first -------------------------
if [ "$WINDOW" -gt 0 ]; then rangeargs="-n $WINDOW"; else rangeargs=""; fi
# shellcheck disable=SC2086
git log --format='%H %P' $rangeargs HEAD -- "$TODO" "$DONE" > "$tmp/log.txt" || exit 2
ncommits=$(grep -c '^' "$tmp/log.txt")

if [ "$ncommits" -lt "$MIN_COMMITS" ]; then
    printf 'REFUSED (REPLAY-DUP-VACUOUS): read %d ledger commits (floor %d).\n  A shallow checkout, a renamed ledger or the wrong working directory all look like a clean sweep here.\n' \
        "$ncommits" "$MIN_COMMITS" >&2
    exit 4
fi

# --- per commit, per ledger file it touched: what each reading says -----------
# One line per (commit, file): sha, file, and the id sets the readings need.
: > "$tmp/facts.tsv"
while read -r sha parents; do
    parent=$(printf '%s\n' "$parents" | awk '{print $1}')
    touched=$(git show --format= --name-only "$sha" -- "$TODO" "$DONE" 2>/dev/null | awk 'NF')
    [ -n "$touched" ] || continue
    for f in $touched; do
        case "$f" in "$TODO") arch=0 ;; "$DONE") arch=1 ;; *) continue ;; esac
        csha=$(git rev-parse --quiet --verify "$sha:$f" 2>/dev/null || true)
        psha=""
        [ -n "$parent" ] && psha=$(git rev-parse --quiet --verify "$parent:$f" 2>/dev/null || true)
        dup_of_blob "$csha" "$arch" "$tmp/c.dup"
        dup_of_blob "$psha" "$arch" "$tmp/p.dup"
        # cur = every duplicated id here; curactive = those with an active entry;
        # new = duplicated here and not in the parent (the shipped delta).
        cur=$(cut -f1 "$tmp/c.dup" | tr '\n' ' ')
        curactive=$(awk -F'\t' '$2 == 1 {print $1}' "$tmp/c.dup" | tr '\n' ' ')
        cut -f1 "$tmp/c.dup" | sort -u > "$tmp/c.ids"
        cut -f1 "$tmp/p.dup" | sort -u > "$tmp/p.ids"
        new=$(comm -23 "$tmp/c.ids" "$tmp/p.ids" | tr '\n' ' ')
        printf '%s\t%s\t%s\t%s\t%s\n' "$sha" "$f" "$cur" "$curactive" "$new" >> "$tmp/facts.tsv"
    done
done < "$tmp/log.txt"

nfacts=$(grep -c '^' "$tmp/facts.tsv" || true)
if [ "$blobs_read" -lt "$MIN_BLOBS" ] && [ "$WINDOW" -eq 0 ]; then
    printf 'REFUSED (REPLAY-DUP-VACUOUS): read %d distinct ledger blobs (floor %d).\n  Every commit resolving to the same blob means the replay is reading one file, not a history.\n' \
        "$blobs_read" "$MIN_BLOBS" >&2
    exit 4
fi

# --- the table ---------------------------------------------------------------
awk -F'\t' -v list="$LIST" -v exempt="$EXEMPT_ID" -v nfacts="$nfacts" -v ncommits="$ncommits" '
function has(set)            { return set ~ /[^ ]/ }
function without(set, id,   r) { r = " " set " "; gsub(" " id " ", " ", r); return r }
{
    sha = $1; file = $2; cur = $3; curactive = $4; new = $5
    key = sha
    seen[key] = 1
    if (has(new))                       r_delta[key] = 1
    if (has(cur))                       r_whole[key] = 1
    if (has(without(cur, exempt)))      r_exempt[key] = 1
    if (has(curactive))                 r_active[key] = 1
    if (has(new)) {
        # delta ∩ active: a NEW duplicate at least one of whose entries is open.
        n = split(new, a, " ")
        for (i = 1; i <= n; i++) if (a[i] != "" && index(" " curactive " ", " " a[i] " ") > 0) r_deltaactive[key] = 1
    }
    if (has(new)) guilty[key] = 1
    cur_of[key] = cur_of[key] " " cur
}
END {
    split("whole wholeexempt wholeactive deltaactive", order, " ")
    for (k in seen) {
        commits++
        g = (k in guilty)
        if (g) baseline++
        for (c = 1; c <= 4; c++) {
            r = order[c]
            refused = (r == "whole") ? (k in r_whole) : \
                      (r == "wholeexempt") ? (k in r_exempt) : \
                      (r == "wholeactive") ? (k in r_active) : (k in r_deltaactive)
            if (refused) tot[r]++
            if (refused && !(k in r_delta)) {
                newly[r]++
                if (!g) { newly_innocent[r]++
                    if (r == "wholeexempt") {
                        n = split(without(cur_of[k], exempt), a, " ")
                        for (i = 1; i <= n; i++) if (a[i] != "") blame[a[i]]++
                    }
                    if (list) printf "  %-12s NEWLY-REFUSED-INNOCENT  %s\n", r, substr(k,1,7) > "/dev/stderr"
                }
            }
            if (!refused && (k in r_delta)) {
                lost[r]++
                if (g) { lost_guilty[r]++
                    if (list) printf "  %-12s NO-LONGER-REFUSED       %s\n", r, substr(k,1,7) > "/dev/stderr"
                }
            }
        }
    }
    printf "replay-duplicate-reading: %d ledger commits, %d (commit,file) pairs examined.\n", ncommits, nfacts
    printf "  baseline -- the reading that ships (delta vs parent) refuses %d of %d commits.\n\n", baseline, commits
    printf "  %-13s %-16s %-24s %s\n", "reading", "refuses", "newly refused (innocent)", "no longer refused (real)"
    for (c = 1; c <= 4; c++) { r = order[c]
        printf "  %-13s %4d of %-9d %4d (%4d)               %4d (%4d)\n", r, tot[r]+0, commits,
            newly[r]+0, newly_innocent[r]+0, lost[r]+0, lost_guilty[r]+0 }
    printf "\n  which standing duplicate drove the wholeexempt innocent refusals:\n"
    nb = 0
    for (id in blame) { nb++; printf "    %-10s %4d commits\n", id, blame[id] }
    if (nb == 0) printf "    (none -- no innocent commit would have been refused)\n"
    printf "\n  BASELINE_REFUSALS=%d\n", baseline
}
' "$tmp/facts.tsv" | tee "$tmp/table.txt"

# THE THIRD FLOOR, and it is the one the other two cannot stand in for. The table above is a set of
# DIFFERENCES against the shipped reading; if the shipped reading refuses nobody, every column is a
# clean sweep by construction and the instrument has measured nothing.
baseline=$(sed -n 's/^  BASELINE_REFUSALS=//p' "$tmp/table.txt")
if [ "${baseline:-0}" -lt "$MIN_BASELINE" ] && [ "$WINDOW" -eq 0 ]; then
    printf 'REFUSED (REPLAY-DUP-VACUOUS): the shipped reading refused %s of %d replayed commits (floor %d).\n  Every candidate column is then a difference against nothing, which reads as a clean sweep.\n' \
        "${baseline:-0}" "$ncommits" "$MIN_BASELINE" >&2
    exit 4
fi

# --- the decisive question: what does each reading say about the NEXT commit? -
# Historical innocent counts are context; a widening lives or dies on whether it refuses an
# ordinary commit that stages the ledger AT HEAD having introduced nothing.
printf '\n  standing population AT HEAD (an ordinary commit staging the ledger, introducing nothing):\n'
for f in "$TODO" "$DONE"; do
    case "$f" in "$TODO") arch=0 ;; *) arch=1 ;; esac
    hsha=$(git rev-parse --quiet --verify "HEAD:$f" 2>/dev/null || true)
    dup_of_blob "$hsha" "$arch" "$tmp/head.dup"
    all=$(cut -f1 "$tmp/head.dup" | tr '\n' ' ')
    act=$(awk -F'\t' '$2 == 1 {print $1}' "$tmp/head.dup" | tr '\n' ' ')
    exm=$(cut -f1 "$tmp/head.dup" | grep -v "^$EXEMPT_ID\$" | tr '\n' ' ')
    printf '    %-18s delta: nobody   whole: %s  wholeexempt: %s  wholeactive: %s\n' "$f" \
        "${all:-(nobody)}" "${exm:-(nobody)}" "${act:-(nobody)}"
done
