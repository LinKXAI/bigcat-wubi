# Contributing

Thank you for helping improve Big Cat Wubi. Please open an issue or pull request
that explains the user-visible problem, the proposed change, and the Windows and
Weasel versions used for testing.

## Requirements

1. Keep normal typing and user-dictionary data local. Do not add telemetry or
   upload keystrokes, committed text, phrases, frequencies, or dictionaries.
2. Never commit `*.userdb`, `*.userdb.kct`, `*.userdb.txt`, `installation.yaml`,
   `user.yaml`, real backups, credentials, or local build output.
3. Document every new dependency, including its purpose, license, integrity
   pin, network behavior, and whether it enters the typing path.
4. Preserve Public Baseline V1 portability invariants. A deliberate change to a
   pinned file must update the manifest and explain the semantic impact.
5. Keep user-facing text UTF-8 without BOM and repository text LF-only.

Run the relevant checks before submitting:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/Run-DaMaoTests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-DaMaoUserDbPortabilityP0.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-DaMaoUserDbPortabilityP1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-DaMaoUserDbPortabilityP2.ps1 -HermeticOnly
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-DaMaoUserDbPortabilityP3.ps1 -HermeticOnly
```

Never use real user data as a test fixture. Construct the smallest synthetic
fixture that demonstrates the behavior.
