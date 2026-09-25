#!/bin/sh
# Replay the ledger's CLOSURE reading over every entry that has ever existed (T-1335).
#
#   ./scripts/replay-closure-reading.sh               # every distinct entry first line, all readings
#   ./scripts/replay-closure-reading.sh --list        # ...and print the lines each reading loses
#   ./scripts/replay-closure-reading.sh --window 150  # ...over the last 150 ledger commits only
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. Every guard in this family has to answer the
# same question before it is allowed to refuse anything -- *how many commits this repository
# actually made would this have stopped* -- and the answer decides between a refusal, a warning and
# nothing at all. [[T-1300]] answered its version with 191 in 274 and settled on a warning;
# [[T-1304]] answered its with 4 in 511 and earned a refusal, and left
# `scripts/replay-message-vs-ledger.sh` in the tree rather than quoting its number. This is the
# same instrument for [[T-1335]]'s question, and for the same reason: the number rots with the next
# commit, and a number quoted in prose cannot be re-derived by whoever wants to widen the rule.
#
# THE QUESTION. `agent-commit.sh`'s `ledger_closed_ids` and `scripts/ledger-lag-check.sh` both
# decide closure by looking for the bare token ANYWHERE on an entry's own first line. An entry that
# merely QUOTES the token -- which is what writing about the ledger format looks like -- therefore
# reads closed, and a commit can name that id and pass the lag guard having closed nothing. The
# repair is a stricter reading; the cost of a stricter reading is that it may stop recognising
# HONEST closures, and that cost is the one this family must not pay, because it turns the lag
# check red on correct commits. So: replay every entry first line that has ever existed in
# `docs/TODO.md` or `docs/TODO_DONE.md`, and count, for each candidate, how many lines the loose
# reading calls closed that the candidate does not.
#
# THE READINGS, all five measured side by side:
#
#   loose     the token anywhere on the first line. `ledger_closed_ids` and `ledger-lag-check.sh`
#             today. The baseline every other column is a subset of.
#   anchored  a bold run OPENING the line, right after the id: `- [T-n] **CLOSED`,
#             `**FULLY CLOSED`, `**PARTIALLY CLOSED`. This is NOT a new reading -- it is the one
#             `ledger_buried_closure_ids` measured over 471 entries (T-1106) and the one
#             `scripts/ledger-view.sh` already ships. Adopting it is two implementations of one
#             rule converging, not a third being invented.
#   boldrun   a bold run introducing the token ANYWHERE on the line, outside inline code. Looser
#             than `anchored` by exactly the entries that put something before the marker.
#   nocode    the token anywhere on the line, outside inline code spans. The ticket's
#             "require it outside backticks" candidate.
#   dated     the token followed by the `yyyy-mm-dd` every real closure carries. The ticket's
#             "require the accompanying date" candidate.
#
# SCOPES, because the two guards do not read the same population:
#
#   * `ledger_closed_ids` reads BOTH ledgers whole, so its scope is every entry.
#   * `ledger-lag-check.sh` already counts `## Done`, `## Cancelled` and every archived entry as
#     closed without looking for a marker at all, so a marker reading can only cost it entries in
#     `docs/TODO.md` OUTSIDE those sections. That is much the smaller population, and the delta
#     there is the number that decides whether the lag check can refuse.
#
# NON-VACUITY. A replay that reads nothing reports a clean sweep. So the run counts the commits and
# the distinct entry lines it read and refuses below a floor -- the shape `ledger-lag-check.sh` and
# `ledger-view.sh` already carry, and the defect [[T-1282]] found in a gate that compiled nothing.
set -u

WINDOW=0
LIST=0
MIN_COMMITS=${CADENCE_REPLAY_CLOSURE_MIN_COMMITS:-100}
MIN_LINES=${CADENCE_REPLAY_CLOSURE_MIN_LINES:-400}

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

if [ "$WINDOW" -gt 0 ]; then
    commits=$(git rev-list HEAD -- "$TODO" "$DONE" | head -n "$WINDOW")
else
    commits=$(git rev-list HEAD -- "$TODO" "$DONE")
fi
ncommits=$(printf '%s\n' "$commits" | grep -c '^[0-9a-f]')

# Every distinct entry FIRST LINE that has ever existed, tagged with the scope it was in. Tag is
# `lag` when the entry was in docs/TODO.md outside ## Done / ## Cancelled -- the only population a
# marker reading can cost the lag check -- and `other` otherwise.
raw=$(
    for sha in $commits; do
        for path in "$TODO" "$DONE"; do
            git show "$sha:$path" 2>/dev/null | awk -v p="$path" '
                /^## / { sec = $0; next }
                /^- \[T-[0-9]+\]/ {
                    tag = (p == "docs/TODO.md" && sec !~ /^## (Done|Cancelled)/) ? "lag" : "other"
                    print tag "\t" $0
                }
            '
        done
    done | sort -u
)

nlines=$(printf '%s\n' "$raw" | grep -c '	- \[T-')

if [ "$ncommits" -lt "$MIN_COMMITS" ] || [ "$nlines" -lt "$MIN_LINES" ]; then
    printf 'REFUSED (REPLAY-CLOSURE-VACUOUS): read %d ledger commits (floor %d) and %d distinct entry lines (floor %d).\n  A shallow checkout, a renamed ledger or the wrong working directory all look like a clean sweep here.\n' \
        "$ncommits" "$MIN_COMMITS" "$nlines" "$MIN_LINES" >&2
    exit 4
fi

printf '%s\n' "$raw" | awk -F'\t' -v list="$LIST" '
function strip_code(s) { while (match(s, /`[^`]*`/)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH); return s }
function idof(s,   i) { i = s; sub(/^- \[/, "", i); sub(/\].*$/, "", i); return i }

$2 !~ /^- \[T-[0-9]+\]/ { next }
{
    tag = $1; line = $2; nc = strip_code(line)
    total++; if (tag == "lag") lag_total++

    loose    = (line ~ /CLOSED/)
    anchored = (line ~ /^- \[T-[0-9]+\] \*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/)
    boldrun  = (nc ~ /\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/)
    nocode   = (nc ~ /CLOSED/)
    dated    = (line ~ /CLOSED[A-Z ]* [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)

    if (!loose) next
    L++; if (tag == "lag") lagL++

    if (!anchored) { lost["anchored"]++; if (tag == "lag") laglost["anchored"]++; if (list) print "  anchored  " tag "  " substr(line, 1, 150) > "/dev/stderr" }
    if (!boldrun)  { lost["boldrun"]++;  if (tag == "lag") laglost["boldrun"]++;  if (list) print "  boldrun   " tag "  " substr(line, 1, 150) > "/dev/stderr" }
    if (!nocode)   { lost["nocode"]++;   if (tag == "lag") laglost["nocode"]++;   if (list) print "  nocode    " tag "  " substr(line, 1, 150) > "/dev/stderr" }
    if (!dated)    { lost["dated"]++;    if (tag == "lag") laglost["dated"]++;    if (list) print "  dated     " tag "  " substr(line, 1, 150) > "/dev/stderr" }
}
END {
    printf "replay-closure-reading: %d distinct entry first lines ever, %d of them read closed by the LOOSE reading.\n", total, L
    printf "  of those, %d are in the lag check'"'"'s own scope (docs/TODO.md outside ## Done / ## Cancelled).\n\n", lagL
    printf "  %-10s %-34s %-22s\n", "reading", "honest closures it stops seeing", "...in the lag scope"
    split("anchored boldrun nocode dated", order, " ")
    for (k = 1; k <= 4; k++) {
        r = order[k]
        printf "  %-10s %5d of %-5d (%5.2f%%)          %5d of %-5d (%5.2f%%)\n", r,
            lost[r] + 0, L, 100.0 * (lost[r] + 0) / L, laglost[r] + 0, lagL, 100.0 * (laglost[r] + 0) / lagL
    }
}
'
