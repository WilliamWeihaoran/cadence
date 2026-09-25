#!/bin/sh
# A generated compact view of the ledger, so nobody reads 1.4 MB to find the open work (T-1331).
#
#   ./scripts/ledger-view.sh                # active entries, with next action and park reason
#   ./scripts/ledger-view.sh brief          # active entries, one line each
#   ./scripts/ledger-view.sh all            # every entry in both ledgers, one line each
#   ./scripts/ledger-view.sh counts         # the census, beside the naive lexical count it corrects
#   ./scripts/ledger-view.sh show T-1325    # the exact entry block(s) for one id, from both ledgers
#   ./scripts/ledger-view.sh selftest       # prove every refusal and every hard reading still fires
#
# WHY THIS EXISTS
#
# `docs/TODO.md` is the authoritative ledger and it is ~11,800 lines / ~1.4 MB. Every agent and
# every coordinator pass pays for it: `rg -n 'T-13'` prints entire multi-kilobyte ticket lines, and
# the workaround everyone independently reinvents -- `rg -n -o '^- \[T-[0-9]+\].{0,180}'` -- truncates
# mid-sentence and cannot tell an open entry from a closed one.
#
# THIS IS DERIVED, NOT MAINTAINED. Nothing here is written down twice: every line of output is read
# out of `docs/TODO.md` and `docs/TODO_DONE.md` at the moment it is asked for. A second
# hand-maintained index would be a third place for the truth to diverge, which is the defect
# [[T-1136]] and [[T-1303]] each cost this repository once already.
#
# WHAT "CLOSED" MEANS HERE, and why it is NOT the naive first-line reading.
#
# The lexical reading everybody reaches for is "the entry's first line contains the closure token".
# `counts` prints it beside this one on every run rather than quoting a figure here that rots
# (T-1146), and it is wrong in both directions:
#
#   * TOO CLOSED. An entry whose prose merely QUOTES the token reads as closed -- [[T-1335]], which
#     was live in the two GUARDS until they adopted the reading below. T-1136 is the witness: an
#     open, decided, not-started ticket whose first line quotes the marker inside backticks while
#     describing the duplicate-entry defect, which this view reported OPEN while `agent-commit.sh`
#     and `scripts/ledger-lag-check.sh` read it closed.
#   * TOO OPEN. A `## Done` or `## Cancelled` entry carries no marker at all, and an entry archived
#     into `docs/TODO_DONE.md` carries its closure there.
#
# So closure is a BOLD RUN INTRODUCING the token on the first line -- `**CLOSED`, `**FULLY CLOSED`,
# `**PARTIALLY CLOSED` -- outside inline code, and never the word loose in prose. That is
# deliberately the same narrowness `agent-commit.sh`'s `ledger_buried_closure_ids` already measured
# over 471 entries (T-1106): it names the real closures and nothing else, and in particular it does
# not name an entry that quotes the convention. `**PARTIAL` is its own status, not a closure:
# [[T-1122]] has one of six MCP create kinds built and five deliberately unbuilt, and calling that
# closed would lose the five.
#
# THE TWO GUARDS NOW READ IT THE SAME WAY (T-1335), which is why this comment says "introducing"
# where it used to say "opening". This view shipped the strict form -- the marker had to open the
# line, right after the id -- and `scripts/replay-closure-reading.sh` measured what that costs over
# every entry first line that has ever existed: it fails to recognise T-777's honest closure,
# written mid-line after the original finding, and three archived ones of the same shape. Widening
# by one clause -- the bold run may be anywhere on the line, as long as it is outside inline code --
# costs nothing anywhere and lets `ledger_closed_ids`, `ledger-lag-check.sh` and this file spell one
# rule one way. Over `docs/TODO.md` at HEAD the two forms are identical entry for entry, so nothing
# this tool prints about the live ledger changed.
#
# WHAT IT CANNOT TELL APART, AND SAYS SO. A closure run that opens a LATER line of the block is two
# different things wearing the same text: a buried closure (the T-1106 defect, which
# `agent-commit.sh` refuses as `LEDGER-CLOSURE-BURIED`) and a legitimately RE-OPENED entry, whose
# old closure sentence stays in place as history while the first line goes back to open. Both read
# ACTIVE here -- the safe direction, since re-opened work is work -- and both carry a `BODY-CLOSURE`
# flag. Guessing between them from the text is what [[T-1325]] is a whole ticket about; this view
# declines to guess and points at the entry instead.
#
# IDS vs ENTRIES. An id can have more than one formal entry ([[T-1303]]: T-1043 had a closed twin
# and an open one). Entries are listed individually and flagged `DUP`; the id census follows
# `ledger_closed_ids`' set reading -- an id is active only while NO entry of it is closed -- so the
# two numbers in `counts` are allowed to differ, and the tool prints both rather than picking one.
#
# NON-VACUITY. A view that reads nothing prints nothing and looks like a tidy backlog. A renamed
# ledger, an empty file and a `cd` into the wrong tree all produce that. So the run counts the
# entries it read and refuses below a floor -- the shape `ledger-lag-check.sh` already carries, and
# the defect [[T-1282]] found in a gate that compiled nothing and [[T-1291]] in a canary that had
# stopped guarding. The overrides exist for the selftest's fixtures; nothing else sets them.
set -u

MIN_ENTRIES=${CADENCE_LEDGER_VIEW_MIN_ENTRIES:-300}

# T-1343. This is a `#!/bin/sh` script and its selftest lays its fixtures down with here-documents,
# which sh writes under $TMPDIR. A caller that hands the file to `zsh` instead -- which is what the
# first registration of this selftest did -- gets a different temp file: zsh writes here-documents
# to $TMPPREFIX, which zsh SETS ITSELF at startup to `/tmp/zsh`, never to $TMPDIR and never empty,
# so no `[ -z ... ]` guard would fire. Where /tmp is unwritable (the App-Sandboxed macOS test host,
# T-719) each document then becomes an EMPTY file and the run reports `LEDGER-VIEW-VACUOUS` against
# a fixture that exists and is blank. Measured 2026-09-23 under `zsh -f`: 8 passed, 33 failed, and
# the refusal quotes the fixture's real path, which is what made it read as a sandbox write failure
# rather than as a here-document one. Harmless under sh; the shell that needs it is the wrong one.
_tmp_base="${TMPDIR:-/tmp/}"; case "$_tmp_base" in */) ;; *) _tmp_base="$_tmp_base/" ;; esac
export TMPPREFIX="${CADENCE_TMPPREFIX:-${_tmp_base}zsh}"

case "$0" in
    /*) SELF_PATH=$0 ;;
    *)  SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
esac
ROOT=$(cd "$(dirname "$SELF_PATH")/.." && pwd)

TODO_PATH=${CADENCE_LEDGER_VIEW_TODO:-$ROOT/docs/TODO.md}
DONE_PATH=${CADENCE_LEDGER_VIEW_DONE:-$ROOT/docs/TODO_DONE.md}

refuse() { printf 'REFUSED (%s): %s\n' "$1" "$2" >&2; exit "$3"; }

# ---------------------------------------------------------------------------
# The reading itself, as one awk pass over the two ledgers. Held in a variable rather than a temp
# file so no exit path has to remember to clean one up.
# ---------------------------------------------------------------------------
AWK_PROG=$(cat <<'AWK'
BEGIN { BQ = sprintf("%c", 96) }
# The closure reading, character for character `agent-commit.sh`'s `$LEDGER_CLOSURE_READING` and
# `scripts/ledger-lag-check.sh`'s copy of it (T-1335). One rule, three files, pinned against each
# other by `CadenceGuardScriptSelftestTests`. This file shipped the first half of it -- a bold run
# OPENING the line -- and the convergence widened it by one clause, so a closure written mid-line
# after the original finding (T-777's shape, the one honest closure the strictly-anchored form ever
# failed to recognise) now reads closed here as well as in the two guards.
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
function trim(s) { sub(/^[ \t\n]+/, "", s); sub(/[ \t\n]+$/, "", s); return s }
function plain(s) { gsub(/\*\*/, "", s); gsub(/\[\[/, "", s); gsub(/\]\]/, "", s); return trim(s) }
function trunc(s, n) { return (length(s) <= n) ? s : (substr(s, 1, n - 1) "\342\200\246") }

# One clause starting at `start` in `text`: up to the first sentence end, else cut on a word
# boundary. Deliberately dumb -- this is a signpost to the entry, not a summary of it.
function clause(text, start, maxlen,   s) {
    s = substr(text, start, maxlen * 2)
    # Sentence end: a period, a space, then a capital, a bold run or an inline-code fence. The
    # fence character is built with sprintf rather than written, because this program is carried in
    # a `$( ... )` command substitution and an odd number of them in there ends it early.
    if (match(s, "\\. +([A-Z*" BQ "]|$)") && RSTART <= maxlen) return plain(substr(s, 1, RSTART))
    if (length(s) <= maxlen) return plain(s)
    s = substr(s, 1, maxlen)
    if (match(s, / [^ ]*$/)) s = substr(s, 1, RSTART - 1)
    return plain(s) "\342\200\246"
}

function entry_id(line,   id) { id = line; sub(/^- \[/, "", id); sub(/\].*$/, "", id); return id }

function finish() {
    if (cur == 0) return
    n++
    e_id[n] = cur_id; e_file[n] = cur_file; e_line[n] = cur_line
    e_sec[n] = cur_sec; e_first[n] = cur_first; e_body[n] = cur_body; e_buried[n] = cur_buried
    seen[cur_id] = seen[cur_id] + 1
    cur = 0
}

# Which ledger a line came from, keyed on FILENAME rather than counted. `ledger-lag-check.sh` told
# its inputs apart positionally with `FNR == 1 { part++ }` and an EMPTY file never yields FNR == 1,
# so a missing optional archive shifted every later input by one ([[T-1317]]). Same trap here, same
# repair: an empty or absent archive cannot make the open ledger read as the archive.
FILENAME != prevfile { finish(); sec = ""; prevfile = FILENAME }

# A block ends at the next entry, at a section header, or at any other line in column 1. Blank
# lines never end it: entries here have several indented paragraphs separated by blanks, so a
# blank-line rule would cut a multiline entry in half and lose everything after the first one.
/^- \[T-[0-9]+\]/ {
    finish()
    cur = 1; cur_id = entry_id($0); cur_file = (FILENAME == f_todo) ? todo_label : done_label
    cur_line = FNR; cur_sec = sec; cur_first = $0; cur_body = ""; cur_buried = 0
    # `inopen` in `agent-commit.sh`'s reading: a closure run deeper in the block only MEANS anything
    # while the first line is still open. Without this every closed entry that also records a
    # sub-closure -- 33 of them at HEAD -- would carry the flag, and a flag 33 entries wear is not
    # a flag.
    cur_open_first = first_line_closed($0) ? 0 : 1
    next
}
/^## / { finish(); sec = trim(substr($0, 4)); next }
/^[^ \t]/ { finish(); next }
cur == 1 {
    cur_body = cur_body "\n" $0
    # The same narrow marker as the first-line reading, one indent in. `agent-commit.sh` measured
    # this exact shape over 471 entries (T-1106): it names the fourteen genuinely buried closures
    # and nothing else -- not the entry whose body says "deleted the CLOSED copy".
    if (cur_open_first && closure_visible($0) ~ /^[ \t]+\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/) cur_buried = 1
    next
}

function text_of(i,   t) { t = e_first[i] " " e_body[i]; gsub(/[\n\t ]+/, " ", t); return t }

function status_of(i,   first, sect) {
    first = e_first[i]; sect = e_sec[i]
    if (e_file[i] == done_label) return "ARCHIVED"
    if (sect ~ /^Done/) return "DONE"
    if (sect ~ /^Cancelled/) return "CANCELLED"
    if (first_line_closed(first)) return "CLOSED"
    if (first ~ /^- \[T-[0-9]+\] \*\*PARTIAL([^A-Za-z]|$)/) return "PARTIAL"
    if (park_of(i) != "") return "PARKED"
    return "OPEN"
}
function active(s) { return (s == "OPEN" || s == "PARTIAL" || s == "PARKED") }

# Read from the WHOLE block, not from the first line: this ledger wraps at ~100 columns and a
# finding's bold run routinely runs onto the second and third line, so a first-line-only reading
# ends the headline mid-clause on exactly the entries whose first line is shortest.
function headline_of(i,   t, h) {
    t = text_of(i); sub(/^- \[T-[0-9]+\] /, "", t)
    if (substr(t, 1, 2) == "**") {
        h = substr(t, 3)
        if (match(h, /\*\*/)) h = substr(h, 1, RSTART - 1)
        return plain(h)
    }
    return plain(t)
}
# An explicit ask, in the shapes this ledger writes one. These are distinctive enough to be read
# anywhere in the block; the park vocabulary below is not, so that one must open a bold run.
function next_of(i,   t) {
    t = text_of(i)
    if (match(t, /(Wanted|WANTED|The ask|Next action|What is wanted):/)) return clause(t, RSTART, 150)
    if (match(t, /The repair is /)) return clause(t, RSTART, 150)
    if (match(t, /\*\*(DECIDE|For the user)[:,]? /)) return clause(t, RSTART + 2, 150)
    return ""
}
function park_of(i,   t) {
    t = text_of(i)
    if (match(t, /\*\*(BLOCKED|Blocked|PARKED|Parked|DEFERRED|Deferred|BACKLOGGED|Backlogged|NOT URGENT|Not urgent|AWAITING|Awaiting|ON HOLD|On hold)/))
        return clause(t, RSTART + 2, 140)
    return ""
}
function flags_of(i,   f) {
    f = ""
    if (seen[e_id[i]] > 1) f = f " DUP"
    if (e_buried[i]) f = f " BODY-CLOSURE"
    return f
}
function archived_count(   i, c) { for (i = 1; i <= n; i++) if (e_file[i] == done_label) c++; return c + 0 }

END {
    finish()
    if (n < min_entries) {
        printf "REFUSED (LEDGER-VIEW-VACUOUS): read only %d ledger entries (floor %d) from %s and %s.\n  An empty file, a renamed ledger or the wrong working directory all look like a tidy backlog here.\n",
            n, min_entries, todo_label, done_label > "/dev/stderr"
        exit 4
    }

    # An id is closed once ANY entry of it is closed -- `ledger_closed_ids`' set reading (T-1303).
    for (i = 1; i <= n; i++) {
        st[i] = status_of(i)
        if (active(st[i])) id_open[e_id[i]] = 1; else id_closed[e_id[i]] = 1
    }

    if (mode == "show") {
        hits = 0
        for (i = 1; i <= n; i++) {
            if (e_id[i] != want) continue
            hits++
            printf "%s:%d  %s  [%s]%s\n", e_file[i], e_line[i], st[i], e_sec[i], flags_of(i)
            print e_first[i]
            m = split(e_body[i], lines, "\n")
            for (j = 2; j <= m; j++) print lines[j]
            print ""
        }
        if (hits == 0) {
            printf "REFUSED (LEDGER-VIEW-NO-SUCH-ID): no formal `- [%s]` entry in %s or %s.\n  The ledger is the id allocator; an id that exists only in a commit message or in another\n  entry's prose is not filed (LEDGER-ID-UNFILED, scripts/agent-commit.sh).\n",
                want, todo_label, done_label > "/dev/stderr"
            exit 5
        }
        exit 0
    }

    if (mode == "counts") {
        # The naive reading this tool exists to correct, computed here so the delta is shown rather
        # than claimed: the closure token anywhere on the first line, entries before `## Done`.
        for (i = 1; i <= n; i++) {
            if (e_file[i] != todo_label) continue
            if (e_sec[i] ~ /^(Done|Cancelled)/) continue
            naive_total++
            if (e_first[i] ~ /CLOSED/) naive_closed++
        }
        for (i = 1; i <= n; i++) { bucket[st[i]]++; if (active(st[i])) act_entries++ }
        for (id in id_open) if (!(id in id_closed)) act_ids++
        for (id in seen) { ids++; if (seen[id] > 1) dup_ids++ }
        printf "ledger-view: %d entries (%s %d, %s %d), %d distinct ids, %d with more than one entry\n",
            n, todo_label, n - archived_count(), done_label, archived_count(), ids, dup_ids
        printf "  by status:"
        for (k in bucket) printf " %s=%d", k, bucket[k]
        printf "\n"
        printf "  ACTIVE: %d entries, %d ids\n", act_entries, act_ids
        printf "  naive lexical reading (token anywhere on the first line, before ## Done): %d entries, %d closed, %d open\n",
            naive_total, naive_closed, naive_total - naive_closed
        exit 0
    }

    shown = 0
    for (i = 1; i <= n; i++) {
        if (mode != "all") {
            if (!active(st[i])) continue
            if (e_id[i] in id_closed) continue   # a closed twin closes the id
        }
        shown++
        if (mode == "brief" || mode == "all") {
            printf "%-8s %-9s %-20s %s%s\n", e_id[i], st[i], e_file[i] ":" e_line[i],
                trunc(headline_of(i), 96), flags_of(i)
            continue
        }
        printf "%-8s %-9s %s%s\n", e_id[i], st[i], e_file[i] ":" e_line[i], flags_of(i)
        printf "         %s\n", trunc(headline_of(i), 130)
        nx = next_of(i); if (nx != "") printf "         next: %s\n", nx
        pk = park_of(i); if (pk != "") printf "         parked: %s\n", pk
    }
    printf "\nledger-view: %d %s entr%s of %d read from %s and %s.\n",
        shown, (mode == "all" ? "listed" : "active"), (shown == 1 ? "y" : "ies"), n, todo_label, done_label
    exit 0
}
AWK
)

run_view() {  # $1 = mode, $2 = wanted id (show only)
    [ -r "$TODO_PATH" ] || refuse LEDGER-VIEW-VACUOUS "$TODO_PATH is not readable; there is no ledger to read." 4
    [ -r "$DONE_PATH" ] || DONE_PATH=/dev/null
    awk -v mode="$1" -v want="${2:-}" -v min_entries="$MIN_ENTRIES" \
        -v f_todo="$TODO_PATH" -v f_done="$DONE_PATH" \
        -v todo_label="$(printf '%s' "$TODO_PATH" | sed "s|^${ROOT}/||")" \
        -v done_label="$(printf '%s' "$DONE_PATH" | sed "s|^${ROOT}/||")" \
        "$AWK_PROG" "$TODO_PATH" "$DONE_PATH"
}

# ---------------------------------------------------------------------------
# The dispatch, and it is a FUNCTION called from the last line of the file rather than a bare `case`
# after the selftest, which is what it was until T-1343. Two refusals are made here and nowhere
# else, and `CadenceGuardScriptSelftestTests.everyRefusalTheScriptsMakeIsStillInducedByTheirOwnSelftest`
# splits a script at `# --- selftest` and requires every refusal to be named ABOVE the split -- that
# is how it tells a refusal the script MAKES from one its selftest merely mentions. A bare dispatch
# has to sit below the selftest, because sh cannot call `cmd_selftest` before it has read it, so the
# two refusals read as selftest-only and the pin silently proved nothing about them. Wrapping the
# dispatch is the repair that does not weaken the question: `main` is defined before the split, its
# body is resolved when it is CALLED, and the only thing left below is the call itself.
#
# `${1:-open}` defaults the PATTERN only, never the parameter, so every arm below has to read the
# defaulted copy. Reading `$1` there is unbound under `set -u` on a no-argument run -- which is the
# invocation the usage line puts first.
main() {
    mode=${1:-open}
    case "$mode" in
        selftest) cmd_selftest; exit $? ;;
        -h|--help) sed -n '2,9p' "$SELF_PATH"; exit 0 ;;
        show)
            case "${2:-}" in
                T-[0-9]*) run_view show "$2" ;;
                *) refuse LEDGER-VIEW-BAD-ID "show takes one exact ticket id, spelled T-<number>; got '${2:-}'." 2 ;;
            esac
            ;;
        open|brief|all|counts) run_view "$mode" ;;
        *) refuse LEDGER-VIEW-UNKNOWN-MODE "'$mode' is not a mode; use open, brief, all, counts, show <id> or selftest." 2 ;;
    esac
}

# --- selftest ----------------------------------------------------------------
# Two markdown fixtures under $TMPDIR and nothing else: no git, no build, no network. Under a
# second. It says nothing about -- and does nothing to -- the checkout it runs from, so it is safe
# alongside siblings editing the real ledger.
pass=0; fail=0
# Both halves are required. An exit code alone would pass a refusal that fired for the wrong reason;
# a needle alone would pass a script that printed it and exited 0. Needles arrive as separate words
# because a caller may hand this file to a shell that does not word-split an unquoted parameter.
#
# EVERY REFUSAL IS ALSO NAMED IN ITS MODE BANNER, and that is not decoration (T-1343). `check` prints
# its needles only when it FAILS, so on a green run the only trace of `LEDGER-VIEW-BAD-ID` was inside
# an unprinted argument list -- and `CadenceGuardScriptSelftestTests.complaints(requiring:)` reads
# this run's OUTPUT for each refusal it claims to exercise, precisely so that a mode deleted from the
# selftest cannot pass as a mode that quietly succeeded. Three of the four were invisible to it. The
# banners carry them the way `ledger-lag-check.sh`'s do, so a deleted mode takes its name with it.
check() {
    _rc=$1; _exp=$2; _out=$3; _label=$4
    shift 4
    ok=1
    [ "$_rc" = "$_exp" ] || ok=0
    for _needle in "$@"; do
        case "$_out" in *"$_needle"*) ;; *) ok=0 ;; esac
    done
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); printf '   ok   %s\n' "$_label"
    else fail=$((fail + 1)); printf '   FAIL %s\n        wanted exit %s containing [%s]; got exit %s:\n%s\n' "$_label" "$_exp" "$*" "$_rc" "$_out"; fi
}
# The opposite assertion, and the reason the readings above are evidence: "T-14 reads as open" also
# passes on a tool that printed every entry twice under both statuses. These say what must be ABSENT.
checkno() {
    _rc=$1; _exp=$2; _out=$3; _label=$4
    shift 4
    ok=1
    [ "$_rc" = "$_exp" ] || ok=0
    for _needle in "$@"; do
        case "$_out" in *"$_needle"*) ok=0 ;; esac
    done
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); printf '   ok   %s\n' "$_label"
    else fail=$((fail + 1)); printf '   FAIL %s\n        wanted exit %s WITHOUT [%s]; got exit %s:\n%s\n' "$_label" "$_exp" "$*" "$_rc" "$_out"; fi
}

cmd_selftest() {
    ws=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ledger-view-selftest-XXXXXX") || exit 3
    trap 'rm -rf "$ws"' EXIT INT TERM
    echo "== ledger-view.sh selftest =="

    todo="$ws/TODO.md"
    archive="$ws/TODO_DONE.md"
    export CADENCE_LEDGER_VIEW_TODO="$todo" CADENCE_LEDGER_VIEW_DONE="$archive"
    # Floors scaled to a fixture. The SHIPPED floor is proved in mode 5 with the override removed,
    # which is the half that would otherwise never run.
    CADENCE_LEDGER_VIEW_MIN_ENTRIES=1; export CADENCE_LEDGER_VIEW_MIN_ENTRIES
    run() { sh "$SELF_PATH" "$@" 2>&1; }

    cat > "$archive" <<'FIXTURE'
# Archive

- [T-40] **CLOSED 2026-09-01 (`def5678`) — archived where closed items go.**
FIXTURE

    cat > "$todo" <<'FIXTURE'
# Ledger

## In progress

- [T-10] **A multiline entry whose finding runs over several lines, and whose later paragraphs are
  indented, so the block does not end until column 1 is reached again.** Filed by the fixture.
  Wanted: the continuation lines read as part of T-10 and not as entries of their own.

  A second paragraph after a blank line, still indented, still T-10. It mentions - [T-99] inline,
  indented, which must NOT be read as a new entry.

## Open — decided, not started

- [T-11] **A plain open finding.** Nothing else to say about it.
- [T-12] **CLOSED 2026-09-19 (`abc1234`) — done, and the marker opens the line.**
- [T-13] **PARTIAL 2026-09-20 (agent `fixture`) — one of six built, five deliberately unbuilt.**
  The five are neither built nor refused, and saying so is the honest state.
- [T-14] **An entry whose first line quotes the token, as `**CLOSED 2026-09-04**`, while writing
  about the ledger format.** This is the T-1335 shape and it must read as open.
- [T-15] **An entry whose prose says CLOSED loose in a sentence.** Still open.
- [T-16] **A finding whose closure sentence was buried, not written on the first line.**
  **CLOSED 2026-09-21 (`0000000`) — the closure an agent put in the wrong place.**
- [T-17] **A ticket closed and then legitimately re-opened, old closure kept as history.**
  **CLOSED 2026-09-15 (`1111111`) — the closure that was correct until it was re-opened.**
- [T-18] **A finding nobody can act on yet.** **BLOCKED ON iOS distribution** — do not implement
  until that changes. Wanted: the distribution question answered first.
- [T-19] **Another parked one.** **Not urgent:** nothing in the tree is in this state today.
- [T-20] **One of two entries two concurrent agents allocated for the same id.**
- [T-20] **CLOSED 2026-09-20 (`2222222`) — the twin that carries the closure.**
- [T-21] **An open entry with an explicit repair.** The repair is to file the missing stub before
  anything else. Nothing is blocked on it.
- [T-24] **A finding that was closed after the fact.** **CLOSED 2026-09-21 (`4444444`) — the
  closure written mid-line, after the original finding. This is T-777's shape and it IS closed.**
- [T-25] **An open finding whose BODY quotes the marker at the start of a line.**
  `**CLOSED 2026-09-21**` is what a closure looks like, and writing that down must not bury one.
- [T-26] **A finding whose buried closure sentence opens with an inline-code span.**
  `2026-09-22` **CLOSED (`5555555`) — the closure an agent put in the wrong place, after a date.**
- [T-110] **A longer id that must not be matched by a lookup for T-11.**

## Done

- [T-30] **A done entry with no marker at all.**

## Cancelled

- [T-31] **A cancelled entry with no marker at all.**
FIXTURE

    # --- mode 1: the readings a naive first-line token scan gets wrong ------
    echo; echo " mode 1 (the hard readings) -- every case the naive first-line token scan gets wrong"
    out=$(run brief); rc=$?
    check "$rc" 0 "$out" "a PARTIAL closure is active, not closed" "T-13     PARTIAL"
    check "$rc" 0 "$out" "an entry that QUOTES the token on its first line stays open ([[T-1335]])" "T-14     OPEN"
    check "$rc" 0 "$out" "the token loose in first-line prose does not close an entry either" "T-15     OPEN"
    check "$rc" 0 "$out" "a closure buried deeper in the block leaves the entry active, and flags it" \
        "T-16     OPEN" BODY-CLOSURE
    check "$rc" 0 "$out" "a RE-OPENED entry reads ACTIVE despite its historical closure sentence" \
        "T-17     OPEN" BODY-CLOSURE
    check "$rc" 0 "$out" "a multiline entry is one entry" "T-10     OPEN"
    checkno "$rc" 0 "$out" "an indented '- [T-99]' inside a block is not an entry of its own" "T-99"
    checkno "$rc" 0 "$out" "a closure marker OPENING the first line does close the entry" "T-12     "
    # T-1335's two halves, and they pull in opposite directions -- which is why both are pinned.
    # A marker QUOTED inside inline code is not a closure (T-14, above); a marker written mid-line,
    # after the original finding, IS one, and the strictly-anchored reading this file shipped until
    # T-1335 was the only candidate that failed to recognise it. `scripts/replay-closure-reading.sh`
    # measured that cost over every entry first line that has ever existed.
    checkno "$rc" 0 "$out" "a closure written MID-LINE after the finding closes the entry too ([[T-777]])" \
        "T-24     "
    checkno "$rc" 0 "$out" "an entry under ## Done is closed with no marker at all" "T-30     "
    checkno "$rc" 0 "$out" "an entry under ## Cancelled is closed with no marker at all" "T-31     "
    checkno "$rc" 0 "$out" "an entry archived into TODO_DONE.md is closed" "T-40     "
    checkno "$rc" 0 "$out" "an id with a closed twin is not listed as active work ([[T-1303]])" "T-20     "

    out=$(run brief | grep '^T-25 '); rc=$?
    check "$rc" 0 "$out" "an entry whose BODY quotes the marker in backticks stays open" "T-25     OPEN"
    checkno "$rc" 0 "$out" "and is not flagged as a buried closure for quoting one" BODY-CLOSURE

    # The other side of the same stripping, and the half that WIDENS rather than narrows: a buried
    # closure sentence whose bold run follows an inline-code span still opens its line once the span
    # is read as the quotation it is. Without this, only the narrowing half of `closure_visible`
    # would be provable, and a stripping pass nothing can distinguish from the identity is not a
    # reading -- it is a line nobody can delete safely.
    out=$(run brief | grep '^T-26 '); rc=$?
    check "$rc" 0 "$out" "a buried closure whose bold run follows a code span is still buried" \
        "T-26     OPEN" BODY-CLOSURE

    out=$(run all); rc=$?
    check "$rc" 0 "$out" "'all' shows the mid-line closure as CLOSED, not merely absent from 'brief'" \
        "T-24     CLOSED"
    check "$rc" 0 "$out" "'all' still shows the duplicated id's open twin, flagged, so it is visible" \
        "T-20     OPEN" DUP
    check "$rc" 0 "$out" "'all' shows closed entries too, which 'brief' deliberately does not" \
        "T-12     CLOSED" "T-30     DONE" "T-31     CANCELLED" "T-40     ARCHIVED"

    # --- mode 2: status, next action, park reason, source location ----------
    echo; echo " mode 2 (the columns) -- status, the one-line next action, the source location"
    out=$(run); rc=$?
    check "$rc" 0 "$out" "a parked entry says PARKED and why it is parked" \
        "T-18     PARKED" "parked: BLOCKED ON iOS distribution"
    check "$rc" 0 "$out" "a second park vocabulary is read too" "T-19     PARKED" "parked: Not urgent:"
    check "$rc" 0 "$out" "an explicit Wanted: clause becomes the next action" \
        "next: Wanted: the distribution question"
    check "$rc" 0 "$out" "so does a 'The repair is' clause" "next: The repair is to file the missing stub"
    check "$rc" 0 "$out" "every entry carries its source location" "TODO.md:"
    check "$rc" 0 "$out" "and the run says how much it read" "active entries"
    # `run` with no arguments at all, which is both the usage line's first form and the shape that
    # `case "${1:-open}"` silently breaks: the pattern defaults, the parameter does not.
    check "$rc" 0 "$out" "the no-argument invocation is the default view, not an unbound-variable" "T-11     OPEN"

    # --- mode 3: the exact-id block lookup ----------------------------------
    echo; echo " mode 3 (show; LEDGER-VIEW-NO-SUCH-ID, LEDGER-VIEW-BAD-ID) -- an EXACT id, over both ledgers"
    out=$(run show T-11); rc=$?
    check "$rc" 0 "$out" "show prints the block and its location" "A plain open finding" "TODO.md:"
    checkno "$rc" 0 "$out" "and does not bleed into T-110" "longer id that must not be matched"

    out=$(run show T-10); rc=$?
    check "$rc" 0 "$out" "show prints a multiline block whole, including the paragraph after a blank" \
        "must NOT be read as a new entry"

    out=$(run show T-40); rc=$?
    check "$rc" 0 "$out" "show reaches the archive as well as the open ledger" "archived where closed items go"

    out=$(run show T-20); rc=$?
    check "$rc" 0 "$out" "show prints BOTH entries of a duplicated id, flagged" DUP "the twin that carries the closure"

    out=$(run show T-9001); rc=$?
    check "$rc" 5 "$out" "an id with no formal entry anywhere is refused, not silently empty" \
        LEDGER-VIEW-NO-SUCH-ID

    out=$(run show nonsense); rc=$?
    check "$rc" 2 "$out" "an argument that is not a ticket id is refused" LEDGER-VIEW-BAD-ID

    out=$(run show); rc=$?
    check "$rc" 2 "$out" "show with no id at all is refused the same way" LEDGER-VIEW-BAD-ID

    # --- mode 3b: the mode nobody defined -----------------------------------
    echo; echo " mode 3b (LEDGER-VIEW-UNKNOWN-MODE) -- a typo must be refused, never quietly defaulted"
    out=$(run wibble); rc=$?
    check "$rc" 2 "$out" "an unknown mode is refused rather than quietly defaulting" LEDGER-VIEW-UNKNOWN-MODE

    # --- mode 4: the census, and the delta it exists to show ----------------
    echo; echo " mode 4 (counts) -- the census, beside the naive reading it corrects"
    out=$(run counts); rc=$?
    check "$rc" 0 "$out" "counts reports entries, ids and duplicates" "distinct ids" "more than one entry"
    check "$rc" 0 "$out" "counts reports the status buckets" "by status:" "PARTIAL=1"
    check "$rc" 0 "$out" "counts reports entries AND ids, which differ when an id is duplicated" "ACTIVE:"
    check "$rc" 0 "$out" "counts prints the naive lexical reading beside it, so the delta is visible" \
        "naive lexical reading"

    # --- mode 5: the floor, with the SHIPPED default ------------------------
    echo; echo " mode 5 (LEDGER-VIEW-VACUOUS) -- a run that read too little must not look tidy"
    out=$(env -u CADENCE_LEDGER_VIEW_MIN_ENTRIES sh "$SELF_PATH" brief 2>&1); rc=$?
    check "$rc" 4 "$out" "the shipped floor refuses this small fixture outright" LEDGER-VIEW-VACUOUS

    : > "$ws/empty.md"
    out=$(CADENCE_LEDGER_VIEW_TODO="$ws/empty.md" CADENCE_LEDGER_VIEW_DONE="$ws/gone.md" \
        sh "$SELF_PATH" brief 2>&1); rc=$?
    check "$rc" 4 "$out" "an EMPTY ledger is vacuous, not an empty backlog" LEDGER-VIEW-VACUOUS

    out=$(CADENCE_LEDGER_VIEW_TODO="$ws/no-such-ledger.md" sh "$SELF_PATH" brief 2>&1); rc=$?
    check "$rc" 4 "$out" "a ledger path that resolves to nothing is vacuous too" LEDGER-VIEW-VACUOUS

    out=$(CADENCE_LEDGER_VIEW_MIN_ENTRIES=9999 sh "$SELF_PATH" counts 2>&1); rc=$?
    check "$rc" 4 "$out" "the floor guards counts, the mode a census would trust" LEDGER-VIEW-VACUOUS

    out=$(CADENCE_LEDGER_VIEW_MIN_ENTRIES=9999 sh "$SELF_PATH" show T-11 2>&1); rc=$?
    check "$rc" 4 "$out" "and guards show, so a lookup cannot report NO-SUCH-ID off an unread file" \
        LEDGER-VIEW-VACUOUS

    out=$(CADENCE_LEDGER_VIEW_DONE="$ws/no-such-archive.md" sh "$SELF_PATH" brief 2>&1); rc=$?
    check "$rc" 0 "$out" "a MISSING archive does not shift the open ledger's reading ([[T-1317]])" "T-11     OPEN"
    checkno "$rc" 0 "$out" "and does not make the open ledger read as the archive" "T-12     "

    echo
    # The vocabulary `CadenceGuardScriptSelftestTests` reads. A tally is what a selftest gutted to
    # `return 0` cannot produce, which is why exit 0 alone is not the pin.
    echo "checks: $pass passed, $fail failed"
    [ "$fail" = 0 ] || exit 1
}

main "$@"
