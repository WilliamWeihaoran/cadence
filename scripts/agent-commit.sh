#!/bin/zsh
# Commit out of a checkout that other agents are editing at the same time (T-679).
#
#   ./scripts/agent-commit.sh <id> -m <message> <path>[=<content-file>]...
#   ./scripts/agent-commit.sh <id> -F <message-file> <path>...
#   ./scripts/agent-commit.sh status                    # outstanding declined-hunk records
#   ./scripts/agent-commit.sh selftest                  # prove the refusals still fire
#
# WHY THIS EXISTS
#
# `git add <specific paths>`, never `git add -A`, is the rule every brief carries. It was followed
# every time and it is not sufficient: **the index is one object shared by every agent in the
# checkout**, so a bare `git commit` takes whatever any of them staged. Four measured failures, and
# the last three are the ones prose did not stop:
#
#   1. A SIBLING'S HUNK IN YOUR COMMIT (Batch D). d1 staged a `git rm`; d2's next commit swept it
#      in, so the deletion landed in 91d533c (T-637) rather than 5b0c2b8 (T-639). Nothing was lost,
#      but the commit carrying a change was not the commit whose message explains it.
#   2. POST-COMMIT RESIDUE (Batch M). An agent committed correctly through a private
#      `GIT_INDEX_FILE` -- and the *shared* index was left holding its pre-commit blobs, 274
#      deletions behind HEAD. The next agent to commit the shared index would have reverted that
#      agent's own landed work. **The private-index pattern is right and it leaves this behind.**
#   3. A STALE BLOB SITTING IN THE SHARED INDEX (Batch M). `docs/TODO.md` was staged missing a
#      ticket that both HEAD and the worktree had; committing it would have reverted a sibling's
#      ledger entry.
#   4. A HUNK BOTH AGENTS DECLINED (Batch M). m3 reconstructed a file as `git show HEAD:` plus only
#      its own hunks -- *correctly* declining m4's in-flight work -- and m4 then committed without
#      it. A required parameter gained by one composer was never passed by the other, and HEAD
#      stopped compiling. Every protection we had guarded the file being written; none noticed that
#      the hunk you declined to take arrived nowhere.
#
# So the incantation is here instead of in a paragraph. It refuses when the shared index holds a
# path that is not yours, commits through a private index, **repairs the shared index afterwards**,
# and remembers hunks you declined so the next commit of that file has to account for them.
#
# WHAT IT REFUSES
#
#   NOT-REPO-ROOT        run from somewhere other than the top of the checkout
#   NO-PATHS             a commit naming no path is the bare `git commit` this exists to replace
#   UNKNOWN-PATH         a named path is in neither HEAD nor the worktree (a typo commits nothing)
#   FOREIGN-STAGED       the shared index holds staged changes for a path you did not name
#   NOTHING-TO-COMMIT    the tree you assembled equals HEAD -- an empty commit, not a commit
#   NO-COAUTHOR-TRAILER  the message does not end in the required Co-Authored-By line
#   DECLINED-HUNK-LOST   a hunk a previous agent declined for this path is in neither HEAD nor the
#                        content you are staging, so this commit strands it. Clear it deliberately
#                        with --accept-declined <path> if it was abandoned on purpose.
#   SHARED-INDEX-DIRTY   the post-commit repair did not leave your paths clean (reported, not silent)
#
# PATH FORMS
#
#   <path>                stage the worktree content. Right for a file you own alone.
#   <path>=<content-file> stage <content-file>'s bytes as <path>. This is the reconstruction form:
#                         build the file as `git show HEAD:<path>` plus only your edits, and pass
#                         it here. Use it whenever a sibling also has in-flight edits in that file,
#                         because the worktree form would take theirs with yours.
#
# A `=` form whose content differs from the worktree is, by construction, declining something. The
# difference is recorded in the declined-hunk ledger under $TMPDIR and reported at the end of every
# run until some commit of that path accounts for it.
#
# WHAT IT CANNOT DO. If nobody ever commits that path again, no commit-time check fires. `status`
# is the backstop: it lists every outstanding record, and a coordinator can read it before closing
# a batch.

set -uo pipefail

# `$0` inside a zsh function is the FUNCTION name, not the script, so capture it at top level.
SCRIPT_PATH="${0:A}"

say() { print -r -- "$@" }
refuse() { print -r -- "REFUSED ($1): $2" >&2; exit 3 }

TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"
LEDGER="${CADENCE_DECLINED_LEDGER:-${TMP_BASE}cadence-declined-hunks}"

# `/usr/bin/git` is an xcrun shim, and xcrun REFUSES to run inside an App Sandbox
# ("xcrun: error: cannot be used within an App Sandbox"). Every git call then fails with that on
# stderr and nothing else, which reads like a broken repository. Probe by running one.
if ! git --version >/dev/null 2>&1; then
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin; do
        [[ -x "$_candidate/git" ]] || continue
        "$_candidate/git" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; break
    done
fi

usage() {
    say "usage: ./scripts/agent-commit.sh <id> -m <message> <path>[=<content-file>]..."
    say "       ./scripts/agent-commit.sh <id> -F <message-file> <path>..."
    say "       ./scripts/agent-commit.sh status"
    say "       ./scripts/agent-commit.sh selftest"
}

ledger_key() { print -r -- "${1//\//__}" }

# Lines present in the worktree file and in no line of the staged blob. Whole-line set membership,
# not diff hunks: `-U3` merges two agents' edits into one hunk once they are within three lines of
# each other, which is how marker-based hunk filtering quietly took a sibling's work before.
# Trivial lines (blank, or nothing but punctuation and braces) carry no meaning on their own.
declined_lines() {  # $1 = staged content, $2 = worktree content
    grep -F -x -v -f "$1" -- "$2" 2>/dev/null | awk '
        { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
          if (length(t) >= 4 && t !~ /^[][(){}.,;:+*&|<>=!?-]+$/) print }'
}

# NOTE (T-787): `local path` would be a live grenade here. In zsh `path` is tied to `$PATH` even
# when declared local, so assigning to it empties the command search path for the rest of the
# function -- and every `sed`/`head`/`grep` below then dies with `command not found`, silently
# losing exactly the backstop listing this function exists to print. Same family as the two
# `path`/`$PATH` traps already in docs/SUBAGENT_RUNBOOK.md. Nothing here may be named `path`,
# `cdpath`, `fpath`, `manpath`, `status`, `argv` or `options`.
show_outstanding() {
    local any=0 record declined_path
    [[ -d "$LEDGER" ]] || return 0
    for record in "$LEDGER"/*.declined(N); do
        declined_path=$(sed -n 's/^# path: //p' "$record" | head -1)
        [[ -n "$declined_path" ]] || continue
        if (( any == 0 )); then
            say ""
            say "OUTSTANDING DECLINED HUNKS -- these are in no commit yet:"
            any=1
        fi
        say "  $declined_path  (declined by $(sed -n 's/^# by: //p' "$record" | head -1) at $(sed -n 's/^# commit: //p' "$record" | head -1))"
        grep -v '^# ' "$record" | sed 's/^/      /'
    done
    return 0
}

# --- status -------------------------------------------------------------------

cmd_status() {
    say "declined-hunk ledger: $LEDGER"
    local before=$(print -rl -- "$LEDGER"/*.declined(N) | grep -c . )
    if (( before == 0 )); then
        say "  (empty -- every declined hunk has been accounted for)"
    else
        show_outstanding
    fi
}

# --- commit -------------------------------------------------------------------

cmd_commit() {
    local id=$1; shift
    local message="" have_message=0
    local -a paths accepted
    paths=(); accepted=()

    while (( $# )); do
        case "$1" in
            -m) [[ $# -ge 2 ]] || refuse BAD-OPTION "-m needs a message"; message="$2"; have_message=1; shift 2 ;;
            -F) [[ $# -ge 2 ]] || refuse BAD-OPTION "-F needs a file"
                [[ -f "$2" ]] || refuse BAD-OPTION "no such message file: $2"
                message="$(<"$2")"; have_message=1; shift 2 ;;
            --accept-declined) [[ $# -ge 2 ]] || refuse BAD-OPTION "--accept-declined needs a path"
                accepted+=("$2"); shift 2 ;;
            --) shift; paths+=("$@"); break ;;
            -*) refuse BAD-OPTION "unknown option $1" ;;
            *)  paths+=("$1"); shift ;;
        esac
    done

    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || refuse NOT-REPO-ROOT "not inside a git checkout"
    [[ "${PWD:A}" == "${root:A}" ]] || refuse NOT-REPO-ROOT "run from $root, not $PWD (paths are repo-relative)"

    (( have_message )) || refuse NO-MESSAGE "pass -m <message> or -F <message-file>"
    (( ${#paths} )) || refuse NO-PATHS "name every path you are committing; a commit naming none is the bare \`git commit\` this replaces"

    local trailer
    trailer=$(print -r -- "$message" | grep -v '^[[:space:]]*$' | tail -1)
    [[ "$trailer" == Co-Authored-By:* ]] || refuse NO-COAUTHOR-TRAILER "the message must end with a Co-Authored-By: line; it ends with: ${trailer:-(nothing)}"

    # Split <path>=<content-file>. Everything downstream works from `names` plus `source_of`.
    local -a names
    local -A source_of
    names=(); source_of=()
    local spec name src
    for spec in "${paths[@]}"; do
        if [[ "$spec" == *=* ]]; then
            name="${spec%%=*}"; src="${spec#*=}"
            [[ -f "$src" ]] || refuse UNKNOWN-PATH "no such content file: $src"
        else
            name="$spec"; src=""
        fi
        [[ -n "${source_of[$name]+x}" ]] && refuse BAD-OPTION "$name named twice"
        names+=("$name"); source_of[$name]="$src"
        if [[ -z "$src" && ! -e "$name" ]] && ! git cat-file -e "HEAD:$name" 2>/dev/null; then
            refuse UNKNOWN-PATH "$name is in neither HEAD nor the worktree"
        fi
    done

    # 1. The shared index must hold nothing but your paths. A sibling's staged hunk here is exactly
    #    what a bare `git commit` would sweep into your commit.
    local -a foreign
    foreign=()
    local staged
    for staged in ${(f)"$(git diff --cached --name-only HEAD 2>/dev/null)"}; do
        [[ -n "$staged" ]] || continue
        [[ -n "${source_of[$staged]+x}" ]] || foreign+=("$staged")
    done
    (( ${#foreign} )) && refuse FOREIGN-STAGED "the shared index holds paths you did not name: ${(j:, :)foreign}
  Another agent staged them. Ask them to commit, or \`git reset -- <path>\` only what you are sure is yours."

    local scratch
    scratch=$(mktemp -d "${TMP_BASE}cadence-agent-commit-${id}-XXXXXX") || refuse SCRATCH "cannot make a scratch directory"
    local priv="$scratch/index"
    GIT_INDEX_FILE="$priv" git read-tree HEAD || { rm -rf "$scratch"; refuse READ-TREE "cannot read HEAD into a private index" }

    # 2. Assemble the tree in the PRIVATE index. The shared one is never written.
    local blob mode headmode content
    local -A staged_content
    staged_content=()
    for name in "${names[@]}"; do
        src="${source_of[$name]}"
        content="$src"
        [[ -z "$content" ]] && content="$name"
        if [[ ! -e "$content" ]]; then
            GIT_INDEX_FILE="$priv" git update-index --force-remove -- "$name" || { rm -rf "$scratch"; refuse UPDATE-INDEX "cannot stage the deletion of $name" }
            continue
        fi
        blob=$(git hash-object -w -- "$content") || { rm -rf "$scratch"; refuse HASH-OBJECT "cannot hash $content" }
        headmode=$(git ls-tree HEAD -- "$name" | awk '{print $1}')
        mode="${headmode:-100644}"
        [[ -z "$headmode" && -x "$content" ]] && mode=100755
        GIT_INDEX_FILE="$priv" git update-index --add --cacheinfo "$mode,$blob,$name" || { rm -rf "$scratch"; refuse UPDATE-INDEX "cannot stage $name" }
        staged_content[$name]="$scratch/$(ledger_key "$name").staged"
        git cat-file -p "$blob" > "${staged_content[$name]}"
    done

    # 3. A declined hunk that this commit does not carry either is stranded, and that is the Batch M
    #    failure that stopped HEAD compiling. Refuse unless it is in HEAD or in what you are staging.
    local record key acceptp lost
    for name in "${names[@]}"; do
        key=$(ledger_key "$name"); record="$LEDGER/$key.declined"
        [[ -f "$record" ]] || continue
        acceptp=0
        for spec in "${accepted[@]}"; do [[ "$spec" == "$name" ]] && acceptp=1; done
        if (( acceptp )); then
            rm -f "$record"
            say "note: cleared the declined-hunk record for $name at your request (--accept-declined)"
            continue
        fi
        local haystack="$scratch/$key.haystack"
        : > "$haystack"
        [[ -n "${staged_content[$name]+x}" ]] && cat "${staged_content[$name]}" >> "$haystack"
        git cat-file -p "HEAD:$name" >> "$haystack" 2>/dev/null
        lost=$(grep -v '^# ' "$record" | grep -F -x -v -f "$haystack" 2>/dev/null)
        if [[ -n "$lost" ]]; then
            rm -rf "$scratch"
            refuse DECLINED-HUNK-LOST "$name: $(sed -n 's/^# by: //p' "$record" | head -1) declined these lines at $(sed -n 's/^# commit: //p' "$record" | head -1), and they are in neither HEAD nor the content you are staging:
$(print -r -- "$lost" | sed 's/^/    /')
  Fold them in, or clear the record deliberately with --accept-declined $name."
        fi
        rm -f "$record"
    done

    # 4. Commit the private index by plumbing: no hook, no editor, and the shared index untouched.
    local tree headsha newsha
    tree=$(GIT_INDEX_FILE="$priv" git write-tree) || { rm -rf "$scratch"; refuse WRITE-TREE "cannot write the tree" }
    headsha=$(git rev-parse HEAD) || { rm -rf "$scratch"; refuse NO-HEAD "no HEAD to commit onto" }
    if [[ "$tree" == "$(git rev-parse "HEAD^{tree}")" ]]; then
        rm -rf "$scratch"
        refuse NOTHING-TO-COMMIT "the tree you assembled is HEAD's tree; nothing you named differs"
    fi
    newsha=$(print -r -- "$message" | git commit-tree "$tree" -p "$headsha") || { rm -rf "$scratch"; refuse COMMIT-TREE "cannot write the commit" }
    local subject
    subject=$(print -r -- "$message" | head -1)
    git update-ref -m "commit: $subject" HEAD "$newsha" "$headsha" || { rm -rf "$scratch"; refuse UPDATE-REF "HEAD moved under us; nothing was committed" }

    # 5. Record what a reconstruction declined, now that there is a commit sha to name.
    local wt declined
    for name in "${names[@]}"; do
        [[ -n "${source_of[$name]}" ]] || continue      # worktree form declines nothing by construction
        [[ -f "$name" ]] || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        declined=$(declined_lines "${staged_content[$name]}" "$name")
        [[ -n "$declined" ]] || continue
        mkdir -p "$LEDGER"
        record="$LEDGER/$(ledger_key "$name").declined"
        { print -r -- "# path: $name"
          print -r -- "# commit: ${newsha[1,8]}"
          print -r -- "# by: $id"
          print -r -- "$declined" } > "$record"
        say "note: $name was committed as reconstructed content; $(print -r -- "$declined" | grep -c .) worktree line(s) were declined and are in no commit."
        say "      recorded at $record -- the next commit of this path must account for them."
    done

    # 6. THE REPAIR. Without this the shared index still holds the pre-commit blobs for your paths,
    #    and `git status` reports your own landed work as a staged revert (Batch M, 274 deletions).
    git reset -q -- "${names[@]}" 2>/dev/null

    local -a residue
    residue=()
    for staged in ${(f)"$(git diff --cached --name-only HEAD 2>/dev/null)"}; do
        [[ -n "$staged" ]] || continue
        [[ -n "${source_of[$staged]+x}" ]] && residue+=("$staged")
    done
    rm -rf "$scratch"
    if (( ${#residue} )); then
        say "SHARED-INDEX-DIRTY: the repair left these staged against the new HEAD: ${(j:, :)residue}" >&2
        say "committed $newsha anyway; fix the index by hand before anyone else commits." >&2
        exit 4
    fi

    say "committed ${newsha[1,8]}  $subject"
    say "shared index is clean against the new HEAD for: ${(j:, :)names}"
    show_outstanding
    return 0
}

# --- selftest -----------------------------------------------------------------
#
# Every refusal above exists because a real batch lost something. A guard nobody exercises is the
# hollow instrument this repository keeps finding one layer up, so each mode is induced against a
# real throwaway repository and the refusal asserted. It builds nothing and takes about a second.

cmd_selftest() {
    local -a failures performed
    failures=(); performed=()
    check() {
        local name=$1 ok=$2 detail=${3:-}
        performed+=("$name")
        say "  $( (( ok )) && print -n "ok  " || print -n "FAIL")  $name$( (( ok )) || print -n "  <- $detail")"
        (( ok )) || failures+=("$name")
    }

    say "== agent-commit.sh selftest =="
    local here="$SCRIPT_PATH"
    local ws; ws=$(mktemp -d "${TMP_BASE}cadence-agent-commit-selftest-XXXXXX")
    export CADENCE_DECLINED_LEDGER="$ws/ledger"
    local out rc

    (
        cd "$ws" || exit 1
        git init -q .
        git config user.email selftest@example.com
        git config user.name Selftest
        git config commit.gpgsign false
        print -r -- "line one" > mine.txt
        print -r -- "shared start" > shared.txt
        print -r -- "sibling file" > theirs.txt
        git add mine.txt shared.txt theirs.txt >/dev/null
        git commit -qm "base

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
    ) > "$ws.fixture.log" 2>&1 || {
        say "  FAIL  could not build the fixture repository -- git said:"
        sed 's/^/        /' "$ws.fixture.log"
        say "        git: $(command -v git 2>&1)  version: $(git --version 2>&1)"
        rm -rf "$ws" "$ws.fixture.log"; return 1
    }
    rm -f "$ws.fixture.log"

    local M=$'msg\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>'

    say ""
    say " mode 1 (FOREIGN-STAGED) -- a sibling's staged hunk must not be sweepable into your commit"
    ( cd "$ws" && print -r -- "sibling edit" >> theirs.txt && git add theirs.txt ) >/dev/null 2>&1
    ( cd "$ws" && print -r -- "line two" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" t1 -m "$M" mine.txt 2>&1 ); rc=$?
    check "a foreign staged path is refused" $(( rc == 3 )) "exit $rc"
    check "and it is named" $( [[ "$out" == *FOREIGN-STAGED*theirs.txt* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" $( [[ $( cd "$ws" && git rev-list --count HEAD ) == 1 ]] && print 1 || print 0 )
    ( cd "$ws" && git reset -q -- theirs.txt && git checkout -q -- theirs.txt )

    say ""
    say " mode 2 (SHARED-INDEX-DIRTY) -- the shared index must be clean against the NEW head after"
    out=$( cd "$ws" && zsh "$here" t2 -m "$M" mine.txt 2>&1 ); rc=$?
    check "the commit is accepted" $(( rc == 0 )) "exit $rc: $out"
    check "HEAD advanced" $( [[ $( cd "$ws" && git rev-list --count HEAD ) == 2 ]] && print 1 || print 0 )
    check "HEAD carries the change" $( [[ $( cd "$ws" && git show HEAD:mine.txt ) == *"line two"* ]] && print 1 || print 0 )
    ( cd "$ws" && git diff --cached --quiet HEAD ) >/dev/null 2>&1
    check "the SHARED index is clean against the new HEAD" $(( $? == 0 )) \
        "$( cd "$ws" && git diff --cached --name-status HEAD )"
    # The positive control: without the repair the same commit leaves the pre-commit blob staged.
    ( cd "$ws"
      print -r -- "line three" >> mine.txt
      idx=$ws/private-index
      GIT_INDEX_FILE=$idx git read-tree HEAD >/dev/null 2>&1
      b=$(git hash-object -w -- mine.txt)
      GIT_INDEX_FILE=$idx git update-index --add --cacheinfo "100644,$b,mine.txt" >/dev/null 2>&1
      t=$(GIT_INDEX_FILE=$idx git write-tree)
      c=$(print -r -- "$M" | git commit-tree "$t" -p HEAD)
      git update-ref HEAD "$c" >/dev/null 2>&1 ) >/dev/null 2>&1
    ( cd "$ws" && git diff --cached --quiet HEAD ) >/dev/null 2>&1
    check "and the private-index pattern WITHOUT the repair leaves it dirty (this is the bug)" \
        $(( $? != 0 )) "the control commit left a clean index, so mode 2 proves nothing"
    ( cd "$ws" && git reset -q -- mine.txt )

    say ""
    say " mode 3 (DECLINED-HUNK-LOST) -- a hunk one agent declined must not be droppable by the next"
    # Agent A reconstructs shared.txt as HEAD plus only its own line, declining B's in-flight line.
    ( cd "$ws"
      print -r -- "B's in-flight line" >> shared.txt        # B's uncommitted worktree edit
      git show HEAD:shared.txt > recon.txt
      print -r -- "A's own line" >> recon.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" a3 -m "$M" shared.txt=recon.txt 2>&1 ); rc=$?
    check "the reconstruction commits" $(( rc == 0 )) "exit $rc: $out"
    check "and it says what it declined" $( [[ "$out" == *"declined"* ]] && print 1 || print 0 ) "$out"
    # T-787: `local path` in show_outstanding emptied $PATH for its own scope, so the backstop
    # listing died with `command not found: sed` after the commit had already succeeded -- a
    # diagnostic that fails silently is the whole failure family this script is about.
    check "the outstanding-hunk backstop actually prints" \
        $( [[ "$out" == *"OUTSTANDING DECLINED HUNKS"* && "$out" == *"in-flight line"* ]] && print 1 || print 0 ) "$out"
    check "and no command in it died for want of a PATH" \
        $( [[ "$out" != *"command not found"* ]] && print 1 || print 0 ) "$out"
    check "HEAD has A's line and not B's" \
        $( [[ $( cd "$ws" && git show HEAD:shared.txt ) == *"A's own line"* && $( cd "$ws" && git show HEAD:shared.txt ) != *"in-flight"* ]] && print 1 || print 0 )
    # Now B commits the same file WITHOUT its own line -- the Batch M failure, exactly.
    ( cd "$ws" && git show HEAD:shared.txt > lost.txt && print -r -- "B's other line" >> lost.txt )
    out=$( cd "$ws" && zsh "$here" b3 -m "$M" shared.txt=lost.txt 2>&1 ); rc=$?
    check "dropping it a second time is refused" $(( rc == 3 )) "exit $rc: $out"
    check "the lost line is quoted back" $( [[ "$out" == *DECLINED-HUNK-LOST*"in-flight line"* ]] && print 1 || print 0 ) "$out"
    # And B folding it in is accepted, and clears the record.
    ( cd "$ws" && git show HEAD:shared.txt > kept.txt && print -r -- "B's in-flight line" >> kept.txt )
    out=$( cd "$ws" && zsh "$here" b3 -m "$M" shared.txt=kept.txt 2>&1 ); rc=$?
    check "folding it in is accepted" $(( rc == 0 )) "exit $rc: $out"
    check "the ledger record is cleared" $( [[ -z $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 )

    say ""
    say " mode 3b -- --accept-declined clears a record deliberately, and only then"
    ( cd "$ws"
      print -r -- "abandoned line" >> shared.txt
      git show HEAD:shared.txt > recon2.txt
      print -r -- "another of A's lines" >> recon2.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" a4 -m "$M" shared.txt=recon2.txt 2>&1 )
    check "a record was written" $( [[ -n $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 ) "$out"
    ( cd "$ws" && git show HEAD:shared.txt > drop.txt && print -r -- "yet another line" >> drop.txt )
    out=$( cd "$ws" && zsh "$here" b4 -m "$M" shared.txt=drop.txt 2>&1 ); rc=$?
    check "the same commit WITHOUT the flag is refused (so the flag is what lets it through)" \
        $( [[ $rc == 3 && "$out" == *DECLINED-HUNK-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" b4 -m "$M" --accept-declined shared.txt shared.txt=drop.txt 2>&1 ); rc=$?
    check "--accept-declined lets it through" $(( rc == 0 )) "exit $rc: $out"
    check "and it says the record was cleared on purpose" \
        $( [[ "$out" == *"--accept-declined"* ]] && print 1 || print 0 ) "$out"

    say ""
    say " mode 4 (NO-PATHS / UNKNOWN-PATH / NOTHING-TO-COMMIT / NO-COAUTHOR-TRAILER / NOT-REPO-ROOT)"
    say "         -- the shapes that commit nothing must not read as a commit"
    out=$( cd "$ws" && zsh "$here" t5 -m "$M" mine.txt 2>&1 ); rc=$?
    check "an unchanged path is NOTHING-TO-COMMIT" \
        $( [[ $rc == 3 && "$out" == *NOTHING-TO-COMMIT* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" t6 -m "$M" 2>&1 ); rc=$?
    check "naming no path is NO-PATHS" $( [[ $rc == 3 && "$out" == *NO-PATHS* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" t7 -m "$M" Cadence/Nope.swift 2>&1 ); rc=$?
    check "a typo'd path is UNKNOWN-PATH" $( [[ $rc == 3 && "$out" == *UNKNOWN-PATH* ]] && print 1 || print 0 ) "exit $rc: $out"
    ( cd "$ws" && print -r -- "x" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" t8 -m "no trailer here" mine.txt 2>&1 ); rc=$?
    check "a message with no Co-Authored-By trailer is refused" \
        $( [[ $rc == 3 && "$out" == *NO-COAUTHOR-TRAILER* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws/.." && zsh "$here" t9 -m "$M" mine.txt 2>&1 ); rc=$?
    check "running from outside the checkout root is refused" \
        $( [[ $rc == 3 && "$out" == *NOT-REPO-ROOT* ]] && print 1 || print 0 ) "exit $rc: $out"

    rm -rf "$ws"
    say ""
    # A tally derived from the checks that actually ran. A selftest gutted to `return 0` still exits
    # 0; it cannot print a non-zero passed count (T-719).
    say "checks: $(( ${#performed} - ${#failures} )) passed, ${#failures} failed"
    if (( ${#failures} )); then
        say "SELFTEST FAILED: ${(j:, :)failures}"
        return 1
    fi
    say "SELFTEST PASSED"
    return 0
}

# --- entry --------------------------------------------------------------------

if (( $# == 0 )); then usage; exit 2; fi
case "$1" in
    selftest) shift; cmd_selftest "$@"; exit $? ;;
    status)   shift; cmd_status "$@"; exit $? ;;
    -h|--help) usage; exit 0 ;;
esac
if (( $# < 2 )); then usage; exit 2; fi
cmd_commit "$@"
