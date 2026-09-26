#!/bin/sh
# Ask the ledger the question `agent-commit.sh` never asks (T-1298).
#
#   ./scripts/ledger-lag-check.sh [<rev>]     # default HEAD; exit 3 on a finding
#   ./scripts/ledger-lag-check.sh selftest    # prove both refusals and the notice still fire
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
# second opinion: a BOLD RUN INTRODUCING the token on the entry's OWN first line -- `**CLOSED`,
# `**FULLY CLOSED`, `**PARTIALLY CLOSED` -- outside inline code. Eighty lines of that script defend
# the narrowness (a body-wide reading marks sixteen open tickets closed; widening to
# RESOLVED/VERIFIED marks two open ones closed, because this ledger uses VERIFIED to mean "confirmed
# real"), and the `closure_visible` / `first_line_closed` pair below is that script's text, copied
# character for character so the two cannot drift; `CadenceGuardScriptSelftestTests` pins the copies
# against each other.
#
# IT USED TO BE THE BARE WORD ANYWHERE ON THAT LINE, and that was a hole in THIS guard (T-1335). An
# entry that merely QUOTES the marker -- and this repository's tickets quote their own ledger
# machinery constantly -- read as closed, so a commit could name that id, land code, close nothing,
# and pass. The live victim was [[T-1136]], an open, decided, not-started ticket whose first line
# quotes the marker inside backticks: `scripts/ledger-view.sh` reported it OPEN while this script
# and `agent-commit.sh` read it closed. `scripts/replay-closure-reading.sh` measured the four
# candidate repairs over every entry first line that has ever existed; the one adopted is the only
# one that has never, in the whole history of this ledger, failed to recognise an honest closure in
# the population this check reads. Its number is 0 of 263.
#
# Three things are added on top of it, all of which mean "not open" here:
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
# THE MIRROR DIRECTION, AND IT IS A NOTICE (T-1342)
#
# Everything above asks whether a commit that LANDS CODE closed anything. The other direction is an
# id that reads CLOSED with nothing landed, and it is invisible in precisely the way that matters,
# because the ledger is what the next agent reads to decide what is already done. It happens
# because `agent-commit.sh` stages WHOLE FILES and `docs/TODO.md` is the one file every agent
# edits: any agent naming the ledger carries whatever else is sitting in it, including a sibling's
# closure lines for work that sibling has not committed yet. The spill is CORRECT behaviour and
# must not be repaired by reverting.
#
# THE READING: an id whose entry <rev>'s OWN ledger diff closed -- a first line added to
# `$TODO_PATH` carrying the T-1335 run, or an entry arriving in `$DONE_PATH` -- which <rev>'s
# subject does not name, and which no commit reachable from <rev> lands code under. It is
# evaluated at the TIP and does not stick: once the sibling's commit lands, the next push is
# silent, which is the whole difference between this and LEDGER-CLOSURE-LAGGED above.
#
# MEASURED FIRST, by `scripts/replay-closure-code-lag.sh`, over all 734 closure events this
# repository has written, in two scopes, with the disqualifying column *how many flagged closures
# never needed code at all*:
#
#   reading         newly refuses (all / last 300)   ...that never needed code
#   here                 558 of 734 / 179 of 347            250 / 38
#   hereorbefore         316 of 734 /  55 of 347            250 / 38
#   unnamed  <-- this    285 of 734 /  43 of 347            219 / 26
#   anywhere             250 of 734 /  38 of 347            250 / 38
#
# The second column is why this is a NOTICE and not a refusal: 250 of the 734 closures this ledger
# has written are for decision, park, duplicate and documentation tickets that never had code to
# land, and nothing visible at commit time tells one from the other. A refusal over that population
# blocks correct commits to prevent a window nobody read. `anywhere` is that column made into a
# reading, and the replay shows it is blind to all four founding cases, because each of them
# self-resolved: the code landed in a LATER commit, which is exactly what hindsight can see and a
# guard standing at the tip cannot.
#
# AND THE DURATION, which is the quantity the harm actually depends on: of the closures flagged
# with their code in another commit, 16 had the code land AFTER, median 20 minutes, p90 350, max
# 553, eight over half an hour and none over a day; 292 had it land BEFORE, which is the direction
# this check already refuses. The four founding cases -- `b358aa3`/T-1334, `b358aa3`/T-1339,
# `e28bc87`/T-1348, `e28bc87`/T-1349 -- resolved in 11, 11, 12 and 12 minutes. [[T-1342]]'s own
# prose put two of those on `cd81288` and read `e28bc87` as carrying T-1351; the replay reads the
# diffs and says otherwise, which is the argument for the script over the number.
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

# The `+` lines one commit's own diff added to one ledger. An empty file is the ordinary answer --
# most commits touch no ledger at all -- and an empty file is also what a MISSING path yields, which
# is why the reading below never concludes anything from emptiness alone: the count is printed on
# every run, green or not (T-1343).
tip_added() {  # $1 = rev, $2 = ledger path
    git show --format= --unified=0 "$1" -- "$2" 2>/dev/null | sed -n 's/^+//p'
    return 0
}

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

    # T-1342: the lines <rev>'s OWN diff added to each ledger, split by which ledger they landed in
    # -- in `$TODO_PATH` a closure has to carry the T-1335 run, while ARRIVING in `$DONE_PATH` is
    # itself the closure. Two files rather than one tagged stream, because the awk below is keyed on
    # FILENAME and reads raw ledger lines (T-1317); a tag column would need a second reading of the
    # line shape in the one pass that must not have one.
    tip_added "$rev" "$TODO_PATH" > "$tmp/tip_todo.txt"
    tip_added "$rev" "$DONE_PATH" > "$tmp/tip_done.txt"

    awk -v min_commits="$SELF_MIN_COMMITS" \
        -v min_entries="$SELF_MIN_ENTRIES" \
        -v min_examined="$SELF_MIN_EXAMINED" \
        -v todo="$TODO_PATH" \
        -v f_todo="$tmp/todo.md" -v f_done="$tmp/done.md" -v f_log="$tmp/log.txt" \
        -v f_tipt="$tmp/tip_todo.txt" -v f_tipd="$tmp/tip_done.txt" \
        "$AWK_PROG" "$tmp/todo.md" "$tmp/done.md" "$tmp/log.txt" "$tmp/tip_todo.txt" "$tmp/tip_done.txt" > "$tmp/pass1.txt"
    rc=$?
    [ "$rc" = 0 ] || return "$rc"          # LEDGER-LAG-VACUOUS already printed its own refusal

    second_pass "$tmp/pass1.txt"
}

# THE SECOND PASS (T-1359, and it is [[T-1325]]'s shape taken one step).
#
# The first pass has two states for an entry -- closed, or open -- and `**PARTIAL` falls on the open
# side. `scripts/ledger-view.sh` has modelled PARTIAL as its own status since it shipped, so the
# three scripts agreed on the closure TOKEN (T-1335) and disagreed on the STATUS MODEL, and
# [[T-1359]] is that gap arriving live: `7b5897d` landed two MCP constructors under [[T-1122]],
# whose entry opens `**PARTIAL 2026-09-25 (agent `mcpcreate`) -- three of the six are built ...`,
# and the run went red and STAYED red, because a finding never expires.
#
# THE READING ADOPTED, and it is narrow on purpose: an id whose entry reads `**PARTIAL` at <rev>
# excuses the commit ONLY WHEN THAT COMMIT'S OWN DIFF WROTE OR REWROTE THAT FIRST LINE. Not
# "PARTIAL is not open" -- that one is rideable: write `**PARTIAL` on an entry once and every later
# commit naming that id passes for free, forever, which is precisely the hole T-1298 built this to
# close. Here the PARTIAL line is evidence only for the commit that produced it, exactly as a
# `**CLOSED` line is evidence for the commit whose sha it carries.
#
# MEASURED, because every widening in this family is (`scripts/replay-partial-reading.sh`,
# committed alongside this and re-runnable in ~19 s). Over all 309 commits this check examines, in
# both scopes -- judged against the ledger at HEAD, which is what CI does, and judged against the
# ledger as each commit itself left it, which is the rule the script PRINTS:
#
#   reading           newly excused (HEAD / as landed)   ...that recorded NOTHING
#   partial                 1 of 1    /   1 of 200              0  /  0
#   partialdated            1 of 1    /   1 of 200              0  /  0
#   partialauthored         1 of 1    /   1 of 200              0  /  0
#   partialhere   <-- this  1 of 1    /   1 of 200              0  /  0
#   ownledger               0 of 1    / 199 of 200              0  /  199
#
# The one commit every partial reading newly excuses is `7b5897d` itself, and it recorded its work.
# The four partial readings are indistinguishable on the numbers, so the choice is made on what
# each one costs when it is WRONG, and `partialhere` is the only one that cannot be ridden by a
# commit that did not write the line. `ownledger` -- [[T-1325]]'s "closed at HEAD OR closed in the
# commit's own ledger" -- is a different question with a different answer and does not touch this
# one: it excuses 0 of the 1 flagged at HEAD, and in the as-landed scope it excuses 199 commits
# that recorded nothing at the time. That is not an argument against it (its whole point is that a
# later commit may repair the ledger, which is what the HEAD leg already does), but it is why it is
# not adopted HERE, by an agent, as a side effect of a red run: see [[T-1325]].
#
# COST. The probe runs only for a CANDIDATE finding that names a PARTIAL id, which is zero commits
# on a green run and one today -- `git show` of one commit's ledger diff, ~30 ms. Nothing is added
# to the 0.3 s green path.
partial_written_here() {  # $1 = sha, $2 = space-separated PARTIAL ids; 0 if this commit wrote one
    _sha=$1; _ids=$2
    [ -n "$_ids" ] || return 1
    git show --format= --unified=0 "$_sha" -- "$TODO_PATH" "$DONE_PATH" 2>/dev/null \
        | sed -n 's/^+//p' > "$tmp/added.txt" || return 1
    for _pid in $_ids; do
        grep -qE "^- \\[$_pid\\] \\*\\*PARTIAL([^A-Za-z]|\$)" "$tmp/added.txt" && return 0
    done
    return 1
}

second_pass() {  # $1 = the first pass's records
    _rev_short=$(git rev-parse --short "${rev:-HEAD}" 2>/dev/null || printf '%s' "${rev:-HEAD}")
    _findings=0
    _excused=0
    _body=""
    _commits=0; _entries=0; _examined=0
    _us=$(printf '\037')
    _ntip=0; _nunlanded=0; _ulist=""
    while IFS="$_us" read -r _kind _a _b _c _d _e; do
        case "$_kind" in
            N) _commits=$_a; _entries=$_b; _examined=$_c ;;
            U) _ntip=$_a; _nunlanded=$_b; _ulist=$_c ;;
            F)
                if partial_written_here "$_a" "$_e"; then
                    _excused=$((_excused + 1))
                    continue
                fi
                _findings=$((_findings + 1))
                _body="$_body$(printf '  %s  %s %-24s %s' "$(echo "$_a" | cut -c1-7)" "$_b" "$_c" "$_d")
"
                ;;
        esac
    done < "$1"

    [ -n "$_body" ] && printf '%s' "$_body"
    printf 'ledger-lag: %d commits, %d ledger entries, %d examined, %d findings' \
        "$_commits" "$_entries" "$_examined" "$_findings"
    if [ "$_excused" -gt 0 ]; then
        printf ', %d excused by a **PARTIAL line the commit wrote itself' "$_excused"
    fi
    printf '\n'

    # T-1342, AND IT PRINTS ITS DENOMINATOR EVERY RUN. A check whose evidence only FAILURE produces
    # proves nothing when it is green -- T-1343's `complaints(requiring:)` read one of four
    # refusals and looked clean, and T-1350's toleration went 13 days unread because nothing
    # reported `passed n tolerating`. So the closure count is stated whether or not any of them is
    # unlanded; a run that read no ledger diff at all is then visibly different from a clean one.
    printf 'closure-lag: %s wrote %d closure(s); %d name no code in this history\n' \
        "$_rev_short" "$_ntip" "$_nunlanded"
    if [ "$_nunlanded" -gt 0 ]; then
        printf 'NOTICE (LEDGER-CLOSURE-UNLANDED): %s closed %s in the ledger, names none of them in its\n' "$_rev_short" "$_ulist" >&2
        printf '  subject, and no commit reachable from here lands code under any of them. That is what a\n' >&2
        printf '  sibling'"'"'s closure lines riding in your ledger commit look like: `agent-commit.sh` stages WHOLE\n' >&2
        printf '  FILES and %s is the one file every agent edits, so the spill is expected and must NOT be\n' "$TODO_PATH" >&2
        printf '  repaired by reverting (T-1342). This is a NOTICE: nothing is failing and the run still passes.\n' >&2
        printf '  Measured with scripts/replay-closure-code-lag.sh: the four founding cases resolved in 11, 11,\n' >&2
        printf '  12 and 12 minutes and the median gap over this history is 20m, so the one thing worth checking\n' >&2
        printf '  is that whoever owns the ticket is still alive to land it.\n' >&2
    fi

    if [ "$_findings" -gt 0 ]; then
        printf 'REFUSED (LEDGER-CLOSURE-LAGGED): %d commit(s) landed code under ticket ids and closed none of them in the ledger.\n  Every id each commit names is still open in %s. Either write the closure on the entry'"'"'s own\n  first line (`- [T-n] **CLOSED <date> (`<sha>`) -- ...`), or -- if the work is genuinely part-done --\n  a `- [T-n] **PARTIAL <date> (...) -- ...` first line IN THIS COMMIT, or, if the ticket is\n  legitimately still open, make the commit name an id it did close.\n' \
            "$_findings" "$TODO_PATH" >&2
        return 3
    fi
    return 0
}

# ---------------------------------------------------------------------------
# The reading itself, as one awk pass over: TODO.md, TODO_DONE.md, the log.
# Held in a variable rather than written to a temp file: the first draft wrote one and removed it
# only on the success path, so every exit 3 and every exit 4 leaked one -- and a guard whose
# refusal path is the one that litters is a guard that gets noticed for the wrong reason.
# ---------------------------------------------------------------------------
AWK_PROG=$(cat <<'AWK'
# The record separator between this pass and the shell that filters its candidates. A unit
# separator, because a commit subject can hold anything a human can type but not a control
# character, and the alternative -- re-parsing the formatted human line -- is a second reading.
BEGIN { US = sprintf("%c", 31) }
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
# The closure reading, character for character `agent-commit.sh`'s `$LEDGER_CLOSURE_READING` and
# `scripts/ledger-view.sh`'s copy of it (T-1335). One rule, three files, pinned against each other.
function closure_visible(s,   bq) {
    # A marker inside inline code is a QUOTATION, not a closure. The fence character is built with
    # sprintf rather than written, because two of the three copies of this reading are carried
    # inside a command substitution where an odd number of literal fences ends it early.
    bq = sprintf("%c", 96)
    while (match(s, bq "[^" bq "]*" bq)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
    return s
}
function first_line_closed(s) {
    return closure_visible(s) ~ /\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/
}
# The PARTIAL status, character for character `scripts/ledger-view.sh`'s `status_of` (T-1359). That
# script has modelled `**PARTIAL` as its own status since it shipped; this one had two states, and
# the gap between the two models is the whole of T-1359. Anchored right after the id, so a first
# line that merely QUOTES the token cannot match and no `closure_visible` pass is needed here.
function first_line_partial(s) {
    return s ~ /^- \[T-[0-9]+\] \*\*PARTIAL([^A-Za-z]|$)/
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
function verdict(   id, known, openn, list, plist) {
    if (c_sha == "") return
    commits++
    if (c_code == 0) return
    # T-1342, and it is this check\047s mirror image. `hascode` is *some commit reachable from <rev>
    # lands code and names this id in its subject* -- the same two readings this function already
    # uses, asked of the whole history rather than of one commit. It is collected here rather than
    # in a second pass because the log is read once and this is the pass that reads it.
    for (id in c_ids) hascode[id] = 1
    known = 0; openn = 0; list = ""; plist = ""
    for (id in c_ids) {
        if (!(id in filed)) continue
        known++
        if (id in openi) {
            openn++; list = list " " id
            if (id in partiali) plist = plist " " id
        }
    }
    if (known == 0) return
    examined++
    if (known == openn) {
        # A CANDIDATE finding, not yet a finding. The second pass in the shell asks, for the ids in
        # `plist`, whether THIS commit is the one that wrote that `**PARTIAL` line; see
        # partial_written_here() and T-1359. `plist` is empty for every commit that names no
        # PARTIAL id, which is 308 of the 309 this repository examines, and an empty `plist` skips
        # the probe entirely -- so a green run costs nothing extra.
        printf "F%c%s%c%s%c%s%c%s%c%s\n", US, c_sha, US, c_date, US, substr(list, 2), US, c_subj, US, substr(plist, 2)
    }
}

# Which of the three inputs this line came from, read from the FILENAME rather than counted (T-1317).
#
# It used to be `FNR == 1 { part++ }`, and **an empty file never yields FNR == 1**, so it never
# counted. The archive is optional -- `git show "$rev:$DONE_PATH" ... || : > "$tmp/done.md"` writes
# an empty file when the path is not there -- and with it empty the commit log arrived as part 2 and
# was parsed as the archive: every `- [T-n]` in it read as an archived (closed) entry, and no line
# was ever read as a commit at all. MEASURED at HEAD:
# `CADENCE_LEDGER_LAG_DONE=docs/NO_SUCH_ARCHIVE.md ./scripts/ledger-lag-check.sh` reported
# "0 commits (floor 200), 557 entries, 0 examined" and refused LEDGER-LAG-VACUOUS. The floors caught
# it -- that is the design working -- but the parse was wrong, and a MISSING archive is only one way
# to arrive here: a zero-byte `docs/TODO.md`, or a `<rev>` whose log is empty, shift the parse in
# exactly the same way while the floors report a different symptom each time.
#
# Keyed on FILENAME, no input can move another one's reading, empty or not. `part` is never
# incremented, so nothing depends on how many lines any input happens to hold.
FILENAME == f_todo { part = 1 }
FILENAME == f_done { part = 2 }
FILENAME == f_log  { part = 3 }
FILENAME == f_tipt { part = 4 }
FILENAME == f_tipd { part = 5 }

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
        if (sec ~ /^## (Done|Cancelled)/ || first_line_closed($0)) {   # the entry's OWN first line
            closedi[id] = 1; delete openi[id]; delete partiali[id]; next
        }
        if (!(id in closedi)) {
            openi[id] = 1
            # PARTIAL is still OPEN here -- it does not excuse anything on its own. It only marks
            # the id as worth the second pass, which is what actually decides (T-1359).
            if (first_line_partial($0)) partiali[id] = 1
        }
    }
    next
}

part == 2 {
    if ($0 ~ /^- \[T-[0-9]+\]/) { id = entry_id($0); filed[id] = 1; entries++; closedi[id] = 1; delete openi[id] }
    next
}

# T-1342. The closures <rev> WROTE, read off its own diff. In `$TODO_PATH` the added first line has
# to carry the T-1335 closure run; an entry ARRIVING in `$DONE_PATH` is a closure by the same rule
# part 2 already uses. An entry merely MOVED under `## Done` without gaining a marker is invisible
# in an added line and is not counted -- that undercounts and never invents.
part == 4 {
    if ($0 ~ /^- \[T-[0-9]+\]/ && first_line_closed($0)) { tipclosed[entry_id($0)] = 1 }
    next
}
part == 5 {
    if ($0 ~ /^- \[T-[0-9]+\]/) { tipclosed[entry_id($0)] = 1 }
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
        # `git log <rev>` is newest first, so the FIRST record is <rev> itself. Its subject ids are
        # the ids it OWNS; a closure it wrote for anything else is a closure it carried (T-1342).
        if (!tipseen) { tipseen = 1; for (k in SID) tipown[k] = 1 }
        next
    }
    if ($0 != "" && is_code($0)) c_code++
    next
}

END {
    verdict()
    if (commits < min_commits || entries < min_entries || examined < min_examined) {
        printf "ledger-lag: %d commits, %d ledger entries, %d examined, 0 findings\n",
            commits, entries, examined
        printf "REFUSED (LEDGER-LAG-VACUOUS): this run read too little to mean anything -- %d commits (floor %d), %d entries (floor %d), %d examined (floor %d).\n  A shallow checkout, a renamed ledger or a rotted path predicate all look like a pass here.\n",
            commits, min_commits, entries, min_entries, examined, min_examined > "/dev/stderr"
        exit 4
    }
    ntip = 0; nunlanded = 0; ulist = ""
    for (id in tipclosed) {
        ntip++
        if (id in tipown)  continue      # <rev> names it: its own closure, whatever else is true
        if (id in hascode) continue      # code for it is in <rev> or in an ancestor
        nunlanded++; ulist = ulist " " id
    }
    printf "U%c%d%c%d%c%s\n", US, ntip, US, nunlanded, US, substr(ulist, 2)
    printf "N%c%d%c%d%c%d\n", US, commits, US, entries, US, examined
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

    # --- mode 2c: a QUOTED marker is not a closure (T-1335) -----------------
    # The hole this check carried until T-1335. "Closed" was the bare token ANYWHERE on the entry's
    # own first line, so an entry that merely QUOTES the marker -- which is what writing about the
    # ledger format looks like, and is exactly [[T-1136]]'s first line -- read as closed, and a
    # commit could name that id, land code and pass having closed nothing. Both directions are
    # checked, because the stricter reading is only worth having if it still recognises the honest
    # closures: `scripts/replay-closure-reading.sh` measured the candidates over every entry first
    # line that has ever existed, and the one adopted here loses none of them in this check's scope.
    echo; echo " mode 2c (T-1335) -- a QUOTED marker is not a closure, and a mid-line one still is"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-30] **An open finding whose first line quotes `**CLOSED 2026-09-04**` while writing about the ledger format.**' \
        '- [T-31] **A finding that was closed after the fact.** **CLOSED 2026-09-21 (`2222222`) — the closure written mid-line, after the original finding.**' \
        '- [T-32] **An open finding whose own first line says the word CLOSED loose in its prose.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "T-31: the fix, whose closure is written mid-line after the original finding" \
        Cadence/Q1.swift "let q1 = 1"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a closure written mid-line after the finding IS still a closure" 0 findings

    land "T-30: code lands under an id whose entry only QUOTES the marker" Cadence/Q2.swift "let q2 = 2"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "an entry that QUOTES the marker in backticks is NOT closed ([[T-1335]])" \
        LEDGER-CLOSURE-LAGGED T-30

    land "T-32: code lands under an id whose entry has the word loose in prose" Cadence/Q3.swift "let q3 = 3"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "nor is the bare word loose in an entry's own first-line prose" \
        LEDGER-CLOSURE-LAGGED T-32

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-30] **CLOSED 2026-09-21 (`3333333`) — the closure, written rather than quoted.**' \
        '- [T-31] **A finding that was closed after the fact.** **CLOSED 2026-09-21 (`2222222`) — the closure written mid-line, after the original finding.**' \
        '- [T-32] **CLOSED 2026-09-21 (`4444444`) — and this one too.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "docs: write both closures so the modes below start from a clean history" docs/DUP.md dup4
    out=$(run); rc=$?
    check "$rc" 0 "$out" "and the history goes quiet once both carry a written closure" 0 findings

    # --- mode 2d: `**PARTIAL` is a closure only for the commit that WROTE it (T-1359) -------
    # `scripts/ledger-view.sh` has always had a PARTIAL status and this check had two states, so a
    # deliberately part-done entry read as plain open and its own commit went red and STAYED red.
    # The repair is not "PARTIAL is not open" -- that one is rideable, and the first two checks
    # below are the pair that tells the two readings apart. `scripts/replay-partial-reading.sh`
    # measured every candidate over all 309 examined commits before this was written.
    echo; echo " mode 2d (T-1359) -- a **PARTIAL line excuses only the commit that wrote it"
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-30] **CLOSED 2026-09-21 (`3333333`) — the closure, written rather than quoted.**' \
        '- [T-31] **A finding that was closed after the fact.** **CLOSED 2026-09-21 (`2222222`) — the closure written mid-line, after the original finding.**' \
        '- [T-32] **CLOSED 2026-09-21 (`4444444`) — and this one too.**' \
        '- [T-40] **PARTIAL 2026-09-25 (agent `fixture`) — three of the six are built; the other three are refused with a measurement each.**' \
        '- [T-41] **An open finding whose first line quotes `**PARTIAL 2026-09-25`** while writing about the ledger format.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "T-40: three of the six constructors, and the other three refused with a measurement each" \
        Cadence/P1.swift "let p1 = 1"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a **PARTIAL first line THIS commit wrote is a recorded closure" \
        0 findings excused

    land "T-40: a later commit lands more code and writes nothing in the ledger" Cadence/P2.swift "let p2 = 2"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "a **PARTIAL somebody ELSE wrote does not excuse a later commit" \
        LEDGER-CLOSURE-LAGGED T-40

    land "T-41: code lands under an id whose entry only QUOTES the PARTIAL marker" Cadence/P3.swift "let p3 = 3"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "an entry that QUOTES **PARTIAL in backticks is not a PARTIAL status" \
        LEDGER-CLOSURE-LAGGED T-41

    # The scoping half: writing a PARTIAL line for an id the commit does NOT name buys nothing.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-30] **CLOSED 2026-09-21 (`3333333`) — the closure, written rather than quoted.**' \
        '- [T-31] **A finding that was closed after the fact.** **CLOSED 2026-09-21 (`2222222`) — the closure written mid-line, after the original finding.**' \
        '- [T-32] **CLOSED 2026-09-21 (`4444444`) — and this one too.**' \
        '- [T-40] **CLOSED 2026-09-25 (`5555555`) — the remaining three landed.**' \
        '- [T-41] **CLOSED 2026-09-25 (`6666666`) — and this one too.**' \
        '- [T-42] **PARTIAL 2026-09-25 (agent `fixture`) — an unrelated part-done ticket.**' \
        '- [T-43] **An open finding, named by the commit below and untouched by it.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "T-43: code lands under an open id while the same commit writes an UNRELATED **PARTIAL" \
        Cadence/P4.swift "let p4 = 4"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "a **PARTIAL written for an id the commit does not name excuses nothing" \
        LEDGER-CLOSURE-LAGGED T-43

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-20] **CLOSED 2026-09-20 (`1111111`) — the fix landed with the closure.**' \
        '- [T-30] **CLOSED 2026-09-21 (`3333333`) — the closure, written rather than quoted.**' \
        '- [T-31] **A finding that was closed after the fact.** **CLOSED 2026-09-21 (`2222222`) — the closure written mid-line, after the original finding.**' \
        '- [T-32] **CLOSED 2026-09-21 (`4444444`) — and this one too.**' \
        '- [T-40] **CLOSED 2026-09-25 (`5555555`) — the remaining three landed.**' \
        '- [T-41] **CLOSED 2026-09-25 (`6666666`) — and this one too.**' \
        '- [T-42] **PARTIAL 2026-09-25 (agent `fixture`) — an unrelated part-done ticket.**' \
        '- [T-43] **CLOSED 2026-09-25 (`7777777`) — closed so the modes below start clean.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "docs: write the closures so the modes below start from a clean history" docs/DUP.md dup5
    out=$(run); rc=$?
    check "$rc" 0 "$out" "and the history goes quiet again once every entry carries its closure" 0 findings

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

    # --- mode 6: an EMPTY input must not shift the parse (T-1317) ------------
    echo; echo " mode 6 (empty inputs) -- an optional archive that is empty must not become the log"
    # `FNR == 1 { part++ }` never fires for a zero-byte file, so the file AFTER an empty one was read
    # as the empty one's part: with no archive, the commit log was parsed as the archive and no line
    # was ever read as a commit. The floors turned that into LEDGER-LAG-VACUOUS rather than a green
    # run -- which is the floors working -- but the reading was wrong, and both halves are checked
    # here: the finding must still arrive with the archive missing, and the silence must too.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-11] **Another open finding.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '- [T-15] **Open.**' '- [T-16] **Open.**' '- [T-17] **Open.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    land "T-11: code lands while its entry is still open" Cadence/I.swift "let i = 9"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "the control: with the archive present this is a finding" LEDGER-CLOSURE-LAGGED T-11

    out=$( cd "$repo" && CADENCE_LEDGER_LAG_DONE=docs/NO_SUCH_ARCHIVE.md sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 3 "$out" "and with the archive MISSING the log is still read as the log" \
        LEDGER-CLOSURE-LAGGED T-11

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-10] **CLOSED 2026-09-19 (`0000000`) — fixed.**' \
        '- [T-11] **CLOSED 2026-09-20 (`2222222`) — the closure the commit above owed.**' \
        '- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done.**' \
        '- [T-15] **Open.**' '- [T-16] **Open.**' '- [T-17] **Open.**' \
        '' '## Done' '' '- [T-13] **A done entry with no marker at all.**'
    ( cd "$repo" && git add -A . && git commit -q -m "T-11: write the closure that commit owed" )
    out=$( cd "$repo" && CADENCE_LEDGER_LAG_DONE=docs/NO_SUCH_ARCHIVE.md sh "$SELF_PATH" 2>&1 ); rc=$?
    check "$rc" 0 "$out" "a missing archive goes silent when the ledger carries the closure" 0 findings

    # The same defect written the other way round, which is why the repair is FILENAME and not a
    # sentinel line in the archive alone: a zero-byte ledger shifts the parse identically. Exit 0
    # here is the proof the log was read as the log -- the examined floor cannot be met otherwise.
    : > "$repo/docs/TODO.md"
    ( cd "$repo" && git add -A . && git commit -q -m "docs: empty the ledger file itself" )
    out=$(run); rc=$?
    check "$rc" 0 "$out" "an EMPTY docs/TODO.md shifts nothing either" ledger-lag:

    # --- mode 7: the MIRROR direction (T-1342) -------------------------------
    echo; echo " mode 7 (LEDGER-CLOSURE-UNLANDED) -- a closure this commit did not name and no code anywhere"
    # Modes 1-6 all ask whether a commit that LANDS CODE closed anything. This is the other
    # direction: an id that reads CLOSED with nothing landed, which happens because
    # `agent-commit.sh` stages WHOLE FILES and docs/TODO.md is the one file every agent edits.
    # A NOTICE, not a refusal -- `scripts/replay-closure-code-lag.sh` measured 558 of 734 closure
    # events over this history with no code in their own commit, 250 of which never needed any.
    # Mode 6 left the ledger EMPTY, so it is rebuilt here -- with ids of its own. Refiling an id an
    # earlier mode already closed would resurrect that mode's finding, because a finding here is
    # sticky and the ledger at <rev> is the only thing that clears one.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **Open, and its code is about to land with its closure.**' \
        '- [T-51] **Open, and a sibling will carry its closure before its code exists.**' \
        '- [T-52] **Open, and it will be archived by a commit that does not name it.**'
    land "docs: a fresh ledger for the closure-lag modes" docs/SEED2.md seed2
    out=$(run); rc=$?
    check "$rc" 0 "$out" "the count is printed on a run with nothing to report (T-1343)" \
        "wrote 0 closure(s); 0 name no code"

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **Open, and a sibling will carry its closure before its code exists.**' \
        '- [T-52] **Open, and it will be archived by a commit that does not name it.**'
    land "T-50: the code and the closure in one commit" Cadence/J.swift "let j = 10"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a closure the commit names, over code it lands, is not noticed" \
        "wrote 1 closure(s); 0 name no code"

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **CLOSED 2026-09-26 (`bbbbbbb`) — a sibling closure, carried by someone else.**' \
        '- [T-52] **Open, and it will be archived by a commit that does not name it.**'
    land "T-50: a ledger tidy that swept up a sibling's closure lines" docs/NOTE2.md note2
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a closure this commit does not name, with no code anywhere, is noticed" \
        LEDGER-CLOSURE-UNLANDED T-51
    check "$rc" 0 "$out" "and it is a NOTICE -- the run still passes" 0 findings

    land "T-51: the sibling's code, arriving after its closure" Cadence/K.swift "let k = 11"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "once the code lands the tip has no unlanded closure of its own" \
        "wrote 0 closure(s)"
    out=$(run "HEAD~1"); rc=$?
    check "$rc" 0 "$out" "and the spilling commit is still judged against ITS OWN history" \
        LEDGER-CLOSURE-UNLANDED T-51

    # Archival is a closure: an entry ARRIVING in the archive needs no marker, which is the same
    # reading part 2 already uses for the open/closed question.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **CLOSED 2026-09-26 (`bbbbbbb`) — a sibling closure, carried by someone else.**'
    archive '# archive' '' '- [T-14] **CLOSED 2026-09-01 (`def5678`).**' \
        '- [T-52] **CLOSED 2026-09-26 (`ccccccc`) — moved to the archive.**'
    land "T-50: an archive move carried in somebody else's ledger commit" docs/NOTE3.md note3
    out=$(run); rc=$?
    check "$rc" 0 "$out" "an entry arriving in the archive is a closure too" \
        LEDGER-CLOSURE-UNLANDED T-52

    # The direction this check ALREADY guards, and it must not be noticed twice: code first,
    # closure later. `hascode` is asked of every commit reachable from <rev>, so an ancestor
    # answers it.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **CLOSED 2026-09-26 (`bbbbbbb`) — a sibling closure, carried by someone else.**' \
        '- [T-53] **Open, and its code is landing before its closure is written.**'
    land "T-53: the code lands first and the closure is deferred" Cadence/L.swift "let l = 12"
    out=$(run); rc=$?
    check "$rc" 3 "$out" "the control: the OTHER direction is still a refusal" LEDGER-CLOSURE-LAGGED T-53

    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **CLOSED 2026-09-26 (`bbbbbbb`) — a sibling closure, carried by someone else.**' \
        '- [T-53] **CLOSED 2026-09-26 (`ddddddd`) — the closure the commit before owed.**'
    # The subject must name NOTHING here, or `tipown` excuses the closure and this says nothing
    # about `hascode` at all. Measured: with the id left in the subject, deleting the `hascode`
    # clause outright kept this mode green.
    land "docs: write the closure the commit before it owed" docs/NOTE4.md note4
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a closure whose code is already an ancestor is not noticed" \
        "wrote 1 closure(s); 0 name no code"

    # And the other half of the same isolation: a ticket that never had code to land -- a decision,
    # a park, a duplicate -- closed by a commit that NAMES it. 250 of this repository's 734
    # closures are this shape, which is the whole reason the reading is a notice and not a refusal.
    # Nothing but `tipown` excuses it, so deleting that clause turns this red.
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **CLOSED 2026-09-26 (`bbbbbbb`) — a sibling closure, carried by someone else.**' \
        '- [T-53] **CLOSED 2026-09-26 (`ddddddd`) — the closure the commit before owed.**' \
        '- [T-54] **A decision to record, with nothing to build for it.**'
    land "docs: file the decision ticket" docs/NOTE5.md note5
    ledger '# ledger' '' '## Open — decided, not started' '' \
        '- [T-50] **CLOSED 2026-09-26 (`aaaaaaa`) — landed with its own code.**' \
        '- [T-51] **CLOSED 2026-09-26 (`bbbbbbb`) — a sibling closure, carried by someone else.**' \
        '- [T-53] **CLOSED 2026-09-26 (`ddddddd`) — the closure the commit before owed.**' \
        '- [T-54] **CLOSED 2026-09-26 (`eeeeeee`) — decided, and there was never any code to land.**'
    land "T-54: the decision is recorded and the ticket is closed" docs/NOTE6.md note6
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a closure the commit NAMES, for a ticket with no code anywhere, is not noticed" \
        "wrote 1 closure(s); 0 name no code"

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
