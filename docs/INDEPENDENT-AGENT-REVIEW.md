# Independent agent security review

Reviewed on 2026-10-15, starting at commit
`5712df0c8a4cf89bec545142a06dd8d6555fb623`.
This was a separate agent's source review, independent of the implementation
agents' conclusions.
It is not an external human audit, security certification, penetration test of
Apple's delivery infrastructure, or App Store approval.

## Result

One low-severity local availability issue was reproduced and corrected.
No additional confidentiality or authorization bypass was confirmed within the
documented threat boundary.
That conclusion is limited to the reviewed source and synthetic checks; it does
not establish absence of vulnerabilities.

### KH-003: FIFO credential files blocked before validation

**Severity:** low.
**Status:** fixed in this review's changes.

`CredentialFiles.read` opened the record with `O_RDONLY` before checking its
type.
A same-user process able to modify the record directory could create a FIFO
named with a valid UUID and `.keyhatch` suffix.
Opening that path waited indefinitely for a writer, so execution never reached
the regular-file check.
Unlock, deletion, or an audit update could consequently block the application's
main actor.
An update stall could also prevent the UI from processing Lock.
This does not grant retrieval: the stalled request has not passed its final
release check or sent a secret.

The relevant path is
[`CredentialFile.swift`](../Sources/KeyhatchCore/CredentialFile.swift),
`CredentialFiles.read`, lines 91–108 after the fix.
Calls occur in `RealCredentialModel.unlock` and
`CredentialFiles.update`/`remove`.
The issue requires write access to the credential directory.
An unrestricted same-user attacker already has other denial-of-service
capabilities outside the documented protection boundary; a sandboxed client
should not have access to the Store broker's private directory.

The open now includes `O_NONBLOCK`; `fstat` then rejects non-regular files.
Regular-file semantics and permissions are unchanged.
The regression in
[`CredentialChecks.swift`](../Tests/KeyhatchCoreTests/CredentialChecks.swift)
creates a private synthetic FIFO without a writer and requires rejection within
five seconds.
Before the fix, the actual core runner failed at its timeout with
`Credential read blocked opening a FIFO`.
After the fix, the regression and all core checks passed.

## Reviewed boundaries

| Boundary | Evidence and assessment |
| --- | --- |
| IPC identity | `LocalIPC.authenticate` checks same UID, the kernel audit token, and strict running-code CDHash validity. Both sides authenticate; the server rechecks identity before handling a release. No request-supplied identity is trusted. |
| Framing and availability | `LocalIPC.readFrame` and `writeFrame` bound frames at 256 KiB and impose socket/deadline limits. A client may delay the serial server or main actor for a bounded interval; there is no remote listener. |
| Sealed deployment | `BundledDeployment.validate` verifies the containing app and client, nested code and architectures, expected locations, identity agreement, and the publisher requirement. A production client copied outside the app cannot fall back to a mutable legacy manifest. Development mode requires ad-hoc signatures. |
| Storage separation | `DeploymentPaths.credentialRoot` selects private broker storage for the Store channel; `ipcRoot` requires the sandbox and configured group entitlement. Only transport state is shared. Missing Store configuration fails closed rather than falling back to legacy storage. |
| Credential files | Descriptor-relative access rejects final-component symlinks, unexpected ownership/mode, hard links, oversized data, and now FIFOs. Writes use a private temporary file, atomic replacement and synchronization. Cooperating sessions hold a file lock. |
| Envelope and lifetime | `EnclaveVault` uses hardware-only Secure Enclave agreement, biometric-current-set access control, HKDF and authenticated AES-GCM. `SessionLifetime` bounds an unlocked session with wall and continuous elapsed time. `RealCredentialModel.handle` rechecks authorization after the encrypted audit write. |
| Client scope | `ClientProtocol.matchesGit` checks HTTPS, exact host/account, duplicates and input bounds. The Store CLI rejects `run`; direct `run` intentionally releases to a chosen child process. Approval identifies the installed client build, not its invoking agent. |
| Release validation | `validate-release.py` inspects each Mach-O slice, checks strict signatures, publisher identity, runtime flags, entitlement restrictions, profile identity/expiry and signer membership. Static archive checks are explicitly distinct from running the embedded client. |
| Update boundary | Production trust derives from the sealed app; code-hash changes require renewed approval. `install-local.sh` retains prior builds and switches the legacy deployment symlink, but is a local development installer, not an authenticated production updater. No secure automatic update service was established by this review. |

## Verification performed in this review

- Ran `swift run --scratch-path .build/independent-review KeyhatchChecks` before
  and after the FIFO fix.
  The added regression reproduced the old failure and passed after correction.
  The after-fix run passed the policy, payload, credential, session, client,
  storage and bundled-deployment groups, including concurrently added lifecycle
  checks.
- Reviewed the Swift core, real credential model, importer, client, native
  import view, direct package builder, preview/local installer and release
  validator.
  Prior audit documentation was consulted for the stated boundary, not treated
  as proof of current behavior.
- `git diff --check` passed for these changes.

No real credentials, biometric prompts, live installation changes, remote
credential requests or Apple uploads were used.
Signed runtime and sandbox evidence from earlier work remains separately
recorded in [`VERIFICATION.md`](VERIFICATION.md); this review did not repeat
that evidence.

## Limits that remain design or release decisions

Recipients can keep disclosed secrets; local lock, expiry and revocation cannot
erase those copies or revoke remote sessions.
Any process under the user can invoke an approved CLI, so approval is not agent
identity isolation.

Direct distribution does not isolate unrestricted same-user access to mutable
files.
The current wrapped-key envelope is not a broker-only Data Protection Keychain
record.
Secure Enclave protection must not be described as per-app authorization
independent of file access and the biometric operation.
Adding that binding would require a deliberate format/migration and recovery
design.

Encrypted files and their history can be deleted or rolled back by an actor with
sufficient filesystem authority.
There is no persistent trusted clock or rollback counter across restarts.
Plaintext and AES keys exist in process memory; deterministic wiping, swap
exclusion and protection against compromised trusted code are not established.

Actual biometric behavior, physical
sleep/resume, supported macOS and Intel runtime coverage, and Store-delivered re-signing behavior remain separate test gates. Public release also requires the privacy/support
and distribution work listed in [`DISTRIBUTION.md`](DISTRIBUTION.md), and should
receive an external security review before claims of a hardened credential
vault.
