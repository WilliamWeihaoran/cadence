#!/bin/sh
# A generated, surface-grouped batch plan for the owed on-screen sightings (T-12960).
#
#   ./scripts/sighting-plan.sh                      # the batch plan: 4 agents, grouped by surface
#   ./scripts/sighting-plan.sh plan --per-agent 8   # the same, with a different cap per agent
#   ./scripts/sighting-plan.sh plan --exclude T-1,T-2
#                                                   # leave out ids a sibling already holds
#   ./scripts/sighting-plan.sh stock                # the backlog stock, and its trend over 7 days
#   ./scripts/sighting-plan.sh ids                  # just the ids, one per line, for scripting
#   ./scripts/sighting-plan.sh selftest             # prove every reading below still fires
#
# WHY THIS EXISTS
#
# A scheduled run has no simulator and no Mac frame, so its agents land from source and unit tests
# only and then correctly file "this was never seen on screen". Nothing in the scheduled path can
# ever retire one of those: the debt is undischargeable by the thing that creates it. Measured
# 2026-11-07, the stock went 40 -> 140 in six days while the whole active ledger grew by 61 -- that
# is, sighting debt was MORE than all the net growth, and every other category was draining.
#
# Only an attended session can pay it down, and attended time is the scarce resource. So the cost
# that matters is not "how many tickets" but "how many app launches": 135 of those 140 entries name
# the device they need, and an agent that takes same-surface sightings in ONE launch does six or
# eight where a filing-order batch does three. That grouping is the whole point of this script.
#
# THIS IS DERIVED, NOT MAINTAINED, for the reason `ledger-view.sh` gives at length: every line of
# output is read out of `docs/TODO.md` at the moment it is asked for. There is no second list.
#
# WHAT COUNTS AS AN OWED SIGHTING
#
# The entry's FIRST LINE opens a bold run introducing OPEN or PARTIAL -- the same narrowness
# `ledger-view.sh` settled on, so an entry that merely quotes a token in prose does not count -- and
# that line says SIGHTING OWED, SIGHTING-OWED or ATTENDED SIGHTING. A CLOSED entry recording a
# sighting that HAPPENED is not debt and must not appear here; that is the reading that makes the
# naive `grep -c SIGHTING` over the whole ledger useless, since it counts both directions at once.
#
# HOW A TICKET GETS ITS SURFACE
#
# From the device the entry itself names: `Cadence-iPhone15`, `Cadence-iPadPro11`,
# `run-macos-app.sh`, or the words iPhone / iPad / macOS. Entries naming more than one surface are
# eligible for each, and the greedy pass below puts each ticket in whichever eligible bucket is
# smallest at the time, so one agent does not get all twenty and its siblings three. An entry that
# names NO surface goes to `unassigned` and is reported rather than silently dropped -- there were 5
# of them when this was written, and a silent drop is how a sighting goes missing for a week.
#
# WHAT THIS DELIBERATELY DOES NOT DO
#
# It does not consolidate many sightings into one per-surface checklist ticket. That would shrink
# the count overnight and is the wrong trade: a to-do buried inside another entry's prose is never
# updated when someone acts on it, which this repository has paid for once already. One ticket per
# sighting stays independently closable; only the BATCH is grouped.

set -eu

LEDGER_REF="${CADENCE_SIGHTING_SOURCE:-HEAD:docs/TODO.md}"
PER_AGENT=6
EXCLUDE=""
ACTION="plan"

say() { printf '%s\n' "$*"; }
die() { printf 'sighting-plan: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------- argument reading

if [ $# -gt 0 ]; then
    case "$1" in
        plan|stock|ids|selftest) ACTION="$1"; shift ;;
        --*) ;;
        *) die "unknown action '$1' -- plan, stock, ids or selftest" ;;
    esac
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --per-agent)
            [ $# -ge 2 ] || die "--per-agent needs a number"
            PER_AGENT="$2"
            case "$PER_AGENT" in
                ''|*[!0-9]*) die "--per-agent takes a number, got '$PER_AGENT'" ;;
            esac
            [ "$PER_AGENT" -gt 0 ] || die "--per-agent must be above zero"
            shift 2 ;;
        --exclude)
            [ $# -ge 2 ] || die "--exclude needs a comma-separated id list"
            EXCLUDE="$2"; shift 2 ;;
        *) die "unknown option '$1'" ;;
    esac
done

ledger() {
    git show "$LEDGER_REF" 2>/dev/null || die "cannot read $LEDGER_REF -- run this inside the repo"
}

# ---------------------------------------------------------------- the reading

# One line per owed sighting: "<id>\t<surfaces>\t<summary>".
# `surfaces` is a comma-joined subset of phone,ipad,mac, or "none".
owed() {
    ledger | awk -F'\t' '
        /^- \[T-[0-9]+\] \*\*(OPEN|PARTIAL)[ ,.;:)]/ {
            line = $0
            up = toupper(line)

            # The debt reading: owed, not recorded. A CLOSED entry never reaches here.
            # Case-insensitive: entries write it as "SIGHTING OWED", "Sighting owed" and
            # "sighting-owed", and a case-sensitive read found 51 of the 140 that exist.
            if (up !~ /SIGHTING[ -]OWED/ && up !~ /ATTENDED SIGHTING/) next

            id = line
            sub(/^- \[/, "", id)
            sub(/\].*$/, "", id)

            s = ""
            if (up ~ /IPHONE/) s = s "phone,"
            if (up ~ /IPAD/)   s = s "ipad,"
            if (up ~ /RUN-MACOS-APP/ || up ~ /MACOS/ || up ~ /MAC /) s = s "mac,"
            if (s == "") s = "none,"
            sub(/,$/, "", s)

            # A readable stub: the prose the entry opens with after its lead run. The lead run is
            # `**STATE date (provenance) -- `, so the summary starts at the FIRST " -- " and ends at
            # the first "**" after it. Taking the last "**" instead (the greedy read) yields
            # "RC-TRIAGE: POST-RC." for a third of the ledger, which names nothing.
            sum = ""
            i = index(line, " -- ")
            if (i > 0) {
                sum = substr(line, i + 4)
                j = index(sum, "**")
                if (j > 0) sum = substr(sum, 1, j - 1)
            }
            if (sum == "") { sum = line; sub(/^- \[T-[0-9]+\] \*\*/, "", sum) }
            gsub(/\*\*/, "", sum)
            gsub(/^[ \t]+|[ \t]+$/, "", sum)
            if (length(sum) > 92) { sum = substr(sum, 1, 92); sub(/ [^ ]*$/, "", sum); sum = sum "..." }

            printf "%s\t%s\t%s\n", id, s, sum
        }'
}

excluded() {
    # exit 0 when $1 is in the --exclude list
    [ -n "$EXCLUDE" ] || return 1
    printf '%s' ",$EXCLUDE," | tr -d ' ' | grep -q ",$1,"
}

active_count() {
    ledger | grep -cE '^- \[T-[0-9]+\] \*\*(OPEN|PARTIAL|PARKED)[ ,.;:)]' || true
}

# ---------------------------------------------------------------- stock

stock_now() { owed | wc -l | tr -d ' '; }

stock() {
    n=$(stock_now)
    a=$(active_count)
    say "== sighting debt =="
    if [ "$a" -gt 0 ]; then
        say "  now:  $n owed, of $a active ($(( n * 100 / a ))%)"
    else
        say "  now:  $n owed"
    fi
    say ""
    say "  trend (first commit before noon each day):"
    i=7
    while [ "$i" -ge 1 ]; do
        d=$(date -v-"${i}"d '+%Y-%m-%d' 2>/dev/null || date -d "$i days ago" '+%Y-%m-%d' 2>/dev/null || echo "")
        [ -n "$d" ] || break
        sha=$(git rev-list -1 --before="$d 12:00" HEAD 2>/dev/null || true)
        if [ -n "$sha" ]; then
            on=$(CADENCE_SIGHTING_SOURCE="$sha:docs/TODO.md" "$0" ids 2>/dev/null | wc -l | tr -d ' ')
            oa=$(git show "$sha:docs/TODO.md" 2>/dev/null | grep -cE '^- \[T-[0-9]+\] \*\*(OPEN|PARTIAL|PARKED)[ ,.;:)]' || true)
            if [ "${oa:-0}" -gt 0 ]; then
                say "    $d   owed=$on  active=$oa  ($(( on * 100 / oa ))%)"
            else
                say "    $d   owed=$on"
            fi
        fi
        i=$(( i - 1 ))
    done
}

# ---------------------------------------------------------------- the plan

AGENTS="phone ipad mac"

bucket_label() {
    case "$1" in
        phone) say "sightphone   Cadence-iPhone15    CAD0F62C-5A83-4FE5-BEBB-5F567FD456B0" ;;
        ipad)  say "sightipad    Cadence-iPadPro11   630EA883-AA8E-4290-9E37-C616B58D40BD" ;;
        mac)   say "sightmac     macOS               scripts/run-macos-app.sh (never the shipping configuration)" ;;
    esac
}

plan() {
    work=$(mktemp -t sighting-plan.XXXXXX) || die "cannot make a work file"
    # shellcheck disable=SC2064
    trap "rm -f '$work' '$work'.*" EXIT INT TERM

    owed > "$work"

    # Greedy balance: rarest-surface tickets first, each into its smallest eligible bucket.
    : > "$work".phone; : > "$work".ipad; : > "$work".mac; : > "$work".none

    # one-surface entries first, so a ticket that can only go one place is never crowded out
    for pass in 1 2; do
        while IFS='	' read -r id surfaces summary; do
            [ -n "$id" ] || continue
            excluded "$id" && continue

            n=$(printf '%s' "$surfaces" | awk -F, '{print NF}')
            if [ "$pass" = 1 ] && [ "$n" != 1 ]; then continue; fi
            if [ "$pass" = 2 ] && [ "$n" = 1 ]; then continue; fi

            if [ "$surfaces" = "none" ]; then
                printf '%s\t%s\n' "$id" "$summary" >> "$work".none
                continue
            fi

            best=""; best_n=-1
            for s in $(printf '%s' "$surfaces" | tr ',' ' '); do
                c=$(wc -l < "$work.$s" | tr -d ' ')
                if [ "$c" -ge "$PER_AGENT" ]; then continue; fi
                if [ "$best_n" -lt 0 ] || [ "$c" -lt "$best_n" ]; then best="$s"; best_n="$c"; fi
            done
            [ -n "$best" ] || continue   # every eligible bucket is full; it waits for the next slot
            printf '%s\t%s\n' "$id" "$summary" >> "$work.$best"
        done < "$work"
    done

    total=$(wc -l < "$work" | tr -d ' ')
    planned=0
    for s in $AGENTS; do
        planned=$(( planned + $(wc -l < "$work.$s" | tr -d ' ') ))
    done

    say "== owed sightings: $total  --  this batch takes $planned, grouped so each agent launches the app once =="
    say ""

    for s in $AGENTS; do
        c=$(wc -l < "$work.$s" | tr -d ' ')
        [ "$c" -gt 0 ] || continue
        printf -- '-- '; bucket_label "$s"
        while IFS='	' read -r id summary; do
            printf '     %-9s %s\n' "$id" "$summary"
        done < "$work.$s"
        say ""
    done

    nc=$(wc -l < "$work".none | tr -d ' ')
    if [ "$nc" -gt 0 ]; then
        say "-- unassigned: $nc entry(s) name no device, so no agent can be sure where to look."
        say "   Read them and say which surface they want; they are NOT in the batch above."
        while IFS='	' read -r id summary; do
            printf '     %-9s %s\n' "$id" "$summary"
        done < "$work".none
        say ""
    fi

    left=$(( total - planned - nc ))
    if [ "$left" -gt 0 ]; then
        say "$left further owed sighting(s) did not fit at --per-agent $PER_AGENT; they keep for the next slot."
    fi
}

# ---------------------------------------------------------------- selftest

selftest() {
    tmp=$(mktemp -d -t sighting-selftest.XXXXXX) || die "cannot make a temp dir"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT INT TERM
    fails=0
    check() {
        if [ "$2" = "$3" ]; then say "  ok    $1"
        else say "  FAIL  $1: expected '$3', got '$2'"; fails=$(( fails + 1 )); fi
    }

    cat > "$tmp/ledger.md" <<'FIXTURE'
## Open — decided, not started
- [T-90001] **OPEN 2026-11-07 (agent `a`) -- SIGHTING OWED for [[T-1]]: on `Cadence-iPhone15` do the thing.**
- [T-90002] **PARTIAL 2026-11-07 (agent `b`) -- SIGHTING OWED: an ATTENDED run via `run-macos-app.sh`.**
- [T-90003] **CLOSED 2026-11-07 (agent `c`) -- SIGHTING done on `Cadence-iPhone15`, seen on screen.**
- [T-90004] **OPEN 2026-11-07 (agent `d`) -- ATTENDED SIGHTING owed on `Cadence-iPadPro11` and `Cadence-iPhone15`.**
- [T-90005] **OPEN 2026-11-07 (agent `e`) -- SIGHTING OWED, but no device is named here at all.**
- [T-90006] **OPEN 2026-11-07 (agent `f`) -- an ordinary open ticket that mentions no debt.**
- [T-90007] **OPEN 2026-11-07 (agent `g`) -- prose quoting `SIGHTING OWED` is still a reading we accept.**
## Done
- [T-90008] **OPEN 2026-11-07 -- SIGHTING OWED on `Cadence-iPhone15`, but below ## Done.**
FIXTURE

    ( cd "$tmp" && git init -q . && git add ledger.md && \
      git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1 \
      || die "selftest could not build its fixture repo"

    run() { ( cd "$tmp" && CADENCE_SIGHTING_SOURCE="HEAD:ledger.md" sh "$OLDPWD_ABS/scripts/sighting-plan.sh" "$@" ); }

    ids=$(run ids | tr '\n' ' ' | sed 's/ $//')
    check "a CLOSED entry recording a sighting is not debt" \
        "$(printf '%s' "$ids" | grep -c 'T-90003' || true)" "0"
    check "an entry with no debt wording is not debt" \
        "$(printf '%s' "$ids" | grep -c 'T-90006' || true)" "0"
    check "OPEN and PARTIAL debt are both read" \
        "$(printf '%s' "$ids" | grep -c 'T-90001' || true)$(printf '%s' "$ids" | grep -c 'T-90002' || true)" "11"
    check "an entry naming no device is still reported" \
        "$(run plan | grep -c 'T-90005' || true)" "1"
    check "a device-less entry is NOT put in an agent bucket" \
        "$(run plan | sed -n '/unassigned/,$p' | grep -c 'T-90005' || true)" "1"
    check "a two-surface entry lands in exactly one bucket" \
        "$(run plan | grep -c 'T-90004' || true)" "1"
    # three buckets, one ticket each at most, so the batch cannot exceed three lines
    check "--per-agent caps every bucket" \
        "$(run plan --per-agent 1 | sed -n '/unassigned/q;p' | grep -cE '^     T-' || true)" "3"
    check "--exclude drops an id" \
        "$(run plan --exclude T-90001 | grep -c 'T-90001' || true)" "0"

    rc=0; run bogus >/dev/null 2>&1 || rc=$?
    check "an unknown action is refused" "$rc" "2"

    rc=0; run plan --per-agent x >/dev/null 2>&1 || rc=$?
    check "--per-agent rejects a non-number" "$rc" "2"

    rc=0; run plan --exclude >/dev/null 2>&1 || rc=$?
    check "--exclude with no list is refused" "$rc" "2"

    say ""
    if [ "$fails" = 0 ]; then say "selftest: all readings hold"; else die "selftest: $fails failure(s)"; fi
}

OLDPWD_ABS=$(cd "$(dirname "$0")/.." && pwd)

case "$ACTION" in
    plan)     plan ;;
    stock)    stock ;;
    ids)      owed | cut -f1 ;;
    selftest) selftest ;;
esac
