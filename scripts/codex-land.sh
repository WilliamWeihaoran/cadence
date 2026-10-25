#!/bin/sh
# Review a Codex branch before the coordinator lands it (docs/CODEX_WORKTREE.md).
#   ./scripts/codex-land.sh review <ref>      # what would land, and every refusal that fires
#   ./scripts/codex-land.sh lease [--status]  # the lease as parsed; --status asks held or spent
#   ./scripts/codex-land.sh held <path>...    # is this path HELD, not merely listed (T-6400)
#   ./scripts/codex-land.sh inbox             # ids currently pending in the inbox
#   ./scripts/codex-land.sh selftest          # prove the refusals still fire
#
# WHY REVIEW AND NOT LAND. This script never commits. Landing goes through
# `scripts/agent-commit.sh`, because that is where FOREIGN-STAGED, REMOVES-HEAD-LINES,
# LEDGER-ID-UNFILED, the T-1335 closure reading and T-1385's foreign-hunk notice live. A second
# landing path would be a second set of guards to keep in step, and T-1382 is the story of what
# happens when two copies of one rule drift for thirteen days.
#
# WHY A LEASE AT ALL. T-1385: `agent-commit.sh` stages WHOLE FILES, so two writers in one file
# means one commit silently carries the other's half-finished work -- no refusal, no declined hunk.
# A separate worktree makes that impossible for files nobody shares; the lease is what keeps the
# sharing from happening in the first place.
#
# GLOBBING IS OFF IN THIS SCRIPT, DELIBERATELY (T-1428). The lease is a list of shell globs, and
# `for pat in $lease` performs PATHNAME EXPANSION on it before the pattern is ever used: with
# three `iOSTaskCollection*.swift` files on disk, the lease line stopped being a pattern and became
# those three literal names. The failure shape is the worst available -- a path that already exists
# is inside its own expansion and passes, so the guard looks correct for every existing file and
# refuses only a NEW one, which is exactly the case a lease exists to govern. It refused Codex's
# first branch and read as Codex violating the protocol. `set -f` disables pathname expansion and
# does NOT affect `case` pattern matching, which is what actually does the lease check.
set -f

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# `/usr/bin/git` is an xcrun shim and xcrun refuses to run inside an App Sandbox, so from the
# sandboxed test host every git call fails with "cannot be used within an App Sandbox" on stderr
# and nothing else -- which reads like a broken repository rather than a missing tool. Same probe
# `scripts/worktree-drift.sh` and `scripts/agent-commit.sh` carry, for the same reason: this script
# is run by `CadenceGuardScriptSelftestTests` from inside that host. Written with `[ ]` rather than
# `[[ ]]` because this script is `#!/bin/sh`, unlike the zsh siblings it copies the probe from.
if ! git --version >/dev/null 2>&1; then
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin; do
        [ -x "$_candidate/git" ] || continue
        "$_candidate/git" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; export PATH; break
    done
fi
cd "$ROOT" || exit 2
DOC=docs/CODEX_WORKTREE.md
INBOX=docs/CODEX_LEDGER_INBOX.md
TODO=docs/TODO.md
DONE=docs/TODO_DONE.md

# --- the lease, parsed from the fenced block in the protocol doc -------------
read_lease() {   # stdout: one glob per line
    [ -f "$DOC" ] || return 1
    awk '/^```lease$/ { inb = 1; next } inb && /^```$/ { exit } inb && NF { print }' "$DOC"
}

cmd_lease() {
    lease=$(read_lease) || { printf 'REFUSED (CODEX-LEASE-UNREADABLE): %s is missing.\n' "$DOC" >&2; return 2; }
    n=$(printf '%s\n' "$lease" | grep -c '^' )
    [ -n "$lease" ] || { printf 'REFUSED (CODEX-LEASE-EMPTY): the lease block in %s names no path.\n  An empty lease reads exactly like a lease that allows everything; it allows nothing.\n' "$DOC" >&2; return 4; }
    lease_validate || return $?
    if [ "${1:-}" = "--status" ]; then cmd_lease_status; return $?; fi
    printf '%s\n' "$lease"
    printf 'lease: %d pattern(s) from %s (plus %s, always allowed).\n' "$n" "$DOC" "$INBOX"
    printf 'This answers "is it LISTED". For "is it HELD", which is the other question and the one\n  that cost a round trip on 2026-10-24, ask `./scripts/codex-land.sh held <path>` (T-6400).\n'
}

cmd_inbox() {
    [ -f "$INBOX" ] || { printf 'inbox: %s does not exist yet; nothing pending.\n' "$INBOX"; return 0; }
    ids=$(grep -oE '^- \[T-[0-9]+\]' "$INBOX" | sed 's/^- \[//;s/\]$//' | sort -u)
    [ -n "$ids" ] && printf '%s\n' "$ids"
    # NOT `$(grep -c … || echo 0)`: `grep -c` prints its count AND exits 1 when the count is zero,
    # so the substitution yields "0\n0" and `printf %d` refuses it. Let grep's own zero stand.
    nlines=$(grep -c '^- \[T-[0-9]\+\]' "$INBOX" 2>/dev/null); nlines=${nlines:-0}
    nids=$(printf '%s\n' "$ids" | grep -c '^T-'); nids=${nids:-0}
    printf 'inbox: %d entry line(s), %d distinct id(s).\n' "$nlines" "$nids"
}

# --- the grant record: one row per lease pattern (T-6400) ---------------------
# WHY A SECOND BLOCK RATHER THAN AN ANNOTATION ON THE LEASE LINES. `read_lease` above is copied
# verbatim into `scripts/ledger-blocker-check.sh`, deliberately, "so the two cannot answer
# differently about what the fence holds" -- and that copy feeds each line straight to Python
# fnmatch. A trailing `branch=... granted=...` on a lease line would quietly turn every pattern
# there into one that matches nothing: a guard that reads clean because it is asking a question
# with no answers, which is the failure this whole document is about. So the lease block stays
# bare and the grant record sits beside it, with refusals below that fire the moment the two
# disagree in either direction. Two lists that cannot drift is not the same thing as one list.
#
# WHAT THE ROWS ARE FOR. `lease` answers *is this path LISTED*. That is a cheaper question than
# *is this path HELD*, and on 2026-10-24 the gap cost a full round trip: five tickets were routed
# to Codex because fnmatch found their paths in the block, and Codex handed all five back -- four
# covered by the 2026-10-20 blanket release, the rest on grants that lapsed when `e711077c` and
# `82901ff6` landed. A grant is for a BRANCH, and when that branch lands the path is free. The
# bare list records no branch, so no entry in it can ever expire; it only ever grows.
#
#   <pattern>  branch=<ref|->  granted=<YYYY-MM-DD>  grant=<sha>  [spent=<sha>]
#
# branch   the Codex branch the grant was made for. `-` is allowed ONLY alongside `spent=`, which
#          is how the 104 patterns released wholesale on 2026-10-20 are carried: their grants are
#          spent, and which branch each was for is not recoverable from this document's history.
# granted  the date the pattern entered the lease block.
# grant    the commit that added it. Evidence for a reader (`git show <sha> -- docs/CODEX_WORKTREE.md`),
#          not checked here -- it is the release that has to be true, not the provenance.
# spent    the commit that RELEASED it. CHECKED, because a release recorded against a commit that
#          never landed is not a release: it must resolve, and it must be an ancestor of main.
GRANTS_BLOCK='```lease-grants'
read_grants() {   # stdout: one row per lease pattern
    [ -f "$DOC" ] || return 1
    awk '/^```lease-grants$/ { inb = 1; next } inb && /^```$/ { exit } inb && NF && $1 !~ /^#/ { print }' "$DOC"
}

row_field() {   # $1 = row, $2 = key; stdout: the value, empty when absent
    # `grant=` is not a prefix of `granted=` -- they differ at the sixth character -- so an
    # index() test is enough and no ordering trick is needed.
    printf '%s\n' "$1" | awk -v k="$2=" '{ for (i = 2; i <= NF; i++) if (index($i, k) == 1) { print substr($i, length(k) + 1); exit } }'
}

# Every lease pattern has exactly one row, and every row names a lease pattern. Either half alone
# rots: a pattern with no row is a path nothing can ever expire, and a row with no pattern is a
# release nobody reads. Both refuse, which is what makes it impossible to add a path to the fence
# without recording the branch it is held for -- the omission this list died of.
lease_validate() {
    _l=$(read_lease) || { printf 'REFUSED (CODEX-LEASE-UNREADABLE): %s is missing.\n' "$DOC" >&2; return 2; }
    [ -n "$_l" ] || { printf 'REFUSED (CODEX-LEASE-EMPTY): the lease block in %s names no path.\n  An empty lease reads exactly like a lease that allows everything; it allows nothing.\n' "$DOC" >&2; return 4; }
    _g=$(read_grants)
    [ -n "$_g" ] || { printf 'REFUSED (CODEX-GRANTS-EMPTY): %s holds a lease block and no %s block.\n  A fence whose entries record no branch cannot expire, so it only grows (T-6400).\n' "$DOC" "$GRANTS_BLOCK" >&2; return 4; }
    _bad=$( { printf '%s\n' "$_g" | sed 's/^/G	/'; printf '%s\n' "$_l" | sed 's/^/L	/'; } | awk -F'\t' '
        $1 == "G" {
            n = split($2, f, /[ \t]+/)
            pat = f[1]; g[pat]++
            b = ""; d = ""; c = ""; s = ""
            for (i = 2; i <= n; i++) {
                if (f[i] ~ /^branch=/)       b = substr(f[i], 8)
                else if (f[i] ~ /^granted=/) d = substr(f[i], 9)
                else if (f[i] ~ /^grant=/)   c = substr(f[i], 7)
                else if (f[i] ~ /^spent=/)   s = substr(f[i], 7)
                else print "UNKNOWN-FIELD        " pat "  (" f[i] ")"
            }
            if (b == "") print "NO-BRANCH            " pat
            if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) print "NO-GRANTED-DATE      " pat
            if (c == "") print "NO-GRANT-COMMIT      " pat
            if (b == "-" && s == "") print "ANONYMOUS-AND-UNSPENT " pat
        }
        $1 == "L" { l[$2]++ }
        END {
            for (k in l) if (!(k in g)) print "NO-GRANT-ROW         " k
            for (k in g) if (!(k in l)) print "ROW-WITHOUT-PATTERN  " k
            for (k in g) if (g[k] > 1)  print "TWO-ROWS-ONE-PATTERN " k
        }')
    [ -z "$_bad" ] && return 0
    printf 'REFUSED (CODEX-LEASE-UNRECORDED): the lease block and the %s block disagree.\n' "$GRANTS_BLOCK" >&2
    printf '%s\n' "$_bad" | sed 's/^/  /' >&2
    printf '  Every fenced pattern needs a row naming the branch it is held for, the date, and the\n  commit that fenced it; every row needs a pattern. Without the branch nothing can expire.\n' >&2
    return 4
}

# --- is a path HELD, or only listed? (T-6400) ---------------------------------
# Sets STATUS and STATUS_TEXT. The fail-safe direction is deliberate and it is not symmetrical:
# an over-wide fence costs a round trip, an under-wide one costs an agent's finished work. So
# anything this cannot settle reports HELD, and only an answer it can stand behind reports SPENT.
grant_status() {   # $1 = a grant row
    _row=$1
    _pat=$(printf '%s\n' "$_row" | awk '{ print $1 }')
    _br=$(row_field "$_row" branch)
    _sp=$(row_field "$_row" spent)

    if [ -n "$_sp" ] && [ "$_sp" != "-" ]; then
        if ! git rev-parse --verify --quiet "$_sp^{commit}" >/dev/null 2>&1; then
            STATUS=HELD
            STATUS_TEXT="spent=$_sp names no commit in this repository, so the release cannot be read -- a release recorded against nothing is not a release"
            return 0
        fi
        if ! git merge-base --is-ancestor "$_sp" main 2>/dev/null; then
            STATUS=HELD
            STATUS_TEXT="spent=$_sp is not an ancestor of main, so the landing it records never landed"
            return 0
        fi
        STATUS=SPENT
        if [ "$_br" = "-" ]; then STATUS_TEXT="released by $_sp"
        else STATUS_TEXT="granted for $_br, released by $_sp"; fi
        return 0
    fi

    if [ "$_br" = "-" ] || ! git rev-parse --verify --quiet "$_br" >/dev/null 2>&1; then
        STATUS=HELD
        STATUS_TEXT="branch $_br does not resolve and no release is recorded -- cannot tell, so it stays fenced"
        return 0
    fi

    # The branch's OWN commits, `--no-merges`, which is the narrowing this document settled on
    # after six wrong answers in one day. `git diff main..<branch>` would also hand back what
    # MAIN changed, which is how a stale branch reads as a live one.
    _touched=$(git log --no-merges --name-only --format= "main..$_br" 2>/dev/null | sort -u | grep -v '^$')
    _match=
    for _f in $_touched; do
        # shellcheck disable=SC2254
        case "$_f" in $_pat) _match="$_match $_f" ;; esac
    done
    if [ -z "$_match" ]; then
        STATUS=RESERVED
        STATUS_TEXT="$_br exists but has written nothing matching this pattern; a grant made ahead of the job is a hold on a file nobody is writing (iOSSearchView.swift, 2026-10-24) -- ask before releasing it"
        return 0
    fi
    _unlanded=
    for _f in $_match; do
        git diff --quiet main "$_br" -- "$_f" 2>/dev/null && continue
        blob_is_in_main_history "$_br" "$_f" && continue
        _unlanded="$_unlanded $_f"
    done
    if [ -n "$_unlanded" ]; then
        STATUS=HELD
        STATUS_TEXT="$_br holds work main does not have:$_unlanded"
    else
        STATUS=SPENT
        STATUS_TEXT="measured: every file $_br wrote under this pattern is already in main"
    fi
}

cmd_held() {
    [ $# -gt 0 ] || { printf 'REFUSED (CODEX-HELD-NO-PATH): name the repository-relative path(s) to ask about.\n  `lease` says what is listed; `held` says what is still held, which is the other question.\n' >&2; return 2; }
    lease_validate || return $?
    _lease=$(read_lease)
    _grants=$(read_grants)
    _worst=0
    for _q in "$@"; do
        printf '%s\n' "$_q"
        _hits=0
        _done=
        for _pat in $_lease; do
            # shellcheck disable=SC2254
            case "$_q" in $_pat) ;; *) continue ;; esac
            case " $_done " in *" $_pat "*) continue ;; esac   # the block repeats four patterns
            _done="$_done $_pat"
            _hits=$((_hits + 1))
            _row=$(printf '%s\n' "$_grants" | awk -v p="$_pat" '$1 == p { print; exit }')
            grant_status "$_row"
            printf '  %-8s  %s\n            granted %s, grant %s -- %s\n' \
                "$STATUS" "$_pat" "$(row_field "$_row" granted)" "$(row_field "$_row" grant)" "$STATUS_TEXT"
            case $STATUS in
                HELD)     _worst=3 ;;
                RESERVED) [ "$_worst" -lt 2 ] && _worst=2 ;;
            esac
        done
        [ "$_hits" -eq 0 ] && printf '  UNFENCED  no lease pattern matches this path; write it.\n'
    done
    case $_worst in
        3) printf '\nHELD: a live grant covers at least one path above. Do not write it and do not release it;\n  releasing a path a branch is still writing is the one error here that destroys work.\n'; return 3 ;;
        2) printf '\nRESERVED: at least one path is fenced for a branch that has written nothing under it.\n  That is a hold on a file nobody is writing. Ask the coordinator rather than assuming either way.\n'; return 4 ;;
        *) printf '\nNOT HELD: every grant matching the path(s) above is spent. The fence lists them; it does not hold them.\n'; return 0 ;;
    esac
}

cmd_lease_status() {
    lease_validate || return $?
    _lease=$(read_lease)
    _grants=$(read_grants)
    _held=0; _spent=0; _reserved=0
    _done=
    for _pat in $_lease; do
        case " $_done " in *" $_pat "*) continue ;; esac
        _done="$_done $_pat"
        _row=$(printf '%s\n' "$_grants" | awk -v p="$_pat" '$1 == p { print; exit }')
        grant_status "$_row"
        printf '%-8s  %-62s  %s\n' "$STATUS" "$_pat" "$STATUS_TEXT"
        case $STATUS in
            HELD)     _held=$((_held + 1)) ;;
            RESERVED) _reserved=$((_reserved + 1)) ;;
            *)        _spent=$((_spent + 1)) ;;
        esac
    done
    printf '\nlease: %d held, %d reserved, %d spent.\n' "$_held" "$_reserved" "$_spent"
    [ "$_held" -eq 0 ] && [ "$_reserved" -eq 0 ] && printf 'Nothing in the fence is held. Every pattern here is a permission for Codex, not a block on you.\n'
    return 0
}

# --- is one named file already in main? (T-1930) ------------------------------
# `git diff --name-only "$base".."$ref"` answers *what did this branch change since it forked*.
# With a branch 23 commits behind main that is NOT *what is main missing*, and the difference is
# not academic: measured 2026-10-01, `review codex/task-page-typography-finish` exited 3 with three
# CODEX-INBOX-ID-CLASH refusals over a 31-file list -- the same exit code and the same words a
# genuinely blocked branch gets -- while every one of those 31 files was already in main. The ids
# clashed BECAUSE the work had landed. So every named file is asked the two-dot question too.
#
# Two shapes count as already-in-main, and the second is why a plain byte comparison is not enough:
#
#   identical    `git diff --quiet main "$ref" -- "$f"`; the bytes match.
#   main-ahead   the branch's blob for that path appears somewhere in main's own history for that
#                path. Two of the 31 measured files were this: the work landed and main then moved
#                PAST it, so the bytes differ while the branch still contributes nothing. Calling
#                that pending would leave the one defect this is for half-unreported.
#
# The history scan is bounded because it costs three processes per file, and the bound fails SAFE:
# a landed file whose commit sits deeper than the scan reads as pending, which leaves a coordinator
# looking at a spent branch -- never the reverse, which would be advising `reset --hard` over work.
BLOB_SCAN_DEPTH=${CODEX_BLOB_SCAN_DEPTH:-200}

blob_is_in_main_history() {   # $1 = ref, $2 = path
    _bb=$(git rev-parse "$1:$2" 2>/dev/null) || return 1
    [ -n "$_bb" ] || return 1
    # One `rev-list` + one `cat-file --batch-check` per file rather than a `rev-parse` per commit:
    # 31 files against a 50-commit scan is 1,550 processes the other way round.
    git rev-list -n "$BLOB_SCAN_DEPTH" main -- "$2" 2>/dev/null \
        | sed "s|\$|:$2|" \
        | git cat-file --batch-check='%(objectname)' 2>/dev/null \
        | grep -qxF "$_bb"
}

# --- review ------------------------------------------------------------------
cmd_review() {
    ref=${1:-}
    [ -n "$ref" ] || { printf 'REFUSED (CODEX-NO-REF): name the branch to review.\n' >&2; return 2; }
    git rev-parse --verify --quiet "$ref" >/dev/null || {
        printf 'REFUSED (CODEX-NO-SUCH-REF): %s does not resolve.\n' "$ref" >&2; return 2; }

    base=$(git merge-base "$ref" main 2>/dev/null) || base=
    [ -n "$base" ] || { printf 'REFUSED (CODEX-NO-MERGE-BASE): %s shares no history with main.\n' "$ref" >&2; return 2; }

    files=$(git diff --name-only "$base".."$ref")
    ncommits=$(git rev-list --count "$base".."$ref")
    # Counted only when there is something to count (T-2051): `printf '%s\n' ""` is one empty
    # line, so `grep -c '^'` on an empty diff answered 1 and the vacuity refusal below reported
    # "1 changed file(s)" for a branch that changed none.
    if [ -n "$files" ]; then nfiles=$(printf '%s\n' "$files" | grep -c '^'); else nfiles=0; fi

    # NON-VACUITY, the shape every guard here carries (T-1282): a review that read nothing must
    # refuse rather than report a clean branch. An empty diff and a broken ref look the same.
    if [ "$ncommits" -eq 0 ] || [ -z "$files" ]; then
        printf 'REFUSED (CODEX-REVIEW-VACUOUS): %s adds %d commit(s) and %d changed file(s) over main.\n  A branch with nothing on it reads exactly like a clean review; it is not one.\n' \
            "$ref" "$ncommits" "$nfiles" >&2
        return 4
    fi

    lease=$(read_lease)
    [ -n "$lease" ] || { printf 'REFUSED (CODEX-LEASE-EMPTY): no lease to check against.\n' >&2; return 4; }
    # The grant record is checked here and not only in `lease`, because this is where a lease that
    # nobody can expire actually does its damage: it refuses work on a path whose grant is spent.
    lease_validate || return $?

    rc=0
    printf 'codex-land: %s is %d commit(s), %d file(s) over %s\n\n' "$ref" "$ncommits" "$nfiles" "$(echo "$base" | cut -c1-8)"

    # 0. does main already have this? (T-1930) -- asked FIRST, because when the answer is yes every
    #    refusal below is a consequence of the work having landed rather than an obstacle to it.
    landed_report=
    pending_list=
    n_identical=0; n_ahead=0; n_pending=0
    for f in $files; do
        if git diff --quiet main "$ref" -- "$f" 2>/dev/null; then
            mark='already in main (identical)'; n_identical=$((n_identical+1))
        elif blob_is_in_main_history "$ref" "$f"; then
            mark='already in main (main has moved past it)'; n_ahead=$((n_ahead+1))
        else
            mark='NOT in main'; n_pending=$((n_pending+1)); pending_list="$pending_list $f"
        fi
        landed_report="$landed_report  $f  --  $mark
"
    done
    if [ "$n_pending" -eq 0 ]; then
        printf 'REFUSED (CODEX-BRANCH-ALREADY-LANDED): all %d file(s) this branch changed are\n  already in main -- %d identical, %d where main has moved past the branch.\n' \
            "$nfiles" "$n_identical" "$n_ahead" >&2
        printf '  The branch is SPENT, not blocked. There is nothing here to land, and an id clash or a\n  lease complaint on a branch in this state is a CONSEQUENCE of the work having landed, not a\n  reason to call the coordinator (T-1930). Reset the Codex worktree to main and reassign.\n' >&2
        printf '\nfiles:\n'
        printf '%s' "$landed_report"
        return 5
    fi
    printf 'landed: %d of %d file(s) already in main; %d still only on the branch.\n' \
        "$((n_identical + n_ahead))" "$nfiles" "$n_pending"
    # The shape the live measurement actually had on 2026-10-01, once main had moved on: 30 of the
    # 31 files already in main and the 31st was the INBOX -- the branch's own ledger entries, which
    # the coordinator never published (T-1800). The code is spent; what is left is the record of it,
    # and an id clash on a branch in THIS state is still a consequence of the work having landed.
    # Said out loud, because a reader who sees only three CODEX-INBOX-ID-CLASH lines concludes the
    # opposite -- that is the defect this whole section is for.
    if [ "$n_pending" -eq 1 ] && [ "$pending_list" = " $INBOX" ]; then
        printf 'note (CODEX-ONLY-THE-INBOX-IS-UNLANDED): every CODE file on this branch is already in\n  main; the one path that is not is %s, the branch'"'"'s own ledger entries.\n  Publish those entries on main (T-1800) rather than treating this as pending work -- an id\n  clash here means the work landed, not that it is blocked.\n' "$INBOX"
    fi
    printf '\n'

    # 1. the ledger is the coordinator's, always
    ledger_hit=$(printf '%s\n' "$files" | grep -E "^($TODO|$DONE)$" || true)
    if [ -n "$ledger_hit" ]; then
        printf 'REFUSED (CODEX-LEDGER-TOUCHED): this branch edits the ledger directly:\n' >&2
        printf '  %s\n' $ledger_hit >&2
        printf '  Every closure edits %s in place, so two writers there always collide. Append to\n  %s instead; the coordinator folds it in when landing.\n' "$TODO" "$INBOX" >&2
        rc=3
    fi

    # 2. the lease
    outside=
    for f in $files; do
        [ "$f" = "$INBOX" ] && continue
        ok=0
        for pat in $lease; do
            # shellcheck disable=SC2254
            case "$f" in $pat) ok=1; break ;; esac
        done
        [ "$ok" -eq 1 ] || outside="$outside $f"
    done
    if [ -n "$outside" ]; then
        printf 'REFUSED (CODEX-LEASE-VIOLATION): %d path(s) outside the lease:\n' "$(printf '%s\n' $outside | grep -c '^')" >&2
        for f in $outside; do printf '  %s\n' "$f" >&2; done
        printf '  Widen the lease in %s deliberately, or leave the path alone and say why it needed\n  changing. A path another writer holds is exactly the T-1385 collision this protocol exists for.\n' "$DOC" >&2
        rc=3
    fi

    # 3. code without a ledger entry
    code=$(printf '%s\n' "$files" | grep -vE '^docs/' | grep -vE '(^|/)AGENTS\.md$' || true)
    inbox_touched=$(printf '%s\n' "$files" | grep -cE "^$INBOX$" || true)
    if [ -n "$code" ] && [ "$inbox_touched" -eq 0 ]; then
        printf 'REFUSED (CODEX-NO-INBOX-ENTRY): this branch lands code and writes no ledger entry.\n' >&2
        printf '  %s is how Codex records what it did; without it the work lands unattributed and\n  `ledger-lag-check.sh` flags the landing commit. Append an entry per ticket.\n' "$INBOX" >&2
        rc=3
    fi

    # 4. an inbox id the ledger already carries
    if [ "$inbox_touched" -gt 0 ]; then
        # Only the ids THIS BRANCH ADDED (T-1490). The inbox is append-only by design, so every id
        # Codex has ever filed stays in it -- including the ones the coordinator has already folded
        # into the ledger, which is exactly when a formal entry exists for them. Reading the whole
        # file made the clash check fire on the protocol working correctly: Codex's second branch
        # was refused for T-1440/T-1441/T-1442, all three landed by the coordinator from its FIRST
        # branch. The question this check means to ask is "is this branch filing an id that is
        # already filed", so it must read the lines the branch added, not the file it inherited.
        newids=$(git diff "$base..$ref" -- "$INBOX" 2>/dev/null \
            | grep -E '^\+' | grep -oE '^\+- \[T-[0-9]+\]' | sed 's/^+- \[//;s/\]$//' | sort -u)
        for id in $newids; do
            if grep -qE "^- \[$id\]" "$TODO" "$DONE" 2>/dev/null; then
                printf 'REFUSED (CODEX-INBOX-ID-CLASH): %s already has a formal entry in the ledger.\n  One id with two entries is the shape T-1356 is about, so this refusal stays -- but it does not\n  by itself mean the branch is blocked, and twice it has been read that way (T-1800).\n  If the coordinator PRE-FILED a stub for this id and assigned the branch to it, this exit is the\n  protocol working: at landing REPLACE THE STUB BODY IN PLACE, keeping the one id and adding no\n  second entry (T-1458, T-3003, T-3004).\n  If instead the id was folded formally while its own inbox entry was never published, publish that\n  entry on main unchanged and re-review (T-1800).\n  Never delete the entry, renumber it, or edit this check.\n' "$id" >&2
                rc=3
            fi
        done
    fi

    # 5. behind main -- a report, not a refusal: landing rebases anyway
    behind=$(git rev-list --count "$ref"..main 2>/dev/null || echo 0)
    [ "$behind" -gt 0 ] && printf 'note: %s is %d commit(s) behind main; the coordinator rebases at landing.\n' "$ref" "$behind"

    # Per file, whether main already has it (T-1930). A bare list of names was the whole of the
    # reporting defect: it reads as 31 files of pending work in exactly the case where it is none.
    printf '\nfiles:\n'
    printf '%s' "$landed_report"
    [ "$rc" -eq 0 ] && printf '\ncodex-land: no refusal fired. Run the tests, then land through scripts/agent-commit.sh.\n'
    return $rc
}

# --- selftest ----------------------------------------------------------------
# Every refusal is exercised against a throwaway clone, because a refusal nobody has seen fire is a
# refusal nobody knows still works -- T-1343's lesson, and T-1397's.
cmd_selftest() {
    pass=0; fail=0
    ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1";
           else fail=$((fail+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi; }

    # A fixture that cannot be built must SAY SO. This block used to end every step with
    # `|| return 2` and send git's stderr to /dev/null, so a host where the fixture could not be
    # created reported a bare exit 2 and the Swift wrapper could only say "nothing says a check
    # ran". That is the same silence T-1343 spent a day on. Each step now names itself and carries
    # git's own words out, which is what turns "exited 2" into a diagnosis.
    setup_fail() { printf 'SELFTEST FIXTURE FAILED at: %s\n' "$1" >&2; [ -n "$2" ] && printf '  %s\n' "$2" >&2; return 2; }

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/codex-land-selftest-XXXXXX") \
        || { setup_fail "mktemp -d under TMPDIR=${TMPDIR:-/tmp}"; return 2; }
    trap 'rm -rf "$tmp"' EXIT INT TERM
    ws="$tmp/repo"
    err=$(git init -q "$ws" 2>&1) || { setup_fail "git init $ws" "$err"; return 2; }
    err=$( ( cd "$ws" && git config user.email t@t && git config user.name t \
      && mkdir -p docs scripts Cadence/iOS \
      && printf '# x\n\n```lease\nCadence/iOS/iOSTaskRow*.swift\n```\n\n```lease-grants\nCadence/iOS/iOSTaskRow*.swift  branch=codex/fixture  granted=2026-10-20  grant=1111111\n```\n' > docs/CODEX_WORKTREE.md \
      && printf 'seed\n' > docs/TODO.md && printf 'seed\n' > docs/TODO_DONE.md \
      && printf 'x\n' > Cadence/iOS/iOSTaskRowExisting.swift \
      && cp "$ROOT/scripts/codex-land.sh" scripts/ && chmod +x scripts/codex-land.sh \
      && git add -A && git commit -qm base && git branch -M main ) 2>&1 ) \
      || { setup_fail "seeding the fixture repo (ROOT=$ROOT)" "$err"; return 2; }

    # Invoked through `sh`, not exec'd. The App-Sandboxed test host can WRITE the copy but not
    # execute it -- every `./scripts/codex-land.sh` came back 126 ("found, not executable") once
    # the git shim was solved, which looks nothing like a sandbox restriction in the output. This
    # is the same workaround the Swift wrapper already uses on this script from the outside
    # (`CadenceSelftestRun.of(..., interpreter: "/bin/sh")`); the fixture needed it on the inside
    # too. The real script's executable bit is unaffected and is still pinned by
    # `allGuardScriptsExistAndAreExecutable`.
    run() { ( cd "$ws" && sh ./scripts/codex-land.sh "$@" >/dev/null 2>&1; echo $? ); }

    ck "a lease with patterns is readable" "$(run lease)" 0

    ( cd "$ws" && git checkout -qb codex/empty main ) >/dev/null 2>&1
    ck "an empty branch is VACUOUS, not clean" "$(run review codex/empty)" 4
    # The number in the refusal is what an agent reads to decide whether the branch holds anything,
    # so it is asserted, not just the exit status (T-2051). The second branch is the case the count
    # exists for: two commits whose net diff over main is nothing.
    msg=$( cd "$ws" && sh ./scripts/codex-land.sh review codex/empty 2>&1 >/dev/null )
    case "$msg" in *"adds 0 commit(s) and 0 changed file(s)"*) got=yes ;; *) got="$msg" ;; esac
    ck "an empty branch's refusal counts 0 changed files, not 1" "$got" yes
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/netzero \
      && printf 'x\n' > Cadence/iOS/iOSTaskRowGone.swift && git add -A && git commit -qm t \
      && git rm -q Cadence/iOS/iOSTaskRowGone.swift && git commit -qm t ) >/dev/null 2>&1
    ck "a branch whose commits cancel out is VACUOUS too" "$(run review codex/netzero)" 4
    msg=$( cd "$ws" && sh ./scripts/codex-land.sh review codex/netzero 2>&1 >/dev/null )
    case "$msg" in *"adds 2 commit(s) and 0 changed file(s)"*) got=yes ;; *) got="$msg" ;; esac
    ck "...and its refusal counts 2 commits and 0 changed files" "$got" yes

    ( cd "$ws" && git checkout -q main && git checkout -qb codex/ledger \
      && printf 'edited\n' >> docs/TODO.md && git add -A && git commit -qm t ) >/dev/null 2>&1
    ck "editing the ledger is refused" "$(run review codex/ledger)" 3

    ( cd "$ws" && git checkout -q main && git checkout -qb codex/outside \
      && mkdir -p Cadence/iOS && printf 'x\n' > Cadence/iOS/iOSOther.swift && git add -A && git commit -qm t ) >/dev/null 2>&1
    ck "a path outside the lease is refused" "$(run review codex/outside)" 3

    ( cd "$ws" && git checkout -q main && git checkout -qb codex/noentry \
      && mkdir -p Cadence/iOS && printf 'x\n' > Cadence/iOS/iOSTaskRowA.swift && git add -A && git commit -qm t ) >/dev/null 2>&1
    ck "code with no inbox entry is refused" "$(run review codex/noentry)" 3

    ( cd "$ws" && git checkout -q main && git checkout -qb codex/clash \
      && mkdir -p Cadence/iOS && printf 'x\n' > Cadence/iOS/iOSTaskRowB.swift \
      && printf -- '- [T-9001] **x**\n' > docs/CODEX_LEDGER_INBOX.md \
      && printf -- '- [T-9001] **already filed**\n' >> docs/TODO.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ck "an id the ledger already has is refused" "$(run review codex/clash)" 3
    # T-1800. The exit status is only half of what this refusal has to get right. It fired as
    # designed on T-3003 and T-3004 -- where the coordinator had PRE-FILED the stub and assigned the
    # branch to it, so exit 3 was the expected state of a branch that WAS ready to land -- and both
    # times Codex stopped and asked the coordinator, because the message named the hazard and no way
    # out. The check is untouched; the words are what changed, so the words are what is asserted.
    msg=$( cd "$ws" && sh ./scripts/codex-land.sh review codex/clash 2>&1 >/dev/null )
    case "$msg" in *"REPLACE THE STUB BODY IN PLACE"*) got=yes ;; *) got="$msg" ;; esac
    ck "...and the clash refusal names the stub-replace landing path" "$got" yes

    ( cd "$ws" && git checkout -q main && git checkout -qb codex/good \
      && mkdir -p Cadence/iOS && printf 'x\n' > Cadence/iOS/iOSTaskRowC.swift \
      && printf -- '- [T-9002] **new**\n' > docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ck "a branch inside the lease with an entry passes" "$(run review codex/good)" 0

    # T-1428. The check above passes even with pathname expansion left on, because the fixture's
    # lease glob matched nothing on disk and so stayed a pattern. This one is the real shape: a
    # file matching the glob is ALREADY committed (iOSTaskRowExisting.swift), so `for pat in $lease`
    # expands the lease line into that one literal name -- and a NEW sibling under the same glob
    # falls outside its own lease. Existing files keep passing, which is why nothing noticed until
    # Codex's first branch added a file. Without `set -f` at the top this returns 3, not 0.
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/newsibling \
      && mkdir -p Cadence/iOS && printf 'x\n' > Cadence/iOS/iOSTaskRowNew.swift \
      && printf -- '- [T-9003] **new sibling**\n' > docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    # ...and the review must run from `main`, which is where the coordinator actually stands. With
    # the branch checked out the new file is on disk, so the lease glob expands to include IT too
    # and the bug hides -- the first version of this check was green against the mutation for
    # exactly that reason. Reviewing a branch means reviewing files you do NOT have.
    ( cd "$ws" && git checkout -q main ) >/dev/null 2>&1
    ck "a NEW file under a glob that also matches an existing file passes" "$(run review codex/newsibling)" 0

    # T-1490, placed before the empty-lease fixture, which rewrites the lease in place. The inbox is
    # append-only, so an id the coordinator has already folded into the ledger stays in it forever
    # -- and at that moment a formal entry for it exists, which is precisely what the clash check
    # looks for. Reading the whole inbox therefore refuses a branch for the protocol having worked.
    # Reproducing it needs the id present at the MERGE-BASE, not added by the branch, which is why
    # this fixture commits to main first. Without the `git diff base..ref` fix this returns 3.
    ( cd "$ws" && git checkout -q main \
      && printf -- '- [T-9100] **already folded**\n' > docs/CODEX_LEDGER_INBOX.md \
      && printf -- '- [T-9100] **folded by the coordinator**\n' >> docs/TODO.md \
      && git add -A && git commit -qm folded ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -qb codex/folded \
      && mkdir -p Cadence/iOS && printf 'x\n' > Cadence/iOS/iOSTaskRowD.swift \
      && printf -- '- [T-9101] **new work**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ck "an inbox id the coordinator already folded is not a clash" "$(run review codex/folded)" 0

    # T-1930, and the ONE-CANDIDATE trap is the reason there are three fixtures here rather than
    # one. A selftest holding only a fully-landed branch passes with the whole per-file reading
    # deleted: delete it and that branch still exits non-zero, because the id clash fires on it
    # too. What the defect was is that the two states are INDISTINGUISHABLE, so the spent branch is
    # pinned beside a genuinely pending one and the two reports are asserted to DIFFER.
    run_out() { ( cd "$ws" && sh ./scripts/codex-land.sh "$@" 2>&1 ); }

    # (a) spent: the coordinator landed the code AND published the inbox entry (T-1800's rule), then
    #     filed the id -- so the clash fires for the one reason that means the work is already in.
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/landed \
      && printf 'typography\n' > Cadence/iOS/iOSTaskRowE.swift \
      && printf -- '- [T-9200] **landed work**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main \
      && printf 'typography\n' > Cadence/iOS/iOSTaskRowE.swift \
      && printf -- '- [T-9200] **landed work**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && printf -- '- [T-9200] **folded by the coordinator**\n' >> docs/TODO.md \
      && git add -A && git commit -qm landed ) >/dev/null 2>&1
    ck "a branch whose every file is already in main is SPENT, not blocked" "$(run review codex/landed)" 5
    spent_out=$(run_out review codex/landed)

    # (b) the control: same shape, same lease, same inbox vocabulary, nothing landed.
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/pending \
      && printf 'typography\n' > Cadence/iOS/iOSTaskRowF.swift \
      && printf -- '- [T-9201] **pending work**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main ) >/dev/null 2>&1
    ck "a genuinely pending branch is NOT reported as landed" "$(run review codex/pending)" 0
    pending_out=$(run_out review codex/pending)

    ck "the spent and the pending branch do not get the same report" \
       "$( [ "$spent_out" != "$pending_out" ] && echo differ || echo same )" differ
    ck "the spent branch's report names the state" \
       "$(printf '%s' "$spent_out" | grep -c 'CODEX-BRANCH-ALREADY-LANDED')" 1
    ck "the pending branch's report does NOT" \
       "$(printf '%s' "$pending_out" | grep -c 'CODEX-BRANCH-ALREADY-LANDED')" 0
    ck "every named file carries its own verdict against main" \
       "$(printf '%s' "$pending_out" | grep -c 'NOT in main')" 2

    # (c) main is AHEAD of the branch on a file the branch changed -- two of the 31 measured files
    #     were this. The bytes differ, so a pure `git diff --quiet` reading calls it pending and the
    #     branch reads as blocked; the blob is in main's history, so it is landed.
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/ahead \
      && printf 'v1\n' > Cadence/iOS/iOSTaskRowG.swift \
      && printf -- '- [T-9202] **work main moved past**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main \
      && printf 'v1\n' > Cadence/iOS/iOSTaskRowG.swift \
      && printf -- '- [T-9202] **work main moved past**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm landed-ahead \
      && printf 'v1\nv2\n' > Cadence/iOS/iOSTaskRowG.swift \
      && git add -A && git commit -qm moved-past ) >/dev/null 2>&1
    ck "a file main has moved PAST still counts as landed, not as pending" "$(run review codex/ahead)" 5

    # (d) the shape the live branch was in once main moved on: all the CODE landed, the branch's
    #     own inbox entries never published, the id filed -- so the clash fires and the branch is
    #     still not "fully landed". It must not read as 31 files of pending work either.
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/inboxonly \
      && printf 'done\n' > Cadence/iOS/iOSTaskRowH.swift \
      && printf -- '- [T-9203] **code landed, entry not published**\n' >> docs/CODEX_LEDGER_INBOX.md \
      && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main \
      && printf 'done\n' > Cadence/iOS/iOSTaskRowH.swift \
      && printf -- '- [T-9203] **folded by the coordinator**\n' >> docs/TODO.md \
      && git add -A && git commit -qm landed-code-only ) >/dev/null 2>&1
    inboxonly_out=$(run_out review codex/inboxonly)
    ck "a branch whose only unlanded path is the inbox still refuses on the clash" \
       "$(run review codex/inboxonly)" 3
    ck "...and SAYS the code landed, instead of reading as pending work" \
       "$(printf '%s' "$inboxonly_out" | grep -c 'CODEX-ONLY-THE-INBOX-IS-UNLANDED')" 1

    ( cd "$ws" && git checkout -q main \
      && printf '# x\n\n```lease\n```\n' > docs/CODEX_WORKTREE.md \
      && git add -A && git commit -qm empty-lease ) >/dev/null 2>&1
    ck "an empty lease refuses rather than allowing all" "$(run review codex/good)" 4

    # ---- T-6400: is the path HELD, or only LISTED? -------------------------------------------
    # The block answered "listed" for three years of grants and nobody noticed, because a spent
    # grant and a live one are the same line. Six fixtures, because the ONE-CANDIDATE trap applies
    # here with full force: a selftest holding only a spent grant passes with the entire liveness
    # reading deleted -- `held` would print SPENT for everything and exit 0, which is exactly the
    # defect. The live grant beside it, and the assertion that the two reports DIFFER, is what
    # makes any of this evidence.
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/landedwork \
      && printf 'done\n' > Cadence/iOS/iOSHeldDone.swift && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main \
      && printf 'done\n' > Cadence/iOS/iOSHeldDone.swift && git add -A && git commit -qm landed ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -qb codex/livework \
      && printf 'wip\n' > Cadence/iOS/iOSHeldLive.swift && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main && git checkout -qb codex/idlework \
      && printf 'elsewhere\n' > Cadence/iOS/iOSTaskRowZ.swift && git add -A && git commit -qm t ) >/dev/null 2>&1
    ( cd "$ws" && git checkout -q main ) >/dev/null 2>&1
    relsha=$( cd "$ws" && git rev-parse HEAD 2>/dev/null )
    livesha=$( cd "$ws" && git rev-parse codex/livework 2>/dev/null )
    [ -n "$relsha" ] && [ -n "$livesha" ] \
      || { setup_fail "resolving the fixture's main and codex/livework for spent= values" ""; return 2; }

    held_doc() {   # $1 = extra lease line(s), $2 = extra grant row(s)
        { printf '# x\n\n```lease\n'
          printf 'Cadence/iOS/iOSHeldDone*.swift\nCadence/iOS/iOSHeldLive*.swift\nCadence/iOS/iOSHeldIdle*.swift\n'
          printf 'Cadence/iOS/iOSHeldRel*.swift\nCadence/iOS/iOSHeldBogus*.swift\nCadence/iOS/iOSHeldGone*.swift\n'
          printf 'Cadence/iOS/iOSHeldUnl*.swift\n'
          [ -n "$1" ] && printf '%s\n' "$1"
          printf '```\n\n```lease-grants\n'
          printf 'Cadence/iOS/iOSHeldDone*.swift   branch=codex/landedwork  granted=2026-10-20  grant=aaaaaaa\n'
          printf 'Cadence/iOS/iOSHeldLive*.swift   branch=codex/livework    granted=2026-10-20  grant=bbbbbbb\n'
          printf 'Cadence/iOS/iOSHeldIdle*.swift   branch=codex/idlework    granted=2026-10-20  grant=ccccccc\n'
          printf 'Cadence/iOS/iOSHeldRel*.swift    branch=-                 granted=2026-10-20  grant=ddddddd  spent=%s\n' "$relsha"
          printf 'Cadence/iOS/iOSHeldBogus*.swift  branch=-                 granted=2026-10-20  grant=eeeeeee  spent=0000000\n'
          printf 'Cadence/iOS/iOSHeldUnl*.swift    branch=-                 granted=2026-10-20  grant=5555555  spent=%s\n' "$livesha"
          printf 'Cadence/iOS/iOSHeldGone*.swift   branch=codex/neverwas    granted=2026-10-20  grant=fffffff\n'
          [ -n "$2" ] && printf '%s\n' "$2"
          printf '```\n'
        } > "$ws/docs/CODEX_WORKTREE.md"
    }
    held_doc "" ""

    ck "a path whose grant branch landed is SPENT, not fenced" \
       "$(run held Cadence/iOS/iOSHeldDone1.swift)" 0
    spent_held=$(run_out held Cadence/iOS/iOSHeldDone1.swift)
    ck "a path a live branch is still writing is HELD" \
       "$(run held Cadence/iOS/iOSHeldLive1.swift)" 3
    live_held=$(run_out held Cadence/iOS/iOSHeldLive1.swift)
    # The pair, not either alone. Both paths are listed in the same block, under the same kind of
    # glob, with grant rows that differ only in which branch they name.
    ck "the spent grant and the live grant do not get the same answer" \
       "$( [ "$spent_held" != "$live_held" ] && echo differ || echo same )" differ
    ck "...and the spent one says SPENT" "$(printf '%s' "$spent_held" | grep -c 'SPENT')" 1
    ck "...and the live one says HELD" "$(printf '%s' "$live_held" | grep -c '  HELD  ')" 1

    # A grant made before the job exists is a hold on a file nobody is writing: the 2026-10-24
    # iOSSearchView.swift case, which cost an agent its finished work. It is neither held nor
    # spent and the script must not pretend to know which.
    ck "a branch that has written nothing under its pattern is RESERVED, not SPENT" \
       "$(run held Cadence/iOS/iOSHeldIdle1.swift)" 4

    ck "a recorded release that is an ancestor of main spends the grant" \
       "$(run held Cadence/iOS/iOSHeldRel1.swift)" 0
    # Non-vacuity on the one field that can free a path. A release recorded against a commit this
    # repository does not have is not a release, and reading it as one would release a held path
    # on the strength of a typo.
    ck "a spent= naming no commit is NOT read as a release" \
       "$(run held Cadence/iOS/iOSHeldBogus1.swift)" 3
    # The shape a release record actually rots into: a real sha that is the BRANCH tip rather than
    # the landing commit. It resolves, so a resolve-only check passes it, and it frees a path whose
    # work never reached main.
    ck "a spent= that resolves but never landed is NOT read as a release" \
       "$(run held Cadence/iOS/iOSHeldUnl1.swift)" 3
    ck "a grant whose branch does not resolve stays fenced" \
       "$(run held Cadence/iOS/iOSHeldGone1.swift)" 3
    ck "a path no pattern matches is UNFENCED" \
       "$(run held Cadence/iOS/iOSNothingMatches.swift)" 0
    ck "held with no path refuses rather than reporting nothing held" "$(run held)" 2

    # The half that keeps this from rotting again: the fence and the grant record must agree, in
    # both directions, or nothing reads either of them. A pattern with no row is a path nothing
    # can expire -- which is precisely how the block got to 179 lines of mostly-spent grants.
    held_doc "Cadence/iOS/iOSHeldOrphan*.swift" ""
    ck "a fenced pattern with no grant row refuses" "$(run lease)" 4
    ck "...and review refuses on it too, where it actually blocks work" "$(run review codex/livework)" 4
    orphan_out=$(run_out lease)
    case "$orphan_out" in *"CODEX-LEASE-UNRECORDED"*) got=yes ;; *) got="$orphan_out" ;; esac
    ck "...and the refusal names the path with no branch recorded" "$got" yes

    held_doc "" "Cadence/iOS/iOSHeldStray*.swift  branch=codex/livework  granted=2026-10-20  grant=9999999"
    ck "a grant row for a pattern that is not fenced refuses" "$(run lease)" 4

    held_doc "" "Cadence/iOS/iOSHeldDone*.swift  branch=codex/livework  granted=2026-10-20  grant=8888888"
    ck "two rows for one pattern refuses" "$(run lease)" 4

    held_doc "Cadence/iOS/iOSHeldNodate*.swift" "Cadence/iOS/iOSHeldNodate*.swift  branch=codex/livework  grant=7777777"
    ck "a grant row with no granted= date refuses" "$(run lease)" 4

    held_doc "Cadence/iOS/iOSHeldAnon*.swift" "Cadence/iOS/iOSHeldAnon*.swift  branch=-  granted=2026-10-20  grant=6666666"
    ck "a row naming no branch and no release refuses" "$(run lease)" 4

    held_doc "" ""
    ck "the whole block can be read held-or-spent in one pass" "$(run lease --status)" 0
    status_out=$(run_out lease --status)
    ck "...and that pass counts the live grant" \
       "$(printf '%s' "$status_out" | grep -c '^lease: 4 held, 1 reserved, 2 spent\.$')" 1

    printf '\nchecks: %d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ] || return 1
    printf 'SELFTEST PASSED\n'
}

case "${1:-}" in
    review)   shift; cmd_review "$@" ;;
    lease)    shift; cmd_lease "$@" ;;
    held)     shift; cmd_held "$@" ;;
    inbox)    cmd_inbox ;;
    selftest) cmd_selftest ;;
    -h|--help|"") sed -n '2,8p' "$0" ;;
    *) printf 'REFUSED (CODEX-LAND-UNKNOWN-MODE): %s\n' "$1" >&2; exit 2 ;;
esac
