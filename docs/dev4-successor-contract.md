# DEV4 successor acceptance contract

This change implements contract acceptance, not completed native-learning or
installer-release acceptance. Do not build or publish a DEV4 candidate from this
stage. Version metadata and DEV3 Release assets remain unchanged.

## Explicit trust root

`contracts/acceptance.lock.json` selects only Public Baseline V2 and pins the V2
manifest, transition authorization, V1 manifest, historical evidence archive,
successor loader and preflight verifier. No directory scanning, environment
selection or V1 fallback exists. The reviewed lock is the trust root; hashes
cannot protect against an attacker also replacing that root and its verifier.
Review the root and exact diff independently before accepting a future revision.
Neither tests nor production verification regenerate expected pins.

The V2 manifest authenticates the original 17 paths plus an explicitly enumerated
support set. The lock, V2 manifest and transition are upstream authentication
objects, not self-hashed members. No object hashes itself or creates a hash cycle.
Run preflight before executing current behavioral tests. A green historical V1
run is never a substitute for current V2 acceptance.

## Exact transition

Predecessor is commit `97d0d659bbe808d11c0eefa3114ea929e0151e7f`.
Its official schema SHA-256 is
`651A0EA5EE42CABD39F4D38A2C580AA04D7C95604DAC2AE6D67547470536080C`.

Only five frozen paths evolve. The formal schema enables `enable_encoder` and
`encode_commit_history`, and adds explicit `max_phrase_length: 4`. All other
schema bytes, including schema version, identity and dictionary, stay identical.
Each P0-P3 file replaces only the baseline loader filename, loader function name,
and baseline display label (not P2's required historical CI step names).
Business assertions remain unchanged. Transition
verification reconstructs every successor from the pinned historical raw bytes
using the fixed recipe, then compares the complete SHA-256. Schema scalar mapping
assertions are additional checks, not a substitute for byte comparison.

The other twelve frozen inputs, V1 manifest and old validator stay byte-identical.
Production portability continues to use the original V1 identity contract. Both
physical Wubi databases remain separate; no lifecycle reclassification, migration,
merge, rename or import is introduced. Alpha03 remains historical experimental
and validation evidence, not the formal installation entry.

## Independent historical closure

`tests/fixtures/public-baseline-v1/source.zip` is a raw Git archive from the fixed
public commit. It contains the original 17 pins, V1 manifest, original CI workflow,
status CLI, Common helper and P2/P3 native fixture adapters (23 files). Every entry
is enumerated and hashed in V2. It contains no real user data, Git history or
private-repository dependencies. The historical runner extracts to a new system
temporary root; it never overlays current source. The original validator and
original P0-P3 execute there in separate PowerShell processes.

Hermetic historical acceptance needs only Windows PowerShell/PowerShell 7 and the
included closure. Full P2/P3 native acceptance additionally takes an explicit
already-locked local Rime DLL; the runner does not download or silently skip it.
CI retains the V1 step names but now runs this historical closure; current V2 P0
has separately named steps, and current P1-P3 retain their business checks.

## Exact official predecessor installation

Both installers share `DaMao.SchemaUpgrade.ps1` and the shipped
`contracts/wubi-schema-upgrade-v1.json`. An absent target installs; exact DEV4
reuses; exact official predecessor upgrades; all other targets fail with
`DM-RESOURCE-CONFLICT`. Source bytes must also match the successor pin. Version,
schema name, semantic YAML similarity and ownership receipts confer no authority.
The recognized predecessor bytes may also have shipped before DEV3; this is not
proof of installation chronology.

Preflight runs before target writes, and source/target identity is rechecked
before copying. Reparse paths are refused. Shared-policy, dictionary conflict,
rollback, default selection, icon, Shift and uninstall contracts remain in place.
User patches are preserved and diagnosed; a disabling patch reports
`ConflictingLearningOverride`, never functional success. Other patches require
later effective-config and native verification. No learning database is touched.

## Acceptance commands

Run `tests/Invoke-DaMaoAcceptance.ps1`, `tests/Test-DaMaoSuccessorContract.ps1`,
`tests/Invoke-DaMaoHistoricalV1.ps1 -HermeticOnly`, current P0-P3 (P2/P3 with
`-HermeticOnly` or an explicit locked `-RimeDll`), and
`tests/Test-DaMaoSchemaUpgrade.ps1`. Run installer, bootstrap, redeploy, uninstall,
quanpin, SHARED-POLICY-01 regressions, `scripts/verify.ps1` and `git diff --check`.
Negative tests that rewrite child pins or a synthetic root do so only inside
new temporary fixtures to exercise rejection paths. They cannot authorize or
rewrite the repository acceptance lock.

Formal native learning, restart persistence and DEV3 learned-state compatibility
remain mandatory in the next functional stage; synthetic database sentinels here
prove non-mutation only. Contract success does not prove those capabilities.
