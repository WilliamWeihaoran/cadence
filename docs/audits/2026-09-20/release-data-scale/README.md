# R51-R54: release, data safety, and scale

```text
Audit date: 2026-09-20
Tree read: 1857938
Dirty files: 0 at source snapshot
Method: source/history inspection, lexical inventory, official Apple documentation
Not run: app builds, Cadence tests, app/simulator, signed-archive inspection,
CloudKit account operations, destructive store operations, performance benchmarks
User's store: not opened; 264 records is the request's figure, not a measurement here
Closing HEAD: 7f85491; only CODEX_REQUESTS.md changed upstream since the source snapshot
```

R55 (round-five icon concepts) arrived while these four research reports were being completed.
It is outside this audit batch and remains unanswered here; its request text was preserved.

This is a bounded review of the four requests, not a certification that the whole repository
cannot lose data or that a 10,000-record store performs acceptably. Source references describe
the pinned tree. `MEASURED-SOURCE` means a command verified code or test text, **not** that the
behavior was reproduced. `DOCUMENTED` identifies Apple's published behavior. `REASONED` marks
an implication or proposal. Tests mentioned below were inspected, not run.

| Request | Report | Highest-value outcome |
| --- | --- | --- |
| R51 | [Privacy and entitlements](privacy.md) | Shared UserDefaults declarations are missing, and tests pin the wrong declarations. Check the iOS APNs entitlement in the signed product. |
| R52 | [Data loss](data-loss.md) | Context deletion crosses a task's container boundary through its goal. Post-commit reset cleanup can still throw an undifferentiated failure. |
| R53 | [Model release](model-release.md) | Deploy additive schema before the dependent build; distinguish server deployment from local model migration and older-client behavior. |
| R54 | [Scale](scale.md) | Startup resolves tags by fetching the tag table once per tagged note. Archive work is synchronous on UI paths. No measured failure threshold. |

## Suggested order

1. Before distribution, fix and verify the privacy declarations and signed entitlements; deploy
   the required CloudKit schema. These are release checks, not another broad refactor.
2. Add a cross-context deletion fixture and settle the ownership rule; preserve externally filed
   tasks unless the product deliberately intends the broader deletion.
3. Finish the reset's typed partial-outcome handling. Reuse the importer's committed-with-warning
   pattern rather than pretending disk, Keychain and SwiftData share a transaction.
4. Pin cross-version archive compatibility, including partial reads and fields added to known
   tables. Keep independent exports before destructive/replacement work.
5. Measure startup tag resolution, archive operations and widget graph traversal using disposable
   fixtures before changing fetch/sort contracts.

## Duplicate check

Read `docs/TODO.md` before filing: T-1290/T-1294 cover schema deployment; T-1100 covers failed
restore preservation; T-1101/T-1102 cover credential/reset rollback; T-291 covers cascade rollback;
T-1111 covers committed import/fold failure; T-623 is a **parked decision**, not an unimplemented
orphan fix; T-1118 scopes deletion copy to this device; X-09 records MCP pagination constraints.
The earlier [privacy-reset audit](../../2026-09-05/batch-02/privacy-reset.md) already suggested a
whole-reset partial result. The remaining filesystem-cleanup case extends that advice, rather
than reopening the fixed swallowed-Keychain bug. No new TODO entries were made.

## Cheap verification

From the repository root:

```sh
ruby docs/audits/2026-09-20/release-data-scale/inventory.rb
git show 1857938:Cadence/Services/CadenceSchema.swift
```

The inventory excludes full-line `//` comments in its second count. It is deliberately a lexical
check, not a claim about conditional compilation, runtime reachability, dynamic library symbols,
or SwiftData's internal query execution.
