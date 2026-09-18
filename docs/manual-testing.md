# Manual Windows testing

Use a disposable Windows account or Windows Sandbox. Do not use real user data as
a fixture.

1. Verify the installer SHA-256 against the release page.
2. Install Big Cat Wubi without network access and confirm that Weasel 0.17.4 is
   installed only when a usable Weasel is absent.
3. Select `大猫输入法`, type known 五笔 86 codes, choose candidates, and verify
   punctuation plus direct ASCII/English input.
4. Run the environment check:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Test-DaMaoEnvironment.ps1
   ```

5. Create a synthetic learned entry, back up the user dictionary, and restore it
   into a separate disposable account. Confirm the learned candidate remains and
   unrelated user data is untouched.
6. Test both uninstall choices: retain Weasel, and remove a Weasel installation
   that Big Cat Wubi demonstrably installed. Confirm uncertain ownership defaults
   to retention.
7. Record Windows version, installer SHA-256, Weasel version, commands, and any
   diagnostics. Remove personal paths and identifiers before sharing results.

Known cosmetic issue: ASCII/English input works, but the displayed schema icon
may remain the Big Cat icon rather than changing to the intended “A” icon.
