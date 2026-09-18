# Changelog

## Big Cat Wubi 0.9.0 RC1 (v0.9.0-rc1)

This is the first public Windows release candidate.

Release identity: `v0.9.0-rc1`. Installer / Installed Apps display version:
`0.9.0 RC1`. Windows numeric file and product version: `0.9.0.0`.

- Windows 五笔 86 input based on Rime/Weasel;
- local, private user-dictionary learning with no Big Cat Wubi telemetry;
- bundled official Weasel 0.17.4 and pinned `rime-wubi` source inputs;
- offline installation and redeployment capability;
- user-dictionary backup and verified restore, including pre-restore safety
  backup for an existing target;
- uninstall choices that distinguish Big Cat Wubi-owned files from Weasel and
  user data;
- unsigned installer: Windows SmartScreen may show an unknown-publisher warning;
- [code signing policy](CODE_SIGNING.md) prepared for a future SignPath
  Foundation application, with no current acceptance or signing request;
- known cosmetic issue: ASCII/English mode works, but the schema icon may remain
  the Big Cat icon instead of changing to the intended “A” icon;
- upstream licenses retained: Weasel 0.17.4 under GPL-3.0, pinned `rime-wubi`
  source under LGPL-3.0, and librime through Weasel under BSD 3-Clause.
