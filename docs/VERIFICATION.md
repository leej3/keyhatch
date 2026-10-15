# Verification record

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
