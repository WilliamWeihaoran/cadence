#!/bin/bash
# codex-inbox.sh — what has Codex answered that the coordinator has not acted on yet?
#
# docs/CODEX_REQUESTS.md is a queue the coordinator writes to and Codex answers into,
# asynchronously and out of band. Nothing in this repository notices an arrival, so the
# 15-minute heartbeat calls this instead of re-deriving the state in prose every fire.
#
# State lives in the document itself, so it survives a lost scratchpad and cannot drift
# away from the thing it describes. TWO markers, and the second one is the whole point:
#
#     <!-- FOLDED-THROUGH: R54 -->
#     <!-- FOLDED-ALSO: R63 -->
#
# T-1330. This used to be ONE marker read as a high-water mark, and the remediation this
# script itself printed set it to the highest new id. Codex answers whichever request it
# picks up, not the lowest — R63 was answered while R55-R62 were still open — so following
# that instruction wrote R63 and every later answer to R55-R62 would have failed `n > marker`
# forever. The loss was invisible: `open` is computed separately, by looking for a missing
# ANSWER line, so "still unanswered" kept listing R55-R62 exactly as before while "NEW
# ANSWERS TO ACT ON" silently never mentioned them again. FOLDED-THROUGH is now only a
# baseline for the contiguous run at the bottom; anything folded out of order is named
# explicitly in FOLDED-ALSO, and the baseline absorbs it once the run becomes contiguous.
#
# Do not hand-edit either marker. `fold` maintains both, which is why it exists: the old
# hand-written sed was the defect.
#
#   scripts/codex-inbox.sh                 report (default)
#   scripts/codex-inbox.sh fold R63 R57    record ids as acted on
#   scripts/codex-inbox.sh selftest        prove the out-of-order case still reports
#
# Exit 0 always in report mode. This is a report, not a gate. `selftest` exits nonzero on
# failure, and `fold` exits nonzero if it cannot write.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 0
DOC=${CODEX_INBOX_DOC:-docs/CODEX_REQUESTS.md}

read_baseline() {
  local m
  m=$(grep -oE '<!-- FOLDED-THROUGH: R[0-9]+ -->' "$1" | tail -1 | grep -oE '[0-9]+')
  echo "${m:-0}"
}

read_also() {
  grep -oE '<!-- FOLDED-ALSO:[^>]*-->' "$1" | tail -1 | grep -oE 'R[0-9]+' | tr -d 'R' | sort -n -u
}

# A request is any "## R<n> — ..." heading. It is answered when an "ANSWER" line appears
# after it and before the next request heading.
read_answered() {
  awk '
    /^## R[0-9]+ / { if (id != "" && seen) print id; id = $2; sub(/^R/, "", id); seen = 0; next }
    /^ANSWER/     { seen = 1 }
    END           { if (id != "" && seen) print id }
  ' "$1" | sort -n
}

read_open() {
  awk '
    /^## R[0-9]+ / {
      if (id != "" && !seen && !standing) print id
      id = $2; sub(/^R/, "", id); seen = 0
      standing = ($0 ~ /Standing:/)
      next
    }
    /^ANSWER/     { seen = 1 }
    END           { if (id != "" && !seen && !standing) print id }
  ' "$1" | sort -n
}

# The one reading the old watermark got wrong: folded is the baseline run UNION the named
# set, never "anything above the highest thing I have seen".
is_folded() {
  local n=$1 baseline=$2 also=$3 a
  [ "$n" -le "$baseline" ] && return 0
  for a in $also; do [ "$n" -eq "$a" ] && return 0; done
  return 1
}

unfolded_answers() {
  local doc=$1 baseline=$2 also=$3 n out=""
  for n in $(read_answered "$doc"); do
    is_folded "$n" "$baseline" "$also" || out="$out $n"
  done
  echo "${out# }"
}

cmd_report() {
  local doc=$1 baseline also new
  baseline=$(read_baseline "$doc")
  also=$(read_also "$doc" | tr '\n' ' ')
  new=$(unfolded_answers "$doc" "$baseline" "$also")

  echo "folded through: R$baseline"
  [ -n "${also// /}" ] && echo "folded also:    $(echo "$also" | sed -E 's/([0-9]+)/R\1/g')"
  if [ -n "$new" ]; then
    echo "NEW ANSWERS TO ACT ON: $(echo "$new" | sed -E 's/([0-9]+)/R\1/g')"
    echo
    echo "For each: read only that request's section, turn its dispositions into tickets in the"
    echo "coordinator's reserved id range, place them in the batch plan, then record it:"
    echo "  scripts/codex-inbox.sh fold $(echo "$new" | sed -E 's/([0-9]+)/R\1/g')"
    echo "Fold only the ones you actually acted on — partial is normal and is why this takes a list."
  else
    echo "no new answers"
  fi

  local open
  open=$(read_open "$doc" | tr '\n' ' ')
  [ -n "${open// /}" ] && echo "still unanswered: $(echo "$open" | sed -E 's/([0-9]+)/R\1/g')"
  echo "standing (recurring, never 'answered'): $(grep -oE '^## R[0-9]+ .*Standing:' "$doc" | grep -oE 'R[0-9]+' | tr '\n' ' ')"
}

cmd_fold() {
  local doc=$1; shift
  [ $# -gt 0 ] || { echo "fold: name at least one request id, e.g. fold R63" >&2; return 2; }
  grep -qE '<!-- FOLDED-THROUGH: R[0-9]+ -->' "$doc" || { echo "fold: no FOLDED-THROUGH marker in $doc" >&2; return 2; }

  local baseline also arg n
  baseline=$(read_baseline "$doc")
  also=$(read_also "$doc" | tr '\n' ' ')

  for arg in "$@"; do
    n=$(echo "$arg" | grep -oE '[0-9]+')
    [ -n "$n" ] || { echo "fold: '$arg' is not a request id" >&2; return 2; }
    is_folded "$n" "$baseline" "$also" && continue
    also="$also $n"
  done
  also=$(echo "$also" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n -u | tr '\n' ' ')

  # Absorb the contiguous run, so the named set stays short and the baseline stays meaningful.
  local absorbed=1
  while [ "$absorbed" -eq 1 ]; do
    absorbed=0
    for n in $also; do
      if [ "$n" -eq $((baseline + 1)) ]; then
        baseline=$n
        also=$(echo "$also" | tr ' ' '\n' | grep -E '^[0-9]+$' | grep -vx "$n" | sort -n -u | tr '\n' ' ')
        absorbed=1
        break
      fi
    done
  done

  local alsoline=""
  [ -n "${also// /}" ] && alsoline="<!-- FOLDED-ALSO: $(echo "$also" | sed -E 's/([0-9]+)/R\1/g' | sed 's/ *$//') -->"

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/codex-inbox.XXXXXX") || return 1
  BASELINE="$baseline" ALSOLINE="$alsoline" awk '
    /<!-- FOLDED-ALSO:[^>]*-->/ { next }
    /<!-- FOLDED-THROUGH: R[0-9]+ -->/ {
      print "<!-- FOLDED-THROUGH: R" ENVIRON["BASELINE"] " -->"
      if (ENVIRON["ALSOLINE"] != "") print ENVIRON["ALSOLINE"]
      next
    }
    { print }
  ' "$doc" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$doc" || { rm -f "$tmp"; return 1; }

  echo "folded through: R$baseline"
  [ -n "$alsoline" ] && echo "$alsoline"
  return 0
}

# ---------------------------------------------------------------------------
# selftest — the case the watermark got wrong, plus the two that keep the fix honest.
# ---------------------------------------------------------------------------
cmd_selftest() {
  local dir rc=0 passed=0 failed=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-inbox-selftest.XXXXXX") || return 1
  trap 'rm -rf "$dir"' RETURN

  fixture() {
    local f=$1; shift
    {
      echo "<!-- FOLDED-THROUGH: R$1 -->"
      [ -n "${2:-}" ] && echo "<!-- FOLDED-ALSO: $2 -->"
      echo
      local n
      for n in 1 2 3 4 5 6 7 8; do
        echo "## R$n — request $n"
        case " ${3:-} " in *" $n "*) echo "ANSWER 2026-09-22:";; esac
        echo
      done
    } > "$f"
  }

  check() {
    local label=$1 expected=$2 got=$3
    if [ "$expected" = "$got" ]; then
      echo "  ok    $label"
      passed=$((passed + 1))
    else
      echo "  FAIL  $label"
      echo "        expected: $expected"
      echo "        got:      $got"
      failed=$((failed + 1))
      rc=1
    fi
  }

  echo "== codex-inbox selftest =="

  # 1. T-1330 itself: a high id folded out of order must not hide a lower answer.
  #    Baseline R4, R8 folded explicitly, and R6 has just been answered.
  fixture "$dir/a" 4 R8 "6 8"
  check "an answer below an out-of-order fold is still reported" \
    "R6" \
    "$(cmd_report "$dir/a" | sed -n 's/^NEW ANSWERS TO ACT ON: //p')"

  # 2. Non-vacuity: the already-folded one is genuinely suppressed, so test 1 is not
  #    passing because nothing is ever filtered.
  fixture "$dir/b" 4 R8 "8"
  check "an already-folded answer is not reported" \
    "no new answers" \
    "$(cmd_report "$dir/b" | grep -c 'NEW ANSWERS' | sed 's/^0$/no new answers/')"

  # 3. The old watermark would have produced R6 R8 here and then swallowed R5 forever;
  #    fold must name what it folds and leave the rest alone.
  fixture "$dir/c" 4 "" "6 8"
  cmd_fold "$dir/c" R8 >/dev/null
  check "fold records only the id it was given" \
    "R6" \
    "$(cmd_report "$dir/c" | sed -n 's/^NEW ANSWERS TO ACT ON: //p')"

  # 4. Compaction: folding the id that closes the gap advances the baseline and empties
  #    the named set, so the markers do not grow without bound.
  fixture "$dir/d" 4 R6 "5 6"
  cmd_fold "$dir/d" R5 >/dev/null
  check "closing the gap advances the baseline" "R6" "$(grep -oE 'FOLDED-THROUGH: R[0-9]+' "$dir/d" | grep -oE 'R[0-9]+')"
  check "closing the gap empties the named set" "" "$(grep -c 'FOLDED-ALSO' "$dir/d" | sed 's/^0$//')"

  # 5. Folding is orthogonal to answering: acting on one request must not change which
  #    requests are reported as still waiting on Codex. Compared before against after,
  #    because the unanswered list deliberately includes ids below the baseline — an id
  #    Codex never answered stays unanswered no matter what the coordinator folded.
  fixture "$dir/e" 4 "" "6"
  local before after
  before=$(cmd_report "$dir/e" | sed -n 's/^still unanswered: //p' | sed 's/ *$//')
  cmd_fold "$dir/e" R6 >/dev/null
  after=$(cmd_report "$dir/e" | sed -n 's/^still unanswered: //p' | sed 's/ *$//')
  check "folding does not change what is still unanswered" "$before" "$after"
  # ...and that list is not empty, or the check above compares nothing to nothing.
  check "the unanswered list is non-vacuous" "R1 R2 R3 R4 R5 R7 R8" "$after"

  # T-1334. The tally is the vocabulary `CadenceGuardScriptSelftestTests` reads, and it is the
  # half that cannot be faked by a selftest gutted to `return 0`: "0 passed" is a complaint there,
  # so a run that printed its headers and asserted nothing fails the test rather than pinning it.
  echo "checks: $passed passed, $failed failed"
  [ "$rc" -eq 0 ] && echo "selftest: all checks passed" || echo "selftest: FAILURES above"
  return "$rc"
}

case "${1:-report}" in
  report)   cmd_report "$DOC"; exit 0 ;;
  fold)     shift; cmd_fold "$DOC" "$@"; exit $? ;;
  selftest) cmd_selftest; exit $? ;;
  *)        echo "usage: $0 [report|fold R<n>...|selftest]" >&2; exit 2 ;;
esac
