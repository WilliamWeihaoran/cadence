#!/bin/zsh
# Regenerate CadenceTests/CadenceRealTreeSweepManifest.txt -- the exact list of every `@Test` that
# sweeps the real product tree (T-808).
#
#   ./scripts/real-tree-sweep-manifest.sh <id>            # check only; says what would change
#   ./scripts/real-tree-sweep-manifest.sh <id> --write    # rewrite the manifest from the scan
#   ./scripts/real-tree-sweep-manifest.sh <id> selftest   # T-873: prove a stale manifest still
#                                                          # yields a non-empty regenerated body
#   ./scripts/real-tree-sweep-manifest.sh <id> selftest -derivedDataPath <path> CODE_SIGN_IDENTITY=...
#                                                          # T-977: anything after the mode is
#                                                          # forwarded verbatim to the internal
#                                                          # `xcb.sh <id> test` call -- CI.yml's
#                                                          # macos-tests job needs this to reuse its
#                                                          # own derived data and signing overrides
#                                                          # rather than paying for a second full
#                                                          # build under an unrelated identity.
#   ./scripts/real-tree-sweep-manifest.sh <id> precheck [--corpus <dir>|--no-corpus] \
#       <manifest-file> <repo-path>[=<file>]...
#                                                          # T-1092: the ~2.6s, build-free half.
#                                                          # Names any `@Test` in the given sources
#                                                          # that is a sweep and is NOT on the
#                                                          # manifest. Hops are resolved against
#                                                          # <dir>, which defaults to this script's
#                                                          # own CadenceTests/ and degrades to the
#                                                          # given sources alone when absent.
#   ./scripts/real-tree-sweep-manifest.sh <id> precheck-selftest
#                                                          # prove the precheck still separates the
#                                                          # eight cases it is built to separate
#
# WHY THE MANIFEST EXISTS
#
# An audit measured 216 tests that walk `Cadence/`, `CadenceWidgets/` or `CadenceMCPServer/` and
# found 0 of them pinned: delete any one of those `@Test` functions and no other test goes red,
# because the ledgers, parsers and fixtures beside it all keep passing while the app-wide sweep
# quietly stops happening. The manifest is the one shared thing that makes such a deletion visible.
#
# WHY IT IS GENERATED AND NOT TYPED
#
# A hand-maintained list of 200-odd names is the next stale ledger, which is the failure this
# repository keeps re-finding. So the classification lives in Swift, in
# `CadenceTests/CadenceRealTreeSweepScan.swift`, where `CadenceTestTargetHygieneTests` fails on it
# every run; this script only *runs* that scan and copies what it computed into the file.
#
# WHY NOT `scripts/test-suite-index.sh`
#
# That script answers "which suite declares this test", by parsing `@Test ... func` and attributing
# each to the type whose braces enclose it. It is the right precedent and this script deliberately
# does not re-implement it -- but it has no notion of what a test's body *reaches*, and the
# classification here is exactly that: a walk needle, a product-root path literal and Swift-source
# evidence, unioned across every declaration the test transitively names. Adding that to a shell
# script would put the rule somewhere no test can fail on it, which is the same shape as the hole
# it is meant to close. The Swift scan is the authority; this is its typist.
#
# HOW THE OUTPUT GETS OUT OF THE TEST
#
# The hygiene test prints the regenerated file between two banners when the committed one disagrees
# with it, so the file travels through the `xcodebuild` log rather than through a write from an
# App-Sandboxed test host into the repository.
#
# T-873. The banners are printed by the `xcodebuild test` invocation itself, and `scripts/xcb.sh`
# writes THAT output to its own fixed path -- "${TMP_BASE}cadence-xcb-$ID.log" -- not to the stdout
# this script used to capture and scan. That stdout is only xcb.sh's own preflight/result summary,
# so the awk below found nothing on the one path anyone runs this for: a failing run (a stale
# manifest, i.e. every real invocation) has `RUN_STATUS != 0`, which skipped the "already matches"
# read of that emptiness and reported "the run failed and printed no manifest" instead -- even
# though the scan printed a full manifest every time, just into a file this script never opened.
# `selftest` below pins exactly this: a deliberately stale manifest must still yield a non-empty
# regenerated body.
set -uo pipefail
ROOT_DIR="${0:A:h:h}"
ID="${1:-}"
MODE="${2:-}"
if [[ -z "$ID" ]]; then
    print -r -- "usage: real-tree-sweep-manifest.sh <id> [--write|selftest]" >&2
    exit 2
fi
if [[ -n "$MODE" && "$MODE" != "--write" && "$MODE" != "selftest" \
      && "$MODE" != "precheck" && "$MODE" != "precheck-selftest" ]]; then
    print -r -- "real-tree-sweep-manifest.sh: unknown option '$MODE'" >&2
    exit 2
fi
# Anything past <id> <mode> is passed straight through to the internal `xcb.sh test` call. Empty
# in every caller this repository already had; T-977's CI wiring is the first to use it.
EXTRA_XCB_ARGS=("${@:3}")

MANIFEST="$ROOT_DIR/CadenceTests/CadenceRealTreeSweepManifest.txt"
_tmp_base="${TMPDIR:-/tmp/}"; [[ "$_tmp_base" != */ ]] && _tmp_base="$_tmp_base/"
# zsh writes here-document temp files to $TMPPREFIX and sets that itself at startup, to `/tmp/zsh`
# -- never $TMPDIR, and never empty, so a `[[ -z $TMPPREFIX ]]` guard would never fire. An
# App-Sandboxed caller cannot write /tmp, so every heredoc below dies with `can't create temp file
# for here document` before one line of it runs. Measured 2026-09-07: that is exactly how this
# script's precheck read as broken from inside `CadenceGuardScriptSelftestTests`, which shells out
# to `agent-commit.sh selftest` from the test host. Same fix, same reason, as `scripts/mutate.sh`.
export TMPPREFIX="${CADENCE_TMPPREFIX:-${_tmp_base}zsh}"
# `/usr/bin/python3` is an xcrun shim, and xcrun REFUSES to run inside an App Sandbox, exiting 1
# with nothing on stdout. Probe by running one rather than trusting a path to mean an interpreter.
PYTHON_BIN="${CADENCE_PYTHON:-}"
if [[ -z "$PYTHON_BIN" ]]; then
    for _candidate in /usr/bin/python3 /Applications/Xcode.app/Contents/Developer/usr/bin/python3 \
                      /opt/homebrew/bin/python3 /usr/local/bin/python3; do
        [[ -x "$_candidate" ]] || continue
        "$_candidate" -c '' >/dev/null 2>&1 || continue
        PYTHON_BIN="$_candidate"; break
    done
fi
LOG="${_tmp_base}cadence-real-tree-sweep-${ID}.log"
XCB_LOG="${_tmp_base}cadence-xcb-${ID}.log"
REGENERATED="${_tmp_base}cadence-real-tree-sweep-${ID}.manifest"

# --- precheck: the build-free half (T-1092) -----------------------------------
#
# The scan above is the authority and costs a build plus the test-host lock: measured 158s wall for
# `-only-testing:CadenceTests/CadenceTestTargetHygieneTests` alone on warm derived data, which is
# why nothing can afford to run it on every `xcb.sh test`, and why for three days running a new
# tree-walking test landed with no manifest entry and was found by whoever next paid for the full
# 22-minute suite.
#
# So this is a second, cheap reader -- and the one property that keeps it from being the "shell copy
# of the classifier" that CadenceRealTreeSweepScan's header rightly refuses is that it is **sound,
# not complete**. The Swift scan starts a test's markers at its own body and only ever unions more
# in (`var union = test.markers`, `union.formUnion(...)`), so ANY SUBSET of a test's reach that
# already carries all three markers proves the full reach does. Every declaration this reads is one
# the Swift scan reads, and every span it takes is contained in the span the Swift scan takes -- so
# a test it flags is a sweep by the Swift rule, always. It just cannot see every sweep, and it is
# not asked to: the authoritative test still runs in the full suite behind it.
#
# WHAT IT REACHES, AND WHY THAT CHANGED (T-1092, 2026-09-12)
#
# It used to hop exactly one declaration, inside one file: the test's own body, plus same-file
# `func`s whose names the body mentions. Measured against the committed manifest over all 314 files
# in `CadenceTests/` -- run it yourself, the whole measurement is one command:
#
#   printf 'Fixture/nothingRealIsNamedHere\n' > /tmp/bogus.txt
#   ./scripts/real-tree-sweep-manifest.sh <id> precheck /tmp/bogus.txt CadenceTests/*.swift
#
#   body only                         146 flagged,  0 false positives,  52.1% of 280 entries
#   + one same-file `func` hop        234 flagged,  0 false positives,  83.6%   <- was
#   + transitive, cross-file, stored  280 flagged,  0 false positives, 100.0%   <- now
#
# **It now derives the committed manifest exactly, in 2.6s, with no build.** That is the whole of
# T-1092's "nothing derives it when it changes": the derivation in CI and the one in the full suite
# were both already there (`ci.yml`'s `CadenceTests` job, and `CadenceTestTargetHygieneTests` with
# its regenerated banner) -- what nobody had was a reader the AUTHOR could afford. Three changes,
# each measured by ablation against the same corpus:
#
#   +41  a transitive closure rather than one hop, and `var`/`let` admitted as hop targets. One hop
#        reads the first helper's markers and stops, so `@Test` -> helper -> helper -> walk was
#        invisible; the closure below is a fixed point, so depth is no longer a number. Dropping
#        just the `var`/`let` targets from the finished reader costs 15 of the 280.
#    +5  resolving file-scope names ACROSS files. `CadenceTests` is one module, so
#        `func cadenceAppSwiftFiles()` declared in `CadenceGlobalUndoSurfaceTests.swift:134` is
#        callable unqualified from `CadenceContextlessListSurfaceTests.swift`, and a reader that
#        resolves names only inside one file sees a test that touches nothing. `docs/TODO.md` had
#        already recorded exactly that case, found by an authoritative `--write` run, not by this.
#
# (The two overlap -- a sweep can need both -- so they do not add to 46.)
#
# One reach was tried and is deliberately NOT here: delimiting a braceless `var`/`let` by balanced
# `{}` as well as `()`/`[]`. It also reaches 280, and it reaches five tests that do NOT sweep --
# `theSweepSkipsTheFilesTheMCPServerTargetCompiles` reads the MCP target's explicit source list, not
# a directory. Completeness is the authority's job. Soundness is this one's, and 280 with five wrong
# answers is worse than 280 with none.
#
# Non-vacuity, measured 2026-09-12 the way any detector here has to be: drop
# `CadenceContextlessListSurfaceTests/theAddFirstListRowIsOneComponentBothCallersShare` from the
# committed manifest and run both readers over that one file. The shipped one exits 0 -- it calls
# the stale manifest clean. This one exits 4 and names it.
#
# So the three indexes and the closure below are now the Swift scan's own, including its one
# asymmetry (see `resolved` in `sweeps_in`). What it still misses is 15 tests that reach a walk
# through a `var`/`let`, and hopping those is measured -- 2026-09-12 -- to gain exactly **zero**:
# adding `var`/`let` targets delimited by a same-line brace flagged the identical 265. The Swift
# scan reaches them only because its span reader runs a braceless `static let x = f()` on to the
# next `{` in the file, which is the unsoundness this reader exists to not have (an earlier spelling
# of it reported 23 false positives). Completeness is the authority's job; soundness is this one's.
#
# Both incidents that could be replayed from git -- T-1090's
# `theStoreRootIsNamedInExactlyOnePlaceUnderCadence` (walks in its own body) and T-1091's
# `theAppsNestedHelperTypesNoLongerSwallowTheDeclarationsBelowThem` (walks through a same-file
# `saveCommitSwiftFiles()`) -- were already caught before this change; the cross-file family was not.
#
# `scripts/xcb.sh` is deliberately NOT the caller. It runs per test invocation, including once per
# mutation inside `scripts/mutate.sh`, where the mutation is in product source and the manifest
# cannot have moved; and it commonly runs in a `git archive HEAD` tree, which is not a checkout, so
# it has no cheap "what changed" to gate on -- it would have to re-read all 314 test files every
# run. `agent-commit.sh` runs once, at the last moment before the work becomes everyone's problem,
# in the real repository, and knows exactly which files are being staged.
precheck_needles=(
    'swiftFiles('
    'enumerator(atPath:'
    'enumerator(at:'
    'contentsOfDirectory(at'
    'subpathsOfDirectory'
    '.sweep('
)

cmd_precheck() {
    # `--corpus <dir>` / `--no-corpus` may lead the arguments. The default is this script's own
    # `CadenceTests/`, so no caller has to be taught the flag -- `agent-commit.sh` gets the deeper
    # reach by upgrading this file alone. A copy of the script sitting beside no `CadenceTests/`
    # (agent-commit.sh's own selftest workspaces do exactly that) falls back to source-only.
    local corpus_dir="$ROOT_DIR/CadenceTests"
    while [[ "${1:-}" == --corpus || "${1:-}" == --no-corpus ]]; do
        if [[ "$1" == --no-corpus ]]; then
            corpus_dir=""
            shift
        else
            corpus_dir="${2:-}"
            shift 2
        fi
    done
    [[ -n "$corpus_dir" && -d "$corpus_dir" ]] || corpus_dir=""
    local manifest_file="${1:-}"
    local -a sources
    sources=("${@:2}")
    if [[ -z "$manifest_file" || ! -f "$manifest_file" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: precheck needs a readable manifest file, got '${manifest_file:-(nothing)}'" >&2
        return 2
    fi
    (( ${#sources} )) || {
        print -r -- "real-tree-sweep-manifest.sh: precheck needs at least one <repo-path>[=<file>]" >&2
        return 2
    }
    [[ -n "$PYTHON_BIN" ]] || {
        print -r -- "real-tree-sweep-manifest.sh: no working python3 found, so the precheck cannot answer" >&2
        return 2
    }
    CADENCE_SWEEP_NEEDLES="${(pj:\n:)precheck_needles}" \
    CADENCE_SWEEP_CORPUS="$corpus_dir" \
        "$PYTHON_BIN" -c "$PRECHECK_PY" "$manifest_file" "${sources[@]}"
}

PRECHECK_PY=$(cat <<'PYEOF'
import os, re, sys

# Sound-not-complete reader of the same rule CadenceTests/CadenceRealTreeSweepScan.swift applies.
# Every needle it uses arrives in CADENCE_SWEEP_NEEDLES from the zsh array above, so there is one
# spelling of them in this file and CadenceTestTargetHygieneTests pins that array against the Swift
# scan's own `walkNeedles`.
WALK = [n for n in os.environ.get("CADENCE_SWEEP_NEEDLES", "").split("\n") if n]
if not WALK:
    sys.stderr.write("precheck: no walk needles were handed in, so it would flag nothing\n")
    sys.exit(2)

QUOTE = '"'
PRODUCT = re.compile(
    QUOTE + r"(?:Cadence|CadenceWidgets|CadenceMCPServer)(?:/[^" + QUOTE + r"\n]*)?" + QUOTE
)
SWIFT_SOURCE = re.compile(r"swiftFiles\(|\.swift" + QUOTE)
TEST = re.compile(r"@Test\b[\s\S]*?\bfunc\s+([A-Za-z0-9_]+)")
FUNC = re.compile(r"\bfunc\s+([A-Za-z0-9_]+)")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# Same two patterns the Swift scan resolves hops with: a top-level type's extent, so a member hop
# `Owner.member` lands somewhere, and the `Owner.member` spelling itself.
TYPE = re.compile(r"\b(?:struct|final class|class|actor|enum)\s+([A-Za-z0-9_]+)")
# `var`/`let` are hop targets in the Swift scan too. An earlier spelling of this reader admitted them
# with a `func`'s span rule -- open at the next `{`, close at its match -- and because a braceless
# `static let x = f()` has no brace of its own, that ran on to the next `{` in the FILE and swallowed
# unrelated code: 23 false positives, the exact failure this reader exists to not have. So a
# braceless one is delimited by its own line instead. A line is a subset of the declaration, and a
# subset can only ever under-report, which is the invariant that keeps this sound.
STORED = re.compile(r"\b(?:var|let)\s+([A-Za-z0-9_]+)")
QUALIFIED = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\.\s*([a-z][A-Za-z0-9_]*)")

WALK_MARK, PRODUCT_MARK, SWIFT_MARK = 1, 2, 4
SWEEP = WALK_MARK | PRODUCT_MARK | SWIFT_MARK


def code_only(src):
    """Blank comments and string literals, preserving every offset -- the same invariant
    CadenceRealTreeSweepScan asserts before it trusts a span (`maskOffsetsDisagree`)."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            j = n if j < 0 else j + 3
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                if src[j] == "\\":
                    j += 1
                if j < n and src[j] == "\n":
                    break
                j += 1
            j = min(j + 1, n)
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i)
            j = n if j < 0 else j + 2
        else:
            i += 1
            continue
        for k in range(i, j):
            if out[k] != "\n":
                out[k] = " "
        i = j
    return "".join(out)


def body_span(code, start, after_name):
    """`start` through the close of the brace block that opens after the declaration's name."""
    open_at = code.find("{", after_name)
    if open_at < 0:
        return None
    depth = 0
    for j in range(open_at, len(code)):
        if code[j] == "{":
            depth += 1
        elif code[j] == "}":
            depth -= 1
            if depth == 0:
                return (start, j + 1)
    return None


def stored_span(code, match):
    """A `var`/`let`'s own text: through the first newline at which no `(`, `[` or `{` it opened is
    still open. That covers `var body: some View { … }` and a multi-line `= [ "Cadence", … ]` alike,
    and stops dead at the end of `let count = 5` -- where the `func` span rule used to run on to the
    next `{` in the FILE and swallow the declaration after it."""
    line_end = code.find("\n", match.end(1))
    line_end = len(code) if line_end < 0 else line_end
    if "{" in code[match.end(1):line_end]:
        # A computed property or a `= { … }()`: it brought its own braces, so read them.
        return body_span(code, match.start(), match.end(1))
    depth = 0
    for j in range(match.end(1), len(code)):
        ch = code[j]
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "{":
            # A brace on a LATER line belongs to the declaration after this one.
            return (match.start(), j)
        elif ch == "\n" and depth <= 0:
            return (match.start(), j)
    return (match.start(), len(code))


def markers(code_slice, raw_slice):
    """Walk needles from code (a fixture that *quotes* a sweep is not one); the path literal and the
    Swift-source evidence from raw, where literals survive. Same split as the Swift scan."""
    found = 0
    if any(needle in code_slice for needle in WALK):
        found |= WALK_MARK
    if PRODUCT.search(raw_slice):
        found |= PRODUCT_MARK
    if SWIFT_SOURCE.search(raw_slice):
        found |= SWIFT_MARK
    return found


def references(code_slice):
    """The two name sets a hop can be spelled with, exactly as the Swift scan collects them."""
    return (
        set(IDENT.findall(code_slice)),
        set("%s.%s" % pair for pair in QUALIFIED.findall(code_slice)),
    )


def type_extents(code, depths):
    """`(name, open, close)` for every top-level type, over a copy in which `extension Foo {` reads
    as `enum      Foo {` -- ten characters for ten, so offsets survive. Without it a member hop into
    `extension CadenceSourceScan` resolves to nothing, which is most of the shared support file."""
    as_types = code.replace("extension ", "enum      ")
    extents = []
    for m in TYPE.finditer(as_types):
        if depths[m.start()] != 0:
            continue
        open_at = as_types.find("{", m.end())
        if open_at < 0:
            continue
        close = len(as_types)
        for j in range(open_at + 1, len(as_types)):
            if as_types[j] == "}" and depths[j] == 1:
                close = j
                break
        extents.append((m.group(1), open_at, close))
    return extents


def parse(path, raw):
    """One file's `@Test`s and its hop targets: `func`, `var` and `let` at file scope or one type
    deep, which is the Swift scan's own `depths[...] <= 1` rule. Where the two differ is the SPAN
    each one reads, and this one is always the shorter -- see `stored_span`. Staying a subset is the
    whole soundness argument."""
    code = code_only(raw)
    if len(code) != len(raw):
        raise SystemExit(
            "precheck: masking changed %s's offsets, so spans read the wrong text" % path
        )

    depth, depths = 0, [0] * len(code)
    for i, ch in enumerate(code):
        depths[i] = depth
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1

    test_names = set(m.group(1) for m in TEST.finditer(code))
    extents = type_extents(code, depths)

    tests, decls = [], []
    for m in TEST.finditer(code):
        span = body_span(code, m.start(), m.end(1))
        if not span:
            continue
        slice_code, slice_raw = code[span[0]:span[1]], raw[span[0]:span[1]]
        names, qualified = references(slice_code)
        tests.append((m.group(1), markers(slice_code, slice_raw), names, qualified))

    candidates = [(m, True) for m in FUNC.finditer(code)]
    candidates += [(m, False) for m in STORED.finditer(code)]
    for m, is_function in candidates:
        # A `@Test` is never a hop target: one test naming another's function does not make the
        # caller a sweep.
        if depths[m.start()] > 1 or m.group(1) in test_names:
            continue
        span = body_span(code, m.start(), m.end(1)) if is_function else stored_span(code, m)
        if not span:
            continue
        slice_code, slice_raw = code[span[0]:span[1]], raw[span[0]:span[1]]
        names, qualified = references(slice_code)
        owner = None
        for extent_name, open_at, close in extents:
            if open_at < m.start() < close:
                owner = extent_name
        decls.append({
            "name": m.group(1),
            "file": path,
            "file_scope": depths[m.start()] == 0,
            "owner": owner,
            "markers": markers(slice_code, slice_raw),
            "names": names,
            "qualified": qualified,
        })
    return tests, decls


def sweeps_in(targets, corpus):
    """Every `@Test` in `targets` that reaches a sweep, resolved across the whole `corpus`.

    `corpus` is `{repo_path: source}` and already carries each target's own bytes. The three indexes
    and the closure below are the Swift scan's, including its one asymmetry: an unqualified name is
    resolved **in the file of the test being classified**, never in the file of whichever helper
    mentioned it. Dropping that asymmetry is measured there as 592 "sweeps" where 240 are real,
    because the shared support file reaches a walker by its own internal plumbing."""
    decls = []
    parsed_targets = {}
    for path in sorted(corpus):
        tests, file_decls = parse(path, corpus[path])
        if path in targets:
            parsed_targets[path] = tests
        for decl in file_decls:
            decls.append(decl)

    by_file_and_name, by_file_scope_name, by_qualified_name = {}, {}, {}
    for index, decl in enumerate(decls):
        by_file_and_name.setdefault(decl["file"], {}).setdefault(decl["name"], []).append(index)
        if decl["file_scope"]:
            # `CadenceTests` is one module, so a file-scope `func cadenceAppSwiftFiles` is callable
            # unqualified from any file in it. Resolving these only inside their own file is how a
            # sweep written as a bare call to a helper next door reads as a test that touches
            # nothing -- measured as 43 of the 46 entries this reader used to miss.
            by_file_scope_name.setdefault(decl["name"], []).append(index)
        if decl["owner"]:
            by_qualified_name.setdefault("%s.%s" % (decl["owner"], decl["name"]), []).append(index)

    def resolved(in_file, names, qualified):
        indices = []
        for name, declared in by_file_and_name.get(in_file, {}).items():
            if name in names:
                indices.extend(declared)
        for name in names:
            indices.extend(by_file_scope_name.get(name, ()))
        for name in qualified:
            indices.extend(by_qualified_name.get(name, ()))
        return indices

    found = []
    for path in sorted(parsed_targets):
        for name, own_markers, names, qualified in parsed_targets[path]:
            union = own_markers
            visited = set()
            frontier = resolved(path, names, qualified)
            while frontier:
                index = frontier.pop()
                if index in visited:
                    continue
                visited.add(index)
                union |= decls[index]["markers"]
                if union & SWEEP == SWEEP:
                    break
                frontier.extend(
                    resolved(path, decls[index]["names"], decls[index]["qualified"])
                )
            if union & SWEEP == SWEEP:
                found.append((path, name))
    return found


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError as problem:
        sys.stderr.write("precheck: cannot read %s: %s\n" % (path, problem))
        sys.exit(2)


manifest_path, pairs = sys.argv[1], sys.argv[2:]
listed = set()
with open(manifest_path, encoding="utf-8", errors="replace") as handle:
    for line in handle:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        listed.add(line.split("/", 1)[-1])
if not listed:
    sys.stderr.write("precheck: the manifest handed in names no test, so every sweep would look new\n")
    sys.exit(2)

# The corpus every hop is resolved against. Absent (`--no-corpus`, or a copy of this script with no
# `CadenceTests/` beside it) it degrades to the staged sources alone, which is the same-file-only
# reach this had before -- fewer findings, never a wrong one.
corpus = {}
corpus_root = os.environ.get("CADENCE_SWEEP_CORPUS", "")
if corpus_root:
    for folder, _, files in os.walk(corpus_root):
        for name in files:
            if not name.endswith(".swift"):
                continue
            full = os.path.join(folder, name)
            corpus[os.path.relpath(full, os.path.dirname(corpus_root.rstrip("/")))] = read(full)

# The staged bytes win over the worktree's for any path this commit carries, and a target that is
# not under the corpus root is simply added to it.
targets = set()
for pair in pairs:
    repo_path, _, source_file = pair.partition("=")
    if not repo_path.endswith(".swift"):
        continue
    corpus[repo_path] = read(source_file or repo_path)
    targets.add(repo_path)

unlisted = [(path, name) for path, name in sweeps_in(targets, corpus) if name not in listed]

for repo_path, name in unlisted:
    print("%s\t%s" % (repo_path, name))
sys.exit(4 if unlisted else 0)
PYEOF
)

if [[ "$MODE" == "precheck" ]]; then
    cmd_precheck "${@:3}"
    exit $?
fi

# --- precheck-selftest --------------------------------------------------------
#
# Eight fixtures, because a precheck is only worth calling if it separates them. Four sweeps, one per
# reach this reader has: in the test's own body; through a same-file helper (the T-1091 shape); two
# hops down; and through a file-scope helper in ANOTHER file. Four non-sweeps, one per way of
# looking like one: the fixed-file assertion that names product paths but walks nothing, the test
# that only QUOTES a sweep inside a string, the one already on the manifest, and -- the reason
# `var`/`let` hop targets were refused for so long -- a test that names a braceless `let` declared
# immediately before a sweeping `func`. A reader that stopped reading passes the first four by
# flagging everything, or the last four by flagging nothing, so both directions are asked.
if [[ "$MODE" == "precheck-selftest" ]]; then
    FAILURES=0
    check() {  # $1 = what, $2 = 1|0
        if (( $2 )); then print -r -- "  ok    $1"; else print -r -- "  FAIL  $1"; FAILURES=$((FAILURES + 1)); fi
    }
    WS=$(mktemp -d "${_tmp_base}cadence-sweep-precheck-${ID}-XXXXXX") || exit 2
    trap 'rm -rf "$WS"' EXIT
    print -r -- "SweepPrecheckFixtures/theOneAlreadyOnTheManifest" > "$WS/manifest.txt"

    cat > "$WS/Fixture.swift" <<'SWIFTEOF'
import Testing

struct SweepPrecheckFixtures {
    private func everyProductSwiftFile() throws -> [String] {
        try CadenceSourceScan.swiftFiles(under: "Cadence")
    }

    @Test func theOneInItsOwnBody() throws {
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/Services") {
            #expect(path.hasSuffix(".swift"))
        }
    }

    @Test func theOneThroughASameFileHelper() throws {
        for path in try everyProductSwiftFile() {
            #expect(!path.isEmpty)
        }
    }

    private func theHopInBetween() throws -> Int {
        try everyProductSwiftFile().count
    }

    @Test func theOneTwoHopsDown() throws {
        #expect(try theHopInBetween() > 0)
    }

    @Test func theOneThroughAHelperInAnotherFile() throws {
        for path in try everyAppSwiftFileNextDoor() {
            #expect(!path.isEmpty)
        }
    }

    private static let everyRootWorthWalking = [
        "Cadence",
        "CadenceWidgets",
    ]

    private static func walkingTheRoots() throws -> [String] {
        try everyRootWorthWalking.flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
    }

    @Test func theOneThroughAMultiLineStoredRoot() throws {
        #expect(try Self.walkingTheRoots().count > 0)
    }

    private static let howManyRootsThereAre = 2

    private static func theSweepDeclaredRightAfterIt() throws -> [String] {
        try CadenceSourceScan.swiftFiles(under: "Cadence")
    }

    @Test func theOneThatOnlyNamesABracelessLet() {
        #expect(howManyRootsThereAre == 2)
    }

    @Test func theFixedFileAssertionThatWalksNothing() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Models/AppTask.swift")
        #expect(!source.isEmpty)
    }

    @Test func theOneAlreadyOnTheManifest() throws {
        for path in try CadenceSourceScan.swiftFiles(under: "CadenceWidgets") {
            #expect(path.hasSuffix(".swift"))
        }
    }

    @Test func theOneThatOnlyQuotesASweep() throws {
        let fixture = "for path in try CadenceSourceScan.swiftFiles(under: \"Cadence\") { }"
        #expect(fixture.contains("Cadence"))
    }
}
SWIFTEOF

    # The neighbour file, so `everyAppSwiftFileNextDoor` is a file-scope `func` in a DIFFERENT file.
    # `CadenceTests` is one module, so the call above is legal Swift and reaches this walk.
    cat > "$WS/Neighbour.swift" <<'SWIFTEOF'
import Foundation

func everyAppSwiftFileNextDoor() throws -> [String] {
    try CadenceSourceScan.swiftFiles(under: "Cadence")
}
SWIFTEOF

    OUT=$(cmd_precheck --corpus "$WS" "$WS/manifest.txt" \
        "CadenceTests/Fixture.swift=$WS/Fixture.swift" 2>&1); RC=$?
    print -r -- "real-tree-sweep-manifest.sh: precheck-selftest (exit $RC)"
    check "an unlisted sweep is reported (exit 4)" $(( RC == 4 ))
    check "the body-only sweep is named" $( [[ "$OUT" == *theOneInItsOwnBody* ]] && print 1 || print 0 )
    check "the same-file-helper sweep is named -- the T-1091 shape" \
        $( [[ "$OUT" == *theOneThroughASameFileHelper* ]] && print 1 || print 0 )
    check "the sweep TWO hops down is named -- the reach one hop could not have" \
        $( [[ "$OUT" == *theOneTwoHopsDown* ]] && print 1 || print 0 )
    check "the sweep through a file-scope helper NEXT DOOR is named -- 5 of T-1092's 46" \
        $( [[ "$OUT" == *theOneThroughAHelperInAnotherFile* ]] && print 1 || print 0 )
    check "the sweep whose product root is a multi-line stored \`let\` is named" \
        $( [[ "$OUT" == *theOneThroughAMultiLineStoredRoot* ]] && print 1 || print 0 )
    # The other half of admitting `var`/`let`, and the reason the earlier reader refused to: a
    # braceless `let` must be delimited by its own statement. Read with a `func`'s span rule it runs
    # on to the next `{` in the FILE, swallows the sweep declared after it, and every test that so
    # much as names the constant becomes a sweep -- 23 false positives, measured.
    check "a test that names only a braceless \`let\` is NOT named -- the run-on defect stays fixed" \
        $( [[ "$OUT" != *theOneThatOnlyNamesABracelessLet* ]] && print 1 || print 0 )
    check "the fixed-file assertion is NOT named" \
        $( [[ "$OUT" != *theFixedFileAssertionThatWalksNothing* ]] && print 1 || print 0 )
    check "a sweep that only appears inside a string literal is NOT named" \
        $( [[ "$OUT" != *theOneThatOnlyQuotesASweep* ]] && print 1 || print 0 )
    check "the sweep already on the manifest is NOT named" \
        $( [[ "$OUT" != *theOneAlreadyOnTheManifest* ]] && print 1 || print 0 )
    check "the repo path is reported, not the temporary file" \
        $( [[ "$OUT" == *"CadenceTests/Fixture.swift"* ]] && print 1 || print 0 )

    # The corpus is the only thing that can see the neighbour, so withholding it must lose exactly
    # that one finding and keep the other three. A reader that ignored `--corpus` would either name
    # the cross-file sweep here anyway, or have named nothing above.
    OUT6=$(cmd_precheck --no-corpus "$WS/manifest.txt" \
        "CadenceTests/Fixture.swift=$WS/Fixture.swift" 2>&1); RC6=$?
    check "with no corpus the cross-file sweep is NOT named" \
        $( [[ "$OUT6" != *theOneThroughAHelperInAnotherFile* ]] && print 1 || print 0 )
    check "...and the two-hop one still is, so the closure is not the corpus in disguise" \
        $( [[ "$OUT6" == *theOneTwoHopsDown* ]] && print 1 || print 0 )
    check "...and it is still a finding (exit 4)" $(( RC6 == 4 ))

    # And the same source against a manifest that already names every sweep must be silent, which is
    # the only way to tell "it read them" from "it flags whatever it is shown".
    print -rl -- "SweepPrecheckFixtures/theOneAlreadyOnTheManifest" \
        "SweepPrecheckFixtures/theOneInItsOwnBody" \
        "SweepPrecheckFixtures/theOneThroughASameFileHelper" \
        "SweepPrecheckFixtures/theOneTwoHopsDown" \
        "SweepPrecheckFixtures/theOneThroughAHelperInAnotherFile" \
        "SweepPrecheckFixtures/theOneThroughAMultiLineStoredRoot" > "$WS/full.txt"
    OUT2=$(cmd_precheck --corpus "$WS" "$WS/full.txt" \
        "CadenceTests/Fixture.swift=$WS/Fixture.swift" 2>&1); RC2=$?
    check "a manifest that names them all is accepted (exit 0)" $(( RC2 == 0 ))
    check "and it says nothing" $( [[ -z "$OUT2" ]] && print 1 || print 0 )

    # Vacuity, both ends: no needles and an empty manifest must refuse rather than report "clean".
    OUT3=$(CADENCE_SWEEP_NEEDLES="" "$PYTHON_BIN" -c "$PRECHECK_PY" "$WS/manifest.txt" \
        "CadenceTests/Fixture.swift=$WS/Fixture.swift" 2>&1); RC3=$?
    check "no walk needles refuses rather than reporting a clean tree" $(( RC3 == 2 ))
    : > "$WS/empty.txt"
    OUT4=$(cmd_precheck "$WS/empty.txt" "CadenceTests/Fixture.swift=$WS/Fixture.swift" 2>&1); RC4=$?
    check "an empty manifest refuses rather than flagging everything" $(( RC4 == 2 ))
    OUT5=$(cmd_precheck "$WS/manifest.txt" 2>&1); RC5=$?
    check "precheck with no sources refuses" $(( RC5 == 2 ))

    if (( FAILURES )); then
        print -r -- "real-tree-sweep-manifest.sh: precheck-selftest FAILED ($FAILURES check(s))" >&2
        print -r -- "$OUT" >&2
        exit 1
    fi
    print -r -- "real-tree-sweep-manifest.sh: precheck-selftest passed"
    exit 0
fi

# Runs the scan once against whatever $MANIFEST currently holds and populates $REGENERATED and
# $RUN_STATUS. Shared by the normal flow and `selftest` so the corruption below exercises the exact
# same path a real drift does.
run_scan_once() {
    print -r -- "real-tree-sweep-manifest.sh: running the scan (log: $LOG, xcodebuild log: $XCB_LOG)"
    "$ROOT_DIR/scripts/xcb.sh" "$ID" test \
        -scheme Cadence -destination 'platform=macOS' \
        -only-testing:CadenceTests/CadenceTestTargetHygieneTests \
        "${EXTRA_XCB_ARGS[@]}" > "$LOG" 2>&1
    RUN_STATUS=$?

    # The banners are spelled by CadenceRealTreeSweepScan.regeneratedBanner. `awk` rather than
    # `sed -n` so an absent banner is distinguishable from an empty section: no lines out means the
    # scan never printed, which is a failed run, not an empty manifest.
    awk '/^--- BEGIN REGENERATED REAL-TREE SWEEP MANIFEST$/ {capture=1; next}
         /^--- END REGENERATED REAL-TREE SWEEP MANIFEST$/ {capture=0}
         capture {print}' "$XCB_LOG" > "$REGENERATED" 2>/dev/null
}

if [[ "$MODE" == "selftest" ]]; then
    if [[ ! -f "$MANIFEST" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: selftest: no manifest at $MANIFEST" >&2
        exit 2
    fi
    BACKUP="${_tmp_base}cadence-real-tree-sweep-${ID}.manifest-backup"
    cp "$MANIFEST" "$BACKUP"
    # Always put the committed file back, pass or fail -- this must never leave the repo stale.
    trap 'cp "$BACKUP" "$MANIFEST"; rm -f "$BACKUP"' EXIT

    # Deliberately stale: drop the first real (non-comment, non-blank) entry so the scan and the
    # manifest disagree, the same shape as the T-873 repro (a merged-HEAD failure).
    STALE_LINE=$(grep -n '^[^#[:space:]]' "$MANIFEST" | head -1 | cut -d: -f1)
    if [[ -z "$STALE_LINE" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: selftest: found no entry line to remove" >&2
        exit 2
    fi
    REMOVED=$(sed -n "${STALE_LINE}p" "$MANIFEST")
    sed -i '' "${STALE_LINE}d" "$MANIFEST"
    print -r -- "real-tree-sweep-manifest.sh: selftest: staled the manifest (removed \"$REMOVED\")"

    run_scan_once

    if (( RUN_STATUS == 0 )); then
        print -r -- "real-tree-sweep-manifest.sh: selftest FAILED: the run passed over a manifest it should have rejected" >&2
        exit 1
    fi
    if [[ ! -s "$REGENERATED" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: selftest FAILED: a stale manifest produced an empty regenerated body -- T-873 is back; see $XCB_LOG" >&2
        exit 1
    fi
    if ! grep -qF "$REMOVED" "$REGENERATED"; then
        print -r -- "real-tree-sweep-manifest.sh: selftest FAILED: the regenerated body does not contain the entry the stale manifest was missing" >&2
        exit 1
    fi
    print -r -- "real-tree-sweep-manifest.sh: selftest passed: a stale manifest yielded a $(wc -l < "$REGENERATED" | tr -d ' ')-line regenerated body"
    exit 0
fi

run_scan_once

if [[ ! -s "$REGENERATED" ]]; then
    if (( RUN_STATUS == 0 )); then
        print -r -- "real-tree-sweep-manifest.sh: the manifest already matches the scan."
        exit 0
    fi
    print -r -- "real-tree-sweep-manifest.sh: the run failed and printed no manifest; see $XCB_LOG (summary: $LOG)" >&2
    exit 1
fi

print -r -- "real-tree-sweep-manifest.sh: the scan differs from the committed manifest."
diff -u "$MANIFEST" "$REGENERATED"

if [[ "$MODE" != "--write" ]]; then
    print -r -- "real-tree-sweep-manifest.sh: pass --write to apply the difference above."
    exit 1
fi

cp "$REGENERATED" "$MANIFEST"
print -r -- "real-tree-sweep-manifest.sh: wrote $MANIFEST"
