# DEV4 final acceptance and release preparation

Recorded: 2026-09-29.
Status: READY FOR COMMIT / READY FOR RELEASE CANDIDATE.
No commit or publication has been performed or authorized in this stage.

This post-build archival addendum supersedes the *human-check-pending* status in
[the build-time functional acceptance](dev4-functional-acceptance.md).
That build-time document, the original sources receipt and the original validation
report remain unchanged historical evidence. This new document is not one of the
86 recorded build source inputs and does not change the candidate binary.

## Candidate identity

- File: BigCatWubi-Quanpin-0.9.1-dev.4-20260928-141608.exe
- Windows numeric version: 0.9.1.4
- Size: 18,316,754 bytes
- SHA-256: `17B4D3AA66CC98F840D94F943B046575502CA63A59E37C289D0FC73CEC98D896`
- Formal schema SHA-256: `A618CEAC52FA428C52172FE8042B3CC61F275C25445C74F32A57B5D054457CFA`
- Sources receipt SHA-256: `D41B2E65220B5E9156F65265323E75966F5AB7C4EAFAFF7D4FB2001D72F23A06`

The candidate was not rebuilt. DEV3 remains an immutable historical RC.
The source receipt describes an uncommitted working tree based on
97d0d659bbe808d11c0eefa3114ea929e0151e7f, not that commit's original binary.

## Exact product scope

Only three formal Wubi behavior changes: enable_encoder=true,
encode_commit_history=true, max_phrase_length=4.
schema_id and user_dict both remain damao_wubi; dictionary remains wubi86.
damao_wubi_alpha03 remains a historical experimental/validation identity.
The two user databases are independent: no automatic rename, migration, copy,
import or merge. No Lua or pinyin behavior change.

## Human Windows Sandbox results — user attestation

The following two results were supplied by the user on 2026-09-29, not executed
by the agent. No screenshot, raw database or input log is claimed as supplied.

### A. Clean DEV4 install + formal Wubi native learning: PASS

In a clean Windows Sandbox the user installed this DEV4, selected Wubi first,
and confirmed normal Wubi input. Cold emsg did not contain 肌醇. Normal input
em -> 肌 followed by sgyb -> 醇 produced 肌醇 as an emsg candidate.
After restarting the input-method service, the candidate remained.
F4 switched to full pinyin and normal pinyin input worked.

This confirms automatic phrase construction and restart persistence through
the actual formal damao_wubi installed entry, not Alpha03.

### B. DEV3 -> DEV4 in-place learning compatibility: PASS

In another clean Sandbox the user installed DEV3, generated existing formal
Wubi learning/frequency state, then installed DEV4 over it without uninstalling.
Old learning remained, with no visible discontinuity in damao_wubi.userdb.
New normal submissions 肌 and 醇 produced 肌醇 under emsg.
After a service restart both DEV3 old learning and DEV4 new learning remained.
Full pinyin could still be selected and used.

The human result is observable continuity, not an independent forensic file-ID
measurement. The separate automated upgrade fixture checks DB file bytes and
volume/file ID across installation.

The full historical DEV3 pinyin/uninstall GUI matrix was NOT rerun as DEV4 human
acceptance. It is inherited regression coverage for unchanged relevant behavior,
not a new manual PASS. The current automated installer, bootstrap, redeploy,
uninstall, pinyin and SHARED-POLICY-01 suites are rerun separately below.

## Historical V1 / Current V2

Explicit acceptance.lock.json selects V2. Historical V1 manifest, validator,
snapshot and transition authorization remain unchanged. Of the original 17
protected inputs, only the 5 authorized transitions differ; the other 12 remain
byte-identical. No manifest pin was recalculated in this archival stage.

The historical ZIP is repository contract evidence, not a disposable test
artifact: tests/fixtures/public-baseline-v1/source.zip preserves 23 historical
source files for independent V1 validation.
Its SHA-256 remains
`C50B65D46253E3DF693020671D5515E60F4470AC06E5F90D38599E2662E618D7`.

## Current automatic acceptance

All 35 grouped test invocations completed successfully on 2026-09-29:
35 PASS, 0 failed. Counted assertions total 5,331 (not double-counting reruns).

| Acceptance scope | Passed assertions / result |
|---|---|
| Formal Fresh / Upgrade / PatchEncoder / PatchHistory | 213 / 224 / 73 / 73, each on PowerShell 5.1 and 7; total 1,166; zero failures/skips |
| Successor contract | 33 x 2 hosts |
| Exact installer predecessor | 71 |
| Current V2 P0 | 17/17 integrity and mutation probe, both hosts |
| Current V2 P1 / P2 / P3 | 104 / 153 / 567, each x 2 hosts |
| Historical V1 P0 | 17/17 integrity and mutation probe, both hosts |
| Historical V1 P1 / P2 / P3 | 104 / 153 / 567, each x 2 hosts |
| Additional CI hermetic P2 / P3 | 33 / 90, each x 2 hosts |
| Installer / Bootstrap / Redeploy / Uninstall | 163 / 83 / 16 / 53 |
| Quanpin install / native / switch / SHARED-POLICY-01 | 58 / 34 / 23 / 56 |
| Alpha03 historical static and native | PASS |
| Comprehensive Run-DaMaoTests | PASS |
| verify.ps1, including installer-family tests | PASS; final archive included, 148 files checked |

Skip accounting: the four extra hermetic invocations each deliberately report
NativeSkipped=1 (4 skip markers total); their real native P2/P3 counterparts were
also executed and passed. No required native gate was skipped. P0, Alpha03,
comprehensive suite and verification file counts are not added to the 5,331
assertion sum because they do not use the same counting convention.

Formal tests include punctuation, single-character input, four-code behavior,
existing-word frequency, two/four-character new phrases, rejection of the whole
five-character phrase, restart persistence, in-place old learning continuity and
preservation/diagnosis of user patches disabling encoder or history.
All native work uses independent temporary fixtures and the existing locked
local librime dependency; no host Rime learning data or service is modified.

## Final byte-preservation audit

- Existing EXE size, numeric version and SHA-256 match the identity above.
- Working-tree raw bytes vs recorded sources: 86/86 MATCH (path, size, SHA-256).
- Actual staged index blob bytes vs working tree and receipt: 86/86 MATCH.
- All 32 changed/new staged files match their working-tree raw bytes.
- All 135 recorded local compiler files still match their size and SHA-256.
- git diff --cached --check and git diff --check pass.
- git check-attr --cached was executed for all 86 inputs; existing exact-path
  upstream -text rules and the historical ZIP binary rule remain unchanged.
- verify.ps1 passes after staging. No schema, baseline, transition, build-time
  document or source-receipt hash was refreshed to accept drift.
- This addendum is the only new post-build document. It is explicitly outside
  the 86 build inputs, and is separately included in the staged-byte audit.

An initial whitespace check found an extra blank line at this new document's
EOF. It was removed before the successful audit; no build input was modified.
No binary mismatch or identity/portability blocker was found.

## Commit boundary

Exactly 32 files are intended for this commit, listed below. This includes the
31 implementation/contract files from the completed DEV4 work and this one
post-build acceptance addendum. No unrelated file is authorized.

```text
.gitattributes
.github/workflows/validate.yml
contracts/acceptance.lock.json
contracts/dev4-transition.json
contracts/public-baseline-v2.json
contracts/wubi-schema-upgrade-v1.json
docs/dev4-final-acceptance.md
docs/dev4-functional-acceptance.md
docs/dev4-successor-contract.md
docs/userdb-portability-acceptance-baseline.md
installer/windows/BigCatWubi.iss
schemas/damao_wubi.schema.yaml
scripts/Build-WindowsInstaller.ps1
scripts/DaMao.SchemaUpgrade.ps1
scripts/Install-DaMao.ps1
scripts/Install-DaMaoWithQuanpin.ps1
scripts/verify.ps1
tests/DaMao.AcceptancePreflight.ps1
tests/DaMao.SuccessorBaseline.ps1
tests/DaMaoRimeWubiLearningNative.cs
tests/Invoke-DaMaoAcceptance.ps1
tests/Invoke-DaMaoHistoricalV1.ps1
tests/Run-DaMaoTests.ps1
tests/Test-DaMaoFormalLearning.ps1
tests/Test-DaMaoSchemaUpgrade.ps1
tests/Test-DaMaoSuccessorContract.ps1
tests/Test-DaMaoUserDbPortabilityP0.ps1
tests/Test-DaMaoUserDbPortabilityP1.ps1
tests/Test-DaMaoUserDbPortabilityP2.ps1
tests/Test-DaMaoUserDbPortabilityP3.ps1
tests/Test-WindowsInstaller.ps1
tests/fixtures/public-baseline-v1/source.zip
```

Categories: attributes/CI wiring; four new successor/upgrade trust contracts;
production schema and installer changes; acceptance loaders/validators;
formal native tests and portability wiring; portable documentation; immutable
V1 historical source evidence.

Do not add dist/, generated EXE/DLL, native extraction, temporary logs,
runtime databases, test output, work/ investigation folders or machine-specific
absolute-path reports. Pre-existing tracked vendored binary dependencies remain
unchanged in the index and are audited as build inputs; they are NOT newly
staged binary changes.

## Suggested subsequent actions (not performed)

- Commit: `feat(wubi): enable native phrase learning with V2 acceptance contract`
- PR: `Enable native phrase learning for production Wubi with V2 baseline transition (DEV4)`
- RC tag: `v0.9.1-dev.4`

After final byte audit, review this exact staged diff and obtain explicit
authorization for commit/push/PR. Review and merge through the normal workflow;
recheck the same candidate identity before a separately authorized tag/release.
Do not rebuild merely to change Git line endings. Any source change requires a
new scope/identity review, not automatic manifest refresh.
