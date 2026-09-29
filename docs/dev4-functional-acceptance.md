# DEV4 formal native learning acceptance

The completed successor-contract stage is documented in
[the contract record](dev4-successor-contract.md). This stage adds formal native
behavioral acceptance and an independent 0.9.1-dev.4 candidate, Windows 0.9.1.4.
It does not change the approved schema bytes or the V1 identity contract.

Run `tests/Test-DaMaoFormalLearning.ps1 -RimeDll <locked-local-rime.dll> -Mode <mode>`
in a separate process for each of Fresh, Upgrade, PatchEncoder and PatchHistory.
The test pins the existing librime 1.13.1 DLL, stages only the Inno application
payload, invokes its Bootstrap flow with synthetic discovery, then the real
dual/formal installers with SkipDeploy. Native deployment uses the same isolated
user directory and an empty shared directory. No host installer, real profile,
registry writes or service changes are used. OS installation remains a human
Sandbox check, not an automated claim.

The formal harness contains no input setter, direct commit or candidate injection.
Codes, page navigation and numbered candidate selection all use process_key.
Actual default sessions must report damao_wubi. The dictionary must exclude the
test words before training. Two characters (U+808C U+9187, emsg), four characters
(U+9701 U+4E91 U+661F U+6E2F, ffji), and the same four followed by U+9CB8 (ffjq)
exercise the four-character maximum before and after normal engine restart.

Upgrade fixtures first deploy the exact immutable DEV3 schema, create positive
single/phrase learning and candidate-frequency changes via real keys, shut down,
and upgrade with the packaged exact-predecessor policy. The DB directory's Windows
volume/file ID and all DB file hashes must remain identical across installation.
Old learning and new native phrases must coexist after restart. No DB is seeded,
copied, renamed or imported; all sync reads are synthetic fixture exports only.

The packaged Get-DaMaoEffectiveLearningStatus checks compiled schema identity,
dictionary, encoder/history and max_phrase_length after deployment. A disabling
user patch is preserved and reports InstalledPreservedAutoPhraseDisabledByUserPatch.
This is successful preservation, not successful auto-phrase acceptance. Missing
or incompatible effective configuration fails, even if source YAML is correct.
SkipDeploy results do not claim any effective capability.

Candidate source receipts bind the V2 lock, transition, all protected inputs,
payload resources, and a conservative complete local compiler-directory inventory
(including unused files). Build checks all hashes again and verifies Git clean
filters would not change any source input, without touching the real Git index.
V1/transition/schema pins are not refreshed. Only reviewed functional support
files receive explicit new pins; this does not redesign portability acceptance.

## Minimum human Sandbox checks

1. In a clean Windows Sandbox, install DEV4, choose Wubi, and check basic typing.
2. Confirm emsg does not contain the new word (U+808C U+9187). Type em, select
   U+808C; type sgyb, select U+9187; type emsg again and find the new phrase.
   Use candidate selection as displayed, not a fixed rank assumption.
3. Restart the input-method service normally; the phrase must remain available.
4. In a separate DEV3 Sandbox, learn an existing candidate repeatedly. DEV3 cannot
   automatically create a new phrase. Upgrade to DEV4, verify that old learning
   remains, then create the new phrase and confirm both survive restart.
5. Use F4 to select full pinyin and confirm normal input.

Do not overwrite user patches to force this check to pass. Do not merge Alpha03
learning. DEV3 Release assets are immutable; DEV4 remains unpublished.
