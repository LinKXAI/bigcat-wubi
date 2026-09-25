> Final DEV3: READY FOR COMMIT / READY FOR RELEASE CANDIDATE.
> SHARED-POLICY-01 CLOSED; automatic acceptance and minimum human rechecks 3/3 PASS.
> [Final DEV3 acceptance](quanpin-dev3-acceptance.md).
> [Commit / PR / RC preparation](quanpin-release-preparation.md).
> DEV2 observations below remain historical evidence, not DEV3 manual PASS.

# Independent full-pinyin candidate

This is an uncommitted candidate on codex/standalone-quanpin-entry, based on
34b1a5f429abbe448160ee1d914d3ece9d5c1e38. No release, tag or commit is created.
The 17-file Public Baseline V1 and PureWubi portability contract are unchanged.
User-reported Windows Sandbox acceptance for DEV2 is archived in
[2026-09-25 acceptance and seal review](quanpin-release-acceptance.md).
The DEV2 minimum manual observations passed; its seal decision was BLOCKED by
a shared-policy conflict. DEV3 fixes that guard; all three final human rechecks passed and the blocker is CLOSED.

## Installation and selection

Setup -> Bootstrap-Weasel.ps1 -> Install-DaMaoWithQuanpin.ps1 -> existing
Install-DaMao.ps1 (SkipDeploy) -> combined configuration -> one deployment ->
verification of both compiled schemes. The always-created Start menu shortcut and optional desktop shortcut use
Install-DaMaoWithQuanpin.ps1. The desktop task is unchecked by default; see the
acceptance archive for names, locations and the limited manual observation. The pure Wubi schema and input core are unchanged.

On an absent or empty Rime directory, Setup offers Wubi (default) or Pinyin
(full pinyin). Bootstrap captures freshness before installing Weasel; therefore
Weasel-generated starter configuration does not defeat the chosen entry. The
fresh schema list contains just damao_wubi and luna_quanpin in the selected
order. Native tests create an actual session WITHOUT selecting a schema and
verify its identity, including simulated Weasel starter selection.

For an existing environment the UI explicitly says to retain current selection,
order and settings, and disables the entry choice. Installer preserves the
existing schema order and unrelated patches and appends only missing entries.
It never directly writes user.yaml. Ambiguous or unsupported YAML is rejected.
Native tests also redeploy after learning and verify the actual selected schema
and learned phrase survive. The user observed first-use Pinyin and retained selection in Sandbox; fresh
Wubi GUI first-use was not separately reported (native test passed).

## Resources and learning

The 14 runtime files in dependencies/quanpin.lock.json come verbatim from the
already pinned Weasel 0.17.4 installer (SHA-256
CF509534A8F5F8AF9C98ED7CBB8F135439F145A8CBE7E50EDE42BB5B5AB45C29).
Each has an archive path, size and SHA-256. Authors, license notices and license
hashes accompany them in third_party/rime/quanpin-weasel-0.17.4.

luna_quanpin schema 0.2 (menu: 全拼) includes luna_pinyin schema 0.26 and uses
its dictionary 2024.02.10. Closure includes stroke schema 0.5/dictionary 1.1,
pinyin spelling rules, prelude configuration fragments, essay vocabulary and
OpenCC t2s/TSCharacters/TSPhrases. No Lua, pinyin-simp or mixed Wubi-pinyin engine
is introduced. Optional grammar/custom_phrase resources are not required.
No runtime files are downloaded at install time; Weasel/librime/rime-wubi stay
at their existing lock versions.

The independent luna_quanpin.custom.yaml copies the inspected named switches
and sets simplification reset=1; the shared base schema remains unchanged.
Ctrl+Shift+4 toggles simplified/traditional; Ctrl+Shift+2 toggles Chinese/ASCII;
F4 or Ctrl+grave opens the scheme menu. PageUp/PageDown page candidates; space
commits, backspace edits, apostrophe separates syllables.

The effective translator dictionary is luna_pinyin with no user_dict override.
Isolated native learning creates luna_pinyin.userdb and exports
luna_pinyin.userdb.txt; no luna_quanpin.userdb is created. This is runtime
identity evidence, not an inference from schema_id. Existing luna_pinyin schemes
may share this learning database; nothing is renamed, migrated or merged.
The existing BigCat PureWubi backup/restore tools DO NOT cover pinyin learning.

## Conflicts, rollback and uninstall

Exact existing user/shared dependencies are reused, missing ones copied locally,
and differing resources or dependency custom patches rejected before changes.
An existing different luna_quanpin.custom.yaml is preserved and rejected for
manual reconciliation, except the exact installer-owned dev.1 policy described
below. Generic error details identify the conflicting file.
DEV3 checks shared-data luna_quanpin.custom.yaml before mutation. Byte-identical
current policy is compatible; all other content, including unrelated patches,
is conservatively rejected. Shared files are neither changed nor claimed as
owned. See DEV3 acceptance for native before/after and repeated-failure tests.

The transaction snapshots only configuration, compiled cache and installer
metadata, never learning databases. It restores original files and removes
only additions on failure. Resource additions/reuse are recorded in
Rime/damao_wubi/quanpin-install.json. Wubi-specific assets continue to use the
existing installer ownership ledger. Shared full-pinyin dependencies and its
policy are retained on uninstall because surviving schemes can use them.

Previously the normal BigCat cleanup unconditionally removed
both damao_wubi.userdb and damao_wubi.userdb.kct regardless of the Weasel choice.
Those two removals are now eliminated. Both ordinary uninstall paths preserve
all personal learning data. The optional registered Weasel uninstaller remains
unchanged; both uninstall/reinstall paths were reported successful by the user.
Reboot-delayed deletion was NOT EXECUTED / NON-BLOCKING. Removing
Weasel removes the Weasel program, not authorization to erase Rime user data.

## Candidate build and automated acceptance

Run in Windows PowerShell 5.1 from the public repository. Native test DLL is
extracted in an isolated directory from the same fixed installer, never from a
user Rime/build directory. Example extraction with existing 7-Zip:

```powershell
& 'C:\Program Files\7-Zip\7z.exe' x -aos -y '-o<isolated-extract>' third_party/weasel/0.17.4/weasel-0.17.4.0-installer.exe
$dll = '<isolated-extract>\rime.dll'
.\tests\Run-DaMaoTests.ps1
.\scripts\verify.ps1
.\tests\Test-DaMaoPunctuationRegression.ps1
.\tests\Test-DaMaoAlpha03.ps1 -WubiDictionary .\third_party\rime\rime-wubi\wubi86.dict.yaml
.\tests\Test-DaMaoUserDbPortabilityP0.ps1
.\tests\Test-DaMaoUserDbPortabilityP1.ps1
.\tests\Test-DaMaoUserDbPortabilityP2.ps1 -RimeDll $dll
.\tests\Test-DaMaoUserDbPortabilityP3.ps1 -RimeDll $dll
.\tests\Test-QuanpinInstall.ps1
.\tests\Test-QuanpinNative.ps1 -RimeDll $dll -DefaultEntry Wubi -BootstrapFresh
.\tests\Test-QuanpinNative.ps1 -RimeDll $dll -DefaultEntry Pinyin -BootstrapFresh
.\scripts\Build-WindowsInstaller.ps1 -QuanpinCandidate
```

Use a new PowerShell process for each native test. Native tests stage the exact
Inno application payload into a fresh temporary directory, use empty shared
data, and call librime directly. They never invoke an installed deployer or
inspect real learning data. Upstream essay compilation emits warnings for
unencodable vocabulary (for example mixed Latin/Han terms); these do not
prevent deployment. Optional grammar absence is also expected.

The candidate build requires no clean commit. It gives the package a unique
BigCatWubi-Quanpin-0.9.1-dev.3-TIMESTAMP.exe name and Windows version 0.9.1.3.
Its .sources.json records the base commit, dirty status, actual input file
hashes, compiler hash, candidate defines and output hash. This explicitly
identifies a working-tree build; the base commit alone is not its source.
It does not overwrite BigCatWubi-Setup.exe.

## Manual Windows Sandbox acceptance (user report, 2026-09-25)

See the [itemized acceptance archive](quanpin-release-acceptance.md) for PASS,
NOT TESTED / NON-BLOCKING and NOT APPLICABLE distinctions. The report covers
clean offline Pinyin first-use, native input, both Shift keys, cat icons,
existing-environment preserve selection, at least one formal redeploy shortcut,
and both uninstall/reinstall paths with learned test phrase recovery.
It is user observation, not agent-executed GUI automation. No independent
screenshots or sandbox logs were supplied. Closed sandbox state cannot be
recovered and is not a product failure. The minimum manual acceptance supplied
for DEV2 is complete; its blocker remains historical evidence. The separate
final DEV3 report confirms clean offline default-Pinyin GUI/TSF input,
DEV2-to-DEV3 scheme/learning preservation and explicit shared-policy rejection.
All three human rechecks PASS; the blocker is CLOSED. Other unexecuted items
retain their recorded non-blocking status.

## Dev.2: native Shift commit and cat icon

Only luna_quanpin.custom.yaml changes input configuration. No Lua, processor,
key interception, engine upgrade, shared configuration edit or pure-Wubi core
change is introduced. The local ascii_composer section includes effective default:/ascii_composer
and patches only Shift_L and Shift_R to commit_code. Other global user
customizations, including Control/Caps settings, remain inherited.

Native tests use the unchanged locked DLL and actual key-down/key-up events.
With xi'an composing and 西安 selected, the observed results are:

| Entry | Dev.1 | Dev.2 |
|---|---|---|
| Left Shift | Inline xi'an, ASCII mode, no commit | Immediately commit exact xi'an, clear composition, ASCII mode |
| Right Shift | Commit 西安, ASCII mode | Immediately commit exact xi'an, clear composition, ASCII mode |
| Return | Commit xi'an, stay Chinese | Unchanged |
| Chinese Space | Commit 西安 | Unchanged |
| English Space | Return key unhandled to host application | Unchanged |
| Ctrl+Shift+2 | Inline xi'an, ASCII mode, no commit | Unchanged |
| Native set_option(ascii_mode) | Inline xi'an, ASCII mode, no commit | Unchanged |
| Caps Lock / Eisu_toggle | Clear composition, ASCII mode, no commit | Unchanged |

Shift requires no following Space/Return and appends no space. Normal Return
was already a raw-code commit; this change does not redefine it. Actual menu
and mouse/frontend paths are not claimed to match Shift and were not GUI-tested.
The upstream native mechanism is described in
[AsciiComposer](https://github.com/rime/librime/blob/1.13.1/src/rime/gear/ascii_composer.cc);
the fixed DLL tests, not an inferred engine version, are the acceptance evidence.

Both schema/icon and schema/ascii_icon point to
luna_quanpin/branding/bigcat-ime.ico. Installer copies the exact existing
assets/branding/windows/bigcat-ime.ico bytes; there is no new icon design or
online dependency. This separate copy survives removal of Wubi's icon while
full pinyin remains installed. Compiled paths and deployed hash are tested;
the user also confirmed Chinese/English cat rendering and normal Wubi icons.

Dev.1 upgrade is allowed only when both original policy SHA-256
39DFD375B5D8D2EC36FB4D3D54C829F3A3B30603D2E2C636183E55DFFE085E30
and its existing format-1 receipt match (Kind QuanpinDefaultPolicy, Action Add,
same hash and exact relative path). Missing/untrusted receipts or customized
bytes fail before mutation. The updated receipt records PreviousSHA256 and the
new hash. New icon conflicts also fail closed. Rollback tests cover restoration
of the old policy and receipt, removal only of a newly added icon, preservation
of an existing icon, and unchanged synthetic learning/configuration bytes.

Additional commands, each in its own Windows PowerShell 5.1 process:

```powershell
.\tests\Test-QuanpinSwitch.ps1 -RimeDll $dll -Policy Dev1
.\tests\Test-QuanpinSwitch.ps1 -RimeDll $dll -Policy Current
.\tests\Test-QuanpinNative.ps1 -RimeDll $dll -DefaultEntry Pinyin -UpgradeDev1
```

The user confirmed the Shift, Return/Space and icon observations above.
Dev.1-to-dev.2 GUI upgrade and GUI conflict fixtures were not separately
reported; native upgrade and conflict/rollback tests passed. Do not broaden
these facts into an all-environment PASS. See the seal archive for the shared
policy conflict that the previous suite did not cover.
