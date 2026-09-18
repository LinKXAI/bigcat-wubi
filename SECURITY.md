# Security policy

## Supported version

Security fixes currently target the `main` branch and the latest public release
candidate.

## Reporting

Do not post real user dictionaries, keystroke history, private configuration,
backup archives, installation identifiers, or other personal data in a public
issue. A useful report should include:

- the affected component and version;
- minimal reproduction steps and expected impact;
- whether networking, keystrokes, dictionary data, clipboard data, install,
  backup, or restore is involved; and
- a synthetic, de-identified fixture when one is necessary.

Use GitHub private vulnerability reporting when it is enabled. Otherwise,
publish only a non-sensitive summary and ask the maintainers for a private
channel before sharing sensitive details.

Unexpected network access, clipboard access without a direct user action,
unsafe restore behavior, secret exposure, or plaintext logging of complete
input receives high priority.
