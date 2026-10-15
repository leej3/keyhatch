# Contributing to Keyhatch

Small fixes, tests, documentation and design feedback are welcome.
You do not need to buy the app, sign a separate contributor agreement, or assign
copyright.

## License and permission

Unless explicitly identified otherwise, contributions submitted for inclusion in
Keyhatch are offered under the Mozilla Public License 2.0, the same license as
the project.
Contributors retain their copyright.
There is no additional permission for the maintainer to relicense your work
under proprietary terms.
The MPL itself supplies its copyright and applicable patent grants.

When submitting a contribution, confirm in the pull request that you wrote it or
have the right to submit it under MPL-2.0.
Identify copied or adapted code, its source and license, and any required
employer permission.
Keep third-party notices intact.
Do not submit code with unclear provenance or incompatible terms.
AI-assisted contributions need the same review and provenance checks; an
AI-generated label is not a permission grant or a substitute for testing.

Suggested pull request statement:

> I have the right to submit this contribution under MPL-2.0.
> Any third-party
> material and applicable notices are identified in this pull request.

No mandatory account on an additional signing service, copyright assignment,
CLA, or legal attestation by an automated agent is required.
Human submitters should make the statement themselves.
A maintainer checks it before merging.

## Local development

```sh
swift run --scratch-path .build/keyhatch KeyhatchChecks
bash scripts/build-preview.sh
```

Use synthetic data in tests.
Never attach passwords, tokens, encrypted personal vaults, biometric
information, full authentication traces, or private account metadata to issues.
See SECURITY.md for reporting guidance.

Use Conventional Commits.
Documentation is formatted by the local Snapper pre-commit hook; install Snapper
and run `pre-commit install` if using that hook.
Keep changes small and describe what was tested and what remains unverified.

## Distribution

Self-builds and redistribution are allowed under MPL-2.0, including commercial
distribution.
Distributed changes to covered files must meet MPL source and notice
obligations.
Separate new files may use other licenses when permitted by the MPL.
The paid Store build is intended as installation/update convenience, not an
exclusive right to use the source.
Before any binary release, provide the corresponding source and an accessible
source notice.
App Store terms must not impair recipients' MPL source rights; Store acceptance
is not guaranteed.

The authoritative terms are in LICENSE, not this summary.
The license reduces permission ambiguity but cannot prevent litigation or cure
unauthorized code.
