# Local pilot, with rollback

## Scope

This milestone supports the one selected, unlocked credential through an
authenticated local CLI.
It is not a general multi-account daemon yet.
Other credentials remain on the existing vault; do not switch every helper
globally.
No cloud service, publication, or App Store enrollment is needed for this pilot.

## Trust and approval

The app owns a user-private Unix socket.
Both peers check the effective UID and the kernel-supplied audit token, then
validate the peer's running code against an exact pinned CDHash using
Security.framework.
The app pins the CLI in its signed bundle; the CLI pins the app in a private
deployment manifest.
User input cannot provide a claimed agent identity or request an unlock,
approval, refresh, or grant extension over IPC.

The deployment uses hardened, ad-hoc signatures: useful local identity pins, not
a notarized product or protection against a user replacing their own deployment.
All agents under the same macOS user may invoke the genuine CLI.
An approval applies to that CLI build, not to a particular chat or model.

The human approves the selected credential in the native app.
That approval is stored inside its encrypted payload until the original cache
expiry; it does not expire on each use or lock.
A five-hour native unlock is still required.
A new CLI code hash requires fresh approval.
Revocation persists before future retrieval is denied.
If audit or state writes fail, the app locks and denies release.
Already disclosed credentials and remote sessions are not revoked.

## Commands

```sh
keyhatch status
keyhatch check example.org account
keyhatch run example.org account --password-env SERVICE_TOKEN -- command args
keyhatch lock
```

Unlock, renew and approvals are native UI actions.
The current pilot serves only the selected unlocked file.
The CLI never automatically fetches a password, opens an approval window, or
falls back to a different vault.
`--cached-only` is accepted for check/run compatibility; all CLI retrieval is
cache-only.

Git configuration uses an exact-host helper:

```text
keyhatch git --host example.org --username account get
```

Git appends `get`, `store` or `erase` itself in normal usage.
`store`/`erase` are no-ops.
`get` refuses terminal output and rejects a mismatched protocol, host, account
or duplicate field.
Do not run a valid `get` directly in captured tool output: Git consumes its
secret-bearing stdout privately.

`run` injects the credential into only the requested child environment, executes
without a shell and preserves the child's exit status.
The child can disclose or retain the secret: this is deliberate credential
handoff, not a sandbox or output scrubber.
Do not use commands that print the credential environment.
Multiple-credential runs are not yet supported.

## Installation and updates

```sh
swift run --scratch-path .build/keyhatch KeyhatchChecks
python3 scripts/test-ipc.py
bash scripts/install-local.sh
```

Installation creates a fresh owner-private release under
`~/.local/share/keyhatch/releases`, a `current` symlink and
`~/.local/bin/keyhatch`.
Previous releases are retained.
It does not change Git settings, existing credential helpers, the original
vault, or encrypted credential files.

Close the old app before opening the installed release.
A second broker cannot replace an active socket.
After closing a duplicate, click Refresh files in the remaining app.
Updates intentionally reject a mixed-version app and CLI; open the installed app
from the current release and approve its new CLI build.

## Verification before cutover

- Confirm locked and unapproved requests fail with no fallback.
- With explicit approval, run the opt-in `scripts/live-smoke.py` inside
  `keyhatch run`, supplying CLI path and selected hostname as arguments.
  It verifies private run delivery, repeated checks, Git credential fill and a
  read-only `/api/v1/user` authentication check.
  No credential value is printed.
- Revoke and verify denial.
  Approve again only with the user's permission.
- Lock and verify denial; restart and verify it starts locked.
  Unlock to verify encrypted approval/history survive without resetting source
  expiry.
- Exercise cancellation and expiry with synthetic data; never change production
  clocks or expiry constants merely to speed up a test.
- Only then route the selected host's existing helper to Keyhatch and test it
  through that actual helper.
  Other hosts must continue on their previous path.

## Rollback

Keep a private backup of the original selected-host helper before changing it.
Restore that helper or remove the explicit pilot routing to return that host to
the old vault.
Do not silently fall back on errors: rollback is an explicit operator action.
The old vault and its cache/key are not deleted.

To roll back a Keyhatch deployment, close the app, restore `current` to the
previous retained release, and open that release's app.
Exact code pins and approvals may require reapproval.
Never overwrite or regenerate enclave keys as a recovery technique.
Cache loss can instead be recovered by an explicitly authorized fetch from the
durable password source.
