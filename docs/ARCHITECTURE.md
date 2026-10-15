# Architecture and release gates

## Proposed trust boundaries

```text
Apple Passwords → user-mediated ingestion → signed credential broker
                                               │
                          Secure Enclave wraps cache encryption key
                                               │
Trusted dashboard ← sanitized events ← policy engine ← authenticated IPC
                                               │
                          constrained service adapters ← agent requests
                                               │
                              exact authorized remote service
```

The current preview implements policy decisions and hardware-envelope source,
not the arrows to Passwords, IPC or remote services.
A sandboxed app bundle and authenticated broker remain release gates.
Same-user agents with unrestricted access to Passwords or the broker's
executable/state are outside the desired containment boundary until deployment
isolates those capabilities.

## Cryptographic construction in this prototype

1. Create a Secure Enclave P-256 key-agreement key with
   `WhenUnlockedThisDeviceOnly`, `privateKeyUsage` and `biometryCurrentSet`.
2. Generate an ephemeral software P-256 key.
   ECDH against the enclave public key, followed by HKDF-SHA256 with a random
   32-byte salt and versioned context, derives a wrapping key.
3. AES-256-GCM wraps a random data key.
   A separate AES-GCM operation encrypts the payload, also authenticating the
   versioned context.
4. Store ciphertext, wrapped data key, salt, ephemeral public key and opaque
   enclave key representation.
   Never export an enclave private key.
5. Unlock reconstructs the enclave key with an LAContext, performs protected
   ECDH, unwraps the data key and authenticates/decrypts the payload.
   No fallback.

The prototype creates one envelope per seal.
Production will use a versioned vault key hierarchy and atomic storage; the
format is not yet stable.
Hardware round-trip testing is opt-in and uses ephemeral synthetic data only.

Enclave key use is biometric-protected; the five-hour session itself is broker
policy, not an enclave-enforced timer.
Once unwrapped, a session key can remain in application memory.
Swift Data/CryptoKit may copy bytes; this prototype does not claim locked-memory
storage or deterministic wiping.
Native sensitive-buffer handling must be implemented and reviewed before real
credential ingestion.

Biometric enrollment changes may render cached data inaccessible.
That is an intentional hardware policy, not a reason to overwrite keys
automatically.
Apple Passwords remains the recovery source.
No cloud backup or cross-device migration of enclave-bound ciphertext is
promised.

## What the policy does and does not enforce

Pure policy tests cover exact identifiers, non-sliding expiry, use reservations,
denial, revocation, and clock rollback.
The host must supply trusted time and authenticated identity, serialize changes,
and recheck immediately before release.
Destination/operation labels only constrain real behavior when an adapter
validates and executes them.
They cannot constrain a raw password once given to a recipient.
UI text is not a security enforcement mechanism.

Review metadata may reveal private service relationships.
Keep it local, encrypted, bounded, and sanitized.
Never log raw child output, authentication headers, secret values, request
bodies, URL query strings or error payloads.

## Apple platform findings (researched 2026-10-14)

- [Secure Enclave key protection](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
  describes hardware-protected elliptic-curve private keys, not arbitrary
  password storage inside the enclave.
- [CryptoKit key agreement](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement)
  supplies the native primitive used by this implementation.
- [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
  is required for Mac App Store distribution.
  General shell/browser integration cannot be assumed to work inside the
  sandbox.
- [Password AutoFill workflow](https://developer.apple.com/documentation/security/about-the-password-autofill-workflow)
  documents user-facing credential selection and associated-domain behavior.
  It does not establish a general unattended API for reading arbitrary Passwords
  entries.
  Feasibility must be verified in the intended app, not inferred from access to
  our own Keychain items.

Consequently, the Store build and the direct/self-build variant may require
different ingestion paths.
No App Store approval, entitlement availability or universal Passwords
integration is claimed by this repository.
