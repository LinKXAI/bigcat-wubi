# UserDB Portability P2

P2 backup behavior is guarded by
[Public Baseline V1](userdb-portability-acceptance-baseline.md). The public test
suite validates current pinned files directly and requires no private Git history.

P2 adds targeted librime 1.13.1 backup and UserDB Portability Package V2. It does
not add restore, import, database-name migration, legacy migration, installer
behavior, or any P3 capability.

## Authority and semantics

`librime.levers.backup_user_dict` is the only canonical portability snapshot
source in P2. Its `<db_name>.userdb.txt` output preserves UserDB metadata and
learning state. `export_user_dict` creates an editable table-style export with
different semantics and is not in the Package V2 authority chain.

**Export != Backup Snapshot.**

The librime 1.13.1 implementation first attempts to open a UserDB read-only. If
the stored `/user_id` differs from the deployer's current identity, it can reopen
the DB writable and recreate metadata before writing the snapshot. P2 therefore
records:

```text
BackupMutationCapability = PotentialMetadataMutation
```

P2 never claims that backup is always read-only. Automated native acceptance
uses the real librime 1.13.1 DLL with temporary synthetic Rime directories and
never enters a daily user database or changes the real `installation.yaml`.

ABI and behavioral authority is pinned to:

- [`rime_api.h` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime_api.h),
  including self-versioned API boundaries and `find_module`;
- [`rime_levers_api.h` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime_levers_api.h),
  including `backup_user_dict` and `export_user_dict`;
- [`UserDictManager::Backup` and `UserDictManager::Export` at librime 1.13.1](https://github.com/rime/librime/blob/1.13.1/src/rime/lever/user_dict_manager.cc);
- the actual verified `rime.dll`, whose `get_version()` must return `1.13.1`.

Unknown versions fail closed before mutation-capable backup.

## Target policy

P2 authorizes only the two physical databases classified by Public Baseline V1:

| Logical role | Schema identity | Physical DB |
| --- | --- | --- |
| `PureWubi` | `damao_wubi_alpha03` | `damao_wubi_alpha03` |
| `PureWubi` | `damao_wubi` | `damao_wubi` |

`logical_role`, `schema_id`, and `db_name` remain separate identity dimensions.
Caller request, public identity policy, and parsed snapshot header must agree exactly.

The policy is `preserve_separate`: one package contains one physical database.
There is no automatic merge and no automatic rename. `damao_wubi_pinyin` is
excluded by default, and unknown databases are rejected as unclassified. Only a
`LiveDb` may enter native backup. `Absent`, `SnapshotOnly`, `LegacyDb`, and
`Ambiguous` are rejected. Other-machine sync history is not used for targeted
state authorization or canonical snapshot selection.

## Native lifecycle and maintenance

The dedicated adapter:

1. supports the pinned Windows x64 ABI only and fails closed on any other
   process architecture;
2. loads `rime_get_api` with the C calling convention and marshals librime
   `Bool` as a 32-bit integer;
3. checks every main and levers function pointer against its advertised
   `data_size` before use;
4. reads `get_version()` and requires exactly `1.13.1`;
5. initializes librime with the `deployer` module group;
6. runs `installation_update` so the deployer uses the detected installation
   identity and sync directory;
7. resolves the `levers` module and its versioned custom API;
8. calls `backup_user_dict` with explicit UTF-8 marshaling; and
9. always pairs initialization with `finalize` in cleanup.

For a non-synthetic operation, P2 enters a bounded maintenance window. It sends
`/quit` only to the verified `WeaselServer.exe`, waits up to the configured
timeout, never force-kills unrelated processes, and requests a restart only if
that verified server was running beforehand. The operation receipt carries a
machine-readable maintenance status. Synthetic tests record
`NotRequiredSynthetic` and do not stop the real user Weasel process.
If package publication succeeds but restoration fails, the verified package is
retained and the operation status is `CompletedWithMaintenanceWarning`, with
`P2_MAINTENANCE_FAILED` in the maintenance result; it is not reported as plain
success.

## Canonical acquisition and validation

`backup_user_dict` chooses its own destination. P2 derives exactly one path from
the P1 detector:

```text
<sync_dir>/<installation_id>/<db_name>.userdb.txt
```

It does not recursively select an old or other-machine snapshot. A successful
native return is insufficient. P2 performs a bounded stable read (metadata,
read/hash, metadata, second read/hash, metadata), then invokes the pinned P1
strict parser. Acceptance requires:

- `StructuralHealth = Healthy`;
- exact requested `DbName` and `DbType = userdb`;
- zero duplicate logical keys;
- nonzero bounded byte length;
- SHA-256 and entry count; and
- unchanged bytes throughout validation.

An unchanged database may legitimately produce the same snapshot SHA-256 on
repeated backup.

## Package V2

Every ZIP has exactly two canonical entries:

```text
manifest.json
snapshots/<db_name>.userdb.txt
```

No LevelDB directory, `.userdb.kct`, other-machine history, log, installer
state, absolute path, or unrelated UserDB is admitted. ZIP entry validation
rejects absolute paths, `..`, backslashes and alternate spellings, ADS/device
syntax, duplicates and case-insensitive collisions, excess entries, reparse
payloads, and snapshots larger than the configured bound.

The manifest records package/version/time; logical, schema, and DB identities;
snapshot relative path, SHA-256, byte length, entries, tombstones and tick
range; snapshot header identity/version; source librime/Weasel versions;
backup API and mutation capability; and the fixed no-merge/no-rename policy. It
contains no phrase, code, entry value, offending line, or absolute local path.

The snapshot is human-readable already. P2 does not create CSV and does not
re-serialize, sort, normalize newlines, or change a BOM. Staging is a
byte-for-byte copy.

Publication is:

```text
temporary staging -> staged parse -> manifest -> temporary ZIP
-> reopen/whitelist/hash/size validation -> same-directory atomic file move
-> final-file length/SHA-256 check -> final ZIP semantic readback
```

On failure, no final ZIP remains and temporary cleanup is attempted. The
official librime sync snapshot may remain. P2 does not roll back live UserDB
metadata and makes no transactional rollback claim.

The temporary ZIP is a sibling of the final file, so publication never relies
on a cross-volume move. An existing final name fails closed with
`P2_PACKAGE_DESTINATION_EXISTS`; Package V2 has no destructive `-Force` mode.

## Privacy and command

The package contains the complete learned dictionary and is sensitive:

```text
Sensitive = true
ContainsUserDictionaryData = true
```

The command warns about this without printing dictionary contents:

```powershell
.\scripts\Backup-DaMaoUserDbPackageV2.ps1 `
  -DbName damao_wubi_alpha03 `
  -OutputDirectory <destination-directory>
```

The success receipt returns package path/hash/length, logical role and DB,
snapshot hash/length/counts, source versions, backup API, mutation capability,
creation time, and maintenance result. Default success and failure output does
not contain phrases, codes, values, or offending snapshot lines.

## Acceptance

The standalone acceptance test runs unchanged on Windows PowerShell 5.1 and
PowerShell 7.x:

```powershell
.\tests\Test-DaMaoUserDbPortabilityP2.ps1
```

It uses real librime 1.13.1 plus isolated synthetic UserDBs. Coverage includes
both authorized DBs, coexistence and separate packages, current and mismatched
Machine-A/B identities, missing DB, all rejected target classes, old-machine
history exclusion, repeated unchanged backup, export-vs-backup semantics,
tombstone and learning-state preservation, canonical/ZIP/atomic validation,
failure injection, privacy, UTF-8, and non-ASCII long Windows paths.

GitHub Actions runs the hermetic P2 contract on Windows PowerShell 5.1 and
PowerShell 7. Native librime integration remains a controlled local clean-tree
acceptance and is reported as an explicit native skip in remote CI, never as a
silent pass. Therefore `P2RemoteCiCoverage = Partial`.

**A successful backup package does not prove restore capability.**

**Restore belongs to P3.**
