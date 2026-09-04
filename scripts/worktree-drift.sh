#!/bin/zsh
# Does this checkout still hold the code HEAD says it does? (T-975)
#
#   ./scripts/worktree-drift.sh check      # exit 3 while any tracked file is behind HEAD
#   ./scripts/worktree-drift.sh report     # the same reading, always exit 0
#   ./scripts/worktree-drift.sh repair     # restore the stale COPIES from HEAD (never the edits)
#   ./scripts/worktree-drift.sh ids <path> # the comm -23 on `- [T-n]` id sets, on its own
#   ./scripts/worktree-drift.sh base <path> [<rev>]   # the reading for ONE path, machine-readable
#   ./scripts/worktree-drift.sh selftest
#
# WHY THIS EXISTS
#
# `agent-commit.sh` commits through a private index via `commit-tree`, deliberately and correctly:
# a landed commit never writes the shared checkout, so it cannot clobber a sibling mid-edit. The
# cost is that **the shared checkout drifts behind HEAD and nothing announces it.** Every agent
# that then reconstructs a file from the worktree instead of `git show HEAD:<path>` propagates the
# stale copy forward, and an integration run started against that tree tests code that is not HEAD.
#
# Measured four times between 2026-09-04 and 2026-09-05. The worst instance, after Batch V: the
# worktree's `docs/TODO.md` was missing five ticket ids HEAD had (T-954, T-955, T-956, T-959,
# T-965) and its `CadenceBuildInvocationHygieneTests.swift` was 101 lines behind the fix already
# committed for T-709. An integration run had been launched against that tree and was stopped
# rather than trusted. Reproduced 2026-09-05 against this repository's own history, by checking
# `0185752^`'s copy of that file into a clone whose HEAD carried the fix.
#
# It is nobody's bug and nothing reports it, because **`git status` prints ` M <path>` for a stale
# copy and for real in-flight work, character for character.** That is the whole failure: the one
# instrument anybody looks at cannot tell the two apart. The hand practice that caught all four
# instances was `comm -23` on the ticket-id sets; this generalises it from ids to lines, and from
# `docs/TODO.md` to any tracked text file.
#
# HOW IT TELLS THEM APART
#
# Set membership over whole lines, not `git diff`: an agent's own edit and a sibling's landed
# commit sit in one hunk once they are within three lines of each other, and hunk-shaped reasoning
# has already taken a sibling's work once here (see `declined_lines` in agent-commit.sh).
#
# For a path whose worktree content differs from HEAD, walk that path's revisions newest-first and
# find the newest revision R whose every (non-trivial) line the worktree still contains -- the
# revision this working copy is BUILT ON.
#
#   * R is the revision HEAD's own blob came from  ->  in-flight work. Not reported, not refused.
#     This is the ordinary case and it costs one comparison: if the worktree contains every line
#     HEAD has, no walk happens at all.
#   * R is older than that                         ->  BEHIND HEAD. Commits have landed on this
#     path that this copy has never seen, and anything reconstructed from it reverts them.
#   * no R within the walk                         ->  cannot tell. The agent has deleted enough
#     that no revision is contained; treated as in-flight, never refused. A guard that guesses
#     here would refuse ordinary work, which is the one thing it must not do.
#
# WHERE THIS IS ASKED FROM
#
#   `xcb.sh test`         gates a whole tree before an integration run READS it (T-975).
#   `agent-commit.sh`     asks `base <path> <sha>` about each bare `<path>` before it WRITES that
#                         path into history (T-982). Detecting drift at the reader is the right
#                         gate for reading, but drift is CREATED one step earlier: a bare `<path>`
#                         whose copy is behind HEAD puts the stale bytes in a commit, and every
#                         later reader inherits them from HEAD itself, where no drift check looks.
#                         The `<path>=<content-file>` form is deliberately NOT checked there --
#                         rebuilding on `git show HEAD:<path>` is the prescribed repair for this
#                         very drift, and refusing the repair would be the worst outcome available.
#
# THE BLIND SPOT, AND WHY IT STAYS (T-984)
#
# A copy that is behind HEAD *and* has lines removed contains no revision of the path, so it reads
# `cannot tell` and is never refused. That is the one shape this reading cannot see, and it cannot
# be narrowed by looking harder at the content, because there is nothing there to look at:
#
#   Let V be an old revision and let HEAD be V plus one added line `a`. Let `d` be any line of V.
#     the stale case  an agent holding V deletes d.              Worktree = V - {d}.
#     the work case   an agent holding HEAD deletes a and d.     Worktree = V - {d}.
#   The two worktrees are the same bytes. One must be refused and the other must not, and no
#   function of the worktree and the history can separate them. Every "narrower" rule proposed for
#   this bucket -- best-overlap ratio, longest contained prefix, thresholded containment -- is such
#   a function, so each one either refuses the work case or passes the stale case.
#
# The only separating evidence is outside the content, and the obvious candidate does not work
# either. File mtime older than the commit that last touched the path would be real evidence of a
# copy written before that commit landed -- but the measured T-975 failure is an agent that
# RECONSTRUCTS from the stale copy, writing a fresh file with stale bytes, so mtime is new and the
# check is blind exactly where it was aimed. It also false-positives on the `git archive HEAD`
# build trees the runbook tells agents to make. A guard that misses its own target case and fires
# on the prescribed workflow is worse than the gap.
#
# So the bucket stays open, and the cost is bounded rather than unbounded, in both callers:
#   * `report`/`check` now NAME the cannot-tell paths instead of calling them in-flight, so a
#     reader sees which files nothing examined.
#   * in `agent-commit.sh` this shape is, by construction, a commit that drops lines HEAD has --
#     which is what REMOVES-HEAD-LINES already gates on a declared exact count. Being behind and
#     carrying deletions is not un-guarded there; it is guarded by the count instead of by the
#     diagnosis. Selftest mode 3(f) below pins the non-refusal so a later narrowing has to come
#     here and argue with the paragraph above rather than quietly flip it.
#
# Two shapes of behind, and they are repaired differently, so they are named differently:
#
#   stale copy  the worktree blob IS R's blob, byte for byte. Nothing local is at risk and
#               `repair` restores it from HEAD.
#   stale base  R's lines plus local edits on top. `repair` will NOT touch it -- restoring would
#               throw away the agent's own work. Rebase the edit onto `git show HEAD:<path>`.
#
# WHAT IT REFUSES
#
#   WORKTREE-BEHIND-HEAD  a tracked file is built on a revision older than HEAD's. Set
#                         CADENCE_ALLOW_DRIFTED_TREE=1 to proceed anyway (it then reports and
#                         exits 0), which is the right call only when you know what drifted.
#   NOT-REPO-ROOT         run from somewhere other than the top of the checkout
#
# WHAT IT DELIBERATELY DOES NOT REFUSE
#
#   * an untracked file, or one HEAD does not have -- there is no older revision to be behind
#   * a tracked file deleted from the worktree -- a `git rm` in flight looks exactly like this
#   * a binary file -- line sets say nothing about one; `git diff --numstat` reports `-` and it is
#     skipped by name in the output rather than silently
#   * a file whose lines are only REORDERED or duplicated (Cadence.xcodeproj/project.pbxproj does
#     this constantly): same line set, so it is on the current base by construction

set -uo pipefail

SCRIPT_PATH="${0:A}"
say() { print -r -- "$@" }
refuse() { print -r -- "REFUSED ($1): $2" >&2; exit 3 }

TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"

# How far back a path's history is walked looking for the revision the worktree is built on. A
# copy older than this reads as "cannot tell" rather than as behind, which is the safe direction.
WALK_DEPTH="${CADENCE_DRIFT_DEPTH:-40}"

# `/usr/bin/git` is an xcrun shim and xcrun refuses to run inside an App Sandbox, so every git call
# fails with that on stderr and nothing else -- which reads like a broken repository. Same probe
# agent-commit.sh uses, and for the same reason: this script is run from a sandboxed test host.
if ! git --version >/dev/null 2>&1; then
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin; do
        [[ -x "$_candidate/git" ]] || continue
        "$_candidate/git" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; break
    done
fi

usage() {
    say "usage: ./scripts/worktree-drift.sh check|report|repair|selftest"
    say "       ./scripts/worktree-drift.sh ids <path>"
    say "       ./scripts/worktree-drift.sh base <path> [<rev>]   # one path, machine-readable"
}

# A line that is blank, or nothing but punctuation and braces, carries no meaning on its own: it
# appears in every revision of every file and would make any two versions look contained in each
# other. Same filter, same reason, as agent-commit.sh's declined_lines.
significant() {
    awk '{ t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
           if (length(t) >= 4 && t !~ /^[][(){}.,;:+*&|<>=!?-]+$/) print }' | sort -u
}

# The practice this script generalises, kept callable on its own because it is the one form a
# human reads without thinking: ids HEAD has that the file in front of you does not.
ledger_ids() { grep -oE '^- \[T-[0-9]+\]' 2>/dev/null | sed 's/^- \[//; s/\]$//' | sort -u }

cmd_ids() {
    (( $# )) || refuse BAD-OPTION "ids needs a path"
    local target=$1
    git cat-file -e "HEAD:$target" 2>/dev/null || refuse UNKNOWN-PATH "$target is not in HEAD"
    local gone
    gone=$(comm -23 <(git show "HEAD:$target" | ledger_ids) <(ledger_ids < "$target" 2>/dev/null))
    if [[ -z "$gone" ]]; then
        say "$target: every ticket id HEAD has is in the worktree copy too."
        return 0
    fi
    say "$target is missing $(print -r -- "$gone" | grep -c .) ticket id(s) HEAD has:"
    print -r -- "$gone" | sed 's/^/  /'
    return 3
}

# --- the reading, one path at a time -------------------------------------------
#
# Factored out of the tree walk because there are two callers and they ask different questions
# (T-982). `check` asks about a whole tree that is about to be READ from. `agent-commit.sh` asks
# about ONE path that is about to be WRITTEN into history -- which is where drift is *created*,
# one step before the gate that detects it. Both must be the same reading, so it is one function.
#
# Sets, for $1 at revision $2, using $3 as scratch:
#
#   state_verdict  matches | inflight | cannot-tell | behind | skip
#   state_kind     "stale copy" | "stale base"           (behind only)
#   state_base     the revision this copy is built on    (behind only)
#   state_detail   a sentence; for skip, the reason
#
# `cannot-tell` used to be folded into `inflight`, and folding it there is still what it MEANS --
# it is never refused. It is named separately because it is the check's one blind spot and a
# reader deserves to see it rather than be told "in-flight" about a file nothing examined. See
# THE BLIND SPOT below.

typeset -g state_verdict state_kind state_base state_detail

read_path_state() {
    local p=$1 headref=$2 scratch=$3
    state_verdict=""; state_kind=""; state_base=""; state_detail=""
    local headlabel="${headref[1,8]}"

    git cat-file -e "$headref:$p" 2>/dev/null \
        || { state_verdict=skip; state_detail="not in $headlabel -- nothing to be behind"; return 0 }
    [[ -f "$p" ]] \
        || { state_verdict=skip; state_detail="absent from the worktree -- a deletion in flight looks like this"; return 0 }
    # `-` in either numstat column is git's own word for "binary".
    if [[ "$(git diff --numstat "$headref" -- "$p" 2>/dev/null | awk '{print $1}')" == "-" ]]; then
        state_verdict=skip; state_detail="binary"; return 0
    fi

    local wt_lines="$scratch/wt" head_lines="$scratch/head" rev_lines="$scratch/rev"
    significant < "$p" > "$wt_lines"
    git show "$headref:$p" | significant > "$head_lines"

    # The cheap question first, and the one that answers almost every path: does this copy already
    # contain everything HEAD has? Then it is built on HEAD and no walk is needed.
    local missing_lines; missing_lines=$(comm -23 "$head_lines" "$wt_lines")
    if [[ -z "$missing_lines" ]]; then
        state_verdict=inflight; state_detail="contains every line $headlabel has"; return 0
    fi

    local newest rev base=""
    newest=$(git rev-list -1 "$headref" -- "$p" 2>/dev/null)
    for rev in ${(f)"$(git rev-list -n "$WALK_DEPTH" "$headref" -- "$p" 2>/dev/null)"}; do
        [[ -n "$rev" ]] || continue
        git show "$rev:$p" 2>/dev/null | significant > "$rev_lines"
        [[ -s "$rev_lines" ]] || continue
        if [[ -z "$(comm -23 "$rev_lines" "$wt_lines")" ]]; then base="$rev"; break; fi
    done

    if [[ -z "$base" ]]; then
        state_verdict=cannot-tell
        state_detail="no revision in the last $WALK_DEPTH on this path is wholly contained in it, so there is nothing to call it built on (T-984)"
        return 0
    fi
    if [[ "$base" == "$newest" ]]; then
        state_verdict=inflight; state_detail="built on ${newest[1,8]}, the newest revision of this path"; return 0
    fi

    state_verdict=behind; state_base="$base"
    if [[ "$(git hash-object -- "$p")" == "$(git rev-parse "$base:$p" 2>/dev/null)" ]]; then
        state_kind="stale copy"
    else
        state_kind="stale base"
    fi
    state_detail="built on ${base[1,8]} ($(git log -1 --format=%s "$base" 2>/dev/null | cut -c1-58)); $(git rev-list --count "$base..$headref" -- "$p" 2>/dev/null) commit(s) to this path since; $(print -r -- "$missing_lines" | grep -c .) line(s) $headlabel has are not in it"
    return 0
}

# --- the reading, over a whole tree ---------------------------------------------
#
# Fills the parallel arrays `behind_paths` / `behind_kind` / `behind_detail`, plus `skipped`,
# `inflight` and `cannot_tell`.

typeset -ga behind_paths behind_kind behind_detail skipped inflight cannot_tell

read_tree_state() {
    behind_paths=(); behind_kind=(); behind_detail=(); skipped=(); inflight=(); cannot_tell=()

    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || refuse NOT-REPO-ROOT "not inside a git checkout"
    [[ "${PWD:A}" == "${root:A}" ]] || refuse NOT-REPO-ROOT "run from $root, not $PWD (paths are repo-relative)"
    git rev-parse HEAD >/dev/null 2>&1 || refuse NO-HEAD "no HEAD to compare against"

    local scratch; scratch=$(mktemp -d "${TMP_BASE}cadence-drift-XXXXXX") || refuse SCRATCH "cannot make a scratch directory"

    # `git diff HEAD` and not `git status`: the shared index is another agent's business, and a
    # path staged-but-identical to HEAD is not drift.
    local -a changed
    changed=(${(f)"$(git diff --name-only HEAD 2>/dev/null)"})

    local p
    for p in "${changed[@]}"; do
        [[ -n "$p" ]] || continue
        read_path_state "$p" HEAD "$scratch"
        case "$state_verdict" in
            skip)        skipped+=("$p ($state_detail)") ;;
            cannot-tell) cannot_tell+=("$p") ;;
            behind)      behind_paths+=("$p"); behind_kind+=("$state_kind"); behind_detail+=("$state_detail") ;;
            *)           inflight+=("$p") ;;
        esac
    done
    rm -rf "$scratch"
}

print_reading() {
    local i p
    if (( ${#behind_paths} == 0 )); then
        say "worktree matches HEAD: ${#inflight} path(s) changed and every one is built on HEAD."
    else
        say "WORKTREE BEHIND HEAD -- ${#behind_paths} tracked file(s) hold code HEAD has moved past:"
        for (( i = 1; i <= ${#behind_paths}; i++ )); do
            p="${behind_paths[i]}"
            say "  $p  [${behind_kind[i]}]"
            say "      ${behind_detail[i]}"
            # Ids, not just a line count. `docs/TODO.md` loses whole tickets inside a number large
            # enough to skim past, and an id is the thing somebody can act on.
            local gone
            gone=$(comm -23 <(git show "HEAD:$p" | ledger_ids) <(ledger_ids < "$p" 2>/dev/null))
            [[ -n "$gone" ]] && say "      ticket ids HEAD has and this copy does not: $(print -r -- "$gone" | tr '\n' ' ')"
        done
    fi
    (( ${#inflight} )) && say "in-flight edits (built on HEAD, left alone): ${(j:, :)inflight}"
    if (( ${#cannot_tell} )); then
        say "cannot tell, so treated as in-flight and NOT refused: ${(j:, :)cannot_tell}"
        say "  These have lines removed as well as lines missing, so no revision of the path is"
        say "  contained in them and there is nothing to call them built on. A deliberate deletion"
        say "  and a stale copy with a deletion on top are the same bytes; see T-984 in this file."
    fi
    (( ${#skipped} )) && { say "not compared:"; local s; for s in "${skipped[@]}"; do say "  $s"; done }
    return 0
}

# The same reading about ONE path, against a caller-chosen revision, in a form a script can read.
# `agent-commit.sh` needs both (T-982): one path, because it must refuse the path being committed
# and not a sibling's unrelated drift; and a caller-chosen revision, because every check in that
# script answers a question about the ONE sha it captured up front, and re-resolving `HEAD` here
# would ask about a different commit than the guards either side of it (T-974).
#
# One tab-separated line on stdout -- verdict, kind, base, detail -- and exit 3 iff behind.
cmd_base() {
    (( $# )) || refuse BAD-OPTION "base needs a path"
    local target=$1 headref=${2:-HEAD}
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || refuse NOT-REPO-ROOT "not inside a git checkout"
    [[ "${PWD:A}" == "${root:A}" ]] || refuse NOT-REPO-ROOT "run from $root, not $PWD (paths are repo-relative)"
    git rev-parse --verify "$headref" >/dev/null 2>&1 || refuse NO-HEAD "no such revision: $headref"
    local scratch; scratch=$(mktemp -d "${TMP_BASE}cadence-drift-XXXXXX") || refuse SCRATCH "cannot make a scratch directory"
    read_path_state "$target" "$headref" "$scratch"
    rm -rf "$scratch"
    # `printf`, not `print -r`: `print -r` does not interpret escapes, so `"a\tb"` emits the two
    # characters `\` and `t` and every `cut -f2` downstream silently reads the whole line as
    # field 1 -- a caller that then compares field 2 against "stale copy" gets a quiet no.
    printf '%s\t%s\t%s\t%s\n' "$state_verdict" "${state_kind:--}" "${state_base:--}" "$state_detail"
    [[ "$state_verdict" == behind ]] && return 3
    return 0
}

cmd_report() { read_tree_state; print_reading; return 0 }

cmd_check() {
    read_tree_state
    print_reading
    (( ${#behind_paths} )) || return 0
    if [[ "${CADENCE_ALLOW_DRIFTED_TREE:-}" == "1" ]]; then
        say ""
        say "CADENCE_ALLOW_DRIFTED_TREE=1 is set, so this is a report and not a refusal."
        return 0
    fi
    say ""
    refuse WORKTREE-BEHIND-HEAD "the paths above are older than HEAD, and a run against them tests code that is not HEAD.
  This is T-975: agent-commit.sh commits through a private index, so a landed commit never writes
  the shared checkout, and \`git status\` shows a stale copy exactly as it shows real work.
  A [stale copy] has nothing local in it:  ./scripts/worktree-drift.sh repair
  A [stale base] has your edits on top of an old one -- do NOT restore it; rebuild the edit on
  \`git show HEAD:<path>\` instead, which is the rule this drift defeats every time it is skipped.
  To run anyway, knowing what drifted: CADENCE_ALLOW_DRIFTED_TREE=1"
}

cmd_repair() {
    read_tree_state
    if (( ${#behind_paths} == 0 )); then say "nothing to repair; every changed path is built on HEAD."; return 0; fi
    local i p restored=0 refused_count=0
    for (( i = 1; i <= ${#behind_paths}; i++ )); do
        p="${behind_paths[i]}"
        if [[ "${behind_kind[i]}" == "stale copy" ]]; then
            git checkout HEAD -- "$p" && { say "restored from HEAD: $p"; (( restored++ )) }
        else
            say "NOT restored: $p [stale base] -- it has local edits on top of an old revision, and"
            say "              restoring would throw them away. Rebuild it on \`git show HEAD:$p\`."
            (( refused_count++ ))
        fi
    done
    say "repaired $restored, left $refused_count for you."
    (( refused_count == 0 )) || return 3
    return 0
}

# --- selftest -----------------------------------------------------------------
#
# A guard nobody exercises is the hollow instrument this repository keeps finding one layer up, so
# every reading below is induced against a real throwaway repository. It builds nothing.
#
# The modes that matter most are the NEGATIVE ones. A drift check that refuses ordinary in-flight
# work would stop the batch dead, and it would do it in the shape everyone is trained to override,
# so the false-positive controls are not decoration: an added-lines edit, a deleted-lines edit, a
# reordered file and an untracked file each have to sail straight through.

cmd_selftest() {
    local -a failures performed
    failures=(); performed=()
    check() {
        local name=$1 ok=$2 detail=${3:-}
        performed+=("$name")
        say "  $( (( ok )) && print -n "ok  " || print -n "FAIL")  $name$( (( ok )) || print -n "  <- $detail")"
        (( ok )) || failures+=("$name")
    }

    say "== worktree-drift.sh selftest =="
    local here="$SCRIPT_PATH"
    local ws; ws=$(mktemp -d "${TMP_BASE}cadence-drift-selftest-XXXXXX")
    local out rc

    # v1 -> v2 on three paths, so there is a real "older revision" to be behind.
    (
        cd "$ws" || exit 1
        git init -q .
        git config user.email selftest@example.com
        git config user.name Selftest
        git config commit.gpgsign false
        print -rl -- "the first line of code" "the second line of code" "the third line of code" > code.swift
        print -rl -- "# Ledger" "" "- [T-101] first ticket, open" "  a body line" > TODO.md
        print -rl -- "alpha entry" "bravo entry" "charlie entry" > ordered.txt
        git add . >/dev/null && git commit -qm v1
        print -rl -- "the first line of code" "the second line of code" "the third line of code" \
                     "the fourth line, added later" "the fifth line, added later" > code.swift
        print -rl -- "# Ledger" "" "- [T-101] first ticket, open" "  a body line" "" \
                     "- [T-102] a ticket a sibling landed" "  another body line" > TODO.md
        git add . >/dev/null && git commit -qm v2
    ) > "$ws.fixture.log" 2>&1 || {
        say "  FAIL  could not build the fixture repository -- git said:"
        sed 's/^/        /' "$ws.fixture.log"
        rm -rf "$ws" "$ws.fixture.log"; return 1
    }
    rm -f "$ws.fixture.log"
    local V1; V1=$( cd "$ws" && git rev-parse --short HEAD^ )

    say ""
    say " mode 0 -- a checkout that matches HEAD is not drift"
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "a clean tree passes" $(( rc == 0 )) "exit $rc: $out"
    check "and says so" $( [[ "$out" == *"worktree matches HEAD"* ]] && print 1 || print 0 ) "$out"

    say ""
    say " mode 1 (WORKTREE-BEHIND-HEAD) -- the stale copy agent-commit.sh leaves behind"
    # Exactly the measured shape: HEAD carries the newer revision, the checkout still holds the
    # older one because no commit ever wrote the checkout.
    ( cd "$ws" && git show HEAD^:code.swift > code.swift )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "a file behind HEAD is refused" \
        $( [[ $rc == 3 && "$out" == *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the path is named" $( [[ "$out" == *code.swift* ]] && print 1 || print 0 ) "$out"
    # The classification is read off the PATH's own line, not off the whole output: the refusal's
    # guidance paragraph names both shapes, so `$out == *"stale base"*` is true either way.
    check "it is called a stale copy, not a stale base" \
        $( [[ "$(print -r -- "$out" | grep 'code\.swift')" == *"[stale copy]"* \
           && "$(print -r -- "$out" | grep 'code\.swift')" != *"[stale base]"* ]] && print 1 || print 0 ) "$out"
    check "and the revision it is built on is named" \
        $( [[ "$out" == *"$V1"* ]] && print 1 || print 0 ) "$out"
    # The control on the whole mode: `git status` says the same thing here as for real work, which
    # is why nothing noticed this four times. If that ever stops being true, this script is moot.
    check "git status cannot tell this from in-flight work" \
        $( [[ "$( cd "$ws" && git status --porcelain -- code.swift )" == " M code.swift" ]] && print 1 || print 0 ) \
        "$( cd "$ws" && git status --porcelain -- code.swift )"

    say ""
    say " mode 1b -- report reads the same and refuses nothing"
    out=$( cd "$ws" && zsh "$here" report 2>&1 ); rc=$?
    check "report exits 0 on the same tree" $(( rc == 0 )) "exit $rc: $out"
    check "and still names the drift" $( [[ "$out" == *"WORKTREE BEHIND HEAD"* && "$out" == *code.swift* ]] && print 1 || print 0 ) "$out"

    say ""
    say " mode 1c -- CADENCE_ALLOW_DRIFTED_TREE=1 downgrades the refusal deliberately"
    out=$( cd "$ws" && CADENCE_ALLOW_DRIFTED_TREE=1 zsh "$here" check 2>&1 ); rc=$?
    check "the override lets it through" $(( rc == 0 )) "exit $rc: $out"
    check "and still says what drifted" $( [[ "$out" == *code.swift* ]] && print 1 || print 0 ) "$out"

    say ""
    say " mode 2 -- repair restores a stale COPY and check then passes"
    out=$( cd "$ws" && zsh "$here" repair 2>&1 ); rc=$?
    check "repair succeeds" $(( rc == 0 )) "exit $rc: $out"
    check "and says which path it restored" $( [[ "$out" == *"restored from HEAD: code.swift"* ]] && print 1 || print 0 ) "$out"
    check "the file is HEAD's content again" \
        $( [[ "$( cd "$ws" && cat code.swift )" == "$( cd "$ws" && git show HEAD:code.swift )" ]] && print 1 || print 0 )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "check passes after the repair" $(( rc == 0 )) "exit $rc: $out"

    say ""
    say " mode 3 -- the FALSE-POSITIVE controls: ordinary in-flight work must sail through"
    # (a) added lines on top of HEAD -- the commonest edit there is.
    ( cd "$ws" && print -r -- "a line this agent is writing now" >> code.swift )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "an edit that ADDS lines to HEAD's content is not drift" $(( rc == 0 )) "exit $rc: $out"
    check "and it is reported as in-flight by name" \
        $( [[ "$out" == *"in-flight edits"*code.swift* ]] && print 1 || print 0 ) "$out"
    # (b) deleted lines -- a mutation, or a deliberate removal. Cannot be told from a stale copy
    #     by line sets alone, so it must be treated as work, never refused.
    ( cd "$ws" && git show HEAD:code.swift | sed '1d' > code.swift )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "an edit that DELETES lines is not refused either" $(( rc == 0 )) "exit $rc: $out"
    # (c) reordered / duplicated lines, the Cadence.xcodeproj/project.pbxproj shape.
    ( cd "$ws" && git checkout -q HEAD -- code.swift && sort -r ordered.txt > ordered.tmp && mv ordered.tmp ordered.txt )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "a file whose lines are only REORDERED is not drift" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws" && git checkout -q HEAD -- ordered.txt )
    # (d) a file HEAD does not have at all.
    ( cd "$ws" && print -r -- "a brand new scratch file" > brand-new.txt )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "an untracked new file is not drift" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws" && rm -f brand-new.txt )
    # (e) a tracked file deleted from the worktree -- a `git rm` in flight.
    ( cd "$ws" && rm -f ordered.txt )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "a deleted tracked file is not refused" $(( rc == 0 )) "exit $rc: $out"
    check "and it is named as not compared, rather than silently ignored" \
        $( [[ "$out" == *"not compared"* && "$out" == *ordered.txt* ]] && print 1 || print 0 ) "$out"
    ( cd "$ws" && git checkout -q HEAD -- ordered.txt )
    # (f) T-984. THE BLIND SPOT, pinned deliberately. An old revision with a line deleted from it
    #     contains no revision of the path, so there is nothing to call it built on and it is not
    #     refused. This is not an oversight to be tightened later: the bytes below are ALSO what an
    #     agent on HEAD produces by deleting the two lines HEAD added plus one more, and that agent
    #     is doing ordinary work. Same file, two histories, opposite verdicts required -- see THE
    #     BLIND SPOT at the top of this file before changing this check to a refusal.
    ( cd "$ws" && git show HEAD^:code.swift | sed '1d' > code.swift )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "an old revision WITH a deletion on top is not refused (T-984, deliberately)" $(( rc == 0 )) "exit $rc: $out"
    check "and it is named as cannot-tell, not quietly called in-flight" \
        $( [[ "$out" == *"cannot tell"*code.swift* && "$out" != *"in-flight edits"*code.swift* ]] && print 1 || print 0 ) "$out"
    check "the refusal it would have got without the deletion is the control" \
        $( [[ "$( cd "$ws" && git show HEAD^:code.swift > code.swift; zsh "$here" check 2>&1 )" == *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) \
        "the same copy without the deletion is not refused either, so mode 3f proves nothing"
    ( cd "$ws" && git checkout -q HEAD -- code.swift )

    say ""
    say " mode 4 -- a STALE BASE (old revision plus local edits) is caught, and NOT auto-restored"
    # The dangerous one: the agent did rebuild the file, but on yesterday's copy. Neither an exact
    # old blob nor a subset of HEAD, so nothing that only compares against HEAD can see it.
    ( cd "$ws" && git show HEAD^:code.swift > code.swift && print -r -- "and the agent's own new line" >> code.swift )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "an old revision with local edits on top is refused" \
        $( [[ $rc == 3 && "$out" == *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and it is called a stale base, not a stale copy" \
        $( [[ "$(print -r -- "$out" | grep 'code\.swift')" == *"[stale base]"* \
           && "$(print -r -- "$out" | grep 'code\.swift')" != *"[stale copy]"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" repair 2>&1 ); rc=$?
    check "repair REFUSES to restore it" \
        $( [[ $rc == 3 && "$out" == *"NOT restored"* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the agent's own line is still there afterwards" \
        $( [[ "$( cd "$ws" && cat code.swift )" == *"the agent's own new line"* ]] && print 1 || print 0 )
    ( cd "$ws" && git checkout -q HEAD -- code.swift )

    say ""
    say " mode 5 -- the ledger is reported by ID, which is the practice this generalises"
    # A line count hides a lost ticket; `comm -23` on the id sets is what caught all four measured
    # instances by hand, and it is the only form of this reading anybody acts on.
    ( cd "$ws" && git show HEAD^:TODO.md > TODO.md )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "a stale ledger is refused" \
        $( [[ $rc == 3 && "$out" == *WORKTREE-BEHIND-HEAD* && "$out" == *TODO.md* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the missing ticket id is NAMED, not just counted" \
        $( [[ "$out" == *"ticket ids HEAD has"*"T-102"* ]] && print 1 || print 0 ) "$out"
    check "the id that is still there is not named" \
        $( [[ "$out" != *"T-101"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" ids TODO.md 2>&1 ); rc=$?
    check "ids <path> is the same reading on its own" \
        $( [[ $rc == 3 && "$out" == *T-102* && "$out" != *T-101* ]] && print 1 || print 0 ) "exit $rc: $out"
    ( cd "$ws" && git checkout -q HEAD -- TODO.md )
    out=$( cd "$ws" && zsh "$here" ids TODO.md 2>&1 ); rc=$?
    check "and it passes once the copy is current" $(( rc == 0 )) "exit $rc: $out"

    say ""
    say " mode 5b -- \`base <path> <rev>\` is the same reading for one path, in a form a script reads"
    # T-982. This is what agent-commit.sh calls, so it has to answer about the path it was asked
    # about and about the revision it was HANDED -- not about the tree, and not about whatever
    # `HEAD` resolves to at the moment it runs, which is a different commit under four agents.
    ( cd "$ws" && git show HEAD^:code.swift > code.swift )
    out=$( cd "$ws" && zsh "$here" base code.swift "$( cd "$ws" && git rev-parse HEAD )" 2>&1 ); rc=$?
    check "base reports a stale copy as behind, and exits 3" \
        $( [[ $rc == 3 && "$out" == behind* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and names the kind in its second field" \
        $( [[ "$(print -r -- "$out" | cut -f2)" == "stale copy" ]] && print 1 || print 0 ) "$out"
    check "and the base revision in its third" \
        $( [[ "$(print -r -- "$out" | cut -f3)" == "$( cd "$ws" && git rev-parse HEAD^ )" ]] && print 1 || print 0 ) "$out"
    # The path it was NOT asked about must not leak in: ordered.txt is clean here, and a `base`
    # that answered about the tree would have to say something about code.swift when asked about it.
    out=$( cd "$ws" && zsh "$here" base ordered.txt 2>&1 ); rc=$?
    check "a clean path is not behind even while another path in the tree is" \
        $( [[ $rc == 0 && "$out" != behind* ]] && print 1 || print 0 ) "exit $rc: $out"
    # Handed the OLD revision, the same stale copy is current -- which is the whole reason the
    # revision is a parameter rather than the string HEAD.
    out=$( cd "$ws" && zsh "$here" base code.swift "$( cd "$ws" && git rev-parse HEAD^ )" 2>&1 ); rc=$?
    check "and against the revision it IS, the same copy is not behind" \
        $( [[ $rc == 0 && "$out" != behind* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" base 2>&1 ); rc=$?
    check "base with no path is refused rather than answering about nothing" \
        $( [[ $rc == 3 && "$out" == *BAD-OPTION* ]] && print 1 || print 0 ) "exit $rc: $out"
    ( cd "$ws" && git checkout -q HEAD -- code.swift )

    say ""
    say " mode 6 (NOT-REPO-ROOT) -- paths are repo-relative, so anywhere else is a wrong answer"
    out=$( cd "$ws/.." && zsh "$here" check 2>&1 ); rc=$?
    check "running from outside the checkout root is refused" \
        $( [[ $rc == 3 && "$out" == *NOT-REPO-ROOT* ]] && print 1 || print 0 ) "exit $rc: $out"

    rm -rf "$ws"
    say ""
    # A tally derived from the checks that really ran: a selftest gutted to `return 0` also exits
    # 0, and cannot print a non-zero passed count (T-719).
    say "checks: $(( ${#performed} - ${#failures} )) passed, ${#failures} failed"
    if (( ${#failures} )); then
        say "SELFTEST FAILED: ${(j:, :)failures}"
        return 1
    fi
    say "SELFTEST PASSED"
    return 0
}

# --- entry --------------------------------------------------------------------

case "${1:-}" in
    check)    shift; cmd_check "$@"; exit $? ;;
    base)     shift; cmd_base "$@"; exit $? ;;
    report)   shift; cmd_report "$@"; exit $? ;;
    repair)   shift; cmd_repair "$@"; exit $? ;;
    ids)      shift; cmd_ids "$@"; exit $? ;;
    selftest) shift; cmd_selftest "$@"; exit $? ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac
