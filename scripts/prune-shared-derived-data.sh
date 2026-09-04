#!/bin/zsh
# T-705. Nothing prunes an orphaned entry in the shared `~/Library/Developer/Xcode/DerivedData`,
# and T-517 declined to automate it because "one of the fourteen is the user's own Xcode entry" and
# telling them apart needed a human. It does not any more: an entry with an `info.plist` carries
# `WorkspacePath`, so it is live exactly when that path still exists, and an entry with none is
# attributed by hashing every `Cadence.xcodeproj` this machine actually has right now and checking
# whether one of them produced that entry's own name. Both are positively controlled against the one
# entry already known to be live -- `Cadence-cfagpqwpaaoeixfvenakmzkidwtg`, this repository's own --
# before either is trusted for anything else, the same discipline T-517 used by hand.
#
#   ./scripts/prune-shared-derived-data.sh audit      # report only; the default; never deletes
#   ./scripts/prune-shared-derived-data.sh prune      # delete only what audit calls ORPHAN
#   ./scripts/prune-shared-derived-data.sh selftest   # prove both discriminators on synthetic fixtures
#
# THE HARD RULE, ABSOLUTE
#
# Never delete an entry any live process holds open. `lsof +D <entry>` is checked before every
# single removal -- in `prune`, and nowhere is it skipped -- and a non-empty result skips that entry
# no matter what the two discriminators concluded. The Mac's Xcode is routinely open and indexing
# through its own shared entry while this runs; wiping a live entry's `Build/Products/` out from
# under it is the exact T-86 crash mechanism this repository already keeps a private-`-derivedDataPath`
# rule for builds. This script does not build anything and does not need that rule, but it can still
# delete what a build depends on, which is the same hazard from the other side.
#
# WHAT COUNTS AS AN ENTRY
#
# Only `Cadence-<28 lowercase letters>` names directly under the shared root are considered. Other
# projects' entries, `*.noindex` caches, and anything not matching that shape are left alone
# unconditionally -- this script prunes Cadence's own debris, not the whole shared directory.
#
# THE TWO DISCRIMINATORS
#
#   WITH `info.plist`: read `WorkspacePath`. Its directory exists      -> ATTRIBUTED (kept).
#                       Its directory is gone, or the key is unreadable -> ORPHAN (candidate).
#   WITHOUT `info.plist`: Xcode's directory suffix is a pure function of the absolute project path
#     -- MD5 of the path, split into two big-endian UInt64s, each rendered as 14 base-26 letters via
#     repeated `n % 26` / `n //= 26`, most-significant digit first in the final string (verified by
#     reproducing the one hash this machine already knows is live -- see `positive_control` below,
#     run before every `audit`/`prune` and again inside `selftest`). Every `Cadence.xcodeproj` this
#     machine actually has right now is hashed; a name matching none of them is unattributable and
#     therefore an ORPHAN.
#
# An entry this cannot read cleanly (a malformed name, an `info.plist` whose `WorkspacePath` key is
# present but not a usable string, ...) is reported UNREADABLE and never touched -- refusing to
# guess is the point of building this at all.
#
# WHERE PROJECTS ARE SEARCHED FOR
#
# `$HOME` plus `/private/tmp` and `/tmp`, pruning `.git`, `.Trash`, `Library`, `DerivedData`,
# `node_modules`, `Pods`, `.build` and `.codex-build` wherever they occur -- deep enough for both an
# agent's `/private/tmp/<scratch>/.../Cadence.xcodeproj` and a normal `~/Desktop/Projects/Cadence`,
# and fast because `$HOME/Library` (where the directory being audited itself lives, plus every other
# Xcode cache) is never descended into. A project living somewhere this does not look is
# unattributable and its entry reads as an orphan -- widen `SEARCH_ROOTS` below if that ever matters
# more than the search staying fast.

set -uo pipefail

SCRIPT_PATH="${0:A}"
ROOT_DIR="${SCRIPT_PATH:h:h}"
SHARED_DD="$HOME/Library/Developer/Xcode/DerivedData"
SEARCH_ROOTS=("$HOME" "/private/tmp" "/tmp")

say() { print -r -- "$@" }

PYTHON_BIN="${CADENCE_PYTHON:-}"
if [[ -z "$PYTHON_BIN" ]]; then
    for _candidate in /usr/bin/python3 /Applications/Xcode.app/Contents/Developer/usr/bin/python3 \
                      /opt/homebrew/bin/python3 /usr/local/bin/python3; do
        [[ -x "$_candidate" ]] || continue
        "$_candidate" -c '' >/dev/null 2>&1 || continue
        PYTHON_BIN="$_candidate"; break
    done
fi
if [[ -z "$PYTHON_BIN" ]]; then
    say "prune-shared-derived-data.sh: no working python3 found (tried /usr/bin, Xcode, homebrew)."
    exit 2
fi

usage() {
    say "usage: ./scripts/prune-shared-derived-data.sh audit|prune|selftest"
}

# One entry's verdict per line, TSV: NAME<TAB>VERDICT<TAB>REASON. VERDICT is one of ATTRIBUTED,
# ORPHAN, LIVE, UNREADABLE. Exposed as its own subcommand (below) so `selftest` can drive it against
# a throwaway directory without ever touching $SHARED_DD.
classify_entries() {
    local dd_root="$1"
    shift
    "$PYTHON_BIN" - "$dd_root" "$@" <<'PY'
import hashlib
import os
import plistlib
import re
import subprocess
import sys

dd_root = sys.argv[1]
search_roots = sys.argv[2:]

NAME_RE = re.compile(r'^Cadence-[a-z]{28}$')
EXCLUDED_DIR_NAMES = [".git", ".Trash", "Library", "DerivedData", "node_modules", "Pods",
                      ".build", ".codex-build"]


def dd_suffix(path: str) -> str:
    """Xcode's DerivedData directory suffix for an absolute project path."""
    digest = hashlib.md5(path.encode("utf-8")).digest()
    hi = int.from_bytes(digest[0:8], "big")
    lo = int.from_bytes(digest[8:16], "big")

    def encode(n: int) -> str:
        digits = []
        for _ in range(14):
            digits.append(chr(ord("a") + (n % 26)))
            n //= 26
        digits.reverse()
        return "".join(digits)

    return encode(hi) + encode(lo)


def find_projects(roots, max_depth=12):
    """Every `Cadence.xcodeproj` under any of `roots`, resolved and de-duplicated. Uses `find`'s
    own `-prune` rather than a hand-rolled walk, so depth and pruning semantics are the well-tested
    ones rather than a second copy of them."""
    found = set()
    for root in roots:
        if not root or not os.path.isdir(root):
            continue
        args = ["/usr/bin/find", root, "-maxdepth", str(max_depth), "("]
        for i, name in enumerate(EXCLUDED_DIR_NAMES):
            if i:
                args.append("-o")
            args += ["-name", name]
        args += [")", "-prune", "-o", "-name", "Cadence.xcodeproj", "-type", "d", "-print"]
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=60)
        except Exception:
            continue
        for line in result.stdout.splitlines():
            line = line.strip()
            if line:
                found.add(os.path.realpath(line))
    return found


def lsof_open(path: str) -> str:
    """Non-empty when some process holds a file under `path` open; empty otherwise. A failed check
    is reported as non-empty too -- a safety check that cannot run must never read as 'safe'."""
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "+D", path],
            capture_output=True, text=True, timeout=30
        )
    except Exception as exc:
        return "LSOF-FAILED: %r" % (exc,)
    return result.stdout.strip()


def workspace_path(info_plist: str):
    """`WorkspacePath` out of an entry's info.plist, or (None, reason) when unreadable."""
    try:
        with open(info_plist, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception as exc:
        return None, "info.plist unreadable: %r" % (exc,)
    value = plist.get("WorkspacePath")
    if not isinstance(value, str) or not value:
        return None, "info.plist has no string WorkspacePath"
    return value, None


if not os.path.isdir(dd_root):
    sys.exit(0)

entries = sorted(
    name for name in os.listdir(dd_root)
    if NAME_RE.match(name) and os.path.isdir(os.path.join(dd_root, name))
)

projects = find_projects(search_roots)
project_hashes = {dd_suffix(p): p for p in projects}

for name in entries:
    entry_path = os.path.join(dd_root, name)
    held = lsof_open(entry_path)
    if held:
        pids = sorted({
            parts[1] for line in held.splitlines()[1:]
            if len(parts := line.split()) > 1
        })
        print("\t".join([name, "LIVE", "held open by pid(s) %s" % (",".join(pids) or "unknown")]))
        continue

    info_plist = os.path.join(entry_path, "info.plist")
    if os.path.isfile(info_plist):
        path, err = workspace_path(info_plist)
        if err:
            print("\t".join([name, "UNREADABLE", err]))
        elif os.path.isdir(path):
            print("\t".join([name, "ATTRIBUTED", "info.plist WorkspacePath exists: %s" % path]))
        else:
            print("\t".join([name, "ORPHAN", "info.plist WorkspacePath gone: %s" % path]))
        continue

    suffix = name[len("Cadence-"):]
    matched = project_hashes.get(suffix)
    if matched:
        print("\t".join([name, "ATTRIBUTED", "hash matches live project: %s" % matched]))
    else:
        print("\t".join([
            name, "ORPHAN",
            "no info.plist and hash matches none of %d project(s) found" % len(projects)
        ]))
PY
}

# Reproduces this machine's one known-live hash before anything downstream is trusted -- T-517's
# own discipline. Takes the shared root to check against, so `selftest` can point it at a scratch
# directory instead of the real one without duplicating the encoder.
positive_control() {
    local dd_root="$1"
    local live_project="$ROOT_DIR/Cadence.xcodeproj"
    [[ -d "$live_project" ]] || { say "positive control skipped: $live_project does not exist here"; return 0; }
    local reproduced
    reproduced=$("$PYTHON_BIN" -c '
import hashlib, sys
path = sys.argv[1]
digest = hashlib.md5(path.encode("utf-8")).digest()
hi = int.from_bytes(digest[0:8], "big")
lo = int.from_bytes(digest[8:16], "big")
def encode(n):
    d = []
    for _ in range(14):
        d.append(chr(ord("a") + (n % 26)))
        n //= 26
    d.reverse()
    return "".join(d)
print(encode(hi) + encode(lo))
' "$live_project")
    if [[ -d "$dd_root/Cadence-$reproduced" ]]; then
        say "positive control OK: $live_project -> Cadence-$reproduced (exists in $dd_root)"
        return 0
    else
        say "!! POSITIVE CONTROL FAILED: $live_project hashed to Cadence-$reproduced, which is not"
        say "   a directory $dd_root has. Refusing to trust the hash discriminator."
        return 1
    fi
}

# The shared logic behind `audit` and `prune`: classify every entry under `dd_root`, print it, and
# -- only when `do_prune` is 1 -- delete the ones classified ORPHAN, re-checking nothing extra,
# because `classify_entries` already ran the lsof check for every entry before this ever sees a row.
report_and_maybe_prune() {
    local dd_root="$1" do_prune="$2"
    shift 2
    say "== scanning $dd_root for Cadence-* entries =="
    typeset -a rows
    rows=("${(@f)$(classify_entries "$dd_root" "$@")}")
    if [[ ${#rows[@]} -eq 0 || -z "${rows[1]}" ]]; then
        say "no Cadence-* entries found."
        return 0
    fi
    typeset -i kept=0 orphans=0 live=0 unreadable=0 deleted=0
    typeset -a deleted_names
    local row name rest verdict reason entry_path size
    for row in "${rows[@]}"; do
        [[ -z "$row" ]] && continue
        name="${row%%$'\t'*}"
        rest="${row#*$'\t'}"
        verdict="${rest%%$'\t'*}"
        reason="${rest#*$'\t'}"
        entry_path="$dd_root/$name"
        case "$verdict" in
            ATTRIBUTED) (( kept++ )); say "  KEEP       $name -- $reason" ;;
            LIVE)       (( live++ )); say "  SKIP(live) $name -- $reason" ;;
            UNREADABLE) (( unreadable++ )); say "  SKIP(?)    $name -- $reason" ;;
            ORPHAN)
                (( orphans++ ))
                if [[ "$do_prune" == 1 ]]; then
                    size=$(du -sh "$entry_path" 2>/dev/null | cut -f1)
                    if rm -rf "$entry_path"; then
                        (( deleted++ ))
                        deleted_names+=("$entry_path (${size:-unknown size})")
                        say "  DELETED    $name ($size) -- $reason"
                    else
                        say "  FAILED     $name -- rm -rf did not exit 0, left in place"
                    fi
                else
                    say "  ORPHAN     $name -- $reason"
                fi
                ;;
            *) say "  SKIP(?)    $name -- unrecognized verdict '$verdict': $reason" ;;
        esac
    done
    say ""
    say "== summary =="
    say "  attributed (kept):    $kept"
    say "  live (skipped):       $live"
    say "  unreadable (skipped): $unreadable"
    if [[ "$do_prune" == 1 ]]; then
        say "  orphans deleted:      $deleted / $orphans"
        if (( ${#deleted_names[@]} > 0 )); then
            say "  removed:"
            for d in "${deleted_names[@]}"; do say "    - $d"; done
        fi
    else
        say "  orphans (not deleted; re-run with 'prune' to remove): $orphans"
    fi
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        audit)
            positive_control "$SHARED_DD" || exit 1
            report_and_maybe_prune "$SHARED_DD" 0 "${SEARCH_ROOTS[@]}"
            ;;
        prune)
            positive_control "$SHARED_DD" || exit 1
            report_and_maybe_prune "$SHARED_DD" 1 "${SEARCH_ROOTS[@]}"
            ;;
        # Internal, used by `selftest` to drive the same logic against a throwaway directory
        # instead of the real shared root. Not documented in `usage` on purpose.
        classify)
            shift
            classify_entries "$@"
            ;;
        prune-dd)
            shift
            local target="$1"
            shift
            report_and_maybe_prune "$target" 1 "$@"
            ;;
        selftest)
            "$PYTHON_BIN" - "$SCRIPT_PATH" "$ROOT_DIR" <<'PY'
import hashlib
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

failures = []

def check(label, condition, detail=""):
    if condition:
        print("ok   - %s" % label)
    else:
        print("FAIL - %s%s" % (label, "  (%s)" % detail if detail else ""))
        failures.append(label)

def dd_suffix(path):
    digest = hashlib.md5(path.encode("utf-8")).digest()
    hi = int.from_bytes(digest[0:8], "big")
    lo = int.from_bytes(digest[8:16], "big")
    def encode(n):
        d = []
        for _ in range(14):
            d.append(chr(ord("a") + (n % 26)))
            n //= 26
        d.reverse()
        return "".join(d)
    return encode(hi) + encode(lo)

script, root_dir = sys.argv[1], sys.argv[2]

# Positive control: the one hash this repository already knows is live, same encoder as above.
live_project = os.path.join(root_dir, "Cadence.xcodeproj")
if os.path.isdir(live_project):
    check(
        "hash reproduces the known-live entry for this repository's own project path",
        dd_suffix(live_project) == "cfagpqwpaaoeixfvenakmzkidwtg",
        dd_suffix(live_project),
    )
else:
    print("skip - positive control (%s does not exist here)" % live_project)

scratch = tempfile.mkdtemp(prefix="cadence-prune-selftest-")
try:
    fake_dd = os.path.join(scratch, "DerivedData")
    os.makedirs(fake_dd)
    fake_home = os.path.join(scratch, "home")
    os.makedirs(fake_home)

    # A live project the "no info.plist" path should attribute to.
    live_by_hash_project_dir = os.path.join(fake_home, "LiveByHash")
    live_by_hash_project = os.path.join(live_by_hash_project_dir, "Cadence.xcodeproj")
    os.makedirs(live_by_hash_project)
    live_by_hash_entry_name = "Cadence-" + dd_suffix(os.path.realpath(live_by_hash_project))
    os.makedirs(os.path.join(fake_dd, live_by_hash_entry_name))

    # Attributed via info.plist -- the entry's own name is deliberately hash-orphan-shaped, since
    # info.plist must be consulted first regardless of what the name would otherwise hash to.
    attributed_by_plist_project = os.path.join(fake_home, "AttributedByPlist")
    os.makedirs(attributed_by_plist_project)
    attributed_entry_name = "Cadence-" + "a" * 28
    attributed_entry = os.path.join(fake_dd, attributed_entry_name)
    os.makedirs(attributed_entry)
    with open(os.path.join(attributed_entry, "info.plist"), "wb") as fh:
        plistlib.dump({"WorkspacePath": attributed_by_plist_project}, fh)

    # Orphan via info.plist: WorkspacePath points at a directory that does not exist.
    orphan_by_plist_entry_name = "Cadence-" + "b" * 28
    orphan_by_plist_entry = os.path.join(fake_dd, orphan_by_plist_entry_name)
    os.makedirs(orphan_by_plist_entry)
    with open(os.path.join(orphan_by_plist_entry, "info.plist"), "wb") as fh:
        plistlib.dump({"WorkspacePath": os.path.join(fake_home, "GoneNow")}, fh)

    # Orphan via hash: no info.plist, and no project anywhere hashes to this name.
    orphan_by_hash_entry_name = "Cadence-" + "c" * 28
    orphan_by_hash_entry = os.path.join(fake_dd, orphan_by_hash_entry_name)
    os.makedirs(orphan_by_hash_entry)

    # Looks exactly like the hash-orphan case by name and has no info.plist, but a process holds a
    # file inside it open. Must be reported LIVE and never deleted, regardless of attribution.
    held_open_entry_name = "Cadence-" + "d" * 28
    held_open_entry = os.path.join(fake_dd, held_open_entry_name)
    os.makedirs(held_open_entry)
    held_path = os.path.join(held_open_entry, "held.log")
    open(held_path, "w").close()
    holder = subprocess.Popen(["/usr/bin/tail", "-f", held_path])
    try:
        time.sleep(0.5)  # give tail a moment to actually open the file

        classify = subprocess.run(
            ["/bin/zsh", script, "classify", fake_dd, fake_home],
            capture_output=True, text=True,
        )
        rows = {}
        for line in classify.stdout.strip().splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                rows[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else "")

        check(
            "info.plist pointing at a live workspace is ATTRIBUTED",
            rows.get(attributed_entry_name, (None,))[0] == "ATTRIBUTED",
            rows.get(attributed_entry_name),
        )
        check(
            "info.plist pointing at a gone workspace is ORPHAN",
            rows.get(orphan_by_plist_entry_name, (None,))[0] == "ORPHAN",
            rows.get(orphan_by_plist_entry_name),
        )
        check(
            "no info.plist, hash matches a live project, is ATTRIBUTED",
            rows.get(live_by_hash_entry_name, (None,))[0] == "ATTRIBUTED",
            rows.get(live_by_hash_entry_name),
        )
        check(
            "no info.plist, hash matches nothing, is ORPHAN",
            rows.get(orphan_by_hash_entry_name, (None,))[0] == "ORPHAN",
            rows.get(orphan_by_hash_entry_name),
        )
        check(
            "an entry a live process holds open is LIVE, never ORPHAN, regardless of attribution",
            rows.get(held_open_entry_name, (None,))[0] == "LIVE",
            rows.get(held_open_entry_name),
        )

        # prune-dd must delete exactly the two orphans and leave the other three untouched, while
        # the holder still has the file open.
        subprocess.run(
            ["/bin/zsh", script, "prune-dd", fake_dd, fake_home],
            capture_output=True, text=True,
        )
    finally:
        holder.terminate()
        holder.wait(timeout=5)

    remaining = sorted(os.listdir(fake_dd))
    check(
        "prune-dd removes both orphans and leaves attributed/live entries untouched",
        remaining == sorted([attributed_entry_name, live_by_hash_entry_name, held_open_entry_name]),
        remaining,
    )
finally:
    shutil.rmtree(scratch, ignore_errors=True)

if failures:
    print("\n%d check(s) failed: %s" % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("\nall selftest checks passed")
PY
            ;;
        *)
            usage
            exit 2
            ;;
    esac
}

main "$@"
