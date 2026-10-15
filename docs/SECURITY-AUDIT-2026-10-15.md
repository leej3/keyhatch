# Security audit — 2026-10-15

## Summary

Reviewed the complete tracked Swift application, credential core, importer, CLI,
Python/shell scripts, package configuration, and security documentation.
The starting revision was `0151d1f484276385b9feb84ea0fe4569da8ec9fa`.
Two lifetime-enforcement issues were identified: one medium-severity expiry
extension and one low-severity asynchronous request-dispatch race.
Both have been corrected in the working tree by separate subagents.
No critical or high-severity vulnerability was confirmed.

This is an agent-assisted source audit with synthetic checks, not an independent
security certification or a claim that the experimental vault is production
ready.
The security skill has no Swift-specific reference checklist; review used the
repository's trust model and primary Apple API documentation.

## Medium severity

### KH-001: Clock rollback could extend the remaining credential lifetime

**Status:** fixed.

The original `Sources/Keyhatch/RealCredentialView.swift:74-79` checked elapsed
monotonic time against five hours, but checked source expiry only against the
wall clock.
The unlock path at original lines 99-103 did not capture the remaining source
lifetime as an elapsed-time limit.

For a synthetic example, unlock at wall time 1000 with source expiry 1060.
After 70 seconds of elapsed time, adjust the wall clock to 1030.
The original predicate still permitted access, even though the 60 seconds
remaining at unlock had elapsed.
A manual or automatic clock correction after unlock can therefore extend
retrieval beyond the originally remaining cache lifetime.
This requires an already unlocked session and existing CLI approval; it is not
an authentication bypass or a capability to change the system clock.

The fix snapshots the remaining source lifetime at unlock and caps it at five
hours.
Both wall time and elapsed continuous time must remain within that bound.
Approval checks use the later of wall time and elapsed time projected from
unlock, and approval is rechecked after the audit write before release.
The implementation uses Swift's `ContinuousClock`, which continues advancing
during sleep, as documented by
[Apple](https://developer.apple.com/documentation/swift/continuousclock).

The new implementation is in `Sources/KeyhatchCore/SessionLifetime.swift:12` and
`:33`, with integration in `Sources/Keyhatch/RealCredentialView.swift:76`,
`:100`, and `:190`.
Synthetic regression checks cover the rollback example and expiry boundaries.

This is an in-session bound.
It does not establish trusted persistent time across a new unlock, process
restart, or rollback of encrypted storage.
Those remain outside the documented rollback-resistance guarantees.

## Low severity

### KH-002: A queued identity check could dispatch after session expiry

**Status:** fixed.

The original `Sources/Keyhatch/RealCredentialView.swift:228-232` started an
asynchronous `URLSession.bytes(for:)` request before checking the task's
generation and session lifetime.
If scheduling delayed that task beyond expiry, the credential-bearing HTTPS
request could begin before the timer locked the session.
The check after receiving a response was too late to prevent dispatch.

The fix at `Sources/Keyhatch/RealCredentialView.swift:244` checks generation
first, then current session validity immediately before starting the request.
An expired current session locks; a stale task returns without changing a
replacement session.
The request remains limited to the explicitly selected HTTPS host, so the impact
is late use of an already authorized credential, not cross-host disclosure.

Verification includes source/control-flow review and app compilation.
There is no automated scheduling-race test of the private SwiftUI model; the
audit did not exercise live credential-bearing network requests.
The guard cannot retract a request already dispatched or control when a remote
server receives it.

## Other reviewed boundaries

- Credential files use owner-only permissions, descriptor-relative access,
  final-component link rejection, bounded reads, authenticated payloads, and
  atomic writes.
  Imports discard supplied approvals and preserve source expiry.
- The envelope uses CryptoKit P-256 agreement, HKDF-SHA256, and AES-GCM;
  hardware unwrap has no software fallback.
  The design matches the roles described in Apple's
  [Secure Enclave guidance](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave).
  Biometric enforcement was not exercised during this audit.
- IPC validates kernel peer identity and pinned running code in both directions,
  then rechecks the client before release.
  Apple's
  [dynamic code-validation API](https://developer.apple.com/documentation/security/seccodecheckvalidity(_:_:_:))
  describes the running-code validation used here.
- CLI Git retrieval checks protocol, host, account, duplicate fields, and output
  delimiters.
  `run` deliberately hands credentials to the requested child; that child can
  retain or disclose them.
- HTTPS identity checking disables redirects and shared credential/cookie
  stores, bounds the response, and persists request intent before dispatch.
- `Package.swift` declares no external package dependencies.
  This audit did not scan the installed operating system or Swift toolchain for
  vulnerabilities.

No additional vulnerability was confirmed in these areas within the stated
threat boundary.
This does not prove absence of vulnerabilities.

## Verification and limits

The original core checks passed before changes.
Authenticated malformed-frame coverage was added because the existing
malformed-client test rejected its sender before reaching the frame parser.
The added cases cover malformed JSON,
zero/oversized lengths, truncated headers/bodies, and stalled headers/bodies.
Each checks actual peer closure and subsequent broker usability.

Final verification passed:

- `swift build --scratch-path .build/keyhatch`: all products compiled.
  Only existing Command Line Tools missing optional framework/library search
  path warnings were emitted.
- `swift run --skip-build --scratch-path .build/keyhatch KeyhatchChecks`: all 18 policy checks, existing credential/client
  groups, and four new session lifetime groups passed.
- `python3 scripts/test-ipc.py`: existing mutual authentication/socket recovery
  checks and all eight new authenticated invalid-frame scenarios passed.
- Snapper's pre-commit documentation hook and `git diff --check` passed.

All audit inputs were synthetic.
No real credentials, password stores, biometric prompts, live authentication,
deployment installation, or external publication were used.
The existing limits in `SECURITY.md` remain: unrestricted same-user tampering,
plaintext copies in native memory and recipients, ad-hoc deployment, and absence
of durable rollback protection.
