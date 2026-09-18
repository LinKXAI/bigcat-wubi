# UserDB Portability P3

P3 consumes the validated UserDB Portability Package V2 format and performs
merge-style recovery through librime 1.13.1. It adds no installer behavior, GUI,
physical database rename, automatic cross-database merge, or migration.

The implementation is guarded by
[Public Baseline V1](userdb-portability-acceptance-baseline.md), which validates
the current public files without depending on private Git history.

## Restore authority

The only native restore authority is:

```text
librime.levers.restore_user_dict(validated_extracted_snapshot_file)
```

`/sync` is not a clean-machine restore mechanism. Librime's `SynchronizeAll`
enumerates existing UserDBs, while `restore_user_dict` reads the snapshot
identity, opens or creates the physical destination database, and runs the
official merge implementation.

ABI and behavior are pinned to:

- [`rime_api.h` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime_api.h);
- [`rime_levers_api.h` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime_levers_api.h);
- [`UserDictManager::Restore` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime/lever/user_dict_manager.cc); and
- [`UserDbMerger` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime/dict/user_db.cc).

The adapter supports the pinned Windows x64 ABI only. It uses self-versioned
`data_size` plus member-offset availability, non-null function pointers,
32-bit librime `Bool`, C calling convention delegates, and explicit UTF-8
buffers whose lifetime covers each call. Any librime version other than
`1.13.1` fails closed with `P3_LIBRIME_MUTATION_UNVERIFIED`.

## Preflight before mutation

The enforced order is:

```text
ZIP validation
-> manifest validation
-> isolated extraction
-> snapshot SHA-256 and size validation
-> strict snapshot parse
-> Public Baseline V1 identity authorization
-> target-state detection and restore plan
-> maintenance window
-> pre-restore safety backup when applicable
-> native restore
```

Package V2 must contain exactly:

```text
manifest.json
snapshots/<db_name>.userdb.txt
```

Preflight rejects absolute, traversal, alternate-separator, ADS/device,
duplicate or case-colliding paths; links and reparse payloads; extra, missing,
or oversized entries; truncated or unreadable ZIP data; malformed JSON or
UTF-8; unsupported package versions; policy changes; and every manifest,
snapshot, filename, hash, count, tick, type, or physical-identity mismatch.

The snapshot is extracted only to a random controlled temporary directory. It
is made read-only, then held through the native call with a read-only handle
that denies write and delete sharing. The ZIP path, user-supplied ZIP path, and
sync history are never passed to `restore_user_dict`.

Immediately before native initialization and again immediately before the
restore call, P3 rechecks the controlled-root path, every reparse-point bit,
byte length, SHA-256, pinned P1 structure, physical identity, entry counts, and
tick range while that handle is held. Drift fails with
`P3_RESTORE_SOURCE_CHANGED` and the restore function is not called.

Only these separate physical identities are authorized:

| Logical role | Schema | Physical DB |
| --- | --- | --- |
| `PureWubi` | `damao_wubi_alpha03` | `damao_wubi_alpha03` |
| `PureWubi` | `damao_wubi` | `damao_wubi` |

Pinyin remains excluded by default. Unknown databases are rejected. P3 never
renames or automatically merges these physical databases.

## Restore is merge-style mutation

Restore is not transactional replacement. Librime creates a temporary UserDB
from the snapshot and streams its entries through `UserDbMerger` into the
destination. For each source key, librime 1.13.1:

1. normalizes source and destination `d` values to their database ticks;
2. selects source `c` only when `abs(source.c) > abs(target.c)` (a tie retains
   the target sign/value);
3. stores the larger normalized `d`;
4. stores the larger database tick; and
5. rebinds destination `/user_id` to the current deployer after merged entries.

Target-only keys are not streamed through the merger and must remain intact.
These rules cover live/tombstone and differing `c/d/t` conflicts; P3 does not
invent a separate deletion-wins policy.

## Clean and existing targets

A clean target has neither `<db_name>.userdb/` nor legacy
`<db_name>.userdb.kct`. `restore_user_dict` creates the correctly named
database. The two authorized DBs can coexist and are restored independently.

An existing target must first produce a fully verified P2 Package V2 in a
unique safety-backup destination. Native restore does not begin if this backup
fails. The receipt calls it `PreRestoreSafetyBackup` and records:

```text
PreRestoreSafetyBackupStatus = Completed
```

Clean targets record:

```text
PreRestoreSafetyBackupStatus = NotApplicable_CleanTarget
```

**Pre-restore backup is a safety artifact, not a transactional rollback
point.** P3 never automatically imports that artifact after a failure and never
claims `RollbackAvailable` or `TransactionalRestore`.

The P2 backup advertises `PotentialMetadataMutation`: it may normalize
`/user_id` through the official metadata path. Consequently, existing-target
semantic verification uses the canonical state emitted by the completed
safety backup as its real baseline. It does not claim that the safety step was
metadata-neutral.

## Maintenance and lifecycle

Package verification occurs before downtime. P3 then reuses the bounded P2
maintenance controls: only the verified Weasel server is asked to stop, no
unrelated process is killed, and a process is restarted only if it was running
beforehand. Native initialization always reaches finalize, including restore
false/exception and post-restore failure paths.

After maintenance entry, P3 re-detects the installation identity, physical DB
name and paths, and live/legacy/clean state. It repeats that binding check after
the safety backup and immediately before restore. Drift fails closed with
`P3_TARGET_STATE_CHANGED` before `restore_user_dict`.

The outer P3 maintenance owner remains active continuously across target
revalidation, the safety backup, native restore, and verification. Calls into
the pinned P2 backup primitive use its synthetic-maintenance switch solely to
suppress a nested stop/restart; P2 target authorization, native canonical
backup, unique publication, readback, and Package V2 verification remain
active. Thus no input activity is reopened between safety backup and restore.

If restore and verification succeed but process restoration fails, the result
is `CompletedWithMaintenanceWarning`, not ordinary success. A successful safety
or diagnostic package is retained.

## Post-restore verification

A successful native return is only the start of verification. P3 finalizes the
restore session, generates a new canonical P2 backup in a separate diagnostic
destination, runs Package V2 preflight and the strict snapshot parser again, and
compares privacy-preserving logical-key maps.

The receipt reports source count, keys present, tombstone results, conflicts
resolved under the pinned algorithm, target-only keys preserved, and missing
keys. `MissingCount` must be zero, all expected `c/d/t` results must match, all
target-only entries must remain, and the target `/user_id` must be bound to the
current installation before ordinary success is possible.

If native restore returns success but verification fails, P3 returns
`RestoreCompletedVerificationFailed`, retains the safety and post-restore
diagnostic packages, and marks `ManualReviewRequired`. It performs no reverse
restore.

If a native call returns false or throws after it may have begun, P3 reports
`RestoreFailedTargetMayBeModified`, records `NativeRestoreAttempted = true`,
sets `TargetMayHaveBeenModified = true`, observes the post-failure physical
state where possible, and requires manual review. This applies to clean and
existing targets. A newly created clean-target DB is not automatically deleted,
and an existing safety package is never automatically imported.

Repeated restore is described as `ReentrantUnderVerifiedSemantics`, not as
mathematical byte-level idempotence. Ticks or serialized metadata may change
legitimately, but structural health, source coverage, conflict behavior, and
absence of duplicate logical keys must continue to verify.

**A successful native restore call alone does not constitute a verified
restore.**

## Receipt and privacy

The structured receipt contains package/snapshot hashes, logical and physical
identity, target state, safety and diagnostic package references, native and
verification status, aggregate semantic counts, versions, architecture,
maintenance and cleanup status, current-machine identity binding as a boolean,
and `Sensitive = true`.

It contains no phrase, code, complete logical key, offending snapshot line,
source user ID, or target user ID. The safety backup, diagnostic backup, and
source package all contain complete dictionary data and must be handled as
sensitive artifacts.

A verified restore followed by receipt serialization failure raises
`P3_RECEIPT_SERIALIZATION_FAILED` with an explicit no-retry/no-reverse-restore
message. Sensitive temporary cleanup failure preserves the verified-restore
fact but changes the result to `CompletedWithCleanupWarning` and the cleanup
state to `SensitiveTemporaryArtifactCleanupFailed`.

```powershell
.\scripts\Restore-DaMaoUserDbPackageV2.ps1 `
  -PackagePath <package-v2.zip> `
  -SafetyBackupDirectory <safety-backup-directory> `
  -DiagnosticBackupDirectory <diagnostic-backup-directory>
```

## Acceptance and CI

The standalone test runs on Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\tests\Test-DaMaoUserDbPortabilityP3.ps1
```

It uses only temporary synthetic Rime machine directories with the real pinned
librime DLL. Coverage includes clean and existing targets, a non-ASCII extended
target path, both physical DBs, the public CLI, candidate ranking and learned
2/3/4-character phrases, tombstone and `c/d/t` conflicts, current-machine user
identity, target-only preservation, repeated restore, corrupt-package
pre-mutation rejection, safety-backup/native failure, forced verification
failure, target-state drift, restore-source drift, clean/existing partial
failure semantics, zero maintenance/backup/restore counts for every corrupt
package, privacy, and cleanup.

GitHub Actions runs `-HermeticOnly` under both PowerShell hosts and explicitly
reports one skipped native dependency with its reason. Real librime integration
remains controlled local clean-tree evidence. Therefore:

```text
P3RemoteCiCoverage = Partial
```

P3 does not touch the installer and does not implement migration, automatic
rename, automatic merge, GUI recovery, or one-click rollback.
