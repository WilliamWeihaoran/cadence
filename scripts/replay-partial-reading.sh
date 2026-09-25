#!/bin/sh
# Replay the ledger lag check's STATUS MODEL over every commit it examines (T-1359, T-1325).
#
#   ./scripts/replay-partial-reading.sh            # the table
#   ./scripts/replay-partial-reading.sh --list     # ...and name every commit each reading excuses
#   ./scripts/replay-partial-reading.sh --window 400   # ...over the last 400 commits only
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. Same reason as
# `scripts/replay-closure-reading.sh` and `scripts/replay-message-vs-ledger.sh`: every guard in
# this family has to answer *how many commits this repository actually made would this have
# stopped* before it is allowed to refuse, and *how many would it stop refusing* before it is
# allowed to widen. [[T-1300]] answered its version with 191 in 274 and took a warning; [[T-1304]]
# answered its with 4 in 511 and earned a refusal. A number quoted in prose rots with the next
# commit and cannot be re-derived by whoever wants to widen the rule again.
#
# THE QUESTION. `scripts/ledger-lag-check.sh` has two states for an entry -- closed, or open --
# while `scripts/ledger-view.sh` has five, and `**PARTIAL` is one of the five. T-1335 converged the
# three scripts' CLOSURE TOKEN reading and left the STATUS MODEL unconverged, and [[T-1359]] is
# exactly that gap: `7b5897d` landed two MCP constructors under [[T-1122]], whose entry opens
# `**PARTIAL 2026-09-25 (agent `mcpcreate`) -- ...`, and the check has no bucket for it, so the run
# is red and STICKY -- every later push is red too until T-1122 closes, which its own entry says is
# waiting on a decision rather than on work.
#
# So the candidates below all WIDEN the guard, and a widening is only safe if it does not excuse
# the case the guard was built for: [[T-1298]]'s commit that lands code, names ids, and records
# NOTHING. That is why the table's second column, not the first, is the one that decides.
#
# THE READINGS:
#
#   today             what ships: an id is closed iff its entry's own first line carries the T-1335
#                     closure run at HEAD, or the entry is under `## Done` / `## Cancelled`, or it
#                     is in the archive. The baseline every other column is measured against.
#   partial           ...or the entry's first line opens `**PARTIAL`, the status `ledger-view.sh`
#                     already models. T-1359's first candidate.
#   partialdated      ...but the `**PARTIAL` run must carry a `yyyy-mm-dd`.
#   partialauthored   ...and an author too -- `(agent `name`)` or a `(`sha`)`. The ticket's "dated,
#                     authored progress statement" wording, read literally.
#   partialhere       `**PARTIAL` counts only when THIS commit's own diff wrote or rewrote that
#                     entry's first line. The strictest partial reading: it credits the commit that
#                     did the work and never a commit riding on someone else's PARTIAL.
#   ownledger         orthogonal, and this is [[T-1325]]'s other half: an id counts closed if it is
#                     closed at HEAD **or** closed in `git show <sha>:docs/TODO.md` -- the ledger as
#                     that commit itself left it. Removes the stickiness rather than the gap.
#   partialhere+own   the two together, reported as `both`. MEASURED AND DISQUALIFIED, for the
#                     same reason `ownledger` is: in the as-landed scope it newly excuses 199
#                     commits that recorded nothing at all, which is the population the guard
#                     exists for. `partialhere` ALONE is what `ledger-lag-check.sh` adopted.
#
# WHAT "CLOSED NOTHING" MEANS, and it is the whole point of the second column. A commit RECORDED
# its work if its own diff to either ledger added a first line for an id it names carrying a
# closure run or a `**PARTIAL` run. T-1298's three founding cases -- `00d576f`, `e4719e3`,
# `44eced5` -- recorded nothing by that test, and any reading that excuses them is disqualified
# regardless of how good its first column looks.
#
# NON-VACUITY. A replay that reads nothing reports a clean sweep, so this refuses below floors, the
# shape `ledger-lag-check.sh` and `replay-closure-reading.sh` already carry ([[T-1282]]).
set -u

WINDOW=0
LIST=0
MIN_COMMITS=${CADENCE_REPLAY_PARTIAL_MIN_COMMITS:-200}
MIN_EXAMINED=${CADENCE_REPLAY_PARTIAL_MIN_EXAMINED:-120}

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-partial-XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

# The status reading, spelled once. `closure_visible` / `first_line_closed` are
# `agent-commit.sh`'s `$LEDGER_CLOSURE_READING` (T-1335) and `first_line_partial` is
# `ledger-view.sh`'s PARTIAL status, so this instrument measures the shipped readings rather than
# a fourth opinion of its own.
READING='
function closure_visible(s,   bq) {
    bq = sprintf("%c", 96)
    while (match(s, bq "[^" bq "]*" bq)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
    return s
}
function first_line_closed(s) {
    return closure_visible(s) ~ /\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/
}
function first_line_partial(s) {
    return s ~ /^- \[T-[0-9]+\] \*\*PARTIAL([^A-Za-z]|$)/
}
function entry_id(line,   id) { id = line; sub(/^- \[/, "", id); sub(/\].*$/, "", id); return id }
'

# --- the HEAD ledger, as the check reads it: id \t status \t first line -------
status_of_rev() {  # $1 = rev, $2 = out file
    { git show "$1:$TODO" 2>/dev/null | sed 's/^/T\t/'
      git show "$1:$DONE" 2>/dev/null | sed 's/^/D\t/'
    } | awk -F'\t' "$READING"'
        $1 == "T" && $2 ~ /^## / { sec = $2; next }
        $2 !~ /^- \[T-[0-9]+\]/ { next }
        {
            id = entry_id($2)
            st = "OPEN"
            if ($1 == "D")                                  st = "CLOSED"
            else if (sec ~ /^## (Done|Cancelled)/)          st = "CLOSED"
            else if (first_line_closed($2))                 st = "CLOSED"
            else if (first_line_partial($2))                st = "PARTIAL"
            # An id is closed while ANY entry of it is closed (T-1303 duplicate shape).
            if (!(id in seen) || rank(st) > rank(seen[id])) { seen[id] = st; line[id] = $2 }
        }
        function rank(s) { return (s == "CLOSED") ? 2 : (s == "PARTIAL") ? 1 : 0 }
        END { for (id in seen) printf "%s\t%s\t%s\n", id, seen[id], line[id] }
    ' > "$2"
}

status_of_rev HEAD "$tmp/head.status"
nentries=$(wc -l < "$tmp/head.status" | tr -d ' ')

# --- every commit, with the ids its subject names and whether it lands code ---
if [ "$WINDOW" -gt 0 ]; then rangeargs="-n $WINDOW"; else rangeargs=""; fi
# shellcheck disable=SC2086
git log --format='%x01%H%x1f%ad%x1f%s' --date=short --name-only $rangeargs HEAD > "$tmp/log.txt" || exit 2

awk "$READING"'
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
function flush(   id, list) {
    if (c_sha == "") return
    commits++
    if (c_code == 0) return
    list = ""
    for (id in c_ids) list = list " " id
    if (list == "") return
    printf "%s\t%s\t%s\t%s\n", c_sha, c_date, substr(list, 2), c_subj
}
substr($0,1,1) == "\001" {
    flush()
    n = split(substr($0, 2), f, "\037")
    c_sha = f[1]; c_date = f[2]; c_subj = (n >= 3) ? f[3] : ""
    c_code = 0
    subject_ids(c_subj); delete c_ids
    for (k in SID) c_ids[k] = 1
    next
}
$0 != "" && is_code($0) { c_code++ }
END { flush() }
' "$tmp/log.txt" > "$tmp/candidates.tsv"

ncommits=$(grep -c '^' "$tmp/log.txt")

# Keep only commits naming at least one id FILED at HEAD -- the check's "examined" population.
cut -f1 "$tmp/head.status" | sort -u > "$tmp/filed.txt"
awk -F'\t' 'NR == FNR { filed[$1] = 1; next }
{
    n = split($3, ids, " "); keep = ""
    for (i = 1; i <= n; i++) if (ids[i] in filed) keep = keep " " ids[i]
    if (keep != "") printf "%s\t%s\t%s\t%s\n", $1, $2, substr(keep, 2), $4
}' "$tmp/filed.txt" "$tmp/candidates.tsv" > "$tmp/examined.tsv"

nexamined=$(grep -c '^' "$tmp/examined.tsv" || true)

if [ "$ncommits" -lt "$MIN_COMMITS" ] || [ "$nexamined" -lt "$MIN_EXAMINED" ]; then
    printf 'REFUSED (REPLAY-PARTIAL-VACUOUS): read %d log lines (floor %d) and %d examined commits (floor %d).\n  A shallow checkout, a renamed ledger or the wrong working directory all look like a clean sweep here.\n' \
        "$ncommits" "$MIN_COMMITS" "$nexamined" "$MIN_EXAMINED" >&2
    exit 4
fi

# --- per-commit facts: the ledger AS THAT COMMIT LEFT IT, and what it WROTE ---
# One `git show` of each ledger per examined commit. ~4 s for ~300 commits, measured 2026-09-25.
: > "$tmp/facts.tsv"
while IFS='	' read -r sha date ids subj; do
    { git show "$sha:$TODO" 2>/dev/null | sed 's/^/T\t/'
      git show "$sha:$DONE" 2>/dev/null | sed 's/^/D\t/'
      # What this commit's own diff ADDED to either ledger. `--unified=0` keeps it to added lines.
      git show --format= --unified=0 "$sha" -- "$TODO" "$DONE" 2>/dev/null \
          | sed -n 's/^+//p' | sed 's/^/A\t/'
    } | awk -F'\t' -v sha="$sha" -v want="$ids" "$READING"'
        BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) need[w[i]] = 1 }
        function rank(s) { return (s == "CLOSED") ? 2 : (s == "PARTIAL") ? 1 : 0 }
        $1 == "T" && $2 ~ /^## / { sec = $2; next }
        $2 !~ /^- \[T-[0-9]+\]/ { next }
        {
            id = entry_id($2); if (!(id in need)) next
            st = "OPEN"
            if ($1 == "D")                         st = "CLOSED"
            else if ($1 == "T" && sec ~ /^## (Done|Cancelled)/) st = "CLOSED"
            else if (first_line_closed($2))        st = "CLOSED"
            else if (first_line_partial($2))       st = "PARTIAL"
            if ($1 == "A") {
                # A progress line this commit itself wrote.
                if (st == "CLOSED" || st == "PARTIAL") { wrote[id] = st }
                next
            }
            if (!(id in own) || rank(st) > rank(own[id])) { own[id] = st; ownline[id] = $2 }
        }
        END {
            for (id in need)
                printf "%s\t%s\t%s\t%s\t%s\n", sha, id, (id in own) ? own[id] : "ABSENT", (id in wrote) ? wrote[id] : "-", (id in ownline) ? ownline[id] : ""
        }
    ' >> "$tmp/facts.tsv"
done < "$tmp/examined.tsv"

# --- the table ---------------------------------------------------------------
# TWO SCOPES, because the check states one rule and enforces another, and [[T-1325]] is that gap.
#
#   at HEAD    what CI does: every examined commit is judged against the ledger at HEAD. This is
#              what makes a finding STICKY -- a commit stays flagged until the entry changes -- and
#              it is why the flagged population here is tiny: 1196 commits of repair have already
#              closed nearly everything. A tiny population is a bad denominator for a widening.
#   as landed  the rule the script PRINTS -- *"write the closure in the commit that lands the
#              code"* -- judged against `git show <sha>:docs/TODO.md`, the ledger as that very
#              commit left it. This is the honest historical population, and the one [[T-1300]]
#              measured its 191-in-274 over.
#
# A reading is only adoptable if BOTH scopes show zero in the "closed NOTHING" column.
awk -F'\t' -v list="$LIST" -v nentries="$nentries" '
function partial_dated(l)  { return l ~ /\*\*PARTIAL[A-Za-z ]* [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ }
function partial_author(l) { return partial_dated(l) && (l ~ /\(agent / || l ~ /\(.?[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/) }

FILENAME ~ /head.status$/ { hstat[$1] = $2; hline[$1] = $3; next }
FILENAME ~ /facts.tsv$/   { k = $1 "\036" $2; own[k] = $3; wrote[k] = $4; ownline[k] = $5; next }
{
    sha = $1; date = $2; ids = $3; subj = $4
    n = split(ids, a, " ")
    delete okH; delete okL
    recorded_here = 0
    for (i = 1; i <= n; i++) {
        id = a[i]; k = sha "\036" id
        h = hstat[id]; hl = hline[id]; o = own[k]; ol = ownline[k]; w = wrote[k]

        # --- scope: at HEAD ---
        if (h == "CLOSED")                                   okH["today"] = 1
        if (h == "PARTIAL")                                  okH["partial"] = 1
        if (h == "PARTIAL" && partial_dated(hl))             okH["partialdated"] = 1
        if (h == "PARTIAL" && partial_author(hl))            okH["partialauthored"] = 1
        if (h == "PARTIAL" && w == "PARTIAL")                okH["partialhere"] = 1
        if (h == "CLOSED" || o == "CLOSED")                  okH["ownledger"] = 1
        if (h == "CLOSED" || o == "CLOSED" || (h == "PARTIAL" && w == "PARTIAL")) okH["both"] = 1

        # --- scope: as landed ---
        if (o == "CLOSED")                                   okL["today"] = 1
        if (o == "PARTIAL")                                  okL["partial"] = 1
        if (o == "PARTIAL" && partial_dated(ol))             okL["partialdated"] = 1
        if (o == "PARTIAL" && partial_author(ol))            okL["partialauthored"] = 1
        if (o == "PARTIAL" && w == "PARTIAL")                okL["partialhere"] = 1
        if (o == "CLOSED" || h == "CLOSED")                  okL["ownledger"] = 1
        if (o == "CLOSED" || h == "CLOSED" || (o == "PARTIAL" && w == "PARTIAL")) okL["both"] = 1

        if (w != "-") recorded_here = 1
    }
    examined++
    split("partial partialdated partialauthored partialhere ownledger both", order, " ")

    if (!okH["today"]) {
        flaggedH++; if (!recorded_here) flaggedH_nothing++
        for (c = 1; c <= 6; c++) {
            r = order[c]; if (!okH[r]) continue
            exH[r]++
            if (!recorded_here) { exH_nothing[r]++
                if (list) printf "  HEAD      %-16s CLOSED-NOTHING  %s  %s  %s\n", r, substr(sha,1,7), ids, substr(subj,1,64) > "/dev/stderr"
            } else if (list) printf "  HEAD      %-16s recorded        %s  %s  %s\n", r, substr(sha,1,7), ids, substr(subj,1,64) > "/dev/stderr"
        }
    }
    if (!okL["today"]) {
        flaggedL++; if (!recorded_here) flaggedL_nothing++
        for (c = 1; c <= 6; c++) {
            r = order[c]; if (!okL[r]) continue
            exL[r]++
            if (!recorded_here) { exL_nothing[r]++
                if (list) printf "  aslanded  %-16s CLOSED-NOTHING  %s  %s  %s\n", r, substr(sha,1,7), ids, substr(subj,1,64) > "/dev/stderr"
            } else if (list) printf "  aslanded  %-16s recorded        %s  %s  %s\n", r, substr(sha,1,7), ids, substr(subj,1,64) > "/dev/stderr"
        }
    }
}
END {
    split("partial partialdated partialauthored partialhere ownledger both", order, " ")
    printf "replay-partial-reading: %d ledger entries at HEAD, %d examined commits.\n\n", nentries, examined
    printf "  scope: AT HEAD (what CI runs, and what makes a finding sticky)\n"
    printf "    %d flagged by the reading that ships; %d of them recorded NOTHING in their own diff.\n", flaggedH, flaggedH_nothing
    printf "    %-17s %-20s %s\n", "reading", "newly excused", "...that closed NOTHING"
    for (c = 1; c <= 6; c++) { r = order[c]
        printf "    %-17s %4d of %-5d        %4d   %s\n", r, exH[r]+0, flaggedH, exH_nothing[r]+0,
            (exH_nothing[r]+0 == 0) ? "keeps the guard" : "DISQUALIFIED" }
    printf "\n  scope: AS LANDED (the rule the script prints: close it in the commit that lands the code)\n"
    printf "    %d flagged by the reading that ships; %d of them recorded NOTHING in their own diff.\n", flaggedL, flaggedL_nothing
    printf "    %-17s %-20s %s\n", "reading", "newly excused", "...that closed NOTHING"
    for (c = 1; c <= 6; c++) { r = order[c]
        printf "    %-17s %4d of %-5d        %4d   %s\n", r, exL[r]+0, flaggedL, exL_nothing[r]+0,
            (exL_nothing[r]+0 == 0) ? "keeps the guard" : "DISQUALIFIED" }
}
' "$tmp/head.status" "$tmp/facts.tsv" "$tmp/examined.tsv"
