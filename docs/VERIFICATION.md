# Verification record

## Signed packaging and sandbox validation — 2026-10-15

- Apple Developer membership and Certificates, Identifiers & Profiles access
  became active.
  Created approved Apple Development, Apple Distribution, Developer ID
  Application and Mac Installer Distribution certificates, keeping their private
  keys in this Mac's Keychain.
  No existing certificate was revoked.
- Configured explicit broker and client identifiers, a dedicated provisioned App
  Group, and separate development and distribution profiles.
  Signing material is outside Git.
  Fixed generated Xcode capability declarations and enabled App Group
  registration so automatic provisioning obtains explicit profiles.
- Xcode 27.0 built a universal Apple Development archive.
  Local App Store export succeeded with Apple Distribution signatures and a Mac
  Installer Distribution installer signature.
  `pkgutil --check-signature` verified its Apple-issued installer chain; strict
  all-architecture nested-code validation, exact entitlements, profile
  identity/group/certificate matching and privacy resources passed on the
  extracted payload.
  The installer was not installed.
  The repository's manual archive command also passed using two separately
  generated, manually managed distribution profiles.
- A universal Developer ID package passed publisher, secure-timestamp, Hardened
  Runtime, resource and executing-client validation.
  It was not notarized or installed as the live credential deployment.
- Fixed release-validator compatibility with current `codesign`: explicitly
  request XML entitlements and use the certificate extraction prefix's `=`
  syntax.
  Entitlement extraction and rejection regressions passed.
- A separate review found that signature validity across architectures did not
  establish matching entitlements or identities.
  The validator now inspects every Mach-O slice, including exact Store
  application/team entitlements and the profile's authorized signer.
  Real universal-binary regressions rejected an extra entitlement, missing
  Hardened Runtime and wrong identifier confined to the non-native slice, while
  all cryptographic signatures remained valid.
  Both Store artifacts and the Developer ID package passed the stricter checks.
- Separated static archive checks (`--static-only`, explicitly reported) from
  executing-client checks.
  The signed nested client could not read its enclosing broker under `.build` or
  `~/Applications` (`EPERM`).
  An unchanged isolated copy under `/Applications` passed.
  No sandbox exception or trust bypass was added; the CLI now explains this
  location requirement on installation-check failure.
- Using the signed development copy under `/Applications`, native synthetic
  import and Touch ID unlock succeeded.
  The broker and client authenticated in both directions; retrieval was denied
  while locked and before approval.
  Explicit per-record approval allowed three exact synthetic Git handoffs;
  cross-host requests were denied.
  No secret output was logged and no remote authentication request was made.
- Native revocation denied further retrieval; CLI lock returned the broker to
  locked denial.
  A subsequent failed/cancelled authentication attempt left the encrypted data
  intact and retrieval locked.
  Native deletion removed the synthetic record and history, leaving the new
  sandbox store empty.
- The opt-in signed sandbox harness passed: App Group scratch write/removal,
  denied open of the known synthetic file in the broker's private container,
  denied outbound loopback connection with an unsandboxed positive control, and
  immediate rejection of a changed, validly signed client executable by the
  authenticated original broker.
  The broker stayed responsive and locked.
  Probe signatures used unchanged client entitlements; the disposable probe
  bundle was removed.
- These runtime results cover arm64 on this Mac and development provisioning.
  They do not establish App Store
  download/re-sign behavior, x86_64 runtime, all supported macOS versions, native sleep/expiry/upgrade coverage, or review acceptance. Earlier deterministic expiry/rollback
  checks remain separate evidence.
  No real credential installation or helper routing was replaced.

## Full Xcode archive validation — 2026-10-15

- Xcode 27.0 (27A266a) completed first-launch setup and recognized the Store
  scheme and all three native targets.
- Release build and archive succeeded with `CODE_SIGNING_ALLOWED=NO` for both
  arm64 and x86_64.
  The archive is for structural validation only; it retains placeholder
  identifiers and cannot be distributed.
- Added the Utilities category to both Store bundles, clearing Xcode's missing
  category warnings.
  The remaining App Intents metadata notices report that neither executable uses
  AppIntents.framework.
- Verified the archive application path, nested client placement, executable
  names, universal architectures, privacy resources and license.
  The external importer is absent.
  The release validator correctly rejects this unconfigured archive because no
  developer team is set.
- No local code-signing identities or provisioning profiles were available.
  Signing, provisioning, sandboxed runtime and Store submission remain pending.
- Core checks rebuilt and passed with the Xcode toolchain: all 18 policy checks
  and the storage, expiry, client-input, deployment and bundle-trust groups.
- No packaged app was launched and no credential store was accessed by these
  build and archive checks.

## Distribution alignment — 2026-10-15

- Debug products and a self-contained Release development app compiled.
  Nested signatures, Hardened Runtime, bundled privacy resources and the
  embedded client's installation verification passed.
- Core checks passed, including new source-expiry, deployment-path rejection,
  inactive-record deletion and bounded legacy trust-file groups.
- Separate-process IPC checks passed, including authenticated malformed,
  oversized, truncated and stalled frames, with broker recovery after each.
- Temporary sealed-bundle tests rejected altered metadata, nested signature
  replacement, ad-hoc production identity, and fallback from broken bundles.
- Release-validator tests rejected mismatched distribution channels, altered
  resources, missing Hardened Runtime and a debug entitlement.
- Native import, cancellation and deletion controls compiled; lifecycle review
  scoped cancellation to its originating form and changed the credential UI to a
  single window to prevent cross-window consent changes.
- Generated Xcode project, scheme and entitlement property lists passed
  structural checks; shell/Python syntax, Snapper and Git whitespace checks
  passed.
- Full Xcode was unavailable during this earlier pass.
  No Store archive, Developer ID signing, provisioning, notarization, Store
  download/re-sign behavior or sandboxed runtime was verified.
- No GUI was launched, biometric prompt triggered, credential store accessed,
  installed app replaced, or routing changed.
  Native import/unlock/delete and exact-host network behavior still need
  controlled packaged-app testing.

See [distribution instructions](DISTRIBUTION.md) for the distinct direct and
Store paths, supported commands and remaining release gates.

## Local replacement pilot implementation — 2026-10-15

- Added same-user, kernel-audit-token/code-hash authentication in both
  directions on an owner-only Unix socket.
  The app pins the CLI and the CLI pins the app.
  Both installed executables use hardened ad-hoc signatures.
- Separate-process synthetic integration checks passed: mutually authenticated
  connection, wrong-client denial, wrong-server denial, untrusted malformed
  client rejection, duplicate-listener rejection, stale-socket recovery.
- The 18 existing policy checks plus
  storage/crypto check groups pass. Added checks for Git host/account/protocol/duplicate-field
  rejection, bounded input, environment names and code-hash-bound approval
  expiration.
- Added private `run` injection, host-scoped Git helper, check/status/lock,
  encrypted persistent CLI approval/revocation and pre-release audit writes.
- Installed versioned local releases with a stable CLI symlink.
  Previous releases and the existing Agent Vault remain intact.
  No source credential was refetched.
- Live installed-client checks verified mutual authentication, locked denial,
  denial after unlock without approval, and locked state after app restart.
- Following explicit user approval, the installed CLI delivered the selected
  real credential privately to a child process and Git credential fill.
  The values matched without being printed.
  Three repeated checks passed without another approval; cross-host CLI and Git
  requests were denied.
- Native revocation denied both check and run; re-approval restored access
  without changing source expiry.
  The child exit status was preserved.
  CLI lock denied further access, and app restart began locked.
- The live CLI-driven HTTPS identity check timed out.
  A separate credential-free request also timed out before establishing a
  connection.
  This does not prove an authentication failure or successful remote use from
  the CLI.
- After post-restart Touch ID, the encrypted approval persisted and CLI check
  succeeded without re-approval.
  The original source expiry was unchanged.
- Selected-host cutover remains pending successful remote verification.
  Existing credential helpers have not been changed.
  Do not call the replacement complete.

## Selected real-data development path — 2026-10-15

- MPL-2.0 license installed from Mozilla's canonical plain-text license; source
  identifiers and same-license contribution instructions added.
  No copyright assignment or proprietary-relicensing CLA introduced.
- All 18 policy checks pass, plus three real-data check groups: strict identity/
  expiry validation; AES round trip, wrong key and tamper rejection; owner-only
  atomic file storage, file locking and unsafe-path/permission rejection.
- Native app and importer compile.
  The real-data tab launches.
  Core dumps are disabled before sensitive operations; storage permissions
  checked as 0700 for the directory and 0600 for the encrypted file.
- The user-selected credential was imported through a private pipe from its
  existing cache into a new hardware-wrapped file outside Git.
  No raw credential was printed, no bulk import performed, and source expiry was
  preserved.
- A Keyhatch unlock prompt was requested.
  The subsequently observed app state was Locked; no successful real-data unlock
  or remote authentication result has been observed yet.
  Do not treat import success as end-to-end verification.
- Known security issues and release blockers are in SECURITY.md.
  Agent IPC is not enabled; this is not a completed production broker or
  independent audit.

## Keyhatch test drive — 2026-10-15

- Renamed product and repository to Keyhatch; new repository path is
  `/Users/johnlee/code/keyhatch`.
- `swift run --scratch-path .build/keyhatch KeyhatchChecks`: 18 checks pass,
  including repeated retrieval on one approval across session renewal, grant
  revocation, and expiry of grants without a use-count limit.
- `bash scripts/build-preview.sh`: renamed app builds and launches.
  Native UI displays the selected tagline and three-day reusable approval
  controls.
- During the user test drive, the native UI reported
  **“Hardware round trip succeeded on this Mac.”** The round trip uses a random
  synthetic payload and the hardware-only EnclaveVault path.
  No software fallback exists in that path.
  The agent observed the success state; it did not inspect biometric input.
- That result does not establish persistence across relaunch, cancellation
  behavior, enrollment-change recovery, production signing, or App Store
  support.
- No real Passwords ingestion or existing Agent Vault migration was performed.

## Earlier foundation verification — 2026-10-14

Development machine: Apple Silicon macOS; Apple Swift 6.4 Command Line Tools.
Verified 2026-10-14.
No personal credentials were accessed.

## Passed

- `swift run HandrailChecks`: 16 checks passed.
  Includes default denial, missing grant, exact scope, zero-use grant, budget
  exhaustion, revocation, lock, session/grant/cache expiry, future fetch
  rejection, wall/monotonic clock rollback, independent monotonic deadline,
  retention across renewal, new grant following revocation, and rejection of
  unsupported envelope versions.
- `swift build --product Handrail`: native dashboard and CryptoKit/Security
  implementation compiled successfully.
  Command Line Tools emitted linker warnings about absent optional developer
  framework search paths.
- `bash scripts/build-preview.sh`: local ad-hoc app bundle built successfully.
- Native UI check: load notice identifies synthetic service/account; request
  denied before approval; two permitted uses followed by budget-exhausted
  denial.
  Review rows and grant usage count visibly match the sequence.
  Layout inspected.
- Snapper pre-commit formatting and Git whitespace checks.

## Not verified / not implemented

- No live Secure Enclave operation or biometric prompt was triggered.
  Compilation does not prove signing/provisioning, biometric enforcement, or
  hardware use.
- No Apple Passwords ingestion, real credentials, remote service requests,
  authenticated IPC, durable storage, or migration has been tested or enabled.
- The preview is not sandboxed, hardened, provisioned, notarized or Store-ready.
- This is not an independent security audit or proof of agent containment.

## Toolchain adaptations

The initial XCTest target could not compile because this Command Line Tools
installation lacks XCTest.
The dependency-free executable checks replace it.
This SDK also exposes a SwiftUI State macro without its plugin in Command Line
Tools; a type alias explicitly selects the stable State property wrapper.
The resulting dashboard build and UI interactions passed.
