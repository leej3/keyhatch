# Selective credential import and local use

Keyhatch accepts one credential you explicitly select.
Importing does not grant client access, change the source password store, or
change existing credential helpers.
The original vault remains separate.
See [LOCAL-PILOT.md](LOCAL-PILOT.md) for CLI approval, installation, and
rollback, and [SECURITY.md](../SECURITY.md) for remaining security and release
limitations.

## Import in the app

1. Lock the session and choose **Import one credential…** in the credential tab.
2. Enter the lowercase host without a scheme or path, the account, and the
   password or token you selected.
   The secret field masks its contents.
3. Set **Originally retrieved** and **Original cache expiry** to the source's
   original timestamps.
   Use **Exact source timestamps (Unix seconds)** if the source provides
   timestamps with seconds or fractional seconds.
4. Confirm that the times preserve the source lifetime, then choose
   **Encrypt and import**.
   The defaults of now and three days later are only suitable for a freshly
   retrieved credential.
   A cached credential must retain its original times; importing must not
   restart its lifetime.
   Expiry must be later than retrieval, no more than three days after retrieval,
   and still in the future.
5. Unlock the newly selected encrypted file with Touch ID.
   Approve the local client separately if you want repeated credential retrieval
   while unlocked.

The app validates the same record format as the private-pipe importer, encrypts
in memory, and creates a new file without replacing an existing file.
Its random filename conceals account metadata while locked.
Canceling an import before its save prevents a pending encryption result from
being written.

The secret field is cleared on submission or dismissal, but this is not a
promise of deterministic memory erasure: Swift strings, JSON encoding, UI
controls, and cryptographic or networking code can retain transient plaintext
copies.
Keyhatch does not write the import's plaintext to a file.
If you paste a credential, the source clipboard and any clipboard manager have
their own retention behavior; Keyhatch does not clear or control them.

## Unlock, retrieve, and check

An unlocked session lasts at most five hours, further limited by the
credential's original expiry.
Local approval permits the pinned client to retrieve the selected credential
during that period.
Other tools under your account may invoke that client.
Once disclosed, a recipient may retain or transmit its copy; locking, revoking
approval, or deleting the local file cannot retract it.

The direct-distribution CLI retains its explicit `run` workflow for supplying
the selected credential to a chosen child process.
The App Store variant rejects `run`; sandboxing does not provide equivalent
arbitrary-child execution.
The native import form is available in both variants.
The Store package does not ship the standalone private-pipe importer.

The optional Forgejo identity check asks for confirmation, then sends an
exact-host HTTPS GET to `/api/v1/user` with Basic authentication.
It refuses redirects and uses no shared cookie store or persistent response
cache.
The response body is not displayed; success requires HTTP 200 and an exact
account-name match.
This check is a narrow user-triggered diagnostic, not a requirement for every
service.

Import, unlock, approval, retrieval, and check events are retained inside the
encrypted payload, capped at the latest 200 events.
The app persists request intent before networking and refuses to start if that
write fails.
A later failure or lock cannot retract a request already received by the host.
Lock cancels in-flight networking and clears the session's references.

## Delete local data

Lock the session, select the encrypted file, choose **Delete selected file…**,
and confirm.
This removes that local encrypted credential and its history.
Another cooperating app instance holding the file prevents deletion.
Expiry alone denies access but does not automatically erase the file.

Deletion does not remove the original source credential, revoke it at the
issuing service, end remote sessions, or remove backups and recipient copies.
Revoke or rotate the credential at its issuing service if those copies must stop
working.
The storage layer retains an empty coordination lock file to preserve consistent
locking between app instances; that file contains no credential or history.

The privacy policy is available without an unlock under
**Help → Keyhatch Privacy** and in
[Resources/Privacy.md](../Resources/Privacy.md).

## Storage boundaries

Direct-distribution and development builds retain the current user's
`~/.local/state/keyhatch` storage.
The App Store variant uses `Library/Application Support/Keyhatch` inside its
macOS app container.
Only IPC transport state is placed in the shared application-group container;
credential files remain in the broker's private container.
Neither variant automatically imports or migrates the other's files.

Credential directories and encrypted files are owner-only.
Symbolic links, hard-linked files, broad permissions, invalid filenames,
oversized payloads, and concurrent cooperative opens are rejected.
Writes use a temporary file, fsync, and atomic publication.
Core dumps are disabled by real-data entry points.
These protections and the App Sandbox do not establish isolation from an
unrestricted malicious process running under the same macOS account.

## Development importer

```sh
swift run --scratch-path .build/keyhatch KeyhatchChecks
swift build --scratch-path .build/keyhatch --product KeyhatchImport
bash scripts/build-preview.sh
```

The direct/development `KeyhatchImport` accepts a bounded JSON object through a
non-terminal stdin only: `host`, `account`, `secret`, Unix-second `fetchedAt`
and `expiresAt`, and an empty `history` array.
Never type a real object into a shell, chat, file, or captured tool call.
Use an authorized source adapter that writes exactly one selected credential to
an anonymous pipe.
No source-specific setup or credentials belong in this repository.

Failed imports emit only a generic error; successful imports emit the nonsecret
encrypted-file path.
The importer resets supplied history and approval, preserves the original source
expiry, and creates a new encrypted file.
There is no general-purpose raw-secret print command; approved protocol delivery
and the direct CLI's explicit child-process handoff deliberately disclose
credentials.

## Release validation still required

Local builds and synthetic checks do not establish App Store acceptance,
successful Developer ID notarization, complete biometric lifecycle coverage,
durable rollback resistance, independent security review, or per-agent identity.
Signed distribution, provisioning, hosted privacy information, and packaged
hardware testing require their own verification.
No bulk import, source password modification, remote rotation, or migration of
existing helpers occurs.
