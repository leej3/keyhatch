# Keyhatch

<img src="docs/images/keyhatch.svg" alt="Keyhatch monogram" width="128">

Prioritizing practicality over perfection.

Keyhatch is a proposed open-source macOS credential broker.
Apple Passwords remains the source of truth.
Approve a few credentials once and let your agents retrieve them repeatedly
within a bounded window, rather than exposing your entire password store or
approving every use.
A visible activity feed and review dashboard show which credentials have been
loaded and requested.
No hosted vault or subscription service is part of the proposed design.

## Status: development foundation, not a production vault

**Real-data development path:** the app now has a separate real-credential tab
and private-pipe importer, encrypted persistence, Touch ID unlock, encrypted
review history, and a user-triggered read-only HTTPS identity check.
See [REAL-DATA.md](docs/REAL-DATA.md) and [known security limits](SECURITY.md).
The synthetic policy dashboard remains separate.
A local pilot now provides mutually code-pinned IPC, explicit per-credential CLI
approval, `run`, `check`, `lock`, and a host-scoped Git helper.
See [LOCAL-PILOT.md](docs/LOCAL-PILOT.md).

**Distribution work:** self-contained
development/direct packages now validate their sealed embedded client, and a separate Xcode App Store candidate adds sandbox entitlements, private broker storage, and App Group IPC. Native selective import/deletion
and Help → Keyhatch Privacy are available.
The Store client rejects arbitrary-command `run`; direct builds retain it.
Signed Store runtime testing, full Xcode archiving, production provisioning, and
review remain release gates.
See [distribution instructions and limits](docs/DISTRIBUTION.md).

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

**Not yet implemented:** production provisioning/notarization, direct Apple
Passwords integration in the app, protected native secret buffers, multi-account
unlocked sessions, constrained operation adapters, or App Store distribution.
The synthetic dashboard is not a security boundary; real CLI approval is
separate and stored inside the encrypted credential record.

Real credentials are loaded only through an explicit selective import; no bulk
source access or automatic import occurs.
No existing vault is changed and no background services are installed.
Use only a deliberately selected credential whose exposure you accept under the
documented experimental-build limitations.

## Run

Requires macOS 14+ and Swift 5.9+ (Apple Command Line Tools suffice for the
synthetic preview).
No third-party package dependencies.

```sh
swift run --scratch-path .build/keyhatch KeyhatchChecks
python3 scripts/test-ipc.py
bash scripts/install-local.sh
```

For a Finder-launchable development preview, run
`bash scripts/build-preview.sh` and open `.build/Keyhatch Preview.app`.
Its ad-hoc signature is only for local development; it is not provisioned,
sandboxed, notarized or Store-ready.

Start a demo session, load the example, simulate a denied request, and choose
“Approve for 3 days.”
Repeated requests now succeed without another approval.
The five-hour session still gates access, independently of the three-day grant.
Revoke a grant or lock the session to see denial in the review history.
Example account and domain are not real user data; nothing survives quitting
this preview.

The hardware button is separate from the demo.
Run it only when ready for a native authentication prompt.
A compiled binary is **not** evidence that provisioning, hardware use, or
cancellation handling have passed on a Mac.

In the real-data tab, unlocking the selected encrypted file is independent of
the synthetic demo and reads actual imported data.
Lock before closing the app; the app also clears session references on view
disappearance and termination.

The checks use a dependency-free executable runner because Command Line Tools on
the development machine do not include XCTest.
They exercise policy, encrypted storage and protocol validation.
Separate-process IPC checks exercise real kernel peer authentication with
synthetic data.
Live credential and biometric tests remain explicit opt-in operations.

## Security promise

Hardware wrapping protects cached data at rest.
It does not put API requests or plaintext credentials inside the Secure Enclave.
Giving a credential to an agent permits that agent to copy it; expiry cannot
revoke an already disclosed password or a remote login session.
The practical goal is to limit which credentials are disclosed, not require
bespoke integrations with every service.
The exposure set includes credentials previously handed out and retained by a
recipient, not only currently unexpired cache entries.
Per-service operation mediation is a possible future feature, not an MVP
requirement or the default workflow.

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
Keyhatch source is licensed under [MPL-2.0](LICENSE).
Contributions use the same license, with no copyright assignment or broad
relicensing CLA.
See [CONTRIBUTING.md](CONTRIBUTING.md).
Source availability and notice obligations must be met for paid binaries too.
App Store approval is not established.

Unless a file states otherwise, original source, tests, scripts, configuration
and project documentation in this repository are covered by MPL-2.0.
License texts and any separately identified third-party material retain their
own terms.
