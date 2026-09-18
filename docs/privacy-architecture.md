# Privacy architecture

## Runtime boundary

Normal typing is local:

```text
keystrokes -> Weasel / librime -> system dictionary + local user dictionary
           -> candidates -> committed text
```

Big Cat Wubi adds no telemetry, cloud candidates, account service, advertising,
input-log upload, or background clipboard monitoring. User dictionaries and
their learned frequencies remain in the local Rime user directory unless the
user explicitly copies or backs them up.

## Network behavior

The network boundary depends on how the product is used:

- **Bundled Windows installer:** includes the pinned Weasel and `rime-wubi`
  inputs required for installation and redeployment; no network retrieval is
  required.
- **Normal runtime typing, backup, and restore:** no Big Cat Wubi network request
  is required or added.
- **Source-tree dependency install:** when the user explicitly passes
  `-InstallWubiDependency`, the script may ask Plum or Git to retrieve the
  official upstream `rime-wubi` dependency.

This project therefore does not claim that every possible installation command
makes zero network requests. Upstream Weasel behavior remains independently
governed by its code and documentation.

## Data classes

| Data | Typical location | Handling rule |
| --- | --- | --- |
| Configuration | Rime user directory | Local; user-controlled |
| User dictionary and frequency data | `*.userdb*` | Local, sensitive, never committed |
| Installation identity | `installation.yaml` | Local, not included in reports or releases |
| Backup package | User-selected location | Sensitive; contains learned dictionary data |
| Test fixtures | System temporary directories | Synthetic only; removed after tests |
| Diagnostics | Console and structured receipts | No phrases, codes, full keys, or user IDs |

## Clipboard and future network features

No current Big Cat Wubi path needs clipboard history. Any future clipboard
feature must require a direct user action and must not poll, subscribe to, or log
clipboard contents. Any future networked feature requires a separate opt-in
boundary, disclosure of transmitted data, threat modeling, and tests proving
that offline typing remains complete.
