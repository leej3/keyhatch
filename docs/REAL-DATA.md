# Real-data development test

This is a local experimental vertical slice, not a production agent broker.
The original real-data test has been extended with a code-pinned local CLI
pilot; see LOCAL-PILOT.md for current scope, approval, installation and
rollback.
Existing helpers remain unchanged until an explicit selected-host cutover passes
its tests; the original vault is preserved.

## Implemented path

1. An external, user-controlled source supplies exactly one selected credential
   to `KeyhatchImport` through private stdin.
   No source-specific setup or credentials belong in this repository.
2. The importer validates hostname/account and source timestamps, preserves the
   original expiry, and creates a new Secure Enclave-wrapped encrypted file.
   It never overwrites an existing file.
   A random filename conceals account metadata while locked.
3. The app's Real credential test tab opens that file with Touch ID.
   A native session key permits repeated access for at most five hours, further
   limited by source expiry.
   The secret is never displayed.
   The payload is encrypted between operations; native cryptographic/networking
   code can retain transient copies, so deterministic memory erasure is not
   claimed.
4. A user-triggered identity check sends an exact-host HTTPS GET to
   `/api/v1/user` with Basic authentication, suitable for a Forgejo/Gitea-style
   service.
   It does not follow redirects, use a shared cookie store, or display the
   response body.
   It verifies HTTP 200 and an exact account-name match.
   This is a narrow test harness, not a required per-service integration model
   for the eventual credential broker.
5. Import/unlock/check events are retained inside the encrypted payload (latest
   200 events).
   The app persists the request intent before network access and refuses to
   start the request if that write fails.
   A later storage failure cannot undo a request already sent.
   Lock cancels in-flight networking and clears session references; it cannot
   retract a request already received.

State lives under the current user's `.local/state/keyhatch`, outside Git.
The directory is owner-only; encrypted files and cooperating-instance lock files
are owner-only.
Symbolic links, hard-linked files, broad permissions, invalid filenames,
oversized payloads, and concurrent cooperative opens are rejected.
Writes use a temporary file, fsync and an atomic rename.
Core dumps are disabled by real-data entry points.
Same-UID malicious processes remain outside this protection boundary.

## Building

```sh
swift run --scratch-path .build/keyhatch KeyhatchChecks
swift build --scratch-path .build/keyhatch --product KeyhatchImport
bash scripts/build-preview.sh
```

The importer accepts a bounded JSON object through a non-terminal stdin only:
`host`, `account`, `secret`, Unix-second `fetchedAt` and `expiresAt`, and an
empty `history` array.
Never type a real object into a shell, chat, file, or captured tool call.
Use an authorized source adapter that writes the object to an anonymous pipe.
Failed imports emit only a generic error; successful imports emit the nonsecret
encrypted-file path.
There is no raw-secret print command.

## Release blockers

See SECURITY.md.
In particular, a local successful test does not establish authenticated agent
identity, hardened deployment, independent security review, App Store
compatibility, durable rollback resistance, biometric-enrollment recovery, or
safe general-purpose credential delivery.
No bulk import, source password modification, remote rotation, or migration of
existing helpers occurs.
