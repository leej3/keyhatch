# Implementation plan

## Product decisions

- Apple Passwords stays the durable credential source; no competing synced
  vault.
- Five-hour fixed unlock window; explicit renewal requires fresh authentication.
- Three-day retention from acquisition, not last access.
  Renewal never changes it.
- Loading a credential visibly identifies service, account, source, requesting
  client, purpose, expiry and access scope.
  Never display the password itself.
- No broad automatic imports.
  User approves a narrowly scoped grant once, followed by permitted uses without
  repeated approval during the grant window.
- Global lock, per-grant revoke, per-credential forget, review and export of
  sanitized audit metadata.
  Clearly distinguish local revocation from remote credential rotation.
- No telemetry or cloud account by default.
  A paid signed build is convenience, not a subscription gate around built-in
  Passwords.

## Milestones and acceptance gates

### 1. Foundation (this repository)

Policy tests, hardware envelope source, synthetic SwiftUI dashboard,
architecture, and naming exploration.
Compile/test without touching existing credentials.
Do not label the app production-ready or hardware-verified based on unit tests.

### 2. Signed hardware vertical slice

Create a proper app and broker target with a chosen developer
team/bundle ID, least-privilege entitlements and supported signing/provisioning.
Hardware key operations must succeed in that deployment configuration, including
after relaunch.
Test approval, cancellation, biometric enrollment change, unavailable hardware,
corrupted envelopes and a missing key.
No silent key regeneration.

Use only synthetic credentials until these checks pass.
Keep a separate test container; do not migrate or reset the existing Agent
Vault.

### 3. Durable broker and trusted user controls

Private atomic encrypted storage, serialized
policy/release transaction, native secret ownership, fixed session deadline, lock-on-restart, and cleanup. Verify that cancellation/lock/expiry
during an operation prevents delivery.
Validate IPC peer code identity using OS-supplied audit identity; never accept a
client name as proof.
Bind grants to an authenticated client and scoped operation.

The broker must own the grant store.
Agents cannot approve grants or extend windows by editing JSON.
Policy-changing UI paths need their own trusted authorization boundary.
Test simultaneous unlock/renew/load requests.

### 4. Passwords ingestion and visible load review

Investigate public user-mediated Passwords/AutoFill integration in the actual
sandboxed target.
Validate what Apple supports before promising universal CLI access.
Keep any separately installed developer bridge outside the repository and app
bundle.
Never copy personal bridge setup or secrets into this repo.

If the supported App Store path cannot provide the intended experience, document
a direct-distribution variant rather than relying on undocumented interfaces in
the Store build.
No bulk CSV export as a default workaround.

Record load intent before acquisition, success/failure after acquisition, and
make a persistent in-app activity item even when notifications are disabled.
Mask sensitive account details in lock-screen notifications.
Coalesce same-entry loads; do not repeatedly prompt after cancellation.

### 5. Agent adapters and damage control

First ship one narrowly defined operation adapter with fixed HTTPS destination,
validated method/path/body, no arbitrary headers, no redirect credential
forwarding, no arbitrary proxy/URL selection, bounded response and rate limits.
Use fake servers to test exfiltration attempts and confused-deputy behavior.

Compatibility credential delivery is a separate explicit opt-in, visibly marked
“recipient can retain this credential.”
Prefer service-specific least-privilege tokens and short-lived credentials.
Do not pretend a request-count budget limits what a recipient can do after
receiving a reusable password.

### 6. Review dashboard and migration

Live pending loads, active grants, cache expiry,
uses/denials, anomaly summaries, revoke/lock/forget controls and bounded audit
retention.
Durable metadata should be encrypted and treated as private.
Test notification failure and disk-full: if required recording fails, deny
release.
Local logs are not tamper-proof against an attacker with equivalent authority.

Only after end-to-end verification, offer an explicit selective migration from
the existing vault.
Preserve rollback, do not delete its key/data, and do not change global Git
configuration without explaining the change.

### 7. Release

Confirm name, license, copyright attribution, developer
account/team, one-time price and store strategy. Independent security review, reproducible build instructions, signed/notarized
distribution as appropriate, privacy policy, recovery guide, supported
OS/hardware matrix and App Review evidence.
Publish only after the owner chooses the destination and approves public
release.

## Immediate next step

Select a signing team and validate the synthetic hardware vertical slice in a
proper app bundle.
This machine currently has Command Line Tools selected, not a full Xcode
installation.
Actual entitlement/provisioning requirements must be tested for the selected
bundle and distribution method; compilation alone is not that test.
No account purchase or signing identity changes are authorized by creating this
development repository.
