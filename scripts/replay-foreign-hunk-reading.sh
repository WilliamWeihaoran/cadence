#!/bin/sh
# Replay reading (a) of [[T-1385]] over every hunk this repository has ever committed to a source
# file: WOULD A NOTICE HAVE NAMED THE SIBLING'S WORK RIDING IN SOMEONE ELSE'S COMMIT.
#
#   ./scripts/replay-foreign-hunk-reading.sh                # the table
#   ./scripts/replay-foreign-hunk-reading.sh --list         # ...and name every flagged hunk
#   ./scripts/replay-foreign-hunk-reading.sh --era 300      # size the second scope
#   ./scripts/replay-foreign-hunk-reading.sh --root <dir>   # read a checkout other than this one
#
# WHY IT IS A SCRIPT AND NOT A NUMBER IN A TICKET. `scripts/replay-partial-reading.sh`,
# `scripts/replay-closure-reading.sh`, `scripts/replay-message-vs-ledger.sh` and
# `scripts/replay-closure-code-lag.sh` are the other four. No guard in this family widens or
# narrows on a number quoted in prose: prose rots with the next commit and cannot be re-derived by
# whoever wants to move the rule again. [[T-1300]] answered its version 191-in-274 and took a
# warning; [[T-1304]] answered 4-in-511 and earned a refusal.
#
# THE DEFECT. `scripts/agent-commit.sh` stages WHOLE FILES. `FOREIGN-STAGED` and the declined-hunk
# ledger both watch paths you did NOT name; inside a path you DID name the unit of staging is the
# file, so a sibling's half-finished work in that file rides into your commit with no refusal, no
# declined hunk and no signal. Measured: `git show dacb9d4:CadenceTests/CadenceGuardScriptSelftestTests.swift
# | grep -c precheckShortfall` is 0 and the same read at `d65d294` is 5 -- agent `sweepcheck`'s whole
# [[T-1139]] block entered the repository inside agent `simlock`'s [[T-1381]]/[[T-1382]] commit,
# carrying a doc comment that cited a declaration still sitting in `sweepcheck`'s OTHER, uncommitted
# file. `CadenceCommentSymbolClaimTests` went red in CI on a commit that was green locally.
#
# THE SIGNAL, and it is the one this repository actually has. Every agent works a ticket, every
# commit subject names its ids, and `docs/TODO.md` says which ids are OPEN. A hunk of Swift or
# shell that cites `T-nnnn` is citing the ticket it was written for. So: a hunk this commit ADDS to
# a source file, which cites an id the commit does not own and which is still OPEN as this commit
# leaves the ledger, is a hunk written for somebody else's live ticket. At `d65d294` the swept
# block cites T-1139 -- open, `sweepcheck`'s, and nowhere in `simlock`'s subject -- while every
# hunk `simlock` actually wrote cites T-1381, T-1382, or a CLOSED id it is referring back to.
#
# THE READINGS:
#
#   subjectonly   own ids = the ids in the commit SUBJECT. Flag a hunk citing anything else.
#   msgledger     own ids = subject ids PLUS every id whose ledger first line this commit's own
#                 diff wrote as `**CLOSED` or `**PARTIAL`. A commit that closes a ticket owns it
#                 whether or not the subject had room for it.
#   open          msgledger, and the foreign id must read OPEN as this commit leaves the ledger.
#                 A CLOSED id in a comment is a back-reference -- `T-1152`, `T-749`, `T-1162` --
#                 and this repository's source is full of them. THE CANDIDATE.
#   openrecent    ...and the foreign id\047s ENTRY must have been filed within the last 50 commits,
#                 i.e. a ticket from the live batch rather than a standing backlog item.
#   opennear      ...or, the same idea read off the id NUMBER: within 64 of the highest id filed at
#                 that commit. MEASURED AND DISQUALIFIED -- it is blind to its own founding case,
#                 because T-1139 and T-1151 are 240-odd below the highest id filed at `d65d294`
#                 while being the two live tickets an agent was working in that very file. This is
#                 [[T-1356]]\047s `wholeactive` again and it is why the founding check is in here.
#
# THE DISQUALIFYING COLUMN is `...no owner ever touched that file`: of the hunks a reading flags,
# how many cite an id that NO other commit ever closed while touching the same path. Those are the
# false alarms -- a live ticket mentioned in passing by the agent that did write the hunk -- and a
# reading that is mostly those is a notice nobody will read. The founding case is the other half of
# the test and it is checked BY NAME, because this family has already measured a reading that
# looked good in aggregate and was blind to its own incident ([[T-1356]]'s `wholeactive`).
#
# WHY A NOTICE AND NOT A REFUSAL. Two agents editing one file is normal and often correct; the
# batch that produced this defect landed nine tickets in an evening. Refusing would stop the
# pattern to prevent a case a human reading one line of output can resolve.
#
# CLOSURE IS TREATED AS MONOTONE. `open at <sha>` is read as *no commit up to and including <sha>
# added a closure first line for that id*, accumulated in one pass, rather than by checking out
# 1,200 copies of a 1.4 MB ledger. `agent-commit.sh`'s `LEDGER-CLOSURE-LOST` refuses a reopening
# unless `--reopens-ids` says so, so the approximation can only be wrong where that flag was used.
#
# NON-VACUITY. A replay that reads nothing reports a clean sweep, so this refuses below floors and
# refuses outright if it cannot see its own founding case ([[T-1282]], [[T-1291]]).
set -u

LIST=0
ERA=300
ROOT_OVERRIDE=
MIN_COMMITS=${CADENCE_REPLAY_FOREIGN_MIN_COMMITS:-200}
MIN_HUNKS=${CADENCE_REPLAY_FOREIGN_MIN_HUNKS:-300}

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
if [ -n "$ROOT_OVERRIDE" ]; then
    ROOT=$(cd "$ROOT_OVERRIDE" && pwd) || exit 2
else
    ROOT=$(cd "$(dirname "$SELF_PATH")/.." && pwd) || exit 2
fi
cd "$ROOT" || exit 2

TODO=docs/TODO.md
DONE=docs/TODO_DONE.md

tmp=$(mktemp -d "${TMPDIR:-/tmp}/cadence-replay-foreign-XXXXXX") || exit 2
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
function first_line_partial(s) {
    return s ~ /^- \[T-[0-9]+\] \*\*PARTIAL([^A-Za-z]|$)/
}
function entry_id(line,   id) { id = line; sub(/^- \[/, "", id); sub(/\].*$/, "", id); return id }
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

# --- pass 0: one ordinal per commit, oldest first -----------------------------
# Every later pass keys on this. The ledger stream and the hunk stream visit DIFFERENT subsets of
# the history -- a ledger-only commit is in the first and not the second -- so "the ledger as this
# commit leaves it" can only be accumulated against a shared clock. The first draft used each
# stream's own position and silently read an empty ledger for the whole replay: `open` reported 0
# of 3874 and the founding-case check caught it, which is what that check is for.
git log --reverse --format='%H' HEAD > "$tmp/order.txt" || exit 2
awk '{ printf "%s\t%d\n", $1, NR }' "$tmp/order.txt" > "$tmp/order.tsv"
ncommits=$(grep -c '^' "$tmp/order.txt")

# --- pass 1: the ledger's history, oldest first -------------------------------
# For each commit: which ids it FILED, and which ids it recorded a closure or a PARTIAL for.
git log --reverse --format='%x01%H' -p --unified=0 -- "$TODO" "$DONE" > "$tmp/ledgerlog.txt" || exit 2

awk "$READING"'
substr($0,1,1) == "\001" { sha = substr($0, 2); next }
substr($0,1,1) != "+" { next }
{
    line = substr($0, 2)
    if (line !~ /^- \[T-[0-9]+\]/) next
    id = entry_id(line)
    printf "%s\t%s\t%s\n", sha, id, (first_line_closed(line) ? "CLOSED" : (first_line_partial(line) ? "PARTIAL" : "FILED"))
}
' "$tmp/ledgerlog.txt" > "$tmp/ledgerevents.raw"

awk -F'\t' 'NR == FNR { ord[$1] = $2; next } ($1 in ord) { printf "%s\t%s\t%s\t%s\n", ord[$1], $1, $2, $3 }' \
    "$tmp/order.tsv" "$tmp/ledgerevents.raw" | sort -n -k1,1 > "$tmp/ledgerevents.tsv"

# --- pass 2: every ADDED hunk of a source file, oldest first ------------------
# Only the shapes the reading needs survive the grep: the commit header, the file header, the hunk
# header, and an added line citing an id. `--unified=0` keeps a hunk to the lines it changed, which
# is what makes "this hunk cites T-n" narrower than "this file mentions T-n".
# FILTERED IN awk AND NOT IN grep, and this cost an hour. `grep -E '^(\001|...)'` is not portable:
# whether `\001` in an ERE means the SOH byte is undefined by POSIX, and the two greps this ran
# under disagreed -- one kept every commit header, the other dropped ALL of them. The stream then
# had no commit records at all, so `own` was empty, every hunk read as foreign under `subjectonly`
# (3874 of 3874) and `open` read 0 of 3874 while the table printed a perfectly plausible shape.
# THE FOUNDING-CASE CHECK IS WHAT CAUGHT IT. awk's "\001" in a string literal is an octal escape
# the language defines, so this comparison means one thing everywhere.
git log --reverse -p --unified=0 --format='%x01%H%x1f%s' -- \
        . ':(exclude)docs' ':(exclude)*AGENTS.md' ':(exclude)CLAUDE.md' ':(exclude)README.md' \
    | awk 'substr($0,1,1) == "\001" || substr($0,1,6) == "+++ b/" || substr($0,1,3) == "@@ " \
           || (substr($0,1,1) == "+" && $0 ~ /T-[0-9]/)' > "$tmp/hunks.txt" || exit 2

nhunkcommits=$(awk 'substr($0,1,1) == "\001" { n++ } END { print n+0 }' "$tmp/hunks.txt")

# --- the join -----------------------------------------------------------------
awk -F'\t' -v era="$ERA" -v ncommits="$ncommits" "$READING"'
FILENAME ~ /order\.tsv$/ { ordof[$1] = $2 + 0; next }
FILENAME ~ /ledgerevents\.tsv$/ {
    nev++; ev_ord[nev] = $1 + 0; ev_id[nev] = $3; ev_kind[nev] = $4; ev_sha[nev] = $2
    if ($4 != "FILED") ledgerown[$2 "\036" $3] = 1
    next
}
# --- the hunk stream ----------------------------------------------------------
substr($0,1,1) == "\001" {
    finish_hunk()
    n = split(substr($0, 2), f, "\037")
    c_sha = f[1]; c_subj = (n >= 2) ? f[2] : ""
    c_ord = ordof[c_sha]
    advance(c_ord)                       # the ledger AS THIS COMMIT LEAVES IT
    subject_ids(c_subj); delete own
    for (k in SID) own[k] = 1
    c_file = ""; inhunk = 0
    next
}
substr($0,1,4) == "+++ " { finish_hunk(); c_file = substr($0, 7); next }
substr($0,1,3) == "@@ "  { finish_hunk(); inhunk = 1; hunkno++; delete cited; next }
substr($0,1,1) == "+" {
    if (!inhunk) next
    rest = $0
    while (match(rest, /T-[0-9]+/)) { cited[substr(rest, RSTART, RLENGTH)] = 1; rest = substr(rest, RSTART + RLENGTH) }
    next
}
function advance(upto,   i) {
    while (cursor < nev && ev_ord[cursor + 1] <= upto) {
        cursor++
        id = ev_id[cursor]
        if (!(id in filedseq)) { filedseq[id] = ev_ord[cursor]; if (substr(id,3)+0 > maxid) maxid = substr(id,3)+0 }
        if (ev_kind[cursor] == "CLOSED") closed[id] = 1
    }
}
function finish_hunk(   id, any, fs, fm, fo, fr, fn) {
    if (!inhunk) { inhunk = 0; return }
    inhunk = 0
    if (c_file == "") { delete cited; return }
    any = 0; fs = ""; fm = ""; fo = ""; fr = ""; fn = ""
    for (id in cited) {
        any = 1
        if (id in own) continue
        fs = fs " " id
        if ((c_sha "\036" id) in ledgerown) continue
        fm = fm " " id
        if (id in closed) continue
        if (!(id in filedseq)) continue        # never filed: out of reach, LEDGER-ID-UNFILED\047s carve-out
        fo = fo " " id
        if (c_ord - filedseq[id] <= 50) fr = fr " " id
        if (maxid - (substr(id,3)+0) <= 64) fn = fn " " id
    }
    delete cited
    if (!any) return
    nhunks++
    inera = (ncommits - c_ord < era) ? 1 : 0
    emit("subjectonly", fs); emit("msgledger", fm); emit("open", fo)
    emit("openrecent", fr); emit("opennear", fn)
}
function emit(reading, ids) {
    if (ids == "") return
    printf "H\t%s\t%d\t%s\t%s\t%s\t%d\t%s\n", reading, hunkno, c_sha, c_file, substr(ids, 2), inera, substr(c_subj, 1, 60)
}
END {
    finish_hunk()
    printf "N\t%d\t%d\t%d\n", nhunks+0, ncommits+0, era+0
}
' "$tmp/order.tsv" "$tmp/ledgerevents.tsv" "$tmp/hunks.txt" > "$tmp/flags.tsv"

nhunks=$(awk -F'\t' '$1 == "N" { print $2 }' "$tmp/flags.tsv")
: "${nhunks:=0}"

if [ "$ncommits" -lt "$MIN_COMMITS" ] || [ "$nhunks" -lt "$MIN_HUNKS" ]; then
    printf 'REFUSED (REPLAY-FOREIGN-VACUOUS): read %d commits (floor %d) and %d id-citing hunks (floor %d).\n  A shallow checkout, the wrong --root or a rotted path exclusion all look like a clean sweep here.\n' \
        "$ncommits" "$MIN_COMMITS" "$nhunks" "$MIN_HUNKS" >&2
    exit 4
fi

# --- ground truth for the disqualifying column --------------------------------
# For each (id, path): did some OTHER commit close that id while touching that path? That is the
# id\047s owner arriving with its own commit of the same file, which is what a genuinely foreign hunk
# looks like in hindsight. A flagged hunk whose every flagged id has no such commit is the likely
# false alarm -- a live ticket mentioned in passing by the agent that did write the hunk.
git log --reverse --format='%x01%H' --name-only HEAD > "$tmp/touch.txt" || exit 2
awk 'substr($0,1,1)=="\001" { sha=substr($0,2); next } $0 != "" { print sha "\t" $0 }' "$tmp/touch.txt" > "$tmp/touched.tsv"
awk -F'\t' '$4 == "CLOSED" { print $2 "\t" $3 }' "$tmp/ledgerevents.tsv" > "$tmp/closers.tsv"
awk -F'\t' 'NR == FNR { cl[$1] = cl[$1] " " $2; next }
{ sha = $1; p = $2; if (!(sha in cl)) next
  n = split(cl[sha], a, " ")
  for (i = 1; i <= n; i++) if (a[i] != "") print a[i] "\t" p "\t" sha }' \
    "$tmp/closers.tsv" "$tmp/touched.tsv" | sort -u > "$tmp/ownerfile.tsv"

# --- the table ----------------------------------------------------------------
awk -F'\t' -v list="$LIST" '
FILENAME ~ /ownerfile\.tsv$/ { owner[$1 "\036" $2] = owner[$1 "\036" $2] " " $3; next }
$1 == "N" { nhunks = $2; ncommits = $3; era = $4; next }
$1 == "H" {
    reading = $2; hunkno = $3; sha = $4; file = $5; ids = $6; inera = $7 + 0; subj = $8
    n = split(ids, a, " ")
    isfalse = 1
    for (i = 1; i <= n; i++) {
        k = a[i] "\036" file
        if (!(k in owner)) continue
        m = split(owner[k], b, " ")
        for (j = 1; j <= m; j++) if (b[j] != "" && b[j] != sha) isfalse = 0
    }
    for (s = 0; s <= 1; s++) {
        if (s == 1 && !inera) continue
        tot[reading, s]++
        if (!((reading SUBSEP s SUBSEP sha) in cseen)) { cseen[reading SUBSEP s SUBSEP sha] = 1; ncm[reading, s]++ }
        if (isfalse) fa[reading, s]++
    }
    if (reading == "open") {
        if (list) printf "  %s  %-8s %-24s %s  %s\n", (isfalse ? "likely-false" : "FOREIGN     "), substr(sha,1,7), ids, file, subj > "/dev/stderr"
        if (substr(sha,1,7) == "d65d294" && file ~ /CadenceGuardScriptSelftestTests/) founding = founding " " ids
    }
    if (substr(sha,1,7) == "d65d294" && file ~ /CadenceGuardScriptSelftestTests/) seen[reading] = seen[reading] " " ids
    next
}
END {
    split("subjectonly msgledger open openrecent opennear", o2, " ")
    printf "replay-foreign-hunk-reading: %d id-citing hunks added to source files over %d commits.\n\n", nhunks, ncommits
    for (s = 0; s <= 1; s++) {
        printf "  scope: %s\n", (s == 0) ? "WHOLE HISTORY" : ("PARALLEL-AGENT ERA (last " era " commits)")
        printf "    %-14s %-18s %-9s %s\n", "reading", "hunks noticed", "commits", "...no owner ever touched that file"
        for (c = 1; c <= 5; c++) { r = o2[c]
            pct = (tot[r,s]+0 == 0) ? 0 : int((fa[r,s]+0) * 100 / (tot[r,s]+0))
            verdict = (r in seen) ? sprintf("%d%% likely false", pct) : "BLIND TO d65d294 -- DISQUALIFIED"
            printf "    %-14s %5d of %-6d  %4d      %5d   %s\n", r, tot[r,s]+0, nhunks+0, ncm[r,s]+0, fa[r,s]+0, verdict }
        printf "\n"
    }
    printf "  founding case (T-1385): d65d294, CadenceTests/CadenceGuardScriptSelftestTests.swift\n"
    for (c = 1; c <= 5; c++)
        printf "    %-14s %s\n", o2[c], (o2[c] in seen) ? seen[o2[c]] : "NOT NOTICED"
    if (founding !~ /T-1139/) {
        printf "REFUSED (REPLAY-FOREIGN-FOUNDING-LOST): the `open` reading does not name T-1139 at d65d294 -- it is blind to the incident it was proposed for.\n" > "/dev/stderr"
        exit 4
    }
}
' "$tmp/ownerfile.tsv" "$tmp/flags.tsv"
