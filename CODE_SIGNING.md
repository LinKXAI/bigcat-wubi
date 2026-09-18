# Code signing policy

## Current status

Big Cat Wubi releases are currently **unsigned**. SignPath Foundation has not
accepted the project, no signing credentials exist, and no signing request has
been submitted. No current download may be represented as signed or as carrying
a SignPath Foundation certificate.

The following attribution is reserved for a future release that is both accepted
and actually signed through that service:

> Free code signing provided by SignPath.io, certificate by SignPath Foundation

## Repository and artifact scope

The intended source of record is the public
[`LinKXAI/bigcat-wubi`](https://github.com/LinKXAI/bigcat-wubi) repository. The
only planned signing unit is `BigCatWubi-Setup.exe` produced by
`.github/workflows/build-windows-release.yml` from that public checkout.

Locally built binaries, substituted inputs, self-hosted-runner outputs, and
separately extracted upstream files are outside the signing scope.

The installer aggregates pinned Weasel and `rime-wubi` files under their own
licenses. Signing the outer Big Cat Wubi installer does not relicense, endorse,
or claim authorship or ownership of Weasel, `rime-wubi`, or librime.

## Authors, Reviewers, and Approvers

- **Authors:** maintainers and contributors who prepare source or build changes.
- **Reviewers:** maintainers who review source, validation, dependency inventory,
  build provenance, and release contents.
- **Approvers:** designated maintainers who manually decide whether each future
  signing request may proceed.

Actual people must be assigned to these roles before applying to or configuring
SignPath. Role overlap is allowed only if SignPath permits it and never removes
the separate manual approval required for each signing request.

Every person with repository or SignPath access must enable multi-factor
authentication (MFA) for the relevant account. The repository owner is
responsible for verifying and maintaining this setting.

## Privacy and network behavior

For Big Cat Wubi-owned runtime components and the bundled installer:

> This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.

Bundled installation, normal input, deployment, backup, restore, and uninstall do
not require network access and add no telemetry. A source-tree install using the
explicit `-InstallWubiDependency` option may fetch the official upstream
dependency through Plum or Git. That user-triggered path is outside the bundled
offline installer behavior. Upstream Weasel behavior remains subject to its own
code and documentation.

## Trusted build and manual release approval

- Signing-eligible installers must be built by the source-controlled GitHub
  Actions workflow on a GitHub-hosted `windows-latest` runner.
- The build must use only the public repository checkout and explicitly pinned
  external tools or dependencies.
- Validation, dependency integrity checks, installer SHA-256, and build metadata
  must complete before an artifact can be considered for signing.
- The unsigned artifact is uploaded first with the stable name
  `bigcat-wubi-windows-unsigned`.
- Build success never authorizes signing. An assigned Approver must manually
  review and approve each future signing request.
- The current workflow contains no SignPath request step or secret and does not
  create a tag, publish a release, or upload to a release automatically.

## Certificate and release statements

Until SignPath Foundation accepts the project, the expected state is no code
signature and no SignPath publisher identity. After acceptance, only an artifact
built and approved under this policy may receive the available certificate.

Every release page must state whether the artifact is unsigned or signed, link
this policy, and publish its SHA-256. The SignPath attribution above may be used
only for an artifact that was actually signed after acceptance.
