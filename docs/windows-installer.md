> Final DEV3: READY FOR COMMIT / READY FOR RELEASE CANDIDATE.
> Automatic acceptance and minimum human Sandbox rechecks 3/3 PASS;
> SHARED-POLICY-01 CLOSED: [DEV3 acceptance](quanpin-dev3-acceptance.md).
> [Commit / PR / RC preparation](quanpin-release-preparation.md) records the
> candidate, submission files and remaining non-blocking checks.
> Historical DEV2 results: [acceptance archive](quanpin-release-acceptance.md).
> The historical sections below do not replace those dated records.

> Candidate full-pinyin integration is documented in [Quanpin candidate](quanpin-candidate.md).
> Normal Setup and redeploy now enter Install-DaMaoWithQuanpin.ps1 before the
> existing Wubi installer. Personal learning databases are retained on uninstall.

# Windows installer and ownership-aware uninstall

## Architecture

`BigCatWubi-Setup.exe` contains every third-party artifact required by the
normal clean-machine installation path. Installation does not use Git, Plum,
GitHub, a browser, or a package manager.

```text
BigCatWubi-Setup.exe
  -> PrepareToInstall stages four read-only guard inputs and rejects conflicting shared full-pinyin policy
  -> installs BigCat scripts, schema, branding, licenses, and pinned rime-wubi files
  -> runs Bootstrap-Weasel.ps1 -ProbeOnly
     -> Usable: do not extract or run the embedded Weasel installer
     -> Absent: extract the embedded official Weasel installer to {tmp}
     -> Unusable: fail closed without replacing the existing installation
  -> validates the bundled rime-wubi source
  -> captures whether %APPDATA%\Rime is absent or has zero entries
  -> rechecks shared policy before writing immutable Weasel provenance
  -> classifies and persists immutable Weasel provenance before deployment
  -> if needed, verifies and runs the direct Weasel installer process
  -> bounded Weasel rediscovery
  -> calls Install-DaMaoWithQuanpin.ps1 with the local Wubi source and Weasel root
     -> existing Install-DaMao.ps1 -SkipDeploy, combined configuration, one deployment
```

The install root is `%LOCALAPPDATA%\Programs\BigCatWubi`. Inno Setup remains
a thin orchestration layer and does not edit Rime YAML, registry settings,
UserDB data, or Weasel program files. `Install-DaMaoWithQuanpin.ps1` coordinates the dual-schema transaction, merge,
deployment and verification. It reuses `Install-DaMao.ps1 -SkipDeploy` for the
existing Wubi installation; the pure-Wubi core remains unchanged. `DaMao.InstallerState.ps1` owns the provenance contract and
`Uninstall-BigCat.ps1` owns the targeted inverse mutation, exact artifact
cleanup, retained-Weasel redeploy, and registered Weasel uninstaller boundary.

## Weasel ownership model and persisted state

The pre-install Weasel observation and any trustworthy earlier BigCat state are
captured before Setup changes Weasel. The state is `%LOCALAPPDATA%\Programs\BigCatWubi\installer-state.ini`
(`{app}\installer-state.ini`) with this versioned format:

```ini
[installer]
format_version=1
weasel_origin=BigCatBootstrap
rime_user_dir=C:\Users\example\AppData\Roaming\Rime

[rime_ownership]
wubi86_dict=<SHA-256, only when BigCat created it>
wubi86_license=<SHA-256, only when BigCat created it>
wubi86_source_metadata=<SHA-256, only when BigCat created it>
```

The three origins are:

- `BigCatBootstrap`: initial discovery was `Absent` and the bundled official
  Weasel installer returned success followed by usable-Weasel rediscovery.
- `PreExisting`: the first tracked BigCat install found a usable Weasel.
- `UnknownLegacy`: a previous BigCat installation exists, Weasel is usable,
  but no trusted versioned provenance exists. It is deliberately treated like
  `PreExisting` during uninstall.

A valid existing origin wins on upgrade or repair. In particular, observing
Weasel on an upgrade can never change `BigCatBootstrap` to `PreExisting`.
A successful new bootstrap is explicit evidence that the current Weasel was
installed by BigCat and records `BigCatBootstrap`. Malformed, missing, or
unsupported state is never interpreted as BigCat ownership.

The optional `[rime_ownership]` hashes cover only shared rime-wubi files that
did not exist before the first tracked installation, or that were already
tracked by an earlier versioned state. Hashes are refreshed on upgrade. They
allow uninstall to distinguish BigCat-created dependencies from pre-existing
or subsequently user-modified files.

## Recorded pre-closure Windows Sandbox acceptance

A real clean Windows Sandbox run confirmed the following:

- the machine initially had no Weasel;
- Setup installed the bundled official Weasel 0.17.4 successfully;
- the direct-process wait returned while `WeaselServer.exe` remained resident;
- after the installer supplied the bundled `rime-wubi` source, Big Cat deployment completed;
- Big Cat Wubi could be selected and used after deployment;
- rerunning Setup did not create a duplicate BigCat installation entry; and
- the earlier preservation-only uninstall left Weasel installed.

That run predates the ownership-aware uninstall closure below and is retained
as preliminary install/bootstrap evidence. The completed final operator run is
covered by the automated Windows installer tests.

Weasel's normal “小狼毫维护中” state appeared during deployment and is accepted
behavior. One first keypress immediately after maintenance did not visibly
produce output, followed by normal use; this single observation is not treated
as a confirmed defect without independent reproduction.

That preliminary run did not positively record that networking was disabled.
The later final operator run explicitly covered network-disabled installation
and the scheme icon; those results are recorded separately below.

## Fresh-install default schema

The earlier merge always used `schema_list/+`. On a clean machine, the silent
Weasel installer creates initial Rime files and starts the server before BigCat
deployment. Appending BigCat therefore left Weasel's initial schema earlier in
the effective list, while `user.yaml` could retain that still-valid previous
selection.

The bootstrap entry point now captures freshness before the Weasel flow starts.
Fresh means exactly one of the following: `%APPDATA%\Rime` does not exist, or it
exists and contains zero filesystem entries, including hidden entries. Any file
or subdirectory makes the state non-fresh.

For only that captured fresh state, `Install-DaMao.ps1` adds BigCat with the
supported `schema_list/@before 0` patch. This places it before the shared Weasel
defaults without deleting them. If Weasel produced an explicit schema list, the
safe merger instead deduplicates it, places BigCat first, and preserves every
other schema's relative order and unrelated `default.custom.yaml` keys. The
normal deploy step makes the compiled order effective.

No path writes `user.yaml`. Existing users continue through the preservation-
first append merger. Because reinstall, repair, and visible redeploy begin with
a non-empty Rime directory and do not forward the one-shot initialization flag,
they preserve a later user-selected schema.

## Pinned third-party payload

The machine-readable source of truth is
`dependencies/windows-installer-v2.lock.json`. The build and repository
verification both check every locked file's exact byte length and SHA-256
before compilation.

### Weasel

- Project: `rime/weasel`
- Repository: https://github.com/rime/weasel
- Version/tag: `0.17.4`
- Official asset: https://github.com/rime/weasel/releases/download/0.17.4/weasel-0.17.4.0-installer.exe
- Size: `12431118` bytes
- SHA-256: `CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29`
- License: GPL-3.0; the tag's `LICENSE.txt` and source URL are included.

The official EXE is stored unchanged under `third_party/weasel/0.17.4`. Inno
embeds it with `dontcopy`, so it is not installed under `{app}`. A discovery
probe runs first. Only an `Absent` result calls `ExtractTemporaryFile`; a
usable existing Weasel, including a version other than 0.17.4, never causes
the payload to be extracted, run, upgraded, downgraded, or replaced.

After extraction, PowerShell copies the asset into a unique controlled
temporary directory, rejects missing/reparse-point/non-regular input, and
verifies the pinned SHA-256 before execution. There is no online fallback.

The installer is started with `/S` and `-PassThru` without PowerShell's
process-tree `-Wait`. The retained direct `System.Diagnostics.Process` is
waited with `WaitForExit(600000)`, so the intentional resident
`WeaselServer.exe` descendant cannot block Setup. A non-zero direct exit is
fatal. After exit zero, V1 discovery retries every 1000 ms for at most 60
seconds. The first usable result emits `WEASEL_BOOTSTRAP_SUCCEEDED` and
continues once; timeout emits `WEASEL_POST_INSTALL_NOT_FOUND` and fails
closed. No production path kills or waits for `WeaselServer.exe`.

### rime-wubi

- Project: `rime/rime-wubi`
- Repository: https://github.com/rime/rime-wubi
- Commit: `152a0d3f3efe40cae216d1e3b338242446848d07`
- Exact tree: https://github.com/rime/rime-wubi/tree/152a0d3f3efe40cae216d1e3b338242446848d07
- License: LGPL-3.0; the pinned tree's `LICENSE` is included.

The minimum complete source accepted by the existing `-WubiSourcePath`
contract is vendored unchanged under `third_party/rime/rime-wubi`:

- `wubi86.dict.yaml`
- `wubi86.schema.yaml`
- `README.md`
- `LICENSE`

The V1 contract validates all four files, the dictionary header, and LGPL
license text. It installs the dictionary and license plus a BigCat-authored
source record. Because every installer and redeploy invocation supplies
`-WubiSourcePath`, its earlier Plum/Git fallback branch is unreachable in the
installer-driven path.

## Per-schema icon branding

Weasel 0.17.4 reads `schema/icon` and `schema/ascii_icon` from the active
schema and resolves relative files against its user-data directory before the
shared-data directory. The authored BigCat schema sets both fields to:

```text
damao_wubi/branding/bigcat-ime.ico
```

`Install-DaMao.ps1` copies the dedicated small-size asset
`assets/branding/windows/bigcat-ime.ico` to that deterministic location beneath
the resolved Rime user directory. Its native 16, 20, and 24 pixel frames use
the same cat-head identity with less transparent margin and a larger foreground
subject. Normal and ASCII mode reuse that IME-specific design. Redeploy restores
a missing or changed project-owned icon. The original
`assets/branding/windows/bigcat.ico` remains authoritative for Setup, Installed
Apps, and shortcut branding. Deployment does not edit `weasel.custom.yaml`,
replace Weasel's application icon, or modify an upstream binary.

## Ownership-aware uninstall

`InitializeUninstall` reads the persisted origin; it does not infer ownership
from whether Weasel happens to exist at uninstall time. A real checkbox is
shown:

- `BigCatBootstrap`: **同时卸载小狼毫** is checked by default, with guidance
  that Weasel was installed by BigCat.
- `PreExisting`: it is unchecked by default, with guidance that retaining
  Weasel is safe.
- `UnknownLegacy` or invalid/missing state: it is unchecked by default because
  ownership cannot be established.

If a `PreExisting` or `UnknownLegacy` user checks the box, a second warning
explains that other Rime schemas may be affected. The user may still confirm.

Before Inno removes `{app}`, `Uninstall-BigCat.ps1` performs the following
bounded sequence:

1. Ask the discovered current `WeaselServer.exe` to exit with its official
   `/quit` command so the local UserDB is not held open. Failure or timeout is
   logged as a continuing diagnostic and never broadens cleanup into a forced
   process kill.
2. Remove only the exact `damao_wubi` registration from supported
   `default.custom.yaml` schema-list structures. This reuses the install-time
   semantic parser. It never restores a whole backup file.
3. Remove the exact BigCat schema, icon, compiled schema, and live local
   `damao_wubi` UserDB artifacts.
4. Remove tracked shared rime-wubi files only when the saved SHA-256 still
   matches and no other installed schema references `wubi86`.
5. If Weasel is retained, run its deployer so the removal becomes effective.
6. If requested, discover the current Weasel uninstall command from Windows
   uninstall registration and invoke that registered executable and arguments.
   BigCat does not guess a versioned `uninstall.exe` path or simulate Weasel's
   cleanup. A successful official uninstall is authoritative: an earlier
   `WeaselServer.exe /quit` failure or timeout does not change the final BigCat
   result and does not produce a partial-cleanup warning.
7. If the registered uninstaller is missing, cancelled, fails, or times out,
   retain the failure, attempt a redeploy of the still-present Weasel, and let
   BigCat uninstall finish. The user receives a distinct Chinese warning.
8. Remove `installer-state.ini`; Inno then removes its program files,
   shortcuts, empty application directories, and uninstall registration.

When Weasel is retained, actual BigCat cleanup or Rime redeploy failures remain
strictly reportable. The diagnostic-only `/quit` classification applies to the
remove-Weasel preparation step and does not weaken those checks.

The exact unconditional Rime cleanup set is:

```text
damao_wubi.schema.yaml
damao_wubi/branding/bigcat-ime.ico
build/damao_wubi.schema.yaml
default.custom.yaml -> only schema_list entries whose schema is exactly damao_wubi
```

The icon directories are removed only after they are empty. The shared
`wubi86.dict.yaml`, `LICENSE.rime-wubi.txt`, and `rime-wubi.source.json` are
conditional on the recorded creation/hash/dependency checks above.

Deliberately preserved data includes `damao_wubi.userdb`,
`damao_wubi.userdb.kct`, all pinyin learning data, `sync`, timestamped configuration backups,
`damao_wubi.custom.yaml` (user-authored schema customization), all other schema
and UserDB identities, unrelated dictionaries and custom files, and the Rime
root itself. No cleanup path uses a wildcard, deletes `%APPDATA%\Rime`, or
deletes a file merely because its name contains `damao`.

## Packaged BigCat payload

The installer packages the BigCat install/state/uninstall scripts including the
full-pinyin transaction wrapper, formal Wubi schema and independent quanpin
policy, product icons/licenses, dependency locks, third-party provenance and
license files, pinned rime-wubi and full-pinyin resources, and the temporary
embedded Weasel installer.
It does not package tests, Git metadata, diagnostic schemas, development
fixtures, or any user-generated Rime state.

## Failure and preservation behavior

The Setup-time PowerShell processes run synchronously and hidden. A non-zero
result is presented as a deliberate Chinese product error, changes the final
page to an unsuccessful deployment state, and becomes Setup's exit code.
Invalid bundled Wubi fails before Weasel installation or BigCat deployment.
Invalid Weasel staging/hash, direct installer failure, rediscovery timeout,
and existing-but-unusable evidence all fail closed.

Inno may already have finalized its owned files and uninstaller when the
post-install gate fails. That state is `PACKAGE_INSTALLED /
DEPLOYMENT_INCOMPLETE`, not a successful deployment. Uninstall still runs the
targeted BigCat cleanup. Weasel removal remains an explicit checkbox decision;
unknown ownership always defaults to retention.

The visible Start Menu and optional Desktop redeploy shortcuts retain
`-NoExit` and `-UserFacingRedeploy`. They also pass the installed bundled
Wubi source path, making redeploy deterministic and offline.

## Build and automated validation

Use Inno Setup 7.1+ or 6.3+:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Build-WindowsInstaller.ps1
```

An explicit compiler is supported with `-ISCCPath`. The build script validates
all inputs and the third-party lock, downloads nothing, and writes only to the
ignored `dist/windows` directory.

Run the release-relevant validation before building:

```powershell
./tests/Test-WeaselBootstrap.ps1
./tests/Test-WindowsInstaller.ps1
./tests/Test-InstallerUninstall.ps1
./tests/Test-DaMaoRedeploy.ps1
./scripts/verify.ps1
./tests/Run-DaMaoTests.ps1
git diff --check
```

## Installer safety invariants

1. Weasel provenance is exactly `BigCatBootstrap`, `PreExisting`, or
   `UnknownLegacy`. `BigCatBootstrap` means Big Cat installed Weasel because no
   usable Weasel existed; `PreExisting` means usable Weasel existed before Big
   Cat; `UnknownLegacy` means legacy Big Cat state exists but ownership cannot
   be proven.
2. Trusted provenance survives upgrade. The mere presence of Weasel during an
   upgrade never converts `BigCatBootstrap` to `PreExisting`.
3. The remove-Weasel checkbox defaults checked only for `BigCatBootstrap`.
   `PreExisting`, `UnknownLegacy`, invalid state, and missing state default to
   unchecked.
4. Explicit Weasel removal for `PreExisting` or `UnknownLegacy` requires an
   additional warning and confirmation.
5. Big Cat removes only owned or provably Big Cat-created artifacts. It never
   performs wildcard Rime-root cleanup or whole-file restoration of
   `default.custom.yaml`; user-created `damao_wubi.custom.yaml` is preserved.
6. Shared wubi86 assets are deleted only when trusted ownership proves Big Cat
   created or tracked them, their current hashes still match, and no other
   schema depends on wubi86.
7. Weasel removal uses the registered official/current Weasel uninstaller. Big
   Cat uninstall remains independently successful if Weasel removal fails.
8. A `WeaselServer.exe /quit` timeout is diagnostic, not final uninstall
   failure. A later successful official Weasel uninstall produces overall
   success; failure or cancellation attempts a recovery redeploy and reports
   an actionable incomplete state.
