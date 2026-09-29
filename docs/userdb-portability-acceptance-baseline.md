# Public Baseline V1

Historical V1 is immutable. DEV4 current-worktree acceptance explicitly selects
V2 through `contracts/acceptance.lock.json`; see
[the successor contract](dev4-successor-contract.md). The original V1 description
below applies to its independently runnable historical snapshot. Production
UserDB identity authorization still uses V1 unchanged.

`contracts/public-baseline-v1.json` is the only portability baseline selected by
the public repository. It describes the accepted current public source state and
does not refer to or require commits from another repository.

The baseline contains:

- the three independent identity dimensions `logical_role`, `schema_id`, and
  `db_name`;
- the two distinct PureWubi physical identities and their no-merge/no-rename
  coexistence policy;
- the default Pinyin exclusion, rejection of unclassified databases, and an
  empty automatic migration rule set;
- the functional backup, restore, native-version, strict-parsing, ambiguity,
  and privacy invariants; and
- SHA-256 pins for 17 current security- and identity-critical source and test
  files.

Every portability test validates those current files directly. The P0 test also
copies one pinned file into a system temporary directory, flips exactly one byte,
and proves that the baseline rejects it.

There is no old-or-new hash allowlist. A future intentional change requires a
reviewed update to both the implementation and this manifest, with the semantic
impact explained in the change review. Historical engineering evidence is not a
dependency of public builds or CI.
