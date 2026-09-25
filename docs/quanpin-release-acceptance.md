> Current final decision (2026-09-25): READY FOR COMMIT / READY FOR RELEASE CANDIDATE.
> DEV3 automatic acceptance PASS; minimum human Sandbox acceptance 3/3 PASS:
> clean offline default Pinyin, DEV2-to-DEV3 scheme/learning preservation,
> and shared page_size=9 conflict fail-closed. SHARED-POLICY-01: CLOSED.
> See [final DEV3 acceptance](quanpin-dev3-acceptance.md) and
> [commit / PR / RC preparation](quanpin-release-preparation.md).
> Everything below is the historical DEV2 review, including its then-BLOCKED
> decision and repair proposal; it does not describe current DEV3 readiness.
> Reboot delayed deletion and the second optional redeploy shortcut remain
> unexecuted/non-blocking; no additional human PASS is inferred.

# DEV2 acceptance archive and pre-release seal review

Date: 2026-09-25. Decision: **C. BLOCKED** (SHARED-POLICY-01).
No implementation or accepted binary changed during this review. No commit,
push, merge, tag, release, rebuild or real Rime deployment was performed.

## Identity and provenance

- Repository: LinKXAI/bigcat-wubi; branch codex/standalone-quanpin-entry.
- HEAD/base: 34b1a5f429abbe448160ee1d914d3ece9d5c1e38.
- Accepted candidate: BigCatWubi-Quanpin-0.9.1-dev.2-20260920-180426.exe.
- Product version 0.9.1-dev.2; Windows version 0.9.1.2; 18,313,013 bytes.
- SHA-256: 9FC939A60ECDBE766BF1D9815E335A024DF87EA34EA9F44E209EC9A1F6AA0B05.
- Binary rehash MATCH; all 46 .sources.json build inputs MATCH (zero drift).
- This is an uncommitted working-tree build, not the base commit alone.
  This round changes documentation/receipts only, outside those 46 inputs.
- Existing feature changes and untracked resources were reviewed; no unrelated
  workspace changes were identified. The historical repository tree was not edited.

## Manual acceptance: user observations only

Source: user instructions received 2026-09-25, for the binary above. These are
not assistant-executed tests. No independent screenshots/logs were supplied.

| Item | Status | Observation / scope |
|---|---|---|
| A Offline clean install, Pinyin chosen | PASS | Actual first activation was full pinyin without F4; F4 offered both schemes. |
| B Full-pinyin input | PASS | chuang, zhongguo, woaizhongguo, xi'an; candidates, Chinese Space, PageUp/PageDown, Backspace, punctuation, simplified/traditional and Chinese/English; no Wubi four-code cutoff. |
| C Left/right Shift | PASS | Uncommitted xi'an with candidate immediately commits exact xi'an, no added space, enters English. |
| C Return / Space unchanged | PASS | Return commits raw code and remains Chinese; Chinese Space selects candidate; English Space inserts ordinary space. |
| C Ctrl+Shift+2 / menu / mouse uniformity | NOT APPLICABLE / NON-BLOCKING | Uniform behavior is outside the agreed requirement; no GUI equivalence claimed. |
| D Icons | PASS | Pinyin Chinese and English show cat; Wubi icon normal. |
| E Existing environment / second install | PASS | Grey preserve-current-scheme UI, no ineffective choice; current Pinyin remains. This is intentional. |
| F Formal redeploy | PASS (at least one shortcut) | Schemas {damao_wubi,luna_quanpin}, Fresh False, DefaultEntry PreserveExisting, Deployed True; selection/input/Shift/icons normal, no duplicate F4 entries. Exact shortcut identity not supplied. |
| F Second shortcut | NOT TESTED / NON-BLOCKING | Do not infer execution of both from the one observed run. |
| G Uninstall retaining Weasel, same-sandbox reinstall | PASS | Personal Rime files/learning retained; learned test phrase callable, no duplicates, input normal. |
| H Uninstall including Weasel, same-sandbox reinstall | PASS | Personal files remained, no delete-all-user-data option; reinstall showed preserve-current; learned test phrase callable. |
| H Reboot / PendingFileRenameOperations | NOT EXECUTED / NON-BLOCKING | Sandbox UI lag prevented this additional check; not part of the minimum manual list, never recorded as PASS. |
| I Earlier sandbox closures | NOT APPLICABLE | Closing Sandbox destroys its state; no product failure inferred. Only completed same-sandbox chains support G/H. |
| Fresh default-Wubi GUI first-use | NOT TESTED / NON-BLOCKING for this review | Not supplied as manual evidence; isolated native Wubi bootstrap first-session test passed. |
| Third scheme/custom-resource GUI matrix; DEV1 GUI upgrade | NOT TESTED / NON-BLOCKING as manual items | Automatic fixtures cover these classes, but do not constitute GUI observations. Shared-policy blocker below remains independent. |

The user-supplied minimum manual acceptance is complete. Both reported
uninstall paths retain learning data; this does not claim the unexecuted reboot
check passed. PureWubi backup remains Wubi-only and excludes luna_pinyin.userdb.

## Redeploy shortcuts: actual installer declarations

installer/windows/BigCatWubi.iss declares two shortcuts, but only one is created
by default (PrivilegesRequired=lowest, current-user shell folders):

| Name | Location | Creation condition |
|---|---|---|
| 大猫五笔 - 重新部署 | Start menu / Programs / 大猫五笔; normally %APPDATA%\Microsoft\Windows\Start Menu\Programs\大猫五笔 | Unconditional {autoprograms} entry |
| 大猫五笔 - 重新部署 | Current user's Desktop known folder ({autodesktop}, may be redirected) | desktopicon task checked by user; unchecked by default |

Both invoke Install-DaMaoWithQuanpin.ps1 with -InstallWubiDependency, the bundled
Wubi source and -UserFacingRedeploy. There is no requirement to blindly locate
a second shortcut when its desktop task was not selected.

## Fresh automatic acceptance

All commands were newly run in separate Windows PowerShell 5.1.26100.9444
processes, working directory the public repository. Invocation prefix:
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File`.
Native DLL and shared fixtures come from the locked Weasel 0.17.4 extraction,
not the real Rime profile. Counts: **16 top-level commands PASS, 0 FAIL, 0 SKIP**.
These existing suites did not cover SHARED-POLICY-01. Passing them does not
negate the additional adversarial failure. No assertion-total aggregation is
used because nested suites overlap.

| Script and arguments (absolute repository prefix rendered as <repo>) | Exit / result |
|---|---|
| `scripts/verify.ps1 ` | 0 / PASS |
| `tests/Run-DaMaoTests.ps1 ` | 0 / PASS |
| `tests/Test-DaMaoPunctuationRegression.ps1 ` | 0 / PASS |
| `tests/Test-DaMaoAlpha03.ps1 -WubiDictionary <repo>\third_party\rime\rime-wubi\wubi86.dict.yaml` | 0 / PASS |
| `tests/Test-DaMaoUserDbPortabilityP0.ps1 ` | 0 / PASS |
| `tests/Test-DaMaoUserDbPortabilityP1.ps1 ` | 0 / PASS |
| `tests/Test-DaMaoUserDbPortabilityP2.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll` | 0 / PASS |
| `tests/Test-DaMaoUserDbPortabilityP3.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll` | 0 / PASS |
| `tests/Test-QuanpinInstall.ps1 ` | 0 / PASS |
| `tests/Test-QuanpinNative.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -DefaultEntry Wubi -BootstrapFresh` | 0 / PASS |
| `tests/Test-QuanpinNative.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -DefaultEntry Pinyin -BootstrapFresh` | 0 / PASS |
| `tests/Test-QuanpinNative.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -DefaultEntry Pinyin -UpgradeDev1` | 0 / PASS |
| `tests/Test-QuanpinSwitch.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -Policy Dev1` | 0 / PASS |
| `tests/Test-QuanpinSwitch.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -Policy Current` | 0 / PASS |
| `tests/Test-QuanpinSwitch.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -Policy Current -CustomDefaults` | 0 / PASS |
| `tests/Invoke-DaMaoAlpha03LearningRuntime.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll -RimeSharedDataDir <repo>\dist\quanpin-work\extracted\data -WubiDictionary <repo>\third_party\rime\rime-wubi\wubi86.dict.yaml` | 0 / PASS |

verify.ps1 includes redeploy (16 assertions), Windows installer (151), bootstrap
(83), uninstall (53), totaling 303 assertions. P0 verifies frozen baseline
17/17 plus its mutation probe; P1 104; P2 153 including 11 native; P3 567
including 19 native; Quanpin install 58; native Wubi/Pinyin/upgrade 34 each;
Shift DEV1/current/custom-default 18/23/26 respectively. Native learning
confirms luna_pinyin.userdb. Wubi/PureWubi core protections remain intact;
no pinyin backup migration, new Lua/processor or dependency upgrade was added.

Raw run receipts (local temporary evidence, not portable prerequisites):

`C:\Users\xcpu\AppData\Local\Temp\BigCatSeal-20260925-d903e955db964a40bd5ad91490cf5579`

| Log | SHA-256 |
|---|---|
| verify.log | 40DB6843D0922CD9DD82AE0E7A338DB3680A79704166B151783CE9D21C749EE3 |
| core.log | B3D0613DD431135D2B21207BB77E27F7133259E8D12E4F34F646A37464D4B159 |
| punctuation.log | 83D5BAC434455C852717FB50EA46EE7A8453D8EA8A7C2D80395D5A7AA38442E7 |
| alpha03.log | 5B925AE442974B69050A5E122D1AD19FB7881E0A73DAED05210EAC07F52CC0C6 |
| p0.log | 74271B20CAFFB2F28C98556F16E95D523190C66FED3CCDE371222AA3F73E30DE |
| p1.log | 89AFF0B410E3A0BCD390944E439E2426EEDC2A09095C71008FF3BD23443E1E77 |
| p2.log | C2BAE69BCF4DF49E957081EB6E2C1B4FD7E679785F552588C1B8A77576E986A3 |
| p3.log | 69DD92ED938289AEB78F6104A02DBE9823A807F190F11A82F6F02ACF0DB3B0F7 |
| quanpin-install.log | 6FF8876F058904FB1BBD839264133BFE3F2340E8116C17A4D05B2560DE58847E |
| native-wubi.log | B43045F3786D437F84027A0AE860A11DFF62C518E497B41C56614786D68C803B |
| native-pinyin.log | A4D3234A2DC4F69CC291EE12455B38C0916674073D5249BAF2E528B0678D4966 |
| native-upgrade.log | 37BFCF809A1D758B5295C4B4419F087094647C33570E8E68DD32A807B28E1298 |
| switch-dev1.log | 1876704650F720E13FBEF0EA9931E1710C79B1ABF5DF545E3253422717186765 |
| switch-dev2.log | 28EC446E8CAA2A71BB4B5A0C33C9655BB2BABD690C7129F44FE43947EF5A22B5 |
| switch-custom.log | 1B1F9B5A520A63282F36161E2EF6E197626B6022E9CD87B9A834C962707FD328 |
| alpha03-native.log | 17B09B69BFF2DF8F70696773FF7130BEB6BF2759C30CB58DA01FEE23FC098E09 |

## Adversarial review: concrete blocker SHARED-POLICY-01

Impact: installing over a supported existing shared full-pinyin customization
silently changes effective behavior. The shared file itself survives, but the
new user-level luna_quanpin.custom.yaml shadows its patch. This violates the
requirement to preserve existing customizations or fail before mutation.

Get-DaMaoQuanpinPlan in scripts/DaMao.Quanpin.ps1 checks shared custom patches
for six dependencies, but checks luna_quanpin.custom.yaml only in RimeUserDir.
It schedules Add even when WeaselRoot/data/luna_quanpin.custom.yaml exists.

Minimal isolated reproduction executed using the exact locked native DLL:

1. Create synthetic user and weasel/data directories, copy the pinned 14-file
   dependency closure into shared data, add a harmless WeaselDeployer.exe marker
   (never executed), and set user default.custom.yaml to select luna_quanpin.
2. Add shared luna_quanpin.custom.yaml containing:
   `patch: {menu/page_size: 9}` (the executed fixture uses equivalent block YAML).
3. Native DeployWorkspace returns True and compiled luna_quanpin has page_size 9.
4. In an equivalent fresh synthetic fixture run Install-DaMaoWithQuanpin.ps1
   -RimeUserDir <fixture/user> -WeaselRoot <fixture/weasel> -SkipDeploy.
   Then deploy through the same locked DLL. It returns True; page_size is now 5.
5. Shared policy hash remains
   26024C5F54D5AAAD695EC72CF289C5034FFE402F6388A0DF4270A5500C807E9C
   in both cases. This demonstrates effective shadowing, not physical deletion.

Both reproduction processes exited 0 because they are diagnostic probes;
**one product protection invariant FAILED** (existing shared patch preserved
or installation rejected). Do not add these exits to the 16-suite PASS total.
The executed reproduction script and outputs are archived below for repeatability.

Minimum repair scope (not implemented during this archival review): extend
policy preflight to inspect shared luna_quanpin.custom.yaml with the same path
safety guarantees. Reject incompatible/unowned shared customizations before
any mutation; if exact compatible policy reuse is supported, prove effective
resolution remains correct. Do not use a user-directory ownership receipt to
claim ownership of a shared custom file. Add isolated conflict/no-mutation and
native effective-configuration coverage. Existing Shift/default/icon settings
need no redesign. Re-run affected suites and create a separately identified
candidate only after repair; current DEV2 cannot be relabeled as fixed.

## Seal checklist

| Check | Outcome |
|---|---|
| 46 source inputs / binary size, version and hash | PASS |
| Worktree scope and source attribution | PASS; dirty feature tree, not base-only build |
| Frozen baseline / pure Wubi core | PASS 17/17; unchanged |
| Fresh vs existing installer paths | PASS automatic and scoped user observations |
| Uninstall learning protection | PASS automatic and both reported manual chains; reboot excluded |
| Shared ownership/conflict/rollback | BLOCKED SHARED-POLICY-01; existing covered rollback cases PASS |
| PureWubi scope | PASS; pinyin database excluded |
| Cat icon deployed references and Wubi uninstall independence | PASS covered native checks and user observations |
| Version / receipt / documentation consistency | PASS identity; dated addendum supersedes historical manual-not-run status |
| Release readiness | BLOCKED; no commit or RC recommendation issued pending the concrete fix |

The DEV2 blocker wait recorded at that time is superseded by the final DEV3
closure above. No staging or release action has been taken.

## Executed diagnostic script (repository prefix normalized)

```powershell
param([switch]$Installed)
$ErrorActionPreference='Stop'
$repo=(Get-Location).Path # run from the public repository
$root=Join-Path $env:TEMP ('BigCatSharedPolicyReview-'+[guid]::NewGuid().ToString('N'))
$user=Join-Path $root 'user';$weasel=Join-Path $root 'weasel';$shared=Join-Path $weasel 'data'
New-Item -ItemType Directory -Path $user,$shared -Force|Out-Null
Copy-Item "$repo\third_party\rime\quanpin-weasel-0.17.4\*" $shared -Recurse
[IO.File]::WriteAllText((Join-Path $weasel 'WeaselDeployer.exe'),'fixture')
[IO.File]::WriteAllText((Join-Path $shared 'luna_quanpin.custom.yaml'),"patch:`n  menu/page_size: 9`n")
[IO.File]::WriteAllText((Join-Path $user 'default.custom.yaml'),"patch:`n  schema_list:`n    - schema: luna_quanpin`n")
if($Installed){& "$repo\scripts\Install-DaMaoWithQuanpin.ps1" -RimeUserDir $user -WeaselRoot $weasel -SkipDeploy|Out-Null}
Add-Type -Path "$repo\tests\DaMaoRimeQuanpinNative.cs"
try {
[DaMaoRimeQuanpinNative]::Load("$repo\dist\quanpin-work\extracted\rime.dll",$shared,$user,(Join-Path $user 'build'))
$ok=[DaMaoRimeQuanpinNative]::DeployWorkspace()
$text=[IO.File]::ReadAllText((Join-Path $user 'build\luna_quanpin.schema.yaml'))
[pscustomobject]@{Installed=[bool]$Installed;Deploy=$ok;PageSize=([regex]::Match($text,'(?m)^\s*page_size:\s*(\d+)').Groups[1].Value);Root=$root;SharedPolicyHash=(Get-FileHash (Join-Path $shared 'luna_quanpin.custom.yaml')).Hash}|ConvertTo-Json
}finally{[DaMaoRimeQuanpinNative]::Shutdown()}

```

Invoked once without flags and once with `-Installed`, in separate Windows
PowerShell processes. Outputs: `C:\Users\xcpu\AppData\Local\Temp\BigCatSharedPolicy-before.log` and
`C:\Users\xcpu\AppData\Local\Temp\BigCatSharedPolicy-after.log`.

## Post-documentation verification

The first verification rerun rejected an absolute checkout path in this new
archive under the existing legacy-identifier lint rule. Only the documentary
path was normalized to `<repo>`; no test or lint rule was relaxed. The second
rerun PASSED (127 files, nested installer checks passed). Total suite command
invocations including these reruns: 18; 17 passed, 1 documentation-lint failure
corrected, 0 skipped. The separate two-process adversarial probe reproduced one
product invariant failure. No test was removed or relaxed.
