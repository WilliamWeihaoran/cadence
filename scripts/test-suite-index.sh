#!/bin/zsh
# Which suite declares a test, read from the source rather than guessed.
#
#   ./scripts/test-suite-index.sh                       # every @Test, as Suite/name
#   ./scripts/test-suite-index.sh theRowStillDraws       # substring match on the name
#   ./scripts/test-suite-index.sh --scope theRowStill    # -only-testing: args for the matches
#   ./scripts/test-suite-index.sh --label SomeSuite      # the string swift-testing prints for it
#   ./scripts/test-suite-index.sh --labels               # TypeName<TAB>label, every suite
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
# to the top-level type whose *braces enclose it* — a nested `private struct Store` fixture is not
# the suite its neighbours are in, and a test appended past the last suite's closing brace is
# `<file scope>` rather than a member of the suite it just escaped (T-465). That second case is the
# one this script used to answer wrongly, which is worse than not answering: it named the suite the
# author meant for the one input where the author is wrong.
# `CadenceTestTargetHygieneTests.noTestInTheTargetIsDeclaredOutsideEverySuite` now fails on any
# such test, so the `<file scope>` bucket should stay empty. Same rules as the Swift parser in
# `CadenceTests/CadenceTestTargetHygieneTests.swift`; if they ever disagree, the Swift one is the
# one a test can fail on.
#
# T-667. `-only-testing:CadenceTests/<Suite>` **does** select and run a suite whose `@Suite` and
# every one of its `@Test`s carry a display name -- measured directly against `ListDetailPageTests`
# (9/9 passed) and `MarkdownTableMobileEditingTests` (27/27 passed) from real logs in this
# repository's own scratch history, and the mechanism is symmetric for `RootModalKeyDispositionTests`.
# The "0 tests" the ticket measured was never a selection failure: swift-testing's console reporter
# prints `✔ Test "<display name>" passed` for a named case instead of `✔ Test funcName() passed`,
# and `scripts/xcb.sh`'s own `TEST_RESULT_PATTERN` (before this change) only matched the bareword
# form -- so the counting guard read a real, fully green run as zero. That is the actual bug, fixed
# in `xcb.sh` alongside this file, and it is a bigger blind spot than these three suites: it is
# silent for *any* `@Test("...")` case in the target (52 of them, in 5 files, at last count).
# What genuinely is true, and worth this script saying, is the trap that produced the "0 tests"
# reading in the first place: `grep '✔ Test <funcName>()'` -- the exact spelling the runbook tells
# you to use to confirm a mutation was killed -- reads 0 forever against a display-named case,
# passing or failing, because the log never spells the function name at all once a display name is
# given. `--label`/`--labels` answer "what string will the log actually use for this suite", and
# `list` marks a display-named case with the quoted text to grep for instead.

set -uo pipefail
ROOT="${0:A:h:h}"
MODE=list
if [[ "${1:-}" == "--scope" ]]; then MODE=scope; shift
elif [[ "${1:-}" == "--label" ]]; then MODE=label; shift
elif [[ "${1:-}" == "--labels" ]]; then MODE=labels; shift
fi
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
        if src[i] == '#':
            h = i
            while h < n and src[h] == '#':
                h += 1
            hashes = h - i
            if h < n and src[h] == '"':
                # A raw string: `\` is content, and the terminator carries the same run of `#`.
                # Reading that backslash as an escape is what desynchronised brace depth for
                # `#"photo\"#` -- the masker ran past the closing quote and blanked the rest of
                # the line, the `{` on it included (T-465).
                multiline = src[h:h+3] == '"""'
                quotes = 3 if multiline else 1
                term = '"' * quotes + '#' * hashes
                j = src.find(term, h + quotes)
                j = n if j < 0 else j + len(term)
                if not multiline:
                    nl = src.find('\n', h)
                    if 0 <= nl < j:
                        j = nl
                wipe(i, j); i = j; continue
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
SUITE_ATTR = re.compile(r'@Suite\b')
LEADING_STRING = re.compile(r'\(\s*"([^"]*)"')

def leading_string(raw, pos, keyword):
    # raw[pos:] starts with the attribute's own '@'. A display name, when given, is always the
    # leading positional argument, so this only has to find the attribute's own parens (stopping at
    # a bare newline or the next '@' if there are none -- i.e. no parens on this attribute at all)
    # and ask whether the first token inside is a quoted string, without parsing the full argument
    # list (traits like `.serialized` or `arguments:` are not display names).
    i = pos + len(keyword)
    limit = min(len(raw), i + 300)
    j = i
    while j < limit and raw[j] not in '(@\n':
        j += 1
    if j >= limit or raw[j] != '(':
        return None
    m = LEADING_STRING.match(raw, j, limit)
    return m.group(1) if m else None

rows = []            # (suite, testname, filename, test_label_or_None)
suite_label = {}      # suite name -> display name string, or None if unnamed

for dirpath, _, filenames in os.walk(os.path.join(root, 'CadenceTests')):
    for filename in sorted(filenames):
        if not filename.endswith('.swift'):
            continue
        path = os.path.join(dirpath, filename)
        raw = open(path, encoding='utf-8').read()
        code = blank(raw)
        depth, depth_at = 0, []
        for ch in code:
            depth_at.append(depth)
            if ch == '{': depth += 1
            elif ch == '}': depth -= 1
        suite_attr_positions = [m.start() for m in SUITE_ATTR.finditer(code) if depth_at[m.start()] == 0]
        types = []
        for m in TYPE.finditer(code):
            if depth_at[m.start()] != 0:
                continue
            open_brace = code.find('{', m.end())
            if open_brace < 0:
                continue
            close = len(code)
            for k in range(open_brace + 1, len(code)):
                # depth_at[k] is the depth *before* code[k], so the brace closing this body is the
                # first '}' seen back at depth 1.
                if code[k] == '}' and depth_at[k] == 1:
                    close = k
                    break
            types.append((m.start(), open_brace, close, m.group(1)))
        prev_close = 0
        for start, open_brace, close, name in types:
            attr_pos = max((p for p in suite_attr_positions if prev_close <= p < start), default=None)
            suite_label[name] = leading_string(raw, attr_pos, '@Suite') if attr_pos is not None else None
            prev_close = close
        for m in TEST.finditer(code):
            suite = None
            for start, open_brace, close, name in types:
                if open_brace < m.start() < close: suite = name
            test_label = leading_string(raw, m.start(), '@Test')
            rows.append((suite or '<file scope>', m.group(1), filename, test_label))
            suite_label.setdefault(suite or '<file scope>', None)

if mode in ('label', 'labels'):
    if mode == 'label':
        print(suite_label.get(needle, needle) or needle)
    else:
        for suite in sorted(suite_label):
            if suite == '<file scope>':
                continue
            print(f'{suite}\t{suite_label[suite] or suite}')
    sys.exit(0)

rows = [r for r in rows if not needle or needle in r[1]]

if mode == 'scope':
    for suite in sorted({r[0] for r in rows}):
        print(f'-only-testing:CadenceTests/{suite}', end=' ')
    print()
    # T-667: this identifier genuinely selects the suite even when it and every one of its cases
    # carry a display name -- the note is so a caller does not go on to verify with the wrong
    # spelling, not a refusal.
    named = sorted({r[0] for r in rows if suite_label.get(r[0])})
    for suite in named:
        print(
            f'note: {suite} runs as Suite "{suite_label[suite]}" -- grep results by that quoted '
            f'text or by `scripts/xcb.sh`\'s own test-result-lines count, not by function name.',
            file=sys.stderr,
        )
else:
    for suite, name, filename, test_label in sorted((r[0], r[1], r[2], r[3]) for r in rows):
        tag = f'  [logs as "{test_label}", not {name}() -- T-667]' if test_label else ''
        print(f'{suite}/{name}  ({filename}){tag}')
    named = sum(1 for r in rows if r[3])
    print(f'-- {len(rows)} test(s), {named} logging under a display name instead of a function name', file=sys.stderr)
PY
