#!/bin/zsh
# T-1176. DID A LAUNCH WRITE THE APP-GROUP SUITE? READ IT THE ONE WAY THAT CAN ANSWER.
#
#   ./scripts/group-defaults-probe.sh sample [<record-file>]   # exit 0 read, 3 absent, 2 refused
#   ./scripts/group-defaults-probe.sh compare <before> <after> # exit 0 UNMOVED, 1 MOVED, 3 NO-SAMPLE
#   ./scripts/group-defaults-probe.sh selftest
#
# WHY THIS EXISTS, AND WHY IT IS AN INSTRUMENT RATHER THAN A FIX
#
# T-1176 asks one question: when an agent launches the macOS app through `run-macos-app.sh`, does
# that launch write `group.com.haoranwei.Cadence` -- the ONE suite `run-macos-app.sh`'s header names
# as still shared with the owner, because `Theme` and `CadenceWidgetRefreshCenter` reach it across
# the widget process boundary and `-CadenceSuiteName` does not route it. Three keys are at stake:
# `cadence.appearance.accentPaletteID`, `cadence.widgets.lastReloadAt`, and the two dictionaries
# `cadence.widgets.today.recentlyCompletedTasks` / `cadence.widgets.habits.recentlyChangedHabits`.
#
# The question has stayed unanswered through two agents, and NOT because the answer is hard to read
# -- because every reading of it so far has been taken by hand, into prose, and a figure in prose
# cannot be compared to the next one by anything but a person. This script is that comparison. It
# makes the measurement window SHORT, which matters here more than usual: the window costs the owner
# their own running app (see the blocker below), so the instrument has to exist before the window,
# not during it.
#
# WHAT IT REFUSES TO DO, AND THE REFUSAL IS THE POINT
#
# **It never writes the suite it reads, and it will not write a record beside it either.** The data
# under `~/Library/Group Containers/` and every `Cadence Store Backups` directory is the OWNER'S,
# and a probe that writes into the thing it measures is not a probe. `sample` reads and hashes; a
# record path that looks like it lands in the group container, a backups folder or the Recovery
# store is refused outright (`REFUSING-TO-WRITE`).
#
# **It does not attribute the change to a writer.** `MOVED` says this file differs between two
# readings and nothing more. cfprefsd, the owner's own `Cadence.app` and an agent's launched build
# all write this suite, and the file records none of them, so every verdict carries
# `NOT AN ATTRIBUTION` and each sample records whether the owner's app was up when it was taken.
# A reading taken while their copy is running cannot answer T-1176 at all, and says so rather than
# quietly counting as the measurement.
#
# TWO MEASURED FACTS THE READING DEPENDS ON
#
# **1. Compare HASHES, not mtimes.** `cadence.widgets.lastReloadAt` carries 2026-10-06 00:16, and on
# 2026-10-06 agent `backupcheck` watched the file's mtime move while its 135 bytes did not. Measured
# again on 2026-10-09, three days later: mtime 12:19:29 that morning, sha256 still
# `81c4a4ac3d903aeb6c35487b206c7577ec96cbd37b5bb8262ecef187f555dbab`, same 135 bytes, same two keys.
# cfprefsd rewrites this file without changing its content, so mtime answers a different question
# than the one asked and answers it wrongly. This script does not read mtimes, and §2 of the
# selftest holds that by comparing two byte-identical fixtures written an hour apart.
#
# **2. `PlistBuddy` cannot read this file's timestamp.** `PlistBuddy -c Print` renders
# `cadence.widgets.lastReloadAt` as `1791260160.000000`; `plutil -p` renders the same bytes as
# `1791260184.86859`. The difference is 24.87 seconds and it is not rounding: 1791260160 is exactly
# the nearest float32. PlistBuddy prints the stored double through a single-precision float, so the
# baseline figure in T-1176's own entry is 25 seconds early and a *small* real write to that key
# would be invisible to it. Every value here comes from `plutil -p`, and §4 pins it with a fixture
# whose value a float32 read cannot reproduce.
#
# THE BLOCKER, WHICH THIS DOES NOT REMOVE AND CANNOT
#
# `run-macos-app.sh start` refuses, exit 3, while the owner's own Cadence is running -- correctly,
# since a second writer on one app-group container is T-236. It was running on 2026-10-06 (pid
# 78892) and is running today (pid 59514). Quitting it is the owner's decision and not an agent's to
# arrange, so the measurement still needs a granted window. What this changes is the cost of the
# window: `sample` before, launch, `stop`, `sample` after, `compare` -- four commands and a verdict,
# instead of a hand-read inventory that the next agent has to re-derive from prose.
#
# WHY IT IS A SCRIPT AND NOT A TEST
#
# **The thing to be measured is the owner's real app-group plist, and no test in this target may go
# near it** -- every fixture a test touches must be built from its own temporary directory. A test
# that read `~/Library/Group Containers/` would be the exact mistake this ticket is about. So the
# reading lives in a script that a person runs with their eyes open, and what the test target holds
# is this script's SELFTEST, run against throwaway fixtures under `$TMPDIR` by
# `CadenceGuardScriptSelftestTests.theGroupDefaultsProbesOwnChecksStillFire`.

set -u
setopt NULL_GLOB

say() { print -r -- "$@" }

TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"

# zsh writes here-document temp files to $TMPPREFIX, which zsh itself sets to `/tmp/zsh` at startup
# -- never $TMPDIR. `/tmp` is unwritable from the App-Sandboxed test host that runs this selftest
# (T-719), so every heredoc below would fail there with nothing useful on stderr. Same line, same
# reason, as `heartbeat-progress.sh`, `agent-scratch.sh` and `mutate.sh`;
# `CadenceTestHostSandboxCapabilityTests` is where that host property is measured and
# `CadenceGuardScriptSelftestTests` is what runs this script inside it.
export TMPPREFIX="${CADENCE_TMPPREFIX:-${TMP_BASE}zsh}"

SELF_PATH="${0:A}"
ROOT_DIR="${SELF_PATH:h:h}"

# The app-group suite, spelled here exactly as `CadenceStoreSupport.appGroupIdentifier` spells it.
# §7 of the selftest compares the two as text: a drift of one character reads a file that is never
# there, and this tool would report `absent` forever while the launch wrote the suite as usual.
GDP_GROUP_ID="group.com.haoranwei.Cadence"
GDP_DEFAULT_PLIST="$HOME/Library/Group Containers/$GDP_GROUP_ID/Library/Preferences/$GDP_GROUP_ID.plist"

# The four keys, in the order a reader wants them: the one that is there, the one T-1176 expects to
# move, and the two that are ABSENT and would have to be CREATED. §7 compares each against the Swift
# file that declares it.
GDP_KEYS=(
  "cadence.appearance.accentPaletteID"
  "cadence.widgets.lastReloadAt"
  "cadence.widgets.today.recentlyCompletedTasks"
  "cadence.widgets.habits.recentlyChangedHabits"
)

# `pgrep -f` is anchored on the installed binary, the same pattern `run-macos-app.sh` refuses on, so
# the two agree about what "the owner's own Cadence" means. The command is a seam only so the
# selftest can substitute a process table; nothing else may set it.
GDP_OWNER_PATTERN="/Applications/Cadence.app/Contents/MacOS/Cadence"
GDP_PGREP_CMD=(${=CADENCE_GROUP_PROBE_PGREP_CMD:-pgrep})

gdp_plist() { print -r -- "${CADENCE_GROUP_PLIST:-$GDP_DEFAULT_PLIST}" }

# Three answers, not two. `/usr/bin/pgrep` is not setuid, so it spawns inside the App Sandbox and
# runs -- but it is denied the process list, prints *"pgrep: Cannot get process list"* and exits 3,
# which a plain `if pgrep` reads as "nothing is running". That is the one reading this script must
# not make: "the owner's app was not up" is the sentence that would make a sample count as the
# measurement. `unknown` is a third state and is carried into the verdict. The host property is
# measured by `CadenceTestHostSandboxCapabilityTests`; §8 of the selftest, run by
# `CadenceGuardScriptSelftestTests`, holds the three-way reading against a blind pgrep.
gdp_owner_app() {
  local out rc
  out="$("${GDP_PGREP_CMD[@]}" -f "$GDP_OWNER_PATTERN" 2>/dev/null)"; rc=$?
  if (( rc >= 2 )); then print -r -- "unknown"; return 0; fi
  if (( rc == 0 )) && print -r -- "$out" | grep -q '^[0-9]'; then print -r -- "running"; return 0; fi
  if (( rc == 0 )); then print -r -- "unknown"; return 0; fi
  print -r -- "absent"
}

# One key's value, by exact prefix match against `plutil -p`'s rendering. A dictionary or array
# opens with `{` or `[` and continues over lines this does not read: for those two keys the question
# T-1176 asks is whether a launch CREATES them, and the file sha256 already answers "did anything at
# all change", so presence is the whole reading and is labelled as such rather than faked into a
# scalar.
gdp_value() {  # $1 = plist, $2 = key -> the value, or nothing when the key is absent
  local rendered
  rendered="$(plutil -p "$1" 2>/dev/null | awk -v needle="\"$2\" => " '
    { line = $0; sub(/^[ \t]+/, "", line); if (index(line, needle) == 1) { print substr(line, length(needle) + 1); exit } }')"
  [[ -n "$rendered" ]] || return 1
  case "$rendered" in
    '{'|'['|'{}'|'[]') print -r -- "PRESENT-CONTAINER" ;;
    *) print -r -- "$rendered" ;;
  esac
}

# A record may not be written into the data it reads. `sample > <somewhere in the group container>`
# is an easy slip -- the path is already in your shell history from the read -- and the backups and
# the Recovery store are the same mistake with worse consequences.
#
# **The container's `Data/tmp` is deliberately NOT on this list, and it was on it for one run.**
# `com.haoranwei.Cadence/Data` as a whole looks like the right thing to refuse until you run this
# inside the App-Sandboxed test host, where `$TMPDIR` IS
# `~/Library/Containers/com.haoranwei.Cadence/Data/tmp/` -- so the blanket form refused the
# selftest's own throwaway workspace and failed 9 of its own checks while claiming to protect
# something. What is worth protecting in that container is `Data/Library` (the preferences and the
# store), `Data/Documents`, and the private store roots under `CadenceUITestStores`; `Data/tmp`
# below those is scratch and `run-macos-app.sh stop` deletes it whole. Measured 2026-10-09;
# `CadenceGroupDefaultsProbeSelftestTests` is what runs this script in that host, and section 6
# holds the discrimination in both directions rather than just the refusal.
gdp_refuse_write_target() {  # $1 = record path
  local target="$1"
  case "$target" in
    *"Group Containers"*|*"Cadence Store Backups"*|*"/Recovery/"*|*CadenceUITestStores*|*"com.haoranwei.Cadence/Data/Library"*|*"com.haoranwei.Cadence/Data/Documents"*)
      say "REFUSING-TO-WRITE: '$target' is inside the owner's data, and a probe does not write what it measures."
      say "   Group containers, backup folders, the Recovery store, the container's Library and"
      say "   Documents, and any private store root are read-only to this script."
      return 1
      ;;
  esac
  return 0
}

group_defaults_sample() {  # $1 = record path or empty
  local record="$1" plist owner lines value key
  plist="$(gdp_plist)"
  if [[ -n "$record" ]]; then gdp_refuse_write_target "$record" || return 2; fi

  owner="$(gdp_owner_app)"
  lines=("# cadence group-defaults sample (T-1176)" "path=$plist" "owner-app=$owner")

  if [[ ! -r "$plist" ]]; then
    lines+=("state=absent")
    lines+=("group-defaults: NO-SAMPLE -- $plist is not readable, so there is nothing to compare.")
    print -rl -- $lines
    [[ -n "$record" ]] && print -rl -- $lines > "$record"
    return 3
  fi

  lines+=("bytes=$(stat -f %z "$plist")")
  lines+=("sha256=$(shasum -a 256 "$plist" | cut -d' ' -f1)")
  for key in $GDP_KEYS; do
    if value="$(gdp_value "$plist" "$key")"; then lines+=("key $key = $value")
    else lines+=("key $key = ABSENT"); fi
  done
  print -rl -- $lines
  [[ -n "$record" ]] && print -rl -- $lines > "$record"
  return 0
}

gdp_field() {  # $1 = record, $2 = field name
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}

gdp_key_value() {  # $1 = record, $2 = key
  local line
  line="$(grep -F -- "key $2 = " "$1" 2>/dev/null | head -1)"
  [[ -n "$line" ]] || return 1
  print -r -- "${line#key $2 = }"
}

group_defaults_compare() {  # $1 = before record, $2 = after record
  local before="$1" after="$2" f key b a moved=0
  for f in "$before" "$after"; do
    if [[ ! -r "$f" ]]; then
      say "  group-defaults: NO-SAMPLE -- '$f' is not readable; nothing was compared."
      return 3
    fi
    if [[ -z "$(gdp_field "$f" sha256)" ]]; then
      say "  group-defaults: NO-SAMPLE -- '$f' carries no sha256, so it is not a sample of a file that existed."
      return 3
    fi
  done

  say "== group-defaults compare =="
  say "  before: sha256=$(gdp_field "$before" sha256) bytes=$(gdp_field "$before" bytes) owner-app=$(gdp_field "$before" owner-app)"
  say "  after:  sha256=$(gdp_field "$after" sha256) bytes=$(gdp_field "$after" bytes) owner-app=$(gdp_field "$after" owner-app)"
  say "  (mtimes are not read. cfprefsd rewrites this file without changing a byte -- measured"
  say "   2026-10-06 and again 2026-10-09, three days apart, both times sha256 81c4a4ac...)"

  for key in $GDP_KEYS; do
    b="$(gdp_key_value "$before" "$key")" || b="(not sampled)"
    a="$(gdp_key_value "$after" "$key")" || a="(not sampled)"
    if [[ "$b" == "ABSENT" && "$a" != "ABSENT" ]]; then say "  key $key: CREATED (absent -> $a)"
    elif [[ "$b" != "ABSENT" && "$a" == "ABSENT" ]]; then say "  key $key: REMOVED ($b -> absent)"
    elif [[ "$b" != "$a" ]]; then say "  key $key: CHANGED ($b -> $a)"
    else say "  key $key: HELD ($a)"; fi
  done

  [[ "$(gdp_field "$before" sha256)" != "$(gdp_field "$after" sha256)" ]] && moved=1

  if (( moved )); then
    say "  group-defaults: MOVED -- the file differs between the two readings."
  else
    say "  group-defaults: UNMOVED -- byte-identical between the two readings."
  fi
  say "              NOT AN ATTRIBUTION. This compares two readings of one file and names no"
  say "              writer: cfprefsd, the owner's own Cadence and an agent's launched build all"
  say "              write this suite, and the file carries no record of which of them did."
  for f in "$before" "$after"; do
    case "$(gdp_field "$f" owner-app)" in
      running) say "              ATTRIBUTION WITHHELD: the owner's own Cadence was RUNNING at ${f:t}. T-1176 asks what an AGENT LAUNCH writes, and this reading cannot say." ;;
      unknown) say "              ATTRIBUTION WITHHELD: whether the owner's Cadence was running could not be read at ${f:t} (the process list was denied), which is not the same as 'it was not'." ;;
    esac
  done
  (( moved )) && return 1
  return 0
}

# --- selftest ----------------------------------------------------------------------------------
#
# Every check runs against throwaway plists under $TMPDIR. Nothing here reads, writes or names the
# owner's real group container, which is the property the whole script exists to keep.
#
# The checks worth knowing about are §2 and §4, and both are controls rather than assertions: §2
# compares two byte-identical fixtures an hour apart and then the same pair with one byte changed,
# so a verdict taken off mtimes passes neither direction; §4 feeds a value no float32 can carry, so
# swapping `plutil` back to `PlistBuddy` reddens here instead of in six months' prose.

selftest() {
  local ws passed=0 failed=0
  ws="$(mktemp -d "${TMP_BASE}cadence-gdp-selftest.XXXXXX")" || { say "selftest: cannot make a workspace"; return 1 }
  trap "chmod -R u+w '$ws' 2>/dev/null; rm -rf '$ws'" EXIT INT TERM

  check() {  # $1 = name, $2 = 1|0, $3 = evidence
    if [[ "$2" == 1 ]]; then print -r -- "  PASS $1"; (( passed++ ))
    else print -r -- "  FAIL $1"; print -r -- "       $3"; (( failed++ )); fi
  }

  local here="$SELF_PATH"
  mkdir -p "$ws/fixtures" "$ws/records" "$ws/readonly"

  # $1 = plist (or NONE), $@[2,-1] = arguments. `out`/`rc` are read by the check that follows.
  probe() {
    local plist=$1; shift
    if [[ "$plist" == NONE ]]; then
      out="$(CADENCE_GROUP_PROBE_PGREP_CMD="${FAKE_PGREP:-pgrep}" zsh -f "$here" "$@" 2>&1)"; rc=$?
    else
      out="$(CADENCE_GROUP_PLIST="$plist" CADENCE_GROUP_PROBE_PGREP_CMD="${FAKE_PGREP:-pgrep}" zsh -f "$here" "$@" 2>&1)"; rc=$?
    fi
    print -r -- "     seen: $(print -r -- "$out" | grep -o 'group-defaults: [A-Z-]*' | head -1)$(print -r -- "$out" | grep -o 'REFUSING-TO-WRITE' | head -1) (exit $rc)"
  }

  # A plist with the two keys the real file has, written as XML so the fixture is readable text.
  # $1 = destination, $2 = the lastReloadAt value, $3 = extra body lines (may be empty).
  write_plist() {
    cat > "$1" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>cadence.appearance.accentPaletteID</key>
	<string>cadence</string>
	<key>cadence.widgets.lastReloadAt</key>
	<real>$2</real>
$3
</dict>
</plist>
PLIST_EOF
  }

  local FAKE_PGREP=""
  # Stand-ins for `pgrep -f`: one that finds the owner's app, one that finds nothing, and one that
  # runs but is DENIED the process list -- the App-Sandboxed reading, which exits 3 and must not be
  # read as "not running". Same three shapes, same reason, as `test-host-lock.sh`'s fixtures.
  print -r -- '#!/bin/zsh
print -r -- 59514
exit 0' > "$ws/pgrep-running"; chmod +x "$ws/pgrep-running"
  print -r -- '#!/bin/zsh
exit 1' > "$ws/pgrep-absent"; chmod +x "$ws/pgrep-absent"
  print -r -- '#!/bin/zsh
print -u2 -- "pgrep: Cannot get process list"
exit 3' > "$ws/pgrep-blind"; chmod +x "$ws/pgrep-blind"

  say "== group-defaults-probe selftest (T-1176) =="

  say "-- 1. a suite that is not there is NO-SAMPLE, never an empty reading"
  FAKE_PGREP="/bin/zsh -f $ws/pgrep-absent"
  probe "$ws/fixtures/nothing-here.plist" sample
  check "an unreadable plist -> NO-SAMPLE (exit 3)" \
    $( (( rc == 3 )) && [[ "$out" == *"group-defaults: NO-SAMPLE"* ]] && print 1 || print 0 ) "exit $rc: $out"
  probe NONE compare "$ws/records/never-written" "$ws/records/also-never"
  check "comparing records that were never written -> NO-SAMPLE (exit 3)" \
    $( (( rc == 3 )) && [[ "$out" == *"group-defaults: NO-SAMPLE"* ]] && print 1 || print 0 ) "exit $rc: $out"

  say "-- 2. the verdict is the HASH. cfprefsd moves the mtime without moving a byte."
  write_plist "$ws/fixtures/a.plist" "1791260184.86859" ""
  cp "$ws/fixtures/a.plist" "$ws/fixtures/b.plist"
  touch -t 200001010101.01 "$ws/fixtures/a.plist"
  touch -t 203001010101.01 "$ws/fixtures/b.plist"
  probe "$ws/fixtures/a.plist" sample "$ws/records/a"
  probe "$ws/fixtures/b.plist" sample "$ws/records/b"
  probe NONE compare "$ws/records/a" "$ws/records/b"
  check "byte-identical fixtures 30 years apart in mtime -> UNMOVED (exit 0)" \
    $( (( rc == 0 )) && [[ "$out" == *"group-defaults: UNMOVED"* ]] && print 1 || print 0 ) "exit $rc: $out"
  # The control for the check above. Without it, a comparison that always said UNMOVED would pass.
  write_plist "$ws/fixtures/c.plist" "1791260999.5" ""
  touch -t 200001010101.01 "$ws/fixtures/c.plist"
  probe "$ws/fixtures/c.plist" sample "$ws/records/c"
  probe NONE compare "$ws/records/a" "$ws/records/c"
  check "one changed value, mtimes identical -> MOVED (exit 1), naming the key CHANGED" \
    $( (( rc == 1 )) && [[ "$out" == *"group-defaults: MOVED"* && "$out" == *"cadence.widgets.lastReloadAt: CHANGED"* ]] && print 1 || print 0 ) "exit $rc: $out"
  check "a verdict carries NOT AN ATTRIBUTION and names no writer" \
    $( [[ "$out" == *"NOT AN ATTRIBUTION"* ]] && print 1 || print 0 ) "$out"

  say "-- 3. absent and present are different facts: two of the three keys do not exist yet"
  write_plist "$ws/fixtures/d.plist" "1791260184.86859" '	<key>cadence.widgets.today.recentlyCompletedTasks</key>
	<dict><key>abc</key><real>12</real></dict>'
  probe "$ws/fixtures/d.plist" sample "$ws/records/d"
  check "an absent key samples as ABSENT, not as an empty value" \
    $( [[ "$out" == *"key cadence.widgets.habits.recentlyChangedHabits = ABSENT"* ]] && print 1 || print 0 ) "$out"
  probe NONE compare "$ws/records/a" "$ws/records/d"
  check "absent -> present reads CREATED, which is what a launch would have to do here" \
    $( [[ "$out" == *"cadence.widgets.today.recentlyCompletedTasks: CREATED"* ]] && print 1 || print 0 ) "$out"
  check "CREATED is not reported as CHANGED, and the untouched key is HELD" \
    $( [[ "$out" != *"recentlyCompletedTasks: CHANGED"* && "$out" == *"cadence.appearance.accentPaletteID: HELD"* ]] && print 1 || print 0 ) "$out"
  probe NONE compare "$ws/records/d" "$ws/records/a"
  check "present -> absent reads REMOVED" \
    $( [[ "$out" == *"cadence.widgets.today.recentlyCompletedTasks: REMOVED"* ]] && print 1 || print 0 ) "$out"

  say "-- 4. the value is read through plutil, because PlistBuddy reads it through a float32"
  # 1791260184.86859 is the real file's stored double; `PlistBuddy -c Print` renders it 1791260160,
  # the nearest float32, 24.87 seconds early. A small write to this key would be invisible there.
  probe "$ws/fixtures/a.plist" sample
  check "FLOAT32-TRUNCATION: the stored double is reported whole, not rounded to 1791260160" \
    $( [[ "$out" == *"1791260184.86859"* && "$out" != *"1791260160"* ]] && print 1 || print 0 ) "$out"

  say "-- 5. reading never writes, and the read works where writing cannot"
  local before_sha after_sha
  cp "$ws/fixtures/a.plist" "$ws/readonly/g.plist"
  before_sha="$(shasum -a 256 "$ws/readonly/g.plist" | cut -d' ' -f1)"
  chmod 500 "$ws/readonly"
  probe "$ws/readonly/g.plist" sample
  chmod 700 "$ws/readonly"
  after_sha="$(shasum -a 256 "$ws/readonly/g.plist" | cut -d' ' -f1)"
  check "a sample from a directory it cannot write to still reads, and changes no byte" \
    $( (( rc == 0 )) && [[ "$before_sha" == "$after_sha" && "$out" == *sha256=* ]] && print 1 || print 0 ) "exit $rc: $before_sha vs $after_sha"

  say "-- 6. a record may not be written into the data it reads"
  probe "$ws/fixtures/a.plist" sample "$ws/Group Containers/record"
  check "a record path inside a group container is REFUSING-TO-WRITE (exit 2)" \
    $( (( rc == 2 )) && [[ "$out" == *"REFUSING-TO-WRITE"* ]] && print 1 || print 0 ) "exit $rc: $out"
  probe "$ws/fixtures/a.plist" sample "$ws/Cadence Store Backups/record"
  check "a record path inside a backups folder is refused the same way" \
    $( (( rc == 2 )) && [[ "$out" == *"REFUSING-TO-WRITE"* ]] && print 1 || print 0 ) "exit $rc: $out"
  # Both directions, because the refusal cost this script a red run in exactly the shape a
  # one-directional check cannot see. Inside the App-Sandboxed test host $TMPDIR is
  # `~/Library/Containers/com.haoranwei.Cadence/Data/tmp/`, so a refusal keyed on the container as
  # a whole refuses the selftest's own workspace -- measured 2026-10-09, 9 checks failed, every one
  # of them on a record it could not write. A guard that refuses everything protects nothing.
  mkdir -p "$ws/com.haoranwei.Cadence/Data/Library/Preferences" "$ws/com.haoranwei.Cadence/Data/tmp"
  probe "$ws/fixtures/a.plist" sample "$ws/com.haoranwei.Cadence/Data/Library/Preferences/record"
  check "a record path in the container's Library is REFUSING-TO-WRITE (exit 2)" \
    $( (( rc == 2 )) && [[ "$out" == *"REFUSING-TO-WRITE"* ]] && print 1 || print 0 ) "exit $rc: $out"
  probe "$ws/fixtures/a.plist" sample "$ws/com.haoranwei.Cadence/Data/tmp/record"
  check "a record path in the same container's tmp is ALLOWED -- the host's own TMPDIR lives there" \
    $( (( rc == 0 )) && [[ "$out" != *"REFUSING-TO-WRITE"* && -s "$ws/com.haoranwei.Cadence/Data/tmp/record" ]] && print 1 || print 0 ) "exit $rc: $out"

  say "-- 7. the suite and the four keys are spelled as their declaring sources spell them"
  local id_sites key_misses=0 k src
  id_sites="$(grep -cF -- "\"$GDP_GROUP_ID\"" "$ROOT_DIR/Cadence/Services/CadenceStoreSupport.swift" 2>/dev/null)"
  check "the app-group id matches CadenceStoreSupport.appGroupIdentifier" \
    $( [[ "${id_sites:-0}" -ge 1 ]] && print 1 || print 0 ) "CadenceStoreSupport.swift names it ${id_sites:-0} time(s)"
  for k in $GDP_KEYS; do
    case "$k" in
      cadence.appearance.*) src="$ROOT_DIR/Cadence/Shared/Theme.swift" ;;
      *) src="$ROOT_DIR/Cadence/Services/CadenceWidgetRefreshCenter.swift" ;;
    esac
    grep -qF -- "\"$k\"" "$src" 2>/dev/null || { key_misses=$((key_misses+1)); say "     $k is not spelled in ${src:t}" }
  done
  check "all four keys are spelled in Theme.swift / CadenceWidgetRefreshCenter.swift" \
    $( (( key_misses == 0 )) && print 1 || print 0 ) "$key_misses key(s) unmatched"

  say "-- 8. 'the owner's app was not running' is a claim, and a denied process list cannot make it"
  FAKE_PGREP="/bin/zsh -f $ws/pgrep-running"
  probe "$ws/fixtures/a.plist" sample
  check "a pgrep that finds the app -> owner-app=running" \
    $( [[ "$out" == *"owner-app=running"* ]] && print 1 || print 0 ) "$out"
  FAKE_PGREP="/bin/zsh -f $ws/pgrep-blind"
  probe "$ws/fixtures/a.plist" sample "$ws/records/blind"
  check "a pgrep DENIED the process list -> owner-app=unknown, never owner-app=absent" \
    $( [[ "$out" == *"owner-app=unknown"* && "$out" != *"owner-app=absent"* ]] && print 1 || print 0 ) "$out"
  probe NONE compare "$ws/records/blind" "$ws/records/blind"
  check "a sample taken blind prints ATTRIBUTION WITHHELD in the verdict" \
    $( [[ "$out" == *"ATTRIBUTION WITHHELD"* ]] && print 1 || print 0 ) "$out"
  FAKE_PGREP="/bin/zsh -f $ws/pgrep-absent"
  probe "$ws/fixtures/a.plist" sample
  check "a pgrep that answers and finds nothing -> owner-app=absent" \
    $( [[ "$out" == *"owner-app=absent"* ]] && print 1 || print 0 ) "$out"

  say "-- 9. no probe left a shell error in its report"
  check "no probe printed a set -u failure, a bad substitution or a missing command" \
    $( [[ "$out" != *"parameter not set"* && "$out" != *"bad substitution"* \
          && "$out" != *"command not found"* ]] && print 1 || print 0 ) "$out"

  say "checks: $passed passed, $failed failed"
  (( failed == 0 ))
}

# --- dispatch ----------------------------------------------------------------------------------

case "${1:-}" in
  sample) group_defaults_sample "${2:-}"; exit $? ;;
  compare)
    [[ -n "${2:-}" && -n "${3:-}" ]] || { say "usage: ./scripts/group-defaults-probe.sh compare <before> <after>"; exit 2 }
    group_defaults_compare "$2" "$3"; exit $?
    ;;
  selftest) selftest; exit $? ;;
  *)
    say "usage: ./scripts/group-defaults-probe.sh sample [<record-file>]"
    say "       ./scripts/group-defaults-probe.sh compare <before> <after>"
    say "       ./scripts/group-defaults-probe.sh selftest"
    exit 2
    ;;
esac
