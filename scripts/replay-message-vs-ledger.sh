#!/bin/zsh
# Replay `agent-commit.sh`'s LEDGER-HUNK-UNCLAIMED reading (T-1304) over real history.
#
#   ./scripts/replay-message-vs-ledger.sh                    # the shipped reading, over HEAD
#   ./scripts/replay-message-vs-ledger.sh --reading subject   # the reading the ticket sketched
#   ./scripts/replay-message-vs-ledger.sh --entries rewritten # only entries that already existed
#   ./scripts/replay-message-vs-ledger.sh --window 150        # …over the last 150 ledger commits
#   ./scripts/replay-message-vs-ledger.sh --commit 938cdb7    # one commit, reachable or not
#
# WHY IT IS A SCRIPT AND NOT A MEASUREMENT IN A TICKET. Every guard in this family needs the same
# question answered before it is allowed to refuse anything -- *how many commits that this
# repository actually made would this have stopped* -- and the answer decides between a refusal, a
# warning and nothing at all. T-1300 answered it with 191 in 274 and settled on a warning; T-1304
# answered it with 4 in 511 and shipped a refusal. Both numbers rot: the next commit changes them,
# and a number quoted in prose cannot be re-derived by the agent who needs to widen the rule. This
# can be re-run in about a minute.
#
# THE READING, which is `agent-commit.sh`'s 3a5b verbatim: a commit is REFUSED when the ids its
# message names and the ids whose formal ledger entries its hunk changes are both non-empty and
# DISJOINT. The shape it is about is `938cdb7`, which committed ledgerguard's T-1206 + T-1207 +
# T-1209 diff under reorderfeel's T-1174 + T-1175 subject line, because both agents wrote
# `.../scratchpad/msg.txt` and `-F` read whichever landed last.
#
# MEASURED 2026-09-22 at `22a4eb1`, over the 511 commits reachable from HEAD that touch a ledger:
#
#   --reading message  --entries touched     4 refusals   (0 in the last 150, 1 in the last 300)
#   --reading subject  --entries touched    13 refusals   (the reading T-1304 sketched)
#   --reading message  --entries rewritten  10 refusals
#   --reading subject  --entries rewritten  12 refusals
#
# and `938cdb7` -- which is still in the object store though no longer reachable -- is refused by
# all four, while `0fb5504`, the same diff under its own message, is refused by none. The choice of
# message-side set is therefore the whole difference between a usable refusal and an unusable one:
# the subject-only reading adds nine ordinary residue filings, and `--entries rewritten` adds six
# commits that closed one ticket while tidying a neighbouring entry. What makes the shipped
# reading quiet is this repository's own practice of describing, in the message body, every entry
# the commit writes -- which is also exactly the repair the refusal asks for.
#
# A CORRECTION TO THE FIRST DRAFT OF THIS HEADER, which is the whole argument for the script: it
# quoted `--entries rewritten` at 18. Re-run at `22a4eb1` it is 10, twice, and no combination of
# the two switches produces 18. The number was not re-derivable and it was wrong, which is exactly
# the rot the file exists to make cheap to catch -- so re-run it rather than cite it.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 2
say() { print -r -- "$@" }

READING=message      # message | subject
ENTRIES=touched      # touched | rewritten
WINDOW=0             # 0 = every ledger commit reachable from the rev
REV=HEAD
ONE=""
VERBOSE=0
while (( $# )); do
  case "$1" in
    --reading) READING="${2:-}"; shift 2 ;;
    --entries) ENTRIES="${2:-}"; shift 2 ;;
    --window)  WINDOW="${2:-0}"; shift 2 ;;
    --commit)  ONE="${2:-}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *)         REV="$1"; shift ;;
  esac
done
case "$READING" in message|subject) ;; *) say "unknown --reading '$READING'"; exit 2 ;; esac
case "$ENTRIES" in touched|rewritten) ;; *) say "unknown --entries '$ENTRIES'"; exit 2 ;; esac

WS=$(mktemp -d "${TMPDIR:-/private/tmp/}cadence-ledger-replay-XXXXXX")
trap 'rm -rf "$WS"' EXIT INT TERM

# `<id>\t<line>` for every line inside a formal `- [T-n]` entry, the entry running until the next
# line that starts in column one and is not blank. Duplicated from `agent-commit.sh`'s
# `ledger_entry_lines` rather than shared, for the reason that file gives for duplicating the git
# probe: a reading that needs another file loaded before it can answer is a reading with a new way
# to stop answering. Mode 4m of that script's selftest is what keeps the two honest.
entry_lines() {  # $1 = ledger file
  awk '
    {
      if ($0 ~ /^- \[T-[0-9]+\]/) { id = $0; sub(/^- \[/, "", id); sub(/\].*$/, "", id) }
      else if ($0 !~ /^[ \t]/ && $0 != "") { id = "" }
      # Blank lines are attributed to nothing; see `ledger_entry_lines` in agent-commit.sh.
      if (id != "" && $0 != "") print id "\t" $0
    }' "$1" 2>/dev/null
}

# No `--` before the filename anywhere in here: BSD awk reads `--` as a FILE NAME and dies with
# "can't open file --", and with stderr discarded that failure is an empty reading rather than an
# error -- which is a replay that examines nothing and reports 0 refusals (measured while writing
# this).
entry_ids() { awk '/^- \[T-[0-9]+\]/ { id = $0; sub(/^- \[/, "", id); sub(/\].*$/, "", id); print id }' "$1" 2>/dev/null | sort -u }

# The ids whose entries differ between two revisions of one ledger. `rewritten` keeps only entries
# that exist on BOTH sides, i.e. drops the stubs the commit files for the first time.
changed_entry_ids() {  # $1 = old blob, $2 = new blob
  entry_lines "$1" | sort -u > "$WS/old.lines"
  entry_lines "$2" | sort -u > "$WS/new.lines"
  # The `;` before `}` is not optional: without it zsh reads the group's last command and the
  # pipeline that follows as separate statements, and the file ends up empty (measured).
  { comm -23 "$WS/old.lines" "$WS/new.lines"; comm -13 "$WS/old.lines" "$WS/new.lines"; } |
    cut -f1 | sort -u > "$WS/changed.ids"
  if [[ "$ENTRIES" == "rewritten" ]]; then
    entry_ids "$1" > "$WS/old.ids"; entry_ids "$2" > "$WS/new.ids"
    comm -12 "$WS/old.ids" "$WS/new.ids" > "$WS/both.ids"
    comm -12 "$WS/changed.ids" "$WS/both.ids"
  else
    cat "$WS/changed.ids"
  fi
}

# The message side. `subject` is `agent-commit.sh`'s `subject_ids` -- first line only, `T-1..T-4`
# ranges expanded -- and `message` is its `message_ids`, every `T-<n>` in the whole message.
message_side_ids() {  # $1 = sha
  if [[ "$READING" == "subject" ]]; then
    git log -1 --format=%s "$1" | awk '
      {
        rest = $0; prev = -1
        while (match(rest, /T-[0-9]+/)) {
          tok = substr(rest, RSTART, RLENGTH); sep = substr(rest, 1, RSTART - 1)
          b = substr(tok, 3) + 0
          if (prev >= 0 && sep ~ /^ *\.\.+ *$/ && b > prev && b - prev <= 64)
            for (i = prev + 1; i < b; i++) print "T-" i
          print tok; prev = b
          rest = substr(rest, RSTART + RLENGTH)
        }
      }' | sort -u
  else
    git log -1 --format=%B "$1" | grep -oE '\bT-[0-9]+\b' | sort -u
  fi
}

examined=0 hits=0 ledger_commits=0
declare -a hit_lines; hit_lines=()
verdict_for() {  # $1 = sha; prints the finding, or nothing
  # `lpath`, never `path`: in zsh `path` is tied to $PATH, so a `local path` empties it for the
  # whole scope and every command in it dies with `command not found` (T-787's shape exactly).
  local sha=$1 lpath
  local -a paths
  paths=(${(f)"$(git show --pretty=format: --name-only "$sha" 2>/dev/null | grep -E '(^|/)TODO(_DONE)?\.md$')"})
  (( ${#paths} )) || return 1
  [[ -n "${paths[1]}" ]] || return 1
  (( ledger_commits++ ))
  : > "$WS/entry.ids"
  for lpath in $paths; do
    [[ -n "$lpath" ]] || continue
    git cat-file -p "$sha:$lpath"  > "$WS/side.new" 2>/dev/null || : > "$WS/side.new"
    git cat-file -p "$sha^:$lpath" > "$WS/side.old" 2>/dev/null || : > "$WS/side.old"
    changed_entry_ids "$WS/side.old" "$WS/side.new" >> "$WS/entry.ids"
  done
  sort -u "$WS/entry.ids" > "$WS/entry.sorted"
  message_side_ids "$sha" > "$WS/msg.sorted"
  (( examined++ ))
  [[ -s "$WS/entry.sorted" && -s "$WS/msg.sorted" ]] || return 1
  [[ -z "$(comm -12 "$WS/msg.sorted" "$WS/entry.sorted")" ]] || return 1
  hit_lines+=("  $(git log -1 --format='%h %ad' --date=short "$sha")  message ${(j:,:)${(f)"$(cat "$WS/msg.sorted")"}}  vs ledger ${(j:,:)${(f)"$(cat "$WS/entry.sorted")"}}  | $(git log -1 --format=%s "$sha" | cut -c1-58)")
  (( hits++ ))
  return 0
}

say "== replay: message ids vs ledger-entry ids (--reading $READING --entries $ENTRIES) =="
if [[ -n "$ONE" ]]; then
  if verdict_for "$ONE"; then
    say "REFUSED:"; print -rl -- "${hit_lines[@]}"
  else
    say "not refused: $(git log -1 --format='%h %s' "$ONE" 2>/dev/null | cut -c1-70)"
  fi
  exit 0
fi

for sha in ${(f)"$(git rev-list "$REV")"}; do
  [[ -n "$sha" ]] || continue
  verdict_for "$sha"
  (( WINDOW > 0 && ledger_commits >= WINDOW )) && break
done

# The floors this family's other checks carry (T-1298's LEDGER-LAG-VACUOUS): a replay that examined
# nothing prints "0 refusals", which is the most reassuring possible report over an empty set.
if (( ledger_commits < 5 )); then
  say "REPLAY-VACUOUS: only $ledger_commits ledger-touching commit(s) examined -- a shallow clone, or"
  say "  the ledger path predicate has rotted. The number below is about nothing."
  exit 4
fi
say "  ledger-touching commits examined: $ledger_commits"
say "  would have been refused:          $hits"
(( ${#hit_lines} )) && print -rl -- "${hit_lines[@]}"
exit 0
