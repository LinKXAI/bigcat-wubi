# User data and backup

## Data locations

| Content | Default location | Owner |
| --- | --- | --- |
| Weasel programs and shared resources | `C:\Program Files\Rime\weasel-*` | Weasel installer |
| Big Cat Wubi source configuration | Repository `schemas/` | Version controlled |
| Rime runtime configuration | `%APPDATA%\Rime\*.yaml` | User / Rime |
| Big Cat Wubi user dictionaries | `%APPDATA%\Rime\damao_wubi*.userdb*` | User / librime |
| Rime sync snapshots | `%APPDATA%\Rime\sync\*\*.userdb.txt` | User / librime |
| Big Cat Wubi backups | `%USERPROFILE%\DaMaoBackups` by default | User |

Configuration copies and user databases share the Rime user directory because
that is the supported Rime runtime model. Big Cat Wubi does not move or upload
them.

## Backup

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Backup-DaMaoUserDictionary.ps1
```

The compatibility backup asks Weasel/Rime to produce a synchronization snapshot
and packages only the Big Cat Wubi snapshot. It does not hot-copy LevelDB files,
other schemas, complete configuration, or `installation.yaml`.

Package V2 provides stricter single-database acquisition and validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Backup-DaMaoUserDbPackageV2.ps1 `
  -DbName damao_wubi_alpha03 -OutputDirectory <destination>
```

Backup archives contain learned words and frequencies. Treat them as sensitive.

## Restore

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Restore-DaMaoUserDictionary.ps1 `
  -Archive <backup.zip>
```

Package V2 restore validates the ZIP, manifest, snapshot bytes, structure,
version, identity, and current target before mutation. Restoring into an existing
database requires a verified pre-restore safety backup. Restore is merge-style,
not transactional replacement, and never performs automatic cross-database
merge, rename, or migration.

## Never commit or disclose

- `*.userdb`, `*.userdb.kct`, `*.userdb.txt`, or `sync/` content;
- `installation.yaml`, `user.yaml`, or real backup archives;
- real names, addresses, private terms, keystroke history, or learned phrases;
- receipts or screenshots that expose personal paths or installation IDs.
