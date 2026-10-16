# Non-biometric lifecycle review

Reviewed 2026-10-15 against the current source and synthetic checks.
This is a separate agent review, not an external security audit or a test of
hardware sleep, Touch ID, reboot, or an App Store installation.
No live credential file was opened and no installed app was changed by this
review.

## Scope and conclusions

The production credential model uses `SessionLifetime` to cap an authenticated
session at the smaller of five hours and the source lifetime remaining when it
was unlocked.
Every retrieval evaluates both wall time and process-relative continuous time.
Its approval check uses the later elapsed value, and retrieval rechecks lifetime
and approval after the encrypted audit write, immediately before returning the
response.
The synthetic `AccessPolicy` demo is a separate policy implementation; its tests
do not by themselves establish production broker behavior.

The production model initializes locked, retains the active key and lifetime
only in memory, and clears both on explicit lock.
Lock also changes its generation token and cancels its active network session.
Asynchronous unlock/import results must still match their initiating generation
before changing state.
Window disappearance and app termination invoke lock.
These are source-review observations; this pass did not exercise those native
events with an unlocked credential.

Persisted broker approval authorizes one exact client code hash and cannot
extend source expiry.
A changed client executable does not inherit an old approval.
Reapproving a replacement hash rejects the old hash in that updated record.
This does not prevent an unrestricted same-user attacker from restoring an older
encrypted file, and approval identifies a client build rather than an individual
agent or process invocation.

No additional production lifecycle defect was demonstrated in this review.
The changes add deterministic coverage rather than changing clock or unlock
behavior.

## Checks run

Command:

```sh
swift run --scratch-path .build/lifecycle-review KeyhatchChecks
```

The final run passed all 18 policy checks and the credential, lifetime, client,
deployment, storage and bundle-trust groups.
The first run observed the parallel review's new FIFO regression before its
nonblocking-open fix had been rebuilt; the final run rebuilt that fix and
passed.
The lifecycle additions in `Tests/KeyhatchCoreTests/SessionLifetimeChecks.swift`
cover:

- A 49-case matrix of wall/continuous elapsed values around approval and source
  expiry, including simulated sleep and partial wall-clock rollback.
- Separate approval and source-expiry checks before and after a simulated
  delayed release; permission before the delay does not imply permission after
  it.
- Session renewal one second before original source expiry, with either clock
  independently reaching expiry.
  Renewal does not restart the original cache duration.
- A reset continuous clock rejects an old session; a newly constructed session
  uses its new origin while preserving absolute source expiry.
- A JSON round trip of persisted approval preserves exact-build binding;
  replacement approval rejects the previous build and still expires.
- A fresh synthetic policy with a restored grant remains locked until session
  authentication is explicitly modeled, and explicit lock denies it again.

Existing tests retain exact boundary, invalid/nonfinite clock, five-hour cap,
revocation, limited-use and credential-retention coverage.
The tests inject elapsed time; they do not change the host clock, sleep the Mac,
invoke authentication or exercise a native app upgrade.

## Remaining verification and limits

- Hardware
  sleep/wake with a genuinely unlocked synthetic credential, native session expiry, and unlock/retrieval
  after the installed upgrade remain deferred.
  Continuous-time arithmetic tests do not prove event delivery, UI cleanup or
  native authentication behavior on every supported macOS version.
- Sleep does not itself end an otherwise valid five-hour session.
  There is no explicit screen-lock or sleep notification that immediately clears
  the active key.
  Requests still enforce lifetime independently of the UI timer.
  Do not describe this as automatic lock-on-sleep or screen-lock protection.
- A new process starts locked, but this test pass did not reboot the machine.
  Continuous timestamps are not persisted, so the lifetime guarantee is within
  an authenticated session.
  A wall-clock rollback across a fresh
  unlock/restart or whole-file rollback is not defeated by a trusted persistent clock/counter.
- Approval pin checks model the hash changing; they do not validate Store
  re-signing, downloaded-package identity, or a real credential migration.
- Once a credential has been delivered, lock, expiry, upgrade or revocation
  cannot retract a recipient's retained copy or end a remote session.

See [the verification record](VERIFICATION.md) for previously completed native
tests and [distribution requirements](DISTRIBUTION.md) for release gates.
