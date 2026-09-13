# Image Import Transaction Ownership

```text
Tree read: 9b31280
Dirty entries at capture: 24 (git status --short; untracked directories count as one)
Source examined: clean git archive of 9b31280; dirty work excluded
Mode: source-only audit; no app launches, builds, or tests
```

## IM-1: Photo Loading Suspends While New Asset Rows Are Pending

**P2 / async persistence interleaving risk / inferred, not reproduced. Extends T-629's image commit boundary, rather than re-reporting its fixed swallowed save.**

**Can this happen today?** On iOS/iPadOS, select at least two photos. Once the first loads, its asset is inserted into the shared context; loading the next photo can suspend. Other main-actor work can run during that suspension, including a save or a failed-delete rollback using the same model context. The picker import task is not stored or cancelled when the editor disappears.

**Exact spots:**
- [iOSMarkdownEditingSurface.swift:124](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSMarkdownEditingSurface.swift:124): an unstructured Task launches each selection import.
- [iOSMarkdownEditingSurface.swift:374](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSMarkdownEditingSurface.swift:374): loop loads each item asynchronously and immediately creates its asset.
- [MarkdownImageAssetService.swift:408](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/MarkdownImageAssetService.swift:408): data creator delegates to the image creator, which inserts a model into the supplied context.
- [iOSMarkdownEditingSurface.swift:390](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSMarkdownEditingSurface.swift:390): commit happens only after all loads have finished.
- [iOSMarkdownEditingSurface.swift:87](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSMarkdownEditingSurface.swift:87): disappear commits the draft; it does not cancel the photo task.
- [CadencePendingChangePersistence.swift:38](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadencePendingChangePersistence.swift:38): commitInsert saves/undoes the supplied models but is not an isolation boundary around previous awaits.

**Inferred risk:** an unrelated save can persist an asset before this operation finishes or inserts its markdown. An unrelated rollback can discard pending asset rows while the import retains references to them. The final commit does not recreate discarded rows. The exact SwiftData behavior of those retained model objects must be tested before claiming a broken reference or a crash; neither was observed here.

The simpler confirmed source fact is the ownership mismatch: the function treats all accumulated assets as its still-pending insertion batch, but yields control between those insertions. T-629's synchronous commit tests do not establish that assumption across suspension points.

## 30-Second Confirmation

```sh
git show 9b31280:Cadence/iOS/iOSMarkdownEditingSurface.swift | sed -n '374,405p'
git show 9b31280:Cadence/Services/MarkdownImageAssetService.swift | sed -n '386,417p'
git show 9b31280:Cadence/Shared/CadencePendingChangePersistence.swift | sed -n '38,51p'
```
Source inspection only; this is not an executed concurrency reproduction.

## Suggested Fix

Load/decode into non-model payloads first. Once all awaited work finishes, validate that this import still belongs to the active editor/job, then perform model insertion and its commit in one uninterrupted main-actor phase. Only after successful commit should markdown be inserted. Use the existing creator and commit helper; do not alter the image schema or change global SwiftData rollback semantics.

Give the photo import a task handle or generation/owner token. Cancellation or replacement should stop before creating persistent rows. Treat CancellationError as cancellation, not a decoder refusal; the current `try? await` obscures that distinction. Define what happens when the user intentionally leaves an editor during a download before enforcing a late-result policy.

**Existing correct pattern:** the adjacent synchronous paste path at [iOSMarkdownEditingSurface.swift:426](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSMarkdownEditingSurface.swift:426) constructs its asset batch and commits it without yielding. Preserve its error and partial-decoding notices.

## Acceptance Checks, Not Run

- Fake loader returns photo A, then suspends photo B: no new model rows should exist before payload loading finishes.
- While B is suspended, issue an unrelated save and an unrelated failed-delete rollback; neither controls photo A's persistence.
- Complete both loads: committed rows and inserted references agree.
- Fail the batch commit: no references are inserted and no new rows survive.
- Cancel or replace the job while a load is suspended: no late model writes or clearing of a newer selection.
- Keep partial decoder failure reporting and the eight-photo picker limit.

## Dedup and Coverage

T-629 pins failed image saves; T-649 pins partial decoding notices; T-620 restricts image garbage collection to explicit deletion candidates. No ticket for suspension between insertions was found in the searched TODO/hand-off docs.

[CadenceMarkdownImageCommitSurfaceTests.swift:104](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift:104) tests refusal cleanup, and its iOS wiring cases check commit-before-markdown. These are useful checks of the final commit. They do not inject an interleaving between two photo loads.

## Looks Solid

- Asset rows are committed before markdown on normal success; refused commits do not immediately emit references.
- Both normalization implementations cap the long edge before encoding at [MarkdownImageAssetService.swift:507](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/MarkdownImageAssetService.swift:507) and [line 542](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/MarkdownImageAssetService.swift:542). Do not file a nonexistent uncapped-output defect.
- [CadenceListDeleteHelpers.swift:282](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceListDeleteHelpers.swift:282) limits garbage collection to candidate IDs and skips collection on failed reference reads. Do not replace it with a full-store orphan sweep to clean up this import risk.

## Patch Order

Add a suspendable loader discriminator, stage payloads before model creation, then pin job ownership/cancellation. Keep image rendering and sibling toolbar/layout changes out of this patch.
