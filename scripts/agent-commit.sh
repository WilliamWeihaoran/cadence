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
#   LEDGER-ID-UNARCHIVED an id `--drops-ids` retires from a `TODO.md` is in no `TODO_DONE.md` as
#                        this commit leaves it. The flag says the removal was deliberate; it does
#                        not say where the ticket WENT, and an entry normally leaves the open list
#                        by MOVING to the archive. `--retires-ids <exact,sorted,list>` says the id
#                        is being struck off rather than archived (T-1148).
#   LEDGER-CLOSURE-LOST  a `TODO.md` entry that is CLOSED in HEAD is open again in the content you
#                        are staging, with its id intact -- so LEDGER-IDS-LOST sees nothing wrong.
#                        `--reopens-ids <exact,sorted,list>` reopens them deliberately.
#   LEDGER-ENTRY-DUPLICATED
#                        a ledger entry in the content you are staging contains its own body twice
#                        -- a closure APPENDED to the draft it was meant to replace, so the entry
#                        asserts both at once. `--duplicated-entries <exact,sorted,list>` says the
#                        repetition is deliberate. Delta-read against HEAD: only an entry this
#                        commit duplicates, or duplicates further, is refused (T-1142).
#   WORKTREE-BEHIND-HEAD a bare `<path>` whose worktree copy is built on a revision older than
#                        HEAD's. Committing it writes the stale bytes into history, where no drift
#                        check looks. Rebuild on `git show HEAD:<path>` and pass the `=` form, or
#                        `--commits-stale <path>` if the old content really is what you mean.
#   REBUILD-BEHIND-HEAD  the same finding about a `<path>=<content-file>` reconstruction: the
#                        content file itself was built on an older revision. Same escape hatch.
#                        This is the diagnosis for the count REMOVES-HEAD-LINES would otherwise
#                        give you one step later, and it names the sha to rebuild on.
#   SWEEP-MANIFEST-MISSING
#                        a `CadenceTests/*.swift` this commit stages declares a `@Test` that walks
#                        the real product tree and is not on `CadenceRealTreeSweepManifest.txt`, so
#                        deleting that test later would stop an app-wide sweep with nothing going
#                        red (T-808). Regenerate with `real-tree-sweep-manifest.sh <id> --write` and
#                        add the file to this commit. `--not-a-sweep <name>` is the escape, and it
#                        should only ever be needed if the cheap precheck and the authoritative
#                        Swift scan have drifted apart -- which is itself worth a ticket (T-1092).
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
# BOTH FORMS ARE ASKED WHERE THEY WERE BUILT (T-982 for the bare one, T-992 for the `=` one)
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
# The `=` form was deliberately not checked at first, for a reason that turned out to be about the
# wrong comparison (T-992). Rebuilding the file as `git show HEAD:<path>` plus your own edits IS
# the prescribed repair for this drift, and its content is by definition not the WORKTREE's -- so a
# check against the worktree would have refused the fix and left only the broken path open. But the
# reading is against HISTORY, and there it separates cleanly:
#
#   rebuilt on HEAD                 contains every line HEAD has -> `inflight`, settled by the first
#                                   comparison, before any revision walk happens.
#   rebuilt on HEAD, lines deleted  no revision is wholly contained -> `cannot-tell`, never refused;
#                                   T-984's blind spot, unchanged and still the safe direction.
#   built on an OLDER revision      -> `behind`, which is the only shape it can name, and the bug.
#
# So the cure is not refused and the mistake is. This matters because the `=` form is what an agent
# is TOLD to reach for by the bare form's own refusal -- the commonest single way a stale file gets
# reconstructed here is an agent repairing one refusal and rebuilding on the wrong sha while doing
# it. Measured 2026-09-05 against a throwaway repository: a content file built two commits back was
# refused as `REMOVES-HEAD-LINES ... --removes 2` and nothing asked, or said, which revision it had
# been built from.
#
# THE DECLARED-ID FLAGS ACTUALLY TAKE THE LIST THEY DOCUMENT (T-1143)
#
# Every `--<something>-ids` flag above documents `<exact,sorted,list>`, and until 2026-09-12 the
# script could not produce or accept one. Both sides were built as `${(j:,:)${(o)$arr}}` -- with no
# `(@)`, so the array is flattened to one scalar BEFORE the sort and the join, and each is a no-op
# on a single element. The hint printed the detection order, space-separated.
#
# It never surfaced for two reasons, and both are worth keeping. Every existing list is fed by
# `comm` or `sort -u`, so it arrives lexicographically sorted and the absent sort was invisible;
# and the selftest declares exactly ONE id in all twelve places it exercises these flags, where a
# sort and a comma-join are both indistinguishable from doing nothing. 144 checks passed over it.
#
# The first list NOT fed by a sorted source was LEDGER-ENTRY-DUPLICATED's, which reads entries in
# file order, and it printed `T-992 T-991 T-986 T-781` -- unsorted, and refusing the comma form its
# own message documented. Fixed at all six sites rather than the new one; the five older ones are
# unchanged in behaviour, since a sorted input sorts to itself. Mode 4g pins a MULTI-id declaration.

# THE DELIBERATE OVERRIDE LEAVES A TRACE (T-991)
#
# `--commits-stale <path>` says "the older content really is what I mean". It used to say it to
# nobody: unlike a declined hunk, which writes a record under $TMPDIR that `check` fails over, it
# wrote nothing at all, so a batch could not afterwards answer *did anyone knowingly commit a copy
# behind HEAD, and on which path*. That question is how all four measured instances of T-975 were
# found. Each overridden path now adds a `Commits-Stale: <path> built-on <sha>` trailer to the
# commit message, immediately above the Co-Authored-By line: `git log --grep=Commits-Stale` answers
# it from any clone, forever, and the base sha makes it answerable in detail rather than in the
# abstract. It is not a declined-hunk record -- those mean somebody still has to act, and `check`
# fails while one exists; this is a settled decision, and recording it as outstanding work would
# make `check` fail over something already decided.
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
    say "              --retires-ids <ids>"
    say "              --unfiled-ids <ids> --buried-closures <ids> --duplicate-ids <ids>"
    say "              --duplicated-entries <ids>"
    say "              --accept-declined <path> --commits-stale <path> --not-a-sweep <@Test name>"
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
# There is deliberately no narrower `is_ledger_path` beside `is_any_ledger_path` (T-1145). One
# existed, matching `TODO.md` alone, and its only two callers -- LEDGER-IDS-LOST and
# LEDGER-CLOSURE-LOST -- were the two guards that consequently could not see the archive. A second
# predicate one word apart from the right one is a trap for whoever writes the next guard.

# T-981. LEDGER-IDS-LOST compares ID SETS, and that is one level too shallow. An entry whose text
# reverts from its closure back to the original open ticket keeps its id, so the id sets are equal
# and the guard passes -- while the ledger now says a shipped ticket is not started. Two measured
# instances, found by replaying every commit that has ever touched that file:
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
# Replayed over the WHOLE history of docs/TODO.md -- every commit that has ever touched it, not a
# sample -- this reading fires on exactly those two and on nothing else. Re-derived 2026-09-12 at
# `17b5b61`, and it still names 169d594d and f566723b alone.
#
# The number of commits that was is deliberately not written down here, and that is T-1146: this
# line used to say "all 349 ... none of the other 347", true on 2026-09-05 and simply wrong now,
# while another header five hundred lines below said 428 about the same population on the same day.
# That population is `git log --format=%H -- docs/TODO.md`; it grows several times a session, and
# it moved 429 -> 430 -> 431 across the two sessions that noticed. A denominator frozen in a
# comment can only rot. What does not rot is the QUESTION and the ANSWER -- replay the file's whole
# history, and these are the two commits it names. Whoever re-runs it supplies their own count.
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
# (Both of those two have since closed -- T-624 on 2026-09-10, T-623 on 2026-09-11, each as a
# recorded decision rather than a repair -- so the counterexample above is now history rather than
# a live pair. The measurement still decides the question: it is about what the word MEANT in an
# open entry, and nothing has established the alternative convention T-983 said would be needed.)
#
# So there is no `RESOLVED`/`VERIFIED` closure CONVENTION to read here -- there are two instances
# and two counterexamples that use the same word to mean "confirmed open". The alternative the
# ticket allows, establishing a convention the ledger then follows, is a rewrite of 118 unmarked
# Done entries and is not this script's to make. The narrowness is the finding. Mode 4d's last two
# checks pin it: an OPEN entry whose own first line says VERIFIED must stay editable.
ledger_closed_ids() {  # $1 = file
    sed -n 's/^- \[\(T-[0-9][0-9]*\)\].*CLOSED.*/\1/p' -- "$1" 2>/dev/null | sort -u
}

# T-1106, and it is the OTHER side of the anchor ledger_closed_ids() just spent eighty lines
# defending. That reading is correct and stays; what nothing checked is whether the ledger actually
# WRITES its closures where the reading looks. An agent that puts the closure sentence in the
# middle of an entry has closed nothing any instrument can see -- the first line still carries the
# original finding, so the entry reads open to `ledger_closed_ids`, to LEDGER-CLOSURE-LOST, and to
# the next agent scanning for work. [[T-1085]] sat in exactly that state for five days after it
# shipped, and was picked up again by an agent who read its first line.
#
# Measured against HEAD's docs/TODO.md on 2026-09-11, over 471 entries: **fourteen** entries were
# buried this way -- T-565, T-661, T-689, T-690, T-691, T-693, T-694, T-755, T-777, T-782, T-986,
# T-991, T-992, T-1074. Not a hypothetical; a standing population, driven to zero in the same
# commit that added this so the guard is enforceable at zero rather than baselined.
#
# The marker is narrow for the same reason the one above is, and the narrowness is measured rather
# than asserted: a BOLD RUN OPENING the line (`**CLOSED`, `**PARTIALLY CLOSED`, `**FULLY CLOSED`),
# never the word loose in prose. Over those same 471 entries that reading names the fourteen and
# nothing else. In particular it does NOT name T-985, whose body says *"deleted the CLOSED copy"*
# about a different ticket, and it does not name T-992's own body sentence *"first line to
# `**CLOSED <date>`"*, which quotes the convention mid-line rather than opening with it. Both are
# false refusals in the commit path, which is the failure this family must not have.
ledger_buried_closure_ids() {  # $1 = file
    awk '
        /^- \[T-[0-9]+\]/ {
            id = $0; sub(/^- \[/, "", id); sub(/\].*$/, "", id)
            inopen = ($0 ~ /^- \[T-[0-9]+\] \*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/) ? 0 : 1
            next
        }
        /^[^ \t]/ { inopen = 0; next }
        inopen && /^[ \t]+\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/ { print id; inopen = 0 }
    ' "$1" 2>/dev/null | sort -u
}

# T-1106's other half, and the one the ticket called the valuable one. The ledger IS the id
# allocator ([[T-1072]]): an id that lives only in a commit message or in another entry's prose is
# invisible to the next agent computing "next free", which is how `T-1119` was allocated twice in
# one week and how `T-1117` was handed out inside T-624's closure with no stub behind it.
#
# So: every `T-<n>` this commit's MESSAGE names must have a formal `- [T-<n>]` entry in a ledger,
# as this commit leaves it. Reading the message rather than the diff is deliberate -- that is the
# one artefact every commit has, and it is where the id was recorded in all eight measured cases.
#
# THE QUESTION, and the answer dated rather than a denominator that rots (T-1146): replay every
# commit reachable from HEAD, take the ids its message names, and ask whether each has a formal
# `- [T-n]` entry in either ledger. Re-derived 2026-09-12 at `60c69b6`: 834 distinct ids appear in
# a commit message and **172** have no formal entry anywhere.
#
# That 172 is not an alarm and the SHAPE is the reason -- 162 of them are `T-441` or below, inside
# the ~200-ticket deficit T-462 measured and decided not to backfill. Above T-462's line the set
# was ten: T-734, T-768, T-849, T-879, T-880, T-1039, T-1064, T-1079 (the eight T-1123 named) plus
# T-1155 and T-1156, which arrived through this guard's own `--unfiled-ids` escape one day after
# T-1123 counted the eight. All ten, and T-441 with them, are now formal entries under
# `## Recovered from history` in docs/TODO_DONE.md, so above the baseline the population is ZERO
# and this guard is enforceable at zero rather than in front of a standing backlog.
#
# An earlier revision of this header said "796 distinct ids ... and eight of them", which was the
# right eight and the wrong reading: it stated the modern tail without stating that a line had been
# drawn at T-462, so re-running the obvious query gave 172 and the number looked like a lie. Same
# lesson as T-1146 -- a count in front of a reader has to carry its population.
#
# Historical ids remain out of reach BY CONSTRUCTION and that is deliberate: this asks only about
# the message in front of it, which is what keeps it usable. The half it does not implement -- an
# id that lives only in another entry's prose, said two paragraphs up -- is T-1206.
message_ids() {  # $1 = message
    print -r -- "$1" | grep -oE '\bT-[0-9]+\b' | sort -u
}
is_any_ledger_path() { [[ "${1:t}" == "TODO.md" || "${1:t}" == "TODO_DONE.md" ]] }

# T-1142, and it is the third failure of the same closure-writing step LEDGER-CLOSURE-BURIED
# guards. That one asks whether the closure was written where the anchor looks. This asks whether
# writing it REPLACED the draft it was meant to replace, or was appended underneath it.
#
# The shape: an entry closed while its work sat in a checkout carries a progress note --
# `**RESOLVED IN THE CHECKOUT <date>, NOT YET IN HEAD**` -- and when it finally lands the agent
# pastes the closure in rather than editing the note out. The entry then says CLOSED on its first
# line and "not yet in HEAD" in its body, with the same paragraphs twice, and every instrument is
# satisfied: the id is present so LEDGER-IDS-LOST passes, the first line is a closure so
# LEDGER-CLOSURE-LOST and LEDGER-CLOSURE-BURIED pass, and the line count only ever went UP so
# REMOVES-HEAD-LINES has nothing to say. Nothing in this script reads an entry against itself.
#
# Measured on HEAD 2026-09-12 over 482 entries: FOUR are in this state -- T-781, T-986, T-991 and
# T-992 -- and all four were created by one commit, `7584c5f`, which landed those same tickets.
# They have survived 40 subsequent commits of this file unread. T-992 carries 33 duplicated lines
# and a "NOT YET IN HEAD" claim that has been false since the moment it was written.
#
# The reading is the longest run of CONSECUTIVE body lines that appears twice in one entry, and
# only lines of >= 40 trimmed characters count -- a short line repeats legitimately (a bare
# `**CLOSED ...**`, a list marker), a paragraph does not. Over those 482 entries the distribution
# is 477 entries at zero, ONE at two (T-624, two prose lines it genuinely says twice), and then the
# four defects at 10, 11, 15 and 33. A minimum run of four sits in that gap with a factor of five
# of margin on each side; it is not a tuned number, it is the only number the gap admits.
LEDGER_DUP_MIN_RUN=4
ledger_selfduplicated_ids() {  # $1 = file, $2 = minimum run length; prints "<id>\t<run>"
    awk -v thresh="${2:-4}" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function flush(   i, j, k, best) {
            best = 0
            for (i = 1; i <= n; i++) {
                for (j = i + 1; j <= n; j++) {
                    if (body[i] != body[j]) continue
                    # Only seed MAXIMAL runs. Without this an entry of N identical lines seeds
                    # N^2/2 pairs and each extends O(N); with it, one. Measured on a 400-line
                    # all-identical entry: 4.3s -> 0.03s, same answer.
                    if (i > 1 && body[i - 1] == body[j - 1]) continue
                    k = 0
                    while (j + k <= n && body[i + k] == body[j + k]) k++
                    if (k > best) best = k
                }
            }
            if (id != "" && best >= thresh) printf "%s\t%d\n", id, best
            n = 0; id = ""
        }
        /^- \[T-[0-9]+\]/ {
            flush()
            id = $0; sub(/^- \[/, "", id); sub(/\].*$/, "", id)
            next
        }
        # A section heading, or any other column-zero line, ends the entry it follows.
        /^[^ \t]/ && NF { flush(); next }
        {
            if (id == "") next
            n++
            # Short lines are made unique, so they can neither seed a run nor extend one.
            body[n] = (length(trim($0)) >= 40) ? trim($0) : ("\001" n)
        }
        END { flush() }
    ' "$1" 2>/dev/null
}

# T-1072, and this is the half the previous two guards do not reach. LEDGER-ID-UNFILED asks whether
# an id in a commit message has an entry; it cannot ask whether that entry is the SECOND one. The
# ticket's own shape is "two agents read `next free` before either committed": both then write a
# stub for the same id, both messages name a filed id, and LEDGER-ID-UNFILED passes both. The only
# artefact the collision leaves anywhere is a ledger with two formal `- [T-n]` entries for one id,
# and until now nothing read it.
#
# WHY THE READING IS A DELTA AND NOT THE WHOLE FILE, which is the opposite of the choice T-1106
# made one function up, and the difference is not taste:
#
#   * The event being guarded IS a single commit. An id is allocated once; "did THIS commit hand
#     out an id that was already handed out" is the literal question, and a whole-file reading
#     answers a different one.
#   * HEAD carries three standing duplicates -- T-781, T-974 and T-1043 -- and they are not all
#     fixable. T-781 and T-974 each have a closure filed as a NEW entry with the original open copy
#     left behind, so one id reads open and closed at once. T-1043 is two genuinely different
#     tickets (an image fix and a calendar-link one), and T-1072 decided in as many words: **"Fix
#     the allocator, not the three collisions."** Renumbering either would orphan every `[[T-1043]]`
#     reference in the ledger. A whole-file reading would therefore refuse every future commit to
#     docs/TODO.md until a fix the ticket forbids had been made -- a permanent false refusal in the
#     commit path, which is the one failure this family must not have.
#
# MEASURED, by replaying every commit that has ever touched either ledger and asking each one
# whether it introduced a duplicate its parent did not have. **436 commits, 7 refusals:**
#
#   939959e  2026-09-11  T-1119   the incident this ticket was re-filed over: one id, two agents,
#                                 both having read the same "next free" before either committed.
#   be10dd4  2026-09-07  T-1109   `importgraph` and `importedge` reserved the SAME TWO ids on the
#                        T-1110   same day for unrelated findings. Not previously recorded anywhere.
#   dcb0a15  2026-09-05  T-1043   the collision T-1072's own entry names.
#   988d7cb  2026-09-04  T-781    a closure filed as a new entry, the open original left in place,
#                        T-974    so `ledger_closed_ids` says closed and a top-down reader says open.
#   022ab0e  2026-09-03  T-777    the duplication `f566723b` later deduped by hand (see T-981 above).
#   b05869d  2026-08-29  33 ids   **the entire file was committed twice** -- two `# Cadence - task
#                                 list` headers, two `## Open` sections, 719 lines apart, byte for
#                                 byte identical. It landed in history and nothing said a word.
#   e322be1  2026-08-31  T-572    the ONE false refusal. A prerequisite note was written in entry
#                                 form (`- [T-572] *(**PREREQUISITE ADDED...`) above the real
#                                 ticket. Nobody allocated T-572 twice; an annotation borrowed the
#                                 entry syntax. Recorded rather than tuned away: narrowing the
#                                 pattern to exclude a `*(` second line would also stop reading the
#                                 shape b05869d landed in, which is the worst of the seven.
#
# So: 6 true, 1 false in 436 replayed commits, against LEDGER-ID-UNFILED's 1 in 60. The flag is
# `--duplicate-ids`, and the T-572 shape is what it is for.
ledger_duplicate_ids() {  # $1... = ledger files, read as one ledger
    grep -h -oE '^- \[T-[0-9]+\]' -- "$@" 2>/dev/null | sed 's/^- \[//; s/\]$//' | sort | uniq -d
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
    local declared_retired_ids=""
    local declared_unfiled_ids="" declared_buried_ids="" declared_duplicate_ids=""
    local declared_duplicated_entries=""
    local -a paths accepted stale_declared not_sweeps
    paths=(); accepted=(); stale_declared=(); not_sweeps=()

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
            --retires-ids) [[ $# -ge 2 ]] || refuse BAD-OPTION "--retires-ids needs a comma-separated id list"
                declared_retired_ids="$2"; shift 2 ;;
            --unfiled-ids) [[ $# -ge 2 ]] || refuse BAD-OPTION "--unfiled-ids needs a comma-separated id list"
                declared_unfiled_ids="$2"; shift 2 ;;
            --buried-closures) [[ $# -ge 2 ]] || refuse BAD-OPTION "--buried-closures needs a comma-separated id list"
                declared_buried_ids="$2"; shift 2 ;;
            --duplicate-ids) [[ $# -ge 2 ]] || refuse BAD-OPTION "--duplicate-ids needs a comma-separated id list"
                declared_duplicate_ids="$2"; shift 2 ;;
            --duplicated-entries) [[ $# -ge 2 ]] || refuse BAD-OPTION "--duplicated-entries needs a comma-separated id list"
                declared_duplicated_entries="$2"; shift 2 ;;
            --commits-stale) [[ $# -ge 2 ]] || refuse BAD-OPTION "--commits-stale needs a path"
                stale_declared+=("$2"); shift 2 ;;
            --not-a-sweep) [[ $# -ge 2 ]] || refuse BAD-OPTION "--not-a-sweep needs a @Test name"
                not_sweeps+=("$2"); shift 2 ;;
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

    # 1b. T-982 (bare form) and T-992 (the `=` form). Every guard below this line asks a question
    #     about the CONTENT being staged. None of them asks WHERE THAT CONTENT WAS BUILT, and both
    #     path forms can be built somewhere stale. Ask before the content questions, because "built
    #     on an older revision, and here is which one" is the diagnosis, and REMOVES-HEAD-LINES --
    #     which fires on this shape too, one step later -- is the symptom plus a cure that makes it
    #     worse (it prints `--removes 2`, and typing it drops the two lines a sibling landed).
    #
    #     One implementation, not a near-copy: `worktree-drift.sh` is the same reading the tree gate
    #     uses, asked about one path. It is handed `$headsha` rather than resolving HEAD itself, so
    #     it answers about the same commit as every check either side of it (T-974).
    #
    #     WHY THE `=` FORM IS ASKED TOO, HAVING BEEN EXEMPT (T-992). It was exempt because it is the
    #     prescribed repair for the bare form's refusal, and a check that refused the cure would
    #     leave only the broken path open. That reasoning was about comparing against the WORKTREE,
    #     which a reconstruction differs from by construction. This reading is against HISTORY:
    #
    #       a genuine rebuild on `git show HEAD:<path>`  contains every line HEAD has -> `inflight`,
    #                                                    settled by the first comparison, no walk.
    #       a rebuild that also deletes lines            no revision is contained -> `cannot-tell`,
    #                                                    never refused (T-984's blind spot, intact).
    #       an OLD revision plus edits                   -> `behind`. That is the bug, and it is the
    #                                                    only shape this can name.
    #
    #     Measured 2026-09-05 in a throwaway repository, on the shape the `=` form actually fails
    #     in: a content file built on `git show <HEAD~2>:shared.txt` plus one new line was refused
    #     as `REMOVES-HEAD-LINES: removes 2 line(s) ... --removes 2` -- a count, and an invitation
    #     to type the number that drops a sibling's work. Nothing anywhere asked which revision the
    #     file had been reconstructed from, which is the one fact that names the mistake.
    local drift_script="${SCRIPT_PATH:h}/worktree-drift.sh"
    [[ -f "$drift_script" ]] || refuse DRIFT-CHECK-MISSING "$drift_script is not there, so the drift check cannot run.
  Skipping it silently is how a guard becomes decoration; restore the script. There is no path form
  that skips this check any more: both \`<path>\` and \`<path>=<content-file>\` are asked (T-992)."
    local -a stale_found stale_report stale_recon stale_audit
    stale_found=(); stale_report=(); stale_recon=(); stale_audit=()
    # NOT `subject`: this function already declares one further down for the commit subject, and a
    # second bare `local subject` in the same scope makes zsh PRINT the parameter rather than
    # redeclare it -- `subject='worktree-drift.sh base-content ...'` on stdout, mid-commit.
    local reading drc drift_call kind
    for name in "${names[@]}"; do
        git cat-file -e "$headsha:$name" 2>/dev/null || continue   # not in HEAD: nothing to be behind
        src="${source_of[$name]}"
        if [[ -n "$src" ]]; then
            drift_call="worktree-drift.sh base-content $name $src"
            reading=$(zsh "$drift_script" base-content "$name" "$src" "$headsha" 2>/dev/null); drc=$?
        else
            [[ -f "$name" ]] || continue                            # a deletion in flight
            drift_call="worktree-drift.sh base $name"
            reading=$(zsh "$drift_script" base "$name" "$headsha" 2>/dev/null); drc=$?
        fi
        # 0 and 3 are readings. Anything else is the check failing to run, and a guard that reads
        # a crash as "fine" is the hollow instrument this whole file exists to avoid.
        (( drc == 0 || drc == 3 )) || refuse DRIFT-CHECK-FAILED "\`$drift_call\` exited $drc and said: ${reading:-(nothing)}
  Nothing was committed, because the question of whether $name is behind HEAD went unanswered."
        [[ "$(print -r -- "$reading" | cut -f1)" == behind ]] || continue
        kind=$(print -r -- "$reading" | cut -f2)
        # WHICH KIND THE `=` FORM IS REFUSED FOR, AND WHY ONLY ONE (T-992).
        #
        #   stale base  an older revision with the agent's OWN edits on top. That is the measured
        #               failure: a rebuild aimed at HEAD that was aimed at the wrong sha, with the
        #               work it was made for sitting on it, so the revert hides inside real work.
        #               Refused.
        #   stale copy  the content file's bytes ARE an older revision, with nothing of the agent's
        #               in it. A mistaken rebuild cannot look like this -- it always carries the
        #               edits it was made for -- so through the `=` form this is somebody reverting
        #               a path on purpose, and REMOVES-HEAD-LINES already names every line it drops.
        #               Reported, not refused. Selftest mode 4b (`cut.txt`) is exactly this shape.
        #
        # The bare form keeps both: a stale COPY in the worktree is T-975's commonest shape, has no
        # local work to lose, and `worktree-drift.sh repair` is a cure the `=` form has no use for.
        if [[ -n "$src" && "$kind" != "stale base" ]]; then
            say "note: $name=$src holds an older revision's bytes exactly [$kind] -- $(print -r -- "$reading" | cut -f4)"
            say "      Not refused: nothing of yours is on top of it, so this reads as a deliberate revert."
            continue
        fi
        stale_found+=("$name")
        stale_report+=("$name  [$kind]  $(print -r -- "$reading" | cut -f4)")
        # The base sha, for T-991's trailer. Field 3 of the machine-readable reading.
        stale_audit+=("$name built-on $(print -r -- "$reading" | cut -f3)")
        [[ -n "$src" ]] && stale_recon+=("$name")
    done
    if (( ${#stale_found} )); then
        local -a undeclared undeclared_recon
        undeclared=(); undeclared_recon=()
        # `spec2` is declared HERE and not in the loop: see T-1074. A bare `local x` whose
        # parameter is already local prints `x=<value>` instead of redeclaring it, so with two
        # stale paths in one commit this put `spec2=<the second path>` on stdout above the
        # refusal. Measured 2026-09-06, in this exact loop.
        local declaredp reconp spec2
        for name in "${stale_found[@]}"; do
            declaredp=0; reconp=0
            for spec2 in "${stale_declared[@]}"; do [[ "$spec2" == "$name" ]] && declaredp=1; done
            (( declaredp )) && continue
            for spec2 in "${stale_recon[@]}"; do [[ "$spec2" == "$name" ]] && reconp=1; done
            if (( reconp )); then undeclared_recon+=("$name"); else undeclared+=("$name"); fi
        done
        if (( ${#undeclared_recon} )); then
            refuse REBUILD-BEHIND-HEAD "these reconstructions were built on a revision older than HEAD: ${(j:, :)undeclared_recon}
$(print -rl -- "${stale_report[@]}" | sed 's/^/    /')
  The \`<path>=<content-file>\` form is the repair for a stale worktree copy, and this one was
  itself rebuilt on stale bytes -- \`git show <an older sha>:<path>\` rather than
  \`git show ${headsha[1,8]}:<path>\`. Committing it reverts every line that landed in between.
  This is the diagnosis for the count you would otherwise be given one step later: a copy behind
  HEAD is missing lines HEAD has by construction, so REMOVES-HEAD-LINES fires on this shape too,
  names a number, and invites you to type it. The number is the symptom.
  Rebuild the content file on \`git show ${headsha[1,8]}:<path>\` plus only your own edits.
  If the older content really is what you mean to commit: --commits-stale <path>"
        fi
        if (( ${#undeclared} )); then
            refuse WORKTREE-BEHIND-HEAD "these bare paths hold content HEAD has moved past: ${(j:, :)undeclared}
$(print -rl -- "${stale_report[@]}" | sed 's/^/    /')
  A bare \`<path>\` stages the worktree copy, and this checkout drifts behind HEAD by design: a
  commit lands through a private index and never writes the checkout (T-975). Committing this copy
  puts the stale bytes in HEAD, where no drift check looks, and every later reader inherits them.
  A [stale copy] has nothing local in it:  ./scripts/worktree-drift.sh repair
  A [stale base] has your edits on an old one -- rebuild them on \`git show ${headsha[1,8]}:<path>\`
  and pass that file as \`<path>=<content-file>\`. That form is checked the same way (T-992), so
  rebuilding on the wrong sha is refused rather than accepted.
  If the older content really is what you mean to commit: --commits-stale <path>"
        fi
        say "note: committing a path that is behind HEAD at your request (--commits-stale): ${(j:, :)stale_found}"
    fi

    # 1d. T-1092. A `@Test` that walks the real product tree must be named in
    #     `CadenceTests/CadenceRealTreeSweepManifest.txt`, or deleting it stops an app-wide sweep and
    #     nothing goes red. That rule has a detector already -- and it is the FULL SUITE, ~22 minutes,
    #     so three times in two days a new sweep landed without its entry and the bill went to
    #     whoever ran the suite next rather than to the author who could have prevented it.
    #
    #     `real-tree-sweep-manifest.sh precheck` is the ~1s, build-free half. It is deliberately
    #     SOUND rather than complete: it reads a subset of what the Swift scan reads, and the Swift
    #     scan's markers only ever grow along a test's reach, so anything this flags IS a sweep by
    #     the real rule (measured: 228 flagged, 228 of them on the committed manifest, 0 false
    #     positives, 86% of the manifest's 265 entries). What it misses the full suite still catches;
    #     this only moves the cheap majority of the finding to the person holding the file.
    #
    #     Here rather than in `xcb.sh` because this is where the facts are: the real repository, the
    #     exact staged bytes, and `git show HEAD:` for the manifest. `xcb.sh` runs per test
    #     invocation -- once per mutation inside `mutate.sh` -- usually in a `git archive HEAD` tree
    #     that is not a checkout at all, so it has nothing to gate on and would re-read all 314 test
    #     files every time.
    local -a staged_tests
    staged_tests=()
    for name in "${names[@]}"; do
        [[ "$name" == CadenceTests/*.swift ]] || continue
        src="${source_of[$name]}"
        [[ -n "$src" ]] || src="$name"
        [[ -f "$src" ]] && staged_tests+=("$name=$src")
    done
    if (( ${#staged_tests} )); then
        local sweep_script="${SCRIPT_PATH:h}/real-tree-sweep-manifest.sh"
        local sweep_manifest="CadenceTests/CadenceRealTreeSweepManifest.txt"
        [[ -f "$sweep_script" ]] || refuse SWEEP-CHECK-MISSING "$sweep_script is not there, so the
  sweep-manifest precheck cannot run on the test sources this commit stages. Skipping it silently is
  how a guard becomes decoration; restore the script."
        # The manifest AS THIS COMMIT WOULD LEAVE IT: the staged copy when the commit carries one,
        # HEAD's otherwise. Regenerating and staging it is what clears this check, so reading the
        # worktree copy here would let an unregenerated commit through on a sibling's edit.
        local sweep_manifest_file="${source_of[$sweep_manifest]:-}"
        local sweep_tmp=""
        if [[ -z "$sweep_manifest_file" ]]; then
            if [[ -n "${names[(r)$sweep_manifest]:-}" && -f "$sweep_manifest" ]]; then
                sweep_manifest_file="$sweep_manifest"
            else
                sweep_tmp=$(mktemp "${TMP_BASE}cadence-sweep-manifest-${id}-XXXXXX") || refuse SCRATCH "cannot make a scratch file"
                git show "$headsha:$sweep_manifest" > "$sweep_tmp" 2>/dev/null || : > "$sweep_tmp"
                sweep_manifest_file="$sweep_tmp"
            fi
        fi
        local sweep_out flagged
        sweep_out=$(zsh "$sweep_script" "$id" precheck "$sweep_manifest_file" "${staged_tests[@]}" 2>&1)
        local swrc=$?
        [[ -n "$sweep_tmp" ]] && rm -f "$sweep_tmp"
        # 0 and 4 are readings. 2 means it refused to answer -- no needles, an empty manifest, an
        # unreadable source -- and a guard that reads its own refusal as "clean" is the hollow
        # instrument this file exists to avoid.
        (( swrc == 0 || swrc == 4 )) || refuse SWEEP-CHECK-FAILED "\`real-tree-sweep-manifest.sh $id precheck\` exited $swrc and said: ${sweep_out:-(nothing)}
  Nothing was committed, because whether these test sources add an unlisted product-tree sweep went
  unanswered."
        if (( swrc == 4 )); then
            local -a sweep_names
            sweep_names=(${(f)"$(print -r -- "$sweep_out" | cut -f2)"})
            local -a still_unnamed
            still_unnamed=()
            for flagged in "${sweep_names[@]}"; do
                [[ -n "${not_sweeps[(r)$flagged]:-}" ]] || still_unnamed+=("$flagged")
            done
            if (( ${#still_unnamed} )); then
                refuse SWEEP-MANIFEST-MISSING "these @Test functions walk the real product tree and are not on $sweep_manifest:
$(print -r -- "$sweep_out" | sed 's/^/    /')
  Deleting one of them would stop an app-wide sweep with nothing going red, which is what the
  manifest exists to prevent (T-808), and finding it costs a full 22-minute suite run (T-1092).
  Regenerate it from the scan -- never by hand:
      ./scripts/real-tree-sweep-manifest.sh $id --write
  then add the regenerated file to this commit:
      $sweep_manifest=<the regenerated file>
  If the authoritative scan disagrees and reports no change, this precheck and
  CadenceRealTreeSweepScan have drifted apart: that is a finding worth a ticket, and
  --not-a-sweep <name> lets the commit through once you have said which names you mean."
            fi
            say "note: precheck flagged ${#sweep_names} sweep(s) you declared not sweeps (--not-a-sweep): ${(j:, :)sweep_names}"
        fi
    fi

    # 1c. T-991. `--commits-stale` is the one deliberate override in this script that discarded
    #     something and left NOTHING to find afterwards. Every other one leaves a trace somebody has
    #     to clear: a declined hunk writes a record under $TMPDIR and `check` fails while it is
    #     outstanding; `--drops-ids` and `--reopens-ids` name their ids in the argv of a command
    #     somebody typed and nowhere else. So a batch could not answer, after the fact, *did anyone
    #     knowingly commit a copy behind HEAD, on which path, and how far behind* -- which is the
    #     exact question all four measured instances of T-975 were found by asking.
    #
    #     The trace goes in the COMMIT MESSAGE, not in the $TMPDIR ledger, and that is the whole
    #     point. The ledger is per-checkout, per-boot and cleared; the question is asked days later
    #     and from a clone. `git log --grep=Commits-Stale` answers it forever, and the base sha
    #     makes it answerable in detail: you can diff what was skipped.
    #
    #     It is NOT a declined-hunk record. Those mean "somebody still has to do something" and
    #     `check` fails while one exists; this means "somebody deliberately did this and here is
    #     what". Filing it as outstanding work would make `check` fail over a settled decision.
    #
    #     Inserted BEFORE the Co-Authored-By line, never after: that line has to stay last, because
    #     NO-COAUTHOR-TRAILER is checked against the last non-blank line and every commit in this
    #     repository ends with it.
    if (( ${#stale_audit} )); then
        local -a audit_lines msg_lines out_lines
        audit_lines=()
        for reading in "${stale_audit[@]}"; do audit_lines+=("Commits-Stale: $reading") done
        # In zsh, not awk: `awk -v extra=...` cannot carry a literal newline in an assignment
        # ("awk: newline in string"), so a two-path override silently produced an EMPTY message and
        # the Co-Authored-By line with it. Measured while writing this. Splice the array instead.
        msg_lines=("${(@f)message}"); out_lines=()
        local last=0 li
        for (( li = 1; li <= ${#msg_lines}; li++ )); do
            [[ "${msg_lines[li]}" == *[^[:space:]]* ]] && last=$li
        done
        for (( li = 1; li <= ${#msg_lines}; li++ )); do
            (( li == last )) && out_lines+=("${audit_lines[@]}")
            out_lines+=("${msg_lines[li]}")
        done
        message="${(F)out_lines}"
        say "note: recorded the override in the commit message: ${(j:; :)audit_lines}"
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
    local skip c                      # hoisted: bare `local c` in a loop prints it (T-1074)
    for record in "$LEDGER"/*.declined(N); do
        skip=0
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
    #
    #     T-1145: this asks the question of BOTH ledgers. It used to ask it of `docs/TODO.md` alone,
    #     while `LEDGER-ID-UNFILED`, `LEDGER-CLOSURE-BURIED`, `LEDGER-ID-DUPLICATE` and
    #     `LEDGER-ENTRY-DUPLICATED` next door all read `is_any_ledger_path` -- so a commit that
    #     dropped an id from `docs/TODO_DONE.md`, where every retired ticket ends up, was refused by
    #     nothing at all. The archive is the half of the ledger nobody rereads, which makes it the
    #     half a stale reconstruction can quietly shorten. MEASURED 2026-09-12 before widening it:
    #     replaying all 11 commits that have ever touched `docs/TODO_DONE.md` through this exact
    #     reading, and through 3a2's, finds ZERO ids dropped and ZERO closures reverted -- so this
    #     is enforceable at zero today rather than baselined, and the same replay over `docs/TODO.md`
    #     names 169d594d and f566723b, which is how we know the reading is not simply blind.
    #
    #     The one case that looked like a false refusal is not one: an entry MOVING from TODO.md to
    #     the archive drops its id from TODO.md, and that half was already refused (with
    #     `--drops-ids`) before this change. Ids only ever ARRIVE in TODO_DONE.md, and an arrival is
    #     not a loss, so widening the reading adds no refusal to the ordinary archival commit.
    local -a lost_ids open_lost_ids
    lost_ids=(); open_lost_ids=()
    # Hoisted out of the loop below on purpose: a bare `local x` whose parameter is already local
    # PRINTS it (`gone=...` on stdout) instead of redeclaring it -- same zsh trap as `drift_call`
    # above. REACHABLE since T-1145 widened the loop to both ledgers: a commit naming TODO.md and
    # TODO_DONE.md together -- which is exactly what archiving an entry looks like -- now takes a
    # second pass, and without this it would print `gone=T-xxx` into a commit's own output.
    local gone reopened
    for name in "${names[@]}"; do
        is_any_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        git cat-file -e "$headsha:$name" 2>/dev/null || continue
        local ledger_head="$scratch/$(ledger_key "$name").ledgerhead"
        git cat-file -p "$headsha:$name" > "$ledger_head"
        gone=$(comm -23 <(ledger_ids "$ledger_head") <(ledger_ids "${staged_content[$name]}"))
        [[ -n "$gone" ]] || continue
        lost_ids+=(${(f)gone})
        # 3a1 below needs to know WHICH ledger each id left, and this is the only place that knows.
        # An id leaving the archive has nowhere further to go; an id leaving the OPEN list is
        # supposed to be arriving somewhere, and that is the question nothing has been asking.
        [[ "${name:t}" == "TODO.md" ]] && open_lost_ids+=(${(f)gone})
    done
    if (( ${#lost_ids} )); then
        local declared_sorted="${(pj:,:)${(@o)${(@s:,:)declared_dropped_ids}}}"
        local lost_sorted="${(pj:,:)${(@o)lost_ids}}"
        if [[ "$declared_sorted" != "$lost_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-IDS-LOST "this commit drops ledger entries HEAD has: ${(j:, :)lost_ids}
  A reconstruction built on a stale copy loses a sibling's tickets in exactly this shape, and a
  line count hides it. Re-read \`git show HEAD:<path>\` and rebuild, or, if you really mean to
  retire them, say so: --drops-ids $lost_sorted"
        fi
    fi

    # 3a1. T-1148, and it is the question `--drops-ids` was invented to stop asking. 3a above asks
    #      whether the drop was DELIBERATE; the flag answers that and nothing then asks the second
    #      half, which is the one the ledger is for: **where did the ticket go?** The ordinary way
    #      an entry leaves `docs/TODO.md` is that it MOVES to `docs/TODO_DONE.md`, and a move is a
    #      drop plus an arrival. Only the drop was ever read, so a bulk archival commit that moves
    #      85 entries and leaves an 86th on the floor is authorised by the same flag as the 85.
    #
    #      MEASURED by replaying every commit that has ever touched `docs/TODO.md` and asking each
    #      one whether an id it dropped is in that commit's own `docs/TODO_DONE.md`. Re-derived
    #      2026-09-12 at `60c69b6`: **101 commits dropped at least one id, 384 drop events in
    #      total, and only 92 of the 384 arrived in the archive in the commit that dropped them.**
    #      Of the 292 that did not, **202 distinct ids are in neither ledger at HEAD**, and the
    #      split is the whole reason this is enforceable: **200 of the 202 are `T-441` or below**,
    #      inside the deficit `T-462` measured (at ~200 tickets) and deliberately did not backfill,
    #      85 of which `193f257f` reconstructed from git history. The other two are T-768 and
    #      T-849, and they are T-1148's -- now recovered, which takes the modern residue to zero.
    #      A previous revision of this comment called that residue "284", which was T-462's own
    #      superseded figure; T-462 narrowed it to 200 and this replay's answer is 202.
    #
    #      SO WHY THIS IS NOT A GUARD THAT FIRES ON THE NORMAL CASE ([[T-986]]), which is the one
    #      failure this family must not have: the gap is HISTORY. Over the **218** commits of
    #      `docs/TODO.md` since 2026-08-30, exactly **THREE** dropped an id at all --
    #
    #        169d594d  T-780, T-781, T-782   the T-981 reversion; all three are back in TODO.md now
    #        7bf25332  T-752, T-768, T-849   T-752 came back; T-768 and T-849 never arrived anywhere
    #        3a381116  T-935                 back in TODO.md now
    #
    #      -- and **all three are defects**. Five of those seven ids were put back by a later
    #      commit, which is what an accidental drop looks like after someone notices; the other two
    #      are T-768 and T-849, which with T-441 were T-1148's standing loss and are now recovered
    #      into docs/TODO_DONE.md, so this guard is enforceable at zero rather than baselined at
    #      three. NOT ONE of the three was a legitimate archival, so this
    #      reading has a measured false-refusal rate of zero over the whole modern population, and
    #      it would have caught every real instance in it. Today's convention is to close an entry
    #      IN PLACE -- 158 of the 193 entries in `## Open` carry `CLOSED` on their own first line --
    #      so dropping an id is already the rare event, not the daily one.
    #
    #      The escape is `--retires-ids`, deliberately a SECOND flag rather than a wider reading of
    #      `--drops-ids`: "this entry is moving to the archive" and "this id is being struck off
    #      because it was never a ticket" are different claims, and the whole finding is that one
    #      flag was being made to carry both. `--retires-ids` must name the unarchived set exactly,
    #      the same discipline every other declaration here uses, so it cannot be typed once and
    #      left in an alias.
    #
    #      Asked of the archive AS THIS COMMIT LEAVES IT -- staged content where the commit names
    #      `TODO_DONE.md`, HEAD's blob otherwise -- so the ordinary move, which stages both files
    #      together, needs no flag at all. There is deliberately no "only ask where an archive
    #      exists" carve-out of the kind LEDGER-ID-UNFILED carries: a checkout with no archive is
    #      precisely the state in which 200 tickets were lost, and answering "no archive, therefore
    #      nothing to check" is how a guard stops matching its population.
    local -a unarchived_ids
    unarchived_ids=()
    local archived_ids="$scratch/archived.ids" apath ablob openlost
    : > "$archived_ids"
    for apath in ${(f)"$(git ls-tree -r --name-only "$headsha" 2>/dev/null | grep -E '(^|/)TODO_DONE\.md$')"} "${names[@]}"; do
        [[ -n "$apath" ]] || continue
        [[ "${apath:t}" == "TODO_DONE.md" ]] || continue
        if [[ -n "${staged_content[$apath]+x}" ]]; then
            ledger_ids "${staged_content[$apath]}" >> "$archived_ids"
        elif git cat-file -e "$headsha:$apath" 2>/dev/null; then
            ablob="$scratch/$(ledger_key "$apath").archived"
            git cat-file -p "$headsha:$apath" > "$ablob"
            ledger_ids "$ablob" >> "$archived_ids"
        fi
    done
    for openlost in "${open_lost_ids[@]}"; do
        grep -qx -- "$openlost" "$archived_ids" || unarchived_ids+=("$openlost")
    done
    if (( ${#unarchived_ids} )); then
        local declared_retired_sorted="${(pj:,:)${(@o)${(@s:,:)declared_retired_ids}}}"
        local unarchived_sorted="${(pj:,:)${(@o)unarchived_ids}}"
        if [[ "$declared_retired_sorted" != "$unarchived_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-ID-UNARCHIVED "this commit drops ledger entries from the open list that arrive nowhere: ${(j:, :)unarchived_ids}
  --drops-ids says the removal was deliberate; it does not say where the ticket went. An entry
  normally LEAVES docs/TODO.md by MOVING to docs/TODO_DONE.md, and none of these is in the archive
  as this commit leaves it -- so the reasoning in them is about to exist only in git history, where
  the next agent to wonder about this ticket will not look. Stage the archive with the entry in it
  in this same commit, or, if the id is being struck off rather than archived -- a draft that was
  never a ticket, a duplicate, an id superseded before it was used -- say which:
  --retires-ids $unarchived_sorted"
        fi
    fi

    # 3a2. T-981, and it is the same shape as 3a one level down. An id that survives while its
    #      CLOSURE does not is a shipped ticket the ledger now describes as not started, and every
    #      guard above is satisfied: the id sets are equal, so LEDGER-IDS-LOST passes; the line
    #      count is whatever the two texts happen to differ by, so REMOVES-HEAD-LINES is a number
    #      somebody acknowledges without reading. Only ids present in BOTH versions are asked
    #      about -- an id that vanished entirely is 3a's finding and naming it twice buries both.
    #      Both ledgers, for T-1145's reason above: an archived closure reverting to its open text
    #      is the same loss as a live one, and reads as a perfectly ordinary rewrite to everything
    #      else in this file. `reopened_in` is a LIST because the loop can now find one in each.
    local -a reopened_ids reopened_in
    reopened_ids=(); reopened_in=()
    for name in "${names[@]}"; do
        is_any_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        git cat-file -e "$headsha:$name" 2>/dev/null || continue
        local closure_head="$scratch/$(ledger_key "$name").closurehead"
        git cat-file -p "$headsha:$name" > "$closure_head"
        reopened=$(comm -12 \
            <(comm -23 <(ledger_closed_ids "$closure_head") <(ledger_closed_ids "${staged_content[$name]}")) \
            <(ledger_ids "${staged_content[$name]}"))
        [[ -n "$reopened" ]] || continue
        reopened_ids+=(${(f)reopened}); reopened_in+=("$name")
    done
    if (( ${#reopened_ids} )); then
        local declared_reopened_sorted="${(pj:,:)${(@o)${(@s:,:)declared_reopened_ids}}}"
        local reopened_sorted="${(pj:,:)${(@o)reopened_ids}}"
        if [[ "$declared_reopened_sorted" != "$reopened_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-CLOSURE-LOST "this commit reverts ledger entries from closed back to open: ${(j:, :)reopened_ids}
  Each id is still there, so LEDGER-IDS-LOST has nothing to say about it -- the entry's own text
  changed from a closure back to the open ticket it was before, which is what a reconstruction
  built on a stale copy does to a ticket somebody closed while you were working. Re-read
  \`git show HEAD:<path>\` for ${(j:, :)${(@u)reopened_in}} and rebuild on it, or, if you really
  are reopening them, say so: --reopens-ids $reopened_sorted"
        fi
    fi

    # 3a3. T-1106, half one: a CLOSURE THE ANCHOR CANNOT SEE. Every guard above, and every reader
    #      of docs/TODO.md, takes the entry's own first line as the state of the ticket. An entry
    #      whose closure was written into its body is therefore closed to a human and open to every
    #      instrument -- which is not a cosmetic difference: [[T-1085]] read as open for five days
    #      after it shipped and was picked up again by an agent who read its first line.
    #
    #      This is a WHOLE-FILE reading, not a "what changed here" one, and that is deliberate: the
    #      measured population on 2026-09-11 was fourteen, all fourteen were fixed in the same
    #      commit that added this, and the guard is enforceable at zero. A per-entry-delta reading
    #      would have let those fourteen sit forever, which is exactly how they accumulated.
    local -a buried_ids
    buried_ids=(); local buried_in="" buried
    for name in "${names[@]}"; do
        is_any_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        buried=$(ledger_buried_closure_ids "${staged_content[$name]}")
        [[ -n "$buried" ]] || continue
        buried_ids+=(${(f)buried}); buried_in="$name"
    done
    if (( ${#buried_ids} )); then
        local declared_buried_sorted="${(pj:,:)${(@o)${(@s:,:)declared_buried_ids}}}"
        local buried_sorted="${(pj:,:)${(@o)buried_ids}}"
        if [[ "$declared_buried_sorted" != "$buried_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-CLOSURE-BURIED "these ledger entries are CLOSED in their body and open on their own first line: ${(j:, :)buried_ids}
  \`ledger_closed_ids\` -- and LEDGER-CLOSURE-LOST, and every agent scanning $buried_in for work --
  anchors on the entry's FIRST line, so a closure written mid-entry closes nothing they can see.
  Move the \`**CLOSED <date> (...)**\` sentence onto each entry's own first line. If one of these
  really is prose and not a closure, say so: --buried-closures $buried_sorted"
        fi
    fi

    # 3a3b. T-1142, and the half 3a3 cannot reach. That guard asks whether the closure was written
    #       where every instrument looks; this asks whether writing it REPLACED the draft it was
    #       meant to replace. An appended closure leaves the entry asserting its own body twice --
    #       and asserting, in T-991/T-992's case, both `CLOSED` and `NOT YET IN HEAD` at once.
    #
    #       DELTA-READ AGAINST HEAD, and unlike 3a3 that is deliberate rather than a concession.
    #       3a3 could be whole-file because its measured population of fourteen was driven to zero
    #       in the commit that added it. This one cannot be: of the four standing instances, T-986
    #       is a live sibling's ticket and T-781 is not mine either, so a whole-file reading would
    #       refuse every commit of this file until somebody else acted -- and the first thing a
    #       blocked agent would reach for is the escape flag, which is how a guard becomes noise.
    #       The delta reading catches the defect at the instant it is CREATED, which is where the
    #       author and the cheap fix both are; the standing four can only shrink from here.
    #
    #       Replayed over the whole history of `docs/TODO.md`, every commit of it: ONE refusal,
    #       `7584c5f`, which is the commit that created all four. Zero false refusals. (The commit
    #       COUNT is not recorded here on purpose -- see ledger_closed_ids() above and T-1146. This
    #       line said 428 while that one said 349, about the same population on the same day, and
    #       neither is true a week later. The sha is the evidence; the denominator was decoration.)
    local -a dup_entries
    dup_entries=(); local dup_in="" dupid duprun prevrun
    # Hoisted, like `gone`/`reopened` above and for T-1074's reason: a bare `local x` whose
    # parameter is already local prints `x=<value>` instead of redeclaring it. Reachable here the
    # moment one commit names both TODO.md and TODO_DONE.md.
    local -A head_runs
    for name in "${names[@]}"; do
        is_any_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        local dup_head="$scratch/$(ledger_key "$name").duphead"
        if git cat-file -e "$headsha:$name" 2>/dev/null; then
            git cat-file -p "$headsha:$name" > "$dup_head"
        else
            : > "$dup_head"
        fi
        # HEAD is read with a threshold of 1, so the comparison is against its TRUE longest run
        # rather than against the refusal threshold: an entry already repeating three lines must
        # not be able to acquire a fourth for free.
        head_runs=()
        while IFS=$'\t' read -r dupid duprun; do
            [[ -n "$dupid" ]] && head_runs[$dupid]="$duprun"
        done < <(ledger_selfduplicated_ids "$dup_head" 1)
        while IFS=$'\t' read -r dupid duprun; do
            [[ -n "$dupid" ]] || continue
            prevrun="${head_runs[$dupid]:-0}"
            (( duprun > prevrun )) || continue
            dup_entries+=("$dupid  [$duprun repeated lines, HEAD had $prevrun]"); dup_in="$name"
        done < <(ledger_selfduplicated_ids "${staged_content[$name]}" "$LEDGER_DUP_MIN_RUN")
    done
    if (( ${#dup_entries} )); then
        local -a dup_ids_only
        dup_ids_only=("${(@)dup_entries%% *}")
        local declared_dup_sorted="${(pj:,:)${(@o)${(@s:,:)declared_duplicated_entries}}}"
        local dup_sorted="${(pj:,:)${(@o)dup_ids_only}}"
        if [[ "$declared_dup_sorted" != "$dup_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-ENTRY-DUPLICATED "these ledger entries now contain their own body twice: ${(j:, :)dup_entries}
  A closure APPENDED to the draft it was meant to replace, rather than written over it. The entry
  then states its case twice and, where the draft was a progress note, states two contradictory
  cases at once -- \`CLOSED\` on the first line and \`NOT YET IN HEAD\` in the body.
  No guard above can see this: the id is still there, the first line is still a closure, and the
  line count only went UP, so REMOVES-HEAD-LINES has nothing to say either.
  Edit the draft OUT of $dup_in rather than pasting the closure underneath it.
  If the repetition really is deliberate, say so: --duplicated-entries $dup_sorted"
        fi
    fi

    # 3a4. T-1106, half two, and the one the ticket called the valuable half. The ledger IS the id
    #      allocator (T-1072): an id that exists only in a commit message, or only in another
    #      entry's prose, is invisible to the next agent computing "next free". `T-1119` was handed
    #      to two agents in one week that way, and `T-1117` was allocated inside T-624's closure
    #      with no stub behind it. Ten ids reached that state before this guard existed; T-1123
    #      recovered all ten into docs/TODO_DONE.md, so there is no standing backlog behind it.
    #
    #      So the message is checked against the ledgers AS THIS COMMIT LEAVES THEM -- writing the
    #      stub in the same commit that first names the id is the rule, and this makes it the only
    #      way through. Historical ids are out of reach by construction: only this message is read.
    local -a unfiled_ids
    unfiled_ids=()
    local filed_ids="$scratch/filed.ids" lpath lblob
    : > "$filed_ids"
    for lpath in ${(f)"$(git ls-tree -r --name-only "$headsha" 2>/dev/null | grep -E '(^|/)TODO(_DONE)?\.md$')"} "${names[@]}"; do
        [[ -n "$lpath" ]] || continue
        is_any_ledger_path "$lpath" || continue
        if [[ -n "${staged_content[$lpath]+x}" ]]; then
            ledger_ids "${staged_content[$lpath]}" >> "$filed_ids"
        elif git cat-file -e "$headsha:$lpath" 2>/dev/null; then
            lblob="$scratch/$(ledger_key "$lpath").filed"
            git cat-file -p "$headsha:$lpath" > "$lblob"
            ledger_ids "$lblob" >> "$filed_ids"
        fi
    done
    # Only ask the question at all where there is a ledger to ask it of. A checkout with neither
    # TODO.md nor TODO_DONE.md anywhere would otherwise read every id in the message as unfiled.
    if [[ -s "$filed_ids" ]]; then
        local msgid
        for msgid in ${(f)"$(message_ids "$message")"}; do
            [[ -n "$msgid" ]] || continue
            grep -qx -- "$msgid" "$filed_ids" || unfiled_ids+=("$msgid")
        done
    fi
    if (( ${#unfiled_ids} )); then
        local declared_unfiled_sorted="${(pj:,:)${(@o)${(@s:,:)declared_unfiled_ids}}}"
        local unfiled_sorted="${(pj:,:)${(@o)unfiled_ids}}"
        if [[ "$declared_unfiled_sorted" != "$unfiled_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-ID-UNFILED "this message names ticket ids with no formal ledger entry: ${(j:, :)unfiled_ids}
  The ledger is the allocator: an id that lives only in a commit message is invisible to the next
  agent computing \"next free\", which is how one id went to two agents in a single week. Write the
  stub -- \`- [$unfiled_ids[1]] **<one line>**\` -- into docs/TODO.md in THIS commit. If the id is a
  historical reference you are only quoting, say so: --unfiled-ids $unfiled_sorted"
        fi
    fi

    # 3a5. T-1072's concurrent half. The guard above makes an id that was never filed impossible;
    #      it says nothing about an id filed TWICE, which is the exact residue of two agents both
    #      reading "next free" before either committed. `T-1119` in one week, `T-1109`/`T-1110` in
    #      another, and `T-1043` -- all three incidents left one shape behind, a ledger with two
    #      formal entries for one id, and nothing read it. Rationale, the delta reading and the
    #      436-commit replay that measured 6 true refusals and 1 false are on `ledger_duplicate_ids`.
    #
    #      Read PER LEDGER FILE, not across both, and that is what was measured: an entry moving
    #      from TODO.md to TODO_DONE.md is briefly in both by construction, and a commit staging one
    #      side of that move is an ordinary commit, not a double allocation.
    local -a duplicate_ids
    duplicate_ids=(); local duplicate_in="" dup_head="" dup_staged="" dup_new="" dup_headfile=""
    for name in "${names[@]}"; do
        is_any_ledger_path "$name" || continue
        [[ -n "${staged_content[$name]+x}" ]] || continue
        dup_staged="$scratch/$(ledger_key "$name").dupstaged"
        ledger_duplicate_ids "${staged_content[$name]}" > "$dup_staged"
        [[ -s "$dup_staged" ]] || continue
        dup_head="$scratch/$(ledger_key "$name").duphead"
        dup_headfile="$scratch/$(ledger_key "$name").duphead.blob"
        git cat-file -p "$headsha:$name" > "$dup_headfile" 2>/dev/null || : > "$dup_headfile"
        ledger_duplicate_ids "$dup_headfile" > "$dup_head"
        dup_new=$(comm -23 "$dup_staged" "$dup_head")
        [[ -n "$dup_new" ]] || continue
        duplicate_ids+=(${(f)dup_new}); duplicate_in="$name"
    done
    if (( ${#duplicate_ids} )); then
        local declared_duplicate_sorted="${(pj:,:)${(@o)${(@s:,:)declared_duplicate_ids}}}"
        local duplicate_sorted="${(pj:,:)${(@o)duplicate_ids}}"
        if [[ "$declared_duplicate_sorted" != "$duplicate_sorted" ]]; then
            rm -rf "$scratch"
            refuse LEDGER-ID-DUPLICATE "this commit files a second formal entry for ids already allocated: ${(j:, :)duplicate_ids}
  The ledger IS the allocator, so an id with two entries is an id two pieces of work answer to, and
  every later \`[[$duplicate_ids[1]]]\` reference is ambiguous forever. This is what two agents both
  reading \"next free\" before either committed leaves behind -- HEAD already moved under you once,
  a sibling's stub for this id landed, and your reconstruction carried yours in beside theirs.
  Renumber YOUR entry to an id that is free in $duplicate_in as this commit leaves it, and fix the
  references in your own hunk. If this really is one ticket written twice on purpose, say so:
  --duplicate-ids $duplicate_sorted"
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
    say " mode 4b3 (REBUILD-BEHIND-HEAD) -- the = reconstruction must be asked where IT was built"
    # T-992. The `=` form is what the refusal in 4b2 TELLS the agent to reach for, so a rebuild on
    # the wrong sha is not an exotic case -- it is the commonest way staleness survives the cure.
    # Measured 2026-09-05: content built two commits back was refused as REMOVES-HEAD-LINES with
    # `--removes 2`, and nothing asked which revision it came from.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    # TWO paths, both with history, because one path can never show the T-1074 leak below.
    ( cd "$ws"
      print -rl -- "rebuild one" "rebuild two" "rebuild three" > rebuild.txt
      print -rl -- "second one" "second two" "second three" > rebuild2.txt
      zsh "$here" g0 -m "$M" rebuild.txt rebuild2.txt
      # Two siblings land on these paths. Ordinary commits: the `=` form reads the CONTENT FILE, so
      # whether the checkout is stale is beside the point here -- which is itself the finding.
      print -r -- "sibling landed four" >> rebuild.txt
      print -r -- "second sibling four" >> rebuild2.txt
      git add rebuild.txt rebuild2.txt && git commit -qm "s1

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
      print -r -- "sibling landed five" >> rebuild.txt
      print -r -- "second sibling five" >> rebuild2.txt
      git add rebuild.txt rebuild2.txt && git commit -qm "s2

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
      git reset -q ) >/dev/null 2>&1
    local stale_base_sha; stale_base_sha=$( cd "$ws" && git rev-parse --short HEAD~2 )
    check "the checkout itself is NOT behind -- only the reconstruction will be" \
        $( [[ "$( cd "$ws" && git status --porcelain -- rebuild.txt )" == "" ]] && print 1 || print 0 ) \
        "$( cd "$ws" && git status --porcelain -- rebuild.txt )"
    ( cd "$ws" && git show HEAD~2:rebuild.txt > recon-stale.txt \
      && print -r -- "this agent's own rebuilt line" >> recon-stale.txt )
    out=$( cd "$ws" && zsh "$here" g1 -m "$M" rebuild.txt=recon-stale.txt 2>&1 ); rc=$?
    check "a content file built on an older revision is refused" \
        $( [[ $rc == 3 && "$out" == *REBUILD-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and it names the revision it was built on, and how far behind that is" \
        $( [[ "$out" == *"built on ${stale_base_sha}"* && "$out" == *"2 commit(s) to this path since"* ]] && print 1 || print 0 ) "$out"
    # The whole point of asking BEFORE the content guards: the old answer was a number, plus an
    # invitation to type it, and typing it drops the two lines the siblings landed.
    check "the staleness is the complaint, not the removed-line count" \
        $( [[ "$out" != *"REFUSED (REMOVES-HEAD-LINES)"* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" \
        $( [[ $( cd "$ws" && git show HEAD:rebuild.txt ) != *"own rebuilt line"* ]] && print 1 || print 0 )
    # T-1074, and it regressed here twice while this mode was being written. A bare `local x` in a
    # zsh function whose parameter is already local PRINTS `x=<value>` rather than redeclaring it,
    # so the second path through any loop above emits a stray assignment line into the refusal --
    # in a script whose output IS how it reports refusals. One path never shows it; two always do.
    ( cd "$ws" && git show HEAD~2:rebuild2.txt > recon-stale2.txt \
      && print -r -- "a second path's own rebuilt line" >> recon-stale2.txt ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" g1b -m "$M" rebuild.txt=recon-stale.txt rebuild2.txt=recon-stale2.txt 2>&1 )
    check "both stale paths are named, so the loop really did run twice" \
        $( [[ "$out" == *rebuild.txt* && "$out" == *rebuild2.txt* ]] && print 1 || print 0 ) "$out"
    # `grep -E`, not a `[[ ]]` glob: `[a-z_]##=` needs EXTENDED_GLOB, which is not set here, so
    # the glob form matched literally and the check passed against the un-fixed script. Caught by
    # the mutation control -- which is the entire reason that control exists.
    check "two paths in one commit emit no stray zsh assignment line (T-1074)" \
        $( print -r -- "$out" | grep -qE '^[a-z_][a-z_0-9]*=' && print 0 || print 1 ) "$out"
    # THE FALSE-REFUSAL CONTROL, and the reason this can live in the commit path at all. A rebuild
    # on HEAD that also DELETES a line contains no whole revision, so it reads `cannot-tell` and is
    # not refused here -- T-984's blind spot, deliberately intact. It still meets REMOVES-HEAD-LINES.
    ( cd "$ws" && git show HEAD:rebuild.txt | grep -v "rebuild two" > recon-del.txt )
    out=$( cd "$ws" && zsh "$here" g2 -m "$M" rebuild.txt=recon-del.txt 2>&1 ); rc=$?
    check "a rebuild ON HEAD that deletes a line is NOT called stale (T-984's bucket is unchanged)" \
        $( [[ "$out" != *REBUILD-BEHIND-HEAD* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "it reaches the removed-line count instead, exactly as before" \
        $( [[ $rc == 3 && "$out" == *REMOVES-HEAD-LINES* ]] && print 1 || print 0 ) "exit $rc: $out"

    say ""
    say " mode 4b4 (T-991) -- --commits-stale must leave something findable afterwards"
    # Every other deliberate override here leaves a trace somebody has to clear. This one wrote
    # nothing, so `did anyone knowingly commit a copy behind HEAD, and on which path` -- the
    # question all four measured instances of T-975 were found by asking -- had no answer at all.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    out=$( cd "$ws" && zsh "$here" g3 -m "$M" --commits-stale rebuild.txt --removes 2 rebuild.txt=recon-stale.txt 2>&1 ); rc=$?
    check "naming the path in --commits-stale lets the stale rebuild through deliberately" $(( rc == 0 )) "exit $rc: $out"
    local stale_msg; stale_msg=$( cd "$ws" && git log -1 --format=%B )
    check "and the commit message carries a Commits-Stale trailer naming the path" \
        $( [[ "$stale_msg" == *"Commits-Stale: rebuild.txt built-on "* ]] && print 1 || print 0 ) "$stale_msg"
    check "the trailer carries the BASE sha, so what was skipped can be diffed later" \
        $( [[ "$stale_msg" == *"built-on $( cd "$ws" && git rev-parse HEAD~3 )"* ]] && print 1 || print 0 ) \
        "want $( cd "$ws" && git rev-parse HEAD~3 ), message was: $stale_msg"
    # The trailer must go ABOVE the Co-Authored-By line: that one has to stay last or the script's
    # own NO-COAUTHOR-TRAILER check would refuse the next commit built from this message.
    check "the Co-Authored-By line is still the last non-blank line" \
        $( [[ "$(print -r -- "$stale_msg" | grep -v '^[[:space:]]*$' | tail -1)" == Co-Authored-By:* ]] && print 1 || print 0 ) "$stale_msg"
    check "git log --grep finds it, which is the question the ticket was about" \
        $( [[ -n "$( cd "$ws" && git log --grep='^Commits-Stale:' --format=%h )" ]] && print 1 || print 0 )
    # The control: an ordinary commit must not acquire the trailer, or `--grep` answers everything
    # and therefore nothing.
    ( cd "$ws" && print -r -- "an ordinary line" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" g4 -m "$M" mine.txt 2>&1 ); rc=$?
    check "an ordinary commit carries no Commits-Stale trailer" \
        $( [[ $rc == 0 && "$( cd "$ws" && git log -1 --format=%B )" != *Commits-Stale* ]] && print 1 || print 0 ) "exit $rc: $out"
    ( cd "$ws" && git reset -q ) >/dev/null 2>&1

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
    # T-1148 changed what this line proves, and the change is the ticket. `--drops-ids` used to be
    # the whole answer; it now authorises the REMOVAL and 3a1 asks the second half -- where did the
    # ticket go? There is no `TODO_DONE.md` in this workspace yet (4d2 creates it), so T-102 arrives
    # nowhere and the bare form is now the refusal rather than the pass.
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" --drops-ids T-102 --removes 1 TODO.md=stale.md 2>&1 ); rc=$?
    check "--drops-ids alone no longer retires an entry that arrives nowhere" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNARCHIVED*T-102* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the refusal offers the flag that says struck off rather than archived" \
        $( [[ "$out" == *"--retires-ids T-102"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" --drops-ids T-102 --retires-ids T-101 --removes 1 TODO.md=stale.md 2>&1 ); rc=$?
    check "retiring the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNARCHIVED* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" --drops-ids T-102 --retires-ids T-102 --removes 1 TODO.md=stale.md 2>&1 ); rc=$?
    check "striking it off deliberately is allowed" $(( rc == 0 )) "exit $rc: $out"
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
    say " mode 4d2 (T-1145) -- both guards above must read the ARCHIVE, not just docs/TODO.md"
    # Everything in 4c and 4d was asserted about `TODO.md`, and for a long time that was all either
    # guard could see: they read a predicate matching that one filename while the four ledger guards
    # beside them read `is_any_ledger_path`. `docs/TODO_DONE.md` is where every retired ticket ends
    # up -- the half nobody rereads, so the half a stale reconstruction can quietly shorten. These
    # checks are the same two findings asked of the archive; without them the widened predicate is
    # one word that any later edit could put back.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws"
      print -rl -- "# Archive" "" "- [T-201] retired" "  body" \
                   "" "- [T-202] **CLOSED 2026-09-05 (\`deadd0c\`).** shipped long ago" "  body" > TODO_DONE.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" f1 -m "$M" TODO_DONE.md 2>&1 ); rc=$?
    check "creating the archive is an ordinary commit" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws"
      print -rl -- "# Archive" "" "- [T-202] **CLOSED 2026-09-05 (\`deadd0c\`).** shipped long ago" "  body" > arch_short.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" f2 -m "$M" TODO_DONE.md=arch_short.md 2>&1 ); rc=$?
    check "an id dropped from the ARCHIVE is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-IDS-LOST*T-201* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" f2 -m "$M" --drops-ids T-201 --removes 1 TODO_DONE.md=arch_short.md 2>&1 ); rc=$?
    check "and retiring it from the archive deliberately is allowed" $(( rc == 0 )) "exit $rc: $out"
    # The closure half. Same id, same line count, T-202's first line back to an open ticket: 4c's
    # reading has nothing to say about it, which is the whole reason 3a2 exists one level down.
    ( cd "$ws"
      git show HEAD:TODO_DONE.md | sed 's/^- \[T-202\] \*\*CLOSED.*/- [T-202] **not shipped after all** back to the open text/' > arch_reopen.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" f3 -m "$M" TODO_DONE.md=arch_reopen.md 2>&1 ); rc=$?
    check "an ARCHIVED closure reverting to open text is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-CLOSURE-LOST*T-202* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the refusal names the archive as the file to re-read" \
        $( [[ "$out" == *TODO_DONE.md* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" f3 -m "$M" --reopens-ids T-202 --removes 1 TODO_DONE.md=arch_reopen.md 2>&1 ); rc=$?
    check "reopening an archived entry deliberately is allowed" $(( rc == 0 )) "exit $rc: $out"
    # Fixture housekeeping, the same note mode 4d carries: the `f2` reconstruction above
    # deliberately retired T-201, so a record of that declined line is outstanding and the next
    # commit of this path would read DECLINED-HUNK-LOST instead of what this check is about.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    # The negative control that decides whether the widening is usable: ARCHIVING an entry is the
    # ordinary ledger commit, and it is the one shape that touches both files at once. Ids only
    # ever arrive in the archive, so this half must need no flag of its own -- the drop on the
    # TODO.md side is 4c's finding and was already declared there.
    ( cd "$ws"
      git show HEAD:TODO_DONE.md > arch_grown.md
      print -rl -- "" "- [T-106] **CLOSED 2026-09-05 (\`deadbef\`).** also shipped" "  body" >> arch_grown.md
      git show HEAD:TODO.md | grep -v '^- \[T-106\]' | grep -v '^  also shipped' > todo_moved.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" f4 -m "$M" --drops-ids T-106 --removes 1 TODO.md=todo_moved.md TODO_DONE.md=arch_grown.md 2>&1 ); rc=$?
    check "moving an entry INTO the archive needs no flag on the archive's side" \
        $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $out"

    say ""
    say " mode 4d3 (LEDGER-ID-UNARCHIVED) -- T-1148: --drops-ids says the removal was deliberate,"
    say "          it does not say where the ticket went"
    # The f4 check directly above is this mode's negative control and the reason the guard is
    # usable: the ORDINARY way an entry leaves the open list is a move, and a move needs no flag.
    # What nothing asked until T-1148 is the other half of that move. `193f257f` archived 85
    # entries and dropped an 86th, `T-441`, on the floor in the same commit; every instrument in
    # this script passed it, because the 86 drops were declared together and only the drops were
    # ever read. The fixture below is that commit in miniature: three ids leave TODO.md, two of
    # them arrive in the archive, one does not.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws"
      git show HEAD:TODO.md > todo_three.md
      print -rl -- "- [T-301] alpha" "  body alpha" \
                   "- [T-302] beta"  "  body beta"  \
                   "- [T-303] gamma" "  body gamma" >> todo_three.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h1 -m "$M" TODO.md=todo_three.md 2>&1 ); rc=$?
    check "three entries arrive in the open list with no flag" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws"
      git show HEAD:TODO.md | grep -vE '^- \[T-30[123]\]|^  body (alpha|beta|gamma)$' > todo_bulk.md
      git show HEAD:TODO_DONE.md > arch_bulk.md
      print -rl -- "- [T-301] alpha" "  body alpha" "- [T-302] beta" "  body beta" >> arch_bulk.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h2 -m "$M" --drops-ids T-301,T-302,T-303 --removes 6 \
              TODO.md=todo_bulk.md TODO_DONE.md=arch_bulk.md 2>&1 ); rc=$?
    check "a bulk move that archives two of three is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNARCHIVED* ]] && print 1 || print 0 ) "exit $rc: $out"
    # The half that makes the refusal worth reading: it must name the one that was dropped on the
    # floor and NOT the two that landed, or it is a line count again.
    check "and it names only the id that arrived nowhere" \
        $( [[ "$out" == *T-303* && "$out" != *T-301* && "$out" != *T-302* ]] && print 1 || print 0 ) "$out"
    # And the mutation that survived every check above until this one existed. With exactly ONE id
    # on the floor, `unarchived_ids+=(...)` and `unarchived_ids=(...)` are indistinguishable:
    # reducing the collection to "keep the last one" left all 173 checks passing, so the refusal
    # could have named T-303 while waving T-302 through in the same commit -- `193f257f` again, one
    # level down. Measured, not imagined: that mutation was run and it was green. The fixture here
    # archives ONE of three, so two ids arrive nowhere and BOTH have to be named.
    ( cd "$ws"
      git show HEAD:TODO_DONE.md > arch_one.md
      print -rl -- "- [T-301] alpha" "  body alpha" >> arch_one.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h2 -m "$M" --drops-ids T-301,T-302,T-303 --removes 6 \
              TODO.md=todo_bulk.md TODO_DONE.md=arch_one.md 2>&1 ); rc=$?
    check "a bulk move that archives ONE of three is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNARCHIVED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and it names BOTH ids that arrived nowhere, not just the last one" \
        $( [[ "$out" == *T-302* && "$out" == *T-303* && "$out" != *T-301* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" h2 -m "$M" --drops-ids T-301,T-302,T-303 --retires-ids T-303 --removes 6 \
              TODO.md=todo_bulk.md TODO_DONE.md=arch_one.md 2>&1 ); rc=$?
    check "and striking off ONE of the two does not satisfy it" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNARCHIVED* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" h2 -m "$M" --drops-ids T-301,T-302,T-303 --retires-ids T-301,T-303 --removes 6 \
              TODO.md=todo_bulk.md TODO_DONE.md=arch_bulk.md 2>&1 ); rc=$?
    check "naming an id that DID arrive as struck off is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNARCHIVED* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" h2 -m "$M" --drops-ids T-301,T-302,T-303 --retires-ids T-303 --removes 6 \
              TODO.md=todo_bulk.md TODO_DONE.md=arch_bulk.md 2>&1 ); rc=$?
    check "striking the third off deliberately is allowed" $(( rc == 0 )) "exit $rc: $out"
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    # An id already IN the archive at HEAD -- deduplicating an entry left behind in the open list
    # after its closure was archived -- has arrived, and arriving earlier is still arriving. This
    # is the false refusal the guard must not have: it reads the archive as this commit LEAVES it,
    # not as this commit CHANGES it, and here the commit does not name the archive at all.
    ( cd "$ws"
      git show HEAD:TODO.md > todo_dupe.md
      print -rl -- "- [T-301] alpha" "  body alpha" >> todo_dupe.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h3 -m "$M" TODO.md=todo_dupe.md 2>&1 ); rc=$?
    check "an id that is already archived may be re-opened in the open list" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws" && git show HEAD:TODO.md | grep -vE '^- \[T-301\]|^  body alpha$' > todo_deduped.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h4 -m "$M" --drops-ids T-301 --removes 2 TODO.md=todo_deduped.md 2>&1 ); rc=$?
    check "and dropping it again needs no --retires-ids, because it is already in the archive" \
        $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $out"
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    # And the boundary: an id leaving the ARCHIVE is 3a's finding, not this one. There is nowhere
    # further for it to arrive, so asking this question of it would be a second refusal for one
    # event -- which is how an agent learns to type both flags without reading either.
    ( cd "$ws" && git show HEAD:TODO_DONE.md | grep -vE '^- \[T-302\]|^  body beta$' > arch_less.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h5 -m "$M" --drops-ids T-302 --removes 2 TODO_DONE.md=arch_less.md 2>&1 ); rc=$?
    check "an id dropped from the ARCHIVE is 3a's refusal alone, not this one" \
        $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $out"
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)

    say ""
    say " mode 4e (LEDGER-CLOSURE-BURIED / LEDGER-ID-UNFILED) -- T-1106: a closure the anchor cannot"
    say "          see, and an id the allocator never heard of"
    # Half one is the other side of 4d. 4d defends the READING of the closure marker; nothing asked
    # whether the ledger writes its closures where that reading looks. Measured 2026-09-11 over
    # HEAD's docs/TODO.md: fourteen entries were closed in their body and open on their own first
    # line -- including T-1085, which read as open for five days after it shipped and was picked up
    # again by an agent who read its first line. Half two is T-1072's rule made enforceable: an id
    # that lives only in a commit message is invisible to the next agent computing "next free".
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws" && git show HEAD:TODO.md > TODO.md ) >/dev/null 2>&1
    # T-110 is buried: shipped, and saying so three lines in. T-111 is closed properly, so the
    # refusal has to name one and not the other.
    ( cd "$ws"
      git show HEAD:TODO.md > buried.md
      print -rl -- "" "- [T-110] **the thing that is not done yet.**" \
                      "  filed 2026-09-08, and then finished." \
                      "  **CLOSED 2026-09-11 (\`deadd0c\`).** shipped, and nothing can tell." \
                      "" "- [T-111] **CLOSED 2026-09-11 (\`deadd0e\`).** closed where the anchor looks" \
                      "  body" >> buried.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h1 -m "$M" TODO.md=buried.md 2>&1 ); rc=$?
    check "a closure written into an entry's body is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-CLOSURE-BURIED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the buried id is named, and the properly closed one is not" \
        $( [[ "$out" == *"T-110"* && "$out" != *"T-111"* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md ) != *"T-110"* ]] && print 1 || print 0 )
    out=$( cd "$ws" && zsh "$here" h1 -m "$M" --buried-closures T-111 TODO.md=buried.md 2>&1 ); rc=$?
    check "naming the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-CLOSURE-BURIED* ]] && print 1 || print 0 ) "exit $rc: $out"
    # The cure the refusal names: the same closure, on the entry's own first line.
    ( cd "$ws"
      git show HEAD:TODO.md > unburied.md
      print -rl -- "" "- [T-110] **CLOSED 2026-09-11 (\`deadd0c\`).** Originally: **the thing that is not done yet.**" \
                      "  filed 2026-09-08, and then finished." \
                      "" "- [T-111] **CLOSED 2026-09-11 (\`deadd0e\`).** closed where the anchor looks" \
                      "  body" >> unburied.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h2 -m "$M" TODO.md=unburied.md 2>&1 ); rc=$?
    check "moving the closure onto the first line is accepted" $(( rc == 0 )) "exit $rc: $out"
    check "and ledger_closed_ids can now see it" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md ) == *"T-110] **CLOSED"* ]] && print 1 || print 0 )
    # The narrowness control, and it is the one that decides this guard can live in the commit
    # path. T-992's real entry in docs/TODO.md contains the sentence *"first line to `**CLOSED
    # <date> (`sha`).**` when it lands"* -- the convention quoted MID-LINE, in an entry that is
    # about the convention. T-985's says "deleted the CLOSED copy" about another ticket. A reading
    # that took the word anywhere in a body, or a bold run anywhere in a line, refuses both.
    ( cd "$ws"
      git show HEAD:TODO.md > quoting.md
      print -rl -- "" "- [T-112] **open, and it is about the convention itself.**" \
                      "  The rule is to change the first line to \`**CLOSED <date> (\`sha\`).**\` when it lands," \
                      "  which nobody did for the CLOSED copy of the entry above." >> quoting.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h3 -m "$M" TODO.md=quoting.md 2>&1 ); rc=$?
    check "an open entry QUOTING the convention mid-line is not a buried closure" \
        $( [[ $rc == 0 && "$out" != *LEDGER-CLOSURE-BURIED* ]] && print 1 || print 0 ) "exit $rc: $out"
    # Half two. `T-901` is in no ledger, and the message is the only place it exists -- which is
    # precisely the state T-1117 was handed out in and the state both allocations of T-1119 read.
    local MU=$'msg for T-901\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
    ( cd "$ws" && print -r -- "unfiled" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" h4 -m "$MU" mine.txt 2>&1 ); rc=$?
    check "a message naming an id with no ledger entry is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNFILED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the unfiled id is named" $( [[ "$out" == *"T-901"* ]] && print 1 || print 0 ) "$out"
    check "and it is asked about a path that is not the ledger at all" \
        $( [[ "$out" != *NOTHING-TO-COMMIT* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" h4 -m "$MU" --unfiled-ids T-902 mine.txt 2>&1 ); rc=$?
    check "naming the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-UNFILED* ]] && print 1 || print 0 ) "exit $rc: $out"
    # The cure, and it is T-1072's rule: the stub goes in the SAME commit that first names the id.
    ( cd "$ws"
      git show HEAD:TODO.md > stub.md
      print -rl -- "" "- [T-901] **the stub, written where the allocator can see it.**" \
                      "  Reserved by the selftest." >> stub.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" h5 -m "$MU" mine.txt TODO.md=stub.md 2>&1 ); rc=$?
    check "writing the stub in the same commit is accepted" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws" && print -r -- "again" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" h6 -m "$MU" mine.txt 2>&1 ); rc=$?
    check "and the id stays usable afterwards with no flag" $(( rc == 0 )) "exit $rc: $out"
    # A quoted fragment that is not a ticket reference at all -- `gone=T-3` appears verbatim in
    # a499f2f8's real message. One commit in the last sixty measured, and the flag is the cost.
    local MQ=$'msg quoting gone=T-902 from a script\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
    ( cd "$ws" && print -r -- "quoted" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" h7 -m "$MQ" --unfiled-ids T-902 mine.txt 2>&1 ); rc=$?
    check "a quoted non-reference gets through by being named" $(( rc == 0 )) "exit $rc: $out"
    # And the negative control that decides the guard is not simply always-on: the ordinary commit,
    # naming ids that ARE filed, needs no flag at all. Every other mode in this selftest uses a
    # message with no id in it, so without this check the whole half could be inverted unnoticed.
    local MF=$'msg for T-901 and T-110\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
    ( cd "$ws" && print -r -- "filed" >> mine.txt )
    out=$( cd "$ws" && zsh "$here" h8 -m "$MF" mine.txt 2>&1 ); rc=$?
    check "a message naming only FILED ids needs no flag" $(( rc == 0 )) "exit $rc: $out"

    say ""
    say " mode 4f (LEDGER-ID-DUPLICATE) -- T-1072: the id two agents both computed as \"next free\""
    # The half LEDGER-ID-UNFILED cannot reach. That guard makes an UNFILED id impossible; both
    # agents in a concurrent allocation file a stub, so both messages pass it. What the collision
    # actually leaves is a ledger with two formal entries for one id, and until T-1136 nothing read
    # it -- three measured incidents (T-1119, T-1109/T-1110, T-1043) landed in exactly this shape.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws" && git show HEAD:TODO.md > TODO.md ) >/dev/null 2>&1
    # The sibling's stub for T-901 is already in HEAD (mode 4e filed it). This is the second agent
    # rebuilding on the new HEAD and carrying its own entry for the same id in beside it, which is
    # precisely what `939959e` did.
    ( cd "$ws"
      git show HEAD:TODO.md > collide.md
      print -rl -- "" "- [T-901] **the OTHER piece of work that read the same next-free value.**" \
                      "  Reserved by a second agent, minutes later, from the same ledger." >> collide.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" TODO.md=collide.md 2>&1 ); rc=$?
    check "a second formal entry for an id HEAD already has is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-DUPLICATE* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the doubly-allocated id is named" $( [[ "$out" == *"T-901"* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md | grep -c '^- \[T-901\]' ) == 1 ]] && print 1 || print 0 )
    out=$( cd "$ws" && zsh "$here" d1 -m "$M" --duplicate-ids T-902 TODO.md=collide.md 2>&1 ); rc=$?
    check "naming the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ID-DUPLICATE* ]] && print 1 || print 0 ) "exit $rc: $out"
    # The cure the refusal names, and the reason it is the right cure: renumbering YOUR entry is
    # the only repair that leaves both pieces of work addressable. Deleting either loses one.
    ( cd "$ws"
      git show HEAD:TODO.md > renumbered.md
      print -rl -- "" "- [T-903] **the OTHER piece of work that read the same next-free value.**" \
                      "  Renumbered off T-901 by the refusal." >> renumbered.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" d2 -m "$M" TODO.md=renumbered.md 2>&1 ); rc=$?
    check "renumbering to a free id is accepted" $(( rc == 0 )) "exit $rc: $out"
    check "and both pieces of work now have an id" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md | grep -cE '^- \[T-(901|903)\]' ) == 2 ]] && print 1 || print 0 )
    # THE CHECK THAT PINS THE DELTA READING, and it is the reason this guard can live in the commit
    # path at all. HEAD's real docs/TODO.md carries three standing duplicates -- T-781 and T-974
    # (a closure filed as a new entry beside the open original) and T-1043 (two genuinely different
    # tickets) -- and T-1072 decided that the allocator gets fixed and the collisions do not, so
    # renumbering them would orphan every reference. A whole-file reading would refuse every commit
    # to the ledger forever. This proves the pre-existing duplicate is tolerated and only a NEW one
    # refuses.
    ( cd "$ws"
      git show HEAD:TODO.md > collide2.md
      print -rl -- "" "- [T-901] **filed twice on purpose, to make the pre-existing duplicate real.**" \
                      "  So the next check is asked of a ledger that already carries one." >> collide2.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" d3 -m "$M" --duplicate-ids T-901 TODO.md=collide2.md 2>&1 ); rc=$?
    check "declaring the duplicate deliberately lands it" $(( rc == 0 )) "exit $rc: $out"
    ( cd "$ws"
      git show HEAD:TODO.md | sed 's/^  Renumbered off T-901 by the refusal./  Renumbered, and this line was later edited./' > afterdup.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" d4 -m "$M" --removes 1 TODO.md=afterdup.md 2>&1 ); rc=$?
    check "an ordinary later edit to a ledger that ALREADY has that duplicate needs no flag" \
        $( [[ $rc == 0 && "$out" != *LEDGER-ID-DUPLICATE* ]] && print 1 || print 0 ) "exit $rc: $out"

    say ""
    say " mode 4g (LEDGER-ENTRY-DUPLICATED) -- T-1142: a closure APPENDED to the draft it replaces"
    # The third failure of the same closure-writing step 4e guards. 4e asks whether the closure was
    # written where the anchor looks; this asks whether writing it replaced the draft or was pasted
    # under it. Measured on HEAD 2026-09-12: four entries carry their own body twice -- T-781,
    # T-986, T-991, T-992 -- all four created by one commit, `7584c5f`, unread for 40 commits since.
    # T-991 and T-992 said `CLOSED` on the first line and `NOT YET IN HEAD` in the body at once.
    rm -f "$CADENCE_DECLINED_LEDGER"/*.declined(N)
    ( cd "$ws" && git show HEAD:TODO.md > TODO.md ) >/dev/null 2>&1
    # T-120 is the defect: a progress note, then the closure pasted underneath with the note's own
    # paragraph repeated verbatim. T-121 is a long entry that says everything once.
    ( cd "$ws"
      git show HEAD:TODO.md > dup.md
      print -rl -- "" "- [T-120] **CLOSED 2026-09-12 (\`deadd10\`).** Originally: the finding, stated once." \
                      "  **RESOLVED IN THE CHECKOUT 2026-09-12, NOT YET IN HEAD** -- one --removes short." \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  Measured afterwards: nothing refused, and the positive control caught them all." \
                      "  Pinned by the mode that follows, so removing it cannot go unnoticed later." \
                      "  **CLOSED 2026-09-12 (\`deadd10\`).**" \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  Measured afterwards: nothing refused, and the positive control caught them all." \
                      "  Pinned by the mode that follows, so removing it cannot go unnoticed later." \
                      "" "- [T-121] **CLOSED 2026-09-12 (\`deadd11\`).** Originally: a long entry that repeats nothing." \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  A second paragraph that differs from the first in every one of its own lines," \
                      "  so that a reader comparing the two entries sees length and not repetition." >> dup.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" j1 -m "$M" TODO.md=dup.md 2>&1 ); rc=$?
    check "an entry that contains its own body twice is refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ENTRY-DUPLICATED* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "the duplicated id is named, and the long entry that repeats nothing is not" \
        $( [[ "$out" == *"T-120"* && "$out" != *"T-121"* ]] && print 1 || print 0 ) "$out"
    check "and it says how long the repeated run is, so the reading can be checked by hand" \
        $( [[ "$out" == *"repeated lines"* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" \
        $( [[ $( cd "$ws" && git show HEAD:TODO.md ) != *"T-120"* ]] && print 1 || print 0 )
    out=$( cd "$ws" && zsh "$here" j2 -m "$M" --duplicated-entries T-121 TODO.md=dup.md 2>&1 ); rc=$?
    check "declaring the WRONG id is still refused" \
        $( [[ $rc == 3 && "$out" == *LEDGER-ENTRY-DUPLICATED* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" j3 -m "$M" --duplicated-entries T-120 TODO.md=dup.md 2>&1 ); rc=$?
    check "declaring it deliberately lets the repetition through" $(( rc == 0 )) "exit $rc: $out"
    # The delta control, and the reason this guard is delta-read at all: once a duplicated entry is
    # in HEAD, ordinary later edits to that ledger must not inherit its refusal. A whole-file
    # reading would refuse every commit of this file until somebody else's entry was cleaned up,
    # and the first thing a blocked agent reaches for is the escape flag.
    ( cd "$ws"
      git show HEAD:TODO.md | sed 's/^  \*\*RESOLVED IN THE CHECKOUT.*/  **RESOLVED IN THE CHECKOUT 2026-09-12** -- and this line was later edited./' > afterj.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" j4 -m "$M" --removes 1 TODO.md=afterj.md 2>&1 ); rc=$?
    check "an ordinary later edit to a ledger that ALREADY has that duplicate needs no flag" \
        $( [[ $rc == 0 && "$out" != *LEDGER-ENTRY-DUPLICATED* ]] && print 1 || print 0 ) "exit $rc: $out"
    # And the positive control on the delta reading: a SECOND entry duplicated on top of the first
    # still refuses, so "already there" is not a blanket amnesty for the file.
    ( cd "$ws"
      git show HEAD:TODO.md > dup2.md
      print -rl -- "" "- [T-122] **CLOSED 2026-09-12 (\`deadd12\`).** Originally: a second entry, duplicated later." \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  Measured afterwards: nothing refused, and the positive control caught them all." \
                      "  Pinned by the mode that follows, so removing it cannot go unnoticed later." \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  Measured afterwards: nothing refused, and the positive control caught them all." \
                      "  Pinned by the mode that follows, so removing it cannot go unnoticed later." >> dup2.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" j5 -m "$M" TODO.md=dup2.md 2>&1 ); rc=$?
    check "a NEW duplicated entry still refuses in a ledger that already carries one" \
        $( [[ $rc == 3 && "$out" == *"T-122"* && "$out" != *"T-120"* ]] && print 1 || print 0 ) "exit $rc: $out"

    say ""
    say " mode 4g2 (T-1143) -- the declared-id flags must take the list they document"
    # Every --<x>-ids flag documents `<exact,sorted,list>` and until 2026-09-12 neither side was
    # sorted OR comma-joined: `${(j:,:)${(o)$arr}}` with no `(@)` flattens the array first, so both
    # operators act on one element and do nothing. Masked everywhere, because every older list is
    # fed by `comm` or `sort -u` and arrives sorted anyway -- and because all twelve existing
    # exercises of these flags declare exactly ONE id, where sorting and joining are unobservable.
    # This is the multi-id case: two entries duplicated at once, declared in the documented form.
    ( cd "$ws"
      git show HEAD:TODO.md > dup3.md
      print -rl -- "" "- [T-131] **CLOSED 2026-09-12 (\`deadd13\`).** Originally: the first of two, both duplicated." \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  Measured afterwards: nothing refused, and the positive control caught them all." \
                      "  Pinned by the mode that follows, so removing it cannot go unnoticed later." \
                      "  The decision the ticket asked for is yes, and here is the reasoning behind it," \
                      "  which runs to several lines so that the repeated run is unmistakably a paragraph." \
                      "  Measured afterwards: nothing refused, and the positive control caught them all." \
                      "  Pinned by the mode that follows, so removing it cannot go unnoticed later." \
                      "" "- [T-130] **CLOSED 2026-09-12 (\`deadd14\`).** Originally: the second of two, filed out of order." \
                      "  A different paragraph, repeated below, so the two ids are found in file" \
                      "  order T-131 then T-130 and a sorted list is observably not that order." \
                      "  It has to be four lines long, because four is the minimum duplicated run." \
                      "  So here is a fourth line, bringing the repeated run up to that minimum." \
                      "  A different paragraph, repeated below, so the two ids are found in file" \
                      "  order T-131 then T-130 and a sorted list is observably not that order." \
                      "  It has to be four lines long, because four is the minimum duplicated run." \
                      "  So here is a fourth line, bringing the repeated run up to that minimum." >> dup3.md ) >/dev/null 2>&1
    out=$( cd "$ws" && zsh "$here" k1 -m "$M" TODO.md=dup3.md 2>&1 ); rc=$?
    check "two duplicated entries at once are both refused" \
        $( [[ $rc == 3 && "$out" == *"T-130"* && "$out" == *"T-131"* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the hint it prints is SORTED and comma-joined, not the order they were found in" \
        $( [[ "$out" == *"--duplicated-entries T-130,T-131"* ]] && print 1 || print 0 ) "$out"
    out=$( cd "$ws" && zsh "$here" k2 -m "$M" --duplicated-entries "T-130,T-131" TODO.md=dup3.md 2>&1 ); rc=$?
    check "the documented comma-separated sorted list is accepted" $(( rc == 0 )) "exit $rc: $out"

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

    say ""
    say " mode 8 (SWEEP-MANIFEST-MISSING) -- a test that walks the product tree must arrive with its"
    say "         manifest entry, at the commit, not 22 minutes later in someone else's suite run"
    say "         ...and it must not be disableable by the precheck not being there, or not answering"
    say "         (SWEEP-CHECK-MISSING / SWEEP-CHECK-FAILED)"
    # The mutation this is here to kill: a `@Test` that sweeps the real product tree, committed with
    # no line for it in CadenceRealTreeSweepManifest.txt. Both directions are asked, because a check
    # that flags everything and a check that flags nothing both pass a one-sided test.
    # Every later revision of this file only ADDS lines, so REMOVES-HEAD-LINES stays out of the way
    # and each check below is answering the question it was written for.
    ( cd "$ws"
      mkdir -p CadenceTests
      print -r -- "SweepSelftestSuite/theSweepThatIsAlreadyListed" > CadenceTests/CadenceRealTreeSweepManifest.txt
      print -rl -- 'import Testing' \
          '' \
          'struct SweepSelftestSuite {' \
          '    @Test func theSweepThatIsAlreadyListed() throws {' \
          '        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") { #expect(!path.isEmpty) }' \
          '    }' \
          '}' > CadenceTests/SweepSelftest.swift
      git add CadenceTests >/dev/null
      git commit -qm "sweep fixture

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" )
    ( cd "$ws" && print -rl -- 'import Testing' \
        '' \
        'struct SweepSelftestSuite {' \
        '    @Test func theSweepThatIsAlreadyListed() throws {' \
        '        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") { #expect(!path.isEmpty) }' \
        '    }' \
        '' \
        '    @Test func theNewSweepNobodyListed() throws {' \
        '        for path in try CadenceSourceScan.swiftFiles(under: "CadenceWidgets") {' \
        '            #expect(path.hasSuffix(".swift"))' \
        '        }' \
        '    }' \
        '}' > CadenceTests/SweepSelftest.swift
    )
    out=$( cd "$ws" && zsh "$here" s8 -m "$M" CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "an unlisted product-tree sweep is refused" \
        $( [[ $rc == 3 && "$out" == *SWEEP-MANIFEST-MISSING* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and the exact @Test is named" \
        $( [[ "$out" == *theNewSweepNobodyListed* ]] && print 1 || print 0 ) "$out"
    check "the sweep that IS listed is not dragged in with it" \
        $( [[ "$out" != *theSweepThatIsAlreadyListed* ]] && print 1 || print 0 ) "$out"
    check "nothing was committed" \
        $( [[ $( cd "$ws" && git show HEAD:CadenceTests/SweepSelftest.swift ) != *theNewSweepNobodyListed* ]] && print 1 || print 0 )
    check "it says how to regenerate, and says not to hand-edit" \
        $( [[ "$out" == *"real-tree-sweep-manifest.sh"*"--write"* ]] && print 1 || print 0 ) "$out"

    # A manifest edited in the CHECKOUT and left out of the commit clears nothing: the file HEAD
    # ends up with is the one that has to name the sweep, and this checkout is not it (T-975 --
    # a commit lands through a private index and never writes the checkout).
    ( cd "$ws" && print -rl -- "SweepSelftestSuite/theSweepThatIsAlreadyListed" \
        "SweepSelftestSuite/theNewSweepNobodyListed" > CadenceTests/CadenceRealTreeSweepManifest.txt )
    out=$( cd "$ws" && zsh "$here" s8w -m "$M" CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "a manifest edited only in the checkout does not clear the check" \
        $( [[ $rc == 3 && "$out" == *SWEEP-MANIFEST-MISSING* ]] && print 1 || print 0 ) "exit $rc: $out"
    ( cd "$ws" && git show HEAD:CadenceTests/CadenceRealTreeSweepManifest.txt > CadenceTests/CadenceRealTreeSweepManifest.txt )

    # The override has to cost the same thing `--removes <n>` costs: reading the refusal. Naming
    # some other test does not get you past it.
    out=$( cd "$ws" && zsh "$here" s8a -m "$M" --not-a-sweep theSweepThatIsAlreadyListed \
        CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "--not-a-sweep naming the WRONG test is still refused" \
        $( [[ $rc == 3 && "$out" == *SWEEP-MANIFEST-MISSING* ]] && print 1 || print 0 ) "exit $rc: $out"
    out=$( cd "$ws" && zsh "$here" s8a2 -m "$M" --not-a-sweep theNewSweepNobodyListed \
        CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "naming the right one lets it through deliberately" $(( rc == 0 )) "exit $rc: $out"
    check "and it says out loud which names were waved past" \
        $( [[ "$out" == *"--not-a-sweep"*theNewSweepNobodyListed* ]] && print 1 || print 0 ) "$out"

    # Committing the regenerated manifest ALONGSIDE the test is what clears it -- the manifest read
    # is the one this commit would leave behind, not the checkout's copy.
    ( cd "$ws" && print -rl -- "SweepSelftestSuite/theNewSweepNobodyListed" \
        "SweepSelftestSuite/theSweepThatIsAlreadyListed" > sweep-manifest.txt )
    out=$( cd "$ws" && zsh "$here" s8b -m "$M" CadenceTests/SweepSelftest.swift \
        CadenceTests/CadenceRealTreeSweepManifest.txt=sweep-manifest.txt 2>&1 ); rc=$?
    check "the same commit WITH the regenerated manifest is accepted" $(( rc == 0 )) "exit $rc: $out"
    check "and HEAD now names the new sweep" \
        $( [[ $( cd "$ws" && git show HEAD:CadenceTests/CadenceRealTreeSweepManifest.txt ) == *theNewSweepNobodyListed* ]] && print 1 || print 0 )

    # A test that names product paths but walks nothing must commit untouched, or the guard is the
    # "flags everything" failure and every test author learns to reach for --not-a-sweep.
    ( cd "$ws" && print -rl -- 'import Testing' \
        '' \
        'struct SweepSelftestSuite {' \
        '    @Test func theSweepThatIsAlreadyListed() throws {' \
        '        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") { #expect(!path.isEmpty) }' \
        '    }' \
        '' \
        '    @Test func theNewSweepNobodyListed() throws {' \
        '        for path in try CadenceSourceScan.swiftFiles(under: "CadenceWidgets") {' \
        '            #expect(path.hasSuffix(".swift"))' \
        '        }' \
        '    }' \
        '' \
        '    @Test func theFixedFileAssertionThatWalksNothing() throws {' \
        '        let source = try CadenceSourceScan.sourceFile("Cadence/Models/AppTask.swift")' \
        '        #expect(!source.isEmpty)' \
        '    }' \
        '}' > CadenceTests/SweepSelftest.swift
    )
    out=$( cd "$ws" && zsh "$here" s8c -m "$M" CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "a fixed-file assertion that walks nothing commits with no manifest change" \
        $(( rc == 0 )) "exit $rc: $out"

    # And it must not be disableable by the precheck simply not being there, or not answering. Same
    # shape as DRIFT-CHECK-MISSING above: "the check could not run, so everything is fine" is the
    # hollow instrument in miniature. `worktree-drift.sh` is copied along so the run gets far enough
    # to reach this check rather than stopping one guard earlier.
    ( cd "$ws" && mkdir -p lonely8 && cp "$here" lonely8/agent-commit.sh
      cp "${here:h}/worktree-drift.sh" lonely8/worktree-drift.sh
      print -r -- "// a sweep committed with no precheck nearby" >> CadenceTests/SweepSelftest.swift )
    out=$( cd "$ws" && zsh "$ws/lonely8/agent-commit.sh" s8d -m "$M" CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "a copy with no real-tree-sweep-manifest.sh beside it refuses rather than skipping" \
        $( [[ $rc == 3 && "$out" == *SWEEP-CHECK-MISSING* ]] && print 1 || print 0 ) "exit $rc: $out"
    check "and nothing was committed by it" \
        $( [[ $( cd "$ws" && git show HEAD:CadenceTests/SweepSelftest.swift ) != *"no precheck nearby"* ]] && print 1 || print 0 )
    ( cd "$ws" && print -rl -- '#!/bin/zsh' 'print -r -- "something went wrong" >&2; exit 2' > lonely8/real-tree-sweep-manifest.sh )
    out=$( cd "$ws" && zsh "$ws/lonely8/agent-commit.sh" s8e -m "$M" CadenceTests/SweepSelftest.swift 2>&1 ); rc=$?
    check "a precheck that exits neither 0 nor 4 is refused, not read as a pass" \
        $( [[ $rc == 3 && "$out" == *SWEEP-CHECK-FAILED* ]] && print 1 || print 0 ) "exit $rc: $out"

    # The precheck's own fixtures -- the helper-hop sweep, the fixed-file assertion, the sweep that
    # exists only inside a string literal, and both vacuity ends -- are asserted next door, and
    # chained to here so that "run agent-commit.sh selftest before a batch closes" (T-781) covers
    # them too. A selftest no runbook names is the hollow instrument one layer along.
    out=$(zsh "${here:h}/real-tree-sweep-manifest.sh" selftest-chain precheck-selftest 2>&1); rc=$?
    check "the precheck's own selftest passes (chained)" $(( rc == 0 )) "exit $rc: $out"

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
