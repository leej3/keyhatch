# Keyhatch release preparation

Candidate: **0.1.0 build 2**.
Prepared for local review, not submitted or released.
The direct and Store editions preserve the same selective-handoff design; the
Store client intentionally omits arbitrary-command execution.

## Prepared materials

- `app-store-metadata.json`: draft field values, explicit unknowns, and manual
  release selection.
  It is not an API upload payload.
- `STORE-DESCRIPTION.txt`: plain-text Store description within the
  4,000-character limit; use only after remaining hardware and release checks
  pass.
- `REVIEW-NOTES.md`: synthetic App Review walkthrough, nested-client
  explanation, hardware requirements and submission decisions.
- `SUPPORT.md`: setup, upgrade approvals, deletion/recovery and issue-reporting
  guidance with support@pythonaisolutions.com for support and private reports.
- `../Resources/Privacy.md`: hostable policy already bundled with the app.
- `../docs/PRIVACY-API-AUDIT.md`: source/API inventory and draft privacy
  answers.
- `../docs/LIFECYCLE-REVIEW.md`: deterministic clock and approval-upgrade
  evidence.
- `../docs/INDEPENDENT-AGENT-REVIEW.md`: separate agent review and FIFO
  rejection fix.
  This is not an external human security assessment.

The repository URLs in the metadata are publication candidates.
Confirm that Apple reviewers and users can open them anonymously and that the
final support page includes actual contact information.
A custom website is optional; a final hosting decision is still required.
Do not publish placeholder contact details.

## Build and export

Build the direct app and archive the Store app using
[distribution instructions](../docs/DISTRIBUTION.md).
For a local Store installer export, preserve the archive's broker/client profile
settings and run:

```sh
export KEYHATCH_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: YOUR NAME (TEAMID)'
bash scripts/export-store.sh /absolute/path/Keyhatch.xcarchive
```

The script exports locally, verifies the installer signature, expands a copy and
validates its signed app.
It never uploads or installs the package.
Signing identities, profiles and private keys remain outside Git.

For direct delivery, notarize a reviewed copy with a preconfigured Keychain
profile using `scripts/notarize-direct.sh`.
After Apple accepts it, staple, validate, and package the stapled copy.
Retain the submission result and the final archive checksum.
The script performs upload and must only be run after specific release
authorization and account configuration.

## Deferred device verification

Do these later with synthetic data and the owner's participation:

1. Native Touch ID success and cancellation on the final candidate.
2. Sleep/wake past session and source expiry, including a paused UI timer.
3. Quit/relaunch, reboot and update with a synthetic encrypted record; confirm
   the app starts locked, retains the record and denies old client approvals.
4. Minimum supported macOS and Intel/Secure Enclave hardware testing if those
   remain supported.
   Both architectures compiling does not establish runtime.
5. Install Apple's delivered build and recheck identity, sandbox, client access
   and credential lifecycle after Store processing/re-signing.

The app does not automatically lock at screen lock or sleep; a still-valid
session can survive a short sleep.
Request-time expiry is independent of the UI timer.
The tests do not establish durable wall-clock/whole-file rollback resistance
across fresh unlocks.

## Owner decisions and external gates

- Confirm delivery and monitoring of support@pythonaisolutions.com and final
  policy/support URLs; private App Review contact name, email and telephone.
- Final copyright owner, pricing, territories, age-rating answers, trader status
  and any required agreements, tax or banking details.
- Confirmation of final privacy responses and encryption export classification.
  No exemption, legal answer, accessibility certification or age rating has been
  guessed or submitted.
- Permission for Apple upload/notarization, Store submission and eventual public
  release; keep release manual until each gate is accepted.
- Independent external security review before describing the product as a
  hardened credential vault.
  Agent review reduces uncertainty but does not replace that assessment.

A broker-only Data Protection Keychain migration remains a design option, not a
release promise.
It needs versioned recovery and migration tests with biometric participation
before changing existing envelopes.
This preparation does not migrate or replace the user's encrypted credentials.

## Apple references

- [Metadata fields and review contact](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Privacy policy and privacy answers](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Mac screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
