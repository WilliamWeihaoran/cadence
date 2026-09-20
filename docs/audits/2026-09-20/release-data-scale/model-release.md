# R53: releasing an additive CloudKit model

```text
Tree read: 1857938
Dirty files: 0 at source snapshot
Production console / deployed schema: not inspected
Old/new client experiments: not run
```

## The decision now

**MEASURED-SOURCE:** both models have landed, not one “being added now”:
[CadenceSchema.swift:26](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceSchema.swift:26)
includes `SidebarLayoutPreference` and `LookPreference` in the primary schema. Look landed in
`58c75ef`. The release-readiness document says both types still owe deployment; that is repository
state, **not** an observation of the owner's console.

**REASONED recommendation:** keep the model in the schema, hold the dependent release, and have
the owner verify/deploy its additive schema first. Do not replace this with a code-level feature
flag that removes a model from an already-used local store. Existing T-1290/T-1294 own this work;
do not file another missing-deploy ticket.

## Do not conflate two independent axes

“Pre-deploy client” and “post-deploy client” are misleading names. A deployment changes the
**server environment's schema**, not the installed client's model. An old binary remains old
after deployment; a new binary can run before deployment and fail to mirror.

| Client / server | Expected boundary |
| --- | --- |
| Old client, old Production schema | Baseline behavior for old entities/fields. |
| New client, missing Production additions | Local model can open/create rows, but exports/mirroring can fail. A feature reading local defaults does not prove the store syncs. |
| Old client, expanded schema, no new rows yet | Deployment adds schema, not data. No novel record needs interpreting yet. |
| Old client, expanded schema, new rows present | Its local model cannot expose a new entity. Compatibility of the rest of the store must be tested on that old binary. |
| New client, expanded schema, old rows present | Must tolerate missing newly added values and absent singleton rows; defaults/fallbacks handle the transition. |

**DOCUMENTED:** Production deployment copies record types, fields and indexes, not records;
schema updates are additive. Apple instructs developers to test Development, deploy, then test
Production before publishing.
[Apple deployment guide](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema).
**REASONED:** a schema-first/no-writer window is therefore the right sequence, not a dangerous
intermediate data migration. It does not waive the need to test later mixed-client writes.

## Release sequence

1. **MEASURED starting point:** record the exact build/tree, container identifier, both model
   additions, and the oldest supported installed build. `PersistenceController.swift:198` uses
   the private `iCloud.com.haoranwei.Cadence` database. Take an independent export before any
   experiment involving real data; use disposable accounts/stores for failure testing.
2. **DOCUMENTED / REASONED application:** initialize the complete final model in Development,
   inspect all resulting types/fields/relationships, and test old-to-new local-store upgrade.
   Merely launching without ever producing a new row is not verification that every required
   field reached the cloud schema. Apple's Core Data schema initializer generates temporary
   instances for this purpose; Cadence uses SwiftData, so verify its generated Development schema
   rather than pretending the app exposes that Core Data initializer.
   [Apple CloudKit model preparation](https://developer.apple.com/documentation/CoreData/creating-a-core-data-model-for-cloudkit?changes=_6_5%2C_6_5).
3. **REASONED mixed-version gate:** in an expendable environment, test an old device and new
   device together: old data imports into new; new preferences exist only on the new surface;
   both directions still sync ordinary tasks/notes; updating the old device preserves the new
   values. Test offline old-client edits of shared entities. Do not test “old client” by opening
   an already-upgraded local SQLite file with an old executable: that is a separate downgrade
   migration scenario.
4. **DOCUMENTED owner action:** select the correct container in CloudKit Console, review the
   complete pending diff and deploy it to Production. Include both new types **and their fields**.
   Verify the resulting Production schema. Do not reset Development: this repository reports real
   development-signed data there, and reset deletes records. Deployment itself does not move that
   Development data to TestFlight's Production database.
   [Apple deployment procedure](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema).
5. **REASONED release gate:** use the exact distribution/TestFlight artifact to check cloud writes
   and reads across devices, including an old installed version. Inspect Console logs for schema
   and mirroring errors, then distribute. A local unit-test pass or a successful app launch is not
   this gate. There is no claimed fixed waiting period; observe convergence instead.

## What is established about older clients?

**DOCUMENTED:** Apple explicitly accounts for old binaries that do not know new fields/types.
Its recommended additive-field strategy lets older clients access records but not the new fields.
It also warns to keep maintaining old fields that old clients still use.
[Apple schema evolution, CloudKit section](https://developer.apple.com/videos/play/wwdc2022/10120/).

**REASONED, not a discovered implementation guarantee:** an old Cadence `Schema` has no model to
return for `LookPreference`; it cannot display/edit that model merely because the server has it.
The official material reviewed does **not** specify the exact unknown-entity import/delegate
behavior for Cadence's current SwiftData/OS combination. I cannot certify “it silently skips the
new type and everything else always syncs.” That sentence requires the mixed-binary experiment
above, ideally with logs. The missing-server-schema failure in R49 is not evidence of the reverse
case (extra server types), and raw `CKQuery` behavior is not proof about SwiftData mirroring.

**MEASURED-SOURCE:** the new preference types have defaults and local preference mirrors; absence
of their rows is expected during first sync. **REASONED:** retain that fallback while verifying
that old shared-content records remain readable. Field optionality/defaults solve missing local
values; they do not create a missing Production field.

## Why removing an already-used model is not a feature flag

**DOCUMENTED:** Core Data model changes require compatible local migration; an incompatible model
can prevent opening the store. Local lightweight migration supports entity removal, but CloudKit
Production does not allow removing deployed types/fields. Local migration does not migrate the
server schema. [Apple schema evolution](https://developer.apple.com/videos/play/wwdc2022/10120/).

**REASONED concrete failure alternatives for Cadence:** removing a type changes the local model,
not just whether a view appears. The store may fail to open and Cadence may present its recovery
store (`PersistenceController.swift:89,102,204`); or an accepted removal migration discards the
removed entity's local representation/data. In either case its queries/export/reset paths can
no longer manage those rows. A later re-add is not a guaranteed undo: unsynced local rows have no
cloud copy, and remirroring behavior is not a backup contract. **Not measured:** that removal
necessarily sends CloudKit tombstones or always erases every server copy. The prior unconditional
“that destroys data” wording should be narrowed to this migration/data-access risk.

Suggested contributor rule, **not applied** to `Models/AGENTS.md`:

```text
Do not remove a previously used persistent type from CadenceSchema to disable a feature or
work around missing CloudKit deployment. Gate its UI/writes while retaining schema membership.
Retiring persisted data requires an explicit, tested local migration and cloud compatibility
plan, an independent recoverable export, and mixed-version verification. Deploy every new
CloudKit type or field before distributing the build that requires it.
```

## Would an optional property be safer?

**DOCUMENTED:** adding fields to an existing deployed type is a supported evolution strategy;
older clients still know the entity and can access its records without understanding every field.
[Apple model-update strategies](https://developer.apple.com/documentation/CoreData/creating-a-core-data-model-for-cloudkit?changes=_6_5%2C_6_5).
**REASONED tradeoff:** this can reduce unknown-entity compatibility surface, but still requires a
Production deploy and introduces ownership/conflict coupling to the chosen existing record.
Attaching global settings to an arbitrary task or context is not inherently safer. A genuinely
existing singleton settings record would be a more natural host; do not create a fake owner just
to avoid a new type. Device-local defaults avoid this schema change but do not deliver cross-device
sync. Packing new settings into an already deployed string still requires versioned decoding and
conflict semantics, not an unreviewed shortcut.

**DOCUMENTED:** missing Production fields can prevent the mirroring delegate from initializing
and abort store exports. Thus a new optional field carries the same deployment-mismatch risk one
level down. [Apple TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer?changes=_9).

## Quick check and what looks solid

```sh
git show --stat 58c75ef
rg -n 'SidebarLayoutPreference.self|LookPreference.self' Cadence/Services/CadenceSchema.swift
rg -n 'cloudKitDatabase|makeRecoveryContainer' Cadence/Services/PersistenceController.swift
```

**MEASURED-SOURCE:** both preference types participate in export/import/reset; their new archive
tables are optional for older-file decoding, and production configuration stays in the shared
container. **REASONED:** keep those additions together with the schema change. The remaining
release evidence is server deployment and mixed-client behavior, not another local mock asserting
that a model can be inserted.
