# DEV3 shared-policy blocker fix and acceptance

DEV3: 0.9.1-dev.3 / Windows 0.9.1.3. No commit, push, tag or release.
Final decision (2026-09-25): **READY FOR COMMIT / READY FOR RELEASE CANDIDATE**.
**SHARED-POLICY-01: CLOSED**. Automatic acceptance and the three minimum human
Windows Sandbox rechecks PASS. Human observations and automated evidence are
recorded separately below. DEV2 remains [historical evidence](quanpin-release-acceptance.md).
See [commit / PR / RC preparation](quanpin-release-preparation.md).

## Reproduced native precedence (before fix)

Both fresh isolated processes used the unchanged locked Weasel 0.17.4 DLL.
Before fixture root:
`C:\Users\xcpu\AppData\Local\Temp\BigCatSharedPolicyReview-64a582f7d1304602bb807b1d5192ce0a`.
After fixture root:
`C:\Users\xcpu\AppData\Local\Temp\BigCatSharedPolicyReview-1cb436934a904b48bf3529449315739b`.

Within each root, the exact shared file is `weasel/data/luna_quanpin.custom.yaml`,
the user file is `user/luna_quanpin.custom.yaml`, and deployed effective config
is `user/build/luna_quanpin.schema.yaml`.
Before installation the shared patch `menu/page_size: 9` is effective (9).
After DEV2 installation, the new user custom file supplies the effective patch,
so the shared-only menu setting disappears and falls back to default 5.
Both native deployments returned True. Shared bytes were unchanged, hash
26024C5F54D5AAAD695EC72CF289C5034FFE402F6388A0DF4270A5500C807E9C.
This is native resolution of the whole same-name custom document, not semantic
merging of its independent patch keys. The old preflight inspected six other
shared custom names and only the USER copy of the full-pinyin custom file.

## Small fix and provenance contract

- `scripts/DaMao.Quanpin.ps1`: one shared-policy guard, called first by the plan.
  A regular, safe-path, byte-identical shared current policy is compatible.
  All differences (including comments or disjoint keys) fail closed with
  DM-PINYIN-SHARED-POLICY-CONFLICT and the conflicting path. No YAML merge.
- `scripts/Check-QuanpinSharedPolicy.ps1`: read-only process entry; nonzero 27
  on failed guard, no Rime discovery of learning contents and no target writes.
- `installer/windows/BigCatWubi.iss`: PrepareToInstall extracts only the guard,
  Common, Quanpin helper and current policy to temporary storage, runs the
  guard hidden, and stops BEFORE copying application payload on failure.
  Inno [ExtractTemporaryFile](https://jrsoftware.org/ishelp/topic_isxfunc_extracttemporaryfile.htm)
  puts each named file in the flat temporary directory used by this guard.
- `scripts/Bootstrap-Weasel.ps1`: repeats the guard before writing installer
  provenance; the wrapper/redeploy path checks again before its first write.
- Build wrapper and candidate defines advance existing candidate mechanism
  to dev.3 / 0.9.1.3, without changing the formal release VERSION or dependencies.
- `tests/Test-QuanpinSharedPolicy.ps1`: six cases, native deployments plus whole
  synthetic target-tree byte/timestamp checks. Temporary Setup payload is also
  exercised as a separate process. No user learning/log contents are accessed.
- `tests/Test-WindowsInstaller.ps1`: exact payload adds only the guard; hidden
  invocation count changes 4 to 5. Weasel installer extraction still occurs
  exactly once only for Absent. Four additional preflight extractions are
  enumerated, not allowed by a wildcard relaxation. No frozen file changes.

Identical shared bytes grant compatibility only, never ownership. If needed,
a local copy is recorded as Add under the USER path; the shared file is not
an owned target and is never changed/deleted. Existing unchanged local DEV2
policy retains its ledger entry; DEV3 has the exact same policy hash
62EB4A300BDF01781B8B4C8D845D355D0D1B7A4002306057077EF0A8FF68991F,
so no byte migration is necessary. User-modified DEV2 is rejected even with
an old ledger. DEV1 upgrade still requires its original hash AND matching
ownership receipt. No new ownership inference is introduced.

No changes to Wubi input, PureWubi scope, luna_pinyin.userdb identity, Shift,
Return/Space, default entry, icons, engine/dependency versions or uninstall.

## Blocker regression cases

| Case | Expected and verified boundary |
|---|---|
| 1 Shared page_size 9 | Explicit conflict before writes; original bytes/timestamps and metadata remain; native effective value 9 before and after rejected install. |
| 2 Exact current shared policy | Allowed; shared bytes untouched; only local copy recorded, native settings unchanged. |
| 3 Unrelated shared patch | Conservatively rejected; original page size and unrelated key still effective in native deployment. |
| 4 DEV2 original plus ledger | DEV3 installation succeeds; same local policy bytes/ledger ownership retained; native Shift unchanged. |
| 5 Modified DEV2 plus old ledger | Rejected; original full target snapshot preserved. |
| 6 Retry after conflict | Same rejection twice, no local policy or ownership receipt created; no false ownership on retry. |

Conflict checks call the wrapper without SkipDeploy: the specific conflict
must occur before any deployment is attempted. Snapshots include default
configuration/schema list, all synthetic learning bytes, metadata, resources,
compiled files and timestamps. Bootstrap provenance and staged Setup guard
are checked independently. Native deployment after rejection is explicitly
performed by the TEST, not by the rejected installer.

## Final human acceptance (Windows Sandbox, user report 2026-09-25)

Source: the user's final DEV3 report for the exact candidate identified below.
The user performed these tests; they are not agent-executed GUI automation.
No independent screenshots, file hash captures or Sandbox logs were supplied.

| Scenario | Human result | Reported observation and conclusion |
|---|---|---|
| DEV3 clean install / default full pinyin | PASS | New clean offline Sandbox, only DEV3 installed; first installer choice was Pinyin (full pinyin). After switching to BigCat, full-pinyin typing worked immediately without F4. Confirms DEV3 clean installation, initial default entry and actual GUI/TSF behavior. |
| DEV2 to DEV3 upgrade preservation | PASS | Another Sandbox: install DEV2, choose Pinyin, establish a learned phrase, then directly install DEV3 over it. Normal input continued and the original learned phrase remained usable. Confirms scheme and luna_pinyin.userdb learning preservation through the installer-owned DEV2 policy upgrade path. |
| Shared luna_quanpin.custom.yaml conflict | PASS | User created the shared custom file with page_size=9. DEV3 explicitly stopped installation with [DM-PINYIN-SHARED-POLICY-CONFLICT]. The message reported shared customization or unsafe inspection, stated installation stopped without changing existing configuration, identified shared data/luna_quanpin.custom.yaml for review/adjustment, and warned against directly deleting personal customizations. User confirmed expected fail-closed behavior. |

**SHARED-POLICY-01: CLOSED.** The reported GUI rejection and isolated
native/no-mutation regression establish protection against silently shadowing
shared page_size=9 with the user-level policy.

The dialog's no-modification statement is a reported UI observation. Whole-tree
byte/timestamp equality and effective native page_size=9 are automated
evidence, not independently reported manual hash measurements. The upgrade's
learned-phrase observation is GUI evidence of preservation; native tests
establish the luna_pinyin.userdb identity.

The previous checklist also suggested extra Shift/xi'an, both F4 entries,
grey preserve-current UI, duplicate-entry checks, upgrade redeploy and manual
before/after hashes. This final DEV3 report does not independently establish
those extra observations. They are not counted as new DEV3 manual PASS and
do not reopen the completed minimum acceptance.

### Remaining recorded non-blocking items

- Reboot / PendingFileRenameOperations delayed-deletion check:
  **NOT EXECUTED / NON-BLOCKING**.
- Optional second (desktop) redeploy shortcut:
  **NOT TESTED / NON-BLOCKING**. The earlier report covered at least one formal
  shortcut without identifying which; the desktop shortcut is optional.
- Fresh default-Wubi GUI first-use, DEV1 GUI upgrade and broader third-scheme /
  custom-resource GUI matrix remain **NOT TESTED / NON-BLOCKING** as previously
  recorded. Native/fixture coverage is separate evidence.
- Ctrl+Shift+2 / menu / mouse equivalence with Shift remains
  **NOT APPLICABLE / NON-BLOCKING**, outside the agreed requirement.

No new blocker was found. Remaining unexecuted items retain their existing
non-blocking status; no unexecuted check is represented as PASS.

## Final automatic results and candidate

These are the completed build-time automatic results. Original local validation
receipts recorded READY FOR HUMAN RECHECK at that time and remain unchanged.
The dated final human acceptance above supersedes that pending decision.

- Full acceptance rerun: **17 commands passed, 0 failed, 0 skipped** (original
  16 plus shared-policy regression). Blocker regression: **56 assertions**.
- verify includes redeploy 16, installer 157, bootstrap 83, uninstall 53.
- P0 frozen baseline 17/17; P1/P2/P3 and Wubi/PureWubi regression passed.
- Native Wubi/Pinyin/DEV1 upgrade: 34 each; Shift historical/current/custom:
  18/23/26. Existing input behavior and luna_pinyin.userdb remain unchanged.
- git diff --check passed. Compiler Inno Setup 7.1.0; build succeeded offline.
- Candidate: `BigCatWubi-Quanpin-0.9.1-dev.3-20260925-191207.exe`.
- Windows version: 0.9.1.3; size: 18312606 bytes.
- SHA-256: 2384C686974DBCBA59CBE3CDA29C788072A58849A2DBA032C57EDE0F6061A8CE.
- Base: 34b1a5f429abbe448160ee1d914d3ece9d5c1e38; branch
  codex/standalone-quanpin-entry; **dirty working-tree build**.
- 47 actual build inputs rehashed successfully against .sources.json;
  base commit alone is NOT the source. Aggregate input digest (UTF-8 lines
  path:size:SHA256 in manifest order, newline-terminated):
  B167C51E0DA244E1763BC71D86040562A7CB960A88F276EB41AD1429CDCFC32F.
- DEV2 remains unchanged, SHA-256
  9FC939A60ECDBE766BF1D9815E335A024DF87EA34EA9F44E209EC9A1F6AA0B05.

Each command below ran in a new Windows PowerShell 5.1 process with
`-NoProfile -ExecutionPolicy Bypass -File`. `<repo>` denotes the public checkout.
These are actual invocations, not proposed tests:

| Command | Exit / outcome |
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
| `tests/Test-QuanpinSharedPolicy.ps1 -RimeDll <repo>\dist\quanpin-work\extracted\rime.dll` | 0 / PASS |

Build command: `scripts/Build-WindowsInstaller.ps1 -QuanpinCandidate -ISCCPath
"C:\Program Files\Inno Setup 7\ISCC.exe"`.

Development diagnostics are not hidden by the final green run: the initial new
harness stopped on normal native stderr and was corrected to capture stderr
while strictly checking child exit codes; intermediate verify runs rejected
outdated exact payload/hidden-process expectations, then passed after explicitly
accounting for the one guard and its staging. No test, frozen hash or safety
requirement was skipped or loosened. The 17/0/0 counts describe the final full
run, not every intermediate development invocation.

Local raw evidence: `C:\Users\xcpu\AppData\Local\Temp\BigCatDev3Acceptance-dd8543d46dd0410e886054d21489f448`.
The candidate .validation.json preserves command arguments and log hashes;
.validation.md links this record. A documentation-only verify is rerun after
writing this record, with its result in the validation receipt.

## Historical archival verification (2026-09-25, before staging)

This round edited acceptance documentation only: the candidate summary, this
record, the release-acceptance archive and Windows installer documentation;
it added the commit/PR/RC preparation document. A before/after file-hash
snapshot confirms no existing code, test, schema, lock or runtime-resource
bytes changed during this round. HEAD remains
34b1a5f429abbe448160ee1d914d3ece9d5c1e38 on codex/standalone-quanpin-entry.
The complete uncommitted submission is 41 files, enumerated in the preparation
document; the index remains unstaged.

| Evidence | Rechecked result / provenance |
|---|---|
| Exact DEV3 EXE | SHA-256 MATCH; 18312606 bytes; Windows 0.9.1.3 |
| Binary source inputs | 47/47 sizes and SHA-256 MATCH before and after documentation edits; zero drift; aggregate B167C51E0DA244E1763BC71D86040562A7CB960A88F276EB41AD1429CDCFC32F |
| Original validation.md / validation.json | Read and cross-checked; preserved unchanged as build-time receipts, including their then-pending human decision |
| Latest full automated set | Existing final 17-command run: 17 PASS, 0 FAIL, 0 SKIP; all 17 raw log hashes rechecked and MATCH; not represented as a new full rerun |
| Original build and post-build documentation verification | Both raw log hashes MATCH their validation receipt |
| Frozen Public Baseline V1 | Fresh P0 run PASS: 17/17, identity valid, mutation probe passed |
| DEV3 blocker regression | Fresh Test-QuanpinSharedPolicy.ps1 run PASS: 56 assertions, 0 failed, 0 skipped; six cases remain present |
| Documentation verification | Fresh scripts/verify.ps1 PASS: 131 files; nested redeploy 16, installer 157, bootstrap 83, uninstall 53 assertions |
| Diff hygiene | git diff --check PASS; verify also checks untracked documentation formatting |
| Wubi core | Existing schemas, Lua/core and frozen files unchanged relative to HEAD; no Wubi core development this round |
| PureWubi backup/restore | Existing backup/restore scripts and portability contract/helpers unchanged; role admits only damao_wubi_alpha03 and damao_wubi physical identities; luna_pinyin.userdb is not admitted |
| Generated output | dist/ and temporary fixture/log outputs excluded from source submission; no real Rime profile accessed or modified |

Binary source inputs and acceptance documentation changes are separate:
none of these five documentation files is in the 47-entry binary manifest.
The EXE does not contain this later acceptance text. No rebuild was necessary;
the original working-tree provenance and source receipt remain authoritative.

Fresh focused commands ran in separate Windows PowerShell 5.1 processes:
tests/Test-DaMaoUserDbPortabilityP0.ps1; tests/Test-QuanpinSharedPolicy.ps1 with
-RimeDll <repo>/dist/quanpin-work/extracted/rime.dll; scripts/verify.ps1.
Only synthetic temporary profiles were used, including native deployments.

Local evidence directory:
C:\Users\xcpu\AppData\Local\Temp\BigCatDev3Final-4ad2679f879d4564913af1564b6dc5c3

| New log | SHA-256 |
|---|---|
| p0.log | 74271B20CAFFB2F28C98556F16E95D523190C66FED3CCDE371222AA3F73E30DE |
| shared-policy.log | 1E57B68ABAB97D9B80D57EE7716AD2A02F0A28B591D672B7192C3E46E914E326 |
| verify.log (after five documents, before this evidence appendix) | E5FC8C80A356D3BDCD90D634B1274CEE78CE5674117872BF664DE7BCACBB44F3 |

The historical full-run totals above are not inflated by these focused reruns.
Final decision: READY FOR COMMIT / READY FOR RELEASE CANDIDATE. Automatic
acceptance PASS; minimum user-performed Windows Sandbox acceptance PASS;
sole blocker CLOSED; remaining untested items are recorded non-blocking.
No staging, commit, push, tag, PR, merge or release has been performed.

## Git byte-preservation closure (2026-09-25)

Execution readiness: **READY TO COMMIT / READY TO PUSH / READY TO CREATE PR**.
The Git EOL normalization blocker and documentation EOF issue are **CLOSED**.
This was a submission-boundary issue, not a product-logic blocker.
SHARED-POLICY-01 remains CLOSED; DEV3 human Sandbox acceptance remains PASS.
No new Sandbox recheck is required because all product bytes are unchanged.

The root rule `* text=auto eol=lf` normalized 12 verbatim locked upstream
inputs from CRLF to LF during staging: working-tree inputs still matched
47/47, but staged blobs matched only 35/47. The immutable DEV1 policy fixture
was also normalized; it is outside the 47 binary inputs and has its own
fixed SHA-256 identity.

Root .gitattributes now adds exact-path `-text whitespace=cr-at-eol` rules
only for those 12 paths and tests/fixtures/quanpin-dev1.custom.yaml.
The generic text policy is unchanged. No binary macro or diff/merge
suppression was added. The narrowly scoped whitespace attribute recognizes
the preserved CR as part of CRLF, allowing standard diff checks without
treating every upstream line ending as trailing whitespace. Ordinary scripts,
Markdown and our own YAML retain text=auto, eol=lf and default whitespace checks.

After changing attributes, an ordinary add initially retained cached normalized
blobs. Only those exact 13 paths were removed from the index with
git restore --staged and added again; no working-tree resource bytes changed.
The acceptance document's extra EOF blank line was removed.
The approved submission increases from 41 to **42 files**, adding only
.gitattributes to the path set. The two existing acceptance/preparation
documents were updated in place. No other source file was modified.

### Raw-byte audit

Each of the 47 source paths was read from the verified .sources.json, the
working tree via raw file bytes, and the index via git show :path captured
as a binary stream. SHA-256 and byte lengths were checked, not diff line counts.
The table identifies the exact 12 paths recomputed from the mismatch set;
both hash columns match the original DEV3 manifest after the fix.

| Exact path | Working raw SHA-256 | Staged raw SHA-256 |
|---|---|---|
| third_party/rime/quanpin-weasel-0.17.4/default.yaml | 5A438C92AA7DDD749644C7C799967074634D41ACE924859BE2A371F29565C892 | 5A438C92AA7DDD749644C7C799967074634D41ACE924859BE2A371F29565C892 |
| third_party/rime/quanpin-weasel-0.17.4/essay.txt | AE37983A4216145A6854375F21016358470C5DCF5AE9F6A54C29801E70B4D824 | AE37983A4216145A6854375F21016358470C5DCF5AE9F6A54C29801E70B4D824 |
| third_party/rime/quanpin-weasel-0.17.4/key_bindings.yaml | 19C52D80A4BF043C16C49FDFEB58CFA4D7A9F2B94BD18C79FF2485BD7627DB5F | 19C52D80A4BF043C16C49FDFEB58CFA4D7A9F2B94BD18C79FF2485BD7627DB5F |
| third_party/rime/quanpin-weasel-0.17.4/luna_pinyin.dict.yaml | DC15421F70E80B5D9DC0339DB79856B671A58F8E6779C1B5B7592B83A57B0817 | DC15421F70E80B5D9DC0339DB79856B671A58F8E6779C1B5B7592B83A57B0817 |
| third_party/rime/quanpin-weasel-0.17.4/luna_pinyin.schema.yaml | A80C89BD16D31842BACBEE6B17B9BA1A4F5FD862B7DB31049A229AED8628299E | A80C89BD16D31842BACBEE6B17B9BA1A4F5FD862B7DB31049A229AED8628299E |
| third_party/rime/quanpin-weasel-0.17.4/luna_quanpin.schema.yaml | 7F48D43A55791A848E0D95F3A43326B9A7F13FEE9D7934E0BF7B1354B3A096CA | 7F48D43A55791A848E0D95F3A43326B9A7F13FEE9D7934E0BF7B1354B3A096CA |
| third_party/rime/quanpin-weasel-0.17.4/opencc/t2s.json | EBE32A6766BFBAEA1869F82368F54A8FC6C977A235E8A896B618714872B5DF09 | EBE32A6766BFBAEA1869F82368F54A8FC6C977A235E8A896B618714872B5DF09 |
| third_party/rime/quanpin-weasel-0.17.4/pinyin.yaml | F2D291166946A848FD88E541844567415F1ED3D9C5A7477757B88AEB3A69C0CA | F2D291166946A848FD88E541844567415F1ED3D9C5A7477757B88AEB3A69C0CA |
| third_party/rime/quanpin-weasel-0.17.4/punctuation.yaml | C9E5147FDA24D1A13085075DF5A2E73DEECB643069BE3751C6D4D793CEB2DE5B | C9E5147FDA24D1A13085075DF5A2E73DEECB643069BE3751C6D4D793CEB2DE5B |
| third_party/rime/quanpin-weasel-0.17.4/stroke.dict.yaml | 0FE1C1C0673F3564F16DEB1F659A75F3AD6A43E5308165DCCFB63FD94864F631 | 0FE1C1C0673F3564F16DEB1F659A75F3AD6A43E5308165DCCFB63FD94864F631 |
| third_party/rime/quanpin-weasel-0.17.4/stroke.schema.yaml | F541D4C7450370B2652AE5E4190396803504EDC987F74F16718458811312F303 | F541D4C7450370B2652AE5E4190396803504EDC987F74F16718458811312F303 |
| third_party/rime/quanpin-weasel-0.17.4/symbols.yaml | D3C1823F0E3BAE5FB2DAC338F4863A0D7164436D1EE132727FF5C4687F53601A | D3C1823F0E3BAE5FB2DAC338F4863A0D7164436D1EE132727FF5C4687F53601A |

DEV1 fixture working and staged SHA-256 both remain
39DFD375B5D8D2EC36FB4D3D54C829F3A3B30603D2E2C636183E55DFFE085E30.

### Re-executed checks

| Check | Result |
|---|---|
| Staged binary source vs working raw bytes vs original manifest | 47/47 MATCH, including all 12 formerly normalized files |
| .sources.json and DEV3 EXE | Unchanged; EXE SHA-256 2384C686974DBCBA59CBE3CDA29C788072A58849A2DBA032C57EDE0F6061A8CE |
| git check-attr for all 13 exact paths | text unset; whitespace cr-at-eol; diff/merge unspecified, not disabled |
| Staged set vs updated preparation list | Exactly 42 paths; no dist, EXE, DLL, logs, generated test output or unknown files |
| git diff --cached --check / git diff --check | PASS with standard settings |
| scripts/verify.ps1 | PASS, 131 files checked |
| tests/Test-DaMaoUserDbPortabilityP0.ps1 | PASS, frozen baseline 17/17, mutation probe passed |
| tests/Test-QuanpinSharedPolicy.ps1 | PASS, 56 assertions, 0 failed, 0 skipped |

.gitattributes and the acceptance/preparation documents are not in the
47-entry EXE binary input manifest. DEV3 was not rebuilt. Neither the manifest
nor the accepted EXE was rewritten to adopt new hashes. The binary still has
its original working-tree build provenance; this index repair preserves
those exact source bytes for the later commit.

Audit scripts, before/after per-file raw hashes and fresh focused test logs:
C:\Users\xcpu\AppData\Local\Temp\BigCatDev3ByteFix-1d461d2f8bc04b61909d1df81e16febc

The initial cached-index mismatch and CR-as-whitespace diagnostic failures
are superseded by the successful exact-path refresh and CRLF-aware checks;
they are not hidden or counted as PASS. No tests or product requirements were
relaxed. Existing recorded non-blocking manual items remain untested, not PASS.

HEAD remains 34b1a5f429abbe448160ee1d914d3ece9d5c1e38.
All 42 approved paths are staged. No commit, push, PR, tag, release or merge
was performed. No real Rime profile was modified. No remaining blocker.
