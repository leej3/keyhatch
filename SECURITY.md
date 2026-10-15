# Security status

Keyhatch is experimental.
Do not treat this development build as a hardened boundary against another
unrestricted process running as your macOS user.

New self-contained packages validate sealed
app/client identities instead of using a writable deployment manifest. The App Store candidate separates private credential storage from shared IPC and requests limited sandbox entitlements. Its signed runtime behavior and App Store acceptance are unverified. See [distribution and same-user tampering details](docs/DISTRIBUTION.md).

## Known limits

- IPC authenticates same-user peers by kernel audit token and pinned running
  code hash in both directions.
  Approval covers the installed CLI build, not a distinct agent, chat or model;
  any agent under that user can invoke the CLI.
  Demo client labels are still not identity.
  Source/deployment modification by an unrestricted same-user attacker remains
  outside the boundary.
- The local pilot uses hardened ad-hoc signing, not sandboxing, notarization or
  an independent audit.
  New distribution tooling supports production signing and a sandboxed Store
  candidate, but no production signing or notarization was performed here.
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
- The pilot holds one selected credential at a time and retains only the latest
  200 audit events per credential.
  Expired records cannot yet be opened in a metadata-only review mode.
  This is not a complete incident-response inventory.
- A release audit event records authorization immediately before the socket
  send; it does not prove receipt by the client.
  Once bytes have been sent, subsequent lock/revocation cannot retract them or
  undo a remote operation.

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
