# Security status

Keyhatch is experimental.
Do not treat this development build as a hardened boundary against another
unrestricted process running as your macOS user.

## Known limits

- No authenticated agent IPC is implemented.
  Demo client labels are not proof of identity.
  Do not enable a credential socket based on those labels.
- The development app is ad-hoc signed, not sandboxed/notarized or independently
  audited.
  Same-user code can modify the executable or state.
  Hardware wrapping does not solve software tampering while unlocked.
- AES keys and transient plaintext exist in application memory.
  Swift and system networking can copy them; deterministic wiping and swap
  exclusion are not established.
  Core dumps are disabled by the real-data entry points.
- Cache/grant expiry stops future retrieval. Copies already given to a process or server-side sessions require separate revocation/rotation.
- Local encrypted audit events are not tamper-proof: equivalent-authority code
  can delete or roll back entire files.
  No trusted monotonic persistent counter or cross-device recovery is provided.
- Biometric enrollment changes or loss of enclave-bound key material can make
  the cache inaccessible.
  Never silently regenerate a key over existing data.
- App Store integration and direct Apple Passwords ingestion remain unverified.

## Reporting

There is not yet a public repository or private disclosure endpoint.
Before public release, maintainers must publish a monitored private security
contact.
Until then, report suspected issues privately to the maintainer through an
existing trusted channel.
Describe affected versions and a synthetic reproduction.
Never include live credentials or personal vault files.

Do not publish an exploit against a real account to demonstrate a bug.
A read-only authentication check confirms that a credential works, not that its
service permissions are narrow or safe.
