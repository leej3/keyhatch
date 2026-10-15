# Verification record

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
