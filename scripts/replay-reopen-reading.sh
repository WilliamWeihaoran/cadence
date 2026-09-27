#!/bin/sh
# Replay the readings that could stop `ledger-lag-check.sh` punishing a RE-OPENED entry (T-1325).
#
#   ./scripts/replay-reopen-reading.sh              # the table
#   ./scripts/replay-reopen-reading.sh --list       # ...and name every (commit, push) pair each reading touches
#   ./scripts/replay-reopen-reading.sh --window 400 # ...over the last 400 pushes instead of all of them
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. The same reason as
# `scripts/replay-partial-reading.sh`, `scripts/replay-closure-reading.sh`,
# `scripts/replay-duplicate-reading.sh`, `scripts/replay-closure-code-lag.sh` and
# `scripts/replay-absent-addition-reading.sh`: every widening in this family has to answer *how
# many real verdicts would this newly excuse* and *how many of those would it get WRONG* before it
# is allowed to ship. [[T-1300]] answered its version with 191 in 274 and took a warning;
# [[T-1304]] answered its with 4 in 511 and earned a refusal; [[T-1356]]'s `wholeactive` and
# [[T-1385]]'s `openrecent` were each their own ticket's preferred reading and each was
# DISQUALIFIED here for being blind to the case that founded it. A number quoted in prose rots with
# the next commit and cannot be re-derived by whoever wants to widen the rule again.
#
# THE QUESTION, which is [[T-1325]]'s and which the owner has now decided the shape of.
# `scripts/ledger-lag-check.sh` judges EVERY examined commit against the ledger at `<rev>` -- HEAD,
# in CI -- while the rule it PRINTS is about the commit itself: *"Write the closure in the commit
# that lands the code."* A finding does not expire, so re-open an entry that was correctly closed
# and the commit that closed it becomes a commit whose whole named set is open again -- on a commit
# that is in history and cannot be rewritten, so every later push is red until the ledger changes
# back. The owner's decision is that RE-OPENING AN ENTRY STAYS A PRACTICE: this ledger's entries
# are long-form and a closure appends an `**Originally:**` suffix that keeps one ticket's history in
# one place, which a follow-up-id rule would fragment, and the alternative was a second allowlist in
# a repository whose [[T-1170]] is the story of the first one. So the check is what changes.
#
# THE READINGS. All of them widen the guard, and a widening is only safe if it does not excuse the
# case the guard was BUILT for: [[T-1298]]'s commit that lands code, names ids, and records
# NOTHING. That is why the table's second column, not the first, is the one that decides.
#
#   today       what ships before this change: an id counts as closed iff it is closed in the
#               ledger at the evaluation rev (the T-1335 run on the entry's own first line, an
#               entry under `## Done` / `## Cancelled`, or an entry in the archive), plus
#               [[T-1359]]'s `partialhere` excuse -- a `**PARTIAL` first line excuses the commit
#               whose own diff wrote it. The baseline every other column is measured against.
#   ownhere     ...or THIS COMMIT'S OWN DIFF wrote the closure line for an id it names. The
#               narrowest repair: it credits the commit that wrote the closure and nothing else,
#               exactly as `partialhere` does. It covers the re-opened CLOSING commit and leaves
#               every later commit that landed code under an already-closed id sticky-red.
#   ownledger   [[T-1325]]'s disjunction, and what `ledger-lag-check.sh` ADOPTED: an id counts as
#               closed if it is closed at the evaluation rev OR closed in that commit's own
#               `git show <sha>:docs/TODO.md`. It restores each commit's verdict AT ITS OWN PUSH
#               and changes no other verdict.
#   headleg     THE CONTROL, and it is expected to be DISQUALIFIED. The disjunction's OTHER leg,
#               the one that already ships, read as a standalone reading: an id counts as closed if
#               it is closed at HEAD, whatever the evaluation rev said. It is what "repair the
#               ledger later" buys, and over the historical population it excuses thousands of
#               commits that recorded nothing at the time. It is in the table because a
#               disqualifying column that never disqualifies anything is indistinguishable from a
#               disqualifying column that cannot reach the reading -- [[T-1394]]'s defect, caught
#               by its own author before adoption. `headleg` is this table's canary: if it ever
#               stops being disqualified, the column is broken and this script REFUSES.
#
# THE POPULATION, and it is not the one `replay-partial-reading.sh` used. That script measured at
# HEAD and as-landed; at HEAD the flagged population is ZERO on a green run, which is a useless
# denominator for a widening, and as-landed measures the disjunction's other leg. What a sticky
# check actually produced is a verdict per (COMMIT, PUSH) pair:
#
#     for every first-parent rev R, and every code-landing commit C reachable from R that names an
#     id filed at R, the verdict `ledger-lag-check.sh` would have printed had it run at R.
#
# AND IT IS WHY THE SIBLING'S TABLE SAYS SOMETHING ELSE. `scripts/replay-partial-reading.sh` carries
# an `ownledger` row that reads `199 of 204 ... 199   DISQUALIFIED`, and that is not this reading
# scoring badly -- in that script's AS-LANDED scope the baseline is *closed in the commit's own
# ledger*, so its `ownledger` column measures the leg that ALREADY SHIPS (closed at HEAD), which is
# `headleg` here and is disqualified in both tables for the same reason. The leg this script
# measures is the other one, and the only scope that can see it is a per-push one.
#
# First-parent only, so "C is an ancestor of R" is exactly "C is earlier in the list" -- no
# ancestry test to get subtly wrong. It drops the 14 commits of this history that are not on the
# mainline, which is 1.1% and none of the cases below. Revs that do not meet the SHIPPED floors are
# skipped, because there the real check refuses LEDGER-LAG-VACUOUS and prints no verdict at all;
# the count of those is reported.
#
# WHAT "RECORDED NOTHING" MEANS, and it is the whole point of the second column: a commit RECORDED
# its work if its own diff to either ledger added a first line, for an id its subject names,
# carrying a closure run or a `**PARTIAL` run. That is `replay-partial-reading.sh`'s test, kept
# identical. [[T-1298]]'s three founding cases -- `00d576f`, `e4719e3`, `44eced5` -- record nothing
# by it, and any reading that excuses one of them is disqualified however good its first column is.
#
# REACHABILITY, which is the question [[T-1394]] taught this family to ask of its own instrument.
# `ownledger` can only differ from `today` where an id went CLOSED -> OPEN between a commit and a
# later push, so if this history has no such transition the adopted reading is never once evaluated
# by the column that exists to disqualify it and its 0 is an artefact of the population. The
# transitions are therefore COUNTED and printed, and both the count and the number of pairs the
# adopted reading newly excuses are FLOORS that refuse rather than report a clean sweep.
#
# FOUNDING CASES. Checked by name rather than in aggregate, and refused over rather than reported:
# T-1298's three commits that recorded nothing must still be FLAGGED and must NOT be excused, and
# T-1325's own shape -- a commit that wrote its closure and had it re-opened underneath it -- must
# be flagged by `today` and excused by the adopted reading. A reading that is blind to either half
# is not adoptable, whatever the table says.
set -u

WINDOW=0
LIST=0
MIN_REVS=${CADENCE_REPLAY_REOPEN_MIN_REVS:-200}
MIN_FLAGGED=${CADENCE_REPLAY_REOPEN_MIN_FLAGGED:-100}
MIN_FLAGGED_NOTHING=${CADENCE_REPLAY_REOPEN_MIN_NOTHING:-50}
MIN_REOPENS=${CADENCE_REPLAY_REOPEN_MIN_REOPENS:-1}
MIN_NEWLY=${CADENCE_REPLAY_REOPEN_MIN_NEWLY:-1}

# The shipped floors, replayed per rev so the population is the one CI would really have judged.
LAG_MIN_COMMITS=${CADENCE_LEDGER_LAG_MIN_COMMITS:-200}
LAG_MIN_ENTRIES=${CADENCE_LEDGER_LAG_MIN_ENTRIES:-300}
LAG_MIN_EXAMINED=${CADENCE_LEDGER_LAG_MIN_EXAMINED:-120}

ADOPTED=ownledger
CONTROL=headleg
FOUND_NOTHING="00d576f e4719e3 44eced5"
FOUND_REOPEN=1273ea8

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-reopen-XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

# The status reading, spelled once and taken from the shipped scripts rather than invented here:
# `closure_visible` / `first_line_closed` are `agent-commit.sh`'s `$LEDGER_CLOSURE_READING`
# (T-1335) and `first_line_partial` is `ledger-view.sh`'s PARTIAL status (T-1359).
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
# The status only moves at a commit that touched a ledger, so only those are extracted and the map
# is carried forward to the pushes in between -- 562 `git show` pairs rather than 1220, which is
# the difference between ~24 s and ~50 s. `grep` first, because the awk that reads the status is
# the expensive half and `docs/TODO.md` is ~1.8 MB per revision of which ~800 lines matter.
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
    if (!(id in seen) || rank(st) > rank(seen[id])) seen[id] = st
}
END { printf "#\t%d\n", lines + 0; for (id in seen) printf "%s\t%s\n", id, seen[id] }
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
# One pass over the whole history rather than one `git show` per commit: `--unified=0` keeps it to
# the changed lines and the two ledgers together are under 5 MB of diff for 1200 commits. An entry
# ARRIVING in the archive is a closure by the same rule the status reading uses.
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
git log --format='%x01%H' --first-parent --unified=0 -p -- "$TODO" "$DONE" 2>/dev/null \
    | awk "$WROTE_AWK" > "$tmp/wrote.tsv"

# --- the table -----------------------------------------------------------------
TABLE_AWK=$(cat <<'AWK'
FILENAME ~ /fp\.txt$/ { idx[$1] = ++nrev; revat[nrev] = $1; next }
FILENAME ~ /revstatus\.txt$/ {
    i = idx[$1]; if (!i) next
    if ($2 == "#") { nlines[i] = $3 + 0; isledger[i] = 1; next }
    rs[i] = rs[i] " " $2 ":" $3; next
}
FILENAME ~ /cands\.tsv$/ { i = idx[$1]; if (!i) next
    csha[i] = $1; cids[i] = $3; csubj[i] = $4; iscand[i] = 1; next }
FILENAME ~ /wrote\.tsv$/ { wrote[$1 "\036" $2] = $3; if ($3 == "C") wroteclosure[$1] = 1; next }

# Does reading r excuse commit C at rev R? One function for the table, the floors and the founding
# cases, so no reading can score clean in the table and be blind where it is pinned.
function excuses(r, sha, ownclosed, headclosed) {
    if (r == "today")     return 0
    if (r == "ownhere")   return (sha in wroteclosure)
    if (r == "ownledger") return ownclosed
    if (r == "headleg")   return headclosed
    return 0
}
function verdict(r) {
    if (r == "today")          return "the baseline every other row is measured against"
    if (exc[r] + 0 == 0)       return "never reached"
    if (excn[r] + 0 != 0)      return "DISQUALIFIED (excuses a commit that recorded nothing)"
    if (f_excused[r] + 0 != 0) return "DISQUALIFIED (excuses a T-1298 founding case)"
    if (f_reopen_exc[r] + 0 == 0) return "DISQUALIFIED (blind to the re-open T-1325 was filed for)"
    return "keeps the guard"
}
# Load the ledger map that rev `r` left, into `cur`.
function load(r,   n, j, p, t) {
    delete cur; n = split(rs[r], t, " ")
    for (j = 1; j <= n; j++) { if (t[j] == "") continue; p = index(t[j], ":")
        cur[substr(t[j], 1, p - 1)] = substr(t[j], p + 1) }
}
END {
    NRD = split("today ownhere ownledger headleg", order, " ")
    m = 0; for (i = 1; i <= nrev; i++) if (iscand[i]) sorted[++m] = i
    ncand = m
    nf = split(found_nothing, fn, " ")

    # PASS ONE. Walk every push in order carrying the ledger map forward, and collect two things
    # nothing else can supply: the CLOSED -> OPEN transitions, which are the whole reachability
    # denominator for `ownledger`, and the status each candidate commit's OWN ledger carried for
    # the ids it names -- the same `git show <sha>:docs/TODO.md` the check's second pass reads.
    for (r = 1; r <= nrev; r++) {
        if (isledger[r]) {
            load(r)
            for (id in cur) {
                if ((id in prevst) && prevst[id] == "CLOSED" && cur[id] != "CLOSED") {
                    nreopen++
                    if (list) printf "  reopen    %s  %s  CLOSED -> %s\n",
                        substr(revat[r], 1, 7), id, cur[id] > "/dev/stderr"
                }
                prevst[id] = cur[id]
            }
        }
        if (iscand[r]) {
            nid = split(cids[r], ids, " ")
            for (k = 1; k <= nid; k++)
                ownst[r "\036" ids[k]] = (ids[k] in cur) ? cur[ids[k]] : "ABSENT"
        }
        if (r == nrev) for (id in cur) headst[id] = cur[id]
    }

    # PASS TWO. One verdict per (commit, push) pair, in the order the pushes happened.
    delete cur
    for (r = 1; r <= nrev; r++) {
        if (isledger[r]) load(r)
        # THE SHIPPED FLOORS ARE COUNTED AND NOT APPLIED, and that is a decision this script was
        # forced into rather than a convenience. Gating on them first -- below any of them the real
        # check refuses LEDGER-LAG-VACUOUS and prints nothing -- left 981 of 1221 pushes unjudged
        # and dropped `1273ea8`, the ONE re-open in this history, out of the range entirely: the
        # adopted reading then scored a flawless 0 in the disqualifying column having never once
        # been evaluated. That is [[T-1394]]'s defect exactly, an interval that excludes the case,
        # and it is caught here only because the founding case is pinned BY NAME. The floors ask
        # whether a RUN is trustworthy; this script asks what a READING says, and a reading's
        # verdict at a rev is well defined whether or not CI would have trusted the run.
        nex = 0
        for (q = 1; q <= ncand; q++) { ci = sorted[q]; if (ci > r) break
            nid = split(cids[ci], ids, " ")
            for (k = 1; k <= nid; k++) if (ids[k] in cur) { nex++; break } }
        if (r < lag_min_commits || nlines[r] + 0 < lag_min_entries || nex < lag_min_examined) nvacuous++
        nlive++
        for (q = 1; q <= ncand; q++) { ci = sorted[q]; if (ci > r) break
            sha = csha[ci]; nid = split(cids[ci], ids, " ")
            known = 0; openn = 0; pexcuse = 0; ownclosed = 0; headclosed = 0; recorded = 0
            for (k = 1; k <= nid; k++) {
                id = ids[k]
                if (wrote[sha "\036" id] != "")       recorded = 1
                if (headst[id] == "CLOSED")           headclosed = 1
                if (ownst[ci "\036" id] == "CLOSED")  ownclosed = 1
                st = (id in cur) ? cur[id] : "ABSENT"
                if (st == "ABSENT") continue
                known++
                if (st == "CLOSED") continue
                openn++
                if (st == "PARTIAL" && wrote[sha "\036" id] == "P") pexcuse = 1
            }
            if (known == 0) continue
            if (known != openn || pexcuse) continue          # `today` does not flag it
            flagged++; if (!recorded) flagged_nothing++
            for (z = 1; z <= nf; z++) if (index(sha, fn[z]) == 1) f_flagged[fn[z]]++
            if (index(sha, found_reopen) == 1) f_reopen_flagged++
            for (c = 1; c <= NRD; c++) {
                rr = order[c]
                if (!excuses(rr, sha, ownclosed, headclosed)) continue
                exc[rr]++
                if (!recorded) {
                    excn[rr]++
                    if (list) printf "  excused   %-10s RECORDED-NOTHING  C=%s R=%s  %s\n",
                        rr, substr(sha, 1, 7), substr(revat[r], 1, 7), cids[ci] > "/dev/stderr"
                } else if (list) printf "  excused   %-10s recorded          C=%s R=%s  %s\n",
                        rr, substr(sha, 1, 7), substr(revat[r], 1, 7), cids[ci] > "/dev/stderr"
                for (z = 1; z <= nf; z++) if (index(sha, fn[z]) == 1) { f_excused[rr]++; f_case[rr "\036" fn[z]]++ }
                if (index(sha, found_reopen) == 1) f_reopen_exc[rr]++
            }
        }
    }

    printf "replay-reopen-reading: %s\n", scope
    printf "  %d pushes judged (%d of them below the shipped floors, counted and NOT skipped -- see\n", nlive + 0, nvacuous + 0
    printf "  the note in PASS TWO), %d code-landing commits naming ids,\n", ncand
    printf "  %d CLOSED -> OPEN transition(s) in this ledger over that range.\n\n", nreopen + 0
    printf "  %d (commit, push) verdicts flagged by the reading that ships; %d of them recorded NOTHING.\n\n",
        flagged + 0, flagged_nothing + 0
    printf "  %-11s %-20s %-22s %s\n", "reading", "newly excused", "...recorded NOTHING", "verdict"
    for (c = 1; c <= NRD; c++) { rr = order[c]
        printf "  %-11s %5d of %-12d %5d                  %s\n",
            rr, exc[rr] + 0, flagged + 0, excn[rr] + 0, verdict(rr) }

    printf "\n  founding cases, checked by name rather than in aggregate:\n"
    # The count is READ, not written: a literal 0 here would be a column that can never report
    # anything else, which is the defect [[T-1394]]'s replay caught in itself before adoption and
    # [[T-1343]] found in a check whose needles printed only on failure. Every reading is named, so
    # a widening that starts excusing a founding case says which one and by how much.
    for (z = 1; z <= nf; z++) {
        row = ""
        for (c = 1; c <= NRD; c++) row = row sprintf(" %s=%d", order[c], f_case[order[c] "\036" fn[z]] + 0)
        printf "    %s  recorded NOTHING, flagged at %d push(es), excused:%s\n",
            fn[z], f_flagged[fn[z]] + 0, row
    }
    row = ""
    for (c = 1; c <= NRD; c++) row = row sprintf(" %s=%d", order[c], f_reopen_exc[order[c]] + 0)
    printf "    %s  wrote its closure and had it re-opened underneath it: flagged at %d push(es), excused:%s\n",
        found_reopen, f_reopen_flagged + 0, row

    fail = ""
    if (nrev < min_revs)
        fail = fail sprintf("\n  %d pushes in range (floor %d).", nrev, min_revs)
    if (flagged + 0 < min_flagged)
        fail = fail sprintf("\n  %d flagged verdicts (floor %d) -- a shallow clone or the wrong working directory looks like a clean sweep here.", flagged + 0, min_flagged)
    if (flagged_nothing + 0 < min_nothing)
        fail = fail sprintf("\n  %d flagged verdicts whose commit recorded nothing (floor %d) -- with none the disqualifying column has no population at all and every reading reads adoptable.", flagged_nothing + 0, min_nothing)
    if (nreopen + 0 < min_reopens)
        fail = fail sprintf("\n  %d CLOSED -> OPEN transitions (floor %d) -- with none, `%s` can never differ from `today`, so its clean second column is an artefact of the population and not a fact about this repository.", nreopen + 0, min_reopens, adopted)
    if (exc[adopted] + 0 < min_newly)
        fail = fail sprintf("\n  `%s` newly excuses %d verdict(s) (floor %d) -- it was never once reached by the column that exists to disqualify it.", adopted, exc[adopted] + 0, min_newly)
    if (excn[control] + 0 == 0)
        fail = fail sprintf("\n  the control reading `%s` was NOT disqualified, so the second column no longer separates anything and a clean sweep below proves nothing.", control)
    if (fail != "") {
        printf "\nREFUSED (REPLAY-REOPEN-VACUOUS): this run cannot settle anything.%s\n", fail > "/dev/stderr"
        exit 4
    }

    for (z = 1; z <= nf; z++)
        if (f_flagged[fn[z]] + 0 == 0)
            fail = fail sprintf("\n  %s is flagged at no push in this range, so no reading above was judged against it.", fn[z])
    if (f_excused[adopted] + 0 != 0)
        fail = fail sprintf("\n  `%s` excuses a T-1298 founding case.", adopted)
    if (f_reopen_flagged + 0 == 0)
        fail = fail sprintf("\n  %s is flagged at no push, so the re-open T-1325 was filed for is not in this range.", found_reopen)
    if (f_reopen_exc[adopted] + 0 == 0)
        fail = fail sprintf("\n  `%s` does not excuse %s, so it is blind to the case that founded T-1325.", adopted, found_reopen)
    if (fail != "") {
        printf "\nREFUSED (REPLAY-REOPEN-FOUNDING-LOST): the adopted reading `%s` can no longer be checked against the cases that decide it.%s\n", adopted, fail > "/dev/stderr"
        exit 5
    }

    printf "\n  adopted: %s -- it restores each commit's verdict at its own push and changes no other.\n", adopted
    printf "  `ownhere` is indistinguishable on these numbers and is NOT adopted: it credits only the\n"
    printf "  commit that wrote the closure, so every later commit that landed code under an\n"
    printf "  already-closed id stays sticky-red after a re-open, which is the half of the punishment\n"
    printf "  T-1325 was filed about. `%s` is the control and is expected to be disqualified.\n", control
    exit 0
}
AWK
)

awk -F'\t' -v list="$LIST" -v scope="$SCOPE" -v adopted="$ADOPTED" -v control="$CONTROL" \
    -v found_nothing="$FOUND_NOTHING" -v found_reopen="$FOUND_REOPEN" \
    -v lag_min_commits="$LAG_MIN_COMMITS" -v lag_min_entries="$LAG_MIN_ENTRIES" \
    -v lag_min_examined="$LAG_MIN_EXAMINED" -v min_revs="$MIN_REVS" -v min_flagged="$MIN_FLAGGED" \
    -v min_nothing="$MIN_FLAGGED_NOTHING" -v min_reopens="$MIN_REOPENS" -v min_newly="$MIN_NEWLY" \
    "$TABLE_AWK" "$tmp/fp.txt" "$tmp/revstatus.txt" "$tmp/cands.tsv" "$tmp/wrote.tsv"
