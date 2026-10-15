# Handrail

Your passwords.
A smaller reach for your agents.

Handrail is a working name for an open-source macOS credential broker.
Apple Passwords remains the source of truth.
Handrail is intended to mediate which credentials an agent may use, for how
long, and for which operations, with a visible activity feed and a review
dashboard.
No hosted vault or subscription service is part of the proposed design.

## Status: development foundation, not a production vault

Implemented here:

- A native SwiftUI review preview with **synthetic data only**, visible load
  notices, explicit grants, usage budgets, revocation, lock, and request
  history.
- A tested policy core: deny by default, exact client/credential/destination/
  operation matching, five-hour sessions, and three-day non-sliding retention.
- A hardware-only Secure Enclave envelope implementation using CryptoKit P-256
  key agreement, HKDF-SHA256 and AES-256-GCM.
  Private-key use requires the current biometric enrollment.
  There is no software-key fallback.
- An opt-in synthetic hardware round-trip button.
  It may request Touch ID; failure is not treated as success or replaced with a
  weaker path.

**Not yet implemented:** production signed app packaging, authenticated IPC,
Apple Passwords ingestion, durable encrypted storage and audit history,
protected native secret buffers, real agent delivery, constrained operation
adapters, migration, or App Store distribution.
The dashboard is a preview, not a security boundary.
Its simulated unlock is explicitly not authentication.

No real credentials are loaded, no existing vault is changed, and no services
are installed.
Do not put personal credentials into this development preview.

## Run

Requires macOS 14+ and Swift 5.9+ (Apple Command Line Tools suffice for the
synthetic preview).
No third-party package dependencies.

```sh
swift run HandrailChecks
swift run Handrail
```

For a Finder-launchable development preview, run
`bash scripts/build-preview.sh` and open `.build/Handrail Preview.app`.
Its ad-hoc signature is only for local development; it is not provisioned,
sandboxed, notarized or Store-ready.

Start a demo session, load the example, simulate a denied request, approve two
reads, and simulate three more requests.
The final request is denied.
Revoke a grant or lock the session to see denial in the review history.
Example account and domain are not real user data; nothing survives quitting
this preview.

The hardware button is separate from the demo.
Run it only when ready for a native authentication prompt.
A compiled binary is **not** evidence that provisioning, hardware use, or
cancellation handling have passed on a Mac.

The checks use a dependency-free executable runner because Command Line Tools on
the development machine do not include XCTest.
They exercise policy and envelope version rejection, not a live hardware round
trip.

## Security promise

Hardware wrapping protects cached data at rest.
It does not put API requests or plaintext credentials inside the Secure Enclave.
Giving a credential to an agent permits that agent to copy it; expiry cannot
revoke an already disclosed password or a remote login session.
Stronger damage control requires keeping credentials in the broker and offering
tightly constrained operations instead.

An unrestricted process running as the user can bypass a voluntary broker if it
can reach the credential source directly.
Preventing that requires a real process/sandbox boundary as well as broker
policy.
Review history is evidence of observed broker activity, not a complete account
of everything an agent did.

See [the implementation plan](docs/PLAN.md), [name exploration](docs/NAMING.md),
and [architecture and release gates](docs/ARCHITECTURE.md).

## Distribution and licensing

Intended model: public source, self-build option, and an inexpensive one-time
Mac App Store purchase for convenient installation and updates.
Store acceptance is not established.
MIT is the proposed license; the owner must confirm the license and copyright
attribution before public release.
No open-source license has been granted by this initial private scaffold.
