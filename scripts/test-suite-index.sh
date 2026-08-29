#!/bin/zsh
# Which suite declares a test, read from the source rather than guessed.
#
#   ./scripts/test-suite-index.sh                       # every @Test, as Suite/name
#   ./scripts/test-suite-index.sh theRowStillDraws       # substring match on the name
#   ./scripts/test-suite-index.sh --scope theRowStill    # -only-testing: args for the matches
#
# This exists for two of the five ways a test has looked like a guard while guaranteeing nothing
# (docs/TODO.md T-161):
#
#   - Tests appended to the *wrong* `struct` are invisible to `-only-testing:CadenceTests/ThatSuite`
#     while passing in a full run, so every mutation against them reads as a survivor. Ask this
#     script where your new test actually landed before you scope a run to where you meant to put
#     it.
#   - A name shared with another suite makes `grep '✔ Test <name>()'` ambiguous. The uniqueness of
#     names is enforced by CadenceTestTargetHygieneTests; this is how you see the collision.
#
# It reads `@Test ... func name` after blanking comments and string literals, and attributes each
# to the nearest *top-level* type declaration — a nested `private struct Store` fixture is not the
# suite its neighbours are in. Same rules as the Swift parser in
# `CadenceTests/CadenceTestTargetHygieneTests.swift`; if they ever disagree, the Swift one is the
# one a test can fail on.

set -uo pipefail
ROOT="${0:A:h:h}"
MODE=list
if [[ "${1:-}" == "--scope" ]]; then MODE=scope; shift; fi
NEEDLE="${1:-}"

python3 - "$ROOT" "$MODE" "$NEEDLE" <<'PY'
import os, re, sys

root, mode, needle = sys.argv[1], sys.argv[2], sys.argv[3]

def blank(src):
    out = list(src)
    n = len(out)
    def wipe(a, b):
        for k in range(a, min(b, n)):
            if out[k] != '\n':
                out[k] = ' '
    i = 0
    while i < n:
        if src[i] == '"':
            if src[i:i+3] == '"""':
                j = src.find('"""', i + 3)
                j = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n and src[j] not in '"\n':
                    if src[j] == '\\':
                        j += 1
                    j += 1
                j = min(j + 1, n)
            wipe(i, j); i = j; continue
        if src[i:i+2] == '//':
            j = src.find('\n', i)
            j = n if j < 0 else j
            wipe(i, j); i = j; continue
        if src[i:i+2] == '/*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            wipe(i, j); i = j; continue
        i += 1
    return ''.join(out)

TYPE = re.compile(r'\b(?:struct|final class|class|actor|enum)\s+([A-Za-z0-9_]+)')
TEST = re.compile(r'@Test\b[\s\S]*?\bfunc\s+([A-Za-z0-9_]+)')

rows = []
for dirpath, _, filenames in os.walk(os.path.join(root, 'CadenceTests')):
    for filename in sorted(filenames):
        if not filename.endswith('.swift'):
            continue
        path = os.path.join(dirpath, filename)
        code = blank(open(path, encoding='utf-8').read())
        depth, depth_at = 0, []
        for ch in code:
            depth_at.append(depth)
            if ch == '{': depth += 1
            elif ch == '}': depth -= 1
        types = [(m.start(), m.group(1)) for m in TYPE.finditer(code) if depth_at[m.start()] == 0]
        for m in TEST.finditer(code):
            suite = None
            for loc, name in types:
                if loc < m.start(): suite = name
                else: break
            rows.append((suite or '<file scope>', m.group(1), filename))

rows = [r for r in rows if not needle or needle in r[1]]
if mode == 'scope':
    for suite in sorted({r[0] for r in rows}):
        print(f'-only-testing:CadenceTests/{suite}', end=' ')
    print()
else:
    for suite, name, filename in sorted(rows):
        print(f'{suite}/{name}  ({filename})')
    print(f'-- {len(rows)} test(s)', file=sys.stderr)
PY
