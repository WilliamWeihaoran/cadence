#!/bin/zsh
# T-1640. WHICH COMMITS ON `main` A CI RUN HAS ACTUALLY REPORTED ON, AND WHICH ONES NOTHING HAS.
#
#   ./scripts/ci-run-coverage.sh report [<limit>]   # ask GitHub and git, classify every sha from
#                                                   #   the last COMPLETED CI run to HEAD
#   ./scripts/ci-run-coverage.sh classify <pushed|unpushed> <paths-file> <runs-file>
#   ./scripts/ci-run-coverage.sh attribution <manifest>
#                                                   # T-1950: does every code-bearing commit in a
#                                                   #   push have a run of its OWN? exit 1 if not
#   ./scripts/ci-run-coverage.sh selftest           # prove the classification discriminates
#
# WHY THIS EXISTS
#
# `.github/workflows/ci.yml` keeps exactly ONE run pending per concurrency group, so a third push
# inside one run's window cancels the second's pending run. Measured in T-1489: `1cc26f6a` queued
# 10:01:39 and was cancelled 10:25:07, one second after `8d5ee828` queued. **What that costs is
# BISECT PRECISION, not coverage** -- `main` is linear, so the next run to complete covers the
# skipped commit's tree (T-1489 decided that, deliberately, and this script does not reopen it).
# What was missing is that nothing RECORDS it: a commit whose run was dropped and a commit that
# was never pushed at all both read as "no run for this sha", and they are not the same thing.
#
# THE FIVE-WAY READING, AND THE FIFTH IS THE ONE THE TICKET DID NOT NAME
#
# T-1640 asked for four states -- completed / in flight / cancelled before it started / never
# pushed. Measured against this repository's own run list on 2026-09-30, that reading is WRONG on
# the single most common commit this project makes:
#
#     c6b5b234  CI in_progress          -> IN-FLIGHT
#     3d1f5c33  CI completed cancelled  -> CANCELLED      (the T-1489 case, live in the last 12)
#     2f864cd3  Docs budget only, NO CI run at all
#
# `2f864cd3` is a docs-only commit. `ci.yml`'s `paths-ignore` skips it *by design*, so no CI run
# for it ever existed and none ever will -- and under the four-way reading it is indistinguishable
# from a sha that was never pushed, or from the one state that really is alarming: a pushed commit
# that compiles something and has no run. That is not a rare corner. `ci.yml`'s own comment counts
# **308 of the 430 commits that have ever touched docs/TODO.md** as touching nothing this workflow
# would compile, so the four-way instrument would have cried wolf on the majority of the ledger and
# been switched off inside a week. Hence CI-SKIPPED, and hence the ignore list is READ OUT OF THE
# WORKFLOW rather than copied here -- a second copy of `paths-ignore` is a second thing to forget.
#
# WHAT THIS DELIBERATELY DOES NOT DO (T-1362, T-1489)
#
# It does not hold pushes and it does not re-dispatch a dropped sha. Re-running one superseded
# revision spends another ~35-minute job for a verdict about a tree that has already been
# superseded. Reporting is the whole ask, and the honest severity is small: this is an INSTRUMENT
# gap, not a coverage gap.
#
# AND IT CANNOT REPORT ANYTHING WHILE ITS CALLER IS HUNG
#
# The intended caller is the 20-minute heartbeat scheduled task, and that task has hung twice.
# Measured 2026-09-30 23:35Z from its own run list: the newest run was `running`, `started_at`
# 20:17:05Z, `last_activity_at` 20:17:12Z -- **7.7 seconds of activity and then nothing for 3h18m**,
# with every 20-minute run behind it never started (6 runs total in two days on a 20-minute
# schedule). A long run is NOT the tell: a *succeeded* run in the same list spans 18 hours, because
# it sat out a usage limit. The tell is the SHAPE -- status still `running`, `last_activity_at`
# only seconds after `started_at`, and `now - last_activity_at` in hours. Nothing this script prints
# is evidence about a tree until something actually runs it.

set -uo pipefail
emulate -L zsh
setopt no_nomatch
# zsh writes here-document temp files to $TMPPREFIX, which zsh itself sets at startup to `/tmp/zsh`
# -- never $TMPDIR, and never empty, so a `[[ -z $TMPPREFIX ]]` guard would never fire. Same fix as
# scripts/simulator-claim.sh and scripts/mutate.sh, which found it first (T-719), and it is not
# theoretical here: the FIRST in-sandbox run of this selftest wrote both workflow fixtures as EMPTY
# files -- `can't create temp file for here document: operation not permitted` on stderr, exit 0 on
# the redirection -- so `ignore_patterns` read nothing, every path looked un-ignored, and
# `docs-only-push-is-not-a-missing-run` went red saying `NO-RUN`. A degraded fixture that still
# runs is the expensive kind; what caught it is that the mode asserts a POSITIVE verdict rather
# than "not NO-RUN". The claim that the App-Sandboxed test host refuses that write is held by
# `CadenceGuardScriptSelftestTests.theCIRunCoverageReaderTellsADroppedRunFromASkippedOne`, which is
# what runs this selftest in there and is where the refusal was measured (T-1153, T-1380).
_tmp_base="${TMPDIR:-/tmp/}"; [[ "$_tmp_base" != */ ]] && _tmp_base="$_tmp_base/"
export TMPPREFIX="${CADENCE_TMPPREFIX:-${_tmp_base}zsh}"

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h}"
WORKFLOW="${CADENCE_CI_WORKFLOW:-$REPO_ROOT/.github/workflows/ci.yml}"
CI_WORKFLOW_NAME="${CADENCE_CI_WORKFLOW_NAME:-CI}"

say() { print -r -- "$@" }

usage() {
    say "usage: ./scripts/ci-run-coverage.sh report [<limit>]"
    say "       ./scripts/ci-run-coverage.sh classify <pushed|unpushed> <paths-file> <runs-file>"
    say "       ./scripts/ci-run-coverage.sh attribution <manifest>"
    say "       ./scripts/ci-run-coverage.sh selftest"
}

# --- the ignore list, read out of the workflow ---------------------------------
#
# Returns one `paths-ignore` glob per line, the union over every `on:` trigger that declares one.
# Read rather than copied: the whole reason CI-SKIPPED is safe to report is that it agrees with
# what the workflow will really do, and a hardcoded list agrees with it only until somebody edits
# one of them.
ignore_patterns() {
    awk '
      /^[[:space:]]*paths-ignore:[[:space:]]*$/ { inblock = 1; next }
      inblock {
        if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
          line = $0
          sub(/^[[:space:]]*-[[:space:]]*/, "", line)
          gsub(/^["'"'"']|["'"'"']$/, "", line)
          if (line != "") print line
          next
        }
        inblock = 0
      }
    ' "$WORKFLOW" | awk '!seen[$0]++'
}

# Whether ONE path is covered by ONE GitHub path filter.
#
# Spelled with string operations rather than by handing the pattern to zsh's `==`, on purpose: the
# three shapes this file's filters use (`docs/**`, `**/AGENTS.md`, a bare literal) are exactly the
# three that a glob comparison gets subtly wrong -- `**` is not `*` to git or to Actions, and a
# pattern arriving through a parameter is one more thing whose expansion has to be reasoned about.
path_matches() {
    local path=$1 pattern=$2
    if [[ "$pattern" == */'**' ]]; then
        local prefix="${pattern%/**}"
        # `"$prefix/"*` and not a slice of `$path`: the prefix is QUOTED (so a `.` or a `*` in a
        # directory name stays literal) and only the trailing `*` is a pattern. `docs` must not
        # match `docsy/`, which the quoted separator is what buys.
        [[ "$path" == "$prefix" || "$path" == "$prefix/"* ]]
        return $?
    fi
    if [[ "$pattern" == '**/'* ]]; then
        local suffix="${pattern#\*\*/}"
        [[ "$path" == "$suffix" || "${path:t}" == "$suffix" ]]
        return $?
    fi
    [[ "$path" == "$pattern" ]]
}

# Whether EVERY path a commit touches is ignored -- i.e. the workflow will not start for it.
# An empty path list is NOT ignorable: "this commit touched nothing" is a reading failure, and
# answering CI-SKIPPED to it would be the quiet kind.
all_paths_ignored() {
    local paths_file=$1
    local -a patterns; patterns=("${(@f)$(ignore_patterns)}")
    (( ${#patterns} )) || return 1
    local path pattern hit any=0
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        any=1
        hit=0
        for pattern in $patterns; do
            if path_matches "$path" "$pattern"; then hit=1; break; fi
        done
        (( hit )) || return 1
    done < "$paths_file"
    (( any ))
}

# --- the classification --------------------------------------------------------
#
# runs-file: one line per run of the CI workflow for this sha, `status<TAB>conclusion`.
# An absent or empty file means GitHub knows of no run for the sha.
classify() {
    local pushed=$1 paths_file=$2 runs_file=$3

    if [[ "$pushed" != "pushed" ]]; then
        # A sha that is not on the remote cannot have a run, so no amount of run data changes this
        # and the run file is not consulted. This is the state T-1640 is about telling apart.
        say "NEVER-PUSHED"
        return 0
    fi

    # `run_status`, not `status`: `status` is a READ-ONLY alias for `$?` in zsh, and assigning to
    # it in a function aborts the assignment with `read-only variable: status` on stderr while the
    # function carries on and returns nothing. Measured here on the first run of this selftest --
    # four properties came back with an empty verdict and one passed anyway.
    local run_status conclusion saw_cancelled=0 saw_run=0 completed=""
    if [[ -s "$runs_file" ]]; then
        while IFS=$'\t' read -r run_status conclusion; do
            [[ -n "$run_status" ]] || continue
            saw_run=1
            if [[ "$run_status" != "completed" ]]; then say "IN-FLIGHT"; return 0; fi
            case "$conclusion" in
                cancelled) saw_cancelled=1 ;;
                ""|null)   say "IN-FLIGHT"; return 0 ;;
                *)         [[ -n "$completed" ]] || completed="$conclusion" ;;
            esac
        done < "$runs_file"
    fi

    # A COMPLETED run outranks a cancelled one for the same sha, and that ordering is not cosmetic:
    # the ordinary way a cancelled run is repaired is a re-run, which leaves BOTH records on the
    # sha. Reading the cancelled one there would report a dropped verdict for a tree that has one.
    if [[ -n "$completed" ]]; then say "COMPLETED-$completed"; return 0; fi
    if (( saw_cancelled )); then say "CANCELLED"; return 0; fi

    if (( saw_run == 0 )) && all_paths_ignored "$paths_file"; then
        say "CI-SKIPPED"
        return 0
    fi
    say "NO-RUN"
}

# --- push attribution (T-1950) -------------------------------------------------
#
# GitHub Actions creates ONE run for the pushed **tip**, not one per commit, so an intermediate
# commit in a multi-commit push never gets a run of its own. Measured 2026-10-01 by the coordinator
# on this very instrument's first real use: `report` printed `NO-RUN  4e00a5a6` -- agent
# `searchsent`'s T-1782/T-1600 landing, 8 files and ~420 insertions across `Cadence/Shared/`,
# `Cadence/macOS/Views/` and `CadenceTests/`, so `paths-ignore` is not and cannot be the cause. It
# rode behind `74e9394a`, a docs-only ledger correction that changed no code at all.
#
# WHAT IS LOST IS ATTRIBUTION, NOT COVERAGE, and that distinction is the whole severity. `main` is
# linear, so the tip's tree contains the intermediate commit's bytes and a break is still caught --
# caught, and blamed on a commit that changed nothing. That is the diagnostic failure T-1640 was
# filed about, reproduced live. The remedy is behavioural and free: push after each landing.
#
# WHAT COUNTS AS CODE-BEARING IS NOT SPELLED OUT HERE. T-1950 words it as `Cadence/` or
# `CadenceTests/`; this asks the question `all_paths_ignored` already answers off the real
# `ci.yml` -- "would the workflow have started for this commit?" -- which strictly contains the
# ticket's two directories and also covers `CadenceWidgets/` and `CadenceMCPServer/`, which the
# ticket's wording silently drops. Same argument as CI-SKIPPED: a second copy of the rule is a
# second thing to forget. In `classify`'s vocabulary a code-bearing commit with no run of its own
# is exactly the verdict `NO-RUN`, so nothing new is being decided here, only aggregated.
#
# Manifest: one line per commit IN PUSH ORDER, `sha<TAB>pushed|unpushed<TAB>paths-file<TAB>runs-file`.
cmd_attribution() {
    local manifest="${1:-}"
    [[ -n "$manifest" && -s "$manifest" ]] || {
        say "ci-run-coverage: attribution manifest '${manifest:-<none>}' is missing or empty; nothing was read."
        return 2
    }
    local sha pushed paths runs verdict
    local -a unattributed; unattributed=()
    local seen=0
    while IFS=$'\t' read -r sha pushed paths runs; do
        [[ -n "$sha" ]] || continue
        seen=$(( seen + 1 ))
        verdict=$(classify "$pushed" "$paths" "$runs")
        printf '  %-18s %s\n' "$verdict" "${sha[1,8]}"
        [[ "$verdict" == "NO-RUN" ]] && unattributed+=("${sha[1,8]}")
    done < "$manifest"
    if (( seen == 0 )); then
        say "push attribution: NOTHING-READ"
        return 2
    fi
    say_attribution "$seen" $unattributed
}

# The verdict line, factored so `report` says the same thing `attribution` does rather than growing
# a second wording of it. `report` prints it and keeps its own exit status (see cmd_report).
say_attribution() {
    local seen=$1; shift
    local -a unattributed; unattributed=("$@")
    if (( ${#unattributed} )); then
        say "push attribution: UNATTRIBUTED -- ${#unattributed} of $seen commit(s) have no run of their own: ${(j:, :)unattributed}"
        say "  Actions creates one run for the pushed TIP, so an intermediate code commit in a"
        say "  multi-commit push is never reported on by name (T-1950). The tip's run still covers"
        say "  the tree; what is lost is which commit a break belongs to. Push after each landing."
        return 1
    fi
    say "push attribution: ATTRIBUTED -- all $seen commit(s) either have a run of their own or compile nothing"
    return 0
}

# --- report --------------------------------------------------------------------
cmd_report() {
    local limit="${1:-40}"
    command -v gh >/dev/null 2>&1 || { say "ci-run-coverage: gh is not installed; nothing to ask."; return 2 }
    local slug; slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
    [[ -n "$slug" ]] || { say "ci-run-coverage: could not resolve the repository from gh."; return 2 }

    local ws; ws=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ci-coverage.XXXXXX") || return 2
    gh api "repos/$slug/actions/runs?per_page=100" \
        --jq '.workflow_runs[] | [.head_sha, .name, .status, (.conclusion // "")] | @tsv' \
        > "$ws/runs.tsv" 2>/dev/null || { say "ci-run-coverage: the runs query failed."; rm -rf "$ws"; return 2 }

    # The floor: the newest sha this workflow has a COMPLETED, non-cancelled run for. Everything
    # after it on `main` is what nothing has reported on yet.
    local floor=""
    local sha name run_status conclusion
    while IFS=$'\t' read -r sha name run_status conclusion; do
        [[ "$name" == "$CI_WORKFLOW_NAME" ]] || continue
        [[ "$run_status" == "completed" && -n "$conclusion" && "$conclusion" != "cancelled" ]] || continue
        if git -C "$REPO_ROOT" cat-file -e "${sha}^{commit}" 2>/dev/null; then floor="$sha"; break; fi
    done < "$ws/runs.tsv"

    local -a shas
    if [[ -n "$floor" ]]; then
        shas=("${(@f)$(git -C "$REPO_ROOT" rev-list --reverse "$floor..HEAD" 2>/dev/null)}")
    else
        shas=("${(@f)$(git -C "$REPO_ROOT" rev-list --reverse -n "$limit" HEAD 2>/dev/null)}")
    fi

    say "ci-run-coverage: repository $slug, workflow '$CI_WORKFLOW_NAME'"
    if [[ -n "$floor" ]]; then
        say "  last COMPLETED run: ${floor[1,8]}  -- $(( ${#shas} )) commit(s) after it"
    else
        say "  no completed run found in the last 100; reading the last $limit commits instead"
    fi
    say "  a CANCELLED line is T-1640: the tree is still covered by the next completed run, but the"
    say "  sha that would have said which commit broke something is the one that was dropped."
    say ""

    local remote_head; remote_head=$(git -C "$REPO_ROOT" rev-parse origin/main 2>/dev/null)
    local verdict subject pushed
    local -a unattributed; unattributed=()
    local walked=0
    for sha in $shas; do
        [[ -n "$sha" ]] || continue
        git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$sha" > "$ws/paths" 2>/dev/null
        awk -F'\t' -v s="$sha" -v w="$CI_WORKFLOW_NAME" \
            '$1 == s && $2 == w { print $3 "\t" $4 }' "$ws/runs.tsv" > "$ws/sha-runs"
        if [[ -n "$remote_head" ]] && git -C "$REPO_ROOT" merge-base --is-ancestor "$sha" "$remote_head" 2>/dev/null; then
            pushed=pushed
        else
            pushed=unpushed
        fi
        verdict=$(classify "$pushed" "$ws/paths" "$ws/sha-runs")
        subject=$(git -C "$REPO_ROOT" log -1 --format='%s' "$sha" 2>/dev/null)
        printf '  %-18s %s  %.72s\n' "$verdict" "${sha[1,8]}" "$subject"
        (( walked = walked + 1 ))
        [[ "$verdict" == "NO-RUN" ]] && unattributed+=("${sha[1,8]}")
    done
    rm -rf "$ws"

    # T-1950's reading, over the window this report already walked. It is PRINTED and does not
    # change this subcommand's exit status, on purpose: a sha pushed seconds ago has a window in
    # which Actions has not created its run yet, and the intended caller is a 20-minute heartbeat.
    # An instrument that flaps gets switched off, which is the same argument CI-SKIPPED is built
    # on. `attribution` over an explicit manifest is the deterministic form and exits 1.
    say ""
    (( walked )) && say_attribution "$walked" $unattributed
    return 0
}

# --- selftest ------------------------------------------------------------------
cmd_selftest() {
    local -a failures performed
    failures=(); performed=()
    check() {
        local name=$1 ok=$2 detail=${3:-}
        performed+=("$name")
        say "  $( (( ok )) && print -n "ok  " || print -n "FAIL")  $name$( (( ok )) || print -n "  <- $detail")"
        (( ok )) || failures+=("$name")
    }

    say "== ci-run-coverage.sh selftest (T-1640) =="
    local ws; ws=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ci-coverage-selftest.XXXXXX") || return 2

    # A workflow fixture with this repository's own filters in it, so the reading under test is the
    # reading the real file asks for.
    # `print -rl`, not a here-document: zsh writes here-docs through $TMPPREFIX and this selftest
    # runs inside an App-Sandboxed test host where that write is refused (see the export at the
    # top). The export fixes it; writing the fixture without a temp file at all means the fixture
    # does not depend on the fix being right.
    print -rl -- \
        'on:' \
        '  push:' \
        '    branches: [main]' \
        '    paths-ignore:' \
        "      - 'docs/**'" \
        "      - '**/AGENTS.md'" \
        "      - 'CLAUDE.md'" \
        "      - 'README.md'" \
        '  pull_request:' \
        '    paths-ignore:' \
        "      - 'docs/**'" \
        'jobs:' \
        '  build:' \
        '    runs-on: macos-latest' > "$ws/ci.yml"
    WORKFLOW="$ws/ci.yml"

    # ...and the fixture is CHECKED, loudly, before a single mode reads it. The first in-sandbox
    # run of this selftest produced two empty workflow files and five green modes over them; a
    # fixture that did not set up must look like a fixture that did not set up, not like a verdict.
    if [[ ! -s "$ws/ci.yml" ]] || (( $(ignore_patterns | grep -c .) != 4 )); then
        say "  FAIL  fixture: the workflow fixture is empty or unreadable ($(ignore_patterns | grep -c .) pattern(s)); nothing below would be about the classifier"
        rm -rf "$ws"
        say "checks: 0 passed, 1 failed"
        say "SELFTEST FAILED: fixture"
        return 1
    fi

    print -r -- "docs/TODO.md" > "$ws/docs-only"
    print -rl -- "docs/TODO.md" "Cadence/Shared/Theme.swift" > "$ws/mixed"
    print -r -- "Cadence/Shared/Theme.swift" > "$ws/code-only"
    print -rl -- "CLAUDE.md" "Cadence/Models/AGENTS.md" > "$ws/root-and-nested"
    : > "$ws/no-paths"

    : > "$ws/no-runs"
    print -r -- $'completed\tcancelled'  > "$ws/cancelled"
    print -r -- $'completed\tsuccess'    > "$ws/success"
    print -r -- $'completed\tfailure'    > "$ws/failure"
    print -r -- $'in_progress\t'         > "$ws/in-flight"
    print -r -- $'queued\t'              > "$ws/queued"
    print -rl -- $'completed\tcancelled' $'completed\tsuccess' > "$ws/cancelled-then-rerun"

    local got

    say ""
    say " 1. cancelled-is-not-never-pushed -- the whole of T-1640"
    # The two readings that are indistinguishable today, over the SAME run data, differing only in
    # whether the sha reached the remote. If these ever answer the same thing the instrument is
    # back to where the ticket found it.
    local cancelled_verdict unpushed_verdict
    cancelled_verdict=$(classify pushed "$ws/code-only" "$ws/cancelled")
    unpushed_verdict=$(classify unpushed "$ws/code-only" "$ws/no-runs")
    check "cancelled-is-not-never-pushed" \
        $( [[ "$cancelled_verdict" == "CANCELLED" && "$unpushed_verdict" == "NEVER-PUSHED" ]] && print 1 || print 0 ) \
        "pushed+cancelled='$cancelled_verdict' unpushed='$unpushed_verdict'"
    # ...and the control that makes it a discrimination rather than two constants: an unpushed sha
    # stays unpushed even when GitHub somehow has a run for it, and a pushed one with no run at all
    # does NOT read as cancelled.
    got=$(classify unpushed "$ws/code-only" "$ws/cancelled")
    check "cancelled-is-not-never-pushed: the remote question is asked first" \
        $( [[ "$got" == "NEVER-PUSHED" ]] && print 1 || print 0 ) "got '$got'"

    say ""
    say " 2. docs-only-push-is-not-a-missing-run -- the state the four-way reading loses"
    got=$(classify pushed "$ws/docs-only" "$ws/no-runs")
    check "docs-only-push-is-not-a-missing-run" \
        $( [[ "$got" == "CI-SKIPPED" ]] && print 1 || print 0 ) "got '$got'"
    got=$(classify pushed "$ws/root-and-nested" "$ws/no-runs")
    check "docs-only-push-is-not-a-missing-run: a root literal and a nested **/ match both count" \
        $( [[ "$got" == "CI-SKIPPED" ]] && print 1 || print 0 ) "got '$got'"

    say ""
    say " 3. eligible-push-with-no-run-is-reported -- the one state that IS alarming"
    # The non-vacuity for mode 2: a classifier that answered CI-SKIPPED to everything would pass
    # every check above, and this is the check it cannot pass.
    got=$(classify pushed "$ws/code-only" "$ws/no-runs")
    check "eligible-push-with-no-run-is-reported" \
        $( [[ "$got" == "NO-RUN" ]] && print 1 || print 0 ) "got '$got'"
    # ONE compiled path among ignored ones is enough to make the workflow start, so it is enough
    # here. `paths-ignore` skips a push only when NO file survives the filter.
    got=$(classify pushed "$ws/mixed" "$ws/no-runs")
    check "eligible-push-with-no-run-is-reported: one compiled path among docs still counts" \
        $( [[ "$got" == "NO-RUN" ]] && print 1 || print 0 ) "got '$got'"
    # An empty path list is a reading failure, not a skip.
    got=$(classify pushed "$ws/no-paths" "$ws/no-runs")
    check "eligible-push-with-no-run-is-reported: a commit that touched nothing is not CI-SKIPPED" \
        $( [[ "$got" == "NO-RUN" ]] && print 1 || print 0 ) "got '$got'"

    say ""
    say " 4. a-completed-run-outranks-a-cancelled-one"
    got=$(classify pushed "$ws/code-only" "$ws/cancelled-then-rerun")
    check "a-completed-run-outranks-a-cancelled-one" \
        $( [[ "$got" == "COMPLETED-success" ]] && print 1 || print 0 ) "got '$got'"
    got=$(classify pushed "$ws/code-only" "$ws/failure")
    check "a-completed-run-outranks-a-cancelled-one: a red run is COMPLETED, not missing" \
        $( [[ "$got" == "COMPLETED-failure" ]] && print 1 || print 0 ) "got '$got'"

    say ""
    say " 5. in-flight-is-not-completed"
    got=$(classify pushed "$ws/code-only" "$ws/in-flight")
    check "in-flight-is-not-completed" \
        $( [[ "$got" == "IN-FLIGHT" ]] && print 1 || print 0 ) "got '$got'"
    got=$(classify pushed "$ws/code-only" "$ws/queued")
    check "in-flight-is-not-completed: a queued run has no conclusion and is not CANCELLED" \
        $( [[ "$got" == "IN-FLIGHT" ]] && print 1 || print 0 ) "got '$got'"

    say ""
    say " 6. the-ignore-list-is-read-from-the-workflow"
    # The property that stops `paths-ignore` becoming a second copy. Same commit, same runs, a
    # workflow whose filter no longer covers `docs/**` -- and the verdict has to move. A hardcoded
    # list passes modes 2 and 3 and fails only here.
    print -rl -- \
        'on:' \
        '  push:' \
        '    branches: [main]' \
        '    paths-ignore:' \
        "      - 'README.md'" \
        'jobs:' \
        '  build:' \
        '    runs-on: macos-latest' > "$ws/ci-nodocs.yml"
    local saved="$WORKFLOW"
    WORKFLOW="$ws/ci-nodocs.yml"
    got=$(classify pushed "$ws/docs-only" "$ws/no-runs")
    WORKFLOW="$saved"
    check "the-ignore-list-is-read-from-the-workflow" \
        $( [[ "$got" == "NO-RUN" ]] && print 1 || print 0 ) \
        "a docs-only commit read '$got' against a workflow that does not ignore docs/**"
    # And the same file read back the other way, so the check above cannot pass because the reader
    # returns nothing at all: the real workflow really does declare the four filters.
    WORKFLOW="${CADENCE_CI_WORKFLOW:-$REPO_ROOT/.github/workflows/ci.yml}"
    local -a real; real=("${(@f)$(ignore_patterns)}")
    check "the-ignore-list-is-read-from-the-workflow: the real ci.yml still declares its filters" \
        $( [[ ${#real} -ge 4 && "${real[*]}" == *'docs/**'* && "${real[*]}" == *'**/AGENTS.md'* ]] && print 1 || print 0 ) \
        "read ${#real} pattern(s): ${real[*]}"
    WORKFLOW="$ws/ci.yml"

    say ""
    say " 7. a-code-commit-riding-behind-a-push-is-unattributed -- T-1950"
    # THE ONE-CANDIDATE CAUTION, DISCHARGED. A check that "every code commit has its own run"
    # passes VACUOUSLY on a history where every push is single-commit, so the ticket asks for a
    # grouped push and a single-commit push to be pinned together and the two readings asserted to
    # DIFFER. Both manifests below describe the SAME code commit; the only thing that changes is
    # whether a run exists for it, which is exactly what push grouping takes away.
    #
    # `aaaa1111` is agent `searchsent`'s landing in miniature; `bbbb2222` is the docs-only ledger
    # correction it rode behind, and it is the one with the run.
    print -rl -- \
        $'aaaa1111\tpushed\t'"$ws/code-only"$'\t'"$ws/no-runs" \
        $'bbbb2222\tpushed\t'"$ws/docs-only"$'\t'"$ws/success" > "$ws/grouped-push"
    print -rl -- \
        $'aaaa1111\tpushed\t'"$ws/code-only"$'\t'"$ws/success" > "$ws/single-push"

    local grouped single grouped_rc single_rc
    grouped=$(cmd_attribution "$ws/grouped-push"); grouped_rc=$?
    single=$(cmd_attribution "$ws/single-push");   single_rc=$?
    check "a-code-commit-riding-behind-a-push-is-unattributed" \
        $( [[ "$grouped" == *UNATTRIBUTED* && "$grouped" == *aaaa1111* && $grouped_rc -eq 1 ]] && print 1 || print 0 ) \
        "grouped push read rc=$grouped_rc: ${grouped//$'\n'/ | }"
    check "a-code-commit-riding-behind-a-push-is-unattributed: a single-commit push is attributed" \
        $( [[ "$single" == *ATTRIBUTED* && "$single" != *UNATTRIBUTED* && $single_rc -eq 0 ]] && print 1 || print 0 ) \
        "single-commit push read rc=$single_rc: ${single//$'\n'/ | }"
    # ...and the assertion the ticket actually asks for, stated rather than inferred from the two
    # above: the SAME commit must read DIFFERENTLY depending only on whether it rode behind
    # another. A guard that answered one constant would satisfy exactly one of the two checks.
    check "a-code-commit-riding-behind-a-push-is-unattributed: the two readings differ" \
        $( [[ "$grouped_rc" -ne "$single_rc" ]] && print 1 || print 0 ) \
        "grouped rc=$grouped_rc and single rc=$single_rc are the same reading"

    # THE OTHER DIRECTION, because a guard that fires on every grouped push is as useless as one
    # that fires on none. T-1950 is explicit that "a docs-only commit riding behind a code commit
    # is harmless"; only the reverse costs anything.
    print -rl -- \
        $'cccc3333\tpushed\t'"$ws/docs-only"$'\t'"$ws/no-runs" \
        $'dddd4444\tpushed\t'"$ws/code-only"$'\t'"$ws/success" > "$ws/harmless-group"
    got=$(cmd_attribution "$ws/harmless-group"); local harmless_rc=$?
    check "a-code-commit-riding-behind-a-push-is-unattributed: a docs commit riding behind is harmless" \
        $( [[ "$got" == *ATTRIBUTED* && "$got" != *UNATTRIBUTED* && $harmless_rc -eq 0 ]] && print 1 || print 0 ) \
        "a grouped push carrying only a docs commit read rc=$harmless_rc: ${got//$'\n'/ | }"
    # ...and an in-flight run is a run. A code commit whose run has not finished yet is not an
    # unattributed one, or the guard screams at every push for the length of a 35-minute job.
    print -r -- $'eeee5555\tpushed\t'"$ws/code-only"$'\t'"$ws/in-flight" > "$ws/in-flight-push"
    got=$(cmd_attribution "$ws/in-flight-push"); local inflight_rc=$?
    check "a-code-commit-riding-behind-a-push-is-unattributed: an in-flight run is a run" \
        $( [[ "$got" == *ATTRIBUTED* && "$got" != *UNATTRIBUTED* && $inflight_rc -eq 0 ]] && print 1 || print 0 ) \
        "a code commit with an in-flight run read rc=$inflight_rc: ${got//$'\n'/ | }"
    # An empty manifest is a reading failure, not an all-clear -- the same rule as the empty path
    # list in mode 3, and the shape a `git log` that returned nothing would take.
    : > "$ws/empty-push"
    got=$(cmd_attribution "$ws/empty-push"); local empty_rc=$?
    check "a-code-commit-riding-behind-a-push-is-unattributed: an empty manifest is not an all-clear" \
        $( [[ "$got" != *"ATTRIBUTED --"* && $empty_rc -eq 2 ]] && print 1 || print 0 ) \
        "an empty manifest read rc=$empty_rc: ${got//$'\n'/ | }"

    rm -rf "$ws"
    say ""
    say "checks: $(( ${#performed} - ${#failures} )) passed, ${#failures} failed"
    if (( ${#failures} )); then
        say "SELFTEST FAILED: ${(j:, :)failures}"
        return 1
    fi
    say "SELFTEST PASSED"
    return 0
}

case "${1:-}" in
    report)   shift; cmd_report "$@" ;;
    classify) shift; (( $# == 3 )) || { usage; exit 2 }; classify "$@" ;;
    attribution) shift; (( $# == 1 )) || { usage; exit 2 }; cmd_attribution "$@" ;;
    selftest) cmd_selftest ;;
    *)        usage; exit 2 ;;
esac
