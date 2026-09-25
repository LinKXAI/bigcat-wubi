# Locked full-pinyin resources

All 14 runtime resources are extracted verbatim from the already pinned Weasel
0.17.4 Windows installer (see dependencies/quanpin.lock.json for archive paths,
size and SHA-256). No floating revision is read by build or install.

luna_quanpin 0.2 / luna_pinyin 0.26: 佛振 and Rime Developers; dictionary
2024.02.10. stroke schema 0.5 / dictionary 1.1: 四季的風, 雪齋, Kunki Chou
and contributors credited in the retained source headers. Prelude and essay:
Rime Developers. Rime data projects use LGPL-3.0; accompanying GPL/LGPL texts
are retained. Original dictionary provenance/attributions remain in each file.
OpenCC t2s and TS dictionaries: BYVoid/OpenCC contributors, Apache-2.0.

The fixed installer, not an inferred upstream commit, identifies these bytes.
Package source: https://github.com/rime/weasel/releases/tag/0.17.4
License references: https://github.com/rime/rime-luna-pinyin/blob/master/LICENSE,
https://github.com/rime/rime-stroke/blob/master/LICENSE,
https://github.com/rime/rime-prelude/blob/master/LICENSE (informational only;
never used to fetch build dependencies).

Closure: quanpin includes luna_pinyin; both use luna_pinyin dictionary;
stroke dependency references luna_pinyin; dictionaries request essay vocabulary;
prelude imports key_bindings/punctuation/symbols; simplifier uses t2s and its
two TS dictionaries. Optional grammar/custom_phrase/custom patches are not
bundled or replaced. No pinyin-simp, alternate engine, Lua or user DB is bundled.
BigCat's separate luna_quanpin.custom.yaml sets the simplification switch reset
by reproducing the inspected named-switch structure, not an assumed index.

Apache-2.0 applicability checked against the fixed OpenCC ver.1.1.9 LICENSE:
https://github.com/BYVoid/OpenCC/blob/ver.1.1.9/LICENSE . The accompanying standard
license text was copied verbatim from the locally installed cryptography 50.0.1
LICENSE.APACHE (license text only; no cryptography code is a dependency).
Direct shell retrieval failed TLS validation; no TLS checks were disabled.
OpenCC runtime bytes still come only from the pinned Weasel package, not 1.1.9.
