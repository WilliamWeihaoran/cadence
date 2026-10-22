#!/bin/sh
# T-4480. Run `scripts/ledger-view.sh lint` in CI under whatever awk the runner has, and PROVE on
# the run itself that this awk reads the ledger the way the macOS awk it was written against does.
#
# The `ledger-lag` job this step lives in runs on Ubuntu, whose awk is mawk, while every reading of
# `ledger-view.sh` before this was made with macOS's one-true-awk. No mawk exists on the machine the
# script was written on, so parity could not be shown there. It is shown HERE instead, every run,
# and the step fails closed when it does not hold:
#
#   1. Name the awk in use, so a red run says which interpreter produced it.
#   2. Calibrate on fixtures: a ledger of only legal lead tokens (plus a headline and an illegal
#      token under `## Done`, which the lint must ignore) must exit 0 over the exact entry count; a
#      ledger with one `**CONFIRMED` lead must exit 6 and name that id and that token. An awk that
#      cannot tell the two apart makes the real-ledger reading below meaningless, so it is refused.
#   3. Lint the real ledger, and refuse unless the entry count the lint reports equals an
#      independent `grep -c` of entry lines across both ledgers. A parser that silently read fewer
#      entries -- a line-length limit, a regex dialect difference -- would otherwise lint a subset
#      and read green.
#
# Exit 6 is the illegal-lead refusal itself; any other non-zero is this step refusing its own
# instrument (LEDGER-LINT-AWK-*), which is a CI defect, not a ledger one.
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VIEW="$ROOT/scripts/ledger-view.sh"
TODO="${CADENCE_LEDGER_LINT_TODO:-$ROOT/docs/TODO.md}"
DONE="${CADENCE_LEDGER_LINT_DONE:-$ROOT/docs/TODO_DONE.md}"

refuse() { printf 'REFUSED (%s): %s\n' "$1" "$2" >&2; exit "$3"; }

# --- 1. the awk -----------------------------------------------------------------
awk_bin=$(command -v awk || echo '<none>')
echo "awk in use: $awk_bin"
[ -L "$awk_bin" ] && echo "  resolves to: $(readlink -f "$awk_bin" 2>/dev/null || readlink "$awk_bin")"
# mawk answers `-W version`, gawk and macOS awk answer `--version`. Informational only: no probe here
# may decide the result, the calibration below does.
v=$(awk -W version </dev/null 2>/dev/null | sed -n 1p)
[ -n "$v" ] || v=$(awk --version </dev/null 2>/dev/null | sed -n 1p)
echo "  version: ${v:-<unreported>}"

# --- 2. calibration -------------------------------------------------------------
ws=$(mktemp -d "${TMPDIR:-/tmp}/ledger-lint.XXXXXX") || refuse LEDGER-LINT-AWK-NO-TMP "mktemp failed" 3
trap 'rm -rf "$ws"' EXIT

cat > "$ws/legal.md" <<'FIXTURE'
# Fixture ledger

## Open

- [T-901] **CLOSED 2026-10-22 (agent `x`)** -- closed.
  continuation line with **CONFIRMED** mid-prose, which is not a lead token.
- [T-902] **PARTIAL 2026-10-22** -- half done.
- [T-903] **OPEN** -- not started.
- [T-904] **PARKED** -- waiting.
- [T-905] **The headline convention** is not a state and is not flagged.
- [T-906] plain first line with no bold run.

## Done

- [T-907] **CONFIRMED 2026-10-01** -- under Done the section decides, so the lint ignores this.
FIXTURE
# The illegal fixture is the legal one with ONE lead token changed, so the only difference the
# lint can be reacting to is that token.
sed 's/^- \[T-903\] \*\*OPEN\*\*/- [T-903] **CONFIRMED**/' "$ws/legal.md" > "$ws/illegal.md"
cmp -s "$ws/legal.md" "$ws/illegal.md" && refuse LEDGER-LINT-AWK-FIXTURE "the illegal fixture came out identical to the legal one" 3

lint() {  # $1 = todo, $2 = done
    CADENCE_LEDGER_VIEW_TODO="$1" CADENCE_LEDGER_VIEW_DONE="$2" CADENCE_LEDGER_VIEW_MIN_ENTRIES=1 \
        sh "$VIEW" lint > "$ws/out" 2>&1
}

lint "$ws/legal.md" /dev/null; rc=$?
if [ "$rc" -ne 0 ] || ! grep -q '0 illegal lead tokens over 7 entries' "$ws/out"; then
    cat "$ws/out" >&2
    refuse LEDGER-LINT-AWK-CALIBRATION "this awk read the all-legal fixture as exit $rc, not exit 0 over 7 entries" 3
fi
echo "calibration: legal fixture -> exit 0, 0 illegal over 7 entries"

lint "$ws/illegal.md" /dev/null; rc=$?
if [ "$rc" -ne 6 ] || ! grep -q '^T-903 .*lead token CONFIRMED' "$ws/out" || grep -q '^T-907 ' "$ws/out"; then
    cat "$ws/out" >&2
    refuse LEDGER-LINT-AWK-CALIBRATION "this awk read the one-illegal-token fixture as exit $rc; wanted exit 6 naming T-903 CONFIRMED and not T-907" 3
fi
echo "calibration: illegal fixture -> exit 6, names T-903 CONFIRMED, ignores the Done section"

# --- 3. the real ledger ---------------------------------------------------------
[ -r "$TODO" ] || refuse LEDGER-LINT-AWK-NO-LEDGER "$TODO is not readable" 3
[ -r "$DONE" ] || DONE=/dev/null
CADENCE_LEDGER_VIEW_TODO="$TODO" CADENCE_LEDGER_VIEW_DONE="$DONE" sh "$VIEW" lint > "$ws/out" 2>&1; rc=$?
cat "$ws/out"
[ "$rc" -eq 6 ] && exit 6
[ "$rc" -eq 0 ] || refuse LEDGER-LINT-AWK-FAILED "ledger-view.sh lint exited $rc over the real ledger" 3

read_n=$(sed -n 's/^ledger-view lint: 0 illegal lead tokens over \([0-9][0-9]*\) entries\.$/\1/p' "$ws/out")
want_n=$(cat "$TODO" "$DONE" | grep -c '^- \[T-[0-9][0-9]*\]')
[ -n "$read_n" ] || refuse LEDGER-LINT-AWK-PARSE-MISMATCH "the lint exited 0 without reporting its entry count" 3
if [ "$read_n" -ne "$want_n" ]; then
    refuse LEDGER-LINT-AWK-PARSE-MISMATCH "this awk read $read_n entries; grep counts $want_n entry lines in $TODO and $DONE. The lint read a different ledger from the one on disk." 3
fi
echo "parity: the lint read $read_n entries and grep counts $want_n; this awk parsed the whole ledger."
exit 0
