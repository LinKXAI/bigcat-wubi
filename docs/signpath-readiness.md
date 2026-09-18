# SignPath Foundation readiness

This is a public readiness checklist. It does not claim SignPath Foundation
acceptance or a current code signature.

| Requirement | Current state | Evidence or remaining action |
| --- | --- | --- |
| OSI-approved licenses | Documented | Big Cat Wubi content is Apache-2.0; upstream components use GPL-3.0, LGPL-3.0, and BSD 3-Clause. See [Licensing](licensing.md). |
| Code signing policy | Documented | [Code signing policy](../CODE_SIGNING.md) records the unsigned state and planned controls. |
| GitHub-hosted unsigned build | Ready for owner run | The manual workflow uses a GitHub-hosted Windows runner, pinned inputs, and an unsigned artifact. |
| GitHub MFA | Owner action | Confirm MFA for every account with repository access. |
| Authors, Reviewers, Approvers | Owner action | Assign actual people and confirm any permitted role overlap. |
| Public release candidate | Owner action | Publish and independently verify the unsigned RC only after public CI passes. |
| SignPath Foundation application | Not submitted | Apply only after the public repository and release are available. |
| SignPath credentials or integration | Not configured | No credentials exist; connect the GitHub integration only after acceptance. |
| Signing request | Not submitted | Add a request step only after acceptance and policy configuration. |

## Release-page wording before acceptance

Use the real policy URL and state the artifact's actual status:

```text
Code signing policy:
https://github.com/LinKXAI/bigcat-wubi/blob/main/CODE_SIGNING.md

Current release status:
unsigned until SignPath Foundation acceptance.
```

The future attribution “Free code signing provided by SignPath.io, certificate
by SignPath Foundation” must not be presented as current until an artifact is
actually signed after acceptance.
