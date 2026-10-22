#!/bin/zsh
# Wait for a `scripts/mutate.sh` run to finish, by its exit sentinel -- never by `pgrep -f` (T-3182).
#
#   ./scripts/wait-mutate.sh <id> [timeout-seconds] [runner-pid]
#   ./scripts/wait-mutate.sh selftest
#
# WHY THIS EXISTS
#
# Agents armed `until <log grep> && ! pgrep -f "mutate.sh <id>"; do sleep 10; done` to learn a
# mutation batch had finished. `pgrep -f` matches the WATCHER'S OWN command line, which contains
# that literal string, so the negation is permanently false: seven such loops were found alive, the
# oldest three days old, each hand-written by a different agent. A fix to one one-liner is undone by
# the next agent who writes a fresh one, so the answer is a file the runner writes and a helper that
# reads it, not a better pattern.
#
# HOW IT DECIDES
#
#   `mutate.sh` writes <scratch>/exit.status on every way out it can catch (return, exception,
#   SIGINT/SIGTERM/SIGHUP), where <scratch> is its own per-ident `/private/tmp/cadence-mut-<id>`,
#   and its wrapper deletes the previous run's file before the interpreter starts. This helper:
#     - prints the recorded status and exits WITH it (0 green, 1 a verdict to read, 2 a refusal,
#       128+N a signal) the moment the file exists -- and, given a runner pid, only when the file
#       names THAT pid, so a stale sentinel cannot answer a new wait even across the launch race;
#     - exits 125 (WAIT-MUTATE-NO-SENTINEL) when the given runner pid is gone and left no
#       sentinel: SIGKILL, which no trap survives -- read the log and <scratch>/runner.pid;
#     - exits 124 (WAIT-MUTATE-TIMEOUT) at the timeout, default 7200 s. Never unbounded.
#
# USE
#
#   nohup ./scripts/mutate.sh <id> <plan> > <log> 2>&1 &
#   ./scripts/wait-mutate.sh <id> 7200 $!       # same shell: $! is the runner (mutate.sh execs)
#   ./scripts/wait-mutate.sh <id>               # later call: the pid is in <scratch>/runner.pid
#
# Run it with the Bash `timeout` raised or backgrounded; it blocks until one of the three answers.
set -uo pipefail
SCRIPT_PATH="${0:A}"
ROOT_DIR="${0:A:h:h}"
DEFAULT_TIMEOUT=7200

wm_scratch_for() {
  print -r -- "${CADENCE_MUTATE_SCRATCH_ROOT:-/private/tmp}/cadence-mut-$1"
}

# Reads the sentinel into the caller's `s_status`, `s_pid`, `s_finished`. Returns 1 when the file is
# absent or incomplete (it is written by rename, so incomplete means "not this helper's to trust").
wm_read_sentinel() {
  local file="$1"
  local key value
  s_status="" s_pid="" s_finished=""
  [[ -f "$file" ]] || return 1
  while IFS='=' read -r key value; do
    case "$key" in
      status) s_status="$value" ;;
      pid) s_pid="$value" ;;
      finished) s_finished="$value" ;;
    esac
  done < "$file"
  [[ "$s_status" == <-> && "$s_pid" == <-> ]] || return 1
  return 0
}

# One poll: 0 = answered (status in s_status), 1 = keep waiting.
wm_answered() {
  local sentinel="$1" want_pid="$2"
  wm_read_sentinel "$sentinel" || return 1
  [[ -z "$want_pid" || "$s_pid" == "$want_pid" ]] || return 1
  return 0
}

wm_wait() {
  local ident="$1" timeout="$2" want_pid="$3"
  local sentinel="$(wm_scratch_for "$ident")/exit.status"
  local poll="${CADENCE_WAIT_MUTATE_POLL:-10}"
  local -i deadline=$(( SECONDS + timeout ))
  local s_status s_pid s_finished
  print -r -- "wait-mutate: $ident -- sentinel $sentinel, timeout ${timeout}s${want_pid:+, runner pid $want_pid}"
  while true; do
    if wm_answered "$sentinel" "$want_pid"; then
      print -r -- "wait-mutate: mutate.sh $ident finished: exit status $s_status (pid $s_pid, at epoch $s_finished)"
      return "$s_status"
    fi
    if [[ -n "$want_pid" ]] && ! kill -0 "$want_pid" 2>/dev/null; then
      # The sentinel is written before the process ends, so one more look closes that gap.
      if wm_answered "$sentinel" "$want_pid"; then
        print -r -- "wait-mutate: mutate.sh $ident finished: exit status $s_status (pid $s_pid, at epoch $s_finished)"
        return "$s_status"
      fi
      print -r -- "WAIT-MUTATE-NO-SENTINEL: runner pid $want_pid is gone and recorded no exit status"
      print -r -- "  (SIGKILL skips every trap). Read its log, and check $(wm_scratch_for "$ident")/runner.pid:"
      print -r -- "  a mutation may still be in its tree."
      return 125
    fi
    if (( SECONDS >= deadline )); then
      print -r -- "WAIT-MUTATE-TIMEOUT: no exit status for mutate.sh $ident after ${timeout}s."
      print -r -- "  The run may still be going: read its log; never conclude it finished from this."
      return 124
    fi
    /bin/sleep "$poll"
  done
}

wm_main() {
  if (( $# < 1 )) || [[ "$1" == -h || "$1" == --help ]]; then
    print -r -- "usage: ./scripts/wait-mutate.sh <id> [timeout-seconds (default $DEFAULT_TIMEOUT)] [runner-pid]"
    print -r -- "       ./scripts/wait-mutate.sh selftest"
    return 64
  fi
  if [[ "$1" == selftest ]]; then
    wm_selftest
    return $?
  fi
  local ident="$1" timeout="${2:-$DEFAULT_TIMEOUT}" want_pid="${3:-}"
  if [[ "$timeout" != <-> ]] || (( timeout < 1 )); then
    print -r -- "wait-mutate: timeout must be a positive number of seconds, got '$timeout'"
    return 64
  fi
  if [[ -n "$want_pid" && "$want_pid" != <-> ]]; then
    print -r -- "wait-mutate: runner pid must be a number, got '$want_pid'"
    return 64
  fi
  wm_wait "$ident" "$timeout" "$want_pid"
}

# --- selftest -----------------------------------------------------------------
#
# Drives REAL `scripts/mutate.sh` runs (against a throwaway --tree, under a throwaway
# CADENCE_MUTATE_SCRATCH_ROOT, no lock, no xcodebuild: the tree's own scripts/xcb.sh is a stub) and
# asserts each way out leaves an exit status this helper reads back.

wm_selftest() {
  local -a failures
  local -i performed=0
  local ws mutate stubpid out code helper runner scratch
  check() {
    performed+=1
    if [[ "$2" == 1 ]]; then
      print -r -- "  ok   $1"
    else
      print -r -- "  FAIL $1  <- $3"
      failures+=("$1")
    fi
  }
  print -r -- "== wait-mutate.sh selftest =="
  ws="$(mktemp -d "${TMPDIR:-/tmp/}cadence-wait-mutate-selftest.XXXXXX")" || return 2
  mutate="$ROOT_DIR/scripts/mutate.sh"
  export CADENCE_MUTATE_SCRATCH_ROOT="$ws/scratch"
  export CADENCE_WAIT_MUTATE_POLL=0.2
  mkdir -p "$ws/tree/scripts" "$ws/scratch"
  print -r -- "hello" > "$ws/tree/dummy.txt"
  # The stub is green (one passing test in WmSuite) unless WM_STUB_BLOCK is set, when it blocks
  # the way a long build does. A blocking stub records its pid so the selftest can end it: a
  # SIGTERM'd runner does not take its xcb.sh child with it, and a selftest leaves nothing behind.
  print -r -- '#!/bin/zsh
if [[ -n "${WM_STUB_BLOCK:-}" ]]; then
  print $$ >> "${0:A:h}/stub.pids"
  exec /bin/sleep 60
fi
print -r -- "Suite WmSuite started."
print -r -- "✔ Test wmCase() passed after 0.001 seconds."
exit 0' > "$ws/tree/scripts/xcb.sh"
  chmod 755 "$ws/tree/scripts/xcb.sh"
  # T-3191. The tree's own test-suite-index.sh is the first thing `mutate.sh` runs from the tree,
  # and it runs BEFORE `Runner.on_signal` is installed -- the window where only `with_exit_sentinel`'s
  # provisional handler stands between SIGTERM and a silent death. With WM_STUB_EARLY set it blocks
  # there; otherwise it fails, which `load_test_labels` reads as "no labels", as if it were absent.
  print -r -- '#!/bin/zsh
if [[ -n "${WM_STUB_EARLY:-}" ]]; then
  print $$ >> "${0:A:h}/early.pids"
  exec /bin/sleep 60
fi
exit 1' > "$ws/tree/scripts/test-suite-index.sh"
  chmod 755 "$ws/tree/scripts/test-suite-index.sh"
  print -r -- $'mutation: m1\nfile: dummy.txt\nsuite: WmSuite\nexpect: survived\n--- old\nhello\n--- new\ngoodbye\n--- end' > "$ws/ok.plan"
  print -r -- $'mutation: m1\nfile: no-such-file.txt\n--- old\nhello\n--- new\ngoodbye\n--- end' > "$ws/bad.plan"
  scratch="$ws/scratch/cadence-mut-wmself"

  # 1. Success: a full run over the green stub -- baseline green, m1 SURVIVED as planned, exit 0.
  /bin/zsh "$mutate" wmself "$ws/ok.plan" --tree "$ws/tree" --no-lock > "$ws/ok.log" 2>&1
  code=$?
  out="$("$SCRIPT_PATH" wmself 5 2>&1)"
  helper=$?
  check "a run that ends normally (exit $code) writes its exit status, and the helper exits with it" \
    $(( code == 0 && helper == 0 )) "mutate exit $code (want 0; its log ends: $(tail -3 "$ws/ok.log")), helper exit $helper: $out"
  [[ "$out" == *"exit status $code "* ]]; check "...and the helper reports exactly that status" $(( $? == 0 )) "$out"

  # 2. Failure: a plan naming a file the tree does not have is refused with exit 2.
  /bin/zsh "$mutate" wmself "$ws/bad.plan" --tree "$ws/tree" --no-lock --no-build > "$ws/bad.log" 2>&1
  code=$?
  "$SCRIPT_PATH" wmself 5 > "$ws/wait-bad.log" 2>&1
  helper=$?
  check "a run that FAILS (exit $code) writes its exit status, and the helper exits with it" \
    $(( code == 2 && helper == 2 )) "mutate exit $code, helper exit $helper: $(<"$ws/wait-bad.log")"

  # 3. Stale: the sentinel from run 2 (status 2) must not answer a wait on a NEW run under the same id.
  WM_STUB_BLOCK=1 /bin/zsh "$mutate" wmself "$ws/ok.plan" --tree "$ws/tree" --no-lock > "$ws/term.log" 2>&1 &
  runner=$!
  local -i i=0
  while (( i < 100 )) && [[ ! -s "$ws/tree/scripts/stub.pids" ]]; do /bin/sleep 0.1; i+=1; done
  "$SCRIPT_PATH" wmself 2 > "$ws/wait-stale.log" 2>&1
  code=$?
  check "a stale sentinel from the previous run does not answer a wait on the new one" \
    $(( code == 124 )) "helper exit $code: $(<"$ws/wait-stale.log")"
  # And the pid token, independently of the wrapper's delete: a sentinel naming another pid is ignored.
  print -r -- $'status=0\npid=1\nfinished=0' > "$scratch/exit.status"
  "$SCRIPT_PATH" wmself 2 "$runner" > "$ws/wait-token.log" 2>&1
  code=$?
  check "given the runner pid, a sentinel naming a different pid is not an answer" \
    $(( code == 124 )) "helper exit $code: $(<"$ws/wait-token.log")"
  rm -f "$scratch/exit.status"

  # 4. SIGTERM mid-run (blocked in the stub build): the trap still records 128+15.
  kill -TERM "$runner" 2>/dev/null
  "$SCRIPT_PATH" wmself 15 "$runner" > "$ws/wait-term.log" 2>&1
  code=$?
  wait "$runner" 2>/dev/null
  check "a run ended by SIGTERM writes exit status 143, and the helper exits with it" \
    $(( code == 143 )) "helper exit $code: $(<"$ws/wait-term.log")"

  # 4b. SIGTERM in the EARLY window (T-3191): before `Runner.on_signal` exists, so only the
  # provisional handler in `with_exit_sentinel` can turn it into a recorded 143. Case 4 cannot see
  # that handler -- by its SIGTERM `on_signal` has replaced it.
  WM_STUB_EARLY=1 /bin/zsh "$mutate" wmself "$ws/ok.plan" --tree "$ws/tree" --no-lock > "$ws/early.log" 2>&1 &
  runner=$!
  i=0
  while (( i < 100 )) && [[ ! -s "$ws/tree/scripts/early.pids" ]]; do /bin/sleep 0.1; i+=1; done
  kill -TERM "$runner" 2>/dev/null
  "$SCRIPT_PATH" wmself 15 "$runner" > "$ws/wait-early.log" 2>&1
  code=$?
  wait "$runner" 2>/dev/null
  check "a SIGTERM before on_signal is installed (blocked in the tree's test-suite-index.sh) still writes 143" \
    $(( code == 143 )) "helper exit $code: $(<"$ws/wait-early.log")"
  [[ -s "$ws/tree/scripts/early.pids" && "$(<"$ws/early.log")" != *"test labels:"* ]]
  check "...and it landed in that window: the runner never got past loading the test labels" \
    $(( $? == 0 )) "early.pids: $(<"$ws/tree/scripts/early.pids" 2>/dev/null); log: $(tail -3 "$ws/early.log")"

  # 5. SIGKILL cannot be trapped: with the pid, the helper says so instead of waiting out its timeout.
  WM_STUB_BLOCK=1 /bin/zsh "$mutate" wmself "$ws/ok.plan" --tree "$ws/tree" --no-lock > "$ws/kill.log" 2>&1 &
  runner=$!
  i=0
  while (( i < 100 )) && [[ ! -s "$scratch/runner.pid" || "$(<"$scratch/runner.pid")" != "$runner" ]]; do
    /bin/sleep 0.1; i+=1
  done
  kill -KILL "$runner" 2>/dev/null
  wait "$runner" 2>/dev/null
  local -i before=$SECONDS
  "$SCRIPT_PATH" wmself 30 "$runner" > "$ws/wait-kill.log" 2>&1
  code=$?
  check "a SIGKILLed runner is reported as WAIT-MUTATE-NO-SENTINEL (125), not waited out" \
    $(( code == 125 && SECONDS - before < 10 )) "helper exit $code after $(( SECONDS - before ))s: $(<"$ws/wait-kill.log")"

  # 6. Timeout: nothing ever runs under this id.
  before=$SECONDS
  "$SCRIPT_PATH" wmnever 1 > "$ws/wait-never.log" 2>&1
  code=$?
  [[ "$(<"$ws/wait-never.log")" == *WAIT-MUTATE-TIMEOUT* ]]
  helper=$?
  check "with no run, the helper times out nonzero (124) and says WAIT-MUTATE-TIMEOUT" \
    $(( code == 124 && helper == 0 && SECONDS - before < 5 )) "helper exit $code: $(<"$ws/wait-never.log")"

  # 7. Arguments.
  "$SCRIPT_PATH" wmself abc > /dev/null 2>&1
  check "a non-numeric timeout is refused (64)" $(( $? == 64 )) "accepted"

  # Leave nothing behind: the stubs a signalled runner orphaned, then the workspace.
  local pidfile
  for pidfile in "$ws/tree/scripts/stub.pids" "$ws/tree/scripts/early.pids"; do
    [[ -f "$pidfile" ]] || continue
    for stubpid in ${(f)"$(<"$pidfile")"}; do
      kill -TERM "$stubpid" 2>/dev/null
    done
  done
  rm -rf "$ws"

  print -r -- ""
  print -r -- "checks: $(( performed - ${#failures} )) passed, ${#failures} failed"
  if (( ${#failures} )); then
    print -r -- "SELFTEST FAILED: ${(j:, :)failures}"
    return 1
  fi
  print -r -- "SELFTEST PASSED"
  return 0
}

wm_main "$@"
