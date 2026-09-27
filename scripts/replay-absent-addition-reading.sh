#!/bin/sh
# Replay the readings that could restore an ADDED file the shared checkout never received (T-1394).
#
#   ./scripts/replay-absent-addition-reading.sh              # the table
#   ./scripts/replay-absent-addition-reading.sh --list       # ...and name every moment each reading touches
#   ./scripts/replay-absent-addition-reading.sh --window 400 # ...over the last 400 commits instead of the era
#   ./scripts/replay-absent-addition-reading.sh --all        # ...over the whole history
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. The same reason as
# `scripts/replay-partial-reading.sh`, `scripts/replay-closure-reading.sh` and
# `scripts/replay-foreign-hunk-reading.sh`: every widening in this family has to answer *how many
# real cases would this newly handle* and *how many would it get WRONG* before it is allowed to
# ship. [[T-1300]] answered its version with 191 in 274 and took a warning; [[T-1304]] answered its
# with 4 in 511 and earned a refusal; [[T-1356]] and [[T-1385]] each had their ticket's own
# preferred reading DISQUALIFIED here for being blind to the case that founded them. A number
# quoted in prose rots with the next commit and cannot be re-derived by whoever wants to widen the
# rule again.
#
# THE QUESTION. `agent-commit.sh` commits through a private index via `commit-tree` so a landed
# commit cannot clobber a sibling mid-edit ([[T-975]]), which means the shared checkout drifts
# behind HEAD. A file a commit ADDS from a scratch tree therefore never reaches the checkout at
# all, and `worktree-drift.sh repair` could not restore it, because
#
#     a never-checked-out ADDITION and a deliberate in-flight DELETION are byte-identical:
#     both are "tracked in HEAD, absent from disk".
#
# That is [[T-984]]'s ambiguity in the add direction. Measured 2026-09-26: `1eddce0` created
# `docs/MODELS_AGENTS_REFERENCE.md` and rewrote `Cadence/Models/AGENTS.md` to route to it in seven
# places, and every one of those pointers was dangling in an always-read guide. At the SAME moment
# `CadenceTests/CadenceBlankingPassParityTests.swift` was also tracked-in-HEAD-and-absent-from-disk
# and was a genuine deliberate deletion by a running sibling. One had to be restored and the other
# left alone, so any reading measured here must get BOTH right -- see FOUNDING CASES below, which
# this script refuses over rather than reports.
#
# THE READINGS. All of them widen `today`, and a widening is only safe if it does not restore a
# file somebody is deliberately deleting -- so the table's SECOND column, not the first, decides.
#
#   today        what shipped before T-1394: an absent tracked path is never restored, because a
#                deletion in flight looks exactly like this. Restores nothing; the baseline.
#   add1         PROVENANCE, window 1: restore an absent path that HEAD'S OWN COMMIT added. Such a
#                path had no local content by construction, so restoring it can destroy nothing --
#                unless a sibling added and then deleted it inside one batch, which is what the
#                second column measures. This is the reading `worktree-drift.sh` adopted.
#   add3         ...added by any of the last 3 commits.
#   add10        ...added by any of the last 10 commits.
#   add40        ...added by any of the last 40, matching this script's sibling's WALK_DEPTH.
#   anyabsent    restore every absent tracked path. The naive fix, and the one the whole design
#                exists to prevent: it restores every deliberate deletion in flight.
#   guideonly    `add1` narrowed to guides and docs -- the ticket's reading (c), *"leave the tool
#                alone and let the guide pairing tests catch it"*, measured as coverage. It cannot
#                restore a deletion in flight either, but its first column is the cost of choosing it.
#
# THE TWO POPULATIONS, both replayed moment by moment over real commits.
#
#   MUST RESTORE  every (commit C, path P) where C ADDED P. At the instant C lands, P is tracked in
#                 HEAD, and if C was committed from a scratch tree P is absent from the shared
#                 checkout -- the founding shape exactly. Restoring is the right answer for all of
#                 them, so column one is coverage.
#   MUST NOT      every (commit C, path P) where P is tracked at C and the next history event for P
#                 is a DELETION landing at commit D. The interval is [add, D) and it is INCLUSIVE
#                 of the commit that added P -- which is the whole reason this column can say
#                 anything about `add1` at all. An exclusive interval would start one commit later,
#                 `add1` would score 0 BY CONSTRUCTION rather than by measurement, and the column
#                 that is supposed to disqualify it could never reach it. See VACUITY below.
#
# TWO HAZARD COLUMNS, because history records where a deletion LANDED and not when it reached the
# disk, and the difference is the whole argument:
#
#   in the interval   the upper bound. A deletion that landed at D was pending somewhere in
#                     [add, D), and nothing in the tree says which moment. Honest, and far too
#                     generous: a file removed on the 26th counts against every moment on the 25th.
#   inside one batch  the moment is on D's own calendar date AND within 4 commits of D -- the span
#                     an agent's `rm` actually sits on disk before its commit lands. This is the
#                     DISQUALIFYING column: a reading that scores anything but 0 restores a file
#                     that was, on the evidence, already deleted on purpose when it ran.
#
# What the second column says about `add1` specifically: it can only score above 0 if some commit
# both added a path and had that path's deletion already in flight -- add-and-delete inside one
# batch. Whether that has ever happened here is a fact about this repository, and it is what this
# script measures rather than assumes. MEASURED 2026-09-26, and the answer is not "never":
#
#   default scope (372 commits since agent-commit.sh)   0 -- `add1` fights nothing.
#   --all (1225 commits)                                1 -- `c562834` added
#       `Cadence/macOS/Views/ListPlanningDomain.swift` on 2026-04-28 and `1070e24` removed it the
#       same day, two commits later. One author, committing from the checkout he was editing.
#
# That one instance is why the default scope is the era and not all of history, and the reason is
# not convenience: before `agent-commit.sh` a commit and the checkout could not diverge, so the
# must-restore population there is hypothetical while the hazard is real, and mixing them measures
# a drift that could not yet happen against deletions that could. `--all` prints the instance as a
# NOTE rather than a refusal; `--all --list | grep HAZARD-BATCH` names it.
#
# WHAT THE TABLE SETTLES WITHOUT ANY THRESHOLD. Coverage SATURATES at `add1`: every wider window
# restores exactly the same 206 files, because a file is added by exactly one commit and `add1`
# already catches it there. So every widening past 1 buys nothing and pays in hazard, and no
# calibration of the window against this repository's one measured deletion is needed to choose.
#
# VACUITY, and it is the floor that matters. A replay that reads nothing reports a clean sweep, so
# this refuses below floors -- the shape `replay-partial-reading.sh` and `replay-closure-reading.sh`
# already carry ([[T-1282]]). Three of them here, and the third is the one with teeth:
#
#   commits / must-restore moments   a shallow clone or the wrong directory looks like a sweep.
#   must-not moments                 with none, the disqualifying column is vacuous and `anyabsent`
#                                    reads adoptable.
#   paths ADDED AND LATER DELETED    with none, no must-not interval contains an addition, so
#                                    `add1` -- the adopted reading -- is never once evaluated by the
#                                    column that exists to disqualify it, and its 0 is an artefact
#                                    of the population rather than a fact about the repository.
set -u

WINDOW=0
ALL=0
LIST=0
MIN_COMMITS=${CADENCE_REPLAY_ADD_MIN_COMMITS:-200}
MIN_ADDS=${CADENCE_REPLAY_ADD_MIN_ADDS:-100}
MIN_DELETE_MOMENTS=${CADENCE_REPLAY_ADD_MIN_DELETE_MOMENTS:-1}
MIN_ADD_THEN_DELETE=${CADENCE_REPLAY_ADD_MIN_ADD_THEN_DELETE:-1}
# How close a moment must be to the deletion that landed for the `rm` to have plausibly been on
# disk already: same calendar date, and within this many commits. Four is this repository's batch.
BATCH_COMMITS=${CADENCE_REPLAY_ADD_BATCH_COMMITS:-4}

# FOUNDING CASES. Not illustrations: the script exits non-zero if it cannot read either one, or if
# the adopted reading gets either one wrong. T-1356 and T-1385 were both caught by exactly this.
FOUND_ADD_SHA=1eddce0
FOUND_ADD_PATH=docs/MODELS_AGENTS_REFERENCE.md
FOUND_DEL_PATH=CadenceTests/CadenceBlankingPassParityTests.swift
FOUND_DEL_SHA=52d727f
ADOPTED=add1

while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=1 ;;
        --all) ALL=1 ;;
        --window) shift; WINDOW=${1:-0} ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-add-XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

# --- the range -----------------------------------------------------------------
#
# The default is THE MULTI-AGENT ERA and not all of history, because the drift this measures is
# created by `agent-commit.sh`'s private index: before that script landed there was one author
# committing from the checkout he was editing, so a commit and the checkout never diverged. Mixing
# the two eras would put a 2026-03 template file's removal in the same denominator as a sibling's
# in-flight `rm`, which are not the same event. `--all` is there so the claim can be checked.
ERA=$(git log --diff-filter=A --format='%H' -- scripts/agent-commit.sh | tail -1)
STRICT=1
if [ "$ALL" -eq 1 ]; then
    RANGE=HEAD; SCOPE="all history"; STRICT=0
elif [ "$WINDOW" -gt 0 ]; then
    RANGE=HEAD; SCOPE="last $WINDOW commits"; STRICT=0
elif [ -n "$ERA" ]; then
    RANGE="$ERA..HEAD"; SCOPE="the multi-agent era (since agent-commit.sh landed at $(echo "$ERA" | cut -c1-7))"
else
    RANGE=HEAD; SCOPE="all history (agent-commit.sh not found in this history)"; STRICT=0
fi
if [ "$WINDOW" -gt 0 ]; then rangeargs="-n $WINDOW"; else rangeargs=""; fi

# Oldest-first, so a commit's index is its position in the range and "N commits ago" is subtraction.
# NO `--diff-filter` on the log itself, deliberately: it drops the commits that added or deleted
# nothing, and then an index counts *file-touching* commits rather than commits. `add3` would mean
# "three commits that moved a file ago", which is not a window any caller can hold. The A/D lines
# are selected in awk instead, so every commit in the range takes a number.
# shellcheck disable=SC2086
git log --reverse --format='%x01%H%x1f%ad' --date=short --name-status $rangeargs $RANGE \
    > "$tmp/events.txt" 2>/dev/null || exit 2
# The commit count is the whole range, not just the commits that added or deleted something: it is
# the floor's denominator and a shallow clone has to be visible in it.
# shellcheck disable=SC2086
ncommits=$(git rev-list --count $rangeargs $RANGE 2>/dev/null || echo 0)

# --- the moments ---------------------------------------------------------------
#
# One pass, oldest-first. `add[p]` is the index of the most recent addition of p seen so far, or
# absent if p entered the range already tracked. A deletion at index d closes the interval and
# emits one MUSTNOT moment per commit in [add, d) -- inclusive of the addition, see TWO HAZARD
# COLUMNS above; that boundary moment is the only one at which `add1` is ever judged.
#
# The founding cases are tagged here rather than re-derived later, so the table and the refusal
# below read the same two moments out of the same pass.
awk -F'\037' -v fa_sha="$FOUND_ADD_SHA" -v fa_path="$FOUND_ADD_PATH" -v fd_path="$FOUND_DEL_PATH" '
substr($0,1,1) == "\001" { n = split(substr($0,2), f, "\037"); sha = f[1]; date = f[2]; idx++
                           shaof[idx] = substr(sha,1,7); dateof[idx] = date; next }
/^[AD]\t/ {
    st = substr($0,1,1); p = substr($0,3)
    if (st == "A") {
        add[p] = idx
        tag = (shaof[idx] == fa_sha && p == fa_path) ? "FOUND-RESTORE" : "-"
        printf "MUSTRESTORE\t%d\t%d\t%s\t%s\t%s\t%d\t%s\t%s\n", idx, idx, p, shaof[idx], dateof[idx], 0, "-", tag
    } else {
        # A path added before the range has no add index here, so every `addN` reading is silent
        # about it by construction -- it is a MUSTNOT moment for `anyabsent` and for nothing else.
        a = (p in add) ? add[p] : -1
        if (a >= 0) addthendelete++
        for (i = (a >= 0 ? a : 1); i < idx; i++) {
            tag = (shaof[i] == fa_sha && p == fd_path) ? "FOUND-LEAVE" : "-"
            printf "MUSTNOT\t%d\t%d\t%s\t%s\t%s\t%d\t%s\t%s\n", i, a, p, shaof[i], dateof[i], idx, dateof[idx], tag
        }
        delete add[p]
    }
}
END { printf "%d\n", addthendelete + 0 > "/dev/stderr" }
' "$tmp/events.txt" > "$tmp/moments.tsv" 2>"$tmp/addthendelete.txt"

nadds=$(grep -c '^MUSTRESTORE' "$tmp/moments.tsv" || true)
ndels=$(grep -c '^MUSTNOT' "$tmp/moments.tsv" || true)
nadd_then_delete=$(cat "$tmp/addthendelete.txt" 2>/dev/null || echo 0)

if [ "$ncommits" -lt "$MIN_COMMITS" ] || [ "$nadds" -lt "$MIN_ADDS" ] \
   || [ "$ndels" -lt "$MIN_DELETE_MOMENTS" ] || [ "$nadd_then_delete" -lt "$MIN_ADD_THEN_DELETE" ]; then
    printf 'REFUSED (REPLAY-ADD-VACUOUS): %d commits in range (floor %d), %d must-restore moments (floor %d), %d must-not moments (floor %d), %d path(s) added and later deleted (floor %d).\n' \
        "$ncommits" "$MIN_COMMITS" "$nadds" "$MIN_ADDS" "$ndels" "$MIN_DELETE_MOMENTS" \
        "$nadd_then_delete" "$MIN_ADD_THEN_DELETE" >&2
    printf '  A shallow checkout, a rewritten history or the wrong working directory all look like a clean sweep here.\n' >&2
    printf '  With no must-not moments the disqualifying column is vacuous and `anyabsent` reads adoptable; with no\n' >&2
    printf '  path added AND later deleted, `add1` is never judged by that column at all and its 0 means nothing.\n' >&2
    exit 4
fi

# --- the table -----------------------------------------------------------------
#
# Every reading is scored on the same three questions and on T-1394's own two cases, in one pass,
# so a reading cannot be adoptable in the table and blind in the founding check. T-1356's
# `wholeactive` and T-1385's `openrecent` were each their ticket's preferred reading and each was
# blind to the case that founded the ticket; naming both cases here is what stops that recurring.
awk -F'\t' -v list="$LIST" -v nadds="$nadds" -v ndels="$ndels" -v scope="$SCOPE" \
    -v ncommits="$ncommits" -v natd="$nadd_then_delete" -v batch="$BATCH_COMMITS" -v adopted="$ADOPTED" \
    -v strict="$STRICT" '
function is_guide(p) {
    if (p ~ /^docs\/.*\.md$/) return 1
    if (p ~ /(^|\/)AGENTS\.md$/) return 1
    if (p == "CLAUDE.md" || p == "README.md") return 1
    return 0
}
# Does reading r restore path p at moment i, given the path was added at index a (-1 = before the
# range)? One function, used for both populations and for the founding cases, so the columns and
# the pins cannot drift apart.
function restores(r, i, a, p) {
    if (r == "today") return 0
    if (r == "anyabsent") return 1
    if (a < 0) return 0
    if (r == "guideonly") return (i == a) && is_guide(p)
    if (r == "add1")  return (i - a <  1)
    if (r == "add3")  return (i - a <  3)
    if (r == "add10") return (i - a < 10)
    if (r == "add40") return (i - a < 40)
    return 0
}
# Spelled once, and every disqualification names WHICH of the four ways it failed.
function verdict(r) {
    if (cov[r] + 0 == 0)      return "restores nothing"
    if (hazb[r] + 0 != 0)     return "DISQUALIFIED (fights a deletion inside one batch)"
    if (!foundR[r])           return "DISQUALIFIED (blind to the founding case)"
    if (foundL[r])            return "DISQUALIFIED (restores the founding deletion)"
    if (cov[r] + 0 < nadds)   return "sound, but covers a fraction"
    return "keeps the guard"
}
BEGIN { split("today add1 add3 add10 add40 anyabsent guideonly", order, " "); nr = 7 }
{
    kind = $1; i = $2 + 0; a = $3 + 0; p = $4; sha = $5; date = $6; d = $7 + 0; ddate = $8; tag = $9
    for (c = 1; c <= nr; c++) {
        r = order[c]
        got = restores(r, i, a, p) ? 1 : 0
        if (tag == "FOUND-RESTORE") { seenR = 1; foundR[r] = got }
        if (tag == "FOUND-LEAVE")   { seenL = 1; foundL[r] = got }
        if (!got) continue
        if (kind == "MUSTRESTORE") {
            cov[r]++
            if (list) printf "  restore   %-10s %s %s  %s\n", r, sha, date, p > "/dev/stderr"
        } else {
            haz[r]++
            # Inside one batch of the deletion that landed: same calendar date, and within `batch`
            # commits of it. That is the span an agent`s `rm` is really sitting on disk.
            if (date == ddate && d - i <= batch) {
                hazb[r]++
                if (list) printf "  HAZARD-BATCH %-8s %s %s  %s\n", r, sha, date, p > "/dev/stderr"
            } else if (list) printf "  hazard    %-10s %s %s  %s\n", r, sha, date, p > "/dev/stderr"
        }
    }
}
END {
    printf "replay-absent-addition-reading: %s\n", scope
    printf "  %d commits, %d must-restore moments, %d must-not moments, %d path(s) added and later deleted.\n\n",
        ncommits, nadds, ndels, natd
    if (!seenR || !seenL) {
        printf "REFUSED (REPLAY-ADD-FOUNDING-LOST): the founding %s moment is not in this range,\n",
            (!seenR ? "must-restore" : "must-not-restore")
        printf "  so no reading below was judged against the case that founded T-1394.\n"
        exit 5
    }
    printf "  %-11s %-18s %-16s %-16s %s\n", "reading", "newly restored", "hazard: in the", "...inside one", "founding cases"
    printf "  %-11s %-18s %-16s %-16s %s\n", "",        "",               "interval",       "batch (decides)", "restore / leave"
    for (c = 1; c <= nr; c++) { r = order[c]
        printf "  %-11s %4d of %-9d %4d of %-9d %4d             %s / %s   %s\n",
            r, cov[r]+0, nadds, haz[r]+0, ndels, hazb[r]+0,
            (foundR[r] ? "YES" : "no "), (foundL[r] ? "RESTORES" : "leaves  "), verdict(r)
    }
    printf "\n  adopted: %s -- coverage saturates there, so every wider window is pure hazard for no gain.\n", adopted
    sound = (hazb[adopted]+0 == 0) && foundR[adopted] && !foundL[adopted] && (cov[adopted]+0 == nadds)
    if (sound) exit 0
    # Outside the default scope this is a NOTE and not a refusal, and the distinction is the
    # argument rather than a convenience: `--all` reaches back before `agent-commit.sh` existed,
    # where one author committed from the checkout he was editing, so an addition could not fail to
    # reach the tree and the must-restore population there is hypothetical. The hazards it finds are
    # real history and worth naming -- `--all --list | grep HAZARD-BATCH` names them -- but they are
    # not evidence about a drift that could not happen yet.
    if (!strict) {
        printf "  NOTE: over this scope %s fights %d deletion(s) inside one batch and %s the founding deletion.\n",
            adopted, hazb[adopted]+0, (foundL[adopted] ? "RESTORES" : "leaves")
        printf "        Adoption rests on the default scope; run with no arguments for the reading that decides.\n"
        exit 0
    }
    printf "REFUSED (REPLAY-ADD-ADOPTED-UNSOUND): %s no longer scores clean on the scope it was adopted over.\n", adopted
    exit 6
}
' "$tmp/moments.tsv"
table_status=$?
[ "$table_status" -eq 0 ] || exit "$table_status"

# --- the founding cases, which this script refuses over rather than reports -----
#
# T-1356's `wholeactive` and T-1385's `openrecent` were each their ticket's preferred reading and
# each was blind to the case that founded the ticket, so a table alone is not enough: the two paths
# below are checked by name, against the commits they really happened at, and a reading that cannot
# see them is refused rather than scored.
founding_fail=""

add_parent=$(git rev-parse --verify "${FOUND_ADD_SHA}^" 2>/dev/null || true)
if [ -z "$add_parent" ]; then
    founding_fail="$founding_fail
  $FOUND_ADD_SHA is not in this history, so the must-restore founding case cannot be read at all."
else
    if git diff --diff-filter=A --name-only "$add_parent" "$FOUND_ADD_SHA" 2>/dev/null \
        | grep -qxF "$FOUND_ADD_PATH"; then
        printf '\n  founding (restore): %s ADDED %s -- `%s` restores it.  OK\n' \
            "$FOUND_ADD_SHA" "$FOUND_ADD_PATH" "$ADOPTED"
    else
        founding_fail="$founding_fail
  $FOUND_ADD_SHA no longer reads as having ADDED $FOUND_ADD_PATH, so \`$ADOPTED\` is blind to the case that founded T-1394."
    fi
fi

# The negative half, and it is the one that makes the fix non-trivial: at the very moment the file
# above was found dangling, this path was ALSO tracked-in-HEAD-and-absent-from-disk, and was a real
# deletion by a running sibling. It must be tracked at that commit and NOT added by it.
if [ -n "$add_parent" ]; then
    if ! git cat-file -e "$FOUND_ADD_SHA:$FOUND_DEL_PATH" 2>/dev/null; then
        founding_fail="$founding_fail
  $FOUND_DEL_PATH is not tracked at $FOUND_ADD_SHA, so the must-NOT-restore founding case cannot be posed."
    elif git diff --diff-filter=A --name-only "$add_parent" "$FOUND_ADD_SHA" 2>/dev/null \
        | grep -qxF "$FOUND_DEL_PATH"; then
        founding_fail="$founding_fail
  $FOUND_DEL_PATH reads as ADDED by $FOUND_ADD_SHA, which would make \`$ADOPTED\` restore a deliberate deletion."
    elif ! git diff --diff-filter=D --name-only "${FOUND_DEL_SHA}^" "$FOUND_DEL_SHA" 2>/dev/null \
        | grep -qxF "$FOUND_DEL_PATH"; then
        founding_fail="$founding_fail
  $FOUND_DEL_SHA no longer reads as having DELETED $FOUND_DEL_PATH, so the deletion half is unpinned."
    else
        printf '  founding (leave):   %s holds %s, and did NOT add it -- `%s` leaves it alone.  OK\n' \
            "$FOUND_ADD_SHA" "$FOUND_DEL_PATH" "$ADOPTED"
        printf '                      %s is the commit that landed that deletion, %s commits later.\n' \
            "$FOUND_DEL_SHA" "$(git rev-list --count "${FOUND_ADD_SHA}..${FOUND_DEL_SHA}" 2>/dev/null || echo '?')"
    fi
fi

if [ -n "$founding_fail" ]; then
    printf 'REFUSED (REPLAY-ADD-FOUNDING-LOST): the adopted reading `%s` can no longer be checked against T-1394'"'"'s own cases.%s\n' \
        "$ADOPTED" "$founding_fail" >&2
    exit 5
fi
exit 0
