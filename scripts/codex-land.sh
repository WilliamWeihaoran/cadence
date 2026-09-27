#!/bin/sh
# Review a Codex branch before the coordinator lands it (docs/CODEX_WORKTREE.md).
#
#   ./scripts/codex-land.sh review <ref>   # what would land, and every refusal that fires
#   ./scripts/codex-land.sh lease          # the lease, as this script parses it
#   ./scripts/codex-land.sh inbox          # ids currently pending in the inbox
#   ./scripts/codex-land.sh selftest       # prove the refusals still fire
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
    printf '%s\n' "$lease"
    printf 'lease: %d pattern(s) from %s (plus %s, always allowed).\n' "$n" "$DOC" "$INBOX"
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
    nfiles=$(printf '%s\n' "$files" | grep -c '^' )

    # NON-VACUITY, the shape every guard here carries (T-1282): a review that read nothing must
    # refuse rather than report a clean branch. An empty diff and a broken ref look the same.
    if [ "$ncommits" -eq 0 ] || [ -z "$files" ]; then
        printf 'REFUSED (CODEX-REVIEW-VACUOUS): %s adds %d commit(s) and %d changed file(s) over main.\n  A branch with nothing on it reads exactly like a clean review; it is not one.\n' \
            "$ref" "$ncommits" "$nfiles" >&2
        return 4
    fi

    lease=$(read_lease)
    [ -n "$lease" ] || { printf 'REFUSED (CODEX-LEASE-EMPTY): no lease to check against.\n' >&2; return 4; }

    rc=0
    printf 'codex-land: %s is %d commit(s), %d file(s) over %s\n\n' "$ref" "$ncommits" "$nfiles" "$(echo "$base" | cut -c1-8)"

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
        newids=$(git show "$ref:$INBOX" 2>/dev/null | grep -oE '^- \[T-[0-9]+\]' | sed 's/^- \[//;s/\]$//' | sort -u)
        for id in $newids; do
            if grep -qE "^- \[$id\]" "$TODO" "$DONE" 2>/dev/null; then
                printf 'REFUSED (CODEX-INBOX-ID-CLASH): %s already has a formal entry in the ledger.\n  Folding this in would give one id two entries, which is the shape T-1356 is about.\n' "$id" >&2
                rc=3
            fi
        done
    fi

    # 5. behind main -- a report, not a refusal: landing rebases anyway
    behind=$(git rev-list --count "$ref"..main 2>/dev/null || echo 0)
    [ "$behind" -gt 0 ] && printf 'note: %s is %d commit(s) behind main; the coordinator rebases at landing.\n' "$ref" "$behind"

    printf '\nfiles:\n'
    for f in $files; do printf '  %s\n' "$f"; done
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
      && printf '# x\n\n```lease\nCadence/iOS/iOSTaskRow*.swift\n```\n' > docs/CODEX_WORKTREE.md \
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

    ( cd "$ws" && git checkout -q main \
      && printf '# x\n\n```lease\n```\n' > docs/CODEX_WORKTREE.md \
      && git add -A && git commit -qm empty-lease ) >/dev/null 2>&1
    ck "an empty lease refuses rather than allowing all" "$(run review codex/good)" 4

    printf '\nchecks: %d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ] || return 1
    printf 'SELFTEST PASSED\n'
}

case "${1:-}" in
    review)   shift; cmd_review "$@" ;;
    lease)    cmd_lease ;;
    inbox)    cmd_inbox ;;
    selftest) cmd_selftest ;;
    -h|--help|"") sed -n '2,8p' "$0" ;;
    *) printf 'REFUSED (CODEX-LAND-UNKNOWN-MODE): %s\n' "$1" >&2; exit 2 ;;
esac
