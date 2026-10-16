# Distribution and Apple alignment

This implementation preserves selective credential handoff.
Recipients retaining a disclosed credential is an accepted product tradeoff.
Expiry bounds future retrieval, not the lifetime of a recipient's copy.

## Supported paths

| Capability | Direct/development bundle | App Store candidate |
| --- | --- | --- |
| Native selective import, unlock, approval, deletion | Implemented | Signed development runtime exercised |
| CLI status, lock, check, host-scoped Git handoff | Implemented | Independently sandboxed client; signed development checks passed |
| `run` with an arbitrary child environment | Supported | Explicitly rejected before IPC |
| Private-pipe importer | Embedded | Not packaged |
| Credential storage | Existing `~/.local/state/keyhatch` | Broker's Application Support inside its sandbox |
| IPC | Existing private socket | Only socket/lock in the entitled App Group container |
| Installation | Self-contained app; optional existing local pilot installer | Xcode archive; no `.local/bin` installation |

The Store client is a nested `KeyhatchClient.app` with its own sandbox,
identifier, and provisioning profile.
It deliberately has no `com.apple.security.inherit` entitlement: Terminal is not
a sandboxed parent whose restrictions the client can inherit.
An arbitrary child of a sandboxed client would inherit restrictions, so the
Store variant cannot promise the direct client's `run` behavior.
Apple describes
[sandboxed helper construction](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
and
[App Group IPC](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups).
The signed development client has passed controlled runtime checks under
`/Applications`.
App Store delivery and review remain separate gates.

Neither variant automatically scans or migrates existing credential stores.
The Store app performs native selective import itself; the external importer
cannot write into the broker's private container.
The client only shares the IPC group, not the broker's credential directory.

## App icon

The app uses the README artwork in `docs/images/keyhatch.svg`.
The checked-in macOS asset catalog supplies the Store app icon; preview and
direct bundles include `Resources/Keyhatch.icns`.
To regenerate both from the SVG, run `python3 scripts/generate-app-icon.py` with
`rsvg-convert` (librsvg) and macOS `iconutil` installed.
Ordinary builds do not need the SVG renderer.

## Build a local self-contained package

```sh
python3 scripts/package-app.py --channel development
```

This builds Release Swift binaries into a fresh directory below
`.build/packages/development-*/Keyhatch.app`, signs them ad hoc with Hardened
Runtime, and validates the package.
It never installs or opens the app, accesses an existing credential, or updates
helper routing.
The direct CLI is `Keyhatch.app/Contents/MacOS/KeyhatchCLI`; capitalized names
avoid a collision with `Keyhatch` on case-insensitive filesystems.

The embedded CLI's `verify-installation` command validates signatures and
configuration without connecting to the broker or accessing credentials.
Do not copy it out of its app bundle.
Existing standalone ad-hoc local pilots retain bounded, owner-only legacy
manifest support, including verification of the client's own pin.

## Direct distribution

```sh
python3 scripts/package-app.py --channel direct \
  --identity 'Developer ID Application: YOUR SIGNING IDENTITY' \
  --team YOUR_TEAM_ID --bundle-id YOUR.REGISTERED.BUNDLE_ID
```

Supply actual enrolled developer values; placeholders fail validation.
The script builds arm64 and x86_64, signs nested code first, adds secure
timestamps, then verifies Apple-issued Developer ID signatures, exact code
identifiers, team consistency, Hardened Runtime, and absence of unnecessary
entitlements.
It includes the importer, privacy policy, privacy manifest, and license.

After human review of the artifact, the explicit release command is:

```sh
bash scripts/notarize-direct.sh /absolute/path/Keyhatch.app NOTARY_KEYCHAIN_PROFILE
```

The profile must already be configured in the user's Keychain; no passwords or
tokens are stored in this repository.
This command sends the artifact to Apple, waits for acceptance, staples the
ticket, and runs Gatekeeper assessment.
Notarization results are retained for review.
Repackage the stapled app for delivery; the original submission ZIP predates
stapling.
The signed direct app was installed locally with user approval; the previous
build was retained for rollback and encrypted credential files were unchanged.
Notarization and public release have not been performed.
See Apple's
[direct distribution requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## App Store candidate

`Keyhatch.xcodeproj` is generated deterministically by
`scripts/generate-xcode-project.py` from the source files.
Regenerate after adding Swift files.
It contains native app, static core, and nested client app targets, with a
shared `Keyhatch Store` scheme.
Full Xcode is required.
Xcode 27.0 has built and archived both universal targets with Apple Development
signing, separate explicit profiles, and the dedicated App Group.
Controlled sandboxed runtime checks passed on the development-signed package;
Apple Distribution profiles and a locally exported Mac Installer Distribution
package also passed static validation.
Store delivery remains a separate gate.

Register a broker bundle ID, its `.client` helper ID, and one authorized App
Group in the Apple Developer account.
Provide separate manually managed distribution profiles for broker and client,
both authorizing that group, and an Apple Distribution identity.
Xcode-managed profiles from automatic export cannot be substituted into this
manual archive command.
Set
`KEYHATCH_TEAM`, `KEYHATCH_BUNDLE_ID`, `KEYHATCH_APP_GROUP`, `KEYHATCH_BROKER_PROFILE`, and `KEYHATCH_CLIENT_PROFILE`,
then run:

```sh
bash scripts/archive-store.sh
```

This archives locally, without automatic account provisioning or submission.
The archive script uses `--static-only`: it validates signatures and
team/identifier consistency without launching archive executables. It also checks sandbox/group
entitlements and provisioning profiles, including their platform, type, expiry,
application IDs and signing certificates for every Mach-O architecture.
A valid signature alone does not establish safe entitlements in another slice.

The broker gets outgoing networking for the explicit identity check.
The client has only sandbox and App Group capabilities.
Neither gets broad filesystem permissions, inbound TCP, Apple Events, sandbox
inheritance, or runtime exceptions.
The importer is absent from the Store package.

### Runtime test location

Use an isolated, provisioned development copy under `/Applications` for signed
Store runtime testing.
Do not overwrite an existing installation.
The independently sandboxed nested client can read its own bundle, but cannot
read the enclosing broker in arbitrary build directories or `~/Applications`.
On the validation Mac, both reads failed with `EPERM`; the unchanged package
passed installation verification and authenticated IPC under `/Applications`.
No filesystem exception entitlement was added.

Run the embedded client's `verify-installation`, then test the GUI and client
together with synthetic data.
`Tests/test-store-sandbox.py --help` describes the opt-in signed probe for App
Group access, private-file isolation, outbound loopback denial and rejection of
a changed client executable.
It uses only a fresh disposable app copy; the original test broker must be
locked.
Static archive validation alone does not establish runtime behavior.
App Store distribution signatures may also require Store installation before
execution, so do not use a failed archive launch as evidence that its static
signatures are invalid.

Xcode Organizer provides the separate App Store
export/upload workflow and appropriate installer signing. `scripts/export-store.sh ARCHIVE_PATH` performs a validated local installer export using the same team/profile settings plus `KEYHATCH_INSTALLER_IDENTITY`.
A local export uses `destination=export`; `destination=upload` is a separate
release action. macOS installer export needs a Mac Installer Distribution
certificate in addition to Apple Distribution.
The direct notarization script is not used for Store submission.

Production bundle trust derives current embedded code hashes after signature
validation, rather than hardcoding pre-upload hashes that Apple could change
when re-signing.
Both peers still authenticate exact current code over IPC, and approvals remain
bound to the client build.
Actual downloaded Store signature behavior is not yet verified.

## Release preparation status

Candidate 0.1.0 build 2 has signed direct and Store packages, a repeatable local
Store export command, release copy,
support/privacy contact and review notes. See [the release checklist](../release/RELEASE-CHECKLIST.md),
[privacy API audit](PRIVACY-API-AUDIT.md),
[lifecycle review](LIFECYCLE-REVIEW.md), and
[independent agent security review](INDEPENDENT-AGENT-REVIEW.md).
The agent review corrected a local FIFO denial-of-service issue; it is not an
external human security audit.

## Remaining release gates

- Review the signed local packages before release.
  Apple Development archives, Developer ID package validation, and Apple
  Distribution installer export have passed their respective local checks.
  No submission or notarization has been performed.
- Extend the signed development runtime evidence to the actual distributed Store
  app.
  Development checks cover group/socket access, authenticated IPC, synthetic Git
  output, denial of `run`, wrong-build client rejection, denied access to a
  broker-private synthetic file and denied outbound loopback access.
  There is no fallback to guessed container paths or legacy storage on failure.
- Extend native
  sleep/expiry and upgrade coverage with synthetic records. Signed development import, biometric unlock, per-record approval, repeated retrieval, cross-host denial, revocation, lock and deletion passed. A failed/cancelled
  authentication attempt preserved locked denial.
  Do not extrapolate these checks to every lifecycle or OS version.
- Icon, candidate
  identity/version metadata, support contact, draft Store copy, policy and review instructions are prepared under `release/`.
  Confirm final policy/support URLs and publisher declarations, and complete
  screenshot export after granting native capture permission.
  The accessible in-app policy is under Help → Keyhatch Privacy.
- The source and final package privacy audit passed for all shipped targets.
  Recheck it when APIs, dependencies or data practices change, and confirm the
  final App Store Connect privacy answers before submission.
  Current declarations cover Store container file metadata and elapsed-time use,
  with no tracking or developer data collection; the audit distinguishes direct
  legacy storage from the Store container reason.
  See Apple's
  [required-reason API guidance](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- Consider a versioned broker-only Data Protection Keychain record for the
  Secure Enclave's wrapped representation, with explicit migration/recovery
  tests.
  This change is not implemented: existing envelope blobs remain protected by
  the enclave's biometric access control and stored alongside ciphertext.
  Do not claim per-app Keychain binding or silently rewrite existing envelopes.
- Obtain independent security review before representing this as a hardened
  credential vault.

These steps address the relevant architecture and packaging requirements, but do
not establish acceptance under Apple's
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## What same-user tampering means

An unrestricted process under the same macOS user can ordinarily modify other
user-writable files.
Reading a locked encrypted credential does not by itself decrypt it.
Deleting or restoring old ciphertext affects availability or rolls back history
and approvals; authenticated encryption does not prevent whole-file rollback.
Replacing deployment code/configuration could instead substitute software before
a future user unlock.

The new production packages remove the mutable trust manifest from the normal
path: trust comes from validated sealed bundle contents and Apple-issued
publisher identities.
Hardened Runtime, production signing, and appropriate container permissions
reduce risk.
They do not make arbitrary user-owned software immutable or defeat every
unrestricted process in the same login session.
Administrator-managed installation ownership can further limit ordinary-user
replacement, but this task neither changes ownership nor installs privileged
helpers.
App Sandbox primarily restricts what the app can do; it is not, by itself, a
universal boundary against unrestricted same-user malware.
Apple also documents a concurrent-modification limitation for
[static code validation](https://developer.apple.com/documentation/security/secstaticcodecheckvalidity(_:_:_:)).
