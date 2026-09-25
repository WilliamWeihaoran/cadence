#!/bin/zsh
# Which suite declares a test, read from the source rather than guessed.
#
#   ./scripts/test-suite-index.sh                       # every @Test, as Suite/name
#   ./scripts/test-suite-index.sh theRowStillDraws       # substring match on the name
#   ./scripts/test-suite-index.sh --scope theRowStill    # -only-testing: args for the matches
#   ./scripts/test-suite-index.sh --label SomeSuite      # the string swift-testing prints for it
#   ./scripts/test-suite-index.sh --labels               # TypeName<TAB>label, every suite
#   ./scripts/test-suite-index.sh --test-labels          # funcName<TAB>label ("" if unnamed), every @Test
#   ./scripts/test-suite-index.sh --suite-files          # Suite<TAB>file<TAB>testCount, every suite
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
#
# T-786. `--label`/`--labels` only ever answered that question at the *suite* level
# (`@Suite("...")`), never per `@Test`, so `scripts/mutate.sh`'s classifier had no way to tell "this
# display-named test did not fail" from "this display-named test did not run" -- it could only grep
# for the bareword `Test funcName()` spelling, which a display-named case never prints. `--test-labels`
# is the missing per-test half: `funcName<TAB>label` (empty second column when the case carries no
# `@Test("...")` name), one line per test, so a caller can map a function name from a plan or a
# manifest to the exact quoted string the log will use. `mutate.sh` reads it from its own tree, the
# same way it reads its own `scripts/xcb.sh`, so a `--tree` run sees the labels of its own
# (possibly uncommitted) tests rather than the repository's.

set -uo pipefail
ROOT="${0:A:h:h}"
MODE=list
if [[ "${1:-}" == "--scope" ]]; then MODE=scope; shift
elif [[ "${1:-}" == "--label" ]]; then MODE=label; shift
elif [[ "${1:-}" == "--labels" ]]; then MODE=labels; shift
elif [[ "${1:-}" == "--test-labels" ]]; then MODE=test_labels; shift
elif [[ "${1:-}" == "--suite-files" ]]; then MODE=suite_files; shift
fi
NEEDLE="${1:-}"

python3 - "$ROOT" "$MODE" "$NEEDLE" <<'PY'
import os, re, sys

root, mode, needle = sys.argv[1], sys.argv[2], sys.argv[3]

# T-1338. Swift's own grammar ends a line on any of these, and so does `Character.isNewline`; this
# pass used to end one only on `\n`. That was the second of the two ways these two implementations
# of one rule could disagree character-for-character: a lone `\r` ended a `//` comment on the Swift
# side and did not here, so everything after it on that line read as comment here and as CODE
# there. `\r\n` is one `Character` and two code points, and both of them are in this set, which is
# what makes the two readings agree on it.
NEWLINES = '\n\x0b\x0c\r\x85\u2028\u2029'


def blank(src):
    # Comments and string-literal TEXT to spaces of equal length, newlines kept -- the same rule as
    # `CadenceSourceScan.codeOnly` in `CadenceTests/CadenceSourceScanSupport.swift`. These are two
    # implementations of one rule in two languages; a divergence between them is a new trap, and
    # `CadenceGuardScriptSelftestTests.theTwoBlankingPassesOfOneRuleStillHandleInterpolatedCode`
    # goes red if either side loses the interpolation half.
    #
    # T-1338: "equal length" is a **code point** count on this side and a grapheme-cluster count on
    # the Swift one, so the Swift pass now spells a blanked cluster as one space per scalar rather
    # than one per cluster. See `CadenceSourceScan.blankedSpansAsSpaces`, and
    # `CadenceBlankingPassParityTests` for the fixtures that pin both halves.
    out = list(src)
    n = len(out)

    def wipe(a, b):
        for k in range(a, min(b, n)):
            if out[k] not in NEWLINES:
                out[k] = ' '

    def line_end(i):
        # The index of the first line terminator at or after `i`, or `n`. Swift's `//` comment runs
        # to the end of ITS line, which is not always the next `\n`.
        while i < n and src[i] not in NEWLINES:
            i += 1
        return i

    def raw_hashes(i):
        # The length of the `#` run opening a RAW literal here, or None when the run is something
        # else (`#if`, `#expect(`, `#filePath`). Inside `#"..."#` a `\` is content and the
        # terminator carries the same run of `#`; reading that backslash as an escape is what
        # desynchronised brace depth for `#"photo\"#` -- the masker ran past the closing quote and
        # blanked the rest of the line, the `{` on it included (T-465).
        h = i
        while h < n and src[h] == '#':
            h += 1
        return h - i if h < n and src[h] == '"' else None

    def scan_literal(start, hashes):
        quote_start = start + hashes
        multiline = src[quote_start:quote_start + 3] == '"""'
        quotes = 3 if multiline else 1
        term = '"' * quotes + '#' * hashes
        pos = quote_start + quotes
        wipe(start, pos)
        while pos < n:
            if src.startswith(term, pos):
                close = pos + len(term)
                wipe(pos, close)
                return close
            # A single-line literal cannot span a newline; stopping here keeps an unterminated one
            # from blanking the rest of the file. Any of Swift's line terminators, not only `\n`
            # (T-1338).
            if not multiline and src[pos] in NEWLINES:
                return pos
            if src[pos] == '\\' and pos + 1 + hashes < n and src.startswith('#' * hashes, pos + 1):
                escaped = pos + 1 + hashes
                if src[escaped] == '(':
                    # T-1328. An interpolation holds a real expression, which can hold literals of
                    # its own -- so it is PARSED to find where this literal ends, then blanked
                    # whole. Reading the whole literal with one "next unescaped quote" loop instead
                    # ended `"tags: [\(names.map { "\"\($0)\"" }.joined(separator: ", "))]"` at the
                    # INNER literal's opening quote, blanking the closure's `{` and keeping its `}`
                    # -- one brace short for the rest of the file, so every `@Test` below it was
                    # reported as `<file scope>` and `xcb.sh` refused its suite as UNKNOWN-SUITE.
                    # Blanking the interpolation keeps brace depth right too: a closure inside one
                    # contributes its `{` and `}` as a matched pair and both go.
                    terminator = scan_code(escaped + 1, True)
                    close = min(terminator + 1, n)
                    wipe(pos, close)
                    pos = close
                    continue
                wipe(pos, escaped + 1)
                pos = escaped + 1
                continue
            wipe(pos, pos + 1)
            pos += 1
        return n

    def scan_code(start, stop_at_close_paren):
        # With stop_at_close_paren, returns the index OF the first `)` that closes no `(` of its
        # own -- the end of the interpolation that called it -- for the caller to blank.
        i = start
        parens = 0
        while i < n:
            if src[i] == '#':
                hashes = raw_hashes(i)
                if hashes is not None:
                    i = scan_literal(i, hashes)
                    continue
            if src[i] == '"':
                i = scan_literal(i, 0)
                continue
            if src[i:i + 2] == '//':
                j = line_end(i)
                wipe(i, j); i = j; continue
            if src[i:i + 2] == '/*':
                j = src.find('*/', i + 2)
                j = n if j < 0 else j + 2
                wipe(i, j); i = j; continue
            # Counted after those branches, so a parenthesis inside a literal or a comment is never
            # seen: each branch consumes its whole span before this reads it.
            if stop_at_close_paren:
                if src[i] == '(':
                    parens += 1
                elif src[i] == ')':
                    if parens == 0:
                        return i
                    parens -= 1
            i += 1
        return n

    scan_code(0, False)
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

if mode == 'suite_files':
    # Suite<TAB>declaring file<TAB>test count, one line per suite. The caller that needs this is
    # `xcb.sh`'s pre-build resolver (T-1076): to answer "is this `-only-testing:` name real, and
    # what ELSE lives in the file that declares it" it needs the file and the count, which no
    # existing mode carries -- `--labels` has neither, and `list` has the file but only per test,
    # 4,499 lines to be re-aggregated by the caller. Emitting it here keeps ONE parser of Swift
    # source in this repository rather than a second, weaker one written in zsh.
    per_suite = {}
    for suite, name, filename, _label in rows:
        if suite not in per_suite:
            per_suite[suite] = [filename, 0]
        per_suite[suite][1] += 1
    for suite in sorted(per_suite):
        filename, count = per_suite[suite]
        print(f'{suite}\t{filename}\t{count}')
    sys.exit(0)

if mode in ('label', 'labels', 'test_labels'):
    if mode == 'label':
        print(suite_label.get(needle, needle) or needle)
    elif mode == 'labels':
        for suite in sorted(suite_label):
            if suite == '<file scope>':
                continue
            print(f'{suite}\t{suite_label[suite] or suite}')
    else:
        # name<TAB>label, every @Test, unsorted-suite-agnostic: test names are unique across the
        # target (CadenceTestTargetHygieneTests enforces it), so a bare function name is enough for
        # a caller to key off of without also carrying its suite.
        for _suite, name, _filename, test_label in sorted((r[0], r[1], r[2], r[3]) for r in rows):
            print(f'{name}\t{test_label or ""}')
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
