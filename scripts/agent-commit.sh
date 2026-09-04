#!/bin/zsh
# Commit out of a checkout that other agents are editing at the same time (T-679).
#
#   ./scripts/agent-commit.sh <id> -m <message> <path>[=<content-file>]...
#   ./scripts/agent-commit.sh <id> -F <message-file> <path>...
#   ./scripts/agent-commit.sh status                    # outstanding declined-hunk records
#   ./scripts/agent-commit.sh check                     # exit 3 while any record is outstanding
#   ./scripts/agent-commit.sh accept <path>             # clear one record deliberately
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
#   LEDGER-IDS-LOST      a `TODO.md` you are committing no longer has a `- [T-n]` entry HEAD had.
#                        `--drops-ids <exact,sorted,list>` retires them deliberately. A line count
#                        cannot show you this; an id can.
#   LEDGER-CLOSURE-LOST  a `TODO.md` entry that is CLOSED in HEAD is open again in the content you
#                        are staging, with its id intact -- so LEDGER-IDS-LOST sees nothing wrong.
#                        `--reopens-ids <exact,sorted,list>` reopens them deliberately.
#   WORKTREE-BEHIND-HEAD a bare `<path>` whose worktree copy is built on a revision older than
#                        HEAD's. Committing it writes the stale bytes into history, where no drift
#                        check looks. Rebuild on `git show HEAD:<path>` and pass the `=` form, or
#                        `--commits-stale <path>` if the old content really is what you mean.
#   REMOVES-HEAD-LINES   the staged content drops lines HEAD has, and you did not say how many.
#                        `--removes <exact count>` acknowledges them. A reconstruction built on a
#                        stale HEAD reverts a sibling's landed work in exactly this shape.
#   HEAD-MOVED           a sibling commit landed between the validation and the commit. Every check
#                        above answers a question about ONE HEAD; committing onto a later one asks
#                        nothing about the difference. Re-read HEAD and run it again.
#   DECLINED-HUNK-STALE  a declined-hunk record has been outstanding longer than
#                        $CADENCE_DECLINED_STALE_MINUTES (default 30). Not necessarily YOUR path:
#                        a record nobody clears is a hunk in no commit, and printing it has
#                        already failed twice. See T-781 below.
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
# WHERE THE BARE FORM GOES WRONG, AND WHY ONLY IT IS DRIFT-CHECKED (T-982)
#
# `worktree-drift.sh` gates `xcb.sh test`, so an integration run cannot start against a checkout
# behind HEAD. That is the right gate for READING. Drift is CREATED one step earlier, here: a bare
# `<path>` takes the worktree copy, and in this checkout the worktree copy is routinely behind HEAD
# precisely because this script commits through a private index and a landed commit never writes
# the checkout (T-975). Commit that copy and the stale bytes are in HEAD, where nothing checks.
#
# Reproduced 2026-09-05 in a throwaway repository, and the reproduction changed the shape of the
# fix. The commit is not unguarded today -- REMOVES-HEAD-LINES fires, because a copy behind HEAD is
# missing lines HEAD has by construction. But it fires with the wrong diagnosis and then hands the
# agent the cure for it: *"say the number: --removes 1"*. Typing `--removes 1` was accepted and the
# sibling's landed line left HEAD. The count is the symptom; "this file is built on an older
# revision, and here is which one" is the diagnosis, and it is the one an agent can act on.
#
# The `=` form is deliberately NOT checked. Rebuilding the file as `git show HEAD:<path>` plus your
# own edits IS the prescribed repair for this drift, and its content is by definition not the
# worktree's, so a check that refused it would refuse the fix and leave only the broken path open.
#
# THE BACKSTOP, AND WHY IT IS NOT `status` (T-781)
#
# The check above fires on the NEXT commit of that path. If nobody ever commits that path again,
# nothing fires at all -- and `status` only helps a coordinator who remembers to run it, which is
# the same prose-shaped protection T-679 was filed about. Measured in one run: two declined records
# sat outstanding for hours, printed at the end of every commit, and nobody acted on either.
#
# So there are two, and neither needs anyone to remember:
#
#   `check`  -- the explicit gate. Exits 3 while ANY record is outstanding, whatever its age. This
#               is the batch-completion check: a batch with a hunk in no commit is not finished.
#   DECLINED-HUNK-STALE -- the automatic one. Once a record is older than
#               $CADENCE_DECLINED_STALE_MINUTES (default 30), the next commit by ANY agent in this
#               checkout is refused until it is dealt with. Every agent commits, so this fires
#               without a coordinator in the loop. Fresh records -- the ordinary in-flight case,
#               minutes old -- block nothing.
#
# `accept <path>` clears one record out of band, for the case where the hunk really was abandoned
# and the person clearing it is not the person committing that file.

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
    say "       flags: --removes <n> --drops-ids <ids> --reopens-ids <ids>"
    say "              --accept-declined <path> --commits-stale <path>"
    say "       ./scripts/agent-commit.sh <id> -F <message-file> <path>..."
    say "       ./scripts/agent-commit.sh status         # report outstanding declined hunks"
    say "       ./scripts/agent-commit.sh check          # exit 3 while any is outstanding"
    say "       ./scripts/agent-commit.sh accept <path>  # clear one deliberately"
    say "       ./scripts/agent-commit.sh selftest"
}

ledger_key() { print -r -- "${1//\//__}" }

# Lines present in the worktree file, in no line of the staged blob, AND in no line of the version
# this commit is replacing. Whole-line set membership, not diff hunks: `-U3` merges two agents'
# edits into one hunk once they are within three lines of each other, which is how marker-based
# hunk filtering quietly took a sibling's work before.
#
# The third input is what makes the record mean something. Without it, every line YOU deliberately
# deleted reads as a hunk you declined -- measured on this script's own first real use, where a
# `docs/TODO.md` ledger move recorded 179 lines, most of them the three tickets the commit was
# closing. Only a line the previous commit did not have can be a sibling's in-flight work.
# Trivial lines (blank, or nothing but punctuation and braces) carry no meaning on their own.
declined_lines() {  # $1 = staged content, $2 = worktree content, $3 = content being replaced
    grep -F -x -v -f "$1" -- "$2" 2>/dev/null \
        | { [[ -s "$3" ]] && grep -F -x -v -f "$3" || cat } \
        | awk '
        { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
          if (length(t) >= 4 && t !~ /^[][(){}.,;:+*&|<>=!?-]+$/) print }'
}

# NOTE (T-787): `local path` would be a live grenade here. In zsh `path` is tied to `$PATH` even
# when declared local, so assigning to it empties the command search path for the rest of the
# function -- and every `sed`/`head`/`grep` below then dies with `command not found`, silently
# losing exactly the backstop listing this function exists to print. Same family as the two
# `path`/`$PATH` traps already in docs/SUBAGENT_RUNBOOK.md. Nothing here may be named `path`,
# `cdpath`, `fpath`, `manpath`, `status`, `argv` or `options`.
# An append-only ledger names its entries, and losing one is a different event from deleting a
# line. `docs/TODO.md` is the repository's ledger and every entry opens `- [T-<n>]`; a commit that
# drops an id is almost always a reconstruction built on a stale worktree copy rather than a
# deliberate retirement. Measured 2026-09-03: n2 lost three of a sibling's tickets exactly this way
# and caught it by diffing the id sets by hand, which is the check this makes automatic.
ledger_ids() {  # $1 = file
    grep -oE '^- \[T-[0-9]+\]' -- "$1" 2>/dev/null | sed 's/^- \[//; s/\]$//' | sort -u
}
is_ledger_path() { [[ "${1:t}" == "TODO.md" ]] }

# T-981. LEDGER-IDS-LOST compares ID SETS, and that is one level too shallow. An entry whose text
# reverts from its closure back to the original open ticket keeps its id, so the id sets are equal
# and the guard passes -- while the ledger now says a shipped ticket is not started. Two measured
# instances in this repository's own 349 ledger commits, both found by replaying that history:
#   169d594d  reverted T-679, T-719 and T-787 from CLOSED back to their open text, in a commit
#             about three unrelated instruments, and nothing said a word.
#   f566723b  deduped T-777 by deleting the CLOSED copy and keeping the open one.
#
# The marker is `CLOSED` on the entry's OWN first line -- the `- [T-n] **CLOSED <date> (`sha`).**`
# form, 161 of the file's 387 entries at the time of writing. Deliberately narrow, twice over:
#
#   * Not the whole entry BODY. Sixteen open tickets mention the word in prose ("closed above",
#     "CLOSED, FALSE PREMISE" quoted from elsewhere), so a body-wide reading would mark them
#     closed and then refuse the ordinary rewrite that drops the mention. That is a false refusal
#     in the commit path, which is the one failure this family of guards must not have.
#   * Not the `## Done` SECTION. An entry legitimately moves from Open to Done, and 112 entries
#     in Done carry no closure marker at all, so the section answers a different question. The
#     refusal is about closed TEXT becoming open TEXT for one id, nothing else.
#
# Replayed over all 349 commits that have ever touched docs/TODO.md, this reading fires on exactly
# those two and on none of the other 347.
#
# AND IT STAYS ONE WORD (T-983). The obvious complaint about the above is that it reads only
# `CLOSED`, so a `RESOLVED` or `VERIFIED` closure is invisible to it. Measured against HEAD's
# docs/TODO.md on 2026-09-05, over 395 entries, and the measurement settles it the other way:
#
#     194  entries whose own first line says CLOSED
#       4  entries whose own first line says RESOLVED or VERIFIED, none of which also says CLOSED
#     118  entries in `## Done` with no closure marker on their first line at all
#
# Of those four, TWO ARE OPEN TICKETS -- T-623 and T-624, both sitting in `## Open — decided, not
# started`, both reading `**<the finding>.** VERIFIED 2026-09-01 from CXT-018`. There, VERIFIED
# means the finding was confirmed to be real: the ledger uses the word with the OPPOSITE sense to
# the one a widened marker would read into it. Widening to `RESOLVED|VERIFIED` would mark those two
# closed, and the next ordinary rewrite of either would be refused as a reversion the agent never
# made -- a false refusal in the commit path, which is the one failure this family must not have.
# It would buy two true positives (T-562, T-648) for two false ones. A body-wide reading is worse
# again: 13 open entries mention one of the three words in their prose.
#
# So there is no `RESOLVED`/`VERIFIED` closure CONVENTION to read here -- there are two instances
# and two counterexamples that use the same word to mean "confirmed open". The alternative the
# ticket allows, establishing a convention the ledger then follows, is a rewrite of 118 unmarked
# Done entries and is not this script's to make. The narrowness is the finding. Mode 4d's last two
# checks pin it: an OPEN entry whose own first line says VERIFIED must stay editable.
ledger_closed_ids() {  # $1 = file
    sed -n 's/^- \[\(T-[0-9][0-9]*\)\].*CLOSED.*/\1/p' -- "$1" 2>/dev/null | sort -u
}

STALE_MINUTES="${CADENCE_DECLINED_STALE_MINUTES:-30}"

# Age from the record's mtime, not from a field inside it: records written before this check
# existed have no timestamp field, and treating "no field" as "age zero" would exempt exactly the
# records that have been sitting longest.
record_age_minutes() {  # $1 = record file
    local mtime now
    mtime=$(stat -f %m -- "$1" 2>/dev/null) || { print -r -- 0; return 0 }
    now=$(date +%s)
    print -r -- $(( (now - mtime) / 60 ))
}

outstanding_records() { print -rl -- "$LEDGER"/*.declined(N) }

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
    local before=$(outstanding_records | grep -c . )
    if (( before == 0 )); then
        say "  (empty -- every declined hunk has been accounted for)"
    else
        show_outstanding
    fi
}

# The batch-completion gate. `status` reports; this one FAILS, which is the difference that makes
# it usable from a heartbeat, a wrapper or a coordinator's closing step without anyone reading it.
cmd_check() {
    local -a records
    records=("$LEDGER"/*.declined(N))
    if (( ${#records} == 0 )); then
        say "declined-hunk ledger is empty; every declined hunk is in a commit."
        return 0
    fi
    show_outstanding
    say ""
    refuse DECLINED-HUNKS-OUTSTANDING "${#records} declined hunk record(s) are in no commit.
  A batch does not close over one of these: the lines above were taken out of one agent's
  reconstruction and never put into anyone's commit. Fold each into a commit of that path, or, if
  it was abandoned deliberately, say so: ./scripts/agent-commit.sh accept <path>"
}

# Clearing a record out of band. `--accept-declined` only reaches a path THIS commit names, and the
# agent who has to clear an abandoned hunk is usually not the one committing that file next.
cmd_accept() {
    (( $# )) || refuse BAD-OPTION "accept needs a path"
    local target record
    for target in "$@"; do
        record="$LEDGER/$(ledger_key "$target").declined"
        [[ -f "$record" ]] || refuse UNKNOWN-PATH "no declined-hunk record for $target
  Outstanding records are: $(outstanding_records | sed 's|.*/||; s|\.declined$||' | tr '\n' ' ')"
        say "cleared the declined-hunk record for $target (declined by $(sed -n 's/^# by: //p' "$record" | head -1) at $(sed -n 's/^# commit: //p' "$record" | head -1)):"
        grep -v '^# ' "$record" | sed 's/^/    /'
        rm -f "$record"
    done
    return 0
}

# --- commit -------------------------------------------------------------------

cmd_commit() {
    local id=$1; shift
    local message="" have_message=0 declared_removals="" declared_dropped_ids="" declared_reopened_ids=""
    local -a paths accepted stale_declared
    paths=(); accepted=(); stale_declared=()

    while (( $# )); do
        case "$1" in
            -m) [[ $# -ge 2 ]] || refuse BAD-OPTION "-m needs a message"; message="$2"; have_message=1; shift 2 ;;
            -F) [[ $# -ge 2 ]] || refuse BAD-OPTION "-F needs a file"
                [[ -f "$2" ]] || refuse BAD-OPTION "no such message file: $2"
                message="$(<"$2")"; have_message=1; shift 2 ;;
            --accept-declined) [[ $# -ge 2 ]] || refuse BAD-OPTION "--accept-declined needs a path"
                accepted+=("$2"); shift 2 ;;
            --removes) [[ $# -ge 2 ]] || refuse BAD-OPTION "--removes needs a count"
                declared_removals="$2"; shift 2 ;;
            --drops-ids) [[ $# -ge 2 ]] || refuse BAD-OPTION "--drops-ids needs a comma-separated id list"
                declared_dropped_ids="$2"; shift 2 ;;
            --reopens-ids) [[ $# -ge 2 ]] || refuse BAD-OPTION "--reopens-ids needs a comma-separated id list"
                declared_reopened_ids="$2"; shift 2 ;;
            --commits-stale) [[ $# -ge 2 ]] || refuse BAD-OPTION "--commits-stale needs a path"
                stale_declared+=("$2"); shift 2 ;;
            --) shift; paths+=("$@"); break ;;
            -*) refuse BAD-OPTION "unknown option $1" ;;
            *)  paths+=("$1"); shift ;;
        esac
    done

    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || refuse NOT-REPO-ROOT "not inside a git checkout"
    [[ "${PWD:A}" == "${root:A}" ]] || refuse NOT-REPO-ROOT "run from $root, not $PWD (paths are repo-relative)"

    # THE SHA EVERY CHECK BELOW IS ABOUT (T-974). Read HEAD exactly once, here, and never write
    # `HEAD` again in this function: `git cat-file -p HEAD:<path>` re-resolves the ref on every
    # call, so with four agents committing at once the guards can be answered against one commit
    # and the tree assembled from another. Measured 2026-09-04: a sibling landed in that window,
    # `git rev-parse HEAD` just before commit-tree returned the SIBLING's sha, the compare-and-swap
    # therefore compared the new head against itself and passed -- and the tree, built by
    # `read-tree` at the old head, reverted the sibling's `docs/TODO.md` and took `T-935` with it.
    # LEDGER-IDS-LOST had already run and been satisfied, against a HEAD that no longer existed.
    local headsha
    headsha=$(git rev-parse HEAD 2>/dev/null) || refuse NO-HEAD "no HEAD to commit onto"

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
        if [[ -z "$src" && ! -e "$name" ]] && ! git cat-file -e "$headsha:$name" 2>/dev/null; then
            refuse UNKNOWN-PATH "$name is in neither HEAD nor the worktree"
        fi
    done

    # 1. The shared index must hold nothing but your paths. A sibling's staged hunk here is exactly
    #    what a bare `git commit` would sweep into your commit.
    local -a foreign
    foreign=()
    local staged
    for staged in ${(f)"$(git diff --cached --name-only "$headsha" 2>/dev/null)"}; do
        [[ -n "$staged" ]] || continue
        [[ -n "${source_of[$staged]+x}" ]] || foreign+=("$staged")
    done
    if (( ${#foreign} )); then
        # Ask the cheaper question first. A sibling that committed between the sha capture above and
        # this diff has repaired the shared index against the NEW head, which reads as "changed"
        # against ours -- so their landed paths would be reported as a foreign staged hunk: a true
        # refusal with a false reason, sending the agent to `git reset` a sibling's committed work.
        [[ "$(git rev-parse HEAD 2>/dev/null)" == "$headsha" ]] || refuse HEAD-MOVED "HEAD moved to $(git rev-parse --short HEAD 2>/dev/null) while this commit was starting; it was ${headsha[1,8]} a moment ago.
  Nothing was committed. Run it again against the new HEAD."
        refuse FOREIGN-STAGED "the shared index holds paths you did not name: ${(j:, :)foreign}
  Another agent staged them. Ask them to commit, or \`git reset -- <path>\` only what you are sure is yours."
    fi

    # 1b. T-982. Every guard below this line asks a question about the CONTENT being staged. None
    #     of them asks where that content came from, and for a bare `<path>` it comes from a shared
    #     checkout that drifts behind HEAD by design. Ask before the content questions, because
    #     "built on an older revision" is the diagnosis and REMOVES-HEAD-LINES -- which fires on
    #     this shape too, one step later -- is the symptom plus a cure that makes it worse.
    #
    #     One implementation, not a near-copy: `worktree-drift.sh base` is the same reading the
    #     tree gate uses, asked about one path. It is handed `$headsha` rather than resolving HEAD
    #     itself, so it answers about the same commit as every check either side of it (T-974).
    local drift_script="${SCRIPT_PATH:h}/worktree-drift.sh"
    [[ -f "$drift_script" ]] || refuse DRIFT-CHECK-MISSING "$drift_script is not there, so the bare-path drift check cannot run.
  Skipping it silently is how a guard becomes decoration; restore the script, or pass the paths as
  \`<path>=<content-file>\` rebuilt on \`git show HEAD:<path>\`, which needs no check."
    local -a stale_found stale_report
    stale_found=(); stale_report=()
    local reading drc
    for name in "${names[@]}"; do
        [[ -z "${source_of[$name]}" ]] || continue      # the `=` form is the repair; never refuse it
        [[ -f "$name" ]] || continue
        git cat-file -e "$headsha:$name" 2>/dev/null || continue
        reading=$(zsh "$drift_script" base "$name" "$headsha" 2>/dev/null); drc=$?
        # 0 and 3 are readings. Anything else is the check failing to run, and a guard that reads
        # a crash as "fine" is the hollow instrument this whole file exists to avoid.
        (( drc == 0 || drc == 3 )) || refuse DRIFT-CHECK-FAILED "\`worktree-drift.sh base $name\` exited $drc and said: ${reading:-(nothing)}
  Nothing was committed, because the question of whether $name is behind HEAD went unanswered."
        [[ "$(print -r -- "$reading" | cut -f1)" == behind ]] || continue
        stale_found+=("$name")
        stale_report+=("$name  [$(print -r -- "$reading" | cut -f2)]  $(print -r -- "$reading" | cut -f4)")
    done
    if (( ${#stale_found} )); then
        local -a undeclared
        undeclared=()
        for name in "${stale_found[@]}"; do
            local declaredp=0 spec2
            for spec2 in "${stale_declared[@]}"; do [[ "$spec2" == "$name" ]] && declaredp=1; done
            (( declaredp )) || undeclared+=("$name")
        done
        if (( ${#undeclared} )); then
            refuse WORKTREE-BEHIND-HEAD "these bare paths hold content HEAD has moved past: ${(j:, :)undeclared}
$(print -rl -- "${stale_report[@]}" | sed 's/^/    /')
  A bare \`<path>\` stages the worktree copy, and this checkout drifts behind HEAD by design: a
  commit lands through a private index and never writes the checkout (T-975). Committing this copy
  puts the stale bytes in HEAD, where no drift check looks, and every later reader inherits them.
  A [stale copy] has nothing local in it:  ./scripts/worktree-drift.sh repair
  A [stale base] has your edits on an old one -- rebuild them on \`git show HEAD:<path>\` and pass
  that file as \`<path>=<content-file>\`, which is the form this check deliberately leaves alone.
  If the older content really is what you mean to commit: --commits-stale <path>"
        fi
        say "note: committing a path that is behind HEAD at your request (--commits-stale): ${(j:, :)stale_found}"
    fi

    local scratch
    scratch=$(mktemp -d "${TMP_BASE}cadence-agent-commit-${id}-XXXXXX") || refuse SCRATCH "cannot make a scratch directory"
    local priv="$scratch/index"
    GIT_INDEX_FILE="$priv" git read-tree "$headsha" || { rm -rf "$scratch"; refuse READ-TREE "cannot read HEAD into a private index" }

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
        headmode=$(git ls-tree "$headsha" -- "$name" | awk '{print $1}')
        mode="${headmode:-100644}"
        [[ -z "$headmode" && -x "$content" ]] && mode=100755
        GIT_INDEX_FILE="$priv" git update-index --add --cacheinfo "$mode,$blob,$name" || { rm -rf "$scratch"; refuse UPDATE-INDEX "cannot stage $name" }
        staged_content[$name]="$scratch/$(ledger_key "$name").staged"
        git cat-file -p "$blob" > "${staged_content[$name]}"
    done

    # 3. A declined hunk that this commit does not carry either is stranded, and that is the Batch M
    #    failure that stopped HEAD compiling. Refuse unless it is in HEAD or in what you are staging.
    local record key acceptp lost
    local -a clear_on_success
    clear_on_success=()
    for name in "${names[@]}"; do
        key=$(ledger_key "$name"); record="$LEDGER/$key.declined"
        [[ -f "$record" ]] || continue
        acceptp=0
        for spec in "${accepted[@]}"; do [[ "$spec" == "$name" ]] && acceptp=1; done
        if (( acceptp )); then
            # NOT `rm -f` here. Every refusal from this point on -- REMOVES-HEAD-LINES,
            # LEDGER-IDS-LOST, and since T-974 HEAD-MOVED, which a racing agent will hit and then
            # retry -- ends with nothing committed. Deleting the record before the commit lands
            # means the retry runs with the protection already spent.
            clear_on_success+=("$record")
            say "note: will clear the declined-hunk record for $name at your request (--accept-declined)"
            continue
        fi
        local haystack="$scratch/$key.haystack"
        : > "$haystack"
        [[ -n "${staged_content[$name]+x}" ]] && cat "${staged_content[$name]}" >> "$haystack"
        git cat-file -p "$headsha:$name" >> "$haystack" 2>/dev/null
        lost=$(grep -v '^# ' "$record" | grep -F -x -v -f "$haystack" 2>/dev/null)
        if [[ -n "$lost" ]]; then
            rm -rf "$scratch"
            refuse DECLINED-HUNK-LOST "$name: $(sed -n 's/^# by: //p' "$record" | head -1) declined these lines at $(sed -n 's/^# commit: //p' "$record" | head -1), and they are in neither HEAD nor the content you are staging:
$(print -r -- "$lost" | sed 's/^/    /')
  Fold them in, or clear the record deliberately with --accept-declined $name."
        fi
        clear_on_success+=("$record")
    done

    # 3c. T-781. A record for a path this commit does NOT name fires no check at all -- the guard
    #     above is per-path and only on the next commit of that path. Two records survived a whole
    #     run that way, printed at the end of every commit and acted on by nobody. So a record that
    #     has outlived a plausible in-flight edit stops the checkout instead of being reported into
    #     it. Fresh ones block nothing; this is not a serialisation.
    local -a stale
    stale=()
    for record in "$LEDGER"/*.declined(N); do
        local skip=0 c
        for c in "${clear_on_success[@]}"; do [[ "$c" == "$record" ]] && skip=1; done
        (( skip )) && continue
        (( $(record_age_minutes "$record") >= STALE_MINUTES )) || continue
        # Quote the lines, not just the path. "shared.txt has an outstanding record" is a thing to
        # look up; the lines are the thing to act on, and whoever reads this refusal is usually not
        # the agent that declined them.
        stale+=("$(sed -n 's/^# path: //p' "$record" | head -1) (declined by $(sed -n 's/^# by: //p' "$record" | head -1) at $(sed -n 's/^# commit: //p' "$record" | head -1), $(record_age_minutes "$record")m ago)"
                "$(grep -v '^# ' "$record" | sed 's/^/  | /')")
    done
    if (( ${#stale} )); then
        rm -rf "$scratch"
        refuse DECLINED-HUNK-STALE "a declined hunk has been in no commit for over ${STALE_MINUTES} minute(s):
$(print -rl -- "${stale[@]}" | sed 's/^/    /')
  It is not necessarily yours, and that is the point: nothing else in this checkout will ever
  notice it. Commit that path with the lines folded in, or -- if the hunk was abandoned on purpose
  -- clear it: ./scripts/agent-commit.sh accept <path>"
    fi

    # 3a. A ledger entry HEAD has and your staged content does not is a LOST TICKET, and it hides
    #     inside any line count large enough to be worth reading past. Name the ids, not the lines.
    local -a lost_ids
    lost_ids=()
    for name in "${names[@]}"; do
        is_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        git cat-file -e "$headsha:$name" 2>/dev/null || continue
        local ledger_head="$scratch/$(ledger_key "$name").ledgerhead"
        git cat-file -p "$headsha:$name" > "$ledger_head"
        local gone
        gone=$(comm -23 <(ledger_ids "$ledger_head") <(ledger_ids "${staged_content[$name]}"))
        [[ -n "$gone" ]] || continue
        lost_ids+=(${(f)gone})
    done
    if (( ${#lost_ids} )); then
        local declared_sorted="${(j:,:)${(o)${(s:,:)declared_dropped_ids}}}"
        local lost_sorted="${(j:,:)${(o)lost_ids}}"
        if [[ "$declared_sorted" != "$lost_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-IDS-LOST "this commit drops ledger entries HEAD has: ${(j:, :)lost_ids}
  A reconstruction built on a stale copy loses a sibling's tickets in exactly this shape, and a
  line count hides it. Re-read \`git show HEAD:<path>\` and rebuild, or, if you really mean to
  retire them, say so: --drops-ids $lost_sorted"
        fi
    fi

    # 3a2. T-981, and it is the same shape as 3a one level down. An id that survives while its
    #      CLOSURE does not is a shipped ticket the ledger now describes as not started, and every
    #      guard above is satisfied: the id sets are equal, so LEDGER-IDS-LOST passes; the line
    #      count is whatever the two texts happen to differ by, so REMOVES-HEAD-LINES is a number
    #      somebody acknowledges without reading. Only ids present in BOTH versions are asked
    #      about -- an id that vanished entirely is 3a's finding and naming it twice buries both.
    local -a reopened_ids
    reopened_ids=(); local reopened_in=""
    for name in "${names[@]}"; do
        is_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        git cat-file -e "$headsha:$name" 2>/dev/null || continue
        local closure_head="$scratch/$(ledger_key "$name").closurehead"
        git cat-file -p "$headsha:$name" > "$closure_head"
        local reopened
        reopened=$(comm -12 \
            <(comm -23 <(ledger_closed_ids "$closure_head") <(ledger_closed_ids "${staged_content[$name]}")) \
            <(ledger_ids "${staged_content[$name]}"))
        [[ -n "$reopened" ]] || continue
        reopened_ids+=(${(f)reopened}); reopened_in="$name"
    done
    if (( ${#reopened_ids} )); then
        local declared_reopened_sorted="${(j:,:)${(o)${(s:,:)declared_reopened_ids}}}"
        local reopened_sorted="${(j:,:)${(o)reopened_ids}}"
        if [[ "$declared_reopened_sorted" != "$reopened_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-CLOSURE-LOST "this commit reverts ledger entries from closed back to open: ${(j:, :)reopened_ids}
  Each id is still there, so LEDGER-IDS-LOST has nothing to say about it -- the entry's own text
  changed from a closure back to the open ticket it was before, which is what a reconstruction
  built on a stale copy does to a ticket somebody closed while you were working. Re-read
  \`git show HEAD:$reopened_in\` and rebuild on it, or, if you really are reopening them, say so:
  --reopens-ids $reopened_sorted"
        fi
    fi

    # 3b. A line HEAD has and your staged content does not is a DELETION, and a reconstruction built
    #     on a stale HEAD deletes a sibling's landed work without either of you seeing it. Measured
    #     twice on 2026-09-03 within an hour, both on `docs/TODO.md`, both reverting a ledger edit
    #     that had already landed. So the count has to be said out loud, the way `count:` does in
    #     scripts/mutate.sh -- the point is not the number, it is looking at what is going.
    local -a removed_report
    removed_report=()
    local total_removed=0 removed
    for name in "${names[@]}"; do
        git cat-file -e "$headsha:$name" 2>/dev/null || continue
        local head_blob="$scratch/$(ledger_key "$name").head"
        git cat-file -p "$headsha:$name" > "$head_blob"
        if [[ -n "${staged_content[$name]+x}" ]]; then
            removed=$(grep -F -x -v -f "${staged_content[$name]}" -- "$head_blob" 2>/dev/null | grep -c .)
        else
            removed=$(grep -c . "$head_blob")      # the whole file is being deleted
        fi
        (( removed > 0 )) || continue
        total_removed=$(( total_removed + removed ))
        removed_report+=("$name: $removed")
    done
    if (( total_removed > 0 )) && [[ "$declared_removals" != "$total_removed" ]]; then
        rm -rf "$scratch"
        refuse REMOVES-HEAD-LINES "this commit removes $total_removed line(s) that HEAD has (${(j:, :)removed_report}).
  A reconstruction built on a stale HEAD deletes a sibling's landed work exactly like this. Read
  \`git diff HEAD -- <path>\` first, then say the number: --removes $total_removed"
    fi

    # 4. Commit the private index by plumbing: no hook, no editor, and the shared index untouched.
    local tree newsha
    tree=$(GIT_INDEX_FILE="$priv" git write-tree) || { rm -rf "$scratch"; refuse WRITE-TREE "cannot write the tree" }
    if [[ "$tree" == "$(git rev-parse "$headsha^{tree}")" ]]; then
        rm -rf "$scratch"
        refuse NOTHING-TO-COMMIT "the tree you assembled is HEAD's tree; nothing you named differs"
    fi
    # The compare-and-swap. `git update-ref <ref> <new> <old>` refuses unless the ref is still
    # <old>, and <old> is the sha the checks above were answered against -- which is the whole
    # point. Checking it beforehand instead would leave a window of its own; only the swap is
    # atomic. Refuse first, though, so the common case does not leave a dangling commit object.
    local nowsha; nowsha=$(git rev-parse HEAD 2>/dev/null)
    if [[ "$nowsha" != "$headsha" ]]; then
        rm -rf "$scratch"
        refuse HEAD-MOVED "HEAD was ${headsha[1,8]} when these checks ran and is ${nowsha[1,8]} now.
  A sibling committed while this one was validating. Committing anyway would parent your tree on a
  commit nothing checked, reverting whatever they landed in the paths you named -- that is how
  T-935 was lost on 2026-09-04. Nothing was committed. Re-read \`git show HEAD:<path>\`, rebuild
  any reconstruction on the new HEAD, and run this again."
    fi
    newsha=$(print -r -- "$message" | git commit-tree "$tree" -p "$headsha") || { rm -rf "$scratch"; refuse COMMIT-TREE "cannot write the commit" }
    local subject
    subject=$(print -r -- "$message" | head -1)
    git update-ref -m "commit: $subject" HEAD "$newsha" "$headsha" || { rm -rf "$scratch"; refuse HEAD-MOVED "HEAD moved between the check and the swap; nothing was committed. Run it again." }

    # The commit has landed, so the records this commit accounted for can go. Not before: see the
    # note in step 3.
    (( ${#clear_on_success} )) && rm -f "${clear_on_success[@]}"

    # 5. Record what a reconstruction declined, now that there is a commit sha to name.
    local wt declined
    for name in "${names[@]}"; do
        [[ -n "${source_of[$name]}" ]] || continue      # worktree form declines nothing by construction
        [[ -f "$name" ]] || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        local previous="$scratch/$(ledger_key "$name").previous"
        git cat-file -p "$headsha:$name" > "$previous" 2>/dev/null || : > "$previous"
        declined=$(declined_lines "${staged_content[$name]}" "$name" "$previous")
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
        print -rl -- "# Ledger" "" "- [T-101] first" "  body" "" "- [T-102] second" "  body" > TODO.md
        git add mine.txt shared.txt theirs.txt TODO.md >/dev/null
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
    say " mode 3c -- a line this commit deliberately DELETES is not a hunk it declined"
    # The worktree still HAS the line; only the reconstruction drops it. That is the ledger-move
    # shape, and without the third input it reads as 179 declined hunks.
    ( cd "$ws"
      git show HEAD:shared.txt > shared.txt
      grep -v "A's own line" shared.txt > delrecon.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" a5 -m "$M" --removes 1 shared.txt=delrecon.txt 2>&1 ); rc=$?
    check "the deletion commits" $(( rc == 0 )) "exit $rc: $out"
    check "and nothing was recorded as declined" \
        $( [[ "$out" != *"were declined"* && -z $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 ) "$out"

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
    say " mode 4b (REMOVES-HEAD-LINES) -- deleting a line HEAD has must be said out loud"
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws"
      git show HEAD:shared.txt > shared.txt
      git show HEAD:shared.txt | sed '$d' > cut.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" c1 -m "$M" shared.txt=cut.txt 2>&1 ); rc=$?
    check "an undeclared removal is refused" \
        $( [[ $rc == 3 && "$out" == *REMOVES-HEAD-LINES* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the count is named" $( [[ "$out" == *"removes 1 line(s)"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" c1 -m "$M" --removes 2 shared.txt=cut.txt 2>&1 ); rc=$?
    check "a WRONG count is still refused" \
        $( [[ $rc == 3 && "$out" == *REMOVES-HEAD-LINES* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" c1 -m "$M" --removes 1 shared.txt=cut.txt 2>&1 ); rc=$?
    check "the exact count lets it through" $(( rc == 0 )) "exit $rc: $out"

    say ""
    say " mode 4b2 (WORKTREE-BEHIND-HEAD) -- a bare <path> must not commit a copy behind HEAD"
    # T-982, reproduced 2026-09-05 before it was fixed and reproduced here every run. The sibling
    # below is exactly the shape T-975 measured: it lands a commit through a private index and
    # repairs the shared index afterwards, so it NEVER writes the checkout -- and `git status` then
    # prints ` M code.txt` for the stale copy, character for character what it prints for real work.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws"
      print -rl -- "the first line of code" "the second line of code" "the third line of code" > code.txt
      zsh "$here" f0 -m "$M" code.txt ) >/dev/null 2>&1
    # A well-behaved sibling: private index, HEAD advances, checkout untouched, shared index clean.
    ( cd "$ws"
      git show HEAD:code.txt > sib.txt
      print -r -- "the sibling's landed line, which this checkout has never seen" >> sib.txt
      idx="$ws/sib-index"
      GIT_INDEX_FILE=$idx git read-tree HEAD
      b=$(git hash-object -w -- sib.txt)
      GIT_INDEX_FILE=$idx git update-index --add --cacheinfo "100644,$b,code.txt"
      t=$(GIT_INDEX_FILE=$idx git write-tree)
      c=$(print -r -- "$M" | git commit-tree "$t" -p HEAD)
      git update-ref HEAD "$c"
      git reset -q -- code.txt
      rm -f sib.txt ) >/dev/null 2>&1
    check "the checkout is now behind HEAD on that path" \
        $( [[ $( cd "$ws" && git show HEAD:code.txt ) == *"sibling's landed line"* \
           && $( cd "$ws" && cat code.txt ) != *"sibling's landed line"* ]] && print 1 || print 0 )
    # The control on the whole mode: nothing in the checkout distinguishes this from real work.
    check "git status cannot tell it from an in-flight edit" \
        $( [[ "$( cd "$ws" && git status --porcelain -- code.txt )" == " M code.txt" ]] && print 1 || print 0 ) \
        "$( cd "$ws" && git status --porcelain -- code.txt )"
    ( cd "$ws" && print -r -- "this agent's own new line" >> code.txt )
    out=$( cd "$ws" && zsh "$here" f1 -m "$M" code.txt 2>&1 ); rc=$?
    check "the bare path is refused" \
        $( [[ $rc == 3 && "$out" == *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and it says which revision the copy is built on, not just a line count" \
        $( [[ "$out" == *code.txt* && "$out" == *"built on"* && "$out" == *"[stale base]"* ]] && print 1 || print 0 ) "$out"
    # The diagnosis has to come FIRST. Before this ticket the same commit was refused as
    # REMOVES-HEAD-LINES -- which then told the agent the number to type to get past it.
    check "it is the staleness that is complained about, not the removed-line count" \
        $( [[ "$out" != *REMOVES-HEAD-LINES* ]] && print 1 || print 0 ) "$out"
    # THE REPRODUCTION, and the reason the count was never enough: this is what a compliant agent
    # did with the old refusal's own advice, and the sibling's line left HEAD.
    out=$( cd "$ws" && zsh "$here" f2 -m "$M" --removes 1 code.txt 2>&1 ); rc=$?
    check "and doing what the OLD refusal advised -- --removes 1 -- no longer gets it through" \
        $( [[ $rc == 3 && "$out" == *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the sibling's landed line is still in HEAD" \
        $( [[ $( cd "$ws" && git show HEAD:code.txt ) == *"sibling's landed line"* ]] && print 1 || print 0 ) \
        "$( cd "$ws" && git log --oneline )"
    # The prescribed repair -- rebuild on `git show HEAD:` and pass the `=` form -- must sail
    # through. A check that refused this would leave an agent with no way forward at all.
    ( cd "$ws" && git show HEAD:code.txt > rebuilt.txt && print -r -- "this agent's own new line" >> rebuilt.txt )
    out=$( cd "$ws" && zsh "$here" f3 -m "$M" code.txt=rebuilt.txt 2>&1 ); rc=$?
    check "rebuilding on HEAD and passing the = form is accepted" $(( rc == 0 )) "exit $rc: $out"
    check "and HEAD now has BOTH lines" \
        $( [[ $( cd "$ws" && git show HEAD:code.txt ) == *"sibling's landed line"* \
           && $( cd "$ws" && git show HEAD:code.txt ) == *"this agent's own new line"* ]] && print 1 || print 0 )
    # --commits-stale is the deliberate escape, and it must be per-path and exact.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws" && git show HEAD~1:code.txt > code.txt && print -r -- "a second line of this agent's" >> code.txt )
    out=$( cd "$ws" && zsh "$here" f4 -m "$M" --commits-stale mine.txt --removes 1 code.txt 2>&1 ); rc=$?
    check "naming the WRONG path in --commits-stale is still refused" \
        $( [[ $rc == 3 && "$out" == *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" f4 -m "$M" --commits-stale code.txt --removes 1 code.txt 2>&1 ); rc=$?
    check "naming the right path lets it through deliberately" $(( rc == 0 )) "exit $rc: $out"
    check "and it says out loud that it committed something behind HEAD" \
        $( [[ "$out" == *"--commits-stale"* ]] && print 1 || print 0 ) "$out"
    # The false-positive control that decides whether this guard can live in the commit path at
    # all: an ordinary bare-path commit of a file built on HEAD must not go near a refusal.
    ( cd "$ws" && git show HEAD:code.txt > code.txt && print -r -- "an ordinary edit on top of HEAD" >> code.txt )
    out=$( cd "$ws" && zsh "$here" f5 -m "$M" code.txt 2>&1 ); rc=$?
    check "an ordinary bare-path edit built on HEAD is not refused" \
        $( [[ $rc == 0 && "$out" != *WORKTREE-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    say "         ...and it must not be disableable by the check simply not answering"
    say "         (DRIFT-CHECK-MISSING / DRIFT-CHECK-FAILED)"
    # And the guard must not be skippable by the check simply not being there. A copy of this
    # script with no `worktree-drift.sh` beside it has to REFUSE, not quietly commit unchecked --
    # "the check could not run, so everything is fine" is the hollow instrument in miniature.
    ( cd "$ws" && mkdir -p lonely && cp "$here" lonely/agent-commit.sh
      git show HEAD:code.txt > code.txt && print -r -- "a line committed with no drift check nearby" >> code.txt )
    out=$( cd "$ws" && zsh "$ws/lonely/agent-commit.sh" f6 -m "$M" code.txt 2>&1 ); rc=$?
    check "a copy with no worktree-drift.sh beside it refuses rather than skipping the check" \
        $( [[ $rc == 3 && "$out" == *DRIFT-CHECK-MISSING* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and nothing was committed by it" \
        $( [[ $( cd "$ws" && git show HEAD:code.txt ) != *"no drift check nearby"* ]] && print 1 || print 0 )
    # The same point one step along: a drift check that is THERE but fails to answer must not read
    # as "not behind". Exit 0 and exit 3 are readings; anything else is the question going
    # unanswered, and rounding that to a pass is how a guard becomes decoration without anyone
    # editing it. This one is a stub because the failure it stands for -- git unusable, the
    # sandboxed `xcrun` shim, a syntax error introduced upstream -- has no other reliable fixture.
    ( cd "$ws" && print -rl -- '#!/bin/zsh' 'print -r -- "something went wrong" >&2; exit 2' > lonely/worktree-drift.sh )
    out=$( cd "$ws" && zsh "$ws/lonely/agent-commit.sh" f7 -m "$M" code.txt 2>&1 ); rc=$?
    check "a drift check that exits neither 0 nor 3 is refused, not read as a pass" \
        $( [[ $rc == 3 && "$out" == *DRIFT-CHECK-FAILED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and nothing was committed by that one either" \
        $( [[ $( cd "$ws" && git show HEAD:code.txt ) != *"no drift check nearby"* ]] && print 1 || print 0 )
    ( cd "$ws" && rm -rf lonely && git checkout -q HEAD -- code.txt 2>/dev/null; git reset -q ) >/dev/null 2>&1

    say ""
    say " mode 4c (LEDGER-IDS-LOST) -- a ledger entry HEAD has cannot vanish inside a line count"
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    # A stale reconstruction: it keeps T-101, adds T-103, and silently loses T-102.
    ( cd "$ws"
      print -rl -- "# Ledger" "" "- [T-101] first" "  body" "" "- [T-103] third" "  body" > stale.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" TODO.md=stale.md 2>&1 ); rc=$?
    check "a dropped ledger id is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-IDS-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the id is named, not just a line count" \
        $( [[ "$out" == *"T-102"* && "$out" != *"T-101"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" --drops-ids T-101 TODO.md=stale.md 2>&1 ); rc=$?
    check "naming the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-IDS-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" --drops-ids T-102 --removes 1 TODO.md=stale.md 2>&1 ); rc=$?
    check "retiring it deliberately is allowed" $(( rc == 0 )) "exit $rc: $out"
    # And the ordinary case -- adding an entry, losing none -- must not be refused at all.
    ( cd "$ws"
      git show HEAD:TODO.md > grown.md
      print -rl -- "" "- [T-104] fourth" "  body" >> grown.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" d2 -m "$M" TODO.md=grown.md 2>&1 ); rc=$?
    check "an append-only ledger edit needs no flag" $(( rc == 0 )) "exit $rc: $out"

    say ""
    say " mode 4d (LEDGER-CLOSURE-LOST) -- a closed entry must not quietly become an open one again"
    # T-981, and the reason 4c is not enough: comparing ID SETS cannot see an entry whose TEXT went
    # back to the open ticket it was before. Reproduced from this repository's own history before
    # it was fixed -- 169d594d reverted T-679, T-719 and T-787 that way inside a commit about three
    # unrelated instruments, and every guard passed.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    # Fixture housekeeping: 4c left the worktree TODO.md holding the `T-102` line it deliberately
    # retired from HEAD, so every `=` reconstruction below would record that as a declined hunk and
    # every check in this mode would read DECLINED-HUNK-LOST instead of what it is about.
    ( cd "$ws" && git show HEAD:TODO.md > TODO.md ) >/dev/null 2>&1
    ( cd "$ws"
      git show HEAD:TODO.md > closing.md
      print -rl -- "" "- [T-105] **CLOSED 2026-09-05 (\`deadbee\`).** shipped and verified" "  body" >> closing.md
      print -rl -- "" "- [T-106] **CLOSED 2026-09-05 (\`deadbef\`).** also shipped" "  body" >> closing.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e1 -m "$M" TODO.md=closing.md 2>&1 ); rc=$?
    check "closing two entries is an ordinary append and needs no flag" $(( rc == 0 )) "exit $rc: $out"
    # The revert: same ids, same count, T-105's closure replaced by its original open text. T-106
    # stays closed, so the refusal has to name one id and not the other.
    ( cd "$ws"
      git show HEAD:TODO.md \
        | sed 's/^- \[T-105\] \*\*CLOSED.*/- [T-105] **the thing that is still not done** filed 2026-09-01/' > reopen.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e2 -m "$M" TODO.md=reopen.md 2>&1 ); rc=$?
    check "reverting a closure back to open text is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-CLOSURE-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the reopened id is named, and the still-closed one is not" \
        $( [[ "$out" == *"T-105"* && "$out" != *"T-106"* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md ) == *"T-105] **CLOSED"* ]] && print 1 || print 0 )
    # It is NOT REMOVES-HEAD-LINES wearing a different hat: that one fires here too, and firing
    # second is the whole point -- a count somebody acknowledges without reading is exactly how
    # this reverted 51 tickets' worth of text without anyone seeing a ticket in it.
    check "and it is the closure that is complained about, not the line count" \
        $( [[ "$out" != *REMOVES-HEAD-LINES* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" e2 -m "$M" --reopens-ids T-106 TODO.md=reopen.md 2>&1 ); rc=$?
    check "naming the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-CLOSURE-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" e2 -m "$M" --reopens-ids T-105 --removes 1 TODO.md=reopen.md 2>&1 ); rc=$?
    check "reopening it deliberately is allowed" $(( rc == 0 )) "exit $rc: $out"
    # The negative control that decides whether this guard is usable at all: the ordinary ledger
    # move -- an entry going from the Open section to Done, gaining its closure -- must not refuse.
    ( cd "$ws"
      git show HEAD:TODO.md \
        | sed 's/^- \[T-105\] \*\*the thing.*/- [T-105] **CLOSED 2026-09-05 (`deadc0d`).** done after all/' > close105.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e3 -m "$M" --removes 1 TODO.md=close105.md 2>&1 ); rc=$?
    check "an entry moving from open to CLOSED needs no flag" $(( rc == 0 )) "exit $rc: $out"
    # And the second control, for the narrowness of the marker: an OPEN entry whose BODY mentions
    # the word is not a closed entry, so rewriting that prose must not read as a reversion.
    # Sixteen real open tickets in docs/TODO.md say "closed above" or quote "CLOSED, FALSE
    # PREMISE"; a body-wide reading would mark all sixteen closed and then refuse the next edit to
    # any of them. The mention is written in the repository's real cross-reference form, `[[T-n]]`,
    # so this also catches a marker whose anchor has been loosened from the entry's own first line
    # to "any line naming an id". That is a false refusal in the commit path, and this is the check that decides
    # the guard is narrow enough to live there.
    ( cd "$ws"
      git show HEAD:TODO.md > mentions.md
      print -rl -- "" "- [T-107] **still open, and it stays open.**" \
                      "  Blocked on [[T-104]], which is CLOSED, FALSE PREMISE and says so above." >> mentions.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e4 -m "$M" TODO.md=mentions.md 2>&1 ); rc=$?
    check "filing an open entry whose BODY mentions the word is accepted" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws"
      git show HEAD:TODO.md | sed 's/^  Blocked on .*/  Blocked on the other one./' > rewrite.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e5 -m "$M" --removes 1 TODO.md=rewrite.md 2>&1 ); rc=$?
    check "and rewriting that prose away is NOT a lost closure" \
        $( [[ $rc == 0 && "$out" != *LEDGER-CLOSURE-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    # T-983, and it is the control that decides the marker stays one word. The two entries below
    # are the real shape of T-623 and T-624 in HEAD's docs/TODO.md: OPEN tickets whose own first
    # line says VERIFIED, where the word means the finding was confirmed real -- the opposite of
    # closed. A marker widened to `RESOLVED|VERIFIED` reads them as closures, and the next ordinary
    # rewrite of either is then refused as a reversion nobody made. Two false refusals bought for
    # two true positives; see the measurement above ledger_closed_ids().
    ( cd "$ws"
      git show HEAD:TODO.md > verified.md
      print -rl -- "" "- [T-108] **Hard list deletion walks only the local replica.** VERIFIED 2026-09-05 from CXT-018." \
                      "  Still open, still not started." \
                      "" "- [T-109] *(RESOLVED 2026-09-05 — the premise was wrong.)* filed and withdrawn" \
                      "  body" >> verified.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e6 -m "$M" TODO.md=verified.md 2>&1 ); rc=$?
    check "filing an OPEN entry whose first line says VERIFIED is accepted" $(( rc == 0 )) "exit $rc: $out"
    # The edit that decides it, and it has to be to the entry's OWN FIRST LINE -- that is where a
    # widened marker would have read a closure, and rewriting an open ticket's headline as it gets
    # refined is the commonest ledger edit there is. Under `CLOSED` alone these two were never
    # closed and nothing happens. Under `RESOLVED|VERIFIED` both were, and both just stopped being.
    ( cd "$ws"
      git show HEAD:TODO.md \
        | sed -e 's/^- \[T-108\] .*/- [T-108] **Hard list deletion walks only the local replica.** Confirmed again 2026-09-05./' \
              -e 's/^- \[T-109\] .*/- [T-109] **The premise was wrong, and here is the better description of why.**/' > verified2.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e7 -m "$M" --removes 2 TODO.md=verified2.md 2>&1 ); rc=$?
    check "and rewriting their first lines later is NOT read as reverting a closure (T-983)" \
        $( [[ $rc == 0 && "$out" != *LEDGER-CLOSURE-LOST* ]] && print 1 || print 0 ) "exit $rc: $out"
    # The positive control: the same rewrite on an entry that IS marked closed still refuses, so
    # the two checks above are narrowness and not a guard that has stopped working.
    ( cd "$ws"
      git show HEAD:TODO.md \
        | sed 's/^- \[T-106\] \*\*CLOSED.*/- [T-106] **not shipped after all** back to the open text/' > unclose.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" e8 -m "$M" TODO.md=unclose.md 2>&1 ); rc=$?
    check "while a genuinely CLOSED entry reverting to open text is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-CLOSURE-LOST*T-106* ]] && print 1 || print 0 ) "exit $rc: $out"

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

    say ""
    say " mode 5 (HEAD-MOVED) -- validating against one HEAD and committing onto another"
    # T-974, measured 2026-09-04. Every check above read `HEAD` at the moment it ran, and `headsha`
    # was captured LATER, just before commit-tree. A sibling landing in that window moved HEAD, so
    # the compare-and-swap compared the NEW head against itself and passed -- while the tree came
    # from a `read-tree` of the OLD head, silently reverting every path the sibling had just
    # committed. That is how u3's commit dropped a sibling's `T-935` while declaring no dropped id:
    # LEDGER-IDS-LOST had already run, correctly, against a HEAD that no longer existed.
    #
    # Landing a commit at a chosen instant inside another process needs that process to run our
    # code at that instant. A `git` shim on PATH is the obvious way and it does NOT work here: the
    # macOS test host is App-Sandboxed, and a sandboxed process is not allowed to EXECUTE a file it
    # just wrote into its own container -- so zsh silently skipped the shim, found the real git
    # further down PATH, and the mode passed nothing while looking fine. Measured 2026-09-04; the
    # `.raced` control below is the only reason it was not a green vacuum.
    #
    # So intercept in-process instead. zsh SOURCES $ZDOTDIR/.zshenv for every non-`-f` invocation,
    # and a shell function named `git` shadows the PATH lookup. Reading a file is not executing
    # one, so the sandbox permits it, and the interception happens inside the very process being
    # tested rather than beside it.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    print -r -- "$M" > "$ws/sibmsg"
    mkdir -p "$ws/zdot"
    print -rl -- \
        'git() {' \
        '  if [[ "$1" == write-tree && -n "$CADENCE_RACE_WS" && ! -e "$CADENCE_RACE_WS/.raced" ]]; then' \
        '    : > "$CADENCE_RACE_WS/.raced"' \
        '    ( cd "$CADENCE_RACE_WS" || exit 1' \
        '      unset GIT_INDEX_FILE' \
        '      command git show HEAD:TODO.md > TODO.md' \
        "      print -rl -- '' '- [T-935] the sibling ticket' '  body' >> TODO.md" \
        '      idx="$CADENCE_RACE_WS/sibling-index"' \
        '      GIT_INDEX_FILE=$idx command git read-tree HEAD' \
        '      b=$(command git hash-object -w -- TODO.md)' \
        '      GIT_INDEX_FILE=$idx command git update-index --add --cacheinfo "100644,$b,TODO.md"' \
        '      t=$(GIT_INDEX_FILE=$idx command git write-tree)' \
        '      c=$(command git commit-tree "$t" -p HEAD -F "$CADENCE_RACE_WS/sibmsg")' \
        '      command git update-ref HEAD "$c"' \
        '      command git rev-parse HEAD > "$CADENCE_RACE_WS/.sibsha"' \
        '    ) >/dev/null 2>&1' \
        '  fi' \
        '  command git "$@"' \
        '}' > "$ws/zdot/.zshenv"
    ( cd "$ws" && print -r -- "the racing agent's own line" >> mine.txt )
    out=$( cd "$ws" && ZDOTDIR="$ws/zdot" CADENCE_RACE_WS="$ws" zsh "$here" r1 -m "$M" mine.txt 2>&1 ); rc=$?
    check "the sibling really did land a commit inside the validation window" \
        $( [[ -e "$ws/.raced" ]] && print 1 || print 0 ) \
        "the interception never fired, so this whole mode proves nothing"
    check "HEAD moving under the validation is refused" \
        $( [[ $rc == 3 && "$out" == *HEAD-MOVED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the sibling's ledger entry is still in HEAD" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md ) == *"T-935"* ]] && print 1 || print 0 ) \
        "$( cd "$ws" && git log --oneline )"
    check "and nothing of the racing agent's own change landed" \
        $( [[ $( cd "$ws" && git show HEAD:mine.txt ) != *"racing agent"* ]] && print 1 || print 0 )
    # Not "HEAD's parent is where we started": a commit parented on the STALE head orphans the
    # sibling entirely and satisfies that reading. HEAD has to BE the sibling's commit.
    check "HEAD is exactly the sibling's commit" \
        $( [[ $( cd "$ws" && git rev-parse HEAD ) == "$(<$ws/.sibsha)" ]] && print 1 || print 0 ) \
        "$( cd "$ws" && git log --oneline )"

    # The rude sibling above skipped agent-commit.sh's shared-index repair; put the fixture back to
    # where a well-behaved one would leave it, or every later mode reads FOREIGN-STAGED.
    ( cd "$ws" && git reset -q ) >/dev/null 2>&1

    # 5b. The same race one step earlier: between reading the sha and the FOREIGN-STAGED diff. The
    # sibling's own shared-index repair leaves their paths matching the NEW head, so diffing the
    # index against OUR sha reports their landed work as somebody's foreign staged hunk -- a refusal
    # with a reason that sends the next agent to `git reset` a commit.
    print -rl -- \
        'git() {' \
        '  if [[ "$1" == rev-parse && "$2" == HEAD && $# -eq 2 && -n "$CADENCE_RACE_WS" && ! -e "$CADENCE_RACE_WS/.raced" ]]; then' \
        '    local _out _rc' \
        '    _out=$(command git "$@"); _rc=$?' \
        '    : > "$CADENCE_RACE_WS/.raced"' \
        '    ( cd "$CADENCE_RACE_WS" || exit 1' \
        '      unset GIT_INDEX_FILE' \
        '      command git show HEAD:theirs.txt > theirs.txt' \
        "      print -r -- 'the sibling landed this' >> theirs.txt" \
        '      idx="$CADENCE_RACE_WS/sibling-index"' \
        '      GIT_INDEX_FILE=$idx command git read-tree HEAD' \
        '      b=$(command git hash-object -w -- theirs.txt)' \
        '      GIT_INDEX_FILE=$idx command git update-index --add --cacheinfo "100644,$b,theirs.txt"' \
        '      t=$(GIT_INDEX_FILE=$idx command git write-tree)' \
        '      c=$(command git commit-tree "$t" -p HEAD -F "$CADENCE_RACE_WS/sibmsg")' \
        '      command git update-ref HEAD "$c"' \
        '      command git reset -q -- theirs.txt' \
        '    ) >/dev/null 2>&1' \
        '    print -r -- "$_out"; return $_rc' \
        '  fi' \
        '  command git "$@"' \
        '}' > "$ws/zdot/.zshenv"
    rm -f "$ws/.raced"
    ( cd "$ws" && print -r -- "another line of the racing agent's" >> mine.txt )
    out=$( cd "$ws" && ZDOTDIR="$ws/zdot" CADENCE_RACE_WS="$ws" zsh "$here" r2 -m "$M" mine.txt 2>&1 ); rc=$?
    check "the earlier race really happened too" \
        $( [[ -e "$ws/.raced" ]] && print 1 || print 0 ) "the interception never fired"
    check "it is refused as HEAD-MOVED, not as the sibling's foreign staged hunk" \
        $( [[ $rc == 3 && "$out" == *HEAD-MOVED* && "$out" != *FOREIGN-STAGED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the sibling's commit is untouched" \
        $( [[ $( cd "$ws" && git show HEAD:theirs.txt ) == *"the sibling landed this"* ]] && print 1 || print 0 )

    # Fixture housekeeping, not a finding: the interception above is a deliberately RUDE sibling -- it
    # moves HEAD by plumbing and skips the shared-index repair a real agent-commit.sh run does at
    # step 6. So the fixture's shared index is left holding the pre-race TODO.md blob, which every
    # later mode would read as FOREIGN-STAGED. Put it back to where a well-behaved sibling would.
    ( cd "$ws" && git reset -q ) >/dev/null 2>&1

    say ""
    say " mode 6 (DECLINED-HUNK-STALE / DECLINED-HUNKS-OUTSTANDING) -- a record nobody clears must"
    say "         stop something, and \`check\` must be able to fail"
    # T-781. The DECLINED-HUNK-LOST guard is per-path and fires on the NEXT commit of that path.
    # A record for a path nobody touches again fires nothing, and `status` only helps someone who
    # remembers to run it. Two records survived a whole run exactly that way. So: an aged record
    # refuses the next commit by ANY agent, and `check` fails while any record is outstanding.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws"
      git show HEAD:shared.txt > shared.txt
      print -r -- "an abandoned in-flight line" >> shared.txt
      git show HEAD:shared.txt > recon6.txt
      print -r -- "agent six's own line" >> recon6.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" s6 -m "$M" shared.txt=recon6.txt 2>&1 ); rc=$?
    check "a record exists to age" \
        $( [[ $rc == 0 && -n $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 ) "exit $rc: $out"
    # Fresh: an unrelated commit must sail straight through. A guard that blocks the ordinary
    # in-flight case would just be a serialisation of the batch.
    ( cd "$ws" && print -r -- "unrelated one" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" s6 -m "$M" mine.txt 2>&1 ); rc=$?
    check "a FRESH record blocks an unrelated commit not at all" $(( rc == 0 )) "exit $rc: $out"
    # Aged: the same unrelated commit is refused, and the refusal names the path that is stuck.
    local aged; aged=$(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N) | head -1)
    touch -t $(date -v-90M +%Y%m%d%H%M) "$aged"
    ( cd "$ws" && print -r -- "unrelated two" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" s7 -m "$M" mine.txt 2>&1 ); rc=$?
    check "an AGED record refuses a commit of a path it has nothing to do with" \
        $( [[ $rc == 3 && "$out" == *DECLINED-HUNK-STALE* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and it names the stuck path and the line" \
        $( [[ "$out" == *shared.txt* && "$out" == *"abandoned in-flight line"* ]] && print 1 || print 0 ) "$out"
    check "nothing of the refused commit landed" \
        $( [[ $( cd "$ws" && git show HEAD:mine.txt ) != *"unrelated two"* ]] && print 1 || print 0 )
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "check exits non-zero while a record is outstanding" \
        $( [[ $rc == 3 && "$out" == *DECLINED-HUNKS-OUTSTANDING* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" accept nosuch.txt 2>&1 ); rc=$?
    check "accept refuses a path with no record" \
        $( [[ $rc == 3 && "$out" == *UNKNOWN-PATH* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" accept shared.txt 2>&1 ); rc=$?
    check "accept clears the record deliberately" \
        $( [[ $rc == 0 && -z $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and it quotes what it threw away" \
        $( [[ "$out" == *"abandoned in-flight line"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" check 2>&1 ); rc=$?
    check "check passes once the ledger is empty" $(( rc == 0 )) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" s8 -m "$M" mine.txt 2>&1 ); rc=$?
    check "and the unrelated commit goes through again" $(( rc == 0 )) "exit $rc: $out"

    say ""
    say " mode 7 -- a REFUSED commit must not spend the declined-hunk record it was going to clear"
    # The record used to be deleted while the checks were still running, so any refusal after that
    # point -- REMOVES-HEAD-LINES, LEDGER-IDS-LOST, and since T-974 HEAD-MOVED, which a racing
    # agent hits and then RETRIES -- left the retry running with the protection already spent.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws"
      git show HEAD:shared.txt > shared.txt
      print -r -- "mode7 in-flight line" >> shared.txt
      git show HEAD:shared.txt > recon7.txt
      print -r -- "mode7 owner line" >> recon7.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" s9 -m "$M" shared.txt=recon7.txt 2>&1 ); rc=$?
    check "a record is written for mode 7" \
        $( [[ $rc == 0 && -n $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 ) "exit $rc: $out"
    # Folds the declined line back in (so DECLINED-HUNK-LOST is satisfied and the record is queued
    # for clearing) but also drops a line HEAD has, so the commit is refused after that point.
    ( cd "$ws"
      git show HEAD:shared.txt | sed '1d' > refused7.txt
      print -r -- "mode7 in-flight line" >> refused7.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" sa -m "$M" shared.txt=refused7.txt 2>&1 ); rc=$?
    check "the commit is refused for removing a line HEAD has" \
        $( [[ $rc == 3 && "$out" == *REMOVES-HEAD-LINES* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the record it would have cleared is STILL THERE" \
        $( [[ -n $(print -rl -- "$CADENCE_DECLINED_LEDGER"/*.declined(N)) ]] && print 1 || print 0 ) \
        "the refused commit consumed the record; the retry would drop the hunk unprotected"
    # The proof that it still protects: dropping the declined line is refused, exactly as before.
    ( cd "$ws" && git show HEAD:shared.txt > drop7.txt && print -r -- "sb's line" >> drop7.txt )
    out=$( cd "$ws" && zsh "$here" sb -m "$M" shared.txt=drop7.txt 2>&1 ); rc=$?
    check "so dropping the declined hunk is still refused after the failed commit" \
        $( [[ $rc == 3 && "$out" == *DECLINED-HUNK-LOST*"mode7 in-flight line"* ]] && print 1 || print 0 ) "exit $rc: $out"
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)

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
    check)    shift; cmd_check "$@"; exit $? ;;
    accept)   shift; cmd_accept "$@"; exit $? ;;
    -h|--help) usage; exit 0 ;;
esac
if (( $# < 2 )); then usage; exit 2; fi
cmd_commit "$@"
