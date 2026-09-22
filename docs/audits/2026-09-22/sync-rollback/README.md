# Sync Coverage And Rollback Research

```text
Tree read: d819a4c
Dirty files: 1 at start: CadenceTests/StartupMaintenancePerfProbeTests.swift (untracked)
Source: committed agent-scratch snapshot; the in-progress probe was not read or used
Mode: read-only research; only request answers and these audit artifacts written
No app/test builds, tests, simulator, device changes, or CloudKit account operations
```

- [R64: sync coverage](coverage.md): all 23 model types are present; template overrides are local
  user content; several other exclusions are intentional. Source eligibility is not device proof.
- [Complete model/field inventory](model-fields.md): 256 stored declarations, including all 62
  relationship endpoints. [Read-only inventory command](model_inventory.rb) emits exact defaults.
- [R65: rollback](rollback.md): restoration is documented, a 26-to-27 semantic change is not
  established by the reviewed notes, and edit-free source is not proof of immediate UI recovery.

Highest-value actions: defer cascade notification cancellations until commit success; strengthen
the refused-detach UI assertion; resolve T-1336 using operation-level failure guarantees; decide
whether custom templates/work hours should sync. Existing model membership needs no patch.

MEASURED-SOURCE means the code/structure was inspected. MEASURED-PROBE means the command ran.
DOCUMENTED means an Apple primary source supports it. REASONED means a consequence or proposal,
not a reproduced device incident. No runtime CloudKit or cross-toolchain result is claimed.

R61's broader commit matrix and R57-R60 remain separate work. R62 overlaps another agent's active
startup measurement and was not duplicated. This batch prioritizes the newer owner questions R64/R65.

Closing source check: HEAD advanced to `b358aa3`; only `docs/TODO.md` changed relative to the audit
snapshot. T-1329 is now closed with that agent's measurements and T-1341 tracks a migration-pass
follow-up. Product references above still match the committed tree. Other agents' working-tree
changes were left untouched and are not credited as part of this audit.
