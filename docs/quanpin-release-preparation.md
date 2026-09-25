# DEV3 commit, PR and Release Candidate preparation

Date: 2026-09-25. Branch: codex/standalone-quanpin-entry.
Decision: **READY FOR COMMIT / READY FOR RELEASE CANDIDATE**.
SHARED-POLICY-01: **CLOSED**. No new blocker.
[Final acceptance](quanpin-dev3-acceptance.md) separates user-reported human
results, automated evidence and remaining non-blocking items.

## Proposed commit and PR

Commit message: `feat(quanpin): add standalone full pinyin and close DEV3 acceptance`

PR title: `Add standalone full pinyin with fail-closed shared-policy protection (DEV3)`

PR body:

```text
Add independent full pinyin alongside Wubi with offline pinned resources,
first-install entry selection, preserved existing selection/learning, native
Shift raw-code commit, cat icons and formal redeploy integration. Preserve
personal learning during uninstall.

DEV2 could silently shadow a shared luna_quanpin.custom.yaml. DEV3 checks it
before Setup payload copy and wrapper/bootstrap writes, rejecting incompatible
or unsafe shared policy with DM-PINYIN-SHARED-POLICY-CONFLICT. Identical shared
bytes grant compatibility, never ownership.

Validation: DEV3 full automated suite 17/17 commands passed; all 17 original
log hashes rechecked. Final focused reruns: frozen baseline 17/17, shared-policy
regression 56 assertions, repository verify and git diff --check passed.
User-reported Windows Sandbox clean offline Pinyin, DEV2-to-DEV3 learning/
selection preservation and shared-policy rejection all PASS; blocker CLOSED.
Wubi core and PureWubi backup/restore scope remain unchanged; pinyin learning
is excluded. Reboot delayed deletion and the second optional redeploy shortcut
remain recorded non-blocking, not PASS.

The accepted artifact remains 0.9.1-dev.3 / Windows 0.9.1.3, from a dirty
working tree at base 34b1a5f429abbe448160ee1d914d3ece9d5c1e38. Its 47 binary
source inputs match the retained source receipt. Final acceptance documents
were written later and are not contained in the EXE.
```

## Proposed RC identity and retained binary

Recommend release name **0.9.1-dev.3 Release Candidate** and tag
**v0.9.1-dev.3**, promoting the accepted DEV3 artifact to prerelease candidate
status without pretending its embedded version is 0.9.1-rc.1.
No tag or release has been created. The formal VERSION file remains unchanged.
A future rc.1 binary version requires a separately identified build and
acceptance decision, outside this documentation-only closure.

- Asset: `dist/windows/BigCatWubi-Quanpin-0.9.1-dev.3-20260925-191207.exe`.
- Embedded version: 0.9.1-dev.3; Windows version: 0.9.1.3.
- Size: 18312606 bytes.
- SHA-256: `2384C686974DBCBA59CBE3CDA29C788072A58849A2DBA032C57EDE0F6061A8CE`.
- Retain matching `.sources.json`, `.validation.json` and `.validation.md`
  as build-time evidence. Their READY FOR HUMAN RECHECK state is historical;
  accompany them with the final acceptance document when publishing RC.
- Do not use DEV1, DEV2, generic BigCatWubi-Setup.exe or the generic
  build-metadata.json / SHA256SUMS.txt as this DEV3 candidate's identity.

## Exact submission file list

Paths below are relative to the public repository root. This is the whole
uncommitted feature plus acceptance closure, not just this round's edits.
Include all entries, including vendored resources/licenses and the DEV1 fixture.
The exact approved set is staged; no commit, push or PR has been created.

```text
.gitattributes
dependencies/quanpin.lock.json
docs/quanpin-candidate.md
docs/quanpin-dev3-acceptance.md
docs/quanpin-release-acceptance.md
docs/quanpin-release-preparation.md
docs/windows-installer.md
installer/windows/BigCatWubi.iss
schemas/luna_quanpin.custom.yaml
scripts/Bootstrap-Weasel.ps1
scripts/Build-WindowsInstaller.ps1
scripts/Check-QuanpinSharedPolicy.ps1
scripts/DaMao.Quanpin.ps1
scripts/Install-DaMaoWithQuanpin.ps1
scripts/Uninstall-BigCat.ps1
scripts/verify.ps1
tests/DaMaoRimeQuanpinNative.cs
tests/fixtures/quanpin-dev1.custom.yaml
tests/Test-InstallerUninstall.ps1
tests/Test-QuanpinInstall.ps1
tests/Test-QuanpinNative.ps1
tests/Test-QuanpinSharedPolicy.ps1
tests/Test-QuanpinSwitch.ps1
tests/Test-WindowsInstaller.ps1
third_party/rime/quanpin-weasel-0.17.4/default.yaml
third_party/rime/quanpin-weasel-0.17.4/essay.txt
third_party/rime/quanpin-weasel-0.17.4/key_bindings.yaml
third_party/rime/quanpin-weasel-0.17.4/LICENSE.Apache-2.0.txt
third_party/rime/quanpin-weasel-0.17.4/LICENSE.GPL-3.0.txt
third_party/rime/quanpin-weasel-0.17.4/LICENSE.LGPL-3.0.txt
third_party/rime/quanpin-weasel-0.17.4/luna_pinyin.dict.yaml
third_party/rime/quanpin-weasel-0.17.4/luna_pinyin.schema.yaml
third_party/rime/quanpin-weasel-0.17.4/luna_quanpin.schema.yaml
third_party/rime/quanpin-weasel-0.17.4/opencc/t2s.json
third_party/rime/quanpin-weasel-0.17.4/opencc/TSCharacters.ocd2
third_party/rime/quanpin-weasel-0.17.4/opencc/TSPhrases.ocd2
third_party/rime/quanpin-weasel-0.17.4/pinyin.yaml
third_party/rime/quanpin-weasel-0.17.4/punctuation.yaml
third_party/rime/quanpin-weasel-0.17.4/stroke.dict.yaml
third_party/rime/quanpin-weasel-0.17.4/stroke.schema.yaml
third_party/rime/quanpin-weasel-0.17.4/symbols.yaml
third_party/rime/quanpin-weasel-0.17.4/UPSTREAM.md
```

Total: 42 files.

## Excluded products and shortest remaining human actions

`dist/` is ignored and must not be committed: it contains DEV1/DEV2/DEV3 and
generic installer outputs, build/validation receipts and extracted Weasel
runtime. Temporary test logs/fixtures are evidence, not source. No real Rime
learning data belongs in the commit. Vendored OpenCC `.ocd2` resources in the
list ARE intentional source dependencies.

1. Review the exact staged file list and final diff, then decide whether to
   commit and push this branch and open the prepared PR.
2. Before merge, review the PR and any required repository checks. No further
   mandatory Sandbox scenario remains for this release decision.
3. If publishing RC, select the resulting reviewed source commit for the
   proposed tag, recheck the accepted EXE hash and attach that exact binary
   with its source/validation receipts and final acceptance record.
   Keep original working-tree build provenance; do not claim it was built
   from the later commit or contains the later documentation.

No commit, push, tag, PR creation, main merge or release is authorized
by this record. Waiting for the user to decide whether to commit / push /
create the Release Candidate.

## Git byte-preservation closure

Execution readiness: **READY TO COMMIT / READY TO PUSH / READY TO CREATE PR**.

Git EOL normalization under text=auto eol=lf changed 12 verbatim upstream
staged inputs from CRLF to LF (35/47 staged matches), while the authoritative
working-tree inputs remained 47/47. Exact-path -text rules now preserve those
12 resources and the immutable DEV1 fixture. Each also uses
whitespace=cr-at-eol to recognize preserved CRLF during standard diff checks;
diff and merge are not disabled. Ordinary source normalization is unchanged.

Both submission-boundary issues are CLOSED: the index is byte-identical to
the original 47/47 DEV3 inputs, and the acceptance EOF blank line is removed.
This is not a product-logic blocker. The EXE and .sources.json are unchanged;
no rebuild and no new Sandbox recheck. SHARED-POLICY-01 stays CLOSED.

The submission set increases from 41 to 42, adding only .gitattributes.
This preparation document and the existing acceptance record were updated
within that set. All 42 paths are staged and verified against the list above.
Both diff checks, verify (131 files), frozen baseline (17/17) and shared-policy
regression (56/56) PASS. No generated binaries, logs or test outputs are staged.

The .gitattributes and documentation edits are outside the EXE's 47 binary
inputs. See [the byte-preservation audit](quanpin-dev3-acceptance.md#git-byte-preservation-closure-2026-09-25)
for all 12 paths, working/staged SHA-256 pairs and exact evidence boundaries.
No commit, push or PR has been created. This round stops at the READY state.
