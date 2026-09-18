# UserDB identity policy

The public identity contract is part of
[Public Baseline V1](userdb-portability-acceptance-baseline.md) and is stored in
[`contracts/public-baseline-v1.json`](../contracts/public-baseline-v1.json).

Three fields remain independent:

- `logical_role`: the policy group that explicitly admits physical databases;
- `schema_id`: the Rime input-schema identifier; and
- `db_name`: the physical librime user-dictionary database name.

`PureWubi` contains two compatibility identities:

| Identity | Schema | Physical DB | Lifecycle |
| --- | --- | --- | --- |
| `purewubi.alpha03` | `damao_wubi_alpha03` | `damao_wubi_alpha03` | current |
| `purewubi.legacy` | `damao_wubi` | `damao_wubi` | legacy |

The `alpha03` string is a persisted compatibility identity, not a public release
stage. The two databases may coexist and must be detected, backed up, and restored
separately. Their common logical role does not authorize automatic merge, rename,
or migration.

`damao_wubi_pinyin` is excluded by default. It can participate only if a future
reviewed baseline explicitly assigns it a logical role. Unknown databases are
rejected as unclassified rather than guessed from their names.
