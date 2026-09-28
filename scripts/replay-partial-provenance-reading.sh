#!/bin/sh
# Replay the readings that could stop `ledger-lag-check.sh` punishing a PARTIAL line the SHARED
# INDEX handed to the wrong commit (T-1434).
#
#   ./scripts/replay-partial-provenance-reading.sh              # the table
#   ./scripts/replay-partial-provenance-reading.sh --list       # ...and name every (commit, push) pair each reading touches
#   ./scripts/replay-partial-provenance-reading.sh --window 400 # ...over the last 400 pushes instead of all of them
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. The same reason as
# `scripts/replay-partial-reading.sh`, `scripts/replay-reopen-reading.sh`,
# `scripts/replay-closure-reading.sh`, `scripts/replay-duplicate-reading.sh`,
# `scripts/replay-closure-code-lag.sh` and `scripts/replay-absent-addition-reading.sh`: every
# widening in this family has to answer *how many real verdicts would this newly excuse* and *how
# many of those would it get WRONG* before it is allowed to ship. [[T-1300]] answered its version
# with 191 in 274 and took a warning; [[T-1304]] answered its with 4 in 511 and earned a refusal;
# [[T-1356]]'s `wholeactive` and [[T-1385]]'s `openrecent` were each their own ticket's preferred
# reading and each was DISQUALIFIED by its replay for being blind to the case that founded it.
#
# THE QUESTION ([[T-1434]]). [[T-1359]] decided that a `**PARTIAL` first line excuses ONLY the
# commit whose own diff wrote it -- `partialhere` -- because the loose reading ("PARTIAL is not
# open") is RIDEABLE: write `**PARTIAL` once and every later commit naming that id passes for free,
# forever, which is the hole [[T-1298]] built the check to close. That decision is not in dispute
# here and this script re-measures it as the control.
#
# What T-1359 did not know is that `partialhere` asks a question the shared index cannot always
# answer honestly. `scripts/agent-commit.sh` stages WHOLE FILES ([[T-679]]), and `docs/TODO.md` is
# the one file every agent edits, so an in-flight ledger edit lands under whoever commits that path
# NEXT -- not under its author. Measured on 2026-09-27, twice in one run of the check:
#
#   a4c12b09  landed the T-1366 widget-cost sweep and touched no ledger; the T-1366 `**PARTIAL`
#             line widgetcost2 had already written was carried into `f94178e4` by a third agent
#             (`notesync`, closing T-1352), and `4421e1f1` then rewrote it to name `a4c12b09`.
#   3c9d28dd  landed the T-1122 MCP work and touched no ledger; its `**PARTIAL` line was carried
#             the same way, and `41bad546` rewrote it to name `3c9d28dd`.
#
# Both agents wrote a correct PARTIAL line for their own ticket. Neither could carry it, because by
# the time their code commit ran the ledger path was already clean. There is no retroactive remedy
# inside T-1359's rule: a follow-up ledger commit is exactly what `mode 2d` refuses.
#
# THE READINGS. All of them widen the guard, and a widening is only safe if it does not excuse the
# case the guard was BUILT for: T-1298's commit that lands code, names ids, and records NOTHING.
#
#   today          what ships: an id counts closed if it is closed at the evaluation rev, or closed
#                  in that commit's own ledger ([[T-1325]]'s `ownledger`), and a `**PARTIAL` first
#                  line excuses the commit whose own diff wrote it (T-1359's `partialhere`). The
#                  baseline every other row is measured against.
#   partialpush    T-1434's candidate (a): a `**PARTIAL` line written by ANY commit in the same
#                  PUSH as this one. Scoped by the push rather than by all of history, so it cannot
#                  be ridden forever -- but see the table: this repository pushes one commit at a
#                  time, so the reading is almost never REACHED and cannot answer the ticket.
#   partialnamed   THE CANDIDATE THIS SCRIPT WAS WRITTEN FOR, and it is not one of the three
#                  readings T-1434 listed. The entry reads `**PARTIAL` at the evaluation rev AND
#                  that first line NAMES THIS COMMIT'S SHA -- a backticked hex run of seven or more
#                  characters that is a prefix of the commit's own sha. It is the provenance the
#                  ledger already writes for a closure: the shipped refusal message asks for
#                  ``- [T-n] **CLOSED <date> (`<sha>`) -- ...``, and a PARTIAL line that carries a
#                  sha is that same statement one step short of done. It CANNOT be ridden by a
#                  commit that did not do the work, because a rider would have to be NAMED, by sha,
#                  on the line -- and naming a sha is a deliberate act by a later author about one
#                  specific commit, not a state a commit can drift into. Note that this is strictly
#                  NARROWER than what `**CLOSED` already buys: a closure at the evaluation rev
#                  excuses every commit naming that id, sha or no sha.
#   partialany     THE CONTROL, and it is expected to be DISQUALIFIED. T-1359's rejected loose
#                  reading: any id the commit names reads `**PARTIAL` at the evaluation rev. It is
#                  in the table because a disqualifying column that never disqualifies anything is
#                  indistinguishable from a disqualifying column that CANNOT REACH the reading --
#                  [[T-1394]]'s defect, and [[T-1325]]'s replay carries `headleg` for the same
#                  reason. `partialany` is this table's canary: if it ever stops being
#                  disqualified, the column is broken and this script REFUSES.
#
# THE POPULATION, and it is `replay-reopen-reading.sh`'s rather than `replay-partial-reading.sh`'s.
# This check is STICKY -- a finding does not expire -- so what it actually produced is a verdict per
# (COMMIT, PUSH) pair:
#
#     for every first-parent rev R, and every code-landing commit C reachable from R that names an
#     id filed at R, the verdict `ledger-lag-check.sh` would have printed had it run at R.
#
# First-parent only, so "C is an ancestor of R" is exactly "C is earlier in the list". It drops the
# commits of this history that are not on the mainline, which is ~1% and none of the cases below.
#
# THE DISQUALIFYING COLUMN, and read this before reading the table, because it is NOT the column
# the two sibling replays use and the difference is the whole of T-1434.
#
#   `replay-partial-reading.sh` and `replay-reopen-reading.sh` both disqualify a reading that
#   excuses a commit which RECORDED NOTHING IN ITS OWN DIFF. That column cannot decide this
#   ticket: `a4c12b09` and `3c9d28dd` recorded nothing in their own diffs -- that is the defect --
#   so a column defined that way answers the question by assuming it. It is still REPORTED here,
#   and `partialnamed`'s number in it is expected to be non-zero and is the ticket restated.
#
#   The column that DECIDES is the next one: *how many of the newly excused verdicts does the
#   ledger at the evaluation rev not NAME at all* -- no first line, for any id the commit's subject
#   names, carrying a backticked sha run that is a prefix of that commit's sha. A commit nobody has
#   written down is exactly T-1298's shape, and all three founding cases fail this test at every
#   push where they are flagged.
#
#   AND `partialnamed` SCORES 0 IN IT BY CONSTRUCTION, which is the honest statement of the same
#   defect T-1394 caught in itself. So this script does not rest on that 0. Three other things,
#   each of which CAN come out the other way, decide it instead:
#     * the control `partialany` must be disqualified by that column, with a real number;
#     * the REFUSED RIDES floor -- the verdicts the loose reading `partialany` excuses and
#       `partialnamed` REFUSES. If the two never once differ on this history then the narrowness
#       that is the whole argument for `partialnamed` was never exercised and its clean column is
#       an artefact of the population, so the script REFUSES rather than reports a sweep. The
#       strongest shape of a ride -- sitting under a `**PARTIAL` line that carries somebody ELSE'S
#       sha -- is reported as a sub-count and deliberately NOT floored: this repository has never
#       written one, and a floor on a shape that has never occurred refuses every honest run. The
#       synthetic version of it is `ledger-lag-check.sh`'s own `mode 2e`, which is where a shape
#       history has not produced belongs;
#     * the RETROACTIVITY spread -- how many pushes pass between a commit and the rev whose ledger
#       first names it. A provenance repair lands within a push or two. An amnesty handed out two
#       hundred pushes later is a different animal, and the number is printed rather than assumed.
#
# FOUNDING CASES. Checked BY NAME rather than in aggregate, and refused over rather than reported:
# T-1298's three commits that recorded nothing (`00d576f`, `e4719e3`, `44eced5`) must still be
# FLAGGED and must be excused by NOTHING; and T-1434's own two cases (`a4c12b09`, `3c9d28dd`) must
# be flagged by `today` and excused by the adopted reading. A reading blind to either half is not
# adoptable, whatever the table says.
#
# FLOORS ARE COUNTED, NOT APPLIED. `replay-reopen-reading.sh`'s first draft gated on the shipped
# LEDGER-LAG-VACUOUS floors and left 981 of 1221 pushes unjudged, which dropped its own founding
# case out of range and scored its adopted reading a flawless 0 having never evaluated it. Same
# decision here: the floors ask whether a RUN is trustworthy, this script asks what a READING says,
# and the count of below-floor pushes is printed.
set -u

WINDOW=0
LIST=0
MIN_REVS=${CADENCE_REPLAY_PROV_MIN_REVS:-200}
MIN_FLAGGED=${CADENCE_REPLAY_PROV_MIN_FLAGGED:-100}
MIN_FLAGGED_NOTHING=${CADENCE_REPLAY_PROV_MIN_NOTHING:-50}
MIN_DECLINED=${CADENCE_REPLAY_PROV_MIN_DECLINED:-1}
MIN_NEWLY=${CADENCE_REPLAY_PROV_MIN_NEWLY:-2}

# The shipped floors, replayed per rev so the population is the one CI would really have judged.
LAG_MIN_COMMITS=${CADENCE_LEDGER_LAG_MIN_COMMITS:-200}
LAG_MIN_ENTRIES=${CADENCE_LEDGER_LAG_MIN_ENTRIES:-300}
LAG_MIN_EXAMINED=${CADENCE_LEDGER_LAG_MIN_EXAMINED:-120}

ADOPTED=partialnamed
CONTROL=partialany
FOUND_NOTHING="00d576f e4719e3 44eced5"
FOUND_PROV="a4c12b09 3c9d28dd"

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-prov-XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

# The status reading, spelled once and taken from the shipped scripts rather than invented here:
# `closure_visible` / `first_line_closed` are `agent-commit.sh`'s `$LEDGER_CLOSURE_READING`
# (T-1335) and `first_line_partial` is `ledger-view.sh`'s PARTIAL status (T-1359).
#
# `sha_tokens` is new and is this script's own: the backticked hex runs on a first line, which is
# how this ledger has always attributed a closure -- ``**CLOSED 2026-09-27 (`1273ea8`) -- ...``.
# Seven characters minimum, written out rather than with an ERE interval, because the interval
# operator is not portable across the awks this repository runs on.
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
function rank(s) { return (s == "CLOSED") ? 2 : (s == "PARTIAL") ? 1 : 0 }
function sha_tokens(s,   bq, out, t, rest) {
    bq = sprintf("%c", 96); out = ""; rest = s
    while (match(rest, bq "[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*" bq)) {
        t = substr(rest, RSTART + 1, RLENGTH - 2)
        out = out " " t
        rest = substr(rest, RSTART + RLENGTH)
    }
    return substr(out, 2)
}
'

# --- the evaluation revs -------------------------------------------------------
if [ "$WINDOW" -gt 0 ]; then
    git rev-list --first-parent -n "$WINDOW" HEAD | sed '1!G;h;$!d' > "$tmp/fp.txt"
    SCOPE="the last $WINDOW pushes"
else
    git rev-list --first-parent --reverse HEAD > "$tmp/fp.txt"
    SCOPE="every push on the mainline"
fi
nrevs=$(grep -c '^' "$tmp/fp.txt" || true)

# --- the ledger at every rev that changed it -----------------------------------
#
# Only the revs that touched a ledger can move the status, so only those are extracted and the map
# is carried forward to the pushes in between -- the same halving `replay-reopen-reading.sh` does.
#
# SHA TOKENS ARE KEPT ONLY FOR ENTRIES THAT ARE NOT CLOSED, and that is not an optimisation with a
# correctness hole in it: a verdict is only FLAGGED when every id the commit names is open at the
# evaluation rev (PARTIAL included -- PARTIAL is open here), so a CLOSED entry can never be one of
# the ids any column below reads. Carrying the sha runs of ~700 closed entries across ~560 revs
# would multiply this script's memory for a column that is unreachable by construction.
STATUS_AWK=$READING$(cat <<'AWK'
$1 == "T" && $2 ~ /^## / { sec = $2; next }
$2 !~ /^- \[T-[0-9]+\]/ { next }
{
    lines++
    id = entry_id($2); st = "OPEN"
    if ($1 == "D")                              st = "CLOSED"
    else if (sec ~ /^## (Done|Cancelled)/)      st = "CLOSED"
    else if (first_line_closed($2))             st = "CLOSED"
    else if (first_line_partial($2))            st = "PARTIAL"
    # An id is closed while ANY entry of it is closed -- the T-1303 duplicate shape.
    if (!(id in seen) || rank(st) > rank(seen[id])) { seen[id] = st; toks[id] = sha_tokens($2) }
}
END {
    printf "#\t%d\t\n", lines + 0
    for (id in seen) printf "%s\t%s\t%s\n", id, seen[id], (seen[id] == "CLOSED") ? "" : toks[id]
}
AWK
)

git log --format=%H --first-parent -- "$TODO" "$DONE" | sort > "$tmp/ledgerrevs.txt"
: > "$tmp/revstatus.txt"
while read -r r; do
    grep -qx "$r" "$tmp/ledgerrevs.txt" || continue
    { git show "$r:$TODO" 2>/dev/null | grep -E '^(## |- \[T-)' | sed 's/^/T	/'
      git show "$r:$DONE" 2>/dev/null | grep -E '^- \[T-' | sed 's/^/D	/'
    } | awk -F'\t' "$STATUS_AWK" | sed "s/^/$r	/" >> "$tmp/revstatus.txt"
done < "$tmp/fp.txt"

# --- the commits the check examines --------------------------------------------
CANDS_AWK=$READING$(cat <<'AWK'
function is_code(p) {
    if (p == "") return 0
    if (p ~ /^docs\//) return 0
    if (p ~ /(^|\/)AGENTS\.md$/) return 0
    if (p == "CLAUDE.md" || p == "README.md") return 0
    return 1
}
function subject_ids(s,   tok, sep, prevnum, a, b, i, rest) {
    delete SID; rest = s; prevnum = -1
    while (match(rest, /T-[0-9]+/)) {
        tok = substr(rest, RSTART, RLENGTH); sep = substr(rest, 1, RSTART - 1); b = substr(tok, 3) + 0
        if (prevnum >= 0 && sep ~ /^ *\.\.+ *$/) {
            a = prevnum
            if (b > a && b - a <= 64) for (i = a + 1; i < b; i++) SID["T-" i] = 1
        }
        SID[tok] = 1; prevnum = b; rest = substr(rest, RSTART + RLENGTH)
    }
}
function flush(   id, list) {
    if (c_sha == "" || c_code == 0) return
    list = ""; for (id in c_ids) list = list " " id
    if (list == "") return
    printf "%s\t%s\t%s\t%s\n", c_sha, c_date, substr(list, 2), c_subj
}
substr($0,1,1) == "\001" {
    flush(); n = split(substr($0, 2), f, "\037")
    c_sha = f[1]; c_date = f[2]; c_subj = (n >= 3) ? f[3] : ""; c_code = 0
    subject_ids(c_subj); delete c_ids; for (k in SID) c_ids[k] = 1; next
}
$0 != "" && is_code($0) { c_code++ }
END { flush() }
AWK
)
git log --format='%x01%H%x1f%ad%x1f%s' --date=short --name-only --first-parent HEAD > "$tmp/log.txt" || exit 2
awk "$CANDS_AWK" "$tmp/log.txt" > "$tmp/cands.tsv"

# --- what each commit's own ledger diff WROTE ----------------------------------
#
# One pass over the whole history rather than one `git show` per commit. An entry ARRIVING in the
# archive is a closure by the same rule the status reading uses. NOT first-parent-only: a PARTIAL
# line written on a side branch belongs to the push that merged it, which is what `partialpush`
# below reads, so the side-branch commits have to be in this file even though they are never
# candidates themselves.
WROTE_AWK=$READING$(cat <<'AWK'
substr($0,1,1) == "\001" { sha = substr($0,2); next }
/^diff --git / { indone = ($0 ~ /TODO_DONE\.md$/); next }
substr($0,1,1) != "+" { next }
{
    line = substr($0, 2)
    if (line !~ /^- \[T-[0-9]+\]/) next
    if (indone)                        printf "%s\t%s\tC\n", sha, entry_id(line)
    else if (first_line_closed(line))  printf "%s\t%s\tC\n", sha, entry_id(line)
    else if (first_line_partial(line)) printf "%s\t%s\tP\n", sha, entry_id(line)
}
AWK
)
git log --format='%x01%H' --unified=0 -p -- "$TODO" "$DONE" 2>/dev/null \
    | awk "$WROTE_AWK" > "$tmp/wrote.tsv"

# --- which push each commit arrived in -----------------------------------------
#
# `partialpush` is T-1434's candidate (a) and it needs a PUSH, not a commit. A first-parent rev R
# brings `git rev-list R --not R^`: itself, plus whatever a merge carried in. Only a MERGE can
# bring more than itself, so only merges are expanded -- 1235 `git rev-list` calls to learn that
# 1223 of them answer "itself" is a minute this script does not need to spend.
awk '{ print $1 "\t" $1 }' "$tmp/fp.txt" > "$tmp/push.tsv"
git log --first-parent --format='%H %P' HEAD | awk 'NF > 2 { print $1 }' > "$tmp/merges.txt"
while read -r r; do
    [ -n "$r" ] || continue
    git rev-list "$r" --not "$r^" 2>/dev/null | sed "s/\$/	$r/" >> "$tmp/push.tsv"
done < "$tmp/merges.txt"

# --- the table -----------------------------------------------------------------
TABLE_AWK=$(cat <<'AWK'
FILENAME ~ /fp\.txt$/ { idx[$1] = ++nrev; revat[nrev] = $1; next }
FILENAME ~ /revstatus\.txt$/ {
    i = idx[$1]; if (!i) next
    if ($2 == "#") { nlines[i] = $3 + 0; isledger[i] = 1; next }
    rs[i] = rs[i] "\034" $2 "\035" $3 "\035" $4; next
}
FILENAME ~ /cands\.tsv$/ { i = idx[$1]; if (!i) next
    csha[i] = $1; cids[i] = $3; csubj[i] = $4; iscand[i] = 1; next }
FILENAME ~ /wrote\.tsv$/ { wrote[$1 "\036" $2] = $3; wsha[++nwrote] = $1; wid[nwrote] = $2; wst[nwrote] = $3; next }
FILENAME ~ /push\.tsv$/  { pushof[$1] = $2; next }

# Does the first line `line_toks` name commit `sha`? A backticked hex run of >= 7 characters that
# is a PREFIX of the full sha. Tested against a real sha rather than by shape, so an English word
# that happens to be hex (`defaced`) cannot match anything.
function names_sha(line_toks, sha,   n, t, j) {
    if (line_toks == "") return 0
    n = split(line_toks, t, " ")
    for (j = 1; j <= n; j++) if (index(sha, t[j]) == 1) return 1
    return 0
}
function verdict(r) {
    if (r == "today")          return "the baseline every other row is measured against"
    if (exc[r] + 0 == 0)       return "NEVER REACHED (this history pushes one commit at a time)"
    if (excu[r] + 0 != 0)      return "DISQUALIFIED (excuses a commit the ledger never names)"
    if (f_excused[r] + 0 != 0) return "DISQUALIFIED (excuses a T-1298 founding case)"
    if (f_prov_exc[r] + 0 == 0) return "DISQUALIFIED (blind to the case T-1434 was filed for)"
    return "keeps the guard"
}
function load(r,   n, j, t, p, q, id) {
    delete cur; delete curtok
    n = split(rs[r], t, "\034")
    for (j = 1; j <= n; j++) {
        if (t[j] == "") continue
        p = index(t[j], "\035"); id = substr(t[j], 1, p - 1)
        q = index(substr(t[j], p + 1), "\035")
        cur[id] = substr(t[j], p + 1, q - 1)
        curtok[id] = substr(t[j], p + q + 1)
    }
}
END {
    NRD = split("today partialpush partialnamed partialany", order, " ")
    m = 0; for (i = 1; i <= nrev; i++) if (iscand[i]) sorted[++m] = i
    ncand = m
    nf = split(found_nothing, fn, " ")
    np = split(found_prov, fp, " ")

    # `partialpush` folded down to a lookup, once: (push, id) -> some commit of that push wrote a
    # **PARTIAL first line for that id. Asked inline it is a scan of every ledger write per flagged
    # verdict, which on this history is a quarter of a billion comparisons.
    for (w = 1; w <= nwrote; w++)
        if (wst[w] == "P" && (wsha[w] in pushof)) pwrote[pushof[wsha[w]] "\036" wid[w]] = 1

    # PASS ONE. Walk every push in order carrying the ledger map forward, and collect the two
    # things only a forward walk can supply: the status each candidate commit's OWN ledger carried
    # (T-1325's `ownledger` leg, part of the `today` baseline), and the FIRST push at which the
    # ledger names each candidate commit -- the retroactivity spread.
    for (r = 1; r <= nrev; r++) {
        if (isledger[r]) load(r)
        if (iscand[r]) {
            nid = split(cids[r], ids, " ")
            for (k = 1; k <= nid; k++)
                ownst[r "\036" ids[k]] = (ids[k] in cur) ? cur[ids[k]] : "ABSENT"
        }
        # The retroactivity spread, and it is asked of **PARTIAL lines only: a closure's sha is
        # T-1335's business and is already an excuse by itself, so mixing the two would report a
        # lag this widening does not cause. Only a ledger rev can move it.
        if (isledger[r]) for (q = 1; q <= ncand; q++) {
            ci = sorted[q]; if (ci > r) break
            if (ci in namedat) continue
            nid = split(cids[ci], ids, " ")
            for (k = 1; k <= nid; k++)
                if (cur[ids[k]] == "PARTIAL" && names_sha(curtok[ids[k]], csha[ci])) { namedat[ci] = r; break }
        }
        if (r == nrev) { for (id in cur) { headst[id] = cur[id]; headtok[id] = curtok[id] } }
    }

    # PASS TWO. One verdict per (commit, push) pair, in the order the pushes happened.
    delete cur; delete curtok
    for (r = 1; r <= nrev; r++) {
        if (isledger[r]) load(r)
        nex = 0
        for (q = 1; q <= ncand; q++) { ci = sorted[q]; if (ci > r) break
            nid = split(cids[ci], ids, " ")
            for (k = 1; k <= nid; k++) if (ids[k] in cur) { nex++; break } }
        if (r < lag_min_commits || nlines[r] + 0 < lag_min_entries || nex < lag_min_examined) nvacuous++
        nlive++
        for (q = 1; q <= ncand; q++) { ci = sorted[q]; if (ci > r) break
            sha = csha[ci]; nid = split(cids[ci], ids, " ")
            known = 0; openn = 0; recorded = 0
            ownclosed = 0; headclosed = 0
            p_here = 0; p_push = 0; p_named = 0; p_any = 0; p_other = 0
            isnamed = 0
            for (k = 1; k <= nid; k++) {
                id = ids[k]
                if (wrote[sha "\036" id] != "")       recorded = 1
                if (headst[id] == "CLOSED")           headclosed = 1
                if (ownst[ci "\036" id] == "CLOSED")  ownclosed = 1
                st = (id in cur) ? cur[id] : "ABSENT"
                if (st == "ABSENT") continue
                known++
                if (names_sha(curtok[id], sha)) isnamed = 1
                if (st == "CLOSED") continue
                openn++
                if (st != "PARTIAL") continue
                p_any = 1
                if (wrote[sha "\036" id] == "P") p_here = 1
                if (names_sha(curtok[id], sha)) p_named = 1
                else if (curtok[id] != "")       p_other = 1
                # candidate (a): any commit of THIS commit's push wrote that PARTIAL line.
                if ((pushof[sha] "\036" id) in pwrote) p_push = 1
            }
            if (known == 0) continue
            # `today` = the shipped reading: closed at R, or closed in the commit's own ledger
            # (T-1325), or a PARTIAL line this commit's own diff wrote (T-1359).
            if (known != openn || p_here || ownclosed) continue
            flagged++
            if (!recorded) flagged_nothing++
            for (z = 1; z <= nf; z++) if (index(sha, fn[z]) == 1) f_flagged[fn[z]]++
            for (z = 1; z <= np; z++) if (index(sha, fp[z]) == 1) f_prov_flagged[fp[z]]++
            delete thisex
            for (c = 1; c <= NRD; c++) {
                rr = order[c]
                if (rr == "today") continue
                if (rr == "partialpush"  && !p_push)  continue
                if (rr == "partialnamed" && !p_named) continue
                if (rr == "partialany"   && !p_any)   continue
                exc[rr]++; thisex[rr] = 1
                if (!recorded) excn[rr]++
                if (!isnamed) {
                    excu[rr]++
                    if (list) printf "  excused   %-13s LEDGER-NAMES-NOBODY  C=%s R=%s  %s\n",
                        rr, substr(sha, 1, 7), substr(revat[r], 1, 7), cids[ci] > "/dev/stderr"
                } else if (list) printf "  excused   %-13s named                C=%s R=%s  %s\n",
                        rr, substr(sha, 1, 7), substr(revat[r], 1, 7), cids[ci] > "/dev/stderr"
                for (z = 1; z <= nf; z++) if (index(sha, fn[z]) == 1) { f_excused[rr]++; f_case[rr "\036" fn[z]]++ }
                for (z = 1; z <= np; z++) if (index(sha, fp[z]) == 1) { f_prov_exc[rr]++; f_pcase[rr "\036" fp[z]]++ }
            }
            # THE REFUSED RIDES, and this is the column that can disqualify `partialnamed`: the
            # verdicts the loose reading excuses and the adopted one REFUSES. If the two never once
            # differ on this history the narrowness is untested and the clean column above is an
            # artefact of the population. It is read off the READINGS rather than off the raw
            # predicates they are built from, and that is not a style choice -- the first draft
            # counted `p_any && !p_named` directly, and a mutation that collapsed `partialnamed`
            # into the control left this number unchanged at 2 while the table went DISQUALIFIED
            # and the script still exited 0. A floor computed beside the thing it measures cannot
            # see it move. `declined_othersha` is the strongest shape of the same thing -- a
            # **PARTIAL line carrying SOMEBODY ELSE'S sha -- and it is reported rather than
            # floored, because this repository has never written one and a floor on a shape that
            # has never occurred refuses every honest run. Its synthetic twin is mode 2f.
            if (thisex[control] && !thisex[adopted]) { declined++; if (p_other) declined_othersha++ }
        }
    }

    printf "replay-partial-provenance-reading: %s\n", scope
    printf "  %d pushes judged (%d of them below the shipped floors, counted and NOT skipped),\n", nlive + 0, nvacuous + 0
    printf "  %d code-landing commits naming ids.\n\n", ncand
    printf "  %d (commit, push) verdicts flagged by the reading that ships; %d of them recorded NOTHING\n", flagged + 0, flagged_nothing + 0
    printf "  in their own diff, and %d are a REFUSED RIDE -- a verdict the loose reading `%s`\n", declined + 0, control
    printf "  excuses and `%s` refuses, %d of them under a line carrying SOMEBODY ELSE'S sha.\n\n", adopted, declined_othersha + 0
    printf "  %-13s %-19s %-13s %-13s %s\n", "reading", "newly excused", "recorded", "ledger names", "verdict"
    printf "  %-13s %-19s %-13s %-13s %s\n", "",        "",              "NOTHING",  "NOBODY",       ""
    for (c = 1; c <= NRD; c++) { rr = order[c]
        printf "  %-13s %5d of %-10d %5d         %5d         %s\n",
            rr, exc[rr] + 0, flagged + 0, excn[rr] + 0, excu[rr] + 0, verdict(rr) }

    printf "\n  founding cases, checked by name rather than in aggregate:\n"
    for (z = 1; z <= nf; z++) {
        row = ""
        for (c = 1; c <= NRD; c++) if (order[c] != "today") row = row sprintf(" %s=%d", order[c], f_case[order[c] "\036" fn[z]] + 0)
        printf "    %s  T-1298, recorded NOTHING: flagged at %d push(es), excused:%s\n",
            fn[z], f_flagged[fn[z]] + 0, row
    }
    for (z = 1; z <= np; z++) {
        row = ""
        for (c = 1; c <= NRD; c++) if (order[c] != "today") row = row sprintf(" %s=%d", order[c], f_pcase[order[c] "\036" fp[z]] + 0)
        printf "    %s  T-1434, a sibling carried its PARTIAL line: flagged at %d push(es), excused:%s\n",
            fp[z], f_prov_flagged[fp[z]] + 0, row
    }

    # RETROACTIVITY. How long after a commit does the ledger first name it? A provenance repair
    # lands within a push or two; a two-hundred-push gap is an amnesty and would be a different
    # ticket. Printed rather than assumed, and the maximum is what the reader should look at.
    printf "\n  retroactivity: pushes between a commit and the first rev whose ledger names it\n"
    nn = 0; maxlag = -1
    for (ci in namedat) { lag = namedat[ci] - ci; nn++; sum += lag
        if (lag > maxlag) { maxlag = lag; maxsha = csha[ci] }
        if (lag == 0) lag0++ }
    if (nn == 0) printf "    no examined commit is named by any ledger line in this range.\n"
    else printf "    %d of %d examined commits are named by a **PARTIAL line at some point; %d in their own push, mean %.1f, max %d (%s).\n",
        nn, ncand, lag0 + 0, sum / nn, maxlag, substr(maxsha, 1, 7)

    fail = ""
    if (nrev < min_revs)
        fail = fail sprintf("\n  %d pushes in range (floor %d).", nrev, min_revs)
    if (flagged + 0 < min_flagged)
        fail = fail sprintf("\n  %d flagged verdicts (floor %d) -- a shallow clone or the wrong working directory looks like a clean sweep here.", flagged + 0, min_flagged)
    if (flagged_nothing + 0 < min_nothing)
        fail = fail sprintf("\n  %d flagged verdicts whose commit recorded nothing (floor %d) -- with none, the columns below have no population at all and every reading reads adoptable.", flagged_nothing + 0, min_nothing)
    if (declined + 0 < min_declined)
        fail = fail sprintf("\n  %d REFUSED RIDES (floor %d) -- `%s` and the loose reading `%s` agree on every verdict in this range, so the narrowness that is the whole argument for `%s` was never once exercised and its clean column is an artefact of the population rather than a fact about this repository.", declined + 0, min_declined, adopted, control, adopted)
    if (exc[adopted] + 0 < min_newly)
        fail = fail sprintf("\n  `%s` newly excuses %d verdict(s) (floor %d) -- it was never once reached by the columns that exist to disqualify it.", adopted, exc[adopted] + 0, min_newly)
    if (excu[control] + 0 == 0)
        fail = fail sprintf("\n  the control reading `%s` was NOT disqualified, so the `ledger names NOBODY` column no longer separates anything and a clean sweep above proves nothing.", control)
    if (fail != "") {
        printf "\nREFUSED (REPLAY-PROV-VACUOUS): this run cannot settle anything.%s\n", fail > "/dev/stderr"
        exit 4
    }

    for (z = 1; z <= nf; z++)
        if (f_flagged[fn[z]] + 0 == 0)
            fail = fail sprintf("\n  %s is flagged at no push in this range, so no reading above was judged against it.", fn[z])
    if (f_excused[adopted] + 0 != 0)
        fail = fail sprintf("\n  `%s` excuses a T-1298 founding case.", adopted)
    for (z = 1; z <= np; z++) {
        if (f_prov_flagged[fp[z]] + 0 == 0)
            fail = fail sprintf("\n  %s is flagged at no push, so the case T-1434 was filed for is not in this range.", fp[z])
        else if (f_pcase[adopted "\036" fp[z]] + 0 == 0)
            fail = fail sprintf("\n  `%s` does not excuse %s, so it is blind to the case that founded T-1434.", adopted, fp[z])
    }
    if (fail != "") {
        printf "\nREFUSED (REPLAY-PROV-FOUNDING-LOST): the adopted reading `%s` can no longer be checked against the cases that decide it.%s\n", adopted, fail > "/dev/stderr"
        exit 5
    }

    # AND THE TABLE HAS TO BE ACTED ON. A replay that PRINTS `DISQUALIFIED` beside the reading it
    # adopts and then exits 0 is a measurement nobody is obliged to read, which is [[T-1343]]'s
    # shape -- evidence only failure produces -- turned inside out. Caught by mutation: collapsing
    # `partialnamed` into the control marked it DISQUALIFIED in the table above and the run still
    # passed.
    if (verdict(adopted) != "keeps the guard") {
        printf "\nREFUSED (REPLAY-PROV-DISQUALIFIED): the adopted reading `%s` is %s.\n  This is the finding, not a failure of the run: do not widen the check.\n", adopted, verdict(adopted) > "/dev/stderr"
        exit 6
    }

    printf "\n  adopted: %s -- a **PARTIAL first line that NAMES this commit's sha is the same\n", adopted
    printf "  attribution a closure already carries, and it cannot be ridden by a commit nobody wrote\n"
    printf "  down. `partialpush` is T-1434's candidate (a) and this table is why it is not adopted.\n"
    printf "  `%s` is the control and is expected to be disqualified.\n", control
    exit 0
}
AWK
)

awk -F'\t' -v list="$LIST" -v scope="$SCOPE" -v adopted="$ADOPTED" -v control="$CONTROL" \
    -v found_nothing="$FOUND_NOTHING" -v found_prov="$FOUND_PROV" \
    -v lag_min_commits="$LAG_MIN_COMMITS" -v lag_min_entries="$LAG_MIN_ENTRIES" \
    -v lag_min_examined="$LAG_MIN_EXAMINED" -v min_revs="$MIN_REVS" -v min_flagged="$MIN_FLAGGED" \
    -v min_nothing="$MIN_FLAGGED_NOTHING" -v min_declined="$MIN_DECLINED" -v min_newly="$MIN_NEWLY" \
    "$TABLE_AWK" "$tmp/fp.txt" "$tmp/revstatus.txt" "$tmp/cands.tsv" "$tmp/wrote.tsv" "$tmp/push.tsv"
