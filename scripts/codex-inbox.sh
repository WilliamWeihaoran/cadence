#!/bin/bash
# codex-inbox.sh — what has Codex answered that the coordinator has not acted on yet?
#
# docs/CODEX_REQUESTS.md is a queue the coordinator writes to and Codex answers into,
# asynchronously and out of band. Nothing in this repository notices an arrival, so the
# 15-minute heartbeat calls this instead of re-deriving the state in prose every fire.
#
# State lives in the document itself, as a single marker line, so it survives a lost
# scratchpad and cannot drift away from the thing it describes:
#
#     <!-- FOLDED-THROUGH: R24 -->
#
# Exit 0 always. This is a report, not a gate.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 0
DOC=docs/CODEX_REQUESTS.md
[ -f "$DOC" ] || { echo "no $DOC"; exit 0; }

marker=$(grep -oE '<!-- FOLDED-THROUGH: R[0-9]+ -->' "$DOC" | tail -1 | grep -oE 'R[0-9]+' | tr -d 'R')
marker=${marker:-0}

# A request is any "## R<n> — ..." heading. It is answered when an "ANSWER" line
# appears after it and before the next request heading.
answered=$(awk '
  /^## R[0-9]+ / { if (id != "" && seen) print id; id = $2; sub(/^R/, "", id); seen = 0; next }
  /^ANSWER/     { seen = 1 }
  END           { if (id != "" && seen) print id }
' "$DOC" | sort -n)

open=$(awk '
  /^## R[0-9]+ / {
    if (id != "" && !seen && !standing) print id
    id = $2; sub(/^R/, "", id); seen = 0
    standing = ($0 ~ /Standing:/)
    next
  }
  /^ANSWER/     { seen = 1 }
  END           { if (id != "" && !seen && !standing) print id }
' "$DOC" | sort -n)

new=""
for n in $answered; do [ "$n" -gt "$marker" ] && new="$new R$n"; done

echo "folded through: R$marker"
if [ -n "$new" ]; then
  echo "NEW ANSWERS TO ACT ON:$new"
  echo
  echo "For each: read only that request's section, turn its dispositions into tickets in the"
  echo "coordinator's reserved id range, place them in the batch plan, then move the marker:"
  echo "  sed -i '' 's/<!-- FOLDED-THROUGH: R[0-9]*/<!-- FOLDED-THROUGH: R$(echo $new | tr ' ' '\n' | tail -1 | tr -d 'R')/' $DOC"
else
  echo "no new answers"
fi

[ -n "$open" ] && echo "still unanswered: $(echo $open | sed 's/\([0-9]*\)/R\1/g')"
echo "standing (recurring, never 'answered'): $(grep -oE '^## R[0-9]+ .*Standing:' "$DOC" | grep -oE 'R[0-9]+' | tr '\n' ' ')"
exit 0
