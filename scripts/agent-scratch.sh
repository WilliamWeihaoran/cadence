#!/bin/zsh
# Mint an isolated verification tree, and REFUSE to delete one whose work is in no commit (T-1094).
#
#   ./scripts/agent-scratch.sh new <id>        # mint a uniquely named tree at HEAD; prints its path
#   ./scripts/agent-scratch.sh check <dir>     # exit 3 if it holds work that is in neither its
#                                              #   base nor HEAD -- i.e. the only copy of something
#   ./scripts/agent-scratch.sh release <dir>   # check, then delete. The only safe way to clean up.
#   ./scripts/agent-scratch.sh status          # every minted tree on this machine, and its state
#   ./scripts/agent-scratch.sh selftest        # prove the refusals still fire
#
# WHY THIS EXISTS, AND WHY IT IS NOT ANOTHER PARAGRAPH
#
# T-1094 was filed on 2026-09-07 after two batches of finished, mutation-tested work stopped
# existing: both commits were refused, and both agents then did the standing "delete DerivedData
# and scratch when you are done", which was the only copy. The prescribed fix was prose, and the
# prose was written -- docs/AGENT_BRIEF_PREAMBLE.md has carried *"A refused commit means your files
# are the only copy of your work. Do not delete them"* ever since.
#
# **It happened again on 2026-09-11, with that paragraph in place.** An agent called `noticetruth`
# finished T-752, T-919 and T-1085, deleted its tree before its commit landed, and every line was
# lost; a second agent rebuilt all three from nothing. So the paragraph is not the fix, and there is
# a specific reason it could not have been: **it is conditioned on a refusal.** "A refused commit
# means..." answers the 2026-09-07 shape and says nothing about deleting before you have tried to
# commit at all, which is the 2026-09-11 shape. The predicate that covers both is not about the
# commit path: *is this work in HEAD yet* -- and that is a question a script can answer.
#
# THE READING IS THREE-WAY, and the third input is what makes it usable
#
# A tree is minted from `git archive <base>` and stamped with <base>. For each file:
#
#   identical to <base>'s blob   -> untouched. You never edited it.
#   identical to HEAD's blob     -> landed. Your commit is in, or a sibling's is; either way a copy
#                                   of these bytes exists in history and deleting them loses nothing.
#   neither                      -> UNLANDED. This file is the only copy, and `release` refuses.
#
# Two-way against HEAD alone would be useless here: siblings land constantly, so by the time you
# finish, an untouched tree differs from HEAD in every path they touched and every release would
# refuse. Measured over this repository's own history (see `selftest` mode 3): a tree minted 8
# commits back and never edited names 0 unlanded files under the three-way reading. Same family of
# fix as `declined_lines` in agent-commit.sh, which needs its third input for the same reason.
#
# AND THE NAME IS MINTED, NOT CHOSEN (the second loss measured that week)
#
# The session scratchpad is SHARED. One agent's isolated tree at `.../scratchpad/tree` was
# overwritten by a sibling's `git archive` extraction into the same generic name, so its entire
# first build-and-test round silently measured HEAD instead of its own edits -- a wrong ANSWER, not
# a crash, which is the expensive kind. docs/AGENT_BRIEF_PREAMBLE.md already named `tree` as a
# hazard in as many words and it happened anyway. `new` therefore does not accept a directory at
# all: it builds one from your agent id, the base sha and the pid, and refuses outright if the id
# is one of the generic words that have already collided.
#
# WHAT IT REFUSES
#
#   NOT-REPO-ROOT            run from somewhere other than the top of the checkout
#   GENERIC-SCRATCH-NAME     `new tree`, `new work`, `new scratch`... -- the names that collided
#   SCRATCH-NAME-TAKEN       the minted path already exists; never extract over a live tree
#   UNKNOWN-SCRATCH          check/release on a directory this script did not mint (no stamp)
#   SCRATCH-HOLDS-UNLANDED-WORK
#                            the tree holds files that are in neither its base nor HEAD. This is
#                            T-1094. `--force` deletes anyway and says which paths it destroyed.
#
# Build output is not work. The reading runs through the tree's own `.gitignore` (`git add -A`), so
# `build/`, `.codex-build/`, `xcuserdata/` and `*.profraw` are invisible to it, and nothing is
# hashed into the real object database -- `GIT_OBJECT_DIRECTORY` points at a throwaway.

set -uo pipefail
SCRIPT_PATH="${0:A}"

say() { print -r -- "$@" }
refuse() { print -r -- "REFUSED ($1): $2" >&2; exit 3 }

TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"
STAMP=".cadence-scratch"

# zsh writes here-document temp files to $TMPPREFIX, and zsh SETS that itself at startup to
# `/tmp/zsh` -- never $TMPDIR, and never empty, so a `[[ -z $TMPPREFIX ]]` guard would never fire.
# Under the App Sandbox the test host runs in, `/tmp` is not writable, and every heredoc in this
# script then fails with nothing useful on stderr (T-719). Same line as mutate.sh and the hook.
export TMPPREFIX="${CADENCE_TMPPREFIX:-${TMP_BASE}zsh}"

if ! git --version >/dev/null 2>&1; then
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin; do
        [[ -x "$_candidate/git" ]] || continue
        "$_candidate/git" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; break
    done
fi

usage() {
    say "usage: ./scripts/agent-scratch.sh new <id> [--at <dir>]"
    say "       ./scripts/agent-scratch.sh check <dir>"
    say "       ./scripts/agent-scratch.sh release <dir> [--force]"
    say "       ./scripts/agent-scratch.sh status"
    say "       ./scripts/agent-scratch.sh selftest"
}

# The words that have actually collided in this session's scratchpad, plus the obvious neighbours.
# Not a style rule: `tree` cost one agent a whole build-and-test round that measured the wrong
# sources, and it was already named as a hazard in the preamble when that happened.
GENERIC_IDS=(tree work scratch tmp temp build test agent lead run copy src source check out output dir)

require_repo_root() {
    local top; top=$(git rev-parse --show-toplevel 2>/dev/null) \
        || refuse NOT-REPO-ROOT "not inside a git checkout"
    [[ "${PWD:A}" == "${top:A}" ]] \
        || refuse NOT-REPO-ROOT "run this from the top of the checkout ($top), not $PWD"
}

# --- new ----------------------------------------------------------------------

cmd_new() {
    (( $# >= 1 )) || { usage; exit 2 }
    local id="$1"; shift
    local at=""
    while (( $# )); do
        case "$1" in
            --at) [[ $# -ge 2 ]] || refuse BAD-OPTION "--at needs a directory"; at="$2"; shift 2 ;;
            *) usage; exit 2 ;;
        esac
    done
    require_repo_root
    [[ "$id" =~ '^[A-Za-z0-9][A-Za-z0-9_-]*$' ]] \
        || refuse GENERIC-SCRATCH-NAME "'$id' is not usable as an agent id; use letters, digits, - and _"
    # `--at` is checked on its BASENAME, which is where the measured collision lived: the hazard was
    # never the parent directory, it was an agent calling its tree `tree` inside a shared scratchpad.
    local g check_words=("${id:l}")
    [[ -n "$at" ]] && check_words+=("${${at:t}:l}")
    local w
    for w in "${check_words[@]}"; do
    for g in "${GENERIC_IDS[@]}"; do
        [[ "$w" == "$g" ]] && refuse GENERIC-SCRATCH-NAME "'$w' is a generic name, and generic names collide.
  The session scratchpad is shared by every agent in the batch. A sibling's \`git archive\` landed
  on top of one agent's tree at \`.../scratchpad/tree\`, and that agent's first whole build-and-test
  round then measured HEAD instead of its own edits -- silently, as a wrong answer. Pass YOUR agent
  id (the word your brief calls you), not what the directory is for."
    done
    done

    local headsha; headsha=$(git rev-parse HEAD 2>/dev/null) \
        || refuse NOT-REPO-ROOT "cannot read HEAD"
    local dir="${at:-${TMP_BASE}cadence-${id}-${headsha[1,7]}-$$}"
    dir="${dir:A}"
    [[ -e "$dir" ]] && refuse SCRATCH-NAME-TAKEN "$dir already exists.
  Never extract over a live tree: that is the failure this helper was written for. Delete it with
  \`release\` (which will tell you if it holds the only copy of something) and mint a new one."

    mkdir -p "$dir" || refuse MKDIR "cannot create $dir"
    git archive "$headsha" | tar -x -C "$dir" \
        || { rm -rf "$dir"; refuse ARCHIVE "git archive into $dir failed" }
    mkdir -p "$dir/$STAMP"
    print -r -- "$headsha"          > "$dir/$STAMP/base"
    print -r -- "$id"               > "$dir/$STAMP/id"
    print -r -- "${PWD:A}"          > "$dir/$STAMP/repo"
    date -u +%Y-%m-%dT%H:%M:%SZ     > "$dir/$STAMP/created"
    cat > "$dir/$STAMP/README" <<'EOF'
This tree was minted by scripts/agent-scratch.sh. Do NOT `rm -rf` it.

    ./scripts/agent-scratch.sh release <this directory>

refuses while anything in here is in neither the base commit nor HEAD -- i.e. while this tree is
the only copy of your work. That is T-1094, which has destroyed three batches of finished work.
EOF
    say "$dir"
    return 0
}

# --- check --------------------------------------------------------------------

# Writes the unlanded paths to stdout, one per line. Exit 0 = nothing unlanded.
unlanded_paths() {  # $1 = dir, $2 = base sha, $3 = head sha
    local dir="${1:A}" base="$2" head="$3"
    local gitdir; gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
    local work; work=$(mktemp -d "${TMP_BASE}cadence-scratch-check.XXXXXX") || return 1
    # Hash into a throwaway object directory with the real one as an alternate: the tree gets read
    # without one loose object landing in a checkout other agents are committing from.
    export GIT_DIR="$gitdir" GIT_WORK_TREE="$dir" GIT_INDEX_FILE="$work/index"
    export GIT_OBJECT_DIRECTORY="$work/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$gitdir/objects"
    mkdir -p "$work/objects"
    (
        cd "$dir" || exit 1
        # SEED THE INDEX FROM THE BASE COMMIT FIRST, and this line is the whole difference between
        # a usable guard and one that refuses every release. `git add -A` skips a path that the
        # .gitignore matches AND the index does not already track -- and this repository tracks
        # `default.profraw` while `.gitignore` carries `*.profraw`. Against an empty index that
        # file is invisible to `add`, so it reads as DELETED against both the base and HEAD, lands
        # in both lists, and is reported as the only copy of something. Measured over 25 untouched
        # trees archived from the last 25 commits: 25 refusals, every one of them that one file.
        # Seeded from the base, the same 25 trees name zero files.
        git read-tree "$base" >/dev/null 2>&1
        # `git add -A` honours the tree's own .gitignore, so NEW build output reaches neither list.
        git add -A -- . >/dev/null 2>&1
        git diff-index --cached --name-only "$base" -- 2>/dev/null | sort -u > "$work/vs-base"
        git diff-index --cached --name-only "$head" -- 2>/dev/null | sort -u > "$work/vs-head"
    )
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    # In NEITHER list: differs from the base you started at AND differs from what history now holds.
    [[ -f "$work/vs-base" && -f "$work/vs-head" ]] \
        && comm -12 "$work/vs-base" "$work/vs-head" | grep -v "^$STAMP/"
    rm -rf "$work"
    return 0
}

read_stamp() {  # $1 = dir; sets SCRATCH_BASE / SCRATCH_ID
    local dir="${1:A}"
    [[ -d "$dir" ]] || refuse UNKNOWN-SCRATCH "$1 is not a directory"
    [[ -f "$dir/$STAMP/base" ]] || refuse UNKNOWN-SCRATCH "$1 carries no $STAMP stamp, so this script did not mint it.
  It cannot tell what revision that tree started from, and without the base it cannot tell your
  edits from the eight commits siblings landed while you worked. Mint trees with
  \`./scripts/agent-scratch.sh new <your-agent-id>\` and this question is answerable."
    SCRATCH_BASE=$(<"$dir/$STAMP/base")
    SCRATCH_ID=$(<"$dir/$STAMP/id")
    git cat-file -e "$SCRATCH_BASE^{commit}" 2>/dev/null \
        || refuse UNKNOWN-SCRATCH "$1's base commit $SCRATCH_BASE is not in this repository"
}

cmd_check() {
    (( $# >= 1 )) || { usage; exit 2 }
    require_repo_root
    local dir="${1:A}"
    read_stamp "$dir"
    local head; head=$(git rev-parse HEAD)
    local -a unlanded
    unlanded=(${(f)"$(unlanded_paths "$dir" "$SCRATCH_BASE" "$head")"})
    unlanded=(${unlanded:#})
    if (( ${#unlanded} == 0 )); then
        say "$dir"
        say "  agent '$SCRATCH_ID', base ${SCRATCH_BASE[1,8]}, HEAD ${head[1,8]}"
        say "  nothing here is in neither the base nor HEAD -- safe to release."
        return 0
    fi
    say "$dir"
    say "  agent '$SCRATCH_ID', base ${SCRATCH_BASE[1,8]}, HEAD ${head[1,8]}"
    print -rl -- "${unlanded[@]}" | sed 's|^|    |'
    refuse SCRATCH-HOLDS-UNLANDED-WORK "${#unlanded} file(s) above are in neither ${SCRATCH_BASE[1,8]} nor HEAD.
  This tree is the only copy of them. Do not delete it: commit first, confirm with
  \`git log --oneline -1\`, and release afterwards. If your commit was REFUSED, that says the commit
  was not taken, not that the work was no good -- report these absolute paths and the refusal text
  so the next agent commits your work instead of rebuilding it (T-1094, three batches lost).
  If you really are throwing this away: release --force, which prints what it destroyed."
}

# --- release ------------------------------------------------------------------

cmd_release() {
    (( $# >= 1 )) || { usage; exit 2 }
    require_repo_root
    local force=0 dir=""
    local a
    for a in "$@"; do
        case "$a" in
            --force) force=1 ;;
            *) dir="${a:A}" ;;
        esac
    done
    [[ -n "$dir" ]] || { usage; exit 2 }
    read_stamp "$dir"
    local head; head=$(git rev-parse HEAD)
    local -a unlanded
    unlanded=(${(f)"$(unlanded_paths "$dir" "$SCRATCH_BASE" "$head")"})
    unlanded=(${unlanded:#})
    if (( ${#unlanded} && ! force )); then
        say "$dir"
        print -rl -- "${unlanded[@]}" | sed 's|^|    |'
        refuse SCRATCH-HOLDS-UNLANDED-WORK "${#unlanded} file(s) above are in neither ${SCRATCH_BASE[1,8]} nor HEAD.
  Nothing was deleted. Commit, check \`git log --oneline -1\` names your commit, then release.
  If the commit was refused, leave this tree where it is and report its absolute path (T-1094).
  If you really are throwing this away: release --force."
    fi
    if (( ${#unlanded} )); then
        say "DESTROYED ${#unlanded} file(s) that were in neither ${SCRATCH_BASE[1,8]} nor HEAD (--force):"
        print -rl -- "${unlanded[@]}" | sed 's|^|    |'
    fi
    rm -rf "$dir" || refuse RELEASE "cannot remove $dir"
    say "released $dir"
    return 0
}

# --- status -------------------------------------------------------------------

cmd_status() {
    require_repo_root
    local head; head=$(git rev-parse HEAD)
    # Every declaration hoisted out of the loop: a bare `local` reached a second time in one zsh
    # function lists the parameter on stdout instead of redeclaring it (T-1074), and this
    # function's stdout is the report.
    local any=0 d base="" id=""
    local -a unlanded
    for d in ${TMP_BASE}cadence-*(N/); do
        [[ -f "$d/$STAMP/base" ]] || continue
        any=1
        base=$(<"$d/$STAMP/base"); id=$(<"$d/$STAMP/id")
        git cat-file -e "$base^{commit}" 2>/dev/null || { say "  $d  (agent '$id', base $base NOT IN THIS REPO)"; continue }
        unlanded=(${(f)"$(unlanded_paths "$d" "$base" "$head")"})
        unlanded=(${unlanded:#})
        if (( ${#unlanded} )); then
            say "  HOLDS UNLANDED WORK (${#unlanded} file(s))  $d  -- agent '$id', base ${base[1,8]}"
            print -rl -- "${unlanded[@]}" | sed 's|^|      |'
        else
            say "  safe to release              $d  -- agent '$id', base ${base[1,8]}"
        fi
    done
    (( any )) || say "  (no minted scratch trees under ${TMP_BASE})"
    return 0
}

# --- selftest -----------------------------------------------------------------

cmd_selftest() {
    local passed=0 failed=0
    local -a failures
    check() {  # $1 = label, $2 = 1|0, $3 = detail
        if (( $2 )); then say "  ok    $1"; passed=$(( passed + 1 ))
        else say "  FAIL  $1  <- ${3:-}"; failed=$(( failed + 1 )); failures+=("$1"); fi
    }
    local here="$SCRIPT_PATH"
    local ws; ws=$(mktemp -d "${TMP_BASE}cadence-scratch-selftest.XXXXXX")
    local repo="$ws/repo"
    mkdir -p "$repo/scripts"
    ( cd "$repo"
      git init -q . && git config user.email a@b.c && git config user.name t
      print -r -- "build/" > .gitignore
      print -r -- "base" > file.swift
      print -r -- "shared" > other.swift
      cp "$here" scripts/agent-scratch.sh
      git add -A && git commit -qm base ) >/dev/null 2>&1

    say ""
    say " mode 1 (GENERIC-SCRATCH-NAME / SCRATCH-NAME-TAKEN) -- the name that collided"
    local out rc
    out=$( cd "$repo" && zsh "$here" new tree 2>&1 ); rc=$?
    check "minting a tree called 'tree' is refused" \
        $( [[ $rc == 3 && "$out" == *GENERIC-SCRATCH-NAME* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$repo" && zsh "$here" new SCRATCH 2>&1 ); rc=$?
    check "and the check is case-insensitive" \
        $( [[ $rc == 3 && "$out" == *GENERIC-SCRATCH-NAME* ]] && print 1 || print 0 ) "exit $rc: $out"
    local tree1; tree1=$( cd "$repo" && zsh "$here" new alpha 2>&1 ); rc=$?
    check "an agent id mints a tree" $( [[ $rc == 0 && -d "$tree1" ]] && print 1 || print 0 ) "exit $rc: $tree1"
    check "the minted name carries the id and the base sha, so two agents cannot collide" \
        $( [[ "${tree1:t}" == cadence-alpha-*-* ]] && print 1 || print 0 ) "$tree1"
    check "and it is a real archive of HEAD, not an empty directory" \
        $( [[ -f "$tree1/file.swift" && "$(<$tree1/file.swift)" == base ]] && print 1 || print 0 )
    # THE SECOND LOSS MEASURED THAT WEEK, exactly: a sibling extracting `git archive` into a
    # directory another agent was already working in. One agent's whole first build-and-test round
    # then measured HEAD rather than its own edits -- a wrong answer, not a crash.
    out=$( cd "$repo" && zsh "$here" new gamma --at "$ws/shared/tree" 2>&1 ); rc=$?
    check "--at a directory called 'tree' is refused on the BASENAME" \
        $( [[ $rc == 3 && "$out" == *GENERIC-SCRATCH-NAME* ]] && print 1 || print 0 ) "exit $rc: $out"
    mkdir -p "$ws/shared/siblings-tree" && print -r -- "a sibling is working here" > "$ws/shared/siblings-tree/file.swift"
    out=$( cd "$repo" && zsh "$here" new gamma --at "$ws/shared/siblings-tree" 2>&1 ); rc=$?
    check "extracting into a directory that already exists is refused, not merged into" \
        $( [[ $rc == 3 && "$out" == *SCRATCH-NAME-TAKEN* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the sibling's file is untouched" \
        $( [[ "$(<$ws/shared/siblings-tree/file.swift)" == "a sibling is working here" ]] && print 1 || print 0 )

    say ""
    say " mode 2 (SCRATCH-HOLDS-UNLANDED-WORK) -- T-1094, the refusal that had to exist"
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "an untouched tree is safe to release" $(( rc == 0 )) "exit $rc: $out"
    print -r -- "the only copy of a day's work" > "$tree1/file.swift"
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "a tree holding an uncommitted edit is refused" \
        $( [[ $rc == 3 && "$out" == *SCRATCH-HOLDS-UNLANDED-WORK* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the file is named" $( [[ "$out" == *file.swift* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$repo" && zsh "$here" release "$tree1" 2>&1 ); rc=$?
    check "release refuses it too" \
        $( [[ $rc == 3 && "$out" == *SCRATCH-HOLDS-UNLANDED-WORK* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "AND NOTHING WAS DELETED -- the whole point" $( [[ -d "$tree1" ]] && print 1 || print 0 )
    # A brand-new file is work too, not just an edit to a tracked one.
    print -r -- "a whole new test suite" > "$tree1/NewTests.swift"
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "an untracked new file counts as unlanded work" \
        $( [[ $rc == 3 && "$out" == *NewTests.swift* ]] && print 1 || print 0 ) "exit $rc: $out"
    # Build output is not work. This is the false-refusal control: every verification tree is full
    # of it, and a guard that names it would be turned off within a day.
    mkdir -p "$tree1/build/Products" && print -r -- "obj" > "$tree1/build/Products/a.o"
    print -r -- "log" > "$tree1/xcb-run.log"
    rm -f "$tree1/NewTests.swift"
    print -r -- "base" > "$tree1/file.swift"
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "a .gitignore'd build directory is not read as work" \
        $( [[ $rc == 3 && "$out" != *"build/Products"* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "but a stray log file beside the sources still is -- the reading is not selective" \
        $( [[ "$out" == *xcb-run.log* ]] && print 1 || print 0 ) "$out"
    rm -f "$tree1/xcb-run.log"; rm -rf "$tree1/build"

    say ""
    say " mode 3 (the third input) -- a sibling landing eight commits must not refuse your release"
    # Two-way against HEAD would refuse every release in this repository within minutes. The base
    # is what separates "I edited this" from "somebody else committed this while I worked".
    local i
    for i in 1 2 3 4 5 6 7 8; do
        ( cd "$repo" && print -r -- "sibling commit $i" > other.swift && git add -A && git commit -qm "sibling $i" ) >/dev/null 2>&1
    done
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "an untouched tree 8 commits behind HEAD names ZERO unlanded files" $(( rc == 0 )) "exit $rc: $out"
    # And the other side of the same reading: work that has LANDED is releasable, even though the
    # tree still differs from its own base. That is the half that makes cleanup possible at all.
    print -r -- "my finished work" > "$tree1/file.swift"
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "before committing, that edit is refused" \
        $( [[ $rc == 3 && "$out" == *SCRATCH-HOLDS-UNLANDED-WORK* ]] && print 1 || print 0 ) "exit $rc: $out"
    ( cd "$repo" && print -r -- "my finished work" > file.swift && git add -A && git commit -qm mine ) >/dev/null 2>&1
    out=$( cd "$repo" && zsh "$here" check "$tree1" 2>&1 ); rc=$?
    check "AND THE SAME TREE IS RELEASABLE ONCE THE COMMIT IS AT HEAD" $(( rc == 0 )) "exit $rc: $out"
    out=$( cd "$repo" && zsh "$here" release "$tree1" 2>&1 ); rc=$?
    check "release then deletes it" $( [[ $rc == 0 && ! -d "$tree1" ]] && print 1 || print 0 ) "exit $rc: $out"

    say ""
    say " mode 4 (UNKNOWN-SCRATCH / --force / NOT-REPO-ROOT)"
    local plain="$ws/unstamped"; mkdir -p "$plain"
    out=$( cd "$repo" && zsh "$here" check "$plain" 2>&1 ); rc=$?
    check "a directory this script did not mint is UNKNOWN-SCRATCH, not a pass" \
        $( [[ $rc == 3 && "$out" == *UNKNOWN-SCRATCH* ]] && print 1 || print 0 ) "exit $rc: $out"
    local tree2; tree2=$( cd "$repo" && zsh "$here" new beta 2>&1 )
    print -r -- "throwaway" > "$tree2/file.swift"
    out=$( cd "$repo" && zsh "$here" release "$tree2" --force 2>&1 ); rc=$?
    check "--force deletes deliberately" $( [[ $rc == 0 && ! -d "$tree2" ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and says out loud what it destroyed" \
        $( [[ "$out" == *DESTROYED*file.swift* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" status 2>&1 ); rc=$?
    check "running from outside a checkout is refused" \
        $( [[ $rc == 3 && "$out" == *NOT-REPO-ROOT* ]] && print 1 || print 0 ) "exit $rc: $out"

    rm -rf "$ws"
    say ""
    say "checks: $passed passed, $failed failed"
    if (( failed )); then say "SELFTEST FAILED: ${(j:, :)failures}"; return 1; fi
    say "SELFTEST PASSED"
    return 0
}

# --- dispatch -----------------------------------------------------------------

(( $# )) || { usage; exit 2 }
case "$1" in
    new)      shift; cmd_new "$@" ;;
    check)    shift; cmd_check "$@" ;;
    release)  shift; cmd_release "$@" ;;
    status)   shift; cmd_status "$@" ;;
    selftest) shift; cmd_selftest "$@" ;;
    *)        usage; exit 2 ;;
esac
