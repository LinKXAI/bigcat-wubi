# Licensing

This file records the distribution boundary and is not legal advice.

| Component | License | Distribution or use |
| --- | --- | --- |
| Big Cat Wubi original code, configuration, and documentation | Apache License 2.0 | Covered by the repository root [LICENSE](../LICENSE) |
| Weasel 0.17.4 | GPL-3.0 | Unmodified official installer, license, source link, size, and SHA-256 are retained |
| `rime-wubi` pinned source | LGPL-3.0 | Minimal source set is retained with its upstream license, source reference, and integrity metadata |
| librime through Weasel | BSD 3-Clause | Used as an upstream component of Weasel |

The complete Windows installer is not licensed solely under Apache-2.0. Every
upstream component keeps its own copyright, authorship, notices, and license.
The pinned versions, source references, and file hashes are recorded in
`dependencies/windows-installer-v2.lock.json` and under `third_party/`.

The outer Big Cat Wubi installer's current unsigned state, or any future Big Cat
Wubi code signature, does not relicense or claim ownership or authorship of
Weasel, `rime-wubi`, or librime.

Any new component must receive a separate source, license, notice, integrity,
and distribution review before it enters a release. In particular, a future
`pinyin-simp` dependency must not be assumed to be covered by the current
inventory.
